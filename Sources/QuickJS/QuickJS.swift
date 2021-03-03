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

let JS_NewCustomContext: @convention(c) (OpaquePointer?) -> OpaquePointer? = { rt in
    guard let ctx = JS_NewContext(rt) else {
        return nil
    }
    
    // system modules
    // TODO: by default?
    let _ = js_init_module_std(ctx, "std")
    let _ = js_init_module_os(ctx, "os")
    
    return ctx
}

let JS_ModuleInit: @convention(c) (OpaquePointer?, OpaquePointer?) -> CInt = { (ctx, m) in
    guard let ctx = ctx,
          let m = m,
          let context = QuickJSContext.retrive(ctx) else {
        return -1
    }
    
    context.loadModule(m)
    
    return 0;
}

public protocol ConvertibleFromJavaScript {
    init?(_ ctx: QuickJSContext, value: JSValue)
}

extension String: ConvertibleFromJavaScript {
    public init?(_ ctx: QuickJSContext, value: JSValue) {
        guard JS_IsString(value) != 0 else {
            return nil
        }
        
        if let cStr = JS_ToCString(ctx.ctx, value) {
            self.init(cString: cStr)
            JS_FreeCString(ctx.ctx, cStr)
        } else {
            return nil
        }
    }
}

extension Int32: ConvertibleFromJavaScript {
    public init?(_ ctx: QuickJSContext, value: JSValue) {
        guard JS_IsNumber(value) != 0 else {
            return nil
        }
        
        var pres: Int32 = 0
        if JS_ToInt32(ctx.ctx, &pres, value) < 0 {
            return nil
        }
        self = pres
    }
}

extension UInt32: ConvertibleFromJavaScript {
    public init?(_ ctx: QuickJSContext, value: JSValue) {
        guard JS_IsNumber(value) != 0 else {
            return nil
        }
        
        var pres: UInt32 = 0
        if JS_ToUint32(ctx.ctx, &pres, value) < 0 {
            return nil
        }
        self = pres
    }
}

extension Int64: ConvertibleFromJavaScript {
    public init?(_ ctx: QuickJSContext, value: JSValue) {
        guard JS_IsNumber(value) != 0 else {
            return nil
        }
        
        var pres: Int64 = 0
        if JS_ToInt64(ctx.ctx, &pres, value) < 0 {
            return nil
        }
        self = pres
    }
}

extension Int: ConvertibleFromJavaScript {
    public init?(_ ctx: QuickJSContext, value: JSValue) {
        guard let valueIn64 = Int64(ctx, value: value) else {
            return nil
        }
        self = .init(valueIn64)
    }
}

extension UInt: ConvertibleFromJavaScript {
    public init?(_ ctx: QuickJSContext, value: JSValue) {
        guard let valueIn32 = UInt32(ctx, value: value) else {
            return nil
        }
        self = .init(valueIn32)
    }
}

extension Array: ConvertibleFromJavaScript where Element: ConvertibleFromJavaScript {
    public init?(_ ctx: QuickJSContext, value: JSValue) {
        guard JS_IsObject(value) != 0 else {
            return nil
        }
        
        let length = JS_GetPropertyStr(ctx.ctx, value, "length")
        defer {
            JS_FreeValue(ctx.ctx, length)
        }
        
        var size: UInt64 = 0
        if JS_ToIndex(ctx.ctx, &size, length) < 0 {
            return nil
        }
        
        self = []
        for index in 0..<size {
            let p = JS_GetPropertyUint32(ctx.ctx, value, UInt32(index))
            if let ele = Element(ctx, value: p) {
                self.append(ele)
                JS_FreeValue(ctx.ctx, p)
            } else {
                JS_FreeValue(ctx.ctx, p)
                return nil
            }
        }
    }
}

public enum QuickJSError: Error, ConvertibleFromJavaScript {
    case exception
    
    public init?(_ ctx: QuickJSContext, value: JSValue) {
        guard JS_IsException(value) != 0 else {
            return nil
        }
        self = .exception
    }
}

public class QuickJSRuntime {
    let rt: OpaquePointer
    
