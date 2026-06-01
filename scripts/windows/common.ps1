function Get-RepoRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

function Resolve-RepoPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    return (Join-Path (Get-RepoRoot) $Path)
}

function Invoke-External {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [string[]]$ArgumentList = @(),

        [string]$WorkingDirectory = ''
    )

    $previousLocation = Get-Location
    if ($WorkingDirectory) {
        Set-Location $WorkingDirectory
    }

    try {
        & $FilePath @ArgumentList
        if ($LASTEXITCODE -ne 0) {
            throw "$FilePath exited with code $LASTEXITCODE"
        }
    } finally {
        if ($WorkingDirectory) {
            Set-Location $previousLocation
        }
    }
}

function Get-VcVarsAll {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path $vswhere)) {
        return $null
    }

    $installationPath = & $vswhere `
        -version '[16.0,17.0)' `
        -latest `
        -products '*' `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath

    if (-not $installationPath) {
        return $null
    }

    $vcVarsAll = Join-Path $installationPath 'VC\Auxiliary\Build\vcvarsall.bat'
    if (Test-Path $vcVarsAll) {
        return $vcVarsAll
    }

    return $null
}

function Import-VcVarsEnvironment {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VcVarsAll,

        [string]$Arch = 'x64'
    )

    if (-not (Test-Path $VcVarsAll)) {
        throw "vcvarsall.bat was not found: $VcVarsAll"
    }

    $command = "`"$VcVarsAll`" $Arch >nul && set"
    $environmentLines = & cmd.exe /d /s /c $command
    if ($LASTEXITCODE -ne 0) {
        throw "vcvarsall.bat failed for arch '$Arch' with code $LASTEXITCODE"
    }

    foreach ($line in $environmentLines) {
        if ($line -match '^([^=]+)=(.*)$') {
            [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process')
        }
    }
}

function Copy-DirectoryContents {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string]$Destination
    )

    if (-not (Test-Path $Source)) {
        return
    }

    New-Item -ItemType Directory -Force $Destination | Out-Null
    Get-ChildItem -LiteralPath $Source -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
    }
}

function Get-GitCommit {
    param([string]$RepositoryRoot = (Get-RepoRoot))

    try {
        $commit = & git -C $RepositoryRoot rev-parse --short HEAD 2>$null
        if ($LASTEXITCODE -eq 0) {
            return ($commit -join '').Trim()
        }
    } catch {
    }

    return ''
}

function Get-VcpkgBaseline {
    param([string]$ManifestPath = (Join-Path (Get-RepoRoot) 'vcpkg.json'))

    if (-not (Test-Path $ManifestPath)) {
        return ''
    }

    try {
        $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
        return [string]$manifest.'builtin-baseline'
    } catch {
        return ''
    }
}

function Set-GitHubProxyOverride {
    param(
        [AllowEmptyString()]
        [string]$GitProxy
    )

    $env:GIT_CONFIG_COUNT = '2'
    $env:GIT_CONFIG_KEY_0 = 'http.https://github.com.proxy'
    $env:GIT_CONFIG_VALUE_0 = $GitProxy
    $env:GIT_CONFIG_KEY_1 = 'https.https://github.com.proxy'
    $env:GIT_CONFIG_VALUE_1 = $GitProxy

    if ($GitProxy) {
        Write-Host "Using per-process GitHub proxy: $GitProxy"
    } else {
        Write-Host 'Ignoring global GitHub proxy for this process.'
    }
}

function Set-DownloadProxyOverride {
    param(
        [AllowEmptyString()]
        [string]$DownloadProxy
    )

    $env:HTTP_PROXY = $DownloadProxy
    $env:HTTPS_PROXY = $DownloadProxy
    $env:http_proxy = $DownloadProxy
    $env:https_proxy = $DownloadProxy

    if ($DownloadProxy) {
        Write-Host "Using download proxy: $DownloadProxy"
    } else {
        Write-Host 'Ignoring HTTP(S) download proxy for this process.'
    }
}