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

typealias JSModuleInitFunction = @convention(c) (OpaquePointer?, OpaquePointer?) -> CInt
typealias JSCFunctionData = @convention(c) (
    _ ctx: OpaquePointer?,
    _ this: JSCValue,
    _ argc: Int32,
    _ argv: UnsafeMutablePointer<JSCValue>?,
    _ magic: Int32,
    _ data: UnsafeMutablePointer<JSCValue>?
) -> JSCValue

public class JSFunction: JSValue, @unchecked Sendable {
    public typealias Block = (_ context: JSContext, _ this: JSValue, _ argc: Int, _ argv: UnsafeMutablePointer<JSCValue>?) -> ConvertibleWithJavascript?

    public let name: String
    public let argc: Int32

    private let block: Block
    private var functionData: JSValue?
    private var didBuild = false

    override var context: JSContextWrapper? {
        didSet {
            if context != nil {
                buildFunction()
            }
        }
    }

    init(_ context: JSContextWrapper?, name: String, argc: Int32, block: @escaping Block) {
        self.name = name
        self.argc = argc
        self.block = block
        super.init(context, value: .undefined, autoFree: false)

        if context != nil {
            buildFunction()
        }
    }

    @available(*, unavailable, message: "JSFunction cannot wrap an existing JS value")
    required init(_ context: JSContextWrapper?, value: JSCValue, dup: Bool = false, autoFree: Bool = true) {
        fatalError("JSFunction cannot wrap an existing JS value")
    }

    @available(*, unavailable, message: "JSFunction cannot wrap an existing JS value")
    public required convenience init?(_ context: JSContext, value: JSCValue) {
        fatalError("JSFunction cannot wrap an existing JS value")
    }

    func buildFunction() {
        guard let context = context, !didBuild else { return }
        didBuild = true

        functionData = context.object(classId: QuickJSClass.functionDataID)

        let dataFunction: JSCFunctionData = { ctx, this, argc, argv, magic, data -> JSCValue in
            guard ctx?.opaqueContext != nil,
                  let funcData = data,
                  let mySelfPtr = JS_GetOpaque(funcData[0], QuickJSClass.functionDataID)
            else {
                return .undefined
            }

            let mySelf = Unmanaged<JSFunction>.fromOpaque(mySelfPtr).takeUnretainedValue()
            return mySelf.callRealFunction(ctx, this, argc, argv, magic, data)
        }

        // Host keeps the Swift object alive via JSContext/JSModule strong refs.
        functionData!.setOpaqueUnretained(self)
        cValue = context.function(dataFunction, argc: argc, magic: 0, length: 1, data: &(functionData!.cValue))
        // Transfer the data object's ref to the C function (which already dups it).
        context.free(functionData!.cValue)
        functionData!.autoFree = false
    }

    func callRealFunction(
        _ ctx: OpaquePointer?,
        _ this: JSCValue,
        _ argc: Int32,
        _ argv: UnsafeMutablePointer<JSCValue>?,
        _ magic: Int32,
        _ data: UnsafeMutablePointer<JSCValue>?
    ) -> JSCValue {
        guard let context = ctx?.opaqueContext else {
            return .undefined
        }

        let thisObj = JSValue(context, value: this, dup: true)
        if let result = block(context, thisObj, Int(argc), argv) {
            if let error = result as? JSError {
                return context.makeThrownError(error)
            }
            if let value = result as? JSValue {
                if let error = value.cachedError ?? value.error {
                    return context.makeThrownError(error)
                }
                if JS_IsException(value.cValue) != 0 {
                    return context.makeThrownError(.exception("JavaScript exception"))
                }
                return value.jsValue(context).steal()
            }
            let jsValue = result.jsValue(context)
            if JS_HasException(context.core.context) != 0 {
                return .exception
            }
            return jsValue.steal()
        }
        if JS_HasException(context.core.context) != 0 {
            return .exception
        }
        return .undefined
    }
}
