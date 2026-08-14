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

/// Opaque handle returned by timer scheduling APIs.
public struct JSTimerID: Hashable {
    public let rawValue: UInt64

    public init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }
}

/// Serializes JavaScript work and hosts timers.
///
/// QuickJS is not thread-safe. All engine access must go through a single
/// `JSEventLoop` instance associated with the runtime.
///
/// - Important: implementations of `sync` must support re-entrancy — when
///   called from the loop's own thread, `sync` must run `work` inline rather
///   than blocking on itself. `DispatchEventLoop` does this via a dispatch
///   specific key. `JSContext.deinit` and `JSValue.deinit` rely on it.
public protocol JSEventLoop: AnyObject, Sendable {
    func async(_ work: @escaping () -> Void)
    func sync<T>(_ work: () throws -> T) rethrows -> T
    func schedule(after delay: TimeInterval, repeating: Bool, _ work: @escaping () -> Void) -> JSTimerID
    func cancel(_ id: JSTimerID)
}

/// Default event loop backed by a serial `DispatchQueue`.
public final class DispatchEventLoop: JSEventLoop, @unchecked Sendable {
    public let queue: DispatchQueue

    private let specificKey = DispatchSpecificKey<UInt8>()
    private let specificValue: UInt8 = 1
    private var nextTimerID: UInt64 = 1
    private var timers: [UInt64: DispatchSourceTimer] = [:]
    private let lock = NSLock()

    public init(label: String = "quickjs.eventloop") {
        self.queue = DispatchQueue(label: label)
        self.queue.setSpecific(key: specificKey, value: specificValue)
    }

    public func async(_ work: @escaping () -> Void) {
        queue.async(execute: work)
    }

    public func sync<T>(_ work: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: specificKey) == specificValue {
            return try work()
        }
        return try queue.sync(execute: work)
    }

    public func schedule(after delay: TimeInterval, repeating: Bool, _ work: @escaping () -> Void) -> JSTimerID {
        lock.lock()
        let id = nextTimerID
        nextTimerID += 1
        lock.unlock()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        let interval = delay.isFinite ? max(delay, 0) : 0
        if repeating {
            let repeatInterval = interval == 0 ? 0.001 : interval
            timer.schedule(deadline: .now() + interval, repeating: repeatInterval)
        } else {
            timer.schedule(deadline: .now() + interval, repeating: .never)
        }
        timer.setEventHandler { [weak self] in
            work()
            if !repeating {
                self?.cancel(JSTimerID(id))
            }
        }

        lock.lock()
        timers[id] = timer
        lock.unlock()
        timer.resume()
        return JSTimerID(id)
    }

    public func cancel(_ id: JSTimerID) {
        lock.lock()
        let timer = timers.removeValue(forKey: id.rawValue)
        lock.unlock()
        timer?.cancel()
    }

    deinit {
        lock.lock()
        let pending = timers
        timers.removeAll()
        lock.unlock()
        pending.values.forEach { $0.cancel() }
    }
}
