param(
    [string]$Version = 'v1.90.9'
)

$ErrorActionPreference = 'Stop'
$demoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$target = Join-Path $demoRoot 'third_party\imgui'

if (Test-Path $target) {
    Write-Host "ImGui already exists: $target"
    exit 0
}

New-Item -ItemType Directory -Force (Join-Path $demoRoot 'third_party') | Out-Null
git -c http.https://github.com.proxy= clone --depth 1 --branch $Version https://github.com/ocornut/imgui.git $target
Remove-Item -Recurse -Force (Join-Path $target '.git')
Write-Host "Fetched ImGui $Version to $target"