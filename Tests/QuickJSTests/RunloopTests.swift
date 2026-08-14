import XCTest
@testable import QuickJS

final class RunloopTests: XCTestCase {
    func testSetTimeoutClearAndInterval() throws {
        let runtime = try XCTUnwrap(JSRuntime())
        let context = try XCTUnwrap(runtime.createContext())
        context.enableEventLoop()

        let timeoutExpectation = expectation(description: "timeout")
        let intervalExpectation = expectation(description: "interval")
        intervalExpectation.expectedFulfillmentCount = 2

        context.module("Waiter") {
            JSModuleFunction("onTimeout", argc: 1) { _, _, argc, argv in
                XCTAssertGreaterThanOrEqual(argc, 1)
                if let argv = argv {
                    XCTAssertEqual(String(context, value: argv[0]), "ok")
                }
                timeoutExpectation.fulfill()
                return nil
            }
            JSModuleFunction("onInterval", argc: 0) { _, _, _, _ in
                intervalExpectation.fulfill()
                return nil
            }
        }

        try context.evaluate("""
        import { onTimeout, onInterval } from "Waiter"
        const cancelled = setTimeout(() => { throw new Error("cleared") }, 20)
        clearTimeout(cancelled)
        setTimeout(msg => onTimeout(msg), 80, "ok")
        let n = 0
        const id = setInterval(() => {
          n += 1
          onInterval()
          if (n >= 2) clearInterval(id)
        }, 40)
        """, options: EvalOptions(type: .module))

        wait(for: [timeoutExpectation, intervalExpectation], timeout: 2)
    }

    func testRunloopModuleCompat() throws {
        let runtime = try XCTUnwrap(JSRuntime())
        let context = try XCTUnwrap(runtime.createContext())
        context.enableRunloop()
        context.enableRunloop() // should be idempotent

        let expectation = expectation(description: "module timeout")
        context.module("Waiter") {
            JSModuleFunction("done", argc: 0) { _, _, _, _ in
                expectation.fulfill()
                return nil
            }
        }

        try context.evaluate("""
        import * as runloop from "Runloop"
        import { done } from "Waiter"
        runloop.setTimeout(() => done(), 50)
        """, options: EvalOptions(type: .module))

        wait(for: [expectation], timeout: 2)
    }

    func testSetTimeoutStringDelayAndCallbackException() throws {
        let runtime = try XCTUnwrap(JSRuntime())
        let context = try XCTUnwrap(runtime.createContext())
        context.enableEventLoop()

        let expectation = expectation(description: "string delay")
        context.module("Waiter") {
            JSModuleFunction("done", argc: 0) { _, _, _, _ in
                expectation.fulfill()
                return nil
            }
        }

        try context.evaluate("""
        import { done } from "Waiter"
        setTimeout(() => { throw new Error("timer boom") }, "40")
        setTimeout(() => done(), "80")
        """, options: EvalOptions(type: .module))

        wait(for: [expectation], timeout: 2)
        XCTAssertEqual(try context.evaluate("1 + 1;").int, 2)
    }
}
