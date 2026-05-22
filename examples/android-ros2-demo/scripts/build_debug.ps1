param(
    [string]$GradleVersion = '8.9'
)

$ErrorActionPreference = 'Stop'

$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$LocalProperties = Join-Path $ProjectRoot 'local.properties'

if (-not (Test-Path $LocalProperties)) {
    throw "Missing local.properties. Set sdk.dir and ndk.dir before building. See README.md."
}

if (-not $env:JAVA_HOME) {
    throw 'JAVA_HOME is not set. This demo expects Java 17.'
}

$GradleRoot = Join-Path $ProjectRoot '.gradle\local'
$GradleBin = Join-Path $GradleRoot "gradle-$GradleVersion\bin\gradle.bat"

if (-not (Test-Path $GradleBin)) {
    New-Item -ItemType Directory -Force $GradleRoot | Out-Null
    $GradleZip = Join-Path $GradleRoot "gradle-$GradleVersion-bin.zip"
    if (-not (Test-Path $GradleZip)) {
        Invoke-WebRequest -Uri "https://services.gradle.org/distributions/gradle-$GradleVersion-bin.zip" -OutFile $GradleZip
    }
    Expand-Archive -Path $GradleZip -DestinationPath $GradleRoot -Force
}

Push-Location $ProjectRoot
try {
    & $GradleBin :app:assembleDebug
} finally {
    Pop-Location
}