    public init?() {
        guard let rt = JS_NewRuntime() else {
            return nil
        }
        self.rt = rt
        
        js_std_set_worker_new_context_func(JS_NewCustomContext);
        js_std_init_handlers(rt);
        JS_SetModuleLoaderFunc(rt, nil, js_module_loader, nil);
    }
    
    deinit {
        JS_FreeRuntime(self.rt)
    }
    
    public func createContext() -> QuickJSContext? {
        return QuickJSContext(self)
    }
}

public class QuickJSContext {
    let ctx: OpaquePointer
    let rt: QuickJSRuntime
    
    class func retrive(_ ctx: OpaquePointer) -> Self? {
        guard let ptr = JS_GetContextOpaque(ctx) else {
            return nil
        }
        
        return Unmanaged<Self>.fromOpaque(ptr).takeUnretainedValue()
    }
    
    required init?(_ rt: QuickJSRuntime) {
        self.rt = rt
        if let ctx = JS_NewCustomContext(rt.rt) {
            self.ctx = ctx
            
            let ptr = Unmanaged<QuickJSContext>.passUnretained(self).toOpaque()
            JS_SetContextOpaque(ctx, ptr)
        } else {
            return nil
        }
    }
    
    deinit {
        JS_FreeContext(self.ctx)
    }
    
    public enum EvalType: Int32 {
        case global = 0
        case module = 1
    }
    
    public func eval<T:ConvertibleFromJavaScript>(_ jsCode: String, type: EvalType = .global) -> T? {
        let cStr = jsCode.cString(using: .utf8)!
        let len = jsCode.lengthOfBytes(using: .utf8)
        let evalType = type.rawValue
        
        let value = JS_Eval(self.ctx, cStr, len, "<Swift>", evalType)
        defer {
            JS_FreeValue(self.ctx, value)
        }
        
        return T(self, value: value)
    }
    
    public func setGlobalProperty(name: String, value: String) {
        let globalObj = JS_GetGlobalObject(ctx)
        let jsValue = JS_NewString(ctx, value.cString(using: .utf8))
        JS_SetPropertyStr(ctx, globalObj, name.cString(using: .utf8), jsValue)
        
        JS_FreeValue(ctx, globalObj)
    }
    
    public func hasGlobalProperty(name: String) -> Bool {
        let globalObj = JS_GetGlobalObject(ctx)
        
        let jsValue = JS_GetPropertyStr(ctx, globalObj, name.cString(using: .ascii))
        
        defer {
            JS_FreeValue(ctx, jsValue)
            JS_FreeValue(ctx, globalObj)
        }
        
        if JS_IsException(jsValue) != 0 || JS_IsUndefined(jsValue) != 0 {
            return false
        }
        
        return true
    }
    
    // MARK: Module
    fileprivate var modules: [OpaquePointer: QuickJSModule] = [:]
    fileprivate func loadModule(_ m: OpaquePointer) {
        guard let module = self.modules[m] else {
            return
        }
        module.moduleDidLoad()
    }
    
    public func createModule(_ name: String) -> QuickJSModule? {
        guard let m = JS_NewCModule(ctx, name, JS_ModuleInit) else {
            return nil
        }
        
        let module = QuickJSModule(self, name: name, m: m)
        self.modules[m] = module
        return module
    }
}

public class QuickJSModule {
    let m: OpaquePointer
    weak var ctx: QuickJSContext!
    
    let name: String
    
    public typealias Founction = @convention(c) (OpaquePointer?, JSValue, Int32, UnsafeMutablePointer<JSValue>?) -> JSValue
    
    private struct FunctionInfo {
        let name: String
        let argc: Int32
        let function: Founction
    }
    private var functionList: [FunctionInfo] = []
    
    init(_ ctx: QuickJSContext, name: String, m: OpaquePointer) {
        self.m = m
        self.ctx = ctx
        self.name = name
    }
    
    func moduleDidLoad() {
        self.functionList.forEach { (info) in
            let val = JS_NewCFunction(ctx.ctx, info.function, info.name, info.argc)
            JS_SetModuleExport(ctx.ctx, m, info.name, val)
        }
    }
    
    public func reigister(_ name: String, argc: Int32, function: @escaping Founction) {
        let info = FunctionInfo(name: name, argc: argc, function: function)
        self.functionList.append(info)
        JS_AddModuleExport(ctx.ctx, m, name)
    }
}
