param(
    [string]$Workdir = (Join-Path (Join-Path $PSScriptRoot '..\..') 'work\windows'),
    [string]$InstallPrefix = '',
    [string]$ArtifactDir = (Join-Path (Join-Path $PSScriptRoot '..\..') 'work\dist\windows'),
    [string]$ThirdPartyDir = (Join-Path (Join-Path $PSScriptRoot '..\..') 'third_party\windows'),
    [ValidateSet('x64')]
    [string]$Arch = 'x64',
    [switch]$NoClean
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

function Copy-FilesByPattern {
    param(
        [string]$SourceDir,
        [string]$DestinationDir,
        [string]$Filter
    )

    if (Test-Path $SourceDir) {
        New-Item -ItemType Directory -Force $DestinationDir | Out-Null
        Get-ChildItem -LiteralPath $SourceDir -Filter $Filter -File -ErrorAction SilentlyContinue |
            Copy-Item -Destination $DestinationDir -Force
    }
}

$Workdir = Resolve-RepoPath $Workdir
$ArtifactDir = Resolve-RepoPath $ArtifactDir
$ThirdPartyDir = Resolve-RepoPath $ThirdPartyDir
if (-not $InstallPrefix) {
    $InstallPrefix = Join-Path $Workdir "install\windows_$Arch"
}
$InstallPrefix = Resolve-RepoPath $InstallPrefix

if (-not (Test-Path $InstallPrefix)) {
    throw "Missing Windows install tree: $InstallPrefix"
}

if (-not $NoClean -and (Test-Path $ArtifactDir)) {
    Remove-Item -LiteralPath $ArtifactDir -Recurse -Force
}

New-Item -ItemType Directory -Force (Join-Path $ArtifactDir 'bin') | Out-Null
New-Item -ItemType Directory -Force (Join-Path $ArtifactDir 'lib') | Out-Null

Copy-DirectoryContents (Join-Path $InstallPrefix 'include') (Join-Path $ArtifactDir 'include')
Copy-FilesByPattern (Join-Path $InstallPrefix 'bin') (Join-Path $ArtifactDir 'bin') '*.dll'
Copy-FilesByPattern (Join-Path $InstallPrefix 'lib') (Join-Path $ArtifactDir 'lib') '*.lib'

if (Test-Path $ThirdPartyDir) {
    Copy-DirectoryContents (Join-Path $ThirdPartyDir 'include') (Join-Path $ArtifactDir 'include')
    Copy-FilesByPattern (Join-Path $ThirdPartyDir 'bin') (Join-Path $ArtifactDir 'bin') '*.dll'
    Copy-FilesByPattern (Join-Path $ThirdPartyDir 'lib') (Join-Path $ArtifactDir 'lib') '*.lib'
}

$dllCount = (Get-ChildItem -LiteralPath (Join-Path $ArtifactDir 'bin') -Filter '*.dll' -File -ErrorAction SilentlyContinue | Measure-Object).Count
$libCount = (Get-ChildItem -LiteralPath (Join-Path $ArtifactDir 'lib') -Filter '*.lib' -File -ErrorAction SilentlyContinue | Measure-Object).Count
$headerCount = if (Test-Path (Join-Path $ArtifactDir 'include')) { (Get-ChildItem -LiteralPath (Join-Path $ArtifactDir 'include') -File -Recurse | Measure-Object).Count } else { 0 }

Write-Host "Windows artifact package: $ArtifactDir"
Write-Host "DLL files: $dllCount"
Write-Host "Import libraries: $libCount"
Write-Host "Header files: $headerCount"
