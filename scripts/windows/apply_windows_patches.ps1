<#
.SYNOPSIS
    Apply Windows static-build patches to the fetched ROS 2 sources.

.DESCRIPTION
    When ROS 2 is built with BUILD_SHARED_LIBS=OFF on Windows (MSVC), two
    classes of problems appear that the Linux/Android recipe never hits:

      1. A few packages hard-code `add_library(... SHARED ...)`, so they keep
         producing DLLs even in a static build. We strip the explicit SHARED
         keyword so they honour BUILD_SHARED_LIBS (mirrors the Android patches
         for rmw_dds_common and rosidl_typesupport_fastrtps_cpp).

      2. The rosidl message/type-support generators decorate their generated
         symbols with the per-package `*_PUBLIC` visibility macro. That macro
         expands to `__declspec(dllimport)` unless the matching
         `*_BUILDING_DLL[_<pkg>]` macro is defined. CMake only defines it (via
         the target DEFINE_SYMBOL property) for SHARED libraries, so a static
         build compiles the *definitions* of dllimport functions and MSVC
         rejects them with error C2491. We append an unconditional
         `target_compile_definitions(... PRIVATE <macro>)` to each generator
         cmake so the generated static libs export their symbols instead.

    The patches are idempotent: re-running is a no-op once applied.

.PARAMETER SourceDir
    Path to the fetched ROS 2 source tree (the directory that contains the
    `ros2/` and `eProsima/` folders). Defaults to ..\..\work\windows\src.
#>
[CmdletBinding()]
param(
    [string]$SourceDir
)

$ErrorActionPreference = 'Stop'

if (-not $SourceDir) {
    $SourceDir = Join-Path $PSScriptRoot '..\..\work\windows\src'
}
$SourceDir = (Resolve-Path -LiteralPath $SourceDir).Path
Write-Host "Applying Windows static patches under: $SourceDir"

function Remove-ForcedShared {
    param(
        [string]$RelPath,
        [string]$Pattern   # regex matching the forced-SHARED add_library line
    )
    $full = Join-Path $SourceDir $RelPath
    if (-not (Test-Path -LiteralPath $full)) {
        Write-Host "  [skip] not found: $RelPath"
        return
    }
    $text = Get-Content -LiteralPath $full -Raw
    if ($text -notmatch $Pattern) {
        Write-Host "  [ok]   already static (no forced SHARED): $RelPath"
        return
    }
    # Drop only the trailing ' SHARED' token from the matched add_library line.
    $patched = [regex]::Replace($text, $Pattern, { param($m) $m.Value -replace '\s+SHARED', '' })
    Set-Content -LiteralPath $full -Value $patched -NoNewline
    Write-Host "  [fix]  removed forced SHARED: $RelPath"
}

function Add-StaticExportDefine {
    param(
        [string]$RelPath,
        [string]$Macro     # macro to define, e.g. ROSIDL_GENERATOR_C_BUILDING_DLL_${PROJECT_NAME}
    )
    $full = Join-Path $SourceDir $RelPath
    if (-not (Test-Path -LiteralPath $full)) {
        Write-Host "  [skip] not found: $RelPath"
        return
    }
    $marker = '# [WINDOWS_STATIC_EXPORT_PATCH]'
    $text = Get-Content -LiteralPath $full -Raw
    if ($text.Contains($marker)) {
        Write-Host "  [ok]   export define already present: $RelPath"
        return
    }
    $block = @"

$marker force the generated static lib to export (not import) its symbols.
target_compile_definitions(`${rosidl_generate_interfaces_TARGET}`${_target_suffix}
  PRIVATE "$Macro")
"@
    Add-Content -LiteralPath $full -Value $block
    Write-Host "  [fix]  appended export define ($Macro): $RelPath"
}

