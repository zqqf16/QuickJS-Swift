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
    var jsValue: JSCValue { get }

    func add(to context: JSContext)
}

public class JSModuleFunction: JSFunction, JSModuleProperty {
    public required init(_ name: String, argc: Int32, block: @escaping Block) {
        super.init(nil, name: name, argc: argc, block: block)
    }

    required init(_ context: JSContextWrapper?, value: JSCValue, dup: Bool = false, autoFree: Bool = true) {
        fatalError("init(_:value:dup:autoFree) has not been implemented")
    }

    public var jsValue: JSCValue {
        cValue
    }

    public func add(to context: JSContext) {
        self.context = context.core
    }
}

private struct JSModuleCombineProperty: JSModuleProperty {
    var jsValue: JSCValue = .undefined
    var name: String
    var children: [JSModuleProperty]

    init(_ children: [JSModuleProperty]) {
        self.name = "<DUMMY>"
        self.children = children
    }

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

public class JSModule {
    public var name: String
    var properties: [String: JSModuleProperty] = [:]

    weak var jsContext: JSContext?
    var context: JSContextWrapper?
    var jsInstance: OpaquePointer

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
    }

    func addExport(_ name: String) {
        context?.addExport(module: jsInstance, name: name)
    }

    func load() {
        for (key, value) in properties {
            context?.setExport(module: jsInstance, name: key, value: value.jsValue)
        }
    }
}
