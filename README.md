# QuickJS-Swift

![CI Status](https://github.com/zqqf16/QuickJS-Swift/actions/workflows/swift.yml/badge.svg)

Swift bindings for [QuickJS](https://bellard.org/quickjs/) (`2026-06-04`), with a serial `DispatchQueue` event loop for timers and Promise jobs.

**Current release:** `1.0.0`

> QuickJS is single-threaded. All engine access is serialized through the runtime's `JSEventLoop`.

### Quick start

```swift
import QuickJS

let runtime = JSRuntime()!
let context = runtime.createContext()!

let result = try context.evaluate("1 + 2;")
print(result.int!) // 3
```

### Runtime options

```swift
let runtime = JSRuntime(options: JSRuntimeOptions(
    memoryLimit: 8 * 1024 * 1024,
    enableStdModules: false,   // no std/os/Worker/filesystem loader (default)
    enableHelpers: true,       // console / print
    interruptHandler: { shouldStop },
    flushJobsAfterEval: true
))!
```

`enableStdModules` is only honored on macOS and Linux; on iOS/tvOS/watchOS the
`std`/`os` modules, filesystem loader, and Worker handlers are unavailable and
this option is ignored.

### Native modules

```swift
context.module("Magic") {
    JSModuleFunction("getMagic", argc: 0) { _, _, _, _ in 10 }
    JSModuleValue("version", "1.0")
}

try context.evaluate("""
import { getMagic, version } from 'Magic'
globalThis.magic = getMagic()
globalThis.version = version
""", options: EvalOptions(type: .module))
```

### Timers

```swift
context.enableEventLoop()

try context.evaluate("""
setTimeout(() => { console.log("hello") }, 100)
""")
```

`enableRunloop()` also installs a compatibility `Runloop` module.

Dropping the last reference to a `JSContext` cancels any pending timers
automatically — pending timers do not keep the context alive.

### Bytecode

```swift
let bytecode = try context.compile("40 + 2;")
let value = try context.evalBytecode(bytecode)
print(value.int!) // 42
```

### Swift Package Manager

```swift
.package(url: "https://github.com/zqqf16/QuickJS-Swift.git", from: "1.0.0")
```
