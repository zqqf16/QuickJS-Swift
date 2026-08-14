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

// MARK: - JSValue

extension JSCValue {
    static var null: JSCValue {
        JSCValue(u: JSValueUnion(uint64: 0), tag: Int64(JS_TAG_NULL))
    }

    static var undefined: JSCValue {
        JSCValue(u: JSValueUnion(uint64: 0), tag: Int64(JS_TAG_UNDEFINED))
    }

    static var exception: JSCValue {
        JSCValue(u: JSValueUnion(uint64: 0), tag: Int64(JS_TAG_EXCEPTION))
    }
}

/// A reference-counted Swift wrapper around a QuickJS `JSValue`.
///
/// All engine calls on the wrapped value are routed through the owning
/// runtime's `JSEventLoop`, so instances may be shared across threads.
/// Marked `@unchecked Sendable` for that reason.
public class JSValue: @unchecked Sendable {
    var cValue: JSCValue
    /// Backing wrapper for host-function values that must not strongly retain `JSContext`
    /// (the context already retains those functions).
    private var storedContext: JSContextWrapper?
    /// Weak back-reference used by host functions (context already retains them).
    private weak var weakOwner: JSContext?
    /// Strong owner for values created via the public `JSContext` APIs.
    /// This is the sole retain path that keeps the C context / runtime alive.
    private var retainedOwner: JSContext?
    var autoFree: Bool = true
    /// Exception details captured when the pending runtime exception was cleared.
    private(set) var cachedError: JSError?

    var context: JSContextWrapper? {
        get { retainedOwner?.core ?? storedContext }
        set { storedContext = newValue }
    }

    required init(_ context: JSContextWrapper?, value: JSCValue, dup: Bool = false, autoFree: Bool = true) {
        self.storedContext = context
        self.autoFree = autoFree
        self.weakOwner = context?.opaque
        if dup {
            precondition(context != nil, "dup requires a context")
            self.cValue = context!.dup(value)
        } else {
            self.cValue = value
        }
    }

    convenience init(_ jsContext: JSContext, value: JSCValue, dup: Bool = false, autoFree: Bool = true) {
        // Intentionally do not retain `jsContext.core` separately; `retainedOwner`
        // already owns it and must be the only Swift retain of the wrapper.
        let owned = dup ? jsContext.core.dup(value) : value
        self.init(nil, value: owned, dup: false, autoFree: autoFree)
        self.weakOwner = jsContext
        self.retainedOwner = jsContext
    }

    public required convenience init?(_ context: JSContext, value: JSCValue) {
        self.init(context, value: value, dup: true)
    }

    func steal() -> JSCValue {
        autoFree = false
        return cValue
    }

    func setOpaqueUnretained<T: AnyObject>(_ obj: T, classId: JSClassID = QuickJSClass.functionDataID) {
        let ptr = Unmanaged<T>.passUnretained(obj).toOpaque()
        JS_SetOpaque(cValue, ptr)
    }

    func attach(owner: JSContext) {
        self.weakOwner = owner
        if retainedOwner == nil && storedContext == nil {
            storedContext = owner.core
        }
    }

    func noteException(_ error: JSError) {
        cachedError = error
    }

    deinit {
        guard autoFree else { return }
        let value = cValue
        if let owner = retainedOwner {
            owner.runtime.perform {
                owner.core.free(value)
            }
        } else if let owner = weakOwner {
            owner.runtime.perform {
                (storedContext ?? owner.core).free(value)
            }
        } else {
            storedContext?.free(value)
        }
    }
}

extension JSValue {
    public static var undefined: JSValue { JSValue(nil, value: .undefined) }
    public static var null: JSValue { JSValue(nil, value: .null) }
}

extension JSValue {
    public var jsContext: JSContext? { retainedOwner ?? weakOwner ?? context?.opaque }

    private func withEngine<T>(_ body: (JSContext) -> T) -> T? {
        guard let jsContext = jsContext else { return nil }
        return jsContext.runtime.perform {
            body(jsContext)
        }
    }

    public var isFunction: Bool {
        withEngine { JS_IsFunction($0.core.context, cValue) != 0 } ?? false
    }

    public var isException: Bool { JS_IsException(cValue) != 0 || cachedError != nil }
    public var isBool: Bool { JS_IsBool(cValue) != 0 }
    public var isNumber: Bool { JS_IsNumber(cValue) != 0 }
    public var isString: Bool { JS_IsString(cValue) != 0 }
    public var isObject: Bool { JS_IsObject(cValue) != 0 }

    public var isArray: Bool {
        withEngine { context in
            let result = JS_IsArray(context.core.context, cValue)
            if result < 0 {
                context.clearException()
                return false
            }
            return result == 1
        } ?? false
    }

    public var isDate: Bool {
        withEngine { $0.isDate(cValue) } ?? false
    }

