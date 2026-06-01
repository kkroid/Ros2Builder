param(
    [string]$Workdir = (Join-Path (Join-Path $PSScriptRoot '..\..') 'work\windows'),
    [string]$Manifest = (Join-Path (Join-Path $PSScriptRoot '..\..') 'manifests\ros2-humble-android.repos'),
    [string]$BuildType = 'Release',
    [ValidateSet('x64')]
    [string]$Arch = 'x64',
    [string]$PythonExe = 'python',
    [string]$NinjaExe = 'ninja',
    [AllowEmptyString()]
    [string]$GitProxy = $null,
    [AllowEmptyString()]
    [string]$DownloadProxy = $null,
    [string]$BuildPackages = '',
    [string]$RmwImplementation = 'rmw_fastrtps_dynamic_cpp',
    [ValidateSet('ON', 'OFF')]
    [string]$BuildSharedLibs = 'ON',
    [ValidateSet('x64-windows', 'x64-windows-static')]
    [string]$Triplet = 'x64-windows',
    [string]$BuildOutputSuffix = '',
    [switch]$DisableRmwRuntimeSelection,
    [string]$StaticTypesupportC = '',
    [string]$StaticTypesupportCpp = '',
    [switch]$Static,
    [switch]$SkipPythonPackages,
    [switch]$SkipVcpkg,
    [switch]$SkipFetch,
    [switch]$NoPackage
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

# -Static expands to the proven Android static-library recipe (see .env.example):
# static ROS 2 libraries + Fast DDS dynamic RMW + introspection typesupport,
# linked against the static-CRT vcpkg triplet. Explicit parameters still win.
if ($Static) {
    if (-not $PSBoundParameters.ContainsKey('BuildSharedLibs')) { $BuildSharedLibs = 'OFF' }
    if (-not $PSBoundParameters.ContainsKey('Triplet')) { $Triplet = 'x64-windows-static' }
    if (-not $PSBoundParameters.ContainsKey('RmwImplementation')) { $RmwImplementation = 'rmw_fastrtps_dynamic_cpp' }
    if (-not $PSBoundParameters.ContainsKey('DisableRmwRuntimeSelection')) { $DisableRmwRuntimeSelection = $true }
    if (-not $PSBoundParameters.ContainsKey('StaticTypesupportC')) { $StaticTypesupportC = 'rosidl_typesupport_introspection_c' }
    if (-not $PSBoundParameters.ContainsKey('StaticTypesupportCpp')) { $StaticTypesupportCpp = 'rosidl_typesupport_introspection_cpp' }
    if (-not $PSBoundParameters.ContainsKey('BuildOutputSuffix')) { $BuildOutputSuffix = 'static' }
    if (-not $PSBoundParameters.ContainsKey('BuildPackages')) { $BuildPackages = 'rclcpp rmw_fastrtps_dynamic_cpp std_msgs' }
}

$repoRoot = Get-RepoRoot
$Workdir = Resolve-RepoPath $Workdir
$Manifest = Resolve-RepoPath $Manifest
$thirdPartyWindows = Join-Path $repoRoot 'third_party\windows'
$sourceDir = Join-Path $Workdir 'src'
$buildLabel = "windows_$Arch"
if ($BuildOutputSuffix) { $buildLabel = "${buildLabel}_$BuildOutputSuffix" }
$buildBase = Join-Path $Workdir "build\$buildLabel"
$installBase = Join-Path $Workdir "install\$buildLabel"
$logBase = Join-Path $Workdir "log\$buildLabel"
$inventoryFile = Join-Path $Workdir 'source-inventory.tsv'
$missingManifest = Join-Path $Workdir 'missing-sources.repos'

function ConvertTo-CMakePath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return ($Path -replace '\\', '/')
}

if ($PSBoundParameters.ContainsKey('GitProxy')) {
    Set-GitHubProxyOverride -GitProxy $GitProxy
}

if ($PSBoundParameters.ContainsKey('DownloadProxy')) {
    Set-DownloadProxyOverride -DownloadProxy $DownloadProxy
}

if (-not $BuildPackages) {
    $BuildPackages = if ($env:BUILD_PACKAGES) { $env:BUILD_PACKAGES } else { 'rclcpp rmw_fastrtps_dynamic_cpp std_msgs' }
}

& (Join-Path $PSScriptRoot 'ensure_windows_deps.ps1') -PythonExe $PythonExe -NinjaExe $NinjaExe -Quiet

$pathPrefixes = @()
$pythonDir = Split-Path $PythonExe -Parent
if ($pythonDir) {
    $pythonScriptsDir = Join-Path $pythonDir 'Scripts'
    if (Test-Path $pythonScriptsDir) {
        $pathPrefixes += $pythonScriptsDir
    }
    $pathPrefixes += $pythonDir
}

$ninjaDir = Split-Path $NinjaExe -Parent
if ($ninjaDir) {
    $pathPrefixes += $ninjaDir
}

if ($pathPrefixes.Count -gt 0) {
    $env:PATH = (($pathPrefixes | Select-Object -Unique) -join ';') + ';' + $env:PATH
}

