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

/// Configuration for `JSRuntime`.
///
/// QuickJS runtimes are single-threaded. All JavaScript execution is serialized
/// through the runtime's `JSEventLoop`.
public struct JSRuntimeOptions {
    /// Soft memory limit in bytes. `nil` means no limit.
    public var memoryLimit: Int?

    /// When true, install QuickJS `std` / `os` modules, helpers (`console`, etc.),
    /// and the file-based ES module loader.
    ///
    /// Disable this for embedded hosts that do not want filesystem / process APIs.
    public var enableStdModules: Bool

    /// Called periodically during JS execution. Return `true` to interrupt.
    public var interruptHandler: (() -> Bool)?

    public init(
        memoryLimit: Int? = nil,
        enableStdModules: Bool = true,
        interruptHandler: (() -> Bool)? = nil
    ) {
        self.memoryLimit = memoryLimit
        self.enableStdModules = enableStdModules
        self.interruptHandler = interruptHandler
    }
}

/// Options controlling script evaluation.
public struct EvalOptions {
    public var type: JSContext.EvalType
    public var filename: String
    public var strict: Bool
    public var compileOnly: Bool
    public var backtraceBarrier: Bool

    public init(
        type: JSContext.EvalType = .global,
        filename: String = "<Swift>",
        strict: Bool = false,
        compileOnly: Bool = false,
        backtraceBarrier: Bool = false
    ) {
        self.type = type
        self.filename = filename
        self.strict = strict
        self.compileOnly = compileOnly
        self.backtraceBarrier = backtraceBarrier
    }

    var rawFlags: Int32 {
        var flags = type.rawValue
        if strict { flags |= JS_EVAL_FLAG_STRICT }
        if compileOnly { flags |= JS_EVAL_FLAG_COMPILE_ONLY }
        if backtraceBarrier { flags |= JS_EVAL_FLAG_BACKTRACE_BARRIER }
        return flags
    }
}
