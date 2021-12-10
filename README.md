# QuickJS-Swift

![CI Status](https://github.com/zqqf16/QuickJS-Swift/actions/workflows/swift.yml/badge.svg) 

Swift bindings to QuickJS. Using **NSRunloop** to implement asynchronization.

### Usage

#### Execute javascript code

```swift
import QuickJS

let runtime = JSRuntime()!
let context = runtime.createContext()!

let jsCode = "var i = 10; i;"
let result = context.eval(jsCode).int
print("Result is \(result!)") //10
```

#### Create a native module

```swift
import QuickJS

let runtime = JSRuntime()!
let context = runtime.createContext()!

// Create a module named "Magic" with two functions "getMagic" and "getMagic2"
context.module("Magic") {
    JSModuleFunction("getMagic", argc: 0) { context, this, argc, argv in
        return 10
    }
    JSModuleFunction("getMagic2", argc: 0) { context, this, argc, argv in
        return 20
    }
}

let getMagic = """
"use strict";
import { getMagic, getMagic2 } from 'swift'
globalThis.magic = getMagic();
globalThis.magic2 = getMagic2();
"""

context.eval(getMagic, type: .module)

let magic = context.eval("magic;").int
print("Magic is \(magic!)") //10

let magic2 = context.eval("magic2;").int
print("Magic2 is \(magic2!)") //20
```

#### Runloop

```swift
let runtime = JSRuntime()!
let context = runtime.createContext()!
context.enableRunloop()
  
let jsCode = """
"use strict";
import * as rl from "Runloop";
rl.setTimeout(function(){ console.log("Hello Runloop"); }, 3000);
"""

let _ = context.eval(jsCode, type: .module)
  
// waiting for 3 seconds
// Hello Runloop
```

### Swift Package Manager

Add this dependency to your `Package.swift` file:

```swift
.package(url: "https://github.com/zqqf16/QuickJS-Swift.git", .branch("master")),
```



