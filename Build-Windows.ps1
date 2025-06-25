<#
Copyright 2025 Nicholas Bissell (TheFreeman193)

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
#>

# Compile ABX/XML tools for Windows MSVC

using namespace System.Management.Automation
using namespace System.IO

[CmdletBinding(DefaultParameterSetName = 'Build')]
param(
    # Build architecture
    [Parameter(ParameterSetName = 'Build')]
    [ValidateSet('x64', 'x86', 'arm64', 'arm')]
    [string]$BuildArch = $($env:PROCESSOR_ARCHITECTURE.ToLowerInvariant() -replace 'amd64', 'x64'),
    # Build type (for debug symbols)
    [Parameter(ParameterSetName = 'Build')]
    [ValidateSet('Release', 'Debug')]
    [string]$BuildType = 'Release',
    # Build files directory
    [Parameter(ParameterSetName = 'Build')]
    [Parameter(ParameterSetName = 'Clean')]
    [string]$BuildDir = 'build',
    # Output binaries directory
    [Parameter(ParameterSetName = 'Build')]
    [Parameter(ParameterSetName = 'Clean')]
    [string]$OutputDir = 'out',
    # Use C++23 standard library
    [Parameter(ParameterSetName = 'Build')]
    [switch]$CXX23,
    # Delete build files after compile
    [Parameter(ParameterSetName = 'Build')]
    [switch]$NoKeepBuild,
    # Clean build directory, output, and CMake lists then exit (for changing configurations)
    [Parameter(ParameterSetName = 'Clean')]
    [switch]$Clean,
    # Keeps the output files when cleaning build files
    [Parameter(ParameterSetName = 'Clean')]
    [switch]$KeepOutput,
    # Shortcut for Get-Help on this script
    [Parameter(ParameterSetName = 'Help')]
    [switch]$Help
)
begin {
    $Continue = $false
    if ($Help) {
        Get-Help $MyInvocation.MyCommand.Source
        return
    }

    $VSVersion = '2022'
    $VSGenerator = 'Visual Studio 17 2022'
    $CMakeMinVersion = '3.13'
    $BuildArch64Alt = $BuildArch.ToLowerInvariant() -replace 'x64', 'amd64'
    $BuildArch32Alt = $BuildArch.ToLowerInvariant() -replace 'x86', 'Win32'
    $AppVersion = '0.1.0'
    $CXXNewVer = '23'
    $CXXNewSuffix = "_cxx$CXXNewVer"
    $ARM32Sdk = '10.0.22621.0'

    # If we're building with C++23 standard, configure CMakeLists for it
    if ($CXX23) {
        $CXXVer = $CXXNewVer
        $CXXSuffix = $CXXNewSuffix
    } else {
        $CXXVer = '17'
        $CXXSuffix = ''
    }

    # Check we're on Windows
    if ($PSVersionTable.PSVersion -ge '6.0' -and $PSVersionTable.OS -notlike 'Microsoft Windows*') {
        $Err = [ErrorRecord]::new([PlatformNotSupportedException]::new('This build script only works on Windows.'), 'UnsupportedPlatform', 'NotImplemented', $PSVersionTable.OS)
        $PSCmdlet.WriteError($Err)
        return
    }
    $Continue = $true
}
process {
    if (-not $Continue) { return }
    Push-Location $PSScriptRoot

    # Clean up utility func
    function DoCleanup {
        [CmdletBinding()]
        param([switch]$KeepOutput)
        # Clean up build directory, protecting the output directory if it's a subdirectory
        if (Test-Path $BuildDir -PathType Container) {
            Write-Host -fo White "Cleaning build directory '$BuildDir'..."
            $BuildDirResolved = (Resolve-Path $BuildDir).Path.TrimEnd('/\ ')
            $BackupOutput = $false
            if ($KeepOutput -and (Test-Path $OutputDir -PathType Container)) {
                $OutputDirResolved = (Resolve-Path $OutputDir).Path.TrimEnd('/\ ')
                $BackupOutput = $OutputDirResolved.StartsWith($BuildDirResolved)
                if ($BackupOutput) {
                    $TDir = Join-Path ([Path]::GetTempPath()) (New-Guid).Guid
                    $null = New-Item -ItemType Directory $TDir
                    Move-Item $OutputDir $TDir -Force
                }
            }
            Remove-Item "$BuildDir\*" -Force -Recurse
            if ($BackupOutput) {
                Move-Item "$TDir\*" (Split-Path $OutputDir -Parent) -Force
                Remove-Item $TDir -Recurse -Force -ErrorAction Ignore
            }
        }
        # Clean up C++23 patched C++ source
        if (($Clean -or $CXX23) -and -not [string]::IsNullOrWhiteSpace($CXXNewSuffix) -and (Test-Path "*$CXXNewSuffix.cpp")) {
            Write-Host -fo White 'Cleaning up C++23 files...'
            Remove-Item "abx2xml$CXXNewSuffix.cpp", "xml2abx$CXXNewSuffix.cpp", "abxtool$CXXNewSuffix.cpp" -Force -ErrorAction Ignore
        }
        # Clean up CMake Lists
        if (Test-Path 'CMakeLists.txt' -PathType Leaf) {
            Write-Host -fo White 'Cleaning CMakeLists.txt...'
            Remove-Item 'CMakeLists.txt' -Force
        }
        if ($KeepOutput) { return }
        # Clean up output files
        if (Test-Path $OutputDir -PathType Container) {
            Write-Host -fo White "Cleaning output directory '$OutputDir'..."
            Remove-Item "$OutputDir\*" -Force -Recurse
        }

    }

    # Clean-only mode
    if ($Clean) { DoCleanup -KeepOutput:$KeepOutput; Pop-Location; return }

    # Ensure build directory exists
    if (-not (Test-Path "$BuildDir")) {
        Write-Host -fo White "Creating build directory '$BuildDir'..."
        $null = New-Item -ItemType Directory "$BuildDir" -ErrorAction Stop
        if (-not $?) { Pop-Location; return }
    }

    # Ensure we have Visual Studio Dev Shell/vcvars present
    Write-Host -fo White "Detecting/launching VS $VSVersion Dev Shell..."
    if ([string]::IsNullOrWhiteSpace($env:VSCMD_VER)) {
        $VSDS = Get-Command "$env:ProgramFiles\Microsoft Visual Studio\$VSVersion\*\Common7\Tools\Launch-VsDevShell.ps1" -All -ErrorAction Stop | Select-Object -Last 1
        if (-not $?) { Pop-Location; return }
        & $VSDS -Latest -ExcludePrerelease -SkipAutomaticLocation -HostArch $env:PROCESSOR_ARCHITECTURE -Arch $BuildArch64Alt
        if (-not $? -or [string]::IsNullOrWhiteSpace($env:VSCMD_VER)) {
            $Err = [ErrorRecord]::new([InvalidPowerShellStateException]::new("Unable to properly configure the VS $VSVersion Dev Shell"), 'VisualStudioConfigError', 'ResourceUnavailable', $VSDS.Path)
            $PSCmdlet.WriteError($Err)
            return
        }
    }

    # ARM32 Cross-compile SDK overrides
    if ($BuildArch -eq 'arm') {
        $WinSdkOverride = @"

set(CMAKE_SYSTEM_VERSION $ARM32Sdk)
set(CMAKE_CXX_COMPILER_WORKS 1)

"@
    } else {
        $WinSdkOverride = ''
    }

    # Find a CMake executable
    Write-Host -fo White 'Detecting CMake executable...'
    foreach ($CMakeCmd in
        "$env:ProgramFiles\Microsoft Visual Studio\$VSVersion\*\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\$VSVersion\*\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe",
        'cmake.exe'
    ) {
        $CMake = Get-Command $CMakeCmd -ErrorAction SilentlyContinue
        if ($null -ne $CMake) { break }
    }
    if (-not $? -or $null -eq $CMake) {
        $Err = [ErrorRecord]::new([FileNotFoundException]::new("Couldn't find a CMake executable. Install Visual Studio $VSVersion and check 'Desktop development with C++'."), 'MissingFile', 'ResourceUnavailable', 'CMake.exe')
        $PSCmdlet.WriteError($Err)
        return
    }

    # Check source files are present
    foreach ($SourceFile in 'abx2xml', 'xml2abx', 'abxtool') {
        if (-not (Test-Path "$SourceFile.cpp")) {
            $Err = [ErrorRecord]::new([InvalidPowerShellStateException]::new("Missing source file '$SourceFile'"), 'MissingFile', 'ResourceUnavailable', "$SourceFile.cpp")
            $PSCmdlet.WriteError($Err)
            return
        }
        if ($CXX23) {
            # Patch to use C++23 standard library bit ops if wanted
            Write-Host -fo White "Patching '$SourceFile.cpp' for C++23..."
        (Get-Content -Raw "$SourceFile.cpp" -ErrorAction Stop) -replace
            '\b_byteswap_u(?:short|long|int64)\(', 'std::byteswap(' -replace
            '(#include <iostream>)(\r?\n)', '$1$2#include <bit>$2' |
                Set-Content "$SourceFile$CXXSuffix.cpp" -Force -NoNewline -ErrorAction Stop
            if (-not $?) { Pop-Location; return }
        }
    }

    # Generate CMake lists
    Set-Content 'CMakeLists.txt' -Value @"
cmake_minimum_required(VERSION $CMakeMinVersion)
$WinSdkOverride
project(android_xml_converter LANGUAGES CXX)

set(CMAKE_CXX_STANDARD $CXXVer)

add_executable(abx2xml abx2xml$CXXSuffix.cpp)
add_executable(xml2abx xml2abx$CXXSuffix.cpp)
add_executable(abxtool abxtool$CXXSuffix.cpp)

set_target_properties(abx2xml PROPERTIES VERSION $AppVersion)
set_target_properties(xml2abx PROPERTIES VERSION $AppVersion)
set_target_properties(abxtool PROPERTIES VERSION $AppVersion)
"@

    # CMake configure
    Write-Host -fo White 'Configuring build...'
    & $CMake -B $BuildDir -S . -G $VSGenerator -A $BuildArch32Alt
    if ($LASTEXITCODE -ne 0) { Pop-Location; return }

    # CMake build
    Write-Host -fo White 'Building C++ source...'
    & $CMake --build $BuildDir --config $BuildType
    if ($LASTEXITCODE -ne 0) { Pop-Location; return }

    # Copy artifacts
    Write-Host -fo White 'Copying build artifacts...'
    if (-not (Test-Path $OutputDir)) {
        $null = New-Item -ItemType Directory $OutputDir -ErrorAction Stop
    }
    if (-not $?) { Pop-Location; return }

    foreach ($Artifact in 'abx2xml', 'xml2abx', 'abxtool') {
        Copy-Item "$BuildDir\$BuildType\$Artifact.*" "$OutputDir\" -ErrorAction Stop
        if (-not $?) { Pop-Location; return }
    }

    # Remove generated files if wanted
    if ($NoKeepBuild) { DoCleanup -KeepOutput }

    Write-Host -fo Green 'Complete. ' -NoNewline
    Write-Host -fo White "The generated binaries should be found in '$(Join-Path $OutputDir '*.exe')'."

    Pop-Location
}

