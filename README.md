## Building Windows Apps with Swift and Using Swift/WinRT

Swift on Windows has come a long way. What started as a cross-platform compiler effort has evolved into a scenario where you can write native Windows applications using Swift. The key enabler is the Windows Runtime (WinRT) - the modern API surface that powers everything from file dialogs to Bluetooth to the Windows Shell.

To call WinRT APIs from Swift, you need **bindings** - code that translates between Swift's calling conventions and COM's binary interface. While there are pre-built package repositories out there, many are archived, version-locked, or don't cover exactly what you need.

This is where **[Swift/WinRT](https://github.com/thebrowsercompany/swift-winrt)** comes in. It's a code generator (written in C++) that takes Windows Metadata (`.winmd`) files and produces both:
- C ABI headers that define the COM vtable structures
- Swift source files that wrap those vtables into native Swift classes, protocols, and methods

In this guide, we'll build `swift-winrt.exe` from source, use it to generate bindings for `Windows.Foundation` types (like `Uri`), create a Swift Package Manager project that consumes those bindings, and walk through every decision and pitfall along the way.

## Prerequisites

Before we begin, you'll need the following installed on your Windows machine.

### Swift Toolchain

The official Swift toolchain for Windows is available from [swift.org](https://www.swift.org/download/). However, as of this writing, the releases from The Browser Company have proven more reliable for building executables. Download the latest release that matches your system architecture from:

[Swift Build Releases](https://github.com/thebrowsercompany/swift-build/releases)

After installing, verify the toolchain:

```powershell
swift --version
```

### Git for Windows

You'll need Git to clone the repository and initialize submodules. Download from [git-scm.com](https://git-scm.com/) and ensure it's in your `PATH`. Verify the installation:

```powershell
git --version
```

### Visual Studio

You'll need Visual Studio 2022 (or later) with the "Desktop development with C++" workload. This provides the MSVC compiler (`cl.exe`) and the Windows SDK headers that `swift-winrt` depends on at build time.

Install from [visualstudio.microsoft.com](https://visualstudio.microsoft.com/).

### CMake and Ninja

The `swift-winrt` code generator is built with CMake. Install CMake from [cmake.org](https://cmake.org/) and ensure it's in your `PATH`. We'll use Ninja as the build system, which CMake can download on its own.

### Visual Studio Developer Environment

Building `swift-winrt` requires the MSVC compiler (`cl.exe`) and associated tools. These are only available inside a **Visual Studio Developer Environment** - a PowerShell session that has the compiler paths and environment variables loaded.

You can start one in two ways:

**Option A - Developer PowerShell (recommended):**
- Open the Start Menu and search for "Developer PowerShell for VS 2022"
- Or in Windows Terminal, click the `+` dropdown button and select "Developer PowerShell for VS 2022"

**Option B - Load into an existing PowerShell session:**
```powershell
Import-Module "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\Microsoft.VisualStudio.DevShell.dll"
Enter-VsDevShell -VsInstallPath "C:\Program Files\Microsoft Visual Studio\2022\Community" -SkipAutomaticLocation -Arch amd64
```

Make sure to use one of these sessions throughout the next section.

> **Why?** The `swift-winrt` CMake project uses `cl.exe` as its C/C++ compiler. A regular PowerShell doesn't have it in its PATH - only Developer PowerShell sessions include the Visual Studio build tools.

### Windows SDK

The Windows SDK ships with Visual Studio, but you may need a specific version depending on which API contracts you're targeting. To check which SDK versions you have installed:

```powershell
Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows Kits\Installed Roots" |
    Select-Object -ExpandProperty PSChildName |
    Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' }
```

During this guide, we'll target `10.0.26100.0` (the latest as of this writing). If you don't have this exact version, don't worry - the tooling we'll use later automatically picks the highest installed version. You can install a Windows SDK version using the Visual Studio Installer or go to the [Windows SDK download page](https://learn.microsoft.com/en-us/windows/apps/windows-sdk/downloads) to download it directly.

## Building swift-winrt.exe

> **Important**: Run all `cmake` commands from a **Developer PowerShell for VS 2022** session so the MSVC compiler (`cl.exe`) is in your PATH. See the prerequisites section above for setup instructions.

Start by cloning the repository and its submodules:

```powershell
git clone https://github.com/thebrowsercompany/swift-winrt.git
cd swift-winrt
git submodule init
git submodule update --recursive
```

The project uses CMake presets. Configure and build with:

```powershell
cmake --preset release
cmake --build --preset release
```

> We use the `release` preset because the debug build is significantly slower (as noted in the project's README).

This produces `swift-winrt.exe` in `build\release\swiftwinrt\`. Verify it works:

```powershell
.\build\release\swiftwinrt\swiftwinrt.exe
```

You should see the help output listing all supported options.

## Understanding the Command Line Options

Here's a reference of all available flags. The most important ones - `-input`, `-output`, `-include`, and `-exclude` - will be explained in detail when we set up the project below.

| Flag | Purpose |
|------|---------|
| `-input <spec>` | Windows Metadata to generate bindings **for**. Can be a `.winmd` file path, a folder, `local` (uses `%windir%\System32\WinMetadata`), `sdk[+]`, or a specific version like `10.0.26100.0[+]`. The `+` suffix includes Extension SDKs. |
| `-reference <spec>` | Windows Metadata to **reference** (dependencies, not generated). You typically use this when your input is a custom `.winmd` that depends on SDK types. |
| `-output <path>` | Directory where the generated `Sources/` tree will be written. |
| `-include <prefix>` | Namespace or specific type to generate bindings for. You can specify this multiple times. |
| `-exclude <prefix>` | Namespace or specific type to exclude. |
| `-overwrite` | Overwrite existing generated files (useful during iteration). |
| `-verbose` | Print detailed progress information. |
| `-ns-prefix` | Policy for prefixing type names with the ABI namespace (default: never). |
| `-support <module>` | Which module gets the runtime support files (default: `WindowsFoundation`). |

## Setting Up the SwiftPM Project

Now that we have our bindings generator built, let's create a project to use it.

### 1. Create the App Package

Create a new directory **separate from the `swift-winrt` repository**. Your app project lives in its own folder.

```powershell
mkdir C:\path\to\swift-on-windows-demo-2
cd C:\path\to\swift-on-windows-demo-2
swift package init --type executable --name App
```

This creates:

```
swift-on-windows-demo-2/
  Package.swift
  Sources/
    App/
      main.swift
  Tests/
    AppTests/
      App.swift
```

### 2. Create the Bindings Package

Inside your project, create a `generated/` directory. This will hold the generated bindings as a **helper package** that your main app depends on.

```powershell
mkdir generated
```

Inside `generated/`, create a `Package.swift`:

```swift
// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "generated",
    products: [
        .library(name: "CWinRT", targets: ["CWinRT"]),
        .library(name: "WindowsFoundation", targets: ["WindowsFoundation"]),
    ],
    targets: [
        .target(name: "CWinRT"),
        .target(
            name: "WindowsFoundation",
            dependencies: ["CWinRT"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
```

> **Why `swiftLanguageModes: [.v5]`?** Some of the generated support files use concurrency patterns that don't compile cleanly under Swift 6's strict concurrency checking. Using v5 mode for the generated package avoids this issue. Your app code (in the root package) can still use v6 mode.

Also place your response file inside `generated/`:

Create `generated/swiftwinrt.rsp` with the following content:

```
-input sdk+
-output C:\path\to\swift-on-windows-demo-2\generated

-include Windows.Foundation
-include Windows.Foundation.Collections
-include Windows.Foundation.Uri

-exclude Windows.Foundation.PropertyValue

-verbose
-overwrite
```

Let's understand each line:

- **`-input sdk+`**: Use the latest Windows SDK as the metadata source, including Extension SDKs. The tool reads the registry key `SOFTWARE\Microsoft\Windows Kits\Installed Roots` and picks the highest installed SDK version. On our machine with SDKs `10.0.17763.0`, `10.0.22621.0`, and `10.0.26100.0`, `sdk+` resolves to `10.0.26100.0`.
- **`-output C:\path\to\swift-on-windows-demo-2\generated`**: Write the generated files into the `generated/` directory inside our project.
- **`-include Windows.Foundation`**: Include the entire `Windows.Foundation` namespace. This gives us all types in that namespace, not just `Uri`. The release build adds roughly 613KB - a negligible cost for the convenience of having everything available.
- **`-include Windows.Foundation.Collections`**: Include the `Collections` namespace separately. The `-include` filter uses **exact namespace matching**, so `Windows.Foundation` does not cover `Windows.Foundation.Collections`. We need Collections because the runtime support files reference `IVector`, `IMap`, and related types.
- **`-include Windows.Foundation.Uri`**: A specific type include, redundant with the blanket `-include Windows.Foundation` above. It's shown here to demonstrate that you can target individual types with the same flag.
- **`-exclude Windows.Foundation.PropertyValue`**: Skip generating bindings for the SDK's `PropertyValue` type. The support files include a hand-written version (in `Support/propertyvalue.swift`) that maps `IInspectable` to `Any`. Both versions would land in the same Swift module, causing an "invalid redeclaration" error. This exclusion solves the conflict.

### 3. Generate the Bindings

Switch back to your **Developer PowerShell for VS 2022** session (where `swiftwinrt.exe` was built) and run:

```powershell
cd C:\path\to\swift-winrt
.\build\release\swiftwinrt\swiftwinrt.exe @C:\path\to\swift-on-windows-demo-2\generated\swiftwinrt.rsp
```

The `-output` path in the response file points to the `generated/` directory inside your project. The tool will create a `Sources/` tree there. With `-verbose` enabled, you'll see output like:

```
 tool:  C:\path\to\swift-winrt\build\release\swiftwinrt\swiftwinrt.exe
 ver:   0.0.1
 in:    C:\Program Files (x86)\Windows Kits\10\References\10.0.26100.0\...
 ref:   (none)
 out:   C:\path\to\swift-on-windows-demo-2\generated
```

After generation, your `generated/` folder contains this structure:

```
generated/
  Package.swift
  swiftwinrt.rsp
  Sources/
    CWinRT/
      include/
        module.modulemap        # Clang module definition for CWinRT
        CWinRT.h                # Umbrella header including all C ABI headers
        Windows.Foundation.h    # C ABI definitions for Windows.Foundation types
        Windows.Foundation.Collections.h
        ...
      shim.c                    # Forces the linker to produce a .lib
    WindowsFoundation/
      Support/
        aggregation.swift
        ...
        winsdk+extensions.swift
      Windows.Foundation.swift              # Type definitions (Uri, enums, etc.)
      Windows.Foundation+ABI.swift         # COM vtable wrappers
      Windows.Foundation+Impl.swift        # Interop bridge types
      Windows.Foundation.Collections.swift
      Windows.Foundation.Collections+ABI.swift
      Windows.Foundation.Collections+Impl.swift
      WindowsFoundation+Generics.swift     # Generic interface instantiations
```

### What Each Layer Does

**CWinRT (C module)**

This is a Clang module (`module.modulemap`) that exposes all the COM ABI types as C declarations. It includes Windows SDK headers (`<windows.h>`, `<combaseapi.h>`, `<roapi.h>`, etc.) and the generated namespace-specific headers that define COM vtable structs, IID constants, and interface typedefs.

The `module.modulemap` looks like:

```
module CWinRT {
    header "CWinRT.h"
    export *
}
```

The CWinRT layer is kept as a separate module because:
- Swift can import C modules through Clang, making all the ABI types and C functions available
- It prevents the Windows SDK's macro-heavy headers from polluting the Swift namespace
- It allows the Swift targets to depend on a clean C interop layer

**WindowsFoundation (Swift module)**

This is where the actual Swift bindings live. Each namespace gets three or four files:

- **`Windows.Foundation.swift`**: The public API - Swift typealiases for enums, struct definitions, protocol definitions for interfaces, and class bridges. This is what you `import` and use in your code.
- **`Windows.Foundation+ABI.swift`**: The ABI namespace (`__ABI_Windows_Foundation`) - Swift classes that wrap the C COM vtables with proper `QueryInterface`/`AddRef`/`Release` handling.
- **`Windows.Foundation+Impl.swift`**: The Impl namespace (`__IMPL_Windows_Foundation`) - bridge types that translate between Swift objects and COM interfaces.
- **`WindowsFoundation+Generics.swift`**: Generic interface instantiations (e.g., `IVector<Int32>`, `IMap<String, String>`) with their vtable entries.

**Support files**

The `Support/` directory contains hand-written runtime files that are embedded as resources in `swift-winrt.exe` and copied to the output during generation. They provide core infrastructure:

| File | Provides |
|------|----------|
| `comptr.swift` | `ComPtr<T>` - reference-counted COM pointer wrapper |
| `hstring.swift` | `HString` - WinRT string wrapper |
| `guid.swift` | `GUID` struct and utilities |
| `iunknown.swift` | `IUnknown` protocol and implementation |
| `iinspectable.swift` | `IInspectable` protocol and implementation |
| `winrtbridgeable.swift` | `WinRTBridgeable` protocol for type marshaling |
| `marshaler.swift` | Type marshaling between Swift and WinRT |
| `event.swift` | WinRT event support |
| `error.swift` | WinRT error-to-Swift-error conversion |
| `propertyvalue.swift` | Hand-written `PropertyValue` for `IInspectable` <-> `Any` mapping |
| `winsdk+extensions.swift` | SDK-specific extensions |

### 4. Wire Up the Root Package.swift

Replace your root `Package.swift` with this manifest that references the bindings as a local path dependency:

```swift
// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "App",
    dependencies: [
        .package(path: "generated")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "CWinRT", package: "generated"),
                .product(name: "WindowsFoundation", package: "generated"),
            ],
        ),
        .testTarget(
            name: "AppTests",
            dependencies: ["App"],
        ),
    ],
    swiftLanguageModes: [.v6]
)
```

The key lines are:

- **`.package(path: "generated")`**: Tells SPM to look at the `generated/` directory as a local swift package. It will read `generated/Package.swift` and make its products available.
- **`.product(name: "CWinRT", package: "generated")`**: Imports the `CWinRT` library (the C ABI Clang module) from the generated package.
- **`.product(name: "WindowsFoundation", package: "generated")`**: Imports the `WindowsFoundation` Swift bindings.

### 5. Write Your App

In your `Sources/App/App.swift` file:

```swift
import CWinRT
import WindowsFoundation

@main
struct App {
    static func main() {
        RoInitialize(RO_INIT_TYPE(1))

        let uri = Uri("https://www.swift.org/path?query=hello")
        print("AbsoluteUri: \(uri.absoluteUri)")
        print("SchemeName: \(uri.schemeName)")
        print("Host: \(uri.host)")
        print("Path: \(uri.path)")
        print("Query: \(uri.query)")
    }
}
```

> **Note:** We don't import `Foundation` because we don't need it - `CWinRT` provides `RoInitialize` through its Clang module, and `WindowsFoundation` provides `Uri` and all the WinRT types we use.

### 6. Build and Run

Build the project:

```powershell
swift build --product App
```

The executable is at `.build\debug\App.exe`. Run it:

```powershell
.\build\debug\App.exe
```

Expected output:

```
AbsoluteUri: https://www.swift.org/path?query=hello
SchemeName: https
Host: www.swift.org
Path: /path
Query: ?query=hello
```

### Final Project Structure

After all steps, your project looks like this:

```
swift-on-windows-demo-2/
  Package.swift                    # Root package manifest
  Sources/
    App/
      App.swift                    # Your app code
  Tests/
    AppTests/
      App.swift                    # Tests
  generated/
    Package.swift                  # Bindings package manifest (v5)
    swiftwinrt.rsp                 # Response file for regenerating
    Sources/
      CWinRT/
        include/
          module.modulemap
          CWinRT.h
          ...
        shim.c
      WindowsFoundation/
        Support/*.swift
        Windows.Foundation.swift
        Windows.Foundation+ABI.swift
        Windows.Foundation+Impl.swift
        Windows.Foundation.Collections.swift
        Windows.Foundation.Collections+ABI.swift
        Windows.Foundation.Collections+Impl.swift
        WindowsFoundation+Generics.swift
```

## COM Initialization - The Hidden Requirement

WinRT is built on COM (Component Object Model). Before calling any WinRT API on a thread, you must initialize COM for that thread. If you forget, you'll crash with:

```
Fatal error: 'try!' expression unexpectedly raised an error: 0x800401f0 - CoInitialize has not been called.
```

This happens because `RoGetActivationFactory` (which is called internally when you create a `Uri`, for example) checks the thread's COM apartment state and fails if it hasn't been initialized.

The fix is to call `RoInitialize` at the start of your application:

```swift
import CWinRT

RoInitialize(RO_INIT_TYPE(1))
```

`RoInitialize` is declared in `<roapi.h>`, which is included by `CWinRT.h`. By importing `CWinRT`, the function and the `RO_INIT_TYPE` enum are available in Swift.

The `RO_INIT_TYPE(1)` parameter corresponds to `RO_INIT_MULTITHREADED`, which places the thread in a multithreaded apartment (MTA). This is the standard choice for console applications and lets you call WinRT APIs from any thread in your process. The alternative `RO_INIT_TYPE(0)` (`RO_INIT_SINGLETHREADED`) is mainly used for UI threads with legacy COM controls.

> **Why `RO_INIT_TYPE(1)` instead of just `1`?** The C enum `RO_INIT_TYPE` is imported by Swift as a struct with a raw value initializer. Writing `RO_INIT_TYPE(1)` makes the intent clear and is the idiomatic way to use a C enum value in Swift.

`RoInitialize` is safe to call multiple times on the same thread - COM uses a reference count internally for initialization calls.

## Using the Uri Type

As we saw in the setup section, the `Uri` class from `Windows.Foundation` is projected into Swift as a native class.

### Why `schemeName` Instead of `scheme`?

WinRT properties follow PascalCase naming (e.g., `SchemeName`, `AbsoluteUri`, `DisplayUri`). The Swift/WinRT code generator converts these to Swift camelCase, so:

| WinRT Property | Swift Property |
|---------------|----------------|
| `Uri.SchemeName` | `uri.schemeName` |
| `Uri.AbsoluteUri` | `uri.absoluteUri` |
| `Uri.Host` | `uri.host` |
| `Uri.Path` | `uri.path` |
| `Uri.Query` | `uri.query` |
| `Uri.Port` | `uri.port` |
| `Uri.Fragment` | `uri.fragment` |
| `Uri.RawUri` | `uri.rawUri` |

### Build

```powershell
swift build --product App
```

### Run

```powershell
.\build\debug\App.exe
```

Expected output:

```
AbsoluteUri: https://www.swift.org/path?query=hello
SchemeName: https
Host: www.swift.org
Path: /path
Query: ?query=hello
```

## Testing

Swift Testing framework works on Windows. Here's how to write tests for your `Uri` usage, with `RoInitialize` called once per test suite:

```swift
import Testing
import WindowsFoundation
import CWinRT

struct UriTests {
    init() {
        RoInitialize(RO_INIT_TYPE(1))
    }

    @Test func properties() {
        let uri = Uri("https://www.swift.org/path?query=hello")
        #expect(uri.absoluteUri == "https://www.swift.org/path?query=hello")
        #expect(uri.schemeName == "https")
        #expect(uri.host == "www.swift.org")
        #expect(uri.path == "/path")
        #expect(uri.query == "?query=hello")
    }

    @Test func port() {
        let uri = Uri("http://localhost:8080/test")
        #expect(uri.host == "localhost")
        #expect(uri.port == 8080)
        #expect(uri.path == "/test")
    }

    @Test func fragment() {
        let uri = Uri("https://example.com/page#section")
        #expect(uri.fragment == "#section")
    }

    @Test func relativeUri() {
        let base = Uri("https://example.com/base/")
        let relative = try? base.combineUri("child")
        #expect(relative?.absoluteUri == "https://example.com/base/child")
    }

    @Test func escaping() {
        let escaped = try? Uri.escapeComponent("hello world")
        #expect(escaped == "hello%20world")

        let unescaped = try? Uri.unescapeComponent("hello%20world")
        #expect(unescaped == "hello world")
    }
}
```

Using a struct-level `init()` means `RoInitialize` runs before each test method. This is safe because `RoInitialize` is reference-counted - calling it multiple times on the same thread just increments a counter.

## Summary of Key Decisions

Throughout this process, we made several choices that are worth explaining:

### Why generate bindings yourself instead of using pre-built packages?

Pre-built packages (like the archived `swift-windowsfoundation` repos) are tied to specific SDK versions and may not include the exact set of types you need. Generating your own bindings gives you full control over which API surfaces are available and which SDK version they target.

### Why does the support file define its own PropertyValue?

The hand-written `PropertyValue` class in `Support/propertyvalue.swift` provides custom logic for wrapping arbitrary Swift values into `IInspectable` objects and unwrapping them back. This is necessary because WinRT's `PropertyValue` is used for boxing - converting value types (Int, String, etc.) into COM objects and back. The generated bindings define a `PropertyValue` that maps directly to the WinRT API surface, but without the custom boxing logic that the Swift projection needs to bridge between `Any` and `IInspectable`.

### Why does COM need to be initialized?

WinRT is fundamentally built on COM. Every WinRT API call goes through COM interfaces, and COM requires the calling thread to specify its concurrency model via `CoInitializeEx` or `RoInitialize`. This is not unique to Swift - every language projection for WinRT (C++, Rust, C#, etc.) requires this step. In a C++/WinRT app, you call `winrt::init_apartment()` at the start of `main()`. In Swift, you call `RoInitialize(RO_INIT_TYPE(1))` instead. Both are explicit.

## Limitations and Future Work

What we've covered here is the foundation - using `Windows.Foundation.Uri` as a first WinRT API. Here's what's next:

- **More namespaces**: The same process works for `Windows.Storage`, `Windows.System`, `Windows.Networking`, and any other WinRT namespace. Just add more `-include` flags.

- **Custom .winmd components**: If you write your own WinRT component in C++/WinRT, you can point `-input` at your `.winmd` file to generate Swift bindings for it.

- **The `-spm` flag**: Swift/WinRT has a declared `-spm` option that's meant to generate a `Package.swift` automatically, but it's currently unimplemented (dead code). This means the `Package.swift` must be hand-written today. This would be a great contribution to the project.

- **WinUI and WinAppSDK**: Once you have the Windows.Foundation bindings working, the same generation process can produce bindings for `Microsoft.UI.Xaml` (WinUI) and `Microsoft.Windows.AppLifecycle` (Windows App SDK), enabling native UI applications.
