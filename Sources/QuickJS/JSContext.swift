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

/// A JavaScript execution context within a `JSRuntime`.
///
/// QuickJS is single-threaded; every public method here serializes its work
/// through the owning runtime's `JSEventLoop`. Instances are therefore safe to
/// share across threads and are marked `@unchecked Sendable`.
public class JSContext: @unchecked Sendable {
    // Declaration order matters: deinit runs in reverse.
    // Free the JS context (`core`) while Swift host/module functions are still alive,
    // then drop those Swift objects, and finally release the runtime.
    public let runtime: JSRuntime
    var hostFunctions: [JSFunction] = []
    private var modules: [OpaquePointer: JSModule] = [:]
    private var timersInstalled = false
    private var runloopModuleInstalled = false
    let core: JSContextWrapper

    init?(_ runtime: JSRuntime, context: OpaquePointer) {
        self.runtime = runtime
        self.core = JSContextWrapper(context)
        self.core.opaque = self
    }

    deinit {
        runtime.perform {
            JSTimers.shutdown(for: self)
            core.opaque = nil
            // Free the C context while Swift host/module functions are still alive.
            // Do this explicitly: an extra Swift retain of `core` must not delay
            // FreeContext until after `runtime` is released.
            core.freeContext()
        }
        // Property teardown: modules / hostFunctions, then runtime.
    }

    public enum EvalType: Int32 {
        case global = 0
        case module = 1
    }

    /// Materialize a NUL-terminated UTF-8 buffer once and reuse it for both the
    /// C pointer and the byte length, instead of bridging the `String` and
    /// walking `.utf8.count` as two separate passes.
    private func jsEval(_ jsCode: String, options: EvalOptions) -> JSCValue {
        let utf8 = jsCode.utf8CString
        return utf8.withUnsafeBufferPointer { buffer in
            JS_Eval(core.context, buffer.baseAddress, buffer.count - 1, options.filename, options.rawFlags)
        }
    }

    // MARK: - Eval

    @discardableResult
    public func eval(_ jsCode: String, type: EvalType = .global) -> JSValue {
        eval(jsCode, options: EvalOptions(type: type))
    }

    /// Evaluate `jsCode` without throwing. Exceptions are surfaced as a
    /// returned `JSValue` whose `isException` is `true` (see `error`).
    @discardableResult
    public func eval(_ jsCode: String, options: EvalOptions) -> JSValue {
        runtime.perform {
            let result = makeValue(jsEval(jsCode, options: options))
            if !result.isException, runtime.options.flushJobsAfterEval {
                _ = try? flushPendingJobsUnlocked()
            }
            return result
        }
    }

    /// Evaluate `jsCode` and throw a `JSError` on failure.
    @discardableResult
    public func evaluate(_ jsCode: String, options: EvalOptions = EvalOptions()) throws -> JSValue {
        try runtime.perform {
            let result = makeValue(jsEval(jsCode, options: options))
            if let error = result.cachedError {
                throw error
            }
            if runtime.options.flushJobsAfterEval {
                try flushPendingJobsUnlocked()
            }
            return result
        }
    }

    public func evaluateResult(_ jsCode: String, options: EvalOptions = EvalOptions()) -> Result<JSValue, JSError> {
        Result { try evaluate(jsCode, options: options) }
            .mapError { ($0 as? JSError) ?? .exception(String(describing: $0)) }
    }

    // MARK: - Bytecode

