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
        JSCValue(u: JSValueUnion(uint64: 0), tag: Int64(JS_TAG_NULL))
    }

    static var undefined: JSCValue {
        JSCValue(u: JSValueUnion(uint64: 0), tag: Int64(JS_TAG_UNDEFINED))
    }
}

public class JSValue {
    var cValue: JSCValue
    var context: JSContextWrapper?
    var autoFree: Bool = true

    required init(_ context: JSContextWrapper?, value: JSCValue, dup: Bool = false, autoFree: Bool = true) {
        self.context = context
        self.autoFree = autoFree
        if dup {
            precondition(context != nil, "dup requires a context")
            self.cValue = context!.dup(value)
        } else {
            self.cValue = value
        }
    }

    /// Transfer ownership of the underlying `JSValue` to the caller.
    func steal() -> JSCValue {
        autoFree = false
        return cValue
    }

    func setOpaqueUnretained<T: AnyObject>(_ obj: T, classId: JSClassID = QuickJSClass.functionDataID) {
        let ptr = Unmanaged<T>.passUnretained(obj).toOpaque()
        JS_SetOpaque(cValue, ptr)
    }

    func getOpaque<T: AnyObject>(classId: JSClassID = QuickJSClass.functionDataID) -> T? {
        guard let ptr = JS_GetOpaque(cValue, classId) else {
            return nil
        }
        return Unmanaged<T>.fromOpaque(ptr).takeUnretainedValue()
    }

    deinit {
        if autoFree {
            context?.free(cValue)
        }
    }
}

extension JSValue {
    public static var undefined: JSValue { JSValue(nil, value: .undefined) }
    public static var null: JSValue { JSValue(nil, value: .null) }
}

extension JSValue {
    public var jsContext: JSContext? { context?.opaque }

    public var isFunction: Bool {
        guard let ctx = context?.context else { return false }
        return JS_IsFunction(ctx, cValue) != 0
    }

    public var isException: Bool { JS_IsException(cValue) != 0 }
    public var isBool: Bool { JS_IsBool(cValue) != 0 }
    public var isNumber: Bool { JS_IsNumber(cValue) != 0 }
    public var isString: Bool { JS_IsString(cValue) != 0 }

    public var isArray: Bool {
        guard let ctx = context?.context else { return false }
        return JS_IsArray(ctx, cValue) != 0
    }

    public var isObject: Bool { JS_IsObject(cValue) != 0 }

    public func getValue<T: ConvertibleWithJavascript>() -> T? {
        guard let jsContext = jsContext else { return nil }
        return T(jsContext, value: cValue)
    }

    public var double: Double? { getValue() }
    public var int: Int? { getValue() }
    public var bool: Bool? { getValue() }
    public var string: String? { getValue() }
    public var date: Date? { getValue() }
    public var data: Data? { getValue() }

    public var error: JSError? {
        guard isException, let jsContext = jsContext else { return nil }
        return JSError.exception(jsContext.exceptionMessage() ?? "JavaScript exception")
    }
}

// MARK: - ConvertibleWithJavascript

public protocol ConvertibleWithJavascript {
    init?(_ context: JSContext, value: JSCValue)
    func jsValue(_ context: JSContext) -> JSValue
}

extension ConvertibleWithJavascript {
    public func jsValue(_ context: JSContext) -> JSValue {
        .undefined
    }
}

extension String: ConvertibleWithJavascript {
    public init?(_ context: JSContext, value: JSCValue) {
        guard let cString = JS_ToCString(context.core.context, value) else {
            return nil
        }
        self.init(cString: cString)
        JS_FreeCString(context.core.context, cString)
    }

    public func jsValue(_ context: JSContext) -> JSValue {
        JSValue(context.core, value: JS_NewString(context.core.context, self))
    }
}

extension Bool: ConvertibleWithJavascript {
    public init?(_ context: JSContext, value: JSCValue) {
        let result = JS_ToBool(context.core.context, value)
        if result < 0 { return nil }
        self = result != 0
    }

    public func jsValue(_ context: JSContext) -> JSValue {
        JSValue(context.core, value: JS_NewBool(context.core.context, self ? 1 : 0))
    }
}

extension Int32: ConvertibleWithJavascript {
    public init?(_ context: JSContext, value: JSCValue) {
        guard JS_IsNumber(value) != 0 else { return nil }
        var pres: Int32 = 0
        if JS_ToInt32(context.core.context, &pres, value) < 0 { return nil }
        self = pres
    }

    public func jsValue(_ context: JSContext) -> JSValue {
        JSValue(context.core, value: JS_NewInt32(context.core.context, self))
    }
}

extension UInt32: ConvertibleWithJavascript {
    public init?(_ context: JSContext, value: JSCValue) {
        guard JS_IsNumber(value) != 0 else { return nil }
        var pres: UInt32 = 0
        if JS_ToUint32(context.core.context, &pres, value) < 0 { return nil }
        self = pres
    }

    public func jsValue(_ context: JSContext) -> JSValue {
        JSValue(context.core, value: JS_NewUint32(context.core.context, self))
    }
}

extension Int64: ConvertibleWithJavascript {
    public init?(_ context: JSContext, value: JSCValue) {
        guard JS_IsNumber(value) != 0 else { return nil }
        var pres: Int64 = 0
        if JS_ToInt64(context.core.context, &pres, value) < 0 { return nil }
        self = pres
    }

    public func jsValue(_ context: JSContext) -> JSValue {
        JSValue(context.core, value: JS_NewInt64(context.core.context, self))
    }
}

extension Int: ConvertibleWithJavascript {
    public init?(_ context: JSContext, value: JSCValue) {
        guard let valueIn64 = Int64(context, value: value) else { return nil }
        self.init(valueIn64)
    }

