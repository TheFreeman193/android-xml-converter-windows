# Android ABX/XML Converter for Windows

## November 2025

**The [upstream source](https://github.com/rhythmcache/android-xml-converter) now compiles without modifications on Windows with MSVC and this fork is no longer needed.**

---

This is an experimental project to convert between XML and Android Binary XML formats. Functionality is not guaranteed.

This fork includes modifications for building on Windows with Visual Studio 2022 for MSVC 17.

## Changes For Building On Windows

- The `__builtin_bswap*()` functions aren't available with the MSVC compiler, so are substituted here with MSVC's `_byteswap_*()` functions.
- Optionally, the C++23 standard library's type-agnostic `std::byteswap()` function can be used with the `-CXX23` switch in the [build script](./Build-Windows.ps1).
- `::isspace` is substituted with `std::isspace` from the standard library with `uchar` casting to avoid [undefined behavior](https://en.cppreference.com/w/cpp/string/byte/isspace#Notes).

## Licenses

The upstream source and modified source are licensed under the [Apache 2.0 License](https://www.apache.org/licenses/LICENSE-2.0) and this readme serves as documentation of the state changes and credits to the original authors.
The source in *abx2xml.cpp* is derived from code licensed under the [MIT License](https://spdx.org/licenses/MIT.html) by CCL Forensics (C) 2021-2024.
The license notices in each source file are updated additionally to document changes and by whom.

## Building

You must have at least one edition of [Visual Studio 2022](https://visualstudio.microsoft.com/vs/) installed with the *Desktop development with C++* module included.
The [free Community edition](https://visualstudio.microsoft.com/thank-you-downloading-visual-studio/?sku=Community&channel=Release&version=VS2022) is perfectly fine.

You can run the [build script](./Build-Windows.ps1) directly from PowerShell or via the batch file wrapper.
The build script will try to load the correct VS2022 VC++ Developer environment and CMake executable.

Build script usage:

```powershell
# Default build - current system architecture, release mode, using .\build and .\out directories, relative to build script
.\Build-Windows.ps1

# Custom build - Parameters are positional as shown
.\Build-Windows.ps1 [[-BuildArch] <x86|x64|arm64>] [[-BuildType] <Release|Debug>] [[-BuildDir] <Path:Default='.\build'>] [[-OutputDir] <Path:Default='.\out'>] [-CXX23] [-NoKeepBuild]

# Clean configuration, build artifacts (if -KeepOutput not specified), and any generated files (CMakeLists.txt, C++23 patched source files etc.)
.\Build-Windows.ps1 -Clean [[-BuildDir] <Path:Default='.\build'>] [[-OutputDir] <Path:Default='.\out'>] [-KeepOutput]
```

Use `Get-Help .\Build-Windows.ps1 -Full` in a PowerShell prompt for more detailed help.

### Cross-Compiling For Other Architectures

If you're compiling for a system architecture other than your own (cross-compiling), you need the additional *build tools* components for each arch.

- Open the Visual Studio Installer
- Click *Modify* button for your edition
- Click the *Individual components* tab
- Type 'msvc build latest' into the search box
- Check the *build tools (Latest)* components for the additional architectures you want
- Click the *Modify* button in the bottom right to download and install the components

You can confirm you have the build tools you need by looking in the path:

```plaintext
C:\Program Files\Microsoft Visual Studio\2022\<edition>\VC\Tools\MSVC\<version>\bin\Host<arch>
```

For the latest MSVC v143 (at the time of writing) with Visual Studio Enterprise 2022 on a 64-bit system, this path would be:

```plaintext
C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Tools\MSVC\14.44.35207\bin\Hostx64
```

### Debug Builds

If you build with the `-Debug` switch, the resulting executables will depend on the debug libraries for MSVC instead of the release/redistributable ones.
If you're testing on the same system or another system with Visual Studio 2022 installed, these libraries should already be in your System* directories.

Each subfolder at this path contains the build tools for an additional architecture.

## Android's Default `abx2xml` and `xml2abx`

- `abx2xml` and `xml2abx` binaries found generally in /system/bin/ of android devices is just a shell script that acts as a wrapper for executing abx.jar. It depends on Java and app_process, making it reliant on Android’s runtime environment. Since it invokes Java code, it cannot run independently in environments where Java isn’t available and also the overhead of launching a Java process adds extra execution time.

## Standalone `abx2xml` and `xml2abx`

- This  `abx2xml` and `xml2abx` binary performs the same function—converting between ABX and XML but in a fully standalone manner. Unlike default android binaries, this binary does not require Java, or abx.jar to function.  

## Command Line Usage

Similar to default abx2xml and xml2abx:

```plaintext
abx2xml [-mr] [-i] input [output]
xml2abx [-i] input [output]
abxtool abx2xml [-mr] [-i] input [output]
abxtool xml2abx [-i] input [output]
```

- When invoked with the `-i` argument, the output of a successful conversion will overwrite the original input file.
- For abx2xml, output can be '-' to use `stdout`.
- For xml2abx, input can be '-' to use `stdin`.

## Credits

- [@android-bits](https://github.com/cclgroupltd/android-bits/tree/main/ccl_abx): abx2xml logic
- [@rhythmcache](https://github.com/rhythmcache/android-xml-converter): C++ implementation

---
