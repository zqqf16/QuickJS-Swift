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

/// Host implementation of timer globals.
enum JSTimers {
    private static var states = [ObjectIdentifier: TimerState]()
    private static let lock = NSLock()

    private final class TimerState {
        var entries: [UInt64: (handle: JSTimerID, function: JSValue, args: [JSValue])] = [:]
        var alive = true
    }

    private static func state(for context: JSContext) -> TimerState {
        let key = ObjectIdentifier(context)
        lock.lock()
        defer { lock.unlock() }
        if let existing = states[key] {
            return existing
        }
        let created = TimerState()
        states[key] = created
        return created
    }

    /// Cancel all timers and drop retained JS values for a context.
    static func shutdown(for context: JSContext) {
        let key = ObjectIdentifier(context)
        lock.lock()
        let state = states.removeValue(forKey: key)
        state?.alive = false
        let entries = state?.entries ?? [:]
        state?.entries.removeAll()
        lock.unlock()

        for (_, entry) in entries {
            context.runtime.eventLoop.cancel(entry.handle)
        }
    }

    static func install(on context: JSContext) {
        _ = state(for: context)

        func installGlobal(name: String, argc: Int32, block: @escaping JSFunction.Block) {
            let function = JSFunction(context.core, name: name, argc: argc, block: block)
            context.hostFunctions.append(function)
            let globalObj = JS_GetGlobalObject(context.core.context)
            defer { JS_FreeValue(context.core.context, globalObj) }
            _ = JS_SetPropertyStr(context.core.context, globalObj, name, function.cValue)
        }

        installGlobal(name: "setTimeout", argc: 2) { ctx, _, argc, argv in
            scheduleTimeout(on: ctx, argc: argc, argv: argv)
        }
        installGlobal(name: "clearTimeout", argc: 1) { ctx, _, argc, argv in
            clearTimeout(on: ctx, argc: argc, argv: argv)
            return nil
        }
        installGlobal(name: "setInterval", argc: 2) { ctx, _, argc, argv in
            scheduleInterval(on: ctx, argc: argc, argv: argv)
        }
        installGlobal(name: "clearInterval", argc: 1) { ctx, _, argc, argv in
            clearTimeout(on: ctx, argc: argc, argv: argv)
            return nil
        }
    }

    static func scheduleTimeout(on context: JSContext, argc: Int, argv: UnsafeMutablePointer<JSCValue>?) -> Int64? {
        schedule(on: context, argc: argc, argv: argv, repeating: false)
    }

    static func scheduleInterval(on context: JSContext, argc: Int, argv: UnsafeMutablePointer<JSCValue>?) -> Int64? {
        schedule(on: context, argc: argc, argv: argv, repeating: true)
    }

    static func clearTimeout(on context: JSContext, argc: Int, argv: UnsafeMutablePointer<JSCValue>?) {
        guard let argv = argv, argc >= 1 else { return }
        var id: Int64 = 0
        if JS_ToInt64(context.core.context, &id, argv[0]) < 0 {
            context.clearException()
            return
        }
        cancel(on: context, id: UInt64(bitPattern: id))
    }

    private static func schedule(on context: JSContext, argc: Int, argv: UnsafeMutablePointer<JSCValue>?, repeating: Bool) -> Int64? {
        guard let argv = argv, argc >= 2 else { return nil }

        // Use the wrapper-based initializer so the retained `JSValue`s do not
        // strongly retain the `JSContext`. Otherwise a pending timer would keep
        // the context (and runtime) alive forever via the static `states` table,
        // preventing `JSContext.deinit` — and therefore `JSTimers.shutdown` —
        // from ever running.
        let function = JSValue(context.core, value: argv[0], dup: true)
        guard function.isFunction else { return nil }

        // Coerce delay without taking ownership of argv[1].
        var rawDelay: Double = 0
        if JS_ToFloat64(context.core.context, &rawDelay, argv[1]) < 0 {
            context.clearException()
            rawDelay = 0
        }
        let delayMs = rawDelay.isFinite ? max(rawDelay, 0) : 0
        let extraArgc = max(argc - 2, 0)
        var args: [JSValue] = []
        args.reserveCapacity(extraArgc)
        for i in 0..<extraArgc {
            args.append(JSValue(context.core, value: argv[2 + i], dup: true))
        }

        let state = state(for: context)
        // Captured by reference so the closure can read the event loop's ID
        // after `schedule` returns; the event loop owns the single ID counter.
        var timerKey: UInt64 = 0

        let handle = context.runtime.eventLoop.schedule(after: delayMs / 1000, repeating: repeating) { [weak context] in
            guard let context = context else { return }

            let snapshot: (JSValue, [JSValue])? = {
                lock.lock()
                defer { lock.unlock() }
                guard state.alive, let entry = state.entries[timerKey] else { return nil }
                return (entry.function, entry.args)
            }()

            guard let (fn, retainedArgs) = snapshot else { return }

            _ = try? context.flushPendingJobs()
            let result = context.call(fn, arguments: retainedArgs)
            // `call` clears pending exceptions; ignore callback failures here.
            _ = result.error

            if !repeating {
                cancel(on: context, id: timerKey)
            } else {
                _ = try? context.flushPendingJobs()
            }
        }

        timerKey = handle.rawValue

        lock.lock()
        if state.alive {
            state.entries[timerKey] = (handle, function, args)
            lock.unlock()
            return Int64(bitPattern: timerKey)
        }
        lock.unlock()
        context.runtime.eventLoop.cancel(handle)
        return nil
    }

    private static func cancel(on context: JSContext, id: UInt64) {
        let state = state(for: context)
        lock.lock()
        let entry = state.entries.removeValue(forKey: id)
        lock.unlock()
        if let entry = entry {
            context.runtime.eventLoop.cancel(entry.handle)
        }
    }
}
