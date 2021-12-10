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

struct JSRunloopTimer {
    var context: OpaquePointer
    var argc: Int32
    var argv: UnsafeMutablePointer<JSValue>
}

final class JSRunloop : JSModule {
    var runloop: RunLoop

    required init(_ context: JSContextWrapper, module: OpaquePointer, name: String, @ModuleBuilder _ propertyBuilder: () -> JSModuleProperty) {
        runloop = RunLoop.current
        super.init(context, module: module, name: "Runloop", propertyBuilder)
        self.addObserver()
        self.registerFunctions()
    }
    
    func registerFunctions() {
        self.function("setTimeout", argc: 2) { [weak self] context, this, argc, argv in
            guard let self = self else { return nil }
            self.scheduleTimer(argc, argv)
            return nil
        }
    }
    
    func addObserver() {
        let observer = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, CFRunLoopActivity.allActivities.rawValue, true, 0) { [weak self] ob, ac in
            guard let self = self else {
                return
            }
            if ac == .beforeTimers {
                self.context?.opaque?.flushPendingJobs()
            }
        }
        let cfRunloop = self.runloop.getCFRunLoop()
        CFRunLoopAddObserver(cfRunloop, observer, .defaultMode)
    }
    
    func scheduleTimer(_ argc: Int, _ argv: JSCValuePointer?) {
        guard let context = self.context,
              let arguments = argv,
              argc >= 2
        else {
            return
        }
        
        let function = JSValue(context, value: arguments[0], dup: true)
        if !function.isFunction {
            return
        }
        
        let interval = JSValue(context, value: arguments[1], dup: true).double ?? 0

        if #available(macOS 10.12, *) {
            let timer = Timer(timeInterval: interval/1000, repeats: false) { timer in
                context.opaque?.call(function: function, argc: argc-2, argv: arguments+2)
            }
            self.runloop.add(timer, forMode: .default)
        } else {
            assert(false, "Upgrade your mac version")
        }
    }
}
