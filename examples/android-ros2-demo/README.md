# Android ROS 2 Demo

This example is a small Android smoke-test app for the ROS 2 Humble Android artifacts produced by this repository.

The design follows [../../docs/ANDROID_TEST_APP_PRD.md](../../docs/ANDROID_TEST_APP_PRD.md): ROS 2 runtime logic lives in C++, while the Android Java layer handles permissions, Foreground Service startup and UI rendering.

## Stack

- Java 17
- Android minSdk 29
- Android targetSdk 35
- Android NDK r25b (`25.1.8937393`)
- CMake native build
- `arm64-v8a` only for the first demo
- ROS 2 shared libraries copied from `../../work/dist/android_arm64-v8a`

## Prepare ROS 2 Artifacts

From this directory on Windows:

```powershell
.\scripts\sync_ros2_artifacts.ps1
```

Or from a POSIX shell:

```bash
./scripts/sync_ros2_artifacts.sh
```

The scripts copy:

- `../../work/dist/android_arm64-v8a/jniLibs/arm64-v8a/*.so` to `app/src/main/jniLibs/arm64-v8a/`
- `../../work/dist/android_arm64-v8a/include/` to `app/src/main/ros2/include/`
- `../../work/dist/android_arm64-v8a/manifest/` to `app/src/main/assets/ros2-manifest/`

The copied libraries and headers are ignored by Git because they are generated build artifacts.

## Build

This project expects an Android SDK and Java 17 to be available in your shell environment.

Create `local.properties` in this example project and point it at your local SDK and NDK. Example for the current workspace layout:

```properties
sdk.dir=D\:\\ENV\\android-sdk-windows
ndk.dir=D\:\\ENV\\android-ndk-r25b-windows\\android-ndk-r25b-windows
```

On Windows, the helper script downloads a local ignored Gradle distribution if `gradle` is not installed globally, then builds the debug APK:

```powershell
.\scripts\build_debug.ps1
```

With a global Gradle installation, you can also run:

```bash
gradle :app:assembleDebug
```

The debug APK is written to `app/build/outputs/apk/debug/app-debug.apk`.

If you prefer Android Studio, open `examples/android-ros2-demo` as the project root.

## Run Scenario

1. Install the debug APK on an Android 29+ `arm64-v8a` device.
2. Keep the Android device and a ROS 2 Humble PC on the same Wi-Fi network.
3. Open the app and tap `Start`.
4. On the PC, verify discovery and topics:

```bash
ros2 node list
ros2 topic echo /android/status
ros2 topic pub --once /android/command std_msgs/msg/String "{data: 'ping'}"
```

The app shows the native runtime state, publish count, received command count and the latest command reported by the C++ core.

The default node name in the app is `android_phone_node` without a leading slash. ROS CLI tools display the fully-qualified name as `/android_phone_node`.

The app also receives WAV audio transfers from the PC side. It listens on `/android/audio_control` and `/android/audio_chunk`, saves one private `ros2_audio.wav` file, shows the received file size, and plays the latest file with `Play Received Audio`.

## Current Scope

Implemented now:

- Java Activity UI with Start / Stop controls.
- Foreground Service shell.
- Wi-Fi multicast lock acquisition.
- JNI bridge.
- C++ `rclcpp` runtime with one node.
- `/android/status` publisher using `std_msgs/msg/String`.
- `/android/command` subscription using `std_msgs/msg/String`.
- `/android/audio_control` and `/android/audio_chunk` subscriptions for PC-to-Android WAV transfer.
- Single-file audio save and playback UI.
- C++ state snapshot rendered by Java UI.

Next steps:

- Add `std_srvs` to the builder output and implement `/android/get_info`.
- Add parameter get/set verification from PC.
- Add diagnostics export.
- Add explicit Wi-Fi disconnect/reconnect scenario tracking.