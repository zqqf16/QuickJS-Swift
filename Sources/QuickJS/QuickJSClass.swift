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

/// Registered QuickJS classes used by the Swift bindings.
enum QuickJSClass {
    /// Class for objects that store a Swift `JSFunction` opaque pointer.
    ///
    /// Allocated once via a lazy `static let` so concurrent `JSRuntime` creation
    /// cannot race on `JS_NewClassID` (QuickJS's class-ID counter is not
    /// thread-safe).
    static let functionDataID: JSClassID = {
        var id: JSClassID = 0
        JS_NewClassID(&id)
        return id
    }()

    private static let functionDataClassName = strdup("SwiftFunctionData")!

    static func register(on runtime: OpaquePointer) {
        guard JS_IsRegisteredClass(runtime, functionDataID) == 0 else {
            return
        }

        var classDef = JSClassDef(
            class_name: functionDataClassName,
            finalizer: nil,
            gc_mark: nil,
            call: nil,
            exotic: nil
        )
        JS_NewClass(runtime, functionDataID, &classDef)
    }
}
