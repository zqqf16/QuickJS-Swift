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

public typealias JSModuleInitFunction = @convention(c) (OpaquePointer?, OpaquePointer?) -> CInt

public typealias JSCFunction = @convention(c) (_ ctx: OpaquePointer?, _ this: JSCValue, _ argc: Int32, _ argv: JSCValuePointer?) -> JSCValue

public typealias JSCFunctionData = @convention(c) (_ ctx: OpaquePointer?, _ this: JSCValue, _ argc: Int32, _ argv: JSCValuePointer?, _ magic: Int32, _ data: JSCValuePointer?) -> JSCValue

public class JSFunction : JSValue {
    public typealias Block = (_ context: JSContext, _ this: JSValue, _ argc: Int, _ argv: JSCValuePointer?) -> ConvertibleWithJavascript?
    
    public var name: String
    public var argc: Int32

    private var block: Block
    private var functionData: JSValue?
    
    override var context: JSContextWrapper? {
        didSet {
            if context != nil {
                self.buildFunction()
            }
        }
    }

    init(_ context: JSContextWrapper?, name: String, argc: Int32, block: @escaping Block) {
        self.name = name
        self.argc = argc
        self.block = block
        super.init(context, value: .undefined, autoFree: false)
        
        if context != nil {
            self.buildFunction()
        }
    }
    
    required init(_ context: JSContextWrapper?, value: JSCValue, dup: Bool = false, autoFree: Bool = true) {
        fatalError("init(_:value:dup:autoFree) has not been implemented")
    }
    
    func buildFunction() {
        guard let context = self.context else {
            return
        }
        
        self.functionData = context.object()
        
        let dataFunction: JSCFunctionData = { (ctx, this, argc, argv, magic, data) -> JSCValue in
            guard let _ = ctx?.opaqueContext,
                  let funcData = data,
                  let mySelfPtr = JS_GetOpaque(funcData[0], 1)
            else {
                return .undefined
            }
            
            let mySelf = Unmanaged<JSFunction>.fromOpaque(mySelfPtr).takeUnretainedValue()
            return mySelf.callRealFunction(ctx, this, argc, argv, magic, data)
        }
        
        self.functionData!.setOpaque(self)
        self.cValue = context.function(dataFunction, argc: argc, magic: 0, length: 1, data: &(self.functionData!.cValue))
    }
    
    func callRealFunction(_ ctx: OpaquePointer?, _ this: JSCValue, _ argc: Int32, _ argv: JSCValuePointer?, _ magic: Int32, _ data: JSCValuePointer?) -> JSCValue {
        guard let context = ctx?.opaqueContext else {
            return .undefined
        }
        
        let thisObj = JSValue(context.core, value: this, dup: true)
        if let result = self.block(context, thisObj, Int(argc), argv) {
            return result.jsValue(context.core).cValue
        }
        return .undefined
    }
}