function Disable-PythonGenerator {
    # Wrap the rosidl_generator_py extension registration in an opt-out guard so
    # passing -DROSIDL_GENERATOR_PY_DISABLE=ON skips Python (.pyd) bindings.
    # The static, DLL-free bridge never needs Python type supports, and the
    # generated python extension object paths overflow CMAKE_OBJECT_PATH_MAX on
    # Windows (fatal error C1083). Mirrors apply_android_patches.sh.
    $RelPath = 'ros2\rosidl_python\rosidl_generator_py\cmake\register_py.cmake'
    $full = Join-Path $SourceDir $RelPath
    if (-not (Test-Path -LiteralPath $full)) {
        Write-Host "  [skip] not found: $RelPath"
        return
    }
    $text = Get-Content -LiteralPath $full -Raw
    if ($text -match 'ROSIDL_GENERATOR_PY_DISABLE') {
        Write-Host "  [ok]   python generator guard already present: $RelPath"
        return
    }
    $original = @"
  ament_register_extension(
    "rosidl_generate_idl_interfaces"
    "rosidl_generator_py"
    "rosidl_generator_py_generate_interfaces.cmake")
"@
    $replacement = @"
  if(NOT ROSIDL_GENERATOR_PY_DISABLE)
    ament_register_extension(
      "rosidl_generate_idl_interfaces"
      "rosidl_generator_py"
      "rosidl_generator_py_generate_interfaces.cmake")
  endif()
"@
    # Normalize to the file's existing newline style before replacing.
    $nl = if ($text -match "`r`n") { "`r`n" } else { "`n" }
    $original = $original -replace "`r?`n", $nl
    $replacement = $replacement -replace "`r?`n", $nl
    if (-not $text.Contains($original)) {
        Write-Host "  [warn] python extension block not found verbatim: $RelPath"
        return
    }
    $patched = $text.Replace($original, $replacement)
    Set-Content -LiteralPath $full -Value $patched -NoNewline
    Write-Host "  [fix]  added python generator opt-out guard: $RelPath"
}

function Set-LibyamlStatic {
    # libyaml_vendor hard-codes -DBUILD_SHARED_LIBS=ON for its bundled libyaml
    # ExternalProject, so it always emits yaml.dll even in an otherwise static
    # build. Force the bundled libyaml static and export YAML_DECLARE_STATIC so
    # consumers (rcl_yaml_param_parser) compile yaml.h as plain declarations
    # instead of __declspec(dllimport) (which would LNK2019 against the static
    # yaml.lib). On non-Windows YAML_DECLARE_STATIC is a harmless no-op.
    $RelPath = 'ros2\libyaml_vendor\CMakeLists.txt'
    $full = Join-Path $SourceDir $RelPath
    if (-not (Test-Path -LiteralPath $full)) {
        Write-Host "  [skip] not found: $RelPath"
        return
    }
    $text = Get-Content -LiteralPath $full -Raw
    $changed = $false

    if ($text.Contains('-DBUILD_SHARED_LIBS=ON')) {
        $text = $text.Replace('-DBUILD_SHARED_LIBS=ON', '-DBUILD_SHARED_LIBS=OFF')
        $changed = $true
        Write-Host "  [fix]  forced bundled libyaml static: $RelPath"
    } else {
        Write-Host "  [ok]   bundled libyaml already static: $RelPath"
    }

    # The bundled libyaml is built by a *separate* ExternalProject cmake
    # invocation that only inherits CMAKE_C_FLAGS / BUILD_SHARED_LIBS / build
    # type, NOT CMAKE_MSVC_RUNTIME_LIBRARY. So it falls back to the MSVC default
    # dynamic CRT (/MD), producing a yaml.lib whose objects reference the import
    # form of CRT calls (e.g. __imp_strdup). Linking that into the /MT static
    # bridge then fails with LNK2019 on __imp_strdup. Force the sub-build onto
    # the static CRT (/MT) so it matches every other ROS 2 static library.
    if ($text -notmatch 'CMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded') {
        $nl = if ($text -match "`r`n") { "`r`n" } else { "`n" }
        $anchor = 'list(APPEND extra_cmake_args -DBUILD_SHARED_LIBS=OFF)'
        $inject = $anchor + $nl +
            '  list(APPEND extra_cmake_args -DCMAKE_POLICY_DEFAULT_CMP0091=NEW)' + $nl +
            '  list(APPEND extra_cmake_args -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded)'
        $text = $text.Replace($anchor, $inject)
        $changed = $true
        Write-Host "  [fix]  forced bundled libyaml static CRT (/MT): $RelPath"
    } else {
        Write-Host "  [ok]   bundled libyaml already uses static CRT: $RelPath"
    }

    if ($text -notmatch 'ament_export_definitions\(YAML_DECLARE_STATIC\)') {
        $nl = if ($text -match "`r`n") { "`r`n" } else { "`n" }
        $anchor = 'ament_export_libraries(yaml)'
        $text = $text.Replace($anchor, $anchor + $nl + 'ament_export_definitions(YAML_DECLARE_STATIC)')
        $changed = $true
        Write-Host "  [fix]  exported YAML_DECLARE_STATIC to consumers: $RelPath"
    } else {
        Write-Host "  [ok]   YAML_DECLARE_STATIC already exported: $RelPath"
    }

    if ($changed) {
        Set-Content -LiteralPath $full -Value $text -NoNewline
    }
}

