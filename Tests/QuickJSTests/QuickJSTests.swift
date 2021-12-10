import XCTest

@testable import QuickJS

final class QuickJSSwiftTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        
        let runtime = JSRuntime()
        XCTAssertNotNil(runtime)
        
        let context = runtime!.createContext()
        XCTAssertNotNil(context)
        
        context!.eval("console.log('Hello QuickJS');")

        let js = "var i = 10; i;"
        let result = context!.eval(js).int
        XCTAssertEqual(result, 10)
        
        let property = "$SwiftTest"
        XCTAssertFalse(context!.hasGlobalProperty(name: property))
        context!.setGlobalProperty(name: property, value: "Hello world")
        XCTAssertTrue(context!.hasGlobalProperty(name: property))
        
        context!.module("swift") {
            JSModuleFunction("getMagic", argc: 0) { context, this, argc, argv in
                return 10
            }
            JSModuleFunction("getMagic2", argc: 0) { context, this, argc, argv in
                return 20
            }
        }
                
        let getMagic = """
        "use strict";
        import { getMagic, getMagic2 } from 'swift'
        globalThis.magic = getMagic();
        globalThis.magic2 = getMagic2();
        """
        
        let error = context!.eval(getMagic, type: .module).error
        XCTAssertNil(error)

        let magic = context!.eval("magic;").int
        XCTAssertEqual(magic, 10)
        
        let magic2 = context!.eval("magic2;").int
        XCTAssertEqual(magic2, 20)
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
