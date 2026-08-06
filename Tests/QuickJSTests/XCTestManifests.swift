import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(QuickJSSwiftTests.allTests),
        testCase(RunloopTests.allTests),
    ]
}
#endif
