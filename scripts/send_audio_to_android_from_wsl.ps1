param(
    [string]$Distro = "Ubuntu-22.04-Humble",
    [string]$RosSetup = "/opt/ros/humble/setup.bash",
    [string]$InputWav = "",
    [double]$Duration = 3.0,
    [int]$Rate = 16000,
    [int]$Channels = 1,
    [string]$Source = "RDPSource",
    [int]$ChunkSize = 2048,
    [double]$PublishDelay = 0.0,
    [double]$DiscoveryTimeout = 8.0,
    [int]$Countdown = 3,
    [string]$Qos = "reliable",
    [string]$KeepWav = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$wslRepoRoot = (wsl -d $Distro -- wslpath -a ("$repoRoot" -replace "\\", "\\")) -join ""
$scriptDir = "$wslRepoRoot/examples/wsl-humble-audio-demo"

$arguments = @()
if ($InputWav) {
    $inputPath = Resolve-Path $InputWav
    $wslInputPath = (wsl -d $Distro -- wslpath -a ("$inputPath" -replace "\\", "\\")) -join ""
    $arguments += "--input-wav '$wslInputPath'"
} else {
    $arguments += "--duration $Duration"
    $arguments += "--rate $Rate"
    $arguments += "--channels $Channels"
    if ($Source) {
        $arguments += "--source '$Source'"
    }
    $arguments += "--countdown $Countdown"
}

if ($KeepWav) {
    $keepPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($KeepWav)
    $wslKeepPath = (wsl -d $Distro -- wslpath -a ("$keepPath" -replace "\\", "\\")) -join ""
    $arguments += "--keep-wav '$wslKeepPath'"
}

$arguments += "--chunk-size $ChunkSize"
$arguments += "--publish-delay $PublishDelay"
$arguments += "--discovery-timeout $DiscoveryTimeout"
$arguments += "--qos $Qos"

$joinedArguments = $arguments -join " "
$command = "set -e; source '$RosSetup'; export ROS_DOMAIN_ID=`${ROS_DOMAIN_ID:-0}; export RMW_IMPLEMENTATION=`${RMW_IMPLEMENTATION:-rmw_fastrtps_cpp}; cd '$scriptDir'; python3 send_audio.py $joinedArguments"

Write-Host "Running in WSL distro: $Distro"
Write-Host "ROS setup: $RosSetup"
Write-Host "Command: python3 send_audio.py $joinedArguments"
wsl -d $Distro -- bash -lc $command
