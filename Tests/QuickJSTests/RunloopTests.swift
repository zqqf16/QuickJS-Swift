import XCTest

@testable import QuickJSC
@testable import QuickJS

class RunloopTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        let runtime = JSRuntime()
        XCTAssertNotNil(runtime)
        
        let context = runtime!.createContext()
        XCTAssertNotNil(context)
        
        context?.enableRunloop()
        
        let expectation = XCTestExpectation(description: "Waiting for runloop")

        context?.module("Waiter") {
            JSModuleFunction("timeIsUp", argc: 0) { context, this, argc, argv in
                expectation.fulfill()
                return nil
            }
        }
        
        let jsCode = """
        "use strict";
        import * as runloop from "Runloop";
        import { timeIsUp } from "Waiter";
        runloop.setTimeout(function(){ timeIsUp(); console.log("Hello Runloop"); }, 3000);
        """
        
        let result = context?.eval(jsCode, type: .module).error
        XCTAssertNil(result)
  
        self.wait(for: [expectation], timeout: 5)
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}
