// QuickJS Swift
//
// Copyright (c) 2021 zqqf16
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation
import QuickJSC

public protocol JSModuleProperty {
    var name: String { get }
    func exportValue(in context: JSContext) -> JSValue
    func add(to context: JSContext)
}

public class JSModuleFunction: JSFunction, JSModuleProperty, @unchecked Sendable {
    private var didExport = false

    public init(_ name: String, argc: Int32, block: @escaping Block) {
        super.init(nil, name: name, argc: argc, block: block)
    }

    @available(*, unavailable, message: "JSModuleFunction cannot wrap an existing JS value")
    required init(_ context: JSContextWrapper?, value: JSCValue, dup: Bool = false, autoFree: Bool = true) {
        fatalError("JSModuleFunction cannot wrap an existing JS value")
    }

    @available(*, unavailable, message: "JSModuleFunction cannot wrap an existing JS value")
    public required convenience init?(_ context: JSContext, value: JSCValue) {
        fatalError("JSModuleFunction cannot wrap an existing JS value")
    }

    public func exportValue(in context: JSContext) -> JSValue {
        // First export transfers ownership of the C function value; later exports dup.
        if didExport {
            return JSValue(context, value: cValue, dup: true, autoFree: true)
        }
        didExport = true
        return JSValue(context, value: cValue, dup: false, autoFree: false)
    }

    public func add(to context: JSContext) {
        self.context = context.core
    }
}

/// A constant / value export for native modules.
public struct JSModuleValue: JSModuleProperty {
    public let name: String
    private let makeValue: (JSContext) -> JSValue

    public init<T: ConvertibleWithJavascript>(_ name: String, _ value: T) {
        self.name = name
        self.makeValue = { context in value.jsValue(context) }
    }

    public init(_ name: String, builder: @escaping (JSContext) -> JSValue) {
        self.name = name
        self.makeValue = builder
    }

    public func exportValue(in context: JSContext) -> JSValue {
        makeValue(context)
    }

    public func add(to context: JSContext) {}
}

private struct JSModuleCombineProperty: JSModuleProperty {
    var name: String = "<DUMMY>"
    var children: [JSModuleProperty]

    init(_ children: [JSModuleProperty]) {
        self.children = children
    }

    func exportValue(in context: JSContext) -> JSValue { .undefined }

    func add(to context: JSContext) {
        children.forEach { $0.add(to: context) }
    }
}

@resultBuilder
public struct ModuleBuilder {
    public static func buildBlock(_ components: JSModuleProperty...) -> JSModuleProperty {
        JSModuleCombineProperty(components)
    }
}

public final class JSModule: @unchecked Sendable {
    public let name: String
    private(set) var properties: [String: JSModuleProperty] = [:]
    private weak var jsContext: JSContext?
    private var context: JSContextWrapper?
    private var jsInstance: OpaquePointer
    private var didLoad = false

    required init(_ context: JSContext, module: OpaquePointer, name: String, @ModuleBuilder _ propertyBuilder: () -> JSModuleProperty) {
        self.jsInstance = module
        self.jsContext = context
        self.context = context.core
        self.name = name

        let property = propertyBuilder()
        if let combined = property as? JSModuleCombineProperty {
            for obj in combined.children {
                properties[obj.name] = obj
            }
        } else {
            properties[property.name] = property
        }

        for (key, value) in properties {
            value.add(to: context)
            addExport(key)
        }
    }

    public func function(_ name: String, argc: Int32, block: @escaping JSFunction.Block) {
        guard let jsContext = jsContext else { return }
        let function = JSModuleFunction(name, argc: argc, block: block)
        function.add(to: jsContext)
        properties[name] = function
        addExport(name)
        if didLoad {
            setExport(name, value: function.exportValue(in: jsContext))
        }
    }

    public func value<T: ConvertibleWithJavascript>(_ name: String, _ value: T) {
        guard let jsContext = jsContext else { return }
        let property = JSModuleValue(name, value)
        properties[name] = property
        addExport(name)
        if didLoad {
            setExport(name, value: property.exportValue(in: jsContext))
        }
    }

    func addExport(_ name: String) {
        context?.addExport(module: jsInstance, name: name)
    }

    func setExport(_ name: String, value: JSValue) {
        context?.setExport(module: jsInstance, name: name, value: value.steal())
    }

    func load() {
        guard let jsContext = jsContext else { return }
        didLoad = true
        for (key, value) in properties {
            setExport(key, value: value.exportValue(in: jsContext))
        }
    }
}
