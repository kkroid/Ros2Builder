# WSL Ubuntu 22.04 + ROS 2 Humble Audio Demo

This demo runs directly in WSL2, without Docker. It is intended for a Windows host with a WSL2 distro named `Ubuntu-22.04-Humble`, ROS 2 Humble, and WSLg PulseAudio.

## Check the environment

```powershell
wsl -d Ubuntu-22.04-Humble -- bash -lc "source /opt/ros/humble/setup.bash; ros2 doctor --report | sed -n '/NETWORK CONFIGURATION/,+80p'"
```

Check microphone access inside WSL:

```powershell
wsl -d Ubuntu-22.04-Humble -- bash -lc "cd /mnt/d/Ros2Builder/examples/wsl-humble-audio-demo && ./check_audio.sh"
```

The raw byte count should be greater than zero.

## Peer test

Start the Android app and press `START`. Then run:

```powershell
wsl -d Ubuntu-22.04-Humble -- bash -lc "cd /mnt/d/Ros2Builder/examples/wsl-humble-audio-demo && WSL_DEMO_EXIT_AFTER=12 ./run_peer.sh"
```

Passing output looks like:

```text
status_count=3 avg_rate=0.75Hz last_status=1.0s ago
last Android status: {"seq":123,"device":"android","state":"running","lastCommand":"ping"}
published command #1: ping
```

## Live audio streaming

Record in WSL, stream raw PCM chunks to Android, and play them as they arrive:

```powershell
wsl -d Ubuntu-22.04-Humble -- bash -lc "cd /mnt/d/Ros2Builder/examples/wsl-humble-audio-demo && ./send_audio.sh --duration 3 --source RDPSource"
```

The script first waits for Android to match both audio subscriptions, then prints a 3-second countdown, `START RECORDING NOW`, and `RECORDING FINISHED`. The default audio publish settings are `--chunk-size 2048 --publish-delay 0.0` so chunks follow the live microphone stream instead of a pre-recorded file.

Android plays the incoming PCM stream with `AudioTrack` while also writing a valid WAV file to its app-private storage. After the stream ends, `Received audio file: N bytes` should match the saved WAV size; pressing `PLAY RECEIVED AUDIO` replays the most recent saved stream.