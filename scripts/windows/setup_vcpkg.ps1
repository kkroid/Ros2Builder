param(
    [string]$VcpkgRoot = (Join-Path (Join-Path $PSScriptRoot '..\..') 'third_party\vcpkg'),
    [string]$InstallRoot = (Join-Path (Join-Path $PSScriptRoot '..\..') 'third_party\windows'),
    [string]$StagingRoot = (Join-Path (Join-Path $PSScriptRoot '..\..') 'third_party\vcpkg_installed'),
    [string]$Triplet = 'x64-windows',
    [ValidateSet('x64')]
    [string]$Arch = 'x64',
    [string]$ExtraPath = '',
    [string]$VcpkgRef = '9b965a116838c6cdcd36bca60d1b81b030c8ab8d',
    [AllowEmptyString()]
    [string]$GitProxy = $null,
    [AllowEmptyString()]
    [string]$DownloadProxy = $null,
    [switch]$CleanInstall
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$repoRoot = Get-RepoRoot
$VcpkgRoot = Resolve-RepoPath $VcpkgRoot
$InstallRoot = Resolve-RepoPath $InstallRoot
$StagingRoot = Resolve-RepoPath $StagingRoot

if ($PSBoundParameters.ContainsKey('GitProxy')) {
    Set-GitHubProxyOverride -GitProxy $GitProxy
}

if ($PSBoundParameters.ContainsKey('DownloadProxy')) {
    Set-DownloadProxyOverride -DownloadProxy $DownloadProxy
}

$vcVarsAll = Get-VcVarsAll
Import-VcVarsEnvironment -VcVarsAll $vcVarsAll -Arch $Arch
$vsInstallPath = Split-Path (Split-Path (Split-Path (Split-Path $vcVarsAll -Parent) -Parent) -Parent) -Parent
$env:VCPKG_VISUAL_STUDIO_PATH = $vsInstallPath
$env:VCPKG_PLATFORM_TOOLSET = 'v142'
Write-Host "Using Visual Studio for vcpkg: $vsInstallPath"
Write-Host 'Using vcpkg platform toolset: v142'

if ($ExtraPath) {
    $env:PATH = $ExtraPath + ';' + $env:PATH
    Write-Host "Prepended extra tool path: $ExtraPath"
}

if (-not (Test-Path $VcpkgRoot)) {
    New-Item -ItemType Directory -Force (Split-Path $VcpkgRoot -Parent) | Out-Null
    Invoke-External git @('clone', 'https://github.com/microsoft/vcpkg.git', $VcpkgRoot)
}

Invoke-External git @('-C', $VcpkgRoot, 'fetch', '--tags', 'origin')
Invoke-External git @('-C', $VcpkgRoot, 'checkout', $VcpkgRef)

$bootstrap = Join-Path $VcpkgRoot 'bootstrap-vcpkg.bat'
Invoke-External $bootstrap @('-disableMetrics') -WorkingDirectory $VcpkgRoot

$vcpkgExe = Join-Path $VcpkgRoot 'vcpkg.exe'
if (-not (Test-Path $vcpkgExe)) {
    throw "vcpkg.exe was not created: $vcpkgExe"
}

if ($CleanInstall -and (Test-Path $StagingRoot)) {
    Remove-Item -LiteralPath $StagingRoot -Recurse -Force
}

New-Item -ItemType Directory -Force $StagingRoot | Out-Null
Invoke-External $vcpkgExe @(
    'install',
    '--triplet', $Triplet,
    "--x-install-root=$StagingRoot"
) -WorkingDirectory $repoRoot

$tripletRoot = Join-Path $StagingRoot $Triplet
if (-not (Test-Path $tripletRoot)) {
    throw "vcpkg triplet output was not found: $tripletRoot"
}

if ($CleanInstall -and (Test-Path $InstallRoot)) {
    Remove-Item -LiteralPath $InstallRoot -Recurse -Force
}

New-Item -ItemType Directory -Force $InstallRoot | Out-Null
foreach ($child in @('include', 'lib', 'bin', 'debug', 'share', 'tools')) {
    Copy-DirectoryContents (Join-Path $tripletRoot $child) (Join-Path $InstallRoot $child)
}

$info = [ordered]@{
    generated_at = (Get-Date).ToString('o')
    vcpkg_ref = $VcpkgRef
    vcpkg_head = ((& git -C $VcpkgRoot rev-parse HEAD) -join '').Trim()
    builtin_baseline = Get-VcpkgBaseline
    triplet = $Triplet
    staging_root = $StagingRoot
    install_root = $InstallRoot
}

$info | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $InstallRoot 'vcpkg-build-info.json') -Encoding UTF8

Write-Host "vcpkg dependencies are ready: $InstallRoot"