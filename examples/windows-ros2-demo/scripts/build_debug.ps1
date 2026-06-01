param(
    [string]$Ros2Prefix = (Join-Path (Join-Path $PSScriptRoot '..\..\..') 'work\windows\install\windows_x64'),
    [string]$ThirdPartyDir = (Join-Path (Join-Path $PSScriptRoot '..\..\..') 'third_party\windows'),
    [string]$BuildDir = (Join-Path (Join-Path $PSScriptRoot '..') 'build'),
    [string]$PythonExe = "$env:USERPROFILE\miniconda3\envs\ros2builder-humble-win\python.exe",
    [string]$NinjaExe = "$env:USERPROFILE\miniconda3\envs\ros2builder-humble-win\Library\bin\ninja.exe"
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
. (Join-Path $repoRoot 'scripts\windows\common.ps1')

$demoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$Ros2Prefix = Resolve-RepoPath $Ros2Prefix
$ThirdPartyDir = Resolve-RepoPath $ThirdPartyDir
$BuildDir = Resolve-RepoPath $BuildDir

if (-not (Test-Path (Join-Path $Ros2Prefix 'setup.ps1'))) {
    throw "Missing Windows ROS 2 install prefix: $Ros2Prefix"
}

$machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$env:Path = "$machinePath;$userPath"
foreach ($name in @(
    'AMENT_PREFIX_PATH',
    'CMAKE_PREFIX_PATH',
    'COLCON_PREFIX_PATH',
    'PYTHONPATH',
    'AMENT_CURRENT_PREFIX',
    'AMENT_TRACE_SETUP_FILES',
    'INCLUDE',
    'LIB',
    'LIBPATH',
    'VSINSTALLDIR',
    'VCINSTALLDIR',
    'VCToolsInstallDir',
    'WindowsSdkDir',
    'WindowsSDKVersion',
    'VisualStudioVersion',
    'VSCMD_ARG_TGT_ARCH',
    'VSCMD_VER',
    '__VSCMD_PREINIT_PATH'
)) {
    Remove-Item "Env:\$name" -ErrorAction SilentlyContinue
}

Import-VcVarsEnvironment -VcVarsAll (Get-VcVarsAll) -Arch x64
. (Join-Path $Ros2Prefix 'setup.ps1')

Remove-Item -LiteralPath (Join-Path $BuildDir 'CMakeCache.txt') -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $BuildDir 'CMakeFiles') -Recurse -Force -ErrorAction SilentlyContinue

$cmakeArgs = @(
    '-S', $demoRoot,
    '-B', $BuildDir,
    '-G', 'Ninja',
    "-DCMAKE_MAKE_PROGRAM=$NinjaExe",
    "-DCMAKE_PREFIX_PATH=$Ros2Prefix;$ThirdPartyDir",
    "-DPython3_EXECUTABLE=$PythonExe",
    "-DROS2_PREFIX=$Ros2Prefix",
    "-DTHIRD_PARTY_DIR=$ThirdPartyDir",
    '-DCMAKE_BUILD_TYPE=RelWithDebInfo'
)

Invoke-External cmake $cmakeArgs
Invoke-External cmake @('--build', $BuildDir, '--config', 'RelWithDebInfo')

Write-Host "Windows demo executable: $(Join-Path $BuildDir 'windows_ros2_demo.exe')"