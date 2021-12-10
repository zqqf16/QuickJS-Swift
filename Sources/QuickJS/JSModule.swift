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
    
    func add(toContext context: JSContextWrapper)
}

public class JSModuleFunction : JSFunction, JSModuleProperty {
    required public init(_ name: String, argc: Int32, block: @escaping Block) {
        super.init(nil, name: name, argc: argc, block: block)
    }
    
    required init(_ context: JSContextWrapper?, value: JSCValue, dup: Bool = false, autoFree: Bool = true) {
        fatalError("init(_:value:dup:autoFree) has not been implemented")
    }
    
    public var jsValue: JSCValue {
        return self.cValue
    }
    
    public func add(toContext context: JSContextWrapper) {
        self.context = context
    }
}

fileprivate struct JSModuleCombineProperty : JSModuleProperty {
    var jsValue: JSCValue = .undefined
    var name: String
    var children: [JSModuleProperty]
    
    init(_ children: [JSModuleProperty]) {
        self.name = "<DUMY>"
        self.children = children
    }
    
    func add(toContext context: JSContextWrapper) {
        self.children.forEach { obj in
            obj.add(toContext: context)
        }
    }
}

@resultBuilder
public struct ModuleBuilder {
    static func buildBlock(_ components: JSModuleProperty...) -> JSModuleProperty {
        return JSModuleCombineProperty(components)
    }
}

public class JSModule {
    public var name: String
    var properties: [String: JSModuleProperty] = [:]

    var context: JSContextWrapper?
    var jsInstance: OpaquePointer
    
    required init(_ context: JSContextWrapper, module: OpaquePointer, name: String, @ModuleBuilder _ propertyBuilder: () -> JSModuleProperty) {
        self.jsInstance = module
        self.context = context
        self.name = name
        
        let property = propertyBuilder()
        if property is JSModuleCombineProperty {
            let children = (property as! JSModuleCombineProperty).children
            children.forEach { obj in
                self.properties[obj.name] = obj
            }
        } else {
            self.properties[property.name] = property
        }
        
        self.properties.forEach { (key, value) in
            value.add(toContext: self.context!)
            self.addExport(key)
        }
    }

    public func function(_ name: String, argc: Int32, block: @escaping JSFunction.Block) {
        let function = JSModuleFunction(name, argc: argc, block: block)
        function.add(toContext: self.context!)
        self.properties[name] = function
        self.addExport(name)
    }
    
    func addExport(_ name: String) {
        context?.addExport(module: jsInstance, name: name)
    }
    
    func load() {
        self.properties.forEach { (key, value) in
            context?.setExport(module: jsInstance, name: key, value: value.jsValue)
        }
    }
}
