import XCTest

@testable import QuickJSC
@testable import QuickJS

final class QuickJSSwiftTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        
        let rt = QuickJSRuntime()
        XCTAssertNotNil(rt)
        
        let ctx = rt!.createContext()
        XCTAssertNotNil(ctx)
        
        let js = "var i = 10; i;"
        let result: Int64? = ctx!.eval(js)
        XCTAssertEqual(result, 10)
        
        let property = "$SwiftTest"
        XCTAssertFalse(ctx!.hasGlobalProperty(name: property))
        ctx!.setGlobalProperty(name: property, value: "Hello world")
        XCTAssertTrue(ctx!.hasGlobalProperty(name: property))
        
        let module = ctx!.createModule("swift")
        XCTAssertNotNil(module)
        
        module!.reigister("getMagic", argc:0, function: { (ctx, this, argc, argv) -> JSValue in
            return JS_NewInt64(ctx, 10);
        })
        
        let getMagic = """
        "use strict";
        import { getMagic } from 'swift'
        globalThis.magic = getMagic();
        """
        
        let error:QuickJSError? = ctx!.eval(getMagic, type: .module)
        XCTAssertNil(error)
        
        let magic: Int64? = ctx!.eval("magic;")
        XCTAssertEqual(magic, 10)
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
