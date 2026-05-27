# Android Demo 依赖盘点（音频收发场景）

记录一次针对本 demo（只需要在 Android 侧收发 `std_msgs/String` + `std_msgs/UInt8MultiArray` 的音频协议）做的 ROS 2 库瘦身审计，作为后续继续优化的起点。

> 工件来源：`work/dist/android_arm64-v8a_static_dynamic/`（ABI: `arm64-v8a`，ROS 2 Humble，FastRTPS）。

## 当前状态（已固化）

| 类别 | 数量 | 说明 |
| --- | --- | --- |
| 静态归档 `.a` | **65** | 链接进 `libros2_android_demo.so` |
| 共享库 `.so`（`jniLibs/arm64-v8a/`） | **4** | `libc++_shared.so`、`librmw_dds_common.so`、`librosidl_typesupport_fastrtps_cpp.so`、`libyaml.so` |
| 头文件目录 | 1994 个文件 | 仅编译期使用 |
| RMW 实现 | `rmw_fastrtps_dynamic_cpp` | 通过 `RMW_IMPLEMENTATION` 环境变量选用 |
| Debug APK 大小 | ~9.3 MB | 含未 strip 的调试符号；Release 会显著缩小 |

冒烟测试结果（emulator-5554, AVD `Medium_Phone_API_36.1`，`autoStart=true`）：

```text
runtimeState: "running"
publishedCount: 11
lastError: ""
```

## 真实可裁剪的范围（已应用）

`scripts/sync_ros2_artifacts.{ps1,sh}` 与 `app/src/main/cpp/CMakeLists.txt` 中维护了三份同步的跳过列表，已剔除以下确认无用的内容：

- `librmw_fastrtps_cpp.a` —— 与 `rmw_fastrtps_dynamic_cpp` 互斥，demo 选了 dynamic。
- `libaction_msgs__*.a` + headers —— demo 不用 action。
- `libunique_identifier_msgs__*.a` + headers —— 仅 action 依赖。
- `libtest_msgs__*.a` + headers —— 测试消息。
- `librcl_logging_spdlog.a` + `libspdlog/` headers + `libspdlog.so` —— `rcl_logging` 在我们的工件里同时存在 `noop` 和 `spdlog` 两个后端，按字母序 `librcl_logging_noop.a` 在 `--start-group` 内会先满足 `rcl_logging_external_*` 符号，因此可以安全去掉 `spdlog`。

> 修改三处必须同步：脚本（影响拷贝）、`CMakeLists.txt` 中 `list(FILTER ... EXCLUDE REGEX)`（链接时再过一遍兜底）。

## 已经探明不能动的部分（如果只看个数）

1. **`statistics_msgs` + `libstatistics_collector`** —— `<rclcpp/rclcpp.hpp>` 透过 `rclcpp/topic_statistics/subscription_topic_statistics.hpp` 传递依赖了 `libstatistics_collector/collector/generate_statistics_message.hpp`。即便运行期不开 topic statistics，删了头文件会直接 fatal error。
2. **`librmw_dds_common.so`** —— FastRTPS RMW 在 participant 创建路径上调用此动态库提供的 `ParticipantEntitiesInfo` 序列化逻辑，工件给的是 `.so` 形态。
3. **`librosidl_typesupport_fastrtps_cpp.so`** —— `rmw_fastrtps_dynamic_cpp` 在 dlopen 时按"识别符 -> 共享库名"查找 typesupport，去掉就报 typesupport handle 不可用。
4. **`libyaml.so`** —— `rcl_yaml_param_parser` 依赖 libyaml 的 ABI 接口（参数文件 / QoS profile 等）。
5. 每条 Fast-DDS / rcutils / rcpputils / rosidl_* / tracetools / rmw_fastrtps_shared_cpp 等静态归档都直接被链接器在 `--start-group` 内引用，删掉会出现 undefined reference。

## 尝试过但未能落地的进一步精简

### Step 2：切换到 `rmw_fastrtps_cpp`（静态 typesupport 路径）

- 目的：开启 Step 3，把所有 `rosidl_typesupport_introspection_{c,cpp}` 系列归档（demo 用不到的内省路径）一起砍掉。
- 实施：把 `kRmwImplementation` 改成 `"rmw_fastrtps_cpp"`，跳过列表把 `librmw_fastrtps_dynamic_cpp.a` 换成 `librmw_fastrtps_cpp.a`，CMake EXCLUDE regex 同步。
- 结果：**链接通过，运行时失败。**
  - 错误：`failed to initialize rcl node: rcl node's rmw handle is invalid, at rcl/node.c:416`。
  - `rmw_create_node` 返回了无效 handle，但 `rmw_get_error_string()` 当时为空，没有给出进一步根因。
