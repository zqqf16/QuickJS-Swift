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

private final class InterruptBox {
    var handler: () -> Bool
    init(_ handler: @escaping () -> Bool) { self.handler = handler }
}

private final class RejectionBox {
    var lastMessage: String?
}

/// Ref-counts process-global QuickJS std worker hooks and helper flags.
private enum StdModulesGate {
    private static let lock = NSLock()
    private static var refCount = 0
    private static var helpersByRuntime = [UnsafeMutableRawPointer: Bool]()

    static func acquire(builder: @escaping @convention(c) (OpaquePointer?) -> OpaquePointer?) {
        lock.lock()
        defer { lock.unlock() }
        refCount += 1
        js_std_set_worker_new_context_func(builder)
    }

    static func release() {
        lock.lock()
        defer { lock.unlock() }
        refCount = max(refCount - 1, 0)
        if refCount == 0 {
            js_std_set_worker_new_context_func(nil)
        }
    }

    static func setHelpersEnabled(_ runtime: OpaquePointer, _ enabled: Bool) {
        lock.lock()
        helpersByRuntime[UnsafeMutableRawPointer(runtime)] = enabled
        lock.unlock()
    }

    static func helpersEnabled(_ runtime: OpaquePointer) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return helpersByRuntime[UnsafeMutableRawPointer(runtime)] ?? true
    }

    static func removeHelpersFlag(_ runtime: OpaquePointer) {
        lock.lock()
        helpersByRuntime.removeValue(forKey: UnsafeMutableRawPointer(runtime))
        lock.unlock()
    }
}

/// Owns a QuickJS runtime.
///
/// - Important: QuickJS is single-threaded. Always access the runtime and its
///   contexts through `perform` / the associated `eventLoop`, or via the
///   public `JSContext` APIs which already serialize work.
public final class JSRuntime {
    let jsInstance: OpaquePointer
    public let eventLoop: JSEventLoop
    public let options: JSRuntimeOptions

    private let interruptBox: InterruptBox?
    private let rejectionBox: RejectionBox
    private let enableStdModules: Bool
    private var isShutdown = false

    private static let cInterrupt: @convention(c) (OpaquePointer?, UnsafeMutableRawPointer?) -> Int32 = { _, opaque in
        guard let opaque = opaque else { return 0 }
        let box = Unmanaged<InterruptBox>.fromOpaque(opaque).takeUnretainedValue()
        return box.handler() ? 1 : 0
    }

    private static let cRejection: @convention(c) (OpaquePointer?, JSCValue, JSCValue, Int32, UnsafeMutableRawPointer?) -> Void = { ctx, _, reason, isHandled, opaque in
        guard isHandled == 0, let opaque = opaque, let ctx = ctx else { return }
        let box = Unmanaged<RejectionBox>.fromOpaque(opaque).takeUnretainedValue()
        if let cString = JS_ToCString(ctx, reason) {
            box.lastMessage = String(cString: cString)
            JS_FreeCString(ctx, cString)
        } else {
            let exception = JS_GetException(ctx)
            JS_FreeValue(ctx, exception)
            box.lastMessage = "Unhandled promise rejection"
        }
    }

    private static let contextBuilder: @convention(c) (OpaquePointer?) -> OpaquePointer? = { rt in
        guard let rt = rt, let ctx = JS_NewContext(rt) else { return nil }
        _ = js_init_module_std(ctx, "std")
        _ = js_init_module_os(ctx, "os")
        if StdModulesGate.helpersEnabled(rt) {
            js_std_add_helpers(ctx, -1, nil)
        }
        return ctx
    }

    public convenience init?() {
        self.init(options: JSRuntimeOptions())
    }

    public init?(options: JSRuntimeOptions = JSRuntimeOptions(), eventLoop: JSEventLoop? = nil) {
        guard let runtime = JS_NewRuntime() else { return nil }

        self.jsInstance = runtime
        self.options = options
        self.enableStdModules = options.enableStdModules
        self.eventLoop = eventLoop ?? DispatchEventLoop()
        self.rejectionBox = RejectionBox()

        QuickJSClass.register(on: runtime)

        if let limit = options.memoryLimit {
            JS_SetMemoryLimit(runtime, limit)
        }

        if let handler = options.interruptHandler {
            let box = InterruptBox(handler)
            self.interruptBox = box
            JS_SetInterruptHandler(runtime, JSRuntime.cInterrupt, Unmanaged.passUnretained(box).toOpaque())
        } else {
            self.interruptBox = nil
        }

        JS_SetHostPromiseRejectionTracker(
            runtime,
            JSRuntime.cRejection,
            Unmanaged.passUnretained(rejectionBox).toOpaque()
        )

        if options.enableStdModules {
            StdModulesGate.setHelpersEnabled(runtime, options.enableHelpers)
            StdModulesGate.acquire(builder: JSRuntime.contextBuilder)
            js_std_init_handlers(runtime)
            JS_SetModuleLoaderFunc2(runtime, nil, js_module_loader, js_module_check_attributes, nil)
        }
    }

    deinit {
        shutdown()
    }

    /// Consume the last unhandled promise rejection message, if any.
    public func takeUnhandledPromiseRejection() -> String? {
        perform {
            let message = rejectionBox.lastMessage
            rejectionBox.lastMessage = nil
            return message
        }
    }

    func shutdown() {
        eventLoop.sync {
            guard !isShutdown else { return }
            isShutdown = true
            JS_SetInterruptHandler(jsInstance, nil, nil)
            JS_SetHostPromiseRejectionTracker(jsInstance, nil, nil)
            if enableStdModules {
                js_std_free_handlers(jsInstance)
                StdModulesGate.release()
                StdModulesGate.removeHelpersFlag(jsInstance)
            }
            JS_FreeRuntime(jsInstance)
        }
    }

    public func perform<T>(_ body: () throws -> T) rethrows -> T {
        try eventLoop.sync(body)
    }

    public func async(_ body: @escaping () -> Void) {
        eventLoop.async(body)
    }

    public func createContext() -> JSContext? {
        perform {
            let ctx: OpaquePointer?
            if enableStdModules {
                ctx = JSRuntime.contextBuilder(jsInstance)
            } else {
                ctx = JS_NewContext(jsInstance)
                if options.enableHelpers, let ctx = ctx {
                    js_std_add_helpers(ctx, -1, nil)
                }
            }
            guard let context = ctx else { return nil }
            return JSContext(self, context: context)
        }
    }
}