if (-not $SkipPythonPackages) {
    Invoke-External $PythonExe @('-m', 'pip', 'install', '--upgrade', 'pip', 'wheel')
    Invoke-External $PythonExe @(
        '-m', 'pip', 'install',
        'colcon-common-extensions',
        'vcstool',
        'empy==3.3.4',
        'lark',
        'catkin_pkg',
        'numpy<2',
        'packaging',
        'PyYAML',
        'setuptools==59.6.0'
    )
}

if (-not $SkipVcpkg) {
    $setupVcpkgArgs = @('-Arch', $Arch, '-Triplet', $Triplet)
    if ($PSBoundParameters.ContainsKey('GitProxy')) {
        $setupVcpkgArgs += @('-GitProxy', $GitProxy)
    }
    if ($PSBoundParameters.ContainsKey('DownloadProxy')) {
        $setupVcpkgArgs += @('-DownloadProxy', $DownloadProxy)
    }
    if ($ninjaDir) {
        $setupVcpkgArgs += @('-ExtraPath', $ninjaDir)
    }
    & (Join-Path $PSScriptRoot 'setup_vcpkg.ps1') @setupVcpkgArgs
}

if (-not (Test-Path $thirdPartyWindows)) {
    throw "Missing third-party Windows dependency tree: $thirdPartyWindows. Run scripts/windows/setup_vcpkg.ps1 first."
}

$vcVarsAll = Get-VcVarsAll
Import-VcVarsEnvironment -VcVarsAll $vcVarsAll -Arch $Arch

$env:PATH = (Join-Path $thirdPartyWindows 'bin') + ';' + $env:PATH
$cmakePrefixPaths = @($thirdPartyWindows)
if ($env:CMAKE_PREFIX_PATH) {
    $cmakePrefixPaths += $env:CMAKE_PREFIX_PATH -split ';' | Where-Object { $_ }
}
$env:CMAKE_PREFIX_PATH = ($cmakePrefixPaths | Select-Object -Unique) -join ';'
$env:RMW_IMPLEMENTATION = $RmwImplementation

$installPythonPath = Join-Path $installBase 'Lib\site-packages'
New-Item -ItemType Directory -Force $installPythonPath | Out-Null
$pythonPaths = @($installPythonPath)
if ($env:PYTHONPATH) {
    $pythonPaths += $env:PYTHONPATH -split ';' | Where-Object { $_ }
}
$env:PYTHONPATH = ($pythonPaths | Select-Object -Unique) -join ';'

New-Item -ItemType Directory -Force $sourceDir | Out-Null

$validateArgs = @(
    (Join-Path $repoRoot 'scripts\validate_sources.py'),
    '--manifest', $Manifest,
    '--src', $sourceDir,
    '--check-existing'
)

if (-not $SkipFetch) {
    $validateArgs += @('--write-missing-manifest', $missingManifest)
}

Invoke-External $PythonExe $validateArgs

if (-not $SkipFetch) {
    $vcsCommand = "vcs import --shallow --workers 1 `"$sourceDir`" < `"$missingManifest`""
    Invoke-External cmd.exe @('/d', '/s', '/c', $vcsCommand)
}

Invoke-External $PythonExe @(
    (Join-Path $repoRoot 'scripts\validate_sources.py'),
    '--manifest', $Manifest,
    '--src', $sourceDir,
    '--check-existing',
    '--write-inventory', $inventoryFile
)

if ($BuildSharedLibs -eq 'OFF') {
    # Static Windows builds need source-level fixes the shared build does not:
    #  - strip hard-coded SHARED so a few packages honour BUILD_SHARED_LIBS=OFF
    #  - define the *_BUILDING_DLL export macro on generated static type-support
    #    libs so MSVC exports (instead of importing) their symbols (fixes C2491)
    # The patch script is idempotent, so it is safe to run on every build.
    Invoke-External powershell @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', (Join-Path $PSScriptRoot 'apply_windows_patches.ps1'),
        '-SourceDir', $sourceDir
    )
}

$packageList = $BuildPackages -split '\s+' | Where-Object { $_ }
if ($packageList.Count -eq 0) {
    throw 'BuildPackages is empty.'
}

$cmakeNinjaExe = ConvertTo-CMakePath $NinjaExe
$cmakePythonExe = ConvertTo-CMakePath $PythonExe
$cmakeAsioIncludeDir = ConvertTo-CMakePath (Join-Path $thirdPartyWindows 'include')

$cmakeArgs = @(
    '-G', 'Ninja',
    "-DCMAKE_MAKE_PROGRAM=$cmakeNinjaExe",
    "-DPython3_EXECUTABLE=$cmakePythonExe",
    "-DPYTHON_EXECUTABLE=$cmakePythonExe",
    "-DAsio_INCLUDE_DIR=$cmakeAsioIncludeDir",
    "-DBUILD_SHARED_LIBS=$BuildSharedLibs",
    "-DCMAKE_BUILD_TYPE=$BuildType",
    '-DBUILD_TESTING=OFF',
    '-DSECURITY=OFF',
    '-DSHM_TRANSPORT_DEFAULT=OFF',
    '-DTHIRDPARTY=OFF',
    '-DTHIRDPARTY_UPDATE=OFF',
    "-DRMW_IMPLEMENTATION=$RmwImplementation"
)

