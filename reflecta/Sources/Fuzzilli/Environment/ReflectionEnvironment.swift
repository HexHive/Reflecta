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

public class ReflectionEnvironment: ComponentBase, Environment {


    // Integer values that are more likely to trigger edge-cases.
    public let interestingIntegers: [Int64] = [
        -9223372036854775808, -9223372036854775807,               // Int64 min, mostly for BigInts
        -9007199254740992, -9007199254740991, -9007199254740990,  // Smallest integer value that is still precisely representable by a double
        -4294967297, -4294967296, -4294967295,                    // Negative Uint32 max
        -2147483649, -2147483648, -2147483647,                    // Int32 min
        -1073741824, -536870912, -268435456,                      // -2**32 / {4, 8, 16}
        -65537, -65536, -65535,                                   // -2**16
        -4096, -1024, -256, -128,                                 // Other powers of two
        -2, -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 16, 64,         // Numbers around 0
        127, 128, 129,                                            // 2**7
        255, 256, 257,                                            // 2**8
        512, 1000, 1024, 4096, 10000,                             // Misc numbers
        65535, 65536, 65537,                                      // 2**16
        268435456, 536870912, 1073741824,                         // 2**32 / {4, 8, 16}
        2147483647, 2147483648, 2147483649,                       // Int32 max
        4294967295, 4294967296, 4294967297,                       // Uint32 max
        9007199254740990, 9007199254740991, 9007199254740992,     // Biggest integer value that is still precisely representable by a double
        9223372036854775806,  9223372036854775807                 // Int64 max, mostly for BigInts (TODO add Uint64 max as well?)
    ]

    // Double values that are more likely to trigger edge-cases.
    public let interestingFloats = [-Double.infinity, -Double.greatestFiniteMagnitude, -1e-15, -1e12, -1e9, -1e6, -1e3, -5.0, -4.0, -3.0, -2.0, -1.0, -Double.ulpOfOne, -Double.leastNormalMagnitude, -0.0, 0.0, Double.leastNormalMagnitude, Double.ulpOfOne, 1.0, 2.0, 3.0, 4.0, 5.0, 1e3, 1e6, 1e9, 1e12, 1e-15, Double.greatestFiniteMagnitude, Double.infinity, Double.nan]

    // TODO more?
    public var interestingStrings = [""]

    // TODO more?
    public let interestingRegExps = [".", "\\d", "\\w", "\\s", "\\D", "\\W", "\\S"]
    public let interestingRegExpQuantifiers = ["*", "+", "?"]

    public let intType = JSType.integer
    public let bigIntType = JSType.bigint
    public let floatType = JSType.float
    public let booleanType = JSType.boolean
    public let regExpType = JSType.jsRegExp
    public let stringType = JSType.jsString
    public let emptyObjectType = JSType.object()
    public let arrayType = JSType.jsArray

    public var builtins = Set<String>([])
    public var customProperties = Set<String>(["p"])
    public var customMethods = Set<String>(["m"])
    public var builtinProperties: Set<String> = Set<String>(["p"])
    public var builtinMethods: Set<String> = Set<String>(["m"])

    public var constructables = [String]()

    private var builtinTypes: [String: JSType] = [:]

    public init(additionalBuiltins: [String: JSType]) {
        super.init(name: "ReflectionEnvironment")

        builtins.formUnion(additionalBuiltins.keys)
    }

    public override func initialize(with fuzzer: Fuzzer) {
        let b = fuzzer.makeBuilder()
        let r = b.loadBuiltin("Reflecta")
        b.callMethod("enumerate", on: r, withArgs: [])
        let program = b.finalize()
        let execution = fuzzer.execute(program, withTimeout: 1000)

        guard let builtins = try? JSONDecoder().decode([String].self, from: Data(execution.fuzzout.trimmingCharacters(in: .whitespaces).utf8)) else {
            logger.log("Program:\n\(fuzzer.lifter.lift(program))", atLevel: .info)
            logger.log("Outcome:\n\(execution.outcome)", atLevel: .error)
            logger.log("STDOUT:\n\(execution.stdout)", atLevel: .error)
            logger.log("STDERR:\n\(execution.stderr)", atLevel: .error)
            logger.log("FUZZOUT:\n\(execution.fuzzout.utf8)", atLevel: .error)
            fatalError("Failed to retrieve builtins through reflection")
        }

        let strs = Set(builtins.flatMap { $0.components(separatedBy: CharacterSet(charactersIn: ".:->")) }.filter { $0 != "" })
        self.builtins.formUnion(builtins)
        self.builtinMethods.formUnion(strs)
        self.builtinProperties.formUnion(strs)
        self.interestingStrings.append(contentsOf: strs)

        // Log detailed information about the environment here so users are aware of it and can modify things if they like.
        logger.info("Initialized reflection environment model")
        logger.info("Have \(builtins.count) available builtins: \(builtins)")
        logger.info("Have \(builtinProperties.count) builtin property names: \(builtinProperties)")
        logger.info("Have \(builtinMethods.count) builtin method names: \(builtinMethods)")
        logger.info("Have \(customProperties.count) custom property names: \(customProperties)")
        logger.info("Have \(customMethods.count) custom method names: \(customMethods)")
    }

    public func type(ofBuiltin builtinName: String) -> JSType {
        return .unknown
    }

    public func type(ofProperty propertyName: String, on baseType: JSType) -> JSType {
        return .unknown
    }

    public func signature(ofMethod methodName: String, on baseType: JSType) -> Signature {
        return Signature.forUnknownFunction
    }
}
