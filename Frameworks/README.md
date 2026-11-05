# Frameworks/

`Baresip.xcframework` is produced here by `Scripts/create-xcframework.sh`. It is
a build artifact and is **not** committed.

Once it exists, wire it into the package:

```swift
// Package.swift
.binaryTarget(name: "Baresip", path: "Frameworks/Baresip.xcframework"),

.target(
    name: "BaresipBridge",
    dependencies: ["Baresip"]   // makes <baresip.h> resolve in the bridge
),
```

With the binary target present, `BaresipBridge`'s
`#if __has_include(<baresip.h>)` guard flips to the real implementation and
`BaresipEngine.isEngineAvailable` returns `true`. Nothing above the bridge
changes — Domain, Data, use cases, and the public API are untouched.