    public func getValue<T: ConvertibleWithJavascript>() -> T? {
        withEngine { T($0, value: cValue) } ?? nil
    }

    public var double: Double? { getValue() }
    public var int: Int? { getValue() }
    public var bool: Bool? { getValue() }
    public var string: String? { getValue() }
    public var date: Date? { getValue() }
    public var data: Data? { getValue() }

    public var error: JSError? {
        if let cachedError = cachedError {
            return cachedError
        }
        guard isException else { return nil }
        return withEngine { $0.mapException() }
    }
}

extension JSValue: ConvertibleWithJavascript {
    public func jsValue(_ context: JSContext) -> JSValue {
        JSValue(context, value: cValue, dup: true)
    }
}

// MARK: - ConvertibleWithJavascript

/// A type that can be produced from a JavaScript value and exported back into
/// JavaScript.
///
/// Both requirements are mandatory: `init?(_:value:)` converts *from* JS and
/// `jsValue(_:)` converts *to* JS. There is no default `jsValue`, so a
/// conforming type cannot silently degrade to `undefined`.
public protocol ConvertibleWithJavascript {
    init?(_ context: JSContext, value: JSCValue)
    func jsValue(_ context: JSContext) -> JSValue
}

extension String: ConvertibleWithJavascript {
    public init?(_ context: JSContext, value: JSCValue) {
        guard let cString = JS_ToCString(context.core.context, value) else {
            context.clearException()
            return nil
        }
        self.init(cString: cString)
        JS_FreeCString(context.core.context, cString)
    }

    public func jsValue(_ context: JSContext) -> JSValue {
        JSValue(context, value: JS_NewString(context.core.context, self))
    }
}

extension Bool: ConvertibleWithJavascript {
    public init?(_ context: JSContext, value: JSCValue) {
        let result = JS_ToBool(context.core.context, value)
        if result < 0 {
            context.clearException()
            return nil
        }
        self = result != 0
    }

    public func jsValue(_ context: JSContext) -> JSValue {
        JSValue(context, value: JS_NewBool(context.core.context, self ? 1 : 0))
    }
}

extension Int32: ConvertibleWithJavascript {
    public init?(_ context: JSContext, value: JSCValue) {
        guard JS_IsNumber(value) != 0 else { return nil }
        var pres: Int32 = 0
        if JS_ToInt32(context.core.context, &pres, value) < 0 {
            context.clearException()
            return nil
        }
        self = pres
    }

    public func jsValue(_ context: JSContext) -> JSValue {
        JSValue(context, value: JS_NewInt32(context.core.context, self))
    }
}

extension UInt32: ConvertibleWithJavascript {
    public init?(_ context: JSContext, value: JSCValue) {
        guard JS_IsNumber(value) != 0 else { return nil }
        var pres: UInt32 = 0
        if JS_ToUint32(context.core.context, &pres, value) < 0 {
            context.clearException()
            return nil
        }
        self = pres
    }

    public func jsValue(_ context: JSContext) -> JSValue {
        JSValue(context, value: JS_NewUint32(context.core.context, self))
    }
}

extension Int64: ConvertibleWithJavascript {
    public init?(_ context: JSContext, value: JSCValue) {
        guard JS_IsNumber(value) != 0 else { return nil }
        var pres: Int64 = 0
        if JS_ToInt64(context.core.context, &pres, value) < 0 {
            context.clearException()
            return nil
        }
        self = pres
    }

    public func jsValue(_ context: JSContext) -> JSValue {
        JSValue(context, value: JS_NewInt64(context.core.context, self))
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
        guard let valueIn64 = Int64(context, value: value), valueIn64 >= 0 else { return nil }
        self.init(UInt64(valueIn64))
    }

    public func jsValue(_ context: JSContext) -> JSValue {
        if self <= UInt(Int64.max) {
            return Int64(self).jsValue(context)
        }
        return Double(self).jsValue(context)
    }
}

extension Double: ConvertibleWithJavascript {
    public init?(_ context: JSContext, value: JSCValue) {
        guard JS_IsNumber(value) != 0 else { return nil }
        var pres: Double = 0
        if JS_ToFloat64(context.core.context, &pres, value) < 0 {
            context.clearException()
            return nil
        }
        self = pres
    }

    public func jsValue(_ context: JSContext) -> JSValue {
        JSValue(context, value: JS_NewFloat64(context.core.context, self))
    }
}

extension Array: ConvertibleWithJavascript where Element: ConvertibleWithJavascript {
    public init?(_ context: JSContext, value: JSCValue) {
        let isArray = JS_IsArray(context.core.context, value)
        if isArray < 0 {
            context.clearException()
            return nil
        }
        guard isArray == 1 else { return nil }

        let length = JS_GetPropertyStr(context.core.context, value, "length")
        defer { context.core.free(length) }
        if JS_IsException(length) != 0 {
            context.clearException()
            return nil
        }

        var size: UInt64 = 0
        if JS_ToIndex(context.core.context, &size, length) < 0 {
            context.clearException()
            return nil
        }

        self = []
        reserveCapacity(Int(size))
        for index in 0..<size {
            let v = JS_GetPropertyUint32(context.core.context, value, UInt32(index))
            defer { context.core.free(v) }
            if JS_IsException(v) != 0 {
                context.clearException()
                return nil
            }
            guard let ele = Element(context, value: v) else { return nil }
            append(ele)
        }
    }