<#
.SYNOPSIS
    Builds the ABX/XML conversion tools for Windows.
.DESCRIPTION
    This script builds the Android Binary XML (ABX)/XML conversion tools for Windows using Visual Studio 2022.
.PARAMETER BuildArch
    The build architecture to use.
.PARAMETER BuildType
    The build type to use. Debug builds include PDB symbols for debugging in Visual Studio.
.PARAMETER BuildDir
    A valid writable path where configuration and build will be placed.
.PARAMETER OutputDir
    A valid writable path where compiled binaries are copied after the build succeeds.
.PARAMETER CXX23
    Uses C++23 standard library byteswap() instead of the MSVC _byteswap_*()
.PARAMETER NoKeepBuild
    Discards files in the build path after build. C++23 files/CMake lists are also discarded.
.PARAMETER Clean
    Removes all files in the build path, plus any generated C++23 source files and CMake lists, then exits.
.PARAMETER KeepOutput
    Used with -Clean, keeps output binaries in -OutputDir
.PARAMETER Help
    Show this help and exit. Use 'Get-Help .\Build-Windows.ps1' for more help options.
.NOTES
    This script runs only on Windows. Visual Studio 2022 Community, Professional, or Enterprise must be installed.
.LINK
    https://github.com/TheFreeman193/android-xml-converter-windows/blob/main/README.md
