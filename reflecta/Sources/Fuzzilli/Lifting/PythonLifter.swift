// Copyright 2019 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation

/// Lifts a FuzzIL program to JavaScript.
public class PythonLifter: Lifter {
    /// Prefix and suffix to surround the emitted code in
    private let prefix: String
    private let suffix: String

    /// The version of the ECMAScript standard that this lifter generates code for.
    let version: ECMAScriptVersion = .es6

    /// Counter to assist the lifter in detecting nested CodeStrings
    private var codeStringNestingLevel = 0

    public init(prefix: String = "",
                suffix: String = "") {
        self.prefix = prefix
        self.suffix = suffix
    }

    public func lift(_ program: Program, withOptions options: LiftingOptions) -> String {
        // Perform some analysis on the program, for example to determine variable uses
        // var needToSupportExploration = false
        // var needToSupportProbing = false
        var analyzer = VariableAnalyzer(for: program)
        for instr in program.code {
            analyzer.analyze(instr)
        }
        analyzer.finishAnalysis()

        var w = JavaScriptWriter(analyzer: analyzer, version: version, stripComments: !options.contains(.includeComments), includeLineNumbers: options.contains(.includeLineNumbers))

        if options.contains(.includeComments), let header = program.comments.at(.header) {
            w.emitComment(header)
        }

        w.emitBlock(prefix)


        for instr in program.code {
            if options.contains(.includeComments), let comment = program.comments.at(.instruction(instr.index)) {
                w.emitComment(comment)
            }

            switch instr.op.opcode {
            case .loadInteger(let op):
                w.assign(NumberLiteral.new(String(op.value)), to: instr.output)

            case .loadBigInt(let op):
                w.assign(NumberLiteral.new(String(op.value)/* + "r"*/), to: instr.output)

            case .loadFloat(let op):
                let expr: Expression
                if op.value.isNaN {
                    expr = Identifier.new("float('nan')")
                } else if op.value.isEqual(to: -Double.infinity) {
                    expr = UnaryExpression.new("-float('inf')")
                } else if op.value.isEqual(to: Double.infinity) {
                    expr = Identifier.new("float('inf')")
                } else {
                    expr = NumberLiteral.new(String(op.value))
                }
                w.assign(expr, to: instr.output)

            case .loadString(let op):
                w.assign(StringLiteral.new("\"\(op.value)\""), to: instr.output)

            case .loadRegExp(let op):
                w.assign(StringLiteral.new("\"\(op.pattern)\""), to: instr.output)

            case .loadBoolean(let op):
                w.assign(Literal.new(op.value ? "True" : "False"), to: instr.output)

            case .loadUndefined:
                w.assign(Literal.new("None"), to: instr.output)

            case .loadNull:
                w.assign(Literal.new("None"), to: instr.output)

            case .loadThis:
                w.assign(Literal.new("self"), to: instr.output)

            case .createArray:
                // When creating arrays, treat undefined elements as holes. This also relies on literals always being inlined.
                var elems = instr.inputs.map({ w.retrieve(expressionFor: $0).text }).map({ $0 == "undefined" ? "" : $0 }).joined(separator: ",")
                if elems.last == "," || (instr.inputs.count == 1 && elems == "") {
                    // If the last element is supposed to be a hole, we need one additional comma
                    elems += ","
                }
                w.assign(ArrayLiteral.new("[\(elems)]"), to: instr.output)

            case .loadBuiltin(let op):
                w.assign(Identifier.new(op.builtinName), to: instr.output)

            case .getProperty(let op):
                    let obj = w.retrieve(expressionFor: instr.input(0))
                    let expr = MemberExpression.new() + obj + "." + op.propertyName
                    w.assign(expr, to: instr.output)

            case .setProperty(let op):
                // For aesthetic reasons, we don't want to inline the lhs of an assignment, so force it to be stored in a variable.
                let obj = w.retrieve(identifierFor: instr.input(0))
                let prop = op.propertyName
                let PROPERTY = MemberExpression.new() + obj + "." + prop
                let VALUE = w.retrieve(expressionFor: instr.input(1))
                w.emit("\(PROPERTY) = \(VALUE);")

            case .getElement(let op):
                let obj = w.retrieve(expressionFor: instr.input(0))
                let expr = MemberExpression.new() + obj + "[" + op.index + "]"
                w.assign(expr, to: instr.output)

            case .setElement(let op):
                // For aesthetic reasons, we don't want to inline the lhs of an assignment, so force it to be stored in a variable.
                let obj = w.retrieve(identifierFor: instr.input(0))
                let ELEMENT = MemberExpression.new() + obj + "[" + op.index + "]"
                let VALUE = w.retrieve(expressionFor: instr.input(1))
                w.emit("\(ELEMENT) = \(VALUE);")

            case .beginPlainFunction:
                liftFunctionDefinitionBegin(instr, keyword: "def", using: &w)
                w.emit("pass")

            case .endPlainFunction(_):
                w.leaveCurrentBlock()

            case .return:
                let VALUE = w.retrieve(expressionFor: instr.input(0))
                w.emit("return \(VALUE);")

            case .callFunction:
                // Avoid inlining of the function expression. This is mostly for aesthetic reasons, but is also required if the expression for
                // the function is a MemberExpression since it would otherwise be interpreted as a method call, not a function call.
                let f = w.retrieve(identifierFor: instr.input(0))
                let args = instr.variadicInputs.map({ w.retrieve(expressionFor: $0) })
                let expr = CallExpression.new() + f + "(" + liftCallArguments(args) + ")"
                w.assign(expr, to: instr.output)

            case .construct:
                let f = w.retrieve(expressionFor: instr.input(0))
                let args = instr.variadicInputs.map({ w.retrieve(expressionFor: $0) })
                let EXPR = NewExpression.new() + f + "(" + liftCallArguments(args) + ")"
                // For aesthetic reasons we disallow inlining "new" expressions and always assign their result to a new variable.
                let V = w.declare(instr.output)
                w.emit("\(V) = \(EXPR);")

            case .callMethod(let op):
                let obj = w.retrieve(expressionFor: instr.input(0))
                let method = MemberExpression.new() + obj + "." + op.methodName
                let args = instr.variadicInputs.map({ w.retrieve(expressionFor: $0) })
                let expr = CallExpression.new() + method + "(" + liftCallArguments(args) + ")"
                w.assign(expr, to: instr.output)

            case .unaryOperation(let op):
                let input = w.retrieve(expressionFor: instr.input(0))
                let expr: Expression
                if op.op.isPostfix {
                    expr = UnaryExpression.new() + input + op.op.token
                } else {
                    expr = UnaryExpression.new() + op.op.token + input
                }
                w.assign(expr, to: instr.output)

            case .binaryOperation(let op):
                let lhs = w.retrieve(expressionFor: instr.input(0))
                let rhs = w.retrieve(expressionFor: instr.input(1))
                let expr = BinaryExpression.new() + lhs + " " + op.op.token + " " + rhs
                w.assign(expr, to: instr.output)

            case .ternaryOperation:
                let cond = w.retrieve(expressionFor: instr.input(0))
                let value1 = w.retrieve(expressionFor: instr.input(1))
                let value2 = w.retrieve(expressionFor: instr.input(2))
                let expr = TernaryExpression.new() + value1 + " if " + cond + " else " + value2
                w.assign(expr, to: instr.output)

            case .reassign:
                let DEST = w.retrieve(expressionFor: instr.input(0))
                let VALUE = w.retrieve(expressionFor: instr.input(1))
                assert(DEST.type === Identifier)
                w.emit("\(DEST) = \(VALUE);")

            case .update(let op):
                let DEST = w.retrieve(expressionFor: instr.input(0))
                let VALUE = w.retrieve(expressionFor: instr.input(1))
                assert(DEST.type === Identifier)
                w.emit("\(DEST) \(op.op.token)= \(VALUE);")

            case .dup:
                let V = w.declare(instr.output)
                let VALUE = w.retrieve(expressionFor: instr.input(0))
                w.emit("\(V) = \(VALUE);")

            case .compare(let op):
                let lhs = w.retrieve(expressionFor: instr.input(0))
                let rhs = w.retrieve(expressionFor: instr.input(1))
                let expr = BinaryExpression.new() + lhs + " " + op.op.token + " " + rhs
                w.assign(expr, to: instr.output)

            case .eval(let op):
                // Woraround until Strings implement the CVarArg protocol in the linux Foundation library...
                // TODO can make this permanent, but then use different placeholder pattern
                var EXPR = op.code
                for v in instr.inputs {
                    let range = EXPR.range(of: "%@")!
                    EXPR.replaceSubrange(range, with: w.retrieve(expressionFor: v).text)
                }
                w.emit("\(EXPR);")

            case .nop:
                w.emit("pass")
                break

            case .beginForLoop:
                let I = w.declare(instr.innerOutput)
                let INITIAL = w.retrieve(expressionFor: instr.input(0))
                let END = w.retrieve(expressionFor: instr.input(1))
                // This is a bit of a hack. Instead, maybe we should have a way of simplifying expressions through some pattern matching code?
                let step = w.retrieve(expressionFor: instr.input(2))
                w.emit("for \(I) in range(\(INITIAL), \(END), \(step)): ")
                w.enterNewBlock()
                w.emit("pass")

            case .endForLoop:
                w.leaveCurrentBlock()

            case .beginTry:
                w.emit("try:")
                w.enterNewBlock()

            case .beginCatch:
                w.leaveCurrentBlock()
                w.emit("except:")
                w.enterNewBlock()
                w.emit("pass")

            case .beginFinally:
                w.leaveCurrentBlock()
                w.emit("finally:")
                w.enterNewBlock()

            case .endTryCatchFinally:
                w.leaveCurrentBlock()

            case .throwException:
                let VALUE = w.retrieve(expressionFor: instr.input(0))
                w.emit("raise \(VALUE)")

            case .print:
                let VALUE = w.retrieve(expressionFor: instr.input(0))
                w.emit("Reflecta.print(\(VALUE))")

            default:
                fatalError("Unimplemented instruction lifter: \(instr.op.opcode)")
            }
        }

        // if needToSupportProbing {
        //     w.emitBlock(JavaScriptProbeHelper.suffixCode)
        // }

        if options.contains(.includeComments), let footer = program.comments.at(.footer) {
            w.emitComment(footer)
        }

        w.emitBlock(suffix)

        return w.code
    }

