# QuickJS-Swift

Swift bindings to QuickJS.

### Usage

```swift
import QuickJS

let rt = QuickJSRuntime()!
let ctx = rt.createContext()!

let jsCode = "var i = 10; i;"
let result: Int64? = ctx.eval(jsCode)
print("Result is \(result!)") //10
```

#### Create a native module

```swift
import QuickJS
import QuickJSC

let rt = QuickJSRuntime()!
let ctx = rt.createContext()!
let module = ctx.createModule("Magic")!

// register a new function `getMagic`
module.reigister("getMagic", argc:0, function: { (ctx, this, argc, argv) -> JSValue in
    return JS_NewInt64(ctx, 10);
})

let getMagic = "import { getMagic } from 'Magic'; globalThis.magic = getMagic();"
let _:QuickJSError? = ctx.eval(getMagic, type: .module)

let magic: Int64? = ctx.eval("magic;")
print("Magic is \(magic!)") //10
```

### Swift Package Manager

Add this dependency to your `Package.swift` file:

```swift
.package(url: "https://github.com/zqqf16/QuickJS-Swift.git", .branch("master")),
```



