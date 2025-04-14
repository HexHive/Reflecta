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

extension Fuzzer {
    public func processExecution(program: Program, execution: Execution) {
        self.dispatchEvent(self.events.ProgramGenerated, data: program)

        switch execution.outcome {
        case .crashed(let termsig):
            self.processCrash(
                program, withSignal: termsig, withStderr: execution.stderr,
                withStdout: execution.stdout, origin: .local, withExectime: execution.execTime)
            program.contributors.generatedCrashingSample()

        case .succeeded:
            self.dispatchEvent(self.events.ValidProgramFound, data: program)
            var isInteresting = false
            if let aspects: ProgramAspects = self.evaluator.evaluate(execution) {
                if self.config.enableInspection {
                    program.comments.add(
                        "Program may be interesting due to \(aspects)", at: .footer)
                }
                isInteresting = self.processMaybeInteresting(
                    program, havingAspects: aspects, origin: .local)
            }

            if isInteresting {
                program.contributors.generatedInterestingSample()
            } else {
                program.contributors.generatedValidSample()
            }

        case .failed(_):
            if self.config.enableDiagnostics {
                program.comments.add("Stdout:\n" + execution.stdout, at: .footer)
            }
            self.dispatchEvent(self.events.InvalidProgramFound, data: program)
            program.contributors.generatedInvalidSample()

        case .timedOut:
            self.dispatchEvent(self.events.TimeOutFound, data: program)
            program.contributors.generatedTimeOutSample()
        }
    }

    public func pred(_ instr: Instruction) -> Bool {
        if instr.op.info == nil || !instr.hasOneOutput || !instr.isSimple {
            return true
        } else if let c = instr.op as? CallMethod {
            if c.methodName == "record" {
                return true
            }
        } else if let l = instr.op as? LoadBuiltin {
            if l.builtinName == "Reflecta" {
                return true
            }
        }

        return false
    }

    public func pruneTryCatch(program: Program, execution: Execution) -> Program {
        // print("******")
        // print("orig:")
        // print(execution.outcome)
        // print(lifter.lift(program))
        // print(FuzzILLifter().lift(program))

        var nops = [Int]()

        if let reflected = self.reflectOn(program, with: execution) {
            for g in Blocks.findAllBlockGroups(in: reflected.code).filter({ $0.begin.op is BeginTry }) {
                nops.append(contentsOf: (g.instructions.filter { pred($0) }.map { $0.index }))
            }
        } else {
            for g in Blocks.findAllBlockGroups(in: program.code).filter({ $0.begin.op is BeginTry }) {
                nops.append(contentsOf: (g.instructions.map {$0.index}))
            }
        }

        let b = makeBuilder()
        b.adopting(from: program) {
            for i in program.code {
                if !nops.contains(i.index) {
                    b.adopt(i)
                }
            }
        }

        let pruned = b.finalize()
        pruned.contributors = program.contributors

        // if execution.fuzzout.count > 0 {
        //     print(nops)
        //     print("fuzzout:")
        //     print(execution.fuzzout)
        //     print("pruned:")
        //     print(lifter.lift(pruned))
        //     fatalError()
        // }

        return pruned
    }
}

/// The core fuzzer responsible for generating and executing programs.
public class ReflectionEngine: ComponentBase, FuzzEngine {
    var consecutiveFails = 0

    public init() {
        super.init(name: "ReflectionEngine")
    }

    public func reprlCheck(_ parent: Program) {
        if consecutiveFails >= 3 {
            if let r = fuzzer.runner as? REPRL {
                r.reset()
                logger.warning("Raw sample from corpus failed to execute consecutively, reseting REPRL...")
                fuzzer.debugProgram(parent)
            }
        }
        guard fuzzer.execute(parent).outcome == .succeeded else {
            consecutiveFails += 1
            return
        }
        consecutiveFails = 0
    }

    public func fuzzOne(_ group: DispatchGroup) {
        let seed = fuzzer.corpus.randomElementForMutating()
        reprlCheck(seed)

        var parent = prepareForMutating(seed)
        for _ in 0..<8 {
            let mutator = fuzzer.mutators.randomElement()

            guard let mutated = mutator.mutate(parent, for: fuzzer) else {
                mutator.failedToGenerate()
                continue
            }
            mutator.addedInstructions(mutated.size - parent.size)

            let execution = fuzzer.execute(mutated)
            let pruned = fuzzer.pruneTryCatch(program: mutated, execution: execution)
            fuzzer.processExecution(program: pruned, execution: execution)

            // Mutate the program further if it succeeded.
            if .succeeded == execution.outcome {
                parent = pruned
            }
        }
    }


    private func prepareForMutating(_ program: Program) -> Program {
        let b = fuzzer.makeBuilder()

        b.run(chooseUniform(from: fuzzer.trivialCodeGenerators))
        for _ in 0...(rand() % 2) {
            b.loadBuiltin(b.randomBuiltin())
        }
        b.append(program)
        let prepared = b.finalize()
        let ok = fuzzer.execute(prepared).outcome == .succeeded

        return ok ? prepared : program
    }

}
