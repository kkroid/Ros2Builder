param(
    [string]$ArtifactRoot = (Join-Path $PSScriptRoot '..\..\..\work\dist\android_arm64-v8a')
)

$ErrorActionPreference = 'Stop'

$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$ArtifactRoot = Resolve-Path $ArtifactRoot

$SourceJniLibs = Join-Path $ArtifactRoot 'jniLibs\arm64-v8a'
$SourceInclude = Join-Path $ArtifactRoot 'include'
$SourceManifest = Join-Path $ArtifactRoot 'manifest'

if (-not (Test-Path $SourceJniLibs)) {
    throw "Missing ROS 2 jniLibs directory: $SourceJniLibs"
}
if (-not (Test-Path $SourceInclude)) {
    throw "Missing ROS 2 include directory: $SourceInclude"
}

$TargetJniLibs = Join-Path $ProjectRoot 'app\src\main\jniLibs\arm64-v8a'
$TargetInclude = Join-Path $ProjectRoot 'app\src\main\ros2\include'
$TargetManifest = Join-Path $ProjectRoot 'app\src\main\assets\ros2-manifest'

Remove-Item -Recurse -Force $TargetJniLibs, $TargetInclude, $TargetManifest -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $TargetJniLibs, $TargetInclude, $TargetManifest | Out-Null

Copy-Item -Path (Join-Path $SourceJniLibs '*') -Destination $TargetJniLibs -Recurse -Force
Copy-Item -Path (Join-Path $SourceInclude '*') -Destination $TargetInclude -Recurse -Force
if (Test-Path $SourceManifest) {
    Copy-Item -Path (Join-Path $SourceManifest '*') -Destination $TargetManifest -Recurse -Force
}

$SoCount = (Get-ChildItem $TargetJniLibs -Filter '*.so*' -File | Measure-Object).Count
$HeaderCount = (Get-ChildItem $TargetInclude -File -Recurse | Measure-Object).Count

Write-Host "Copied ROS 2 artifacts from $ArtifactRoot"
Write-Host "Shared libraries: $SoCount"
Write-Host "Header files: $HeaderCount"