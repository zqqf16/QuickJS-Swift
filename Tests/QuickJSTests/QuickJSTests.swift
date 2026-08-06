import XCTest
@testable import QuickJS
import QuickJSC

final class QuickJSSwiftTests: XCTestCase {
    func testEvalAndGlobals() throws {
        let runtime = try XCTUnwrap(JSRuntime())
        let context = try XCTUnwrap(runtime.createContext())

        context.eval("console.log('Hello QuickJS');")
        XCTAssertEqual(context.eval("var i = 10; i;").int, 10)

        context.setGlobalProperty(name: "$SwiftTest", value: "Hello world")
        XCTAssertEqual(context.getGlobalProperty("$SwiftTest").string, "Hello world")
        context.setGlobalProperty(name: "$flag", value: true)
        XCTAssertEqual(context.getGlobalProperty("$flag").bool, true)

        XCTAssertEqual(try context.evaluate("1 + 2;").int, 3)
        XCTAssertThrowsError(try context.evaluate("throw new Error('boom');")) { error in
            guard case JSError.exception(let message) = error else {
                return XCTFail("unexpected \(error)")
            }
            XCTAssertTrue(message.contains("boom"))
        }
    }

    func testNativeModuleAndValues() throws {
        let runtime = try XCTUnwrap(JSRuntime())
        let context = try XCTUnwrap(runtime.createContext())

        context.module("swift") {
            JSModuleFunction("getMagic", argc: 0) { _, _, _, _ in 10 }
            JSModuleFunction("echo", argc: 1) { context, _, argc, argv in
                guard argc >= 1, let argv = argv else { return nil }
                return String(context, value: argv[0])
            }
            JSModuleValue("label", "ok")
        }

        try context.evaluate("""
        import { getMagic, echo, label } from 'swift'
        globalThis.magic = getMagic()
        globalThis.echoed = echo("hi")
        globalThis.label = label
        """, options: EvalOptions(type: .module))

        XCTAssertEqual(context.eval("magic;").int, 10)
        XCTAssertEqual(context.eval("echoed;").string, "hi")
        XCTAssertEqual(context.eval("label;").string, "ok")
    }

    func testConversions() throws {
        let runtime = try XCTUnwrap(JSRuntime())
        let context = try XCTUnwrap(runtime.createContext())

        XCTAssertEqual(context.eval("true;").bool, true)
        XCTAssertEqual(context.eval("[1,2,3];").getValue() as [Int]?, [1, 2, 3])

        context.setGlobalProperty(name: "obj", value: ["a": 1, "b": 2])
        XCTAssertEqual(context.eval("obj.a + obj.b;").int, 3)

        let payload = Data([0xDE, 0xAD, 0xBE, 0xEF])
        context.setGlobalProperty(name: "buf", value: payload)
        XCTAssertEqual(context.getGlobalProperty("buf").data, payload)

        // Failed Data conversion must not poison the context.
        XCTAssertNil(context.eval("({a:1});").data)
        XCTAssertEqual(try context.evaluate("1 + 1;").int, 2)

        let date = Date(timeIntervalSince1970: 1_700_000_000)
        context.setGlobalProperty(name: "d", value: date)
        XCTAssertEqual(context.eval("d.getTime();").double, date.timeIntervalSince1970 * 1000)
        XCTAssertNil(context.eval("({ valueOf() { return 1 } });").date)

        let big = UInt(UInt32.max) + 10
        context.setGlobalProperty(name: "big", value: big)
        XCTAssertEqual(context.eval("big;").int, Int(big))
    }

    func testCallWithThis() throws {
        let runtime = try XCTUnwrap(JSRuntime())
        let context = try XCTUnwrap(runtime.createContext())
        let fn = try context.evaluate("function f(){ return this.x + 1 }; f;")
        let object = try context.evaluate("({ x: 41 })")
        XCTAssertEqual(context.call(fn, this: object).int, 42)
    }

    func testInterrupt() throws {
        let runtime = try XCTUnwrap(JSRuntime(options: JSRuntimeOptions(
            enableHelpers: false,
            interruptHandler: { true }
        )))
        let context = try XCTUnwrap(runtime.createContext())
        XCTAssertFalse(context.hasGlobalProperty(name: "console"))

        XCTAssertThrowsError(try context.evaluate("for(;;){}")) { error in
            XCTAssertEqual(error as? JSError, .interrupted)
        }
    }

    func testBytecodeAndPromises() throws {
        let runtime = try XCTUnwrap(JSRuntime())
        let context = try XCTUnwrap(runtime.createContext())

        let bytecode = try context.compile("1 + 41;")
        XCTAssertEqual(try context.evalBytecode(bytecode).int, 42)

        try context.evaluate("""
        globalThis.done = false
        Promise.resolve(7).then(v => { globalThis.done = v })
        """)
        XCTAssertEqual(context.eval("done;").int, 7)
    }

    func testTimerTeardown() throws {
        let runtime = try XCTUnwrap(JSRuntime())
        var context: JSContext? = runtime.createContext()
        context?.enableEventLoop()
        try context?.evaluate("setInterval(() => {}, 10)")
        context = nil
        // Giving the queue a moment must not crash after teardown.
        let expectation = expectation(description: "delay")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
        _ = runtime
    }

    static var allTests = [
        ("testEvalAndGlobals", testEvalAndGlobals),
        ("testNativeModuleAndValues", testNativeModuleAndValues),
        ("testConversions", testConversions),
        ("testCallWithThis", testCallWithThis),
        ("testInterrupt", testInterrupt),
        ("testBytecodeAndPromises", testBytecodeAndPromises),
        ("testTimerTeardown", testTimerTeardown),
    ]
}