    public func jsValue(_ context: JSContext) -> JSValue {
        Int64(self).jsValue(context)
    }
}

extension UInt: ConvertibleWithJavascript {
    public init?(_ context: JSContext, value: JSCValue) {
        guard let valueIn32 = UInt32(context, value: value) else { return nil }
        self.init(valueIn32)
    }

    public func jsValue(_ context: JSContext) -> JSValue {
        UInt32(self).jsValue(context)
    }
}

extension Double: ConvertibleWithJavascript {
    public init?(_ context: JSContext, value: JSCValue) {
        guard JS_IsNumber(value) != 0 else { return nil }
        var pres: Double = 0
        if JS_ToFloat64(context.core.context, &pres, value) < 0 { return nil }
        self = pres
    }

    public func jsValue(_ context: JSContext) -> JSValue {
        JSValue(context.core, value: JS_NewFloat64(context.core.context, self))
    }
}

extension Array: ConvertibleWithJavascript where Element: ConvertibleWithJavascript {
    public init?(_ context: JSContext, value: JSCValue) {
        guard JS_IsArray(context.core.context, value) != 0 else { return nil }

        let length = JS_GetPropertyStr(context.core.context, value, "length")
        defer { context.core.free(length) }

        var size: UInt64 = 0
        if JS_ToIndex(context.core.context, &size, length) < 0 { return nil }

        self = []
        reserveCapacity(Int(size))
        for index in 0..<size {
            let v = JS_GetPropertyUint32(context.core.context, value, UInt32(index))
            defer { context.core.free(v) }
            guard let ele = Element(context, value: v) else { return nil }
            append(ele)
        }
    }

    public func jsValue(_ context: JSContext) -> JSValue {
        let array = JS_NewArray(context.core.context)
        for (index, element) in enumerated() {
            _ = JS_SetPropertyUint32(context.core.context, array, UInt32(index), element.jsValue(context).steal())
        }
        return JSValue(context.core, value: array)
    }
}

extension Dictionary: ConvertibleWithJavascript where Key == String, Value: ConvertibleWithJavascript {
    public init?(_ context: JSContext, value: JSCValue) {
        guard JS_IsObject(value) != 0, JS_IsArray(context.core.context, value) == 0 else {
            return nil
        }

        var tab: UnsafeMutablePointer<JSPropertyEnum>?
        var len: UInt32 = 0
        if JS_GetOwnPropertyNames(context.core.context, &tab, &len, value, Int32(JS_GPN_STRING_MASK | JS_GPN_ENUM_ONLY)) != 0 {
            return nil
        }
        defer {
            if let tab = tab {
                JS_FreePropertyEnum(context.core.context, tab, len)
            }
        }

        self = [:]
        guard let tab = tab else { return }
        for i in 0..<len {
            let atom = tab[Int(i)].atom
            guard let keyCString = JS_AtomToCString(context.core.context, atom) else {
                return nil
            }
            let key = String(cString: keyCString)
            JS_FreeCString(context.core.context, keyCString)

            let prop = JS_GetProperty(context.core.context, value, atom)
            defer { context.core.free(prop) }
            guard let converted = Value(context, value: prop) else {
                return nil
            }
            self[key] = converted
        }
    }

    public func jsValue(_ context: JSContext) -> JSValue {
        let obj = JS_NewObject(context.core.context)
        for (key, value) in self {
            _ = JS_SetPropertyStr(context.core.context, obj, key, value.jsValue(context).steal())
        }
        return JSValue(context.core, value: obj)
    }
}

extension Data: ConvertibleWithJavascript {
    public init?(_ context: JSContext, value: JSCValue) {
        var size = 0
        if let ptr = JS_GetArrayBuffer(context.core.context, &size, value) {
            self.init(bytes: ptr, count: size)
            return
        }

        var offset = 0
        var length = 0
        var bytesPerElement = 0
        let buffer = JS_GetTypedArrayBuffer(context.core.context, value, &offset, &length, &bytesPerElement)
        defer { context.core.free(buffer) }
        guard JS_IsException(buffer) == 0 else { return nil }

        var bufferSize = 0
        guard let ptr = JS_GetArrayBuffer(context.core.context, &bufferSize, buffer) else {
            return nil
        }
        self.init(bytes: ptr.advanced(by: offset), count: length)
    }

    public func jsValue(_ context: JSContext) -> JSValue {
        let value: JSCValue = withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return JS_NewArrayBufferCopy(context.core.context, nil, 0)
            }
            return JS_NewArrayBufferCopy(context.core.context, base, count)
        }
        return JSValue(context.core, value: value)
    }
}

extension Date: ConvertibleWithJavascript {
    public init?(_ context: JSContext, value: JSCValue) {
        guard JS_IsObject(value) != 0 else { return nil }

        let atom = JS_NewAtom(context.core.context, "valueOf")
        defer { JS_FreeAtom(context.core.context, atom) }
        let result = JS_Invoke(context.core.context, value, atom, 0, nil)
        defer { context.core.free(result) }
        guard JS_IsException(result) == 0 else { return nil }

        var millis: Double = 0
        if JS_ToFloat64(context.core.context, &millis, result) < 0 { return nil }
        self.init(timeIntervalSince1970: millis / 1000)
    }

    public func jsValue(_ context: JSContext) -> JSValue {
        let millis = timeIntervalSince1970 * 1000
        return JSValue(context.core, value: JS_NewDate(context.core.context, millis))
    }
}

public enum JSError: Error, Equatable {
    case exception(String)
    case conversionFailed
    case interrupted

    public var message: String {
        switch self {
        case .exception(let message): return message
        case .conversionFailed: return "Value conversion failed"
        case .interrupted: return "JavaScript execution interrupted"
        }
    }
}
