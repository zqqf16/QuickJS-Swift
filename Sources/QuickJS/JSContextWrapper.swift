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

extension OpaquePointer {
    var opaqueContext: JSContext? {
        get {
            guard let ptr = JS_GetContextOpaque(self) else {
                return nil
            }
            return Unmanaged<JSContext>.fromOpaque(ptr).takeUnretainedValue()
        }
        set {
            if let jsContext = newValue {
                let ptr = Unmanaged<JSContext>.passUnretained(jsContext).toOpaque()
                JS_SetContextOpaque(self, ptr)
            } else {
                JS_SetContextOpaque(self, nil)
            }
        }
    }
}

public class JSContextWrapper {
    var context: OpaquePointer
    
    init(_ context: OpaquePointer) {
        self.context = context
    }
    
    deinit {
        JS_FreeContext(context)
    }
    
    var opaque: JSContext? {
        get {
            return context.opaqueContext
        }
        set {
            context.opaqueContext = newValue
        }
    }
}

// Alloc & Free
extension JSContextWrapper {
    func free(_ value: JSCValue) {
        JS_FreeValue(context, value)
    }
    
    func dup(_ value: JSCValue) -> JSCValue {
        return JS_DupValue(context, value)
    }
    
    func object() -> JSValue {
        let obj = JS_NewObject(context)
        return JSValue(self, value: obj)
    }
}

// MARK: Function
extension JSContextWrapper {
    func function(_ function: @escaping JSCFunctionData, argc: Int32, magic: Int32, length: Int32, data: JSCValuePointer?) -> JSCValue {
        return JS_NewCFunctionData(context, function, argc, magic, length, data)
    }
}

// MARK: Module
extension JSContextWrapper {
    func addExport(module: OpaquePointer, name: String) {
        JS_AddModuleExport(context, module, name)
    }
    
    func setExport(module: OpaquePointer, name: String, value: JSCValue) {
        JS_SetModuleExport(context, module, name, value)
    }
}
