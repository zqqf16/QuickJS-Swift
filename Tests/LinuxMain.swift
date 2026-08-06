import XCTest
import QuickJSTests

var tests = [XCTestCaseEntry]()
tests += QuickJSSwiftTests.allTests()
tests += RunloopTests.allTests()
XCTMain(tests)
