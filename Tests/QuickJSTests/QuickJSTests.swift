import XCTest
@testable import QuickJS
import QuickJSC

final class QuickJSSwiftTests: XCTestCase {
    func testEvalAndGlobals() throws {
        let runtime = try XCTUnwrap(JSRuntime())
        let context = try XCTUnwrap(runtime.createContext())

        context.eval("console.log('Hello QuickJS');")
        XCTAssertEqual(context.eval("var i = 10; i;").int, 10)

        let property = "$SwiftTest"
        XCTAssertFalse(context.hasGlobalProperty(name: property))
        context.setGlobalProperty(name: property, value: "Hello world")
        XCTAssertTrue(context.hasGlobalProperty(name: property))
        XCTAssertEqual(context.getGlobalProperty(property).string, "Hello world")

        context.setGlobalProperty(name: "$flag", value: true)
        XCTAssertEqual(context.getGlobalProperty("$flag").bool, true)

        let value = try context.evaluate("1 + 2;")
        XCTAssertEqual(value.int, 3)

        XCTAssertThrowsError(try context.evaluate("throw new Error('boom');")) { error in
            guard case JSError.exception(let message) = error else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertTrue(message.contains("boom"))
        }
    }

    func testNativeModule() throws {
        let runtime = try XCTUnwrap(JSRuntime())
        let context = try XCTUnwrap(runtime.createContext())

        context.module("swift") {
            JSModuleFunction("getMagic", argc: 0) { _, _, _, _ in 10 }
            JSModuleFunction("getMagic2", argc: 0) { _, _, _, _ in 20 }
            JSModuleFunction("echo", argc: 1) { context, _, argc, argv in
                guard argc >= 1, let argv = argv else { return nil }
                return String(context, value: argv[0])
            }
        }

        let script = """
        "use strict";
        import { getMagic, getMagic2, echo } from 'swift'
        globalThis.magic = getMagic();
        globalThis.magic2 = getMagic2();
        globalThis.echoed = echo("hi");
        """

        XCTAssertNil(context.eval(script, type: .module).error)
        XCTAssertEqual(context.eval("magic;").int, 10)
        XCTAssertEqual(context.eval("magic2;").int, 20)
        XCTAssertEqual(context.eval("echoed;").string, "hi")
    }

    func testConversions() throws {
        let runtime = try XCTUnwrap(JSRuntime())
        let context = try XCTUnwrap(runtime.createContext())

        XCTAssertEqual(context.eval("true;").bool, true)

        let arrayValue = context.eval("[1, 2, 3];")
        XCTAssertTrue(arrayValue.isArray)
        let numbers: [Int]? = arrayValue.getValue()
        XCTAssertEqual(numbers, [1, 2, 3])

        context.setGlobalProperty(name: "arr", value: [10, 20, 30])
        XCTAssertEqual(context.eval("arr[0] + arr[1] + arr[2];").int, 60)

        context.setGlobalProperty(name: "obj", value: ["a": 1, "b": 2])
        XCTAssertEqual(context.eval("obj.a + obj.b;").int, 3)
        let dict: [String: Int]? = context.eval("({x: 7, y: 8});").getValue()
        XCTAssertEqual(dict?["x"], 7)
        XCTAssertEqual(dict?["y"], 8)

        let payload = Data([0xDE, 0xAD, 0xBE, 0xEF])
        context.setGlobalProperty(name: "buf", value: payload)
        XCTAssertEqual(context.eval("buf.byteLength;").int, 4)
        XCTAssertEqual(context.getGlobalProperty("buf").data, payload)

        let date = Date(timeIntervalSince1970: 1_700_000_000)
        context.setGlobalProperty(name: "d", value: date)
        XCTAssertEqual(context.eval("d.getTime();").double, date.timeIntervalSince1970 * 1000)
        let roundTrip = context.eval("new Date(1700000000000);").date
        XCTAssertEqual(roundTrip?.timeIntervalSince1970, 1_700_000_000)
    }

    func testDupKeepsValueAlive() throws {
        let runtime = try XCTUnwrap(JSRuntime())
        let context = try XCTUnwrap(runtime.createContext())

        let original = context.eval("({ n: 1 });")
        let duplicated = JSValue(context.core, value: original.cValue, dup: true)
        _ = original.isException

        let prop = JS_GetPropertyStr(context.core.context, duplicated.cValue, "n")
        defer { JS_FreeValue(context.core.context, prop) }
        var intValue: Int32 = 0
        XCTAssertEqual(JS_ToInt32(context.core.context, &intValue, prop), 0)
        XCTAssertEqual(intValue, 1)
    }

    func testInterruptAndOptionalStd() throws {
        var shouldInterrupt = false
        let runtime = try XCTUnwrap(JSRuntime(options: JSRuntimeOptions(
            enableStdModules: false,
            interruptHandler: { shouldInterrupt }
        )))
        let context = try XCTUnwrap(runtime.createContext())

        // console comes from std helpers; without std modules it should be missing.
        XCTAssertFalse(context.hasGlobalProperty(name: "console"))

        shouldInterrupt = true
        let result = context.eval("for(;;){}")
        XCTAssertTrue(result.isException)
    }

    func testBytecodeRoundTrip() throws {
        let runtime = try XCTUnwrap(JSRuntime(options: JSRuntimeOptions(enableStdModules: false)))
        let context = try XCTUnwrap(runtime.createContext())

        let bytecode = try context.compile("1 + 41;")
        XCTAssertFalse(bytecode.isEmpty)
        XCTAssertEqual(try context.evalBytecode(bytecode).int, 42)
    }

    static var allTests = [
        ("testEvalAndGlobals", testEvalAndGlobals),
        ("testNativeModule", testNativeModule),
        ("testConversions", testConversions),
        ("testDupKeepsValueAlive", testDupKeepsValueAlive),
        ("testInterruptAndOptionalStd", testInterruptAndOptionalStd),
        ("testBytecodeRoundTrip", testBytecodeRoundTrip),
    ]
}