    public func compile(_ jsCode: String, options: EvalOptions = EvalOptions()) throws -> Data {
        try runtime.perform {
            var compileOptions = options
            compileOptions.compileOnly = true
            let object = jsEval(jsCode, options: compileOptions)
            defer { JS_FreeValue(core.context, object) }
            if JS_IsException(object) != 0 {
                throw mapException()
            }

            var size = 0
            guard let buffer = JS_WriteObject(core.context, &size, object, Int32(JS_WRITE_OBJ_BYTECODE)) else {
                throw mapException()
            }
            defer { js_free(core.context, buffer) }
            return Data(bytes: buffer, count: size)
        }
    }

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
                throw mapException()
            }

            if value.tag == Int64(JS_TAG_MODULE) {
                if JS_ResolveModule(core.context, value) < 0 {
                    JS_FreeValue(core.context, value)
                    throw mapException()
                }
            }

            let result = makeValue(JS_EvalFunction(core.context, value))
            if let error = result.cachedError {
                throw error
            }
            if runtime.options.flushJobsAfterEval {
                try flushPendingJobsUnlocked()
            }
            return result
        }
    }

    // MARK: - Call

    @discardableResult
    public func call(_ function: JSValue, this: JSValue? = nil, arguments: [JSValue] = []) -> JSValue {
        runtime.perform {
            let thisValue = this?.cValue ?? JSCValue.undefined
            var args = arguments.map { $0.cValue }
            let result: JSCValue
            if args.isEmpty {
                result = JS_Call(core.context, function.cValue, thisValue, 0, nil)
            } else {
                result = args.withUnsafeMutableBufferPointer { buffer in
                    JS_Call(core.context, function.cValue, thisValue, Int32(buffer.count), buffer.baseAddress)
                }
            }
            let jsValue = makeValue(result)
            if !jsValue.isException, runtime.options.flushJobsAfterEval {
                _ = try? flushPendingJobsUnlocked()
            }
            return jsValue
        }
    }

    @discardableResult
    public func call(_ function: JSValue, this: JSValue? = nil, converting arguments: [ConvertibleWithJavascript]) -> JSValue {
        let jsArgs = arguments.map { $0.jsValue(self) }
        return call(function, this: this, arguments: jsArgs)
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
            return makeValue(JS_GetPropertyStr(core.context, globalObj, name))
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

    public func flushPendingJobs() throws {
        _ = try runtime.perform {
            try flushPendingJobsUnlocked()
        }
    }

    @discardableResult
    func flushPendingJobsUnlocked() throws -> Int {
        var executed = 0
        var ctx: OpaquePointer?
        while true {
            let status = JS_ExecutePendingJob(runtime.jsInstance, &ctx)
            if status == 0 {
                break
            }
            if status < 0 {
                if let ctx = ctx, let jobContext = ctx.opaqueContext {
                    throw jobContext.mapException()
                }
                throw mapException()
            }
            executed += 1
        }
        return executed
    }

    public func enableEventLoop() {
        runtime.perform {
            guard !timersInstalled else { return }
            JSTimers.install(on: self)
            timersInstalled = true
        }
    }

    public func enableRunloop() {
        enableEventLoop()
        runtime.perform {
            guard !runloopModuleInstalled else { return }
            let _: JSModule? = module("Runloop") {
                JSModuleFunction("setTimeout", argc: 2) { [weak self] _, _, argc, argv in
                    guard let self = self else { return nil }
                    return JSTimers.scheduleTimeout(on: self, argc: argc, argv: argv)
                }
                JSModuleFunction("clearTimeout", argc: 1) { [weak self] _, _, argc, argv in
                    guard let self = self else { return nil }
                    JSTimers.clearTimeout(on: self, argc: argc, argv: argv)
                    return nil
                }
                JSModuleFunction("setInterval", argc: 2) { [weak self] _, _, argc, argv in
                    guard let self = self else { return nil }
                    return JSTimers.scheduleInterval(on: self, argc: argc, argv: argv)
                }
                JSModuleFunction("clearInterval", argc: 1) { [weak self] _, _, argc, argv in
                    guard let self = self else { return nil }
                    JSTimers.clearTimeout(on: self, argc: argc, argv: argv)
                    return nil
                }
            }
            runloopModuleInstalled = true
        }
    }

    // MARK: - Exception

    public func getException() -> String? {
        runtime.perform { exceptionMessage() }
    }

    func mapException() -> JSError {
        let message = exceptionMessage() ?? "JavaScript exception"
        if message.contains("interrupted") {
            return .interrupted
        }
        return .exception(message)
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

    func clearException() {
        let exception = JS_GetException(core.context)
        JS_FreeValue(core.context, exception)
    }
}
