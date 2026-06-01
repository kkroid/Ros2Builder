param(
    [Version]$MinCMakeVersion = [Version]'3.20',
    [string]$PythonExe = 'python',
    [string]$NinjaExe = 'ninja',
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$failures = New-Object System.Collections.Generic.List[string]

function Add-Failure {
    param([string]$Message)
    $failures.Add($Message) | Out-Null
    if (-not $Quiet) {
        Write-Host "[missing] $Message" -ForegroundColor Red
    }
}

function Write-Ok {
    param([string]$Message)
    if (-not $Quiet) {
        Write-Host "[ok] $Message" -ForegroundColor Green
    }
}

function Test-CommandAvailable {
    param(
        [string]$Name,
        [string]$InstallHint
    )

    if ([System.IO.Path]::IsPathRooted($Name) -and (Test-Path -LiteralPath $Name -PathType Leaf)) {
        Write-Ok "${Name}: $Name"
        return (Get-Item -LiteralPath $Name)
    }

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) {
        Write-Ok "${Name}: $($command.Source)"
        return $command
    }

    Add-Failure "$Name not found. $InstallHint"
    return $null
}

$null = Test-CommandAvailable 'git' 'Install Git for Windows: https://git-scm.com/download/win'
$null = Test-CommandAvailable $NinjaExe 'Install Ninja and add it to PATH, or pass -NinjaExe: https://github.com/ninja-build/ninja/releases'
$cmakeCommand = Test-CommandAvailable 'cmake' 'Install CMake >= 3.20: https://cmake.org/download/'
$pythonCommand = Test-CommandAvailable $PythonExe 'Install Python 3.8 or 3.10 and add it to PATH, or pass -PythonExe: https://www.python.org/downloads/windows/'

if ($cmakeCommand) {
    $cmakeVersionLine = (& cmake --version | Select-Object -First 1)
    if ($cmakeVersionLine -match '(\d+\.\d+\.\d+)') {
        $cmakeVersion = [Version]$matches[1]
        if ($cmakeVersion -lt $MinCMakeVersion) {
            Add-Failure "CMake $cmakeVersion found, but $MinCMakeVersion or newer is required."
        } else {
            Write-Ok "CMake version $cmakeVersion"
        }
    } else {
        Add-Failure 'Unable to parse CMake version.'
    }
}

if ($pythonCommand) {
    $pythonVersionText = (& $PythonExe -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}')") -join ''
    $pythonVersion = [Version]$pythonVersionText
    if ($pythonVersion.Major -ne 3 -or $pythonVersion.Minor -lt 8 -or $pythonVersion.Minor -gt 10) {
        Add-Failure "Python $pythonVersion found, but ROS 2 Humble Windows builds expect Python 3.8 or 3.10."
    } else {
        Write-Ok "Python version $pythonVersion"
    }
}

$vcVarsAll = Get-VcVarsAll
if ($vcVarsAll) {
    Write-Ok "VS 2019 vcvarsall.bat: $vcVarsAll"
} else {
    Add-Failure 'Visual Studio 2019 Build Tools with MSVC v142 were not found. Install: https://visualstudio.microsoft.com/vs/older-downloads/'
}

$windowsKitRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\Include'
if (Test-Path $windowsKitRoot) {
    $windowsSdk = Get-ChildItem -LiteralPath $windowsKitRoot -Directory |
        Sort-Object Name -Descending |
        Where-Object { Test-Path (Join-Path $_.FullName 'um\Windows.h') } |
        Select-Object -First 1

    if ($windowsSdk) {
        Write-Ok "Windows SDK: $($windowsSdk.Name)"
    } else {
        Add-Failure 'Windows SDK headers were not found under Windows Kits\10\Include.'
    }
} else {
    Add-Failure 'Windows 10 SDK was not found. Install it with Visual Studio Build Tools.'
}

if ($failures.Count -gt 0) {
    $messageLines = New-Object System.Collections.Generic.List[string]
    $messageLines.Add('Windows build prerequisites are incomplete:') | Out-Null
    foreach ($failure in $failures) {
        $messageLines.Add("- $failure") | Out-Null
    }
    $messageLines.Add('') | Out-Null
    $messageLines.Add('This script only detects system prerequisites; it does not install VS, CMake, Git, Ninja, or Python.') | Out-Null
    $message = $messageLines -join [Environment]::NewLine
    throw $message
}

Write-Ok 'Windows build prerequisites look ready.'