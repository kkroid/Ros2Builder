param(
    [string]$Image = "osrf/ros:humble-desktop",
    [string]$WslDistro = "Ubuntu-24.04"
)

$ErrorActionPreference = "Continue"

Write-Host "== Docker container direct audio devices =="
$directAudioCheck = 'echo ''--- /dev/snd ---''; ls -la /dev/snd 2>/dev/null || echo ''no /dev/snd''; echo ''--- recording commands ---''; command -v arecord || true; command -v parec || true; command -v pactl || true; command -v ffmpeg || true; echo ''--- python modules ---''; python3 -c "import importlib.util; [print(f''{name}={importlib.util.find_spec(name) is not None}'') for name in [''sounddevice'',''pyaudio'',''rclpy'']]"'
docker run --rm $Image bash -lc $directAudioCheck

Write-Host ""
Write-Host "== WSLg PulseAudio socket in $WslDistro =="
wsl -d $WslDistro -- bash -lc 'echo PULSE_SERVER=${PULSE_SERVER:-unset}; ls -la /mnt/wslg/PulseServer 2>/dev/null || echo no-wslg-pulse-server'

Write-Host ""
Write-Host "== Try mounting WSLg PulseAudio into Docker =="
docker run --rm `
    -v "\\wsl.localhost\$WslDistro\mnt\wslg:/mnt/wslg" `
    -e PULSE_SERVER=unix:/mnt/wslg/PulseServer `
    $Image bash -lc 'echo PULSE_SERVER=$PULSE_SERVER; ls -la /mnt/wslg/PulseServer; command -v parec || true; command -v pactl || true'

Write-Host ""
Write-Host "If the WSLg mount fails with a distro mount service error, enable Docker Desktop WSL integration for $WslDistro and rerun this script."
