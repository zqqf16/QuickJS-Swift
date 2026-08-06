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

    init(_ handler: @escaping () -> Bool) {
        self.handler = handler
    }
}

/// Owns a QuickJS runtime.
///
/// - Important: QuickJS is single-threaded. Always access the runtime and its
///   contexts through `perform` / the associated `eventLoop`, or via the
///   public `JSContext` APIs which already serialize work.
public class JSRuntime {
    public private(set) var jsInstance: OpaquePointer
    public let eventLoop: JSEventLoop
    public let options: JSRuntimeOptions

    private let interruptBox: InterruptBox?
    private let enableStdModules: Bool

    private static let cInterrupt: @convention(c) (OpaquePointer?, UnsafeMutableRawPointer?) -> Int32 = { _, opaque in
        guard let opaque = opaque else { return 0 }
        let box = Unmanaged<InterruptBox>.fromOpaque(opaque).takeUnretainedValue()
        return box.handler() ? 1 : 0
    }

    private static let contextBuilder: @convention(c) (OpaquePointer?) -> OpaquePointer? = { rt in
        guard let rt = rt, let ctx = JS_NewContext(rt) else {
            return nil
        }
        // Workers always get std helpers when this builder is installed.
        _ = js_init_module_std(ctx, "std")
        _ = js_init_module_os(ctx, "os")
        js_std_add_helpers(ctx, -1, nil)
        return ctx
    }

    public convenience init?() {
        self.init(options: JSRuntimeOptions())
    }

    public init?(options: JSRuntimeOptions = JSRuntimeOptions(), eventLoop: JSEventLoop? = nil) {
        guard let runtime = JS_NewRuntime() else {
            return nil
        }

        self.jsInstance = runtime
        self.options = options
        self.enableStdModules = options.enableStdModules
        self.eventLoop = eventLoop ?? DispatchEventLoop()

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

        if options.enableStdModules {
            js_std_set_worker_new_context_func(JSRuntime.contextBuilder)
            js_std_init_handlers(runtime)
            JS_SetModuleLoaderFunc2(runtime, nil, js_module_loader, js_module_check_attributes, nil)
        }
    }

    deinit {
        JS_SetInterruptHandler(jsInstance, nil, nil)
        if enableStdModules {
            js_std_free_handlers(jsInstance)
        }
        JS_FreeRuntime(jsInstance)
    }

    /// Run work on the runtime's serial event loop.
    public func perform<T>(_ body: () throws -> T) rethrows -> T {
        try eventLoop.sync(body)
    }

    /// Schedule work on the runtime's serial event loop.
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
            }
            guard let context = ctx else {
                return nil
            }
            return JSContext(self, context: context)
        }
    }
}