    private func liftParameters(_ parameters: Parameters, as variables: [String]) -> String {
        assert(parameters.count == variables.count)
        var paramList = [String]()
        for v in variables {
            if parameters.hasRestParameter && v == variables.last {
                paramList.append("..." + v)
            } else {
                paramList.append(v)
            }
        }
        return paramList.joined(separator: ", ")
    }

    private func liftFunctionDefinitionBegin(_ instr: Instruction, keyword FUNCTION: String, using w: inout JavaScriptWriter) {
        // Function are lifted as `function f3(a4, a5, a6) { ...`.
        // This will produce functions with a recognizable .name property, which the JavaScriptExploreHelper code makes use of (see shouldTreatAsConstructor).
        guard let op = instr.op as? BeginAnyFunction else {
            fatalError("Invalid operation passed to liftFunctionDefinitionBegin")
        }
        let NAME = w.declare(instr.output, as: "f\(instr.output.number)")
        let vars = w.declareAll(instr.innerOutputs, usePrefix: "a")
        let PARAMS = liftParameters(op.parameters, as: vars)
        w.emit("\(FUNCTION) \(NAME)(\(PARAMS)):")
        w.enterNewBlock()

    }

    private func liftCallArguments(_ args: [Expression], spreading spreads: [Bool] = []) -> String {
        var arguments = [String]()
        for (i, a) in args.enumerated() {
            if spreads.count > i && spreads[i] {
                let expr = SpreadExpression.new() + "..." + a
                arguments.append(expr.text)
            } else {
                arguments.append(a.text)
            }
        }
        return arguments.joined(separator: ", ")
    }

