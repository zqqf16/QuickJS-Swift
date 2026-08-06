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

final class JSRunloop : JSModule {
    var runloop: RunLoop
    private var observer: CFRunLoopObserver?
    private var pendingTimers: [Timer] = []

    required init(_ context: JSContextWrapper, module: OpaquePointer, name: String, @ModuleBuilder _ propertyBuilder: () -> JSModuleProperty) {
        runloop = RunLoop.current
        super.init(context, module: module, name: "Runloop", propertyBuilder)
        self.addObserver()
        self.registerFunctions()
    }

    deinit {
        if let observer = observer {
            CFRunLoopRemoveObserver(runloop.getCFRunLoop(), observer, .defaultMode)
        }
        pendingTimers.forEach { $0.invalidate() }
        pendingTimers.removeAll()
    }
    
    func registerFunctions() {
        self.function("setTimeout", argc: 2) { [weak self] context, this, argc, argv in
            guard let self = self else { return nil }
            self.scheduleTimer(argc, argv)
            return nil
        }
    }
    
    func addObserver() {
        let observer = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, CFRunLoopActivity.beforeTimers.rawValue, true, 0) { [weak self] _, activity in
            guard let self = self, activity == .beforeTimers else {
                return
            }
            self.context?.opaque?.flushPendingJobs()
        }
        self.observer = observer
        CFRunLoopAddObserver(self.runloop.getCFRunLoop(), observer, .defaultMode)
    }
    
    func scheduleTimer(_ argc: Int, _ argv: JSCValuePointer?) {
        guard let context = self.context,
              let arguments = argv,
              argc >= 2
        else {
            return
        }
        
        let function = JSValue(context, value: arguments[0], dup: true)
        guard function.isFunction else {
            return
        }
        
        let intervalMs = JSValue(context, value: arguments[1]).double ?? 0
        let extraArgc = max(argc - 2, 0)

        // Retain callback arguments: argv becomes invalid after the native call returns.
        var retainedArgs: [JSValue] = []
        retainedArgs.reserveCapacity(extraArgc)
        for index in 0..<extraArgc {
            retainedArgs.append(JSValue(context, value: arguments[2 + index], dup: true))
        }

        let timer = Timer(timeInterval: intervalMs / 1000, repeats: false) { [weak self] timer in
            defer {
                self?.pendingTimers.removeAll { $0 === timer }
            }

            if retainedArgs.isEmpty {
                context.opaque?.call(function: function, argc: 0, argv: nil)
            } else {
                var cArgs = retainedArgs.map { $0.cValue }
                _ = cArgs.withUnsafeMutableBufferPointer { buffer in
                    context.opaque?.call(function: function, argc: extraArgc, argv: buffer.baseAddress)
                }
            }
        }
        pendingTimers.append(timer)
        self.runloop.add(timer, forMode: .default)
    }
}
