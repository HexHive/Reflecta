// Copyright 2023 Google LLC
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

/// Enum defining all opcodes supported in FuzzIL.
///
/// There should be a 1:1 mapping between opcodes and Operation subclasses.
/// This enum is then mainly used for efficient type testing of Operations, for example in switch constructs:
///
///     switch instr.op.opcode() {
///         case .loadInt(let op):
///             doSomethingWithLoadInteger(op)
///         // ...
///         case .callFunction(let op):
///             doSomethingWithCallFunction(op)
///         // ...
///     }
///
/// This is both efficient, as only an integer value needs to be switched on, and type-safe, as it avoids type casts entirely.
enum Opcode {
    case nop(Nop)
    case loadInteger(LoadInteger)
    case loadBigInt(LoadBigInt)
    case loadFloat(LoadFloat)
    case loadString(LoadString)
    case loadBoolean(LoadBoolean)
    case loadUndefined(LoadUndefined)
    case loadNull(LoadNull)
    case loadThis(LoadThis)
    case loadArguments(LoadArguments)
    case loadRegExp(LoadRegExp)
    case beginObjectLiteral(BeginObjectLiteral)
    case objectLiteralAddProperty(ObjectLiteralAddProperty)
    case objectLiteralAddElement(ObjectLiteralAddElement)
    case objectLiteralAddComputedProperty(ObjectLiteralAddComputedProperty)
    case objectLiteralCopyProperties(ObjectLiteralCopyProperties)
    case objectLiteralSetPrototype(ObjectLiteralSetPrototype)
    case beginObjectLiteralMethod(BeginObjectLiteralMethod)
    case endObjectLiteralMethod(EndObjectLiteralMethod)
    case beginObjectLiteralGetter(BeginObjectLiteralGetter)
    case endObjectLiteralGetter(EndObjectLiteralGetter)
    case beginObjectLiteralSetter(BeginObjectLiteralSetter)
    case endObjectLiteralSetter(EndObjectLiteralSetter)
    case endObjectLiteral(EndObjectLiteral)
    case beginClassDefinition(BeginClassDefinition)
    case beginClassConstructor(BeginClassConstructor)
    case endClassConstructor(EndClassConstructor)
    case classAddInstanceProperty(ClassAddInstanceProperty)
    case classAddInstanceElement(ClassAddInstanceElement)
    case classAddInstanceComputedProperty(ClassAddInstanceComputedProperty)
    case beginClassInstanceMethod(BeginClassInstanceMethod)
    case endClassInstanceMethod(EndClassInstanceMethod)
    case beginClassInstanceGetter(BeginClassInstanceGetter)
    case endClassInstanceGetter(EndClassInstanceGetter)
    case beginClassInstanceSetter(BeginClassInstanceSetter)
    case endClassInstanceSetter(EndClassInstanceSetter)
    case classAddStaticProperty(ClassAddStaticProperty)
    case classAddStaticElement(ClassAddStaticElement)
    case classAddStaticComputedProperty(ClassAddStaticComputedProperty)
    case beginClassStaticInitializer(BeginClassStaticInitializer)
    case endClassStaticInitializer(EndClassStaticInitializer)
    case beginClassStaticMethod(BeginClassStaticMethod)
    case endClassStaticMethod(EndClassStaticMethod)
    case beginClassStaticGetter(BeginClassStaticGetter)
    case endClassStaticGetter(EndClassStaticGetter)
    case beginClassStaticSetter(BeginClassStaticSetter)
    case endClassStaticSetter(EndClassStaticSetter)
    case classAddPrivateInstanceProperty(ClassAddPrivateInstanceProperty)
    case beginClassPrivateInstanceMethod(BeginClassPrivateInstanceMethod)
    case endClassPrivateInstanceMethod(EndClassPrivateInstanceMethod)
    case classAddPrivateStaticProperty(ClassAddPrivateStaticProperty)
    case beginClassPrivateStaticMethod(BeginClassPrivateStaticMethod)
    case endClassPrivateStaticMethod(EndClassPrivateStaticMethod)
    case endClassDefinition(EndClassDefinition)
    case createArray(CreateArray)
    case createIntArray(CreateIntArray)
    case createFloatArray(CreateFloatArray)
    case createArrayWithSpread(CreateArrayWithSpread)
    case createTemplateString(CreateTemplateString)
    case loadBuiltin(LoadBuiltin)
    case getProperty(GetProperty)
    case setProperty(SetProperty)
    case updateProperty(UpdateProperty)
    case deleteProperty(DeleteProperty)
    case configureProperty(ConfigureProperty)
    case getElement(GetElement)
    case setElement(SetElement)
    case updateElement(UpdateElement)
    case deleteElement(DeleteElement)
    case configureElement(ConfigureElement)
    case getComputedProperty(GetComputedProperty)
    case setComputedProperty(SetComputedProperty)
    case updateComputedProperty(UpdateComputedProperty)
    case deleteComputedProperty(DeleteComputedProperty)
    case configureComputedProperty(ConfigureComputedProperty)
    case typeOf(TypeOf)
    case testInstanceOf(TestInstanceOf)
    case testIn(TestIn)
    case beginPlainFunction(BeginPlainFunction)
    case endPlainFunction(EndPlainFunction)
    case beginArrowFunction(BeginArrowFunction)
    case endArrowFunction(EndArrowFunction)
    case beginGeneratorFunction(BeginGeneratorFunction)
    case endGeneratorFunction(EndGeneratorFunction)
    case beginAsyncFunction(BeginAsyncFunction)
    case endAsyncFunction(EndAsyncFunction)
    case beginAsyncArrowFunction(BeginAsyncArrowFunction)
    case endAsyncArrowFunction(EndAsyncArrowFunction)
    case beginAsyncGeneratorFunction(BeginAsyncGeneratorFunction)
    case endAsyncGeneratorFunction(EndAsyncGeneratorFunction)
    case beginConstructor(BeginConstructor)
    case endConstructor(EndConstructor)
    case `return`(Return)
    case yield(Yield)
    case yieldEach(YieldEach)
    case await(Await)
    case callFunction(CallFunction)
    case callFunctionWithSpread(CallFunctionWithSpread)
    case construct(Construct)
    case constructWithSpread(ConstructWithSpread)
    case callMethod(CallMethod)
    case callMethodWithSpread(CallMethodWithSpread)
    case callComputedMethod(CallComputedMethod)
    case callComputedMethodWithSpread(CallComputedMethodWithSpread)
    case unaryOperation(UnaryOperation)
    case binaryOperation(BinaryOperation)
    case ternaryOperation(TernaryOperation)
    case update(Update)
    case dup(Dup)
    case reassign(Reassign)
    case destructArray(DestructArray)
    case destructArrayAndReassign(DestructArrayAndReassign)
    case destructObject(DestructObject)
    case destructObjectAndReassign(DestructObjectAndReassign)
    case compare(Compare)
    case loadNamedVariable(LoadNamedVariable)
    case storeNamedVariable(StoreNamedVariable)
    case defineNamedVariable(DefineNamedVariable)
    case eval(Eval)
    case beginWith(BeginWith)
    case endWith(EndWith)
    case callSuperConstructor(CallSuperConstructor)
    case callSuperMethod(CallSuperMethod)
    case getPrivateProperty(GetPrivateProperty)
    case setPrivateProperty(SetPrivateProperty)
    case updatePrivateProperty(UpdatePrivateProperty)
    case callPrivateMethod(CallPrivateMethod)
    case getSuperProperty(GetSuperProperty)
    case setSuperProperty(SetSuperProperty)
    case updateSuperProperty(UpdateSuperProperty)
    case beginIf(BeginIf)
    case beginElse(BeginElse)
    case endIf(EndIf)
    case beginWhileLoop(BeginWhileLoop)
    case endWhileLoop(EndWhileLoop)
    case beginDoWhileLoop(BeginDoWhileLoop)
    case endDoWhileLoop(EndDoWhileLoop)
    case beginForLoop(BeginForLoop)
    case endForLoop(EndForLoop)
    case beginForInLoop(BeginForInLoop)
    case endForInLoop(EndForInLoop)
    case beginForOfLoop(BeginForOfLoop)
    case beginForOfWithDestructLoop(BeginForOfWithDestructLoop)
    case endForOfLoop(EndForOfLoop)
    case beginRepeatLoop(BeginRepeatLoop)
    case endRepeatLoop(EndRepeatLoop)
    case loopBreak(LoopBreak)
    case loopContinue(LoopContinue)
    case beginTry(BeginTry)
    case beginCatch(BeginCatch)
    case beginFinally(BeginFinally)
    case endTryCatchFinally(EndTryCatchFinally)
    case throwException(ThrowException)
    case beginCodeString(BeginCodeString)
    case endCodeString(EndCodeString)
    case beginBlockStatement(BeginBlockStatement)
    case endBlockStatement(EndBlockStatement)
    case beginSwitch(BeginSwitch)
    case beginSwitchCase(BeginSwitchCase)
    case beginSwitchDefaultCase(BeginSwitchDefaultCase)
    case endSwitchCase(EndSwitchCase)
    case endSwitch(EndSwitch)
    case switchBreak(SwitchBreak)
    case print(Print)
    case explore(Explore)
    case probe(Probe)
}
