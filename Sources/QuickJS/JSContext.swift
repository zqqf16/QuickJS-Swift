// QuickJS Swift
//
// Copyright (c) 2021 zqqf16
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation
import QuickJSC

public class JSContext {
    let core: JSContextWrapper
    let runtime: JSRuntime

    required init?(_ runtime: JSRuntime, context: OpaquePointer) {
        self.runtime = runtime
        self.core = JSContextWrapper(context)
        self.core.opaque = self
    }
    
    public enum EvalType: Int32 {
        case global = 0
        case module = 1
    }

    @discardableResult
    public func eval(_ jsCode: String, type: EvalType = .global) -> JSValue {
        let value = JS_Eval(core.context, jsCode, jsCode.lengthOfBytes(using: .utf8), "<Swift>", type.rawValue)
        return JSValue(core, value: value)
    }
    
    @discardableResult
    public func call(function: JSValue, argc: Int, argv: JSCValuePointer?) -> JSValue {
        let result = JS_Call(core.context, function.cValue, .undefined, Int32(argc), argv)
        let obj = JSValue(core, value: result)
        if (obj.isException) {
            if let exception = self.getException() {
                print(exception)
            }
        }
        
        return obj
    }
    
    // MARK: Property
    public func setGlobalProperty(name: String, value: String) {
        let globalObj = JS_GetGlobalObject(core.context)
        let jsValue = JS_NewString(core.context, value.cString(using: .utf8))
        JS_SetPropertyStr(core.context, globalObj, name.cString(using: .utf8), jsValue)
        
        JS_FreeValue(core.context, globalObj)
    }
    
    public func hasGlobalProperty(name: String) -> Bool {
        let globalObj = JS_GetGlobalObject(core.context)
        
        let jsValue = JS_GetPropertyStr(core.context, globalObj, name.cString(using: .ascii))
        
        defer {
            JS_FreeValue(core.context, jsValue)
            JS_FreeValue(core.context, globalObj)
        }
        
        if JS_IsException(jsValue) != 0 || JS_IsUndefined(jsValue) != 0 {
            return false
        }
        
        return true
    }
    
    // MARK: Module
    private var modules: [OpaquePointer: JSModule] = [:]
    private func loadModule(_ cModule: OpaquePointer) {
        guard let module = self.modules[cModule] else {
            return
        }
        module.load()
    }
    
    static let JS_ModuleInit: JSModuleInitFunction = { (ctx, m) in
        guard let ctx = ctx,
              let m = m,
              let context = ctx.opaqueContext else {
                  return -1
              }
        
        context.loadModule(m)
        return 0;
    }
    
    @discardableResult
    public func module<T:JSModule>(_ name: String, @ModuleBuilder _ propertyBuilder: () -> JSModuleProperty) -> T? {
        guard let cModule = JS_NewCModule(core.context, name, JSContext.JS_ModuleInit) else {
            return nil
        }
        
        let module = T(self.core, module: cModule, name: name, propertyBuilder)
        self.modules[cModule] = module
        return module
    }
    
    func flushPendingJobs() {
        var ctx: OpaquePointer?
        while true {
            if JS_ExecutePendingJob(self.runtime.jsInstance, &ctx) <= 0 {
                break
            }
        }
    }
    
    // Exception
    public func getException() -> String? {
        let exception = JS_GetException(core.context)
        defer {
            JS_FreeValue(core.context, exception)
        }
        
        let description = String(self.core, value: exception)
        if JS_IsError(core.context, exception) == 0 {
            return description
        }
        
        let stack = JS_GetPropertyStr(core.context, exception, "stack")
        defer {
            JS_FreeValue(core.context, stack)
        }
        
        let stackStr = String(self.core, value: stack)
        if description == nil {
            return stackStr
        }
        
        if stackStr == nil {
            return description
        }
        
        return "\(description!)\n\(stackStr!)"
    }
        
    // Runloop
    public func enableRunloop() {
        let _: JSRunloop? = self.module("Runloop", {})
    }
}