    private func liftPropertyDescriptor(flags: PropertyFlags, type: PropertyType, values: [Expression]) -> String {
        var parts = [String]()
        if flags.contains(.writable) {
            parts.append("writable: true")
        }
        if flags.contains(.configurable) {
            parts.append("configurable: true")
        }
        if flags.contains(.enumerable) {
            parts.append("enumerable: true")
        }
        switch type {
        case .value:
            parts.append("value: \(values[0])")
        case .getter:
            parts.append("get: \(values[0])")
        case .setter:
            parts.append("set: \(values[0])")
        case .getterSetter:
            parts.append("get: \(values[0])")
            parts.append("set: \(values[1])")
        }
        return "{ \(parts.joined(separator: ", ")) }"
    }

    private func liftArrayDestructPattern(indices: [Int64], outputs: [String], hasRestElement: Bool) -> String {
        assert(indices.count == outputs.count)

        var arrayPattern = ""
        var lastIndex = 0
        for (index64, output) in zip(indices, outputs) {
            let index = Int(index64)
            let skipped = index - lastIndex
            lastIndex = index
            let dots = index == indices.last! && hasRestElement ? "..." : ""
            arrayPattern += String(repeating: ",", count: skipped) + dots + output
        }

        return arrayPattern
    }

    private func liftObjectDestructPattern(properties: [String], outputs: [String], hasRestElement: Bool) -> String {
        assert(outputs.count == properties.count + (hasRestElement ? 1 : 0))

        var objectPattern = ""
        for (property, output) in zip(properties, outputs) {
            objectPattern += "\"\(property)\":\(output),"
        }
        if hasRestElement {
            objectPattern += "...\(outputs.last!)"
        }

        return objectPattern
    }

