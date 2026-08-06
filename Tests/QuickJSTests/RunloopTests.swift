import XCTest
@testable import QuickJS

final class RunloopTests: XCTestCase {
    func testSetTimeout() throws {
        let runtime = JSRuntime()
        XCTAssertNotNil(runtime)

        let context = runtime!.createContext()
        XCTAssertNotNil(context)

        context?.enableRunloop()

        let expectation = XCTestExpectation(description: "Waiting for runloop")

        context?.module("Waiter") {
            JSModuleFunction("timeIsUp", argc: 1) { _, _, argc, argv in
                if argc >= 1, let argv = argv {
                    let value = String(context!.core, value: argv[0])
                    XCTAssertEqual(value, "ok")
                } else {
                    XCTFail("missing timer argument")
                }
                expectation.fulfill()
                return nil
            }
        }

        let jsCode = """
        "use strict";
        import * as runloop from "Runloop";
        import { timeIsUp } from "Waiter";
        runloop.setTimeout(function(msg){ timeIsUp(msg); console.log("Hello Runloop"); }, 200, "ok");
        """

        XCTAssertNil(context?.eval(jsCode, type: .module).error)
        wait(for: [expectation], timeout: 2)
    }

    static var allTests = [
        ("testSetTimeout", testSetTimeout),
    ]
}
