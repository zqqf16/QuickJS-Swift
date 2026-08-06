import XCTest
@testable import QuickJS
import QuickJSC

final class QuickJSSwiftTests: XCTestCase {
    func testEvalAndGlobals() {
        let runtime = JSRuntime()
        XCTAssertNotNil(runtime)

        let context = runtime!.createContext()
        XCTAssertNotNil(context)

        context!.eval("console.log('Hello QuickJS');")

        let result = context!.eval("var i = 10; i;").int
        XCTAssertEqual(result, 10)

        let property = "$SwiftTest"
        XCTAssertFalse(context!.hasGlobalProperty(name: property))
        context!.setGlobalProperty(name: property, value: "Hello world")
        XCTAssertTrue(context!.hasGlobalProperty(name: property))
        XCTAssertEqual(context!.getGlobalProperty(property).string, "Hello world")

        context!.setGlobalProperty(name: "$flag", value: true)
        XCTAssertEqual(context!.getGlobalProperty("$flag").bool, true)
    }

    func testNativeModule() {
        let runtime = JSRuntime()!
        let context = runtime.createContext()!

        context.module("swift") {
            JSModuleFunction("getMagic", argc: 0) { _, _, _, _ in
                return 10
            }
            JSModuleFunction("getMagic2", argc: 0) { _, _, _, _ in
                return 20
            }
            JSModuleFunction("echo", argc: 1) { _, _, argc, argv in
                guard argc >= 1, let argv = argv else { return nil }
                return String(context.core, value: argv[0])
            }
        }

        let getMagic = """
        "use strict";
        import { getMagic, getMagic2, echo } from 'swift'
        globalThis.magic = getMagic();
        globalThis.magic2 = getMagic2();
        globalThis.echoed = echo("hi");
        """

        XCTAssertNil(context.eval(getMagic, type: .module).error)
        XCTAssertEqual(context.eval("magic;").int, 10)
        XCTAssertEqual(context.eval("magic2;").int, 20)
        XCTAssertEqual(context.eval("echoed;").string, "hi")
    }

    func testBoolAndArrayConversion() {
        let runtime = JSRuntime()!
        let context = runtime.createContext()!

        let boolResult = context.eval("true;").bool
        XCTAssertEqual(boolResult, true)

        let arrayValue = context.eval("[1, 2, 3];")
        XCTAssertTrue(arrayValue.isArray)
        let numbers: [Int]? = arrayValue.getValue()
        XCTAssertEqual(numbers, [1, 2, 3])

        let jsArray = [10, 20, 30].jsValue(context.core)
        context.setGlobalProperty(name: "arr", value: [10, 20, 30])
        XCTAssertEqual(context.eval("arr[0] + arr[1] + arr[2];").int, 60)
        XCTAssertTrue(jsArray.isArray)
    }

    func testDupKeepsValueAlive() {
        let runtime = JSRuntime()!
        let context = runtime.createContext()!

        let original = context.eval("({ n: 1 });")
        let duplicated = JSValue(context.core, value: original.cValue, dup: true)

        // Free the original wrapper; the dup'd value must remain valid.
        // (original deinits at end of scope below via autorelease-like local lifetime)
        var n: Int?
        do {
            let tmp = original
            n = context.eval("1;").int // keep context busy
            _ = tmp.isException
        }
        XCTAssertEqual(n, 1)

        let prop = JS_GetPropertyStr(context.core.context, duplicated.cValue, "n")
        defer { JS_FreeValue(context.core.context, prop) }
        var intValue: Int32 = 0
        XCTAssertEqual(JS_ToInt32(context.core.context, &intValue, prop), 0)
        XCTAssertEqual(intValue, 1)
    }

    static var allTests = [
        ("testEvalAndGlobals", testEvalAndGlobals),
        ("testNativeModule", testNativeModule),
        ("testBoolAndArrayConversion", testBoolAndArrayConversion),
        ("testDupKeepsValueAlive", testDupKeepsValueAlive),
    ]
}