    public func jsValue(_ context: JSContext) -> JSValue {
        let array = JS_NewArray(context.core.context)
        for (index, element) in enumerated() {
            _ = JS_SetPropertyUint32(context.core.context, array, UInt32(index), element.jsValue(context).steal())
        }
        return JSValue(context, value: array)
    }
}

extension Dictionary: ConvertibleWithJavascript where Key == String, Value: ConvertibleWithJavascript {
    public init?(_ context: JSContext, value: JSCValue) {
        guard JS_IsObject(value) != 0 else { return nil }
        let isArray = JS_IsArray(context.core.context, value)
        if isArray < 0 {
            context.clearException()
            return nil
        }
        guard isArray == 0 else { return nil }

        var tab: UnsafeMutablePointer<JSPropertyEnum>?
        var len: UInt32 = 0
        if JS_GetOwnPropertyNames(context.core.context, &tab, &len, value, Int32(JS_GPN_STRING_MASK | JS_GPN_ENUM_ONLY)) != 0 {
            context.clearException()
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
                context.clearException()
                return nil
            }
            let key = String(cString: keyCString)
            JS_FreeCString(context.core.context, keyCString)

            let prop = JS_GetProperty(context.core.context, value, atom)
            defer { context.core.free(prop) }
            if JS_IsException(prop) != 0 {
                context.clearException()
                return nil
            }
            guard let converted = Value(context, value: prop) else { return nil }
            self[key] = converted
        }
    }

    public func jsValue(_ context: JSContext) -> JSValue {
        let obj = JS_NewObject(context.core.context)
        for (key, value) in self {
            _ = JS_SetPropertyStr(context.core.context, obj, key, value.jsValue(context).steal())
        }
        return JSValue(context, value: obj)
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
        if JS_IsException(buffer) != 0 {
            context.clearException()
            return nil
        }
        defer { context.core.free(buffer) }

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
        return JSValue(context, value: value)
    }
}

extension Date: ConvertibleWithJavascript {
    public init?(_ context: JSContext, value: JSCValue) {
        guard context.isDate(value) else { return nil }

        let atom = JS_NewAtom(context.core.context, "valueOf")
        defer { JS_FreeAtom(context.core.context, atom) }
        let result = JS_Invoke(context.core.context, value, atom, 0, nil)
        defer { context.core.free(result) }
        guard JS_IsException(result) == 0 else {
            context.clearException()
            return nil
        }

        var millis: Double = 0
        if JS_ToFloat64(context.core.context, &millis, result) < 0 {
            context.clearException()
            return nil
        }
        self.init(timeIntervalSince1970: millis / 1000)
    }

    public func jsValue(_ context: JSContext) -> JSValue {
        JSValue(context, value: JS_NewDate(context.core.context, timeIntervalSince1970 * 1000))
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

extension JSError: ConvertibleWithJavascript {
    public init?(_ context: JSContext, value: JSCValue) {
        nil
    }

    public func jsValue(_ context: JSContext) -> JSValue {
        // Returning an error from a host function throws into JS.
        JSValue(context, value: context.makeThrownError(self), autoFree: false)
    }
}

extension JSContext {
    func isDate(_ value: JSCValue) -> Bool {
        guard JS_IsObject(value) != 0 else { return false }
        let globalObj = JS_GetGlobalObject(core.context)
        defer { JS_FreeValue(core.context, globalObj) }
        let dateCtor = JS_GetPropertyStr(core.context, globalObj, "Date")
        defer { JS_FreeValue(core.context, dateCtor) }
        guard JS_IsFunction(core.context, dateCtor) != 0 else { return false }
        let result = JS_IsInstanceOf(core.context, value, dateCtor)
        if result < 0 {
            clearException()
            return false
        }
        return result != 0
    }

    func makeValue(_ value: JSCValue) -> JSValue {
        let jsValue = JSValue(self, value: value, dup: false, autoFree: true)
        if JS_IsException(value) != 0 {
            jsValue.noteException(mapException())
        }
        return jsValue
    }

    func makeThrownError(_ error: JSError) -> JSCValue {
        let err = JS_NewError(core.context)
        let message = JS_NewString(core.context, error.message)
        _ = JS_DefinePropertyValueStr(
            core.context,
            err,
            "message",
            message,
            JS_PROP_WRITABLE | JS_PROP_CONFIGURABLE
        )
        return JS_Throw(core.context, err)
    }
}
