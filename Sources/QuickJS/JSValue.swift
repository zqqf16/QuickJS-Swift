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

public typealias JSCValue = QuickJSC.JSValue
public typealias JSCValuePointer = UnsafeMutablePointer<JSCValue>

// MARK: - JSValue

extension JSCValue {
    static var null: JSCValue {
        return JSCValue(u: JSValueUnion(int32: 0), tag: Int64(JS_TAG_NULL))
    }
    
    static var undefined: JSCValue {
        return JSCValue(u: JSValueUnion(int32: 0), tag: Int64(JS_TAG_UNDEFINED))
    }
}

public class JSValue {
    var cValue: JSCValue
    var context: JSContextWrapper?
    var autoFree: Bool = true

    required init(_ context: JSContextWrapper?, value: JSCValue, dup: Bool = false, autoFree: Bool = true) {
        self.context = context
        if dup {
            self.cValue = self.context!.dup(value)
        }
        self.cValue = value
        self.autoFree = autoFree
    }
    
    func setOpaque<T: AnyObject>(_ obj: T) {
        let ptr = Unmanaged<T>.passUnretained(obj).toOpaque()
        JS_SetOpaque(cValue, ptr)
    }
    
    func getOpaque<T: AnyObject>() -> T? {
        if let ptr = JS_GetOpaque(cValue, 1) {
            return Unmanaged<T>.fromOpaque(ptr).takeUnretainedValue()
        }
        return nil
    }
    
    deinit {
        if autoFree {
            context?.free(cValue)
        }
    }
}

extension JSValue {
    static var undefined: JSValue {
        return JSValue(nil, value: .undefined)
    }
    static var null: JSValue {
        return JSValue(nil, value: .null)
    }
}

extension JSValue {
    var isFunction: Bool {
        guard let context = context?.context else { return false }
        return JS_IsFunction(context, cValue) != 0
    }
    
    var isException: Bool {
        return JS_IsException(cValue) != 0
    }
    
    func getValue<T:ConvertibleWithJavascript>() -> T? {
        return context != nil ? T(context!, value: cValue) : nil
    }
    
    var double: Double? {
        guard self.context != nil else { return nil }
        return self.getValue()
    }
    
    var int: Int? {
        guard self.context != nil else { return nil }
        return self.getValue()
    }
    
    var string: String? {
        guard self.context != nil else { return nil }
        return self.getValue()
    }
    
    var error: JSError? {
        guard self.context != nil else { return nil }
        return self.getValue()
    }
}

// MARK: Swift Types

public protocol ConvertibleWithJavascript {
    init?(_ context: JSContextWrapper, value: JSCValue)
    func jsValue(_ context: JSContextWrapper) -> JSValue
}

extension ConvertibleWithJavascript {
    public func jsValue(_ context: JSContextWrapper) -> JSValue {
        return .undefined
    }
}

extension String: ConvertibleWithJavascript {
    public init?(_ context: JSContextWrapper, value: JSCValue) {
        if let cString = JS_ToCString(context.context, value) {
            self.init(cString: cString)
            JS_FreeCString(context.context, cString)
        } else {
            return nil
        }
    }
    
    public func jsValue(_ context: JSContextWrapper) -> JSValue {
        let value = JS_NewString(context.context, self)
        return JSValue(context, value: value)
    }
}

extension Int32: ConvertibleWithJavascript {
    public init?(_ context: JSContextWrapper, value: JSCValue) {
        if JS_IsNumber(value) == 0 {
            return nil
        }
        
        var pres: Int32 = 0
        if JS_ToInt32(context.context, &pres, value) < 0 {
            return nil
        }
        self = pres
    }
    
    public func jsValue(_ context: JSContextWrapper) -> JSValue {
        let value = JS_NewInt32(context.context, self)
        return JSValue(context, value: value)
    }
}

extension UInt32: ConvertibleWithJavascript {
    public init?(_ context: JSContextWrapper, value: JSCValue) {
        if JS_IsNumber(value) == 0 {
            return nil
        }
        
        var pres: UInt32 = 0
        if JS_ToUint32(context.context, &pres, value) < 0 {
            return nil
        }
        self = pres
    }
    
    public func jsValue(_ context: JSContextWrapper) -> JSValue {
        let value = JS_NewUint32(context.context, self)
        return JSValue(context, value: value)
    }
}

extension Int64: ConvertibleWithJavascript {
    public init?(_ context: JSContextWrapper, value: JSCValue) {
        if JS_IsNumber(value) == 0 {
            return nil
        }
        
        var pres: Int64 = 0
        if JS_ToInt64(context.context, &pres, value) < 0 {
            return nil
        }
        self = pres
    }
    
    public func jsValue(_ context: JSContextWrapper) -> JSValue {
        let value = JS_NewInt64(context.context, self)
        return JSValue(context, value: value)
    }
}

extension Int: ConvertibleWithJavascript {
    public init?(_ context: JSContextWrapper, value: JSCValue) {
        guard let valueIn64 = Int64(context, value: value) else {
            return nil
        }
        self = .init(valueIn64)
    }
    
    public func jsValue(_ context: JSContextWrapper) -> JSValue {
        return Int64(self).jsValue(context)
    }
}

extension UInt: ConvertibleWithJavascript {
    public init?(_ context: JSContextWrapper, value: JSCValue) {
        guard let valueIn32 = UInt32(context, value: value) else {
            return nil
        }
        self = .init(valueIn32)
    }
    
    public func jsValue(_ context: JSContextWrapper) -> JSValue {
        return UInt32(self).jsValue(context)
    }
}

extension Double: ConvertibleWithJavascript {
    public init?(_ context: JSContextWrapper, value: JSCValue) {
        if JS_IsNumber(value) == 0 {
            return nil
        }
        
        var pres: Double = 0
        if JS_ToFloat64(context.context, &pres, value) < 0 {
            return nil
        }
        self = pres
    }
    
    public func jsValue(_ context: JSContextWrapper) -> JSValue {
        let value = JS_NewFloat64(context.context, self)
        return JSValue(context, value: value)
    }
}

extension Array: ConvertibleWithJavascript where Element: ConvertibleWithJavascript {
    public init?(_ context: JSContextWrapper, value: JSCValue) {
        guard JS_IsObject(value) != 0 else {
            return nil
        }
        
        let length = JS_GetPropertyStr(context.context, value, "length")
        defer {
            context.free(length)
        }
        var size: UInt64 = 0
        if JS_ToIndex(context.context, &size, value) < 0 {
            return nil
        }
        
        self = []
        for index in 0..<size {
            let v = JS_GetPropertyUint32(context.context, value, UInt32(index))
            if let ele = Element(context, value: v) {
                self.append(ele)
            } else {
                return nil
            }
        }
    }
    
    public func jsValue(_ context: JSContextWrapper) -> JSValue {
        fatalError("TODO")
    }
}

public enum JSError: Error, ConvertibleWithJavascript {
    case exception
    
    public init?(_ context: JSContextWrapper, value: JSCValue) {
        guard JS_IsException(value) != 0 else {
            return nil
        }
        self = .exception
    }
}