.LINK
    https://github.com/rhythmcache/android-xml-converter/blob/main/README.md
.EXAMPLE
    .\Build-Windows.ps1

    Builds the ABX tools with default configuration - x64 release using .\build and .\out directories, relative to
    this script
.EXAMPLE
    .\Build-Windows.ps1 -BuildArch x86 -BuildType Debug

    Builds for x86 (32-bit) Windows with debug symbols, using .\build and .\out directories.
.EXAMPLE
    .\Build-Windows.ps1 -BuildArch x64 -BuildDir "$env:TEMP\abxbuild" -OutputDir C:\abxtools -NoKeepBuild

    Builds for x64 (64-bit) Windows in release mode, using a temporary directory for build files and installing
    the resulting .exe binaries in C:\abxtools. The temporary directory will be deleted after the build.
.EXAMPLE
    .\Build-Windows.ps1 -BuildArch arm64 -CXX23

    Builds for ARM64 (64-bit) Windows using the C++23 standard libraries instead of MSVC ones for byte operations,
    using .\build and .\out directories.
.EXAMPLE
    .\Build-Windows.ps1 -Clean

    Clean all build and output files, CMake lists, and generated C++23 source files from the root, .\build, and
    ,\out directories.
.EXAMPLE
    .\Build-Windows.ps1 -Clean -KeepOutput -BuildDir .\mybuild -OutputDir .\bin

    Clean all build files, CMake lists, and generated C++23 source files from the root and .\mybuild directory,
    but keep output files in .\bin
#>