    /// A wrapper around a ScriptWriter. It's main responsibility is expression inlining.
    ///
    /// Expression inlining roughly works as follows:
    /// - FuzzIL operations that map to a single JavaScript expressions are lifted to these expressions and associated with the output FuzzIL variable using assign()
    /// - If an expression is pure, e.g. a number literal, it will be inlined into all its uses
    /// - On the other hand, if an expression is effectful, it can only be inlined if there is a single use of the FuzzIL variable (otherwise, the expression would execute multiple times), _and_ if there is no other effectful expression before that use (otherwise, the execution order of instructions would change)
    /// - To achieve that, pending effectful expressions are kept in a list of expressions which must execute in FIFO order at runtime
    /// - To retrieve the expression for an input FuzzIL variable, the retrieve() function is used. If an inlined expression is returned, this function takes care of first emitting pending expressions if necessary (to ensure correct execution order)
    private struct JavaScriptWriter {
        private var writer: ScriptWriter
        private var analyzer: VariableAnalyzer

        var code: String {
            return writer.code
        }

        // Maps each FuzzIL variable to its JavaScript expression.
        // The expression for a FuzzIL variable can generally either be
        //  * an identifier like "v42" if the FuzzIL variable is mapped to a JavaScript variable OR
        //  * an arbitrary expression if the expression producing the FuzzIL variable is a candidate for inlining
        private var expressions = VariableMap<Expression>()

        // List of effectful expressions that are still waiting to be inlined. In the order that they need to be executed at runtime.
        // The expressions are identified by the FuzzIL output variable that they generate. The actual expression is stored in the expressions dictionary.
        private var pendingExpressions = [Variable]()

