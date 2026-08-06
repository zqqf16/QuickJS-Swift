import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    [
        testCase(QuickJSSwiftTests.allTests),
        testCase(RunloopTests.allTests),
    ]
}
#endif
