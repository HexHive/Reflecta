// Copyright 2022 Google LLC
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

public func chooseWeighted<E>(from collection: [E], by: (E) -> Int, inverse: Bool = false) -> E {
    var weights = collection.map(by)
    if inverse {
        let sum = weights.reduce(0, +)
        weights = weights.map { sum / $0 }
    }

    let weightedList = WeightedList(Array(zip(collection, weights)))

    return weightedList.randomElement()
}

func groupElements<K, V>(of list: [V], by key: (V) -> K) -> [K: [V]] {
    var groups = [K: [V]]()
    for e in list {
        groups[key(e), default: []].append(e)
    }
    return groups
}

extension Code {
    public func reflectedType(of variable: Variable) -> String? {
        for instr in self {
            if instr.hasOneOutput && instr.output == variable {
                return instr.op.info?.type
            }
        }
        return nil
    }

    public func outputInstrs(reflected: Bool = false) -> [Instruction] {
        return self.filter({ $0.hasOneOutput && $0.isSimple && (!reflected || $0.op.info != nil) })
    }

    public func getVarUsage() -> [Variable: Int] {
        let outputInstrs = self.outputInstrs()
        var varUsageCount: [Variable: Int] = [:]

        for instr in outputInstrs {
            varUsageCount[instr.output] = 0
        }

        for instr in self {
            for v in instr.inputs {
                varUsageCount[v]! += 1
            }
        }

        return varUsageCount
    }

    // public func groupInstrsByType(withName: Bool) -> [[String?]: [Instruction]] {
    //     return groupElements(of: self.outputInstrs(), by: {[$0.op.info?.type] + (withName ? [$0.op.info?.name] : [])})
    // }
}

extension ProgramBuilder {
    func wrapReflectCall(body: () -> Variable) {
        self.buildTryCatchFinally(tryBody: {
            let i = self.loadInt(Int64(self.indexOfNextInstruction() + 1))
            let o = body()
            let r = self.reuseOrLoadBuiltin("Reflecta")
            self.callMethod("record", on: r, withArgs: [o, i])
        })
    }

    func generateCallArguments(arity: Int?) -> [Variable] {
        let a: Int;
        if arity == nil || probability(0.5) {
            a = WeightedList([(0, 4), (1, 4), (2, 2), (3, 1)]).randomElement()
        } else {
            a = arity! + WeightedList([(0, 4), (1, 1)]).randomElement()
        }

        let sig = Signature(expects: (0..<a).map {_ in Signature.Parameter.anything}, returns: JSType.unknown)

        return self.generateCallArguments(for: sig)
    }

}
extension Fuzzer {
    public func debugProgram(_ program: Program, _ level: LogLevel = .warning) {
        let src = lifter.lift(program)
        let execution = execute(program)
        logger.log("Source:\n\(src)", atLevel: level)
        logger.log("Outcome: \(execution.outcome)", atLevel: level)
        logger.log(
            "STDOUT:\(execution.stdout.isEmpty ? " <empty>" : "\n" + execution.stdout)",
            atLevel: level)
        logger.log(
            "STDERR:\(execution.stderr.isEmpty ? " <empty>" : "\n" + execution.stderr)",
            atLevel: level)
        logger.log(
            "FUZZOUT:\(execution.fuzzout.isEmpty ? " <empty>" : "\n" + execution.fuzzout)",
            atLevel: level)
    }


    public func instrumentWithReflection(_ program: Program) -> Program {
        let b = self.makeBuilder()
        b.adopting(from: program) {
            let helper = b.reuseOrLoadBuiltin("Reflecta")
            for instr in program.code {
                b.adopt(instr)
                if instr.isSimple && instr.hasOneOutput {
                    let args = [b.adopt(instr.output), b.loadInt(Int64(instr.index))]
                    b.callMethod("record", on: helper, withArgs: args)
                }
            }
        }

        return b.finalize()
    }

    public func reflectOn(_ program: Program, with execution: Execution) -> Program? {
        if execution.fuzzout == "" {
            return nil
        }

        let json = execution.fuzzout
            .split(separator: "\n")
            .map { try? JSONDecoder().decode(ReflectionInfo.self, from: Data($0.drop{ $0 == "\0" || $0 == "\n" }.utf8)) }
            .filter { $0 != nil && $0!.index < program.code.count }

        guard json.count > 0 && execution.outcome == .succeeded else {
            return nil
        }


        let copy = program.copy()
        for i in json {
            copy.code[i!.index].op.info = i
        }

        return copy
    }