        init(analyzer: VariableAnalyzer, version: ECMAScriptVersion, stripComments: Bool = false, includeLineNumbers: Bool = false, indent: Int = 4) {
            self.writer = ScriptWriter(stripComments: stripComments, includeLineNumbers: includeLineNumbers, indent: indent, commentPrefix: "#")
            self.analyzer = analyzer
        }

        /// Assign a JavaScript expression to a FuzzIL variable.
        ///
        /// If the expression can be inlined, it will be associated with the variable and returned at its use. If the expression cannot be inlined,
        /// the expression will be emitted either as part of a variable definition or as an expression statement (if the value isn't subsequently used).
        mutating func assign(_ expr: Expression, to v: Variable) {
            if shouldTryInlining(expr, producing: v) {
                expressions[v] = expr
                // If this is an effectful expression, it must be the next expression to be evaluated. To ensure that, we
                // keep a list of all "pending" effectful expressions, which must be executed in FIFO order.
                if expr.isEffectful {
                    pendingExpressions.append(v)
                }
            } else {
                // The expression cannot be inlined. Now decide whether to define the output variable or not. The output variable can be omitted if:
                //  * It is not used by any following instructions, and
                //  * It is not an Object literal, as that would not be valid syntax (it would mistakenly be interpreted as a block statement)
                if analyzer.numUses(of: v) == 0 && expr.type !== ObjectLiteral {
                    emit("\(expr);")
                } else {
                    // let LET = declarationKeyword(for: v)
                    let V = declare(v)
                    emit("\(V) = \(expr);")
                }
            }
        }

        /// Retrieve the JavaScript expression for the given FuzzIL variable.
        ///
        /// This is a mutating operation: if the expression is being inlined, this will:
        ///  * emit all pending expressions that need to execute first
        ///  * remove this expression from the expression mapping
        mutating func retrieve(expressionFor v: Variable) -> Expression {
            guard let expression = expressions[v] else {
                fatalError("Don't have an expression for variable \(v)")
            }

            if expression.isEffectful {
                // Inlined, effectful expressions must only be used once. To guarantee that, remove the expression from the dictionary.
                expressions.removeValue(forKey: v)

                // Emit all pending expressions that need to be evaluated prior to this one.
                var i = 0
                while i < pendingExpressions.count {
                    let pending = pendingExpressions[i]
                    i += 1
                    if pending == v { break }
                    emitPendingExpression(forVariable: pending)
                }
                pendingExpressions.removeFirst(i)
            }

            return expression
        }

        /// Retrieve a JavaScript identifier for the given FuzzIL variable.
        ///
        /// This will retrieve the expression for the given variable and, if it is not an identifier (because the expression is being inlined), store it into a local variable.
        /// Useful mostly for aesthetic reasons, when assigning a value to a temporary variable will result in more readable code.
        mutating func retrieve(identifierFor v: Variable) -> Expression {
            var expr = retrieve(expressionFor: v)
            if expr.type !== Identifier {
                // When creating a temporary variable for the expression, we're _not_ replacing the existing
                // expression with it since we cannot guarantee that the variable will still be visible at
                // the next use. Consider the following example:
                //
                //     v0 <- LoadInt(0)
                //     v1 <- LoadInt(10)
                //     BerginDoWhileLoop v0, '<', v1
                //         SetElement v1, '0', v0
                //         v2 <- Unary v1, '++'
                //     EndDoWhileLoop
                //
                // For the SetElement, we force the object to be in a local variable. However, in the do-while loop
                // that variable would no longer be visible:
                //
                //    let v0 = 0;
                //    do {
                //        const v1 = 10;
                //        v1[0] = v0;
                //        v0++;
                //    } while (v0 < v1)
                //
                // So instead, in the do-while loop we again need to use the inlined expression (`10`).
                // We use a different naming scheme for these temporary variables since we may end up defining
                // them multiple times (if the same expression is "un-inlined" multiple times).
                // We could instead remember the existing local variable for as long as it is visible, but it's
                // probably not worth the effort.
                let V = "t" + String(writer.currentLineNumber)
                emit("\(V) = \(expr);")
                expr = Identifier.new(V)
            }
            return expr
        }

