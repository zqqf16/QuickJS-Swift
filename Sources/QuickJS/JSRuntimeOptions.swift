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

    /// Install QuickJS `std` / `os` modules, the file-based ES module loader,
    /// and worker handlers.
    ///
    /// Defaults to `false` for safer embedding (no filesystem / process / Worker).
    ///
    /// - Note: Only honored on macOS and Linux. `std`/`os` install POSIX signal
    ///   handlers and call into process/filesystem APIs that are unavailable or
    ///   unsafe on iOS, tvOS, and watchOS, where this option is ignored.
    public var enableStdModules: Bool

    /// Install `console` / `print` helpers via `js_std_add_helpers`.
    public var enableHelpers: Bool

    /// Called periodically during JS execution. Return `true` to interrupt.
    public var interruptHandler: (() -> Bool)?

    /// Drain Promise jobs automatically after eval / call.
    public var flushJobsAfterEval: Bool

    public init(
        memoryLimit: Int? = nil,
        enableStdModules: Bool = false,
        enableHelpers: Bool = true,
        interruptHandler: (() -> Bool)? = nil,
        flushJobsAfterEval: Bool = true
    ) {
        self.memoryLimit = memoryLimit
        self.enableStdModules = enableStdModules
        self.enableHelpers = enableHelpers
        self.interruptHandler = interruptHandler
        self.flushJobsAfterEval = flushJobsAfterEval
    }
}

/// Options controlling script evaluation.
public struct EvalOptions {
    public var type: JSContext.EvalType
    public var filename: String
    public var strict: Bool
    public var compileOnly: Bool
    public var backtraceBarrier: Bool
    /// Allow top-level await in global scripts (`JS_EVAL_FLAG_ASYNC`).
    public var async: Bool

    public init(
        type: JSContext.EvalType = .global,
        filename: String = "<Swift>",
        strict: Bool = false,
        compileOnly: Bool = false,
        backtraceBarrier: Bool = false,
        async: Bool = false
    ) {
        self.type = type
        self.filename = filename
        self.strict = strict
        self.compileOnly = compileOnly
        self.backtraceBarrier = backtraceBarrier
        self.async = async
    }

    var rawFlags: Int32 {
        var flags = type.rawValue
        if strict { flags |= JS_EVAL_FLAG_STRICT }
        if compileOnly { flags |= JS_EVAL_FLAG_COMPILE_ONLY }
        if backtraceBarrier { flags |= JS_EVAL_FLAG_BACKTRACE_BARRIER }
        if async { flags |= JS_EVAL_FLAG_ASYNC }
        return flags
    }
}