if ($DisableRmwRuntimeSelection) {
    $cmakeArgs += '-DRMW_IMPLEMENTATION_DISABLE_RUNTIME_SELECTION=ON'
}
if ($StaticTypesupportC) {
    $cmakeArgs += "-DSTATIC_ROSIDL_TYPESUPPORT_C=$StaticTypesupportC"
}
if ($StaticTypesupportCpp) {
    $cmakeArgs += "-DSTATIC_ROSIDL_TYPESUPPORT_CPP=$StaticTypesupportCpp"
}
if ($BuildSharedLibs -eq 'OFF') {
    # Static ROS 2 must use the static MSVC runtime (/MT) to match the static
    # vcpkg triplet and avoid mixing CRTs across the single linked artifact.
    # CMAKE_MSVC_RUNTIME_LIBRARY is only honored when policy CMP0091 is NEW.
    # Fast-CDR (and other deps) declare cmake_minimum_required compatible with
    # CMake < 3.15, so without forcing the policy they silently fall back to /MD
    # and produce a CRT mismatch (LNK2038/LNK1319) when linked against /MT code.
    $cmakeArgs += '-DCMAKE_POLICY_DEFAULT_CMP0091=NEW'
    $cmakeArgs += '-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded$<$<CONFIG:Debug>:Debug>'
    $cmakeArgs += '-DCMAKE_POSITION_INDEPENDENT_CODE=ON'
    # The Python (.pyd) bindings are dynamic modules that have no place in a
    # static, DLL-free bridge, and their long generated object paths overflow
    # CMAKE_OBJECT_PATH_MAX on Windows (fatal error C1083). The matching
    # register_py.cmake guard is installed by apply_windows_patches.ps1.
    $cmakeArgs += '-DROSIDL_GENERATOR_PY_DISABLE=ON'

    # Consumer-side visibility fix (MSVC only).
    #
    # ROS 2's visibility_control.h has no "static" branch: a package's
    # `<PKG>_PUBLIC` macro expands to `__declspec(dllimport)` unless the
    # matching `<PKG>_BUILDING_(DLL|LIBRARY)` macro is defined. CMake only
    # defines that macro while building the package *itself*, so when a
    # consumer (e.g. rclcpp) compiles a *producer* header (rcl/rcutils/rmw)
    # it sees `dllimport` and emits `__imp_<sym>` references. Those indirect
    # symbols do not exist in a static archive (which carries only the plain
    # `<sym>`), so a fully-static link fails with hundreds of LNK2019
    # (e.g. `__imp_rcl_node_init`, `__imp_rcutils_*`, `__imp_rmw_*`).
    #
    # On GCC/Clang `<PKG>_IMPORT` is empty, so consumers already emit direct
    # references — which is why the Android static build links cleanly and
    # this patch is Windows-only.
    #
    # The fix lives in static_visibility_defs.cmake, injected here via
    # CMAKE_PROJECT_INCLUDE so it runs after every package's project() call and
    # globally defines the core BUILDING macros with add_compile_definitions().
    # We deliberately do NOT set CMAKE_CXX_FLAGS for this: overriding it drops
    # the MSVC defaults (notably /EHsc), which sends Fast-DDS/boost down the
    # BOOST_NO_EXCEPTIONS path and breaks the link with unresolved
    # boost::throw_exception.
    #
    # NOTE: producer object files already carry `dllexport` directives (each
    # package defines its own BUILDING macro when built), so the final bridge
    # DLL will re-export those ROS 2 symbols. That export-table "pollution" is
    # cosmetic — the host only ever resolves HrxRos2BridgeGetVTable and never
    # links ROS 2 directly. Stripping the table to a single export would
    # require neutralizing the producer EXPORT macro too (a separate change).
    $staticVisibilityInclude = ConvertTo-CMakePath (Join-Path $PSScriptRoot 'static_visibility_defs.cmake')
    $cmakeArgs += "-DCMAKE_PROJECT_INCLUDE=$staticVisibilityInclude"
}

$colconArgs = @(
    '--log-base', $logBase,
    'build',
    '--merge-install',
    '--base-paths', $sourceDir,
    '--build-base', $buildBase,
    '--install-base', $installBase,
    '--packages-up-to'
) + $packageList + @('--cmake-args') + $cmakeArgs

Write-Host "Building Windows packages up to: $BuildPackages"
Write-Host "Workdir: $Workdir"
Write-Host "Install base: $installBase"
Write-Host "CMAKE_PREFIX_PATH: $env:CMAKE_PREFIX_PATH"
Invoke-External colcon $colconArgs -WorkingDirectory $Workdir

if (-not $NoPackage) {
    $artifactDir = Join-Path $repoRoot "work\dist\$buildLabel"
    & (Join-Path $PSScriptRoot 'package_windows_artifacts.ps1') `
        -Workdir $Workdir `
        -InstallPrefix $installBase `
        -ArtifactDir $artifactDir `
        -ThirdPartyDir $thirdPartyWindows `
        -Arch $Arch
}