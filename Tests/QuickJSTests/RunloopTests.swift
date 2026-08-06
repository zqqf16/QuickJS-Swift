import XCTest
@testable import QuickJS

final class RunloopTests: XCTestCase {
    func testSetTimeoutAndClear() throws {
        let runtime = try XCTUnwrap(JSRuntime())
        let context = try XCTUnwrap(runtime.createContext())
        context.enableEventLoop()

        let expectation = XCTestExpectation(description: "timeout fired")

        context.module("Waiter") {
            JSModuleFunction("timeIsUp", argc: 1) { _, _, argc, argv in
                XCTAssertGreaterThanOrEqual(argc, 1)
                if let argv = argv {
                    XCTAssertEqual(String(context, value: argv[0]), "ok")
                }
                expectation.fulfill()
                return nil
            }
        }

        let script = """
        "use strict";
        import { timeIsUp } from "Waiter";
        const id = setTimeout(function(msg){ timeIsUp(msg); }, 150, "ok");
        const cancelled = setTimeout(function(){ throw new Error("should be cleared"); }, 50);
        clearTimeout(cancelled);
        """

        XCTAssertNil(context.eval(script, type: .module).error)
        wait(for: [expectation], timeout: 2)
    }

    func testRunloopModuleCompat() throws {
        let runtime = try XCTUnwrap(JSRuntime())
        let context = try XCTUnwrap(runtime.createContext())
        context.enableRunloop()

        let expectation = XCTestExpectation(description: "module timeout")
        context.module("Waiter") {
            JSModuleFunction("done", argc: 0) { _, _, _, _ in
                expectation.fulfill()
                return nil
            }
        }

        let script = """
        "use strict";
        import * as runloop from "Runloop";
        import { done } from "Waiter";
        runloop.setTimeout(function(){ done(); }, 100);
        """
        XCTAssertNil(context.eval(script, type: .module).error)
        wait(for: [expectation], timeout: 2)
    }

    static var allTests = [
        ("testSetTimeoutAndClear", testSetTimeoutAndClear),
        ("testRunloopModuleCompat", testRunloopModuleCompat),
    ]
}