        /// Declare the given FuzzIL variable as a JavaScript variable with the given name.
        /// Whenever the variable is used in a FuzzIL instruction, the given identifier will be used in the lifted JavaScript code.
        ///
        /// Note that there is a difference between declaring a FuzzIL variable as a JavaScript identifier and assigning it to the current value of that identifier.
        /// Consider the following FuzzIL code:
        ///
        ///     v0 <- LoadUndefined
        ///     v1 <- LoadInt 42
        ///     Reassign v0 v1
        ///
        /// This code should be lifted to:
        ///
        ///     let v0 = undefined;
        ///     v0 = 42;
        ///
        /// And not:
        ///
        ///     undefined = 42;
        ///
        /// The first (correct) example corresponds to assign()ing v0 the expression 'undefined', while the second (incorrect) example corresponds to declare()ing v0 as 'undefined'.
        @discardableResult
        mutating func declare(_ v: Variable, as maybeName: String? = nil) -> String {
            assert(!expressions.contains(v))
            let name = maybeName ?? "v" + String(v.number)
            expressions[v] = Identifier.new(name)
            return name
        }

        /// Declare all of the given variables. Equivalent to calling declare() for each of them.
        /// The variable names will be constructed as prefix + v.number. By default, the prefix "v" is used.
        @discardableResult
        mutating func declareAll(_ vars: ArraySlice<Variable>, usePrefix prefix: String = "v") -> [String] {
            return vars.map({ declare($0, as: prefix + String($0.number)) })
        }

        mutating func enterNewBlock() {
            emitPendingExpressions()
            writer.increaseIndentionLevel()
        }

        mutating func leaveCurrentBlock() {
            emitPendingExpressions()
            writer.decreaseIndentionLevel()
        }

        mutating func emit(_ line: String) {
            emitPendingExpressions()
            writer.emit(line)
        }

        /// Emit a (potentially multi-line) comment.
        mutating func emitComment(_ comment: String) {
            writer.emitComment(comment)
        }

        /// Emit one or more lines of code.
        mutating func emitBlock(_ block: String) {
            emitPendingExpressions()
            writer.emitBlock(block)
        }

        /// Emit all expressions that are still waiting to be inlined.
        /// This is usually used because some other effectful piece of code is about to be emitted, so the pending expression must execute first.
        mutating func emitPendingExpressions() {
            for v in pendingExpressions {
                emitPendingExpression(forVariable: v)
            }
            pendingExpressions.removeAll(keepingCapacity: true)
        }

        private mutating func emitPendingExpression(forVariable v: Variable) {
            guard let EXPR = expressions[v] else {
                fatalError("Missing expression for variable \(v)")
            }
            expressions.removeValue(forKey: v)
            assert(analyzer.numUses(of: v) > 0)
            let V = declare(v)
            // Need to use writer.emit instead of emit here as the latter will emit all pending expressions.
            writer.emit("\(V) = \(EXPR);")
        }

        /// Decide if we should attempt to inline the given expression. We do that if:
        ///  * The output variable is not reassigned later on (otherwise, that reassignment would fail as the variable was never defined)
        ///  * The output variable is pure and has at least one use OR
        ///  * The output variable is effectful and has exactly one use. However, in this case, the expression will only be inlined if it is still the next expression to be evaluated at runtime.
        private func shouldTryInlining(_ expression: Expression, producing v: Variable) -> Bool {
            if analyzer.numAssignments(of: v) > 1 {
                // Can never inline an expression when the output variable is reassigned again later.
                return false
            }

            switch expression.characteristic {
            case .pure:
                return analyzer.numUses(of: v) > 0
            case .effectful:
                return analyzer.numUses(of: v) == 1
            }
        }
    }
}
