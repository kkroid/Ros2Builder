# PC ROS 2 Demo Peer

This example runs a standard ROS 2 Humble node in Docker and uses it as the PC-side peer for `examples/android-ros2-demo`.

The Android app uses the cross-compiled ROS 2 libraries produced by this repository. This peer uses the official ROS 2 Humble runtime from the container image, so the test verifies that the Android build can communicate with a normal ROS 2 Humble environment.

## What It Tests

- Android node discovery from a standard ROS 2 environment.
- Android publishing `/android/status` as `std_msgs/msg/String`.
- PC peer publishing `/android/command` as `std_msgs/msg/String`.
- Basic command flow: `ping`, `reset_metrics`, `set_rate:5`.
- Message rate and last-message visibility from the PC side.
- Optional PC-to-Android WAV audio transfer over ROS 2 topics.

## Run

Start the Android app first, then run the peer:

```bash
docker compose run --rm ros2-demo-peer
```

Both demos default to `ROS_DOMAIN_ID=0`. If you change the Android app input, pass the same value to the peer, for example `-e ROS_DOMAIN_ID=7`.

Open an interactive official ROS 2 shell for manual checks:

```bash
docker compose run --rm ros2-demo-shell
```

Useful commands inside the shell:

```bash
ros2 node list
ros2 topic echo /android/status
ros2 topic pub --once /android/command std_msgs/msg/String "{data: 'ping'}"
```

## Audio Transfer

With the Android app running, stream a WAV file to the phone:

```bash
source /opt/ros/humble/setup.bash
export ROS_DOMAIN_ID=0
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
python3 examples/pc-ros2-demo/record_and_send_audio.py --input-wav /path/to/input.wav
```

To record from the PC microphone first, run:

```bash
python3 examples/pc-ros2-demo/record_and_send_audio.py --duration 3
```

Recording requires the Python `sounddevice` package and a working microphone in the ROS 2 Python environment. The Android app stores a single private `ros2_audio.wav`; each transfer overwrites the previous file. The UI shows the received file size and includes a playback button.

If recording must happen inside Docker, first run from the repository root:

```powershell
.\scripts\check_docker_audio.ps1
```

On Windows Docker Desktop, the default ROS 2 container normally has no `/dev/snd` device and no recording tools. To use the host microphone from a Linux container, enable Docker Desktop WSL integration for the WSL distro that exposes `/mnt/wslg/PulseServer`, mount the WSLg directory into the container, and use an image that includes PulseAudio recording tools.

This repository provides `ros2-demo-audio` for that path:

```powershell
$env:WSLG_DIR='\\wsl.localhost\Ubuntu-24.04\mnt\wslg'
docker compose build ros2-demo-audio
docker compose run --rm -e AUDIO_DURATION=5 ros2-demo-audio
Remove-Item Env:\WSLG_DIR
```

This verifies recording inside Docker when `parec` can list `RDPSource` and the generated WAV byte count is greater than zero. If Android does not receive the file, check Docker-to-phone DDS discovery separately with `ros2-demo-peer`; on Docker Desktop for Windows, `status_count=0` usually means the container network path is blocking ROS 2 discovery or UDP traffic even though audio recording works.

Audio topics:

| Topic | Type | Meaning |
| --- | --- | --- |
| `/android/audio_control` | `std_msgs/msg/String` | `begin` / `end` transfer markers. |
| `/android/audio_chunk` | `std_msgs/msg/UInt8MultiArray` | WAV file byte chunks. |

## Network Notes

ROS 2 discovery depends on UDP multicast. On native Linux Docker, `network_mode: host` is usually the closest match to running ROS 2 directly on the PC.

On Docker Desktop for Windows, host networking and multicast behavior can differ from native Linux. If discovery does not work from the container, run the same ROS 2 commands from WSL or a Linux machine on the same Wi-Fi network. The Android app should still be tested on the real device because Android permissions, multicast lock and lifecycle behavior cannot be reproduced in Docker.

## Configuration

Environment variables accepted by the peer service:

| Variable | Default | Meaning |
| --- | --- | --- |
| `ROS_DOMAIN_ID` | `0` | Domain ID shared with the Android app. |
| `RMW_IMPLEMENTATION` | `rmw_fastrtps_cpp` | RMW implementation. |
| `ANDROID_STATUS_TOPIC` | `/android/status` | Topic subscribed by the peer. |
| `ANDROID_COMMAND_TOPIC` | `/android/command` | Topic published by the peer. |
| `ROS2_PEER_COMMANDS` | `ping` | Comma-separated command loop. |
| `ROS2_PEER_COMMAND_PERIOD` | `5.0` | Seconds between command publishes. |
| `ROS2_PEER_EXIT_AFTER` | `0` | Optional seconds before automatic exit; `0` means run until interrupted. |
| `ROS2_PEER_QOS` | `best_effort` | QoS reliability mode, matching the Android demo default. Use `reliable` only if the Android app is configured the same way. |
| `ROS2_AUDIO_QOS` | `reliable` | QoS reliability mode used by `record_and_send_audio.py`. |