    public func reflectOn(_ program: Program) -> Program? {
        let instrumented = instrumentWithReflection(program)
        let execution = self.execute(instrumented)

        return reflectOn(program, with: execution)
    }
}

public class ReflectionMutator: Mutator {
    private let logger = Logger(withLabel: "ReflectionMutator")

    // If true, this mutator will log detailed statistics like how often each type of operation was performend.
    private let verbose = true

    public var propertySet = Set<String>()
    public var methodSet = Set<String>()

    private var attrFreqMap = [String: Int]()
    private var typeFreqMap = [[String?]: Int]()

    override public init() {}

    override func mutate(_ program: Program, using b: ProgramBuilder, for fuzzer: Fuzzer) -> Program? {
        guard let reflected = fuzzer.reflectOn(program) else {
            return nil
        }

        return mutateImpl(reflected, for: fuzzer)
    }


    public func selectInstrs(_ program: Program) -> [Int] {
        let n = 1 + rand() % 3
        let candidates = program.code.filter{ $0.op.info != nil}.map {$0.index}
        let indices =  (1...n).map { _ in chooseUniform(from: candidates)}

        return indices
    }

    public func selectField(_ fields: [String]) -> String {
        return chooseUniform(from: fields)

    }

    public func selectMethod(_ methods: [[String]]) -> [String] {
        return chooseUniform(from: methods)
    }

    public func callRandomMethods(_ b: ProgramBuilder, methods: [[String]], obj: Variable) {
        guard methods.count > 0 else { return }
        let n = 1 + rand() % 3
        let ms =  (1...n).map { _ in selectMethod(methods) }

        for m in ms {
            let args = b.generateCallArguments(arity: Int(m[1]))
            b.wrapReflectCall { b.callMethod(m[0], on: obj, withArgs: args) }
        }
    }

    public func accessRandomFields(_ b: ProgramBuilder, fields: [String], obj: Variable) {
        guard fields.count > 0 else { return }
        let n = 1 + rand() % 3
        let fs =  (1...n).map { _ in selectField(fields) }

        for f in fs {
            if probability(0.9) {
                b.getProperty(f, of: obj)
            } else {
                b.setProperty(f, of: obj, to: b.randomVariable())
            }
        }
    }

    private func mutateImpl(_ program: Program, for fuzzer: Fuzzer) -> Program {
        let b = fuzzer.makeBuilder()
        let indices = selectInstrs(program)

        b.adopting(from: program) {
            for instr in program.code {
                b.adopt(instr)

                guard instr.op.info != nil && instr.hasOneOutput && indices.contains(instr.index) else { continue }
                let info = instr.op.info!
                let obj = b.adopt(instr.output)

                switch info.kind {
                case "primitive":
                    if probability(0.5) { callRandomMethods(b, methods: info.methods, obj: obj) }
                    if probability(0.5) { accessRandomFields(b, fields: info.fields, obj: obj) }
                case "object":
                    if probability(0.8) { callRandomMethods(b, methods: info.methods, obj: obj) }
                    if probability(0.8) { accessRandomFields(b, fields: info.fields, obj: obj) }
                case "function":
                    if probability(0.8) { b.callFunction(obj, withArgs: b.generateCallArguments(arity: info.arity)) }
                    if probability(0.2) { callRandomMethods(b, methods: info.methods, obj: obj) }
                    if probability(0.2) { accessRandomFields(b, fields: info.fields, obj: obj) }
                case "class":
                    if probability(0.8) { b.construct(obj, withArgs: b.generateCallArguments(arity: info.arity)) }
                    if probability(0.5) { callRandomMethods(b, methods: info.methods, obj: obj) }
                    if probability(0.2) { accessRandomFields(b, fields: info.fields, obj: obj) }
                default:
                    break
                }
            }
        }

        let p = b.finalize()
        // print(fuzzer.lifter.lift(p))

        return p
    }


    public func selectAttr(from attrs: [String]) -> String {
        let attr = chooseWeighted(from: attrs, by: { attrFreqMap[$0, default: 1] }, inverse: true)

        attrFreqMap[attr, default: 0] += 1

        return attr
    }

