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
    // Declaration order matters: deinit runs in reverse, so `runtime` must outlive
    // `core` (JS_FreeContext before JS_FreeRuntime).
    public let runtime: JSRuntime
    let core: JSContextWrapper
    private var modules: [OpaquePointer: JSModule] = [:]
    /// Strong refs for host functions installed as globals (timers, etc.).
    var hostFunctions: [JSFunction] = []
    private var timersInstalled = false

    required init?(_ runtime: JSRuntime, context: OpaquePointer) {
        self.runtime = runtime
        self.core = JSContextWrapper(context)
        self.core.opaque = self
    }

    deinit {
        // Drop Swift-owned host callbacks before freeing the JS context.
        hostFunctions.removeAll()
        modules.removeAll()
        core.opaque = nil
    }

    public enum EvalType: Int32 {
        case global = 0
        case module = 1
    }

    // MARK: - Eval

    @discardableResult
    public func eval(_ jsCode: String, type: EvalType = .global) -> JSValue {
        eval(jsCode, options: EvalOptions(type: type))
    }

    @discardableResult
    public func eval(_ jsCode: String, options: EvalOptions) -> JSValue {
        runtime.perform {
            let value = JS_Eval(
                core.context,
                jsCode,
                jsCode.utf8.count,
                options.filename,
                options.rawFlags
            )
            return JSValue(core, value: value)
        }
    }

    /// Evaluate JavaScript and throw on exception.
    @discardableResult
    public func evaluate(_ jsCode: String, options: EvalOptions = EvalOptions()) throws -> JSValue {
        let value = eval(jsCode, options: options)
        if value.isException {
            throw JSError.exception(exceptionMessage() ?? "JavaScript exception")
        }
        return value
    }

    public func evaluateResult(_ jsCode: String, options: EvalOptions = EvalOptions()) -> Result<JSValue, JSError> {
        Result { try evaluate(jsCode, options: options) }
            .mapError { ($0 as? JSError) ?? .exception(String(describing: $0)) }
    }

    // MARK: - Bytecode

    /// Compile JavaScript to QuickJS bytecode.
    public func compile(_ jsCode: String, options: EvalOptions = EvalOptions()) throws -> Data {
        try runtime.perform {
            var compileOptions = options
            compileOptions.compileOnly = true
            let object = JS_Eval(
                core.context,
                jsCode,
                jsCode.utf8.count,
                compileOptions.filename,
                compileOptions.rawFlags
            )
            defer { JS_FreeValue(core.context, object) }
            if JS_IsException(object) != 0 {
                throw JSError.exception(exceptionMessage() ?? "Compile failed")
            }

            var size = 0
            guard let buffer = JS_WriteObject(core.context, &size, object, Int32(JS_WRITE_OBJ_BYTECODE)) else {
                throw JSError.exception(exceptionMessage() ?? "Bytecode serialization failed")
            }
            defer { js_free(core.context, buffer) }
            return Data(bytes: buffer, count: size)
        }
    }

    /// Load and evaluate previously compiled bytecode.
    @discardableResult
    public func evalBytecode(_ data: Data) throws -> JSValue {
        try runtime.perform {
            let value: JSCValue = data.withUnsafeBytes { raw in
                guard let base = raw.bindMemory(to: UInt8.self).baseAddress else {
                    return JSCValue.undefined
                }
                return JS_ReadObject(core.context, base, data.count, Int32(JS_READ_OBJ_BYTECODE))
            }
            if JS_IsException(value) != 0 {
                throw JSError.exception(exceptionMessage() ?? "Bytecode load failed")
            }

            if value.tag == Int64(JS_TAG_MODULE) {
                if JS_ResolveModule(core.context, value) < 0 {
                    JS_FreeValue(core.context, value)
                    throw JSError.exception(exceptionMessage() ?? "Module resolve failed")
                }
            }

            let result = JS_EvalFunction(core.context, value)
            let jsValue = JSValue(core, value: result)
            if jsValue.isException {
                throw JSError.exception(exceptionMessage() ?? "Bytecode eval failed")
            }
            return jsValue
        }
    }

    // MARK: - Call

    @discardableResult
    public func call(function: JSValue, argc: Int, argv: JSCValuePointer?) -> JSValue {
        runtime.perform {
            let result = JS_Call(core.context, function.cValue, .undefined, Int32(argc), argv)
            return JSValue(core, value: result)
        }
    }

    // MARK: - Globals

    public func setGlobalProperty<T: ConvertibleWithJavascript>(name: String, value: T) {
        runtime.perform {
            let globalObj = JS_GetGlobalObject(core.context)
            defer { JS_FreeValue(core.context, globalObj) }
            JS_SetPropertyStr(core.context, globalObj, name, value.jsValue(self).steal())
        }
    }

    public func getGlobalProperty(_ name: String) -> JSValue {
        runtime.perform {
            let globalObj = JS_GetGlobalObject(core.context)
            defer { JS_FreeValue(core.context, globalObj) }
            return JSValue(core, value: JS_GetPropertyStr(core.context, globalObj, name))
        }
    }

    public func hasGlobalProperty(name: String) -> Bool {
        let value = getGlobalProperty(name)
        return !value.isException && JS_IsUndefined(value.cValue) == 0
    }

    // MARK: - Module

    private func loadModule(_ cModule: OpaquePointer) {
        modules[cModule]?.load()
    }

    private static let moduleInit: JSModuleInitFunction = { ctx, m in
        guard let ctx = ctx, let m = m, let context = ctx.opaqueContext else {
            return -1
        }
        context.loadModule(m)
        return 0
    }

    @discardableResult
    public func module<T: JSModule>(_ name: String, @ModuleBuilder _ propertyBuilder: () -> JSModuleProperty) -> T? {
        runtime.perform {
            guard let cModule = JS_NewCModule(core.context, name, JSContext.moduleInit) else {
                return nil
            }
            let module = T(self, module: cModule, name: name, propertyBuilder)
            modules[cModule] = module
            return module
        }
    }

    // MARK: - Jobs / Event loop

    public func flushPendingJobs() {
        runtime.perform {
            var ctx: OpaquePointer?
            while JS_ExecutePendingJob(runtime.jsInstance, &ctx) > 0 {}
        }
    }

    /// Install `setTimeout` / `clearTimeout` / `setInterval` / `clearInterval` globals.
    public func enableEventLoop() {
        runtime.perform {
            guard !timersInstalled else { return }
            JSTimers.install(on: self)
            timersInstalled = true
        }
    }

    /// Backward-compatible alias of `enableEventLoop()`, also exposes a `Runloop` module.
    public func enableRunloop() {
        enableEventLoop()
        runtime.perform {
            let _: JSModule? = module("Runloop") {
                JSModuleFunction("setTimeout", argc: 2) { [weak self] _, _, argc, argv in
                    guard let self = self else { return nil }
                    return JSTimers.scheduleTimeout(on: self, argc: argc, argv: argv)
                        .map { $0 as ConvertibleWithJavascript }
                }
                JSModuleFunction("clearTimeout", argc: 1) { [weak self] _, _, argc, argv in
                    guard let self = self else { return nil }
                    JSTimers.clearTimeout(on: self, argc: argc, argv: argv)
                    return nil
                }
                JSModuleFunction("setInterval", argc: 2) { [weak self] _, _, argc, argv in
                    guard let self = self else { return nil }
                    return JSTimers.scheduleInterval(on: self, argc: argc, argv: argv)
                        .map { $0 as ConvertibleWithJavascript }
                }
                JSModuleFunction("clearInterval", argc: 1) { [weak self] _, _, argc, argv in
                    guard let self = self else { return nil }
                    JSTimers.clearTimeout(on: self, argc: argc, argv: argv)
                    return nil
                }
            }
        }
    }

    // MARK: - Exception

    public func getException() -> String? {
        runtime.perform { exceptionMessage() }
    }

    func exceptionMessage() -> String? {
        let exception = JS_GetException(core.context)
        defer { JS_FreeValue(core.context, exception) }

        let description = String(self, value: exception)
        if JS_IsError(core.context, exception) == 0 {
            return description
        }

        let stack = JS_GetPropertyStr(core.context, exception, "stack")
        defer { JS_FreeValue(core.context, stack) }
        let stackStr = String(self, value: stack)

        switch (description, stackStr) {
        case (nil, nil): return nil
        case (let d?, nil): return d
        case (nil, let s?): return s
        case (let d?, let s?): return "\(d)\n\(s)"
        }
    }
}
