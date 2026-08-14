import XCTest
@testable import QuickJS

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
        weak var weakContext: JSContext?
        var context: JSContext? = runtime.createContext()
        weakContext = context
        context?.enableEventLoop()
        try context?.evaluate("setInterval(() => {}, 10)")
        context = nil
        XCTAssertNil(weakContext, "A pending interval must not keep the context alive")
        // Giving the queue a moment must not crash after teardown.
        let expectation = expectation(description: "delay")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
        _ = runtime
    }

    func testExceptionDoesNotPoisonContext() throws {
        let runtime = try XCTUnwrap(JSRuntime())
        let context = try XCTUnwrap(runtime.createContext())

        let failed = context.eval("throw new Error('poison');")
        XCTAssertTrue(failed.isException)
        XCTAssertNotNil(failed.error)
        XCTAssertEqual(try context.evaluate("2 + 2;").int, 4)

        let fn = try context.evaluate("function boom(){ throw new Error('call'); }; boom;")
        let callFailed = context.call(fn)
        XCTAssertTrue(callFailed.isException)
        XCTAssertEqual(try context.evaluate("3 + 3;").int, 6)

        // Non-stringifiable throw must not leave a pending conversion exception.
        let symbolThrow = context.eval("throw Symbol('x');")
        XCTAssertTrue(symbolThrow.isException)
        XCTAssertEqual(try context.evaluate("5 + 5;").int, 10)

        context.module("Conv") {
            JSModuleFunction("asString", argc: 1) { context, _, argc, argv in
                guard argc >= 1, let argv = argv else { return nil }
                return String(context, value: argv[0])
            }
        }
        try context.evaluate("""
        import { asString } from 'Conv'
        globalThis.convOk = asString(Symbol('s')) === undefined
        """, options: EvalOptions(type: .module))
        XCTAssertEqual(context.eval("convOk;").bool, true)
        XCTAssertEqual(try context.evaluate("6 + 6;").int, 12)
    }

    func testHostThrowAndJSValueReturn() throws {
        let runtime = try XCTUnwrap(JSRuntime())
        let context = try XCTUnwrap(runtime.createContext())

        context.module("Host") {
            JSModuleFunction("fail", argc: 0) { _, _, _, _ in
                JSError.exception("from-swift")
            }
            JSModuleFunction("wrap", argc: 1) { context, _, argc, argv in
                guard argc >= 1, let argv = argv else { return nil }
                return JSValue(context, value: argv[0], dup: true)
            }
        }

        try context.evaluate("""
        import { fail, wrap } from 'Host'
        globalThis.wrapped = wrap(99)
        try { fail(); globalThis.ok = false } catch (e) {
          globalThis.ok = String(e).includes('from-swift')
        }
        """, options: EvalOptions(type: .module))

        XCTAssertEqual(context.eval("wrapped;").int, 99)
        XCTAssertEqual(context.eval("ok;").bool, true)
    }

    func testPromiseRejectionTracker() throws {
        let runtime = try XCTUnwrap(JSRuntime())
        let context = try XCTUnwrap(runtime.createContext())

        try context.evaluate("Promise.reject(new Error('rejected'));")
        let message = try XCTUnwrap(runtime.takeUnhandledPromiseRejection())
        XCTAssertTrue(message.contains("rejected"))
        XCTAssertNil(runtime.takeUnhandledPromiseRejection())
    }

    func testStdModules() throws {
        #if os(macOS) || os(Linux)
        let runtime = try XCTUnwrap(JSRuntime(options: JSRuntimeOptions(enableStdModules: true, enableHelpers: false)))
        let context = try XCTUnwrap(runtime.createContext())

        try context.evaluate("""
        import * as std from 'std'
        import * as os from 'os'
        globalThis.stdOK = typeof std.exit === 'function'
        globalThis.osOK = typeof os.now === 'function'
        """, options: EvalOptions(type: .module))

        XCTAssertEqual(context.eval("stdOK;").bool, true)
        XCTAssertEqual(context.eval("osOK;").bool, true)
        #endif
    }

    func testVersionConsistency() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repo = testFile
            .deletingLastPathComponent()   // QuickJSTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
        let versionFile = repo.appendingPathComponent("Sources/QuickJSC/VERSION")
        let content = try String(contentsOf: versionFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(content, quickJSCVersion)
    }

    func testJSValueKeepsContextAlive() throws {
        var value: QuickJS.JSValue?
        weak var weakContext: JSContext?
        weak var weakRuntime: JSRuntime?
        do {
            let runtime = try XCTUnwrap(JSRuntime(options: JSRuntimeOptions(enableHelpers: false)))
            weakRuntime = runtime
            let context = try XCTUnwrap(runtime.createContext())
            weakContext = context
            value = try context.evaluate("'alive';")
        }
        XCTAssertNotNil(weakContext, "JSValue should keep its JSContext alive")
        XCTAssertNotNil(weakRuntime, "JSContext should keep its JSRuntime alive")
        XCTAssertEqual(value?.string, "alive")
        value = nil
        XCTAssertNil(weakContext)
        XCTAssertNil(weakRuntime)
    }
}