    public func selectType(from types: [[String?]]) -> [String?] {
        let type = chooseWeighted(from: types, by: { typeFreqMap[$0, default: 1] }, inverse: true)
        typeFreqMap[type, default: 0] += 1

        return type
    }


}

    // public func selectInstrs(_ program: Program) -> [Int] {
    //     let candidates = program.code
    //         .filter { $0.op.info != nil }
    //         .filter { $0.op.info!.kind == "primitive" ? probability(0.1) : probability(0.5) }
    //         .map { $0.index }

    //     return candidates
    // }


    // public func recordAttr(
    //     attrs: [String], globalSet: inout Set<String>, name: String, _ fuzzer: Fuzzer
    // ) {
    //     let count = globalSet.count
    //     globalSet = globalSet.union(attrs)
    //     if globalSet.count > count {
    //         let storage = fuzzer.modules["Storage"]! as! Storage
    //         let path = URL(fileURLWithPath: storage.storageDir + "/" + name)
    //         if let json = try? JSONSerialization.data(withJSONObject: Array(globalSet), options: [])
    //         {
    //             try? json.write(to: path)
    //         }
    //         // print(globalSet)
    //     }
    // }

    // Type rarity of a variable
    // - type tuple: (type, name) or unknown
    // - local: within the same program
    // - global: among all corpus programs
    // Whether a variable has been used
    // private func selectInstruction(_ program: Program, n: Int = 1) -> Instruction {
    //     // let typeGroups = program.code.groupInstrsByType(withName: true)
    //     // let type = selectType(from: Array(typeGroups.keys))

    //     // let varUsage = program.code.getVarUsage()
    //     // let instr = chooseWeighted(from: typeGroups[type]!, by: { varUsage[$0.output] == 0 ? 2 : 1})

    //     let candidates = program.code.outputInstrs(reflected: true)
    //     let fstChoice = candidates.last!
    //     let sndChoice = chooseUniform(from: candidates)
    //     let choice = probability(0.5) ? fstChoice : sndChoice

    //     return choice
    // }

    // public func recordTypeSummary(reflected: Program, corpusIdx: Int) {
    //     for instr in reflected.code.outputInstrs(reflected: true) {
    //         if let i = instr.op.info {
    //             try! type.db.run(
    //                 type.table.insert(
    //                     type.program <- corpusIdx,
    //                     type.instr <- i.index!,
    //                     type.type <- i.type,
    //                     type.name <- i.name))
    //         }
    //     }
    // }

    // public func checkNewType(program: Program) -> (Int, String, String?)? {
    //     if let reflected = reflectOn(program) {
    //         for instr in reflected.code.outputInstrs(reflected: true) {
    //             let blocklist = Set(["Symbol", "Method"])
    //             guard let info = instr.op.info, !blocklist.contains(info.type) else {
    //                 continue
    //             }

    //             let predicate =
    //                 (type.type == instr.op.info!.type && type.name == instr.op.info!.name)
    //             let c = try! type.db.scalar((type.table.filter(predicate).count))
    //             if c == 0 {
    //                 return (instr.index, info.type, info.name)
    //             }
    //         }
    //     }

    //     return nil
    // }

    // public func randomArity() -> Arity {
    //     return Arity(required: 0, optional: 2, variadic: true, block: false)
    // }

    // public func getArity(forMethod name: String, instr: Instruction, program: Program) -> Arity {
    //     let b = makeBuilder(prepend: program)
    //     b.callMethod("method", on: instr.output, withArgs: [b.loadString(name)])
    //     let p = b.finalize()

    //     guard let info = executeWithReflection(p),
    //         let arity = info.first(where: { $0.index == p.code.lastInstruction.index })?.arity
    //     else {
    //         return Arity(required: 0, optional: 2, variadic: true, block: false)
    //     }

    //     return arity
    // }

    // public func drawRandomType(withName: Bool) -> (String, String?) {
    //     let columns: [SQLite.Expressible] = withName ? [type.type, type.name] : [type.type]
    //     let query = type.table.select(distinct: columns)
    //         .order(SQLite.Expression<Int>.random())
    //         .limit(1)

    //     let r = try! type.db.prepare(query).first(where: { _ in true })!

    //     return (r[type.type], withName ? r[type.name] : nil)
    // }

    // public func drawRandomInstr(ofType: (String, String?)) -> (Program, Instruction)? {
    //     let query = type.table.select(type.program, type.instr)
    //         .filter(type.type == ofType.0)
    //         .filter(type.name == ofType.1 || ofType.1 == nil)
    //         .order(SQLite.Expression<Int>.random())
    //         .limit(1)

    //     guard let r = try? type.db.prepare(query).first(where: { _ in true }) else {
    //         return nil
    //     }

    //     let program = corpus[r[type.program]]
    //     let instr = program.code[r[type.instr]]

    //     assert(ofType.0 == instr.op.info!.type)

    //     return (program, instr)
    // }

    // public func drawRandomProgram() -> Program {
    //     let t = drawRandomType(withName: true)
    //     let (program, _) = drawRandomInstr(ofType: t)!

    //     return program
    // }