- 根本症结：工件里**没有** `librmw_implementation.a`。这意味着 ROS 2 这套构建并没有真正的 rmw 调度层 —— `RMW_IMPLEMENTATION` 环境变量在静态形态下只是装饰品，实际生效的是链接进来的那一个 `librmw_fastrtps_*_cpp.a`。dynamic 那条路径在我们的工件里是被特别配合（typesupport `.so`、`librmw_dds_common.so`）跑通的；切到 static 仅做归档替换还差几样东西。
- 已经回滚，当前状态不受影响。

### Step 3：删除 introspection 归档

依赖 Step 2 完成，未启动。如果 RMW 仍是 dynamic，introspection typesupport 是参与运行时序列化的，砍掉会立即触发 typesupport 解析失败。

## 如果还要进一步精简，可选路径

按代价从低到高：

1. **接受现状（推荐）**：65 .a + 4 .so 是目前这个 ROS 2 工件能干净给到的下限。继续追个数边际收益小，APK 体积主要由 `libros2_android_demo.so` 的代码段决定，去几个 archive 也不会显著变小，Release 模式 + `-Wl,--gc-sections` + symbol strip 才是体积优化的正路。
2. **深挖 Step 2**：在原生侧补全异常捕获（直接抓 `rclcpp::exceptions::RCLError::what()` 包含的 rmw 错误链）+ 打开 `RCUTILS_LOGGING_SEVERITY=DEBUG`，定位 `rmw_create_node` 失败的具体环节，看能否补齐缺失的静态归档让 `rmw_fastrtps_cpp` 跑通。如果能跑通，再做 Step 3 砍掉 introspection（预计可减 ~12 个 `.a`）。
3. **重建工件**：改 `docker/` 与 `scripts/build_android.sh` 的 colcon 参数，明确只构 `rmw_fastrtps_cpp` 一套，并把当前 demo 不需要的包从 `manifests/ros2-humble-android.repos` 中摘掉（如 `*_introspection_*`、test_msgs、action_msgs、unique_identifier_msgs、spdlog 等）。代价是要重跑一遍整套构建，但能从源头消除工件里的无用文件。

## 维护提醒

跳过列表分布在三个文件，需保持一致：

- `examples/android-ros2-demo/scripts/sync_ros2_artifacts.ps1`（`$SkipStaticLibs` / `$SkipIncludeDirs` / `$SkipJniLibs`）
- `examples/android-ros2-demo/scripts/sync_ros2_artifacts.sh`（`skip_static` / `skip_include_dirs` / `skip_jni_libs`）
- `examples/android-ros2-demo/app/src/main/cpp/CMakeLists.txt`（`list(FILTER ROS2_STATIC_LIBS EXCLUDE REGEX ...)`）

任何一项不同步都可能出现"脚本拷过来但 CMake 又过滤掉"或反向情况，链接期或运行期才报错。

## 验证流程（emulator 即可）

```powershell
# 1) 同步工件
cd examples\android-ros2-demo
pwsh -NoProfile -File .\scripts\sync_ros2_artifacts.ps1

# 2) 构建
$env:JAVA_HOME='D:\NVPACK\jdk-17.0.2'
$env:ANDROID_HOME='D:\NVPACK\android-sdk-windows'
$env:ANDROID_NDK_HOME='D:\NVPACK\android-sdk-windows\ndk\25.1.8937393'  # 或本地 r25b 路径
gradle --no-daemon assembleDebug

# 3) 启 emulator（无窗口）
Start-Process -FilePath "$env:ANDROID_HOME\emulator\emulator.exe" `
  -ArgumentList @('-avd','Medium_Phone_API_36.1','-no-snapshot-save','-no-boot-anim','-no-window')

# 4) 安装并自动启动，抓 UI 快照
$adb = "$env:ANDROID_HOME\platform-tools\adb.exe"
& $adb wait-for-device
& $adb install -r app\build\outputs\apk\debug\app-debug.apk
& $adb shell am start -n com.example.ros2demo/.MainActivity --ez autoStart true
Start-Sleep 12
& $adb shell uiautomator dump /sdcard/window.xml
& $adb pull /sdcard/window.xml "$env:TEMP\ros2demo-window.xml"
```

通过判据：`window.xml` 中 `runtimeState: "running"`、`publishedCount` > 0、`lastError` 为空。