# -------------------------------------------------------------------------
# Patch 1 & 2: strip forced SHARED so these honour BUILD_SHARED_LIBS=OFF
# -------------------------------------------------------------------------
Remove-ForcedShared `
    -RelPath 'ros2\rmw_dds_common\rmw_dds_common\CMakeLists.txt' `
    -Pattern 'add_library\(\$\{PROJECT_NAME\}_library SHARED'
Remove-ForcedShared `
    -RelPath 'ros2\rosidl_typesupport_fastrtps\rosidl_typesupport_fastrtps_cpp\CMakeLists.txt' `
    -Pattern 'add_library\(\$\{PROJECT_NAME\} SHARED'

# -------------------------------------------------------------------------
# Patch 3..9: define the *_BUILDING_DLL[_<pkg>] export macro on the generated
# static type-support / message libraries (fixes MSVC error C2491).
# -------------------------------------------------------------------------
Add-StaticExportDefine `
    -RelPath 'ros2\rosidl\rosidl_generator_c\cmake\rosidl_generator_c_generate_interfaces.cmake' `
    -Macro 'ROSIDL_GENERATOR_C_BUILDING_DLL_${PROJECT_NAME}'
Add-StaticExportDefine `
    -RelPath 'ros2\rosidl\rosidl_typesupport_introspection_c\cmake\rosidl_typesupport_introspection_c_generate_interfaces.cmake' `
    -Macro 'ROSIDL_TYPESUPPORT_INTROSPECTION_C_BUILDING_DLL_${PROJECT_NAME}'
Add-StaticExportDefine `
    -RelPath 'ros2\rosidl\rosidl_typesupport_introspection_cpp\cmake\rosidl_typesupport_introspection_cpp_generate_interfaces.cmake' `
    -Macro 'ROSIDL_TYPESUPPORT_INTROSPECTION_CPP_BUILDING_DLL'
Add-StaticExportDefine `
    -RelPath 'ros2\rosidl_typesupport\rosidl_typesupport_c\cmake\rosidl_typesupport_c_generate_interfaces.cmake' `
    -Macro 'ROSIDL_GENERATOR_C_BUILDING_DLL_${PROJECT_NAME}'
Add-StaticExportDefine `
    -RelPath 'ros2\rosidl_typesupport\rosidl_typesupport_cpp\cmake\rosidl_typesupport_cpp_generate_interfaces.cmake' `
    -Macro 'ROSIDL_TYPESUPPORT_CPP_BUILDING_DLL'
Add-StaticExportDefine `
    -RelPath 'ros2\rosidl_typesupport_fastrtps\rosidl_typesupport_fastrtps_c\cmake\rosidl_typesupport_fastrtps_c_generate_interfaces.cmake' `
    -Macro 'ROSIDL_TYPESUPPORT_FASTRTPS_C_BUILDING_DLL_${PROJECT_NAME}'
Add-StaticExportDefine `
    -RelPath 'ros2\rosidl_typesupport_fastrtps\rosidl_typesupport_fastrtps_cpp\cmake\rosidl_typesupport_fastrtps_cpp_generate_interfaces.cmake' `
    -Macro 'ROSIDL_TYPESUPPORT_FASTRTPS_CPP_BUILDING_DLL_${PROJECT_NAME}'

# -------------------------------------------------------------------------
# Patch 10: allow disabling the Python (.pyd) generator via -DROSIDL_GENERATOR_PY_DISABLE=ON
# -------------------------------------------------------------------------
Disable-PythonGenerator

# -------------------------------------------------------------------------
# Patch 11: force the bundled libyaml static (eliminate yaml.dll)
# -------------------------------------------------------------------------
Set-LibyamlStatic

Write-Host "Windows static patches applied."
