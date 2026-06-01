# Windows ROS 2 Demo

This demo is a native Windows peer for the Android ROS 2 demo. It uses C++17, Win32, DirectX 11, ImGui, and the Windows ROS 2 install tree from Phase 2.

## Build

From the repository root:

```powershell
.\examples\windows-ros2-demo\scripts\build_debug.ps1
```

The script loads VS 2019, sources `work/windows/install/windows_x64/setup.ps1`, configures with Ninja, and builds `examples/windows-ros2-demo/build/windows_ros2_demo.exe`.

## Run

```powershell
.\examples\windows-ros2-demo\build\windows_ros2_demo.exe --auto-start --domain-id 0
```

Useful options:

- `--auto-start`
- `--audio-file <path>`
- `--send-speed <n>`
- `--discovery-server <ip:port>`
- `--domain-id <n>`

## Topic Mapping

- Subscribes: `/android/status`, `/wsl/audio_control`, `/wsl/audio_chunk`.
- Publishes: `/android/command`, `/android/audio_control`, `/android/audio_chunk`.

Received Android audio is saved under `%LOCALAPPDATA%\Ros2Builder\received\`.

The first Windows build supports status, commands, WAV TX, default-device microphone TX, and received-audio WAV save/playback. Live WASAPI render and cross-device Android/WSL validation remain in the roadmap checklist.