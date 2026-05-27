param(
    [string]$ArtifactRoot = (Join-Path $PSScriptRoot '..\..\..\work\dist\android_arm64-v8a_static_dynamic')
)

$ErrorActionPreference = 'Stop'

$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$ArtifactRoot = Resolve-Path $ArtifactRoot

$SourceJniLibs = Join-Path $ArtifactRoot 'jniLibs\arm64-v8a'
$SourceLib = Join-Path $ArtifactRoot 'lib'
$SourceInclude = Join-Path $ArtifactRoot 'include'
$SourceManifest = Join-Path $ArtifactRoot 'manifest'

if (-not (Test-Path $SourceJniLibs)) {
    throw "Missing ROS 2 jniLibs directory: $SourceJniLibs"
}
if (-not (Test-Path $SourceInclude)) {
    throw "Missing ROS 2 include directory: $SourceInclude"
}

$TargetJniLibs = Join-Path $ProjectRoot 'app\src\main\jniLibs\arm64-v8a'
$TargetLib = Join-Path $ProjectRoot 'app\src\main\ros2\lib\arm64-v8a'
$TargetInclude = Join-Path $ProjectRoot 'app\src\main\ros2\include'
$TargetManifest = Join-Path $ProjectRoot 'app\src\main\assets\ros2-manifest'

Remove-Item -Recurse -Force $TargetJniLibs, $TargetLib, $TargetInclude, $TargetManifest -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $TargetJniLibs, $TargetLib, $TargetInclude, $TargetManifest | Out-Null

# Packages/libs not required by the audio demo. Keep in sync with sync_ros2_artifacts.sh
# and the EXCLUDE regex in app/src/main/cpp/CMakeLists.txt.
$SkipStaticLibs = @(
    'librmw_fastrtps_cpp.a',
    'libaction_msgs__*.a',
    'libunique_identifier_msgs__*.a',
    'libtest_msgs__*.a',
    'librcl_logging_spdlog.a'
)
$SkipIncludeDirs = @(
    'action_msgs',
    'unique_identifier_msgs',
    'test_msgs',
    'spdlog'
)
$SkipJniLibs = @(
    'libspdlog.so'
)

Get-ChildItem -Path $SourceJniLibs -File | Where-Object { $SkipJniLibs -notcontains $_.Name } | ForEach-Object {
    Copy-Item -Path $_.FullName -Destination $TargetJniLibs -Force
}
if (Test-Path $SourceLib) {
    Get-ChildItem -Path $SourceLib -Filter '*.a' -File | Where-Object {
        $name = $_.Name
        -not ($SkipStaticLibs | Where-Object { $name -like $_ })
    } | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $TargetLib -Force
    }
}
Get-ChildItem -Path $SourceInclude -Force | Where-Object {
    -not ($_.PSIsContainer -and ($SkipIncludeDirs -contains $_.Name))
} | ForEach-Object {
    Copy-Item -Path $_.FullName -Destination $TargetInclude -Recurse -Force
}
if (Test-Path $SourceManifest) {
    Copy-Item -Path (Join-Path $SourceManifest '*') -Destination $TargetManifest -Recurse -Force
}

$SoCount = (Get-ChildItem $TargetJniLibs -Filter '*.so*' -File | Measure-Object).Count
$StaticCount = (Get-ChildItem $TargetLib -Filter '*.a' -File | Measure-Object).Count
$HeaderCount = (Get-ChildItem $TargetInclude -File -Recurse | Measure-Object).Count

Write-Host "Copied ROS 2 artifacts from $ArtifactRoot"
Write-Host "Shared libraries: $SoCount"
Write-Host "Static libraries: $StaticCount"
Write-Host "Header files: $HeaderCount"