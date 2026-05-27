# ROS 2 Humble Android Builder

这个仓库提供一套用 Docker Compose 交叉编译 ROS 2 Humble 到 Android 的构建工作区。它只保存构建环境、源码清单和辅助脚本，不提交 ROS 2 源码、Android NDK、构建目录或二进制产物。

当前默认目标是 Android `arm64-v8a` / API 29，默认构建包集合是：

```text
rclcpp rmw_fastrtps_cpp std_msgs
```

默认源码清单只包含这组包的最小依赖闭包：31 个仓库。当前最小构建的打包输出包含 94 个 `.so`，其中 93 个来自 ROS 2 install tree，另 1 个是 Android 运行时需要的 `libc++_shared.so`。

## 当前状态

- 已初步走通 Android 版本编译流程。
- 运行时集成、APK 打包和真机通信测试仍待验证。
- `tf2_ros`、`image_transport`、`rosbag2` 等扩展包建议逐个开启、逐个排错。
- 本仓库使用 Apache License 2.0 开源，详见 [LICENSE](LICENSE)。

## 目录

- [docker-compose.yml](docker-compose.yml): 默认构建容器和挂载配置，兼容 Docker Desktop 和 Podman。
- [docker-compose.host-gateway.yml](docker-compose.host-gateway.yml): Docker Engine 专用的 `host.docker.internal:host-gateway` override。
- [docker/Dockerfile](docker/Dockerfile): Ubuntu 22.04 + CMake + colcon + vcstool + Python 生成工具。
- [manifests/ros2-humble-android.repos](manifests/ros2-humble-android.repos): 默认最小 Humble 源码仓库清单，覆盖 `rclcpp rmw_fastrtps_cpp std_msgs`。
- [manifests/ros2-humble-android-full.repos](manifests/ros2-humble-android-full.repos): 扩展包实验用的完整源码仓库清单。
- [scripts/ensure_ndk.sh](scripts/ensure_ndk.sh): 下载、解压、校验 Linux Android NDK，并尝试修复 Windows 解压造成的符号链接问题。
- [scripts/fetch_sources.sh](scripts/fetch_sources.sh): 校验 manifest，检查重复仓库和已有 checkout，然后下载源码到 `/work/src`。
- [scripts/validate_sources.py](scripts/validate_sources.py): 校验 `.repos` 里的仓库地址、版本、重复项和外部源码目录。
- [scripts/build_android.sh](scripts/build_android.sh): 使用 NDK CMake toolchain 构建 Android `arm64-v8a`。
- [scripts/apply_android_patches.sh](scripts/apply_android_patches.sh): 对已知 Android 构建问题应用本地、幂等补丁。
- [scripts/package_android_artifacts.sh](scripts/package_android_artifacts.sh): 从 install tree 聚合头文件、动态库、`jniLibs` 和 manifest。
- [DEPENDENCIES.md](DEPENDENCIES.md): 对你原始依赖清单的校准和仓库映射。
- [CONTRIBUTING.md](CONTRIBUTING.md): 贡献约定和仓库卫生说明。
- [docs/ANDROID_TEST_APP_PRD.md](docs/ANDROID_TEST_APP_PRD.md): Android ROS 2 测试 App 的产品需求文档。
- [docs/OPEN_SOURCE_CHECKLIST.md](docs/OPEN_SOURCE_CHECKLIST.md): 公开仓库前的检查清单。
- [examples/android-ros2-demo](examples/android-ros2-demo): Android 29+ Java 17 示例 App，使用 C++ 承载 ROS 2 runtime。
- [examples/pc-ros2-demo](examples/pc-ros2-demo): 官方 ROS 2 Humble 容器里的 PC 侧互测节点。
- [examples/wsl-humble-audio-demo](examples/wsl-humble-audio-demo): WSL2 Ubuntu 22.04 + ROS 2 Humble 原生 PC 侧互测和录音发送 demo，不经过 Docker。

## 前置要求

- Docker Desktop 或 Docker Engine，支持 Docker Compose v2；也可以使用 Podman 和 `podman compose`。
- 可访问 GitHub、ROS 2 源码仓库和 Android NDK 下载地址的网络环境。
- 足够的磁盘空间。`work/` 会保存源码、build、install、log 和 dist；`ndk/` 会保存 NDK 缓存。
- Windows 用户建议让 NDK 由容器下载并在 Linux 环境里解压，避免 Windows 解压破坏 NDK 内部符号链接。

## 快速开始

下面示例使用 `docker compose`；如果使用 Podman，把命令中的 `docker compose` 替换为 `podman compose`。

1. 复制环境变量模板：

```bash
cp .env.example .env
```

2. 修改 `.env`。默认会把 NDK 缓存在外部目录 `./ndk`，由容器自动下载并解压 Linux NDK，避免 Windows 解压破坏 NDK 里的符号链接。

```dotenv
NDK_CACHE_DIR=./ndk
NDK_VERSION=r25b
NDK_DOWNLOAD_URL=https://dl.google.com/android/repository/android-ndk-r25b-linux.zip
ANDROID_NDK_HOME=/opt/android-ndk-cache/android-ndk-r25b-linux
```

创建本地挂载目录。Docker Desktop 通常会自动创建 bind mount 目录；Podman 下建议显式创建，避免 `statfs ./work: no such file or directory`。

```bash
mkdir -p work ndk
```

3. 一键执行完整流水线。默认启动 `all-in-one` 服务，顺序准备 NDK、下载源码、构建最小集合并聚合产物。

```bash
docker compose up --build
```

如果镜像已经是最新的，也可以直接运行：

```bash
docker compose up
```

生成结果在：

```text
work/install/android_arm64-v8a
```

输出目录默认是：

```text
work/dist/android_arm64-v8a
```

如果要分步调试，也可以单独运行：

```bash
docker compose build
docker compose run --rm prepare-ndk
docker compose run --rm fetch-sources
docker compose run --rm builder bash -lc "/scripts/build_android.sh && /scripts/package_android_artifacts.sh"
```

## 网络和代理

如果 Docker Hub 拉取 `ubuntu:22.04` 失败，可以在 `.env` 中临时使用镜像源：

```dotenv
BASE_IMAGE=docker.m.daocloud.io/library/ubuntu:22.04
```

如果失败的是 PC demo 使用的 `osrf/ros:humble-desktop`，设置：

```dotenv
ROS2_DEMO_IMAGE=docker.m.daocloud.io/osrf/ros:humble-desktop
```

如果你本地有代理，先在 `.env` 里设置代理。默认 [docker-compose.yml](docker-compose.yml) 不注入 Docker 专用的 `host-gateway`，这样同一份 compose 可以同时用于 Docker Desktop 和 Podman。代理地址按运行时选择。

Docker Desktop 下通常用 `host.docker.internal`：

```dotenv
HTTP_PROXY=http://host.docker.internal:7890
HTTPS_PROXY=http://host.docker.internal:7890
ALL_PROXY=socks5h://host.docker.internal:7891
NO_PROXY=localhost,127.0.0.1,::1,host.docker.internal,host.containers.internal
```

Podman 下通常用 `host.containers.internal`：

```dotenv
HTTP_PROXY=http://host.containers.internal:7890
HTTPS_PROXY=http://host.containers.internal:7890
ALL_PROXY=socks5h://host.containers.internal:7891
NO_PROXY=localhost,127.0.0.1,::1,host.docker.internal,host.containers.internal
```

如果你用的是 Linux 上的 Docker Engine，并且容器里没有内置 `host.docker.internal`，再叠加 Docker 专用 override：

```bash
docker compose -f docker-compose.yml -f docker-compose.host-gateway.yml build
docker compose -f docker-compose.yml -f docker-compose.host-gateway.yml run --rm fetch-sources
```

这个 override 只用于 Docker Engine；Podman 下不要叠加它。

`HTTP_PROXY` 和 `HTTPS_PROXY` 会用于镜像构建阶段的 `apt`、`pip`，也会用于运行阶段的 `pip`、`git`、`vcs`。`ALL_PROXY=socks5h://...` 适合 Git/pip 这类 libcurl 或 Python 工具；`apt` 对 SOCKS 支持不稳定，建议给 apt 准备 HTTP 代理端口。

如果容器里连不上本地代理，检查你的代理软件是否允许来自 Docker 网络的连接。有些 Windows 代理客户端需要开启 `Allow LAN`，或把监听地址从 `127.0.0.1` 改成 `0.0.0.0`。可以先测试：

```bash
docker compose run --rm builder bash -lc "curl -I https://github.com && git ls-remote https://github.com/ros2/rclcpp.git HEAD"
```

## 源码清单

默认下载过程会先检查 [manifests/ros2-humble-android.repos](manifests/ros2-humble-android.repos)。这份清单只保留默认 `BUILD_PACKAGES` 所需的最小源码仓库；扩展包实验可以改用 [manifests/ros2-humble-android-full.repos](manifests/ros2-humble-android-full.repos)。

- 每个仓库必须有固定的 `url` 和 `version`。
- 不允许重复路径。
- 不允许同一个 Git URL 重复出现，尤其是不同版本重复。
- 如果 `work/src` 里已经有同名目录，必须是 Git checkout，且 remote 必须和 manifest 一致。
- `fetch-sources` 会对当前 manifest 顺序执行 `vcs import --recursive --skip-existing --workers 1`；已存在的仓库不会重复 clone。
- 拉取完成后会生成 `work/source-inventory.tsv`，记录路径、URL、manifest version 和当前 commit。

默认最小清单当前包含 31 个仓库；对应默认构建产物里有 94 个 `.so`：93 个来自 `work/install/android_arm64-v8a/lib`，另 1 个是打包到 `work/dist/android_arm64-v8a/lib` 的 `libc++_shared.so`。

如果只想检查清单和已有源码，不下载新仓库：

```bash
docker compose run --rm builder python3 /scripts/validate_sources.py --manifest /manifests/ros2-humble-android.repos --src /work/src --check-existing
```

也可以显式指定另一个 manifest：

```bash
docker compose run --rm -e SOURCE_MANIFEST=/manifests/ros2-humble-android.repos fetch-sources
```

如果要下载扩展包实验清单：

```bash
docker compose run --rm -e SOURCE_MANIFEST=/manifests/ros2-humble-android-full.repos fetch-sources
```

默认 `BUILD_PACKAGES` 是：

```text
rclcpp rmw_fastrtps_cpp std_msgs
```

## 产物打包

这个步骤不会重新编译，只会从 `work/install/android_arm64-v8a` 整理输出到：

```text
work/dist/android_arm64-v8a
```

输出结构：

```text
include/                  # 所有 ROS 2 和生成消息头文件
lib/                      # 所有 Android .so，包括 libc++_shared.so
jniLibs/arm64-v8a/        # Android Studio/Gradle 可直接打包的 .so
manifest/build-info.txt
manifest/source-inventory.tsv
manifest/artifact-manifest.tsv
```

默认不会复制 `share`、`cmake` 和 `pkgconfig` 这类元数据，因为这些目录小文件很多，在 Windows bind mount 上会明显拖慢，而 Android 工程通常只需要头文件和 `.so`。如果你要保留这些调试/CMake 元数据：

```bash
docker compose run --rm -e ARTIFACT_WITH_METADATA=ON package-artifacts
```

默认清单只记录文件大小和路径，适合 Windows 挂载目录下快速整理。如果需要为所有文件计算 sha256：

```bash
docker compose run --rm -e ARTIFACT_CHECKSUMS=ON package-artifacts
```

如果只想生成 `include`、`lib`，不复制一份 `jniLibs`，可以这样运行：

```bash
docker compose run --rm -e ARTIFACT_WITH_JNILIBS=OFF package-artifacts
```

如果要改输出目录，传容器内路径即可，建议仍放在 `/work` 下以便宿主机可见：

```bash
docker compose run --rm -e ARTIFACT_DIR=/work/dist/my_android_package package-artifacts
```

## 常用配置

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `ANDROID_ABI` | `arm64-v8a` | Android ABI。当前脚本和产物布局主要按 arm64 验证。 |
| `ANDROID_API` | `29` | Android platform API level。 |
| `ANDROID_STL` | `c++_shared` | Android C++ runtime。多 `.so` 默认用 shared；封装成单个 bridge `.so` 时才考虑实验 `c++_static`。 |
| `BUILD_SHARED_LIBS` | `ON` | ROS 2/CMake 标准开关。默认生成共享库；静态库实验可设为 `OFF`。 |
| `BUILD_OUTPUT_SUFFIX` | 空 | 可选输出后缀。例如设为 `static_dynamic` 时使用 `work/build/android_arm64-v8a_static_dynamic`、`work/install/android_arm64-v8a_static_dynamic`、`work/dist/android_arm64-v8a_static_dynamic`。 |
| `BUILD_PACKAGES` | `rclcpp rmw_fastrtps_cpp std_msgs` | 传给 `colcon --packages-up-to` 的包列表。 |
| `PARALLEL_WORKERS` | `nproc` | colcon 并行 worker 数。 |
| `NDK_VERSION` | `r25b` | 下载和缓存的 Android NDK 版本。 |
| `ROS2_ANDROID_WORKDIR` | `./work` | 宿主机上的源码、构建、安装和日志目录。 |

## 静态库实验

静态库实验只使用 ROS 2/ament/CMake 已有机制，不修改上游源码。Android demo 当前验证通过的组合是 `rmw_fastrtps_dynamic_cpp` + introspection typesupport：关闭 `BUILD_SHARED_LIBS`，固定 RMW，并禁用 RMW 运行时动态选择。输出放到独立后缀目录，避免覆盖默认共享库构建。

```bash
docker compose run --rm \
	-e BUILD_OUTPUT_SUFFIX=static_dynamic \
	-e BUILD_SHARED_LIBS=OFF \
	-e BUILD_PACKAGES="rclcpp rmw_fastrtps_dynamic_cpp std_msgs" \
	-e RMW_IMPLEMENTATION=rmw_fastrtps_dynamic_cpp \
	-e RMW_IMPLEMENTATION_DISABLE_RUNTIME_SELECTION=ON \
	-e CMAKE_POSITION_INDEPENDENT_CODE=ON \
	-e STATIC_ROSIDL_TYPESUPPORT_C=rosidl_typesupport_introspection_c \
	-e STATIC_ROSIDL_TYPESUPPORT_CPP=rosidl_typesupport_introspection_cpp \
	builder bash /scripts/build_android.sh

docker compose run --rm \
	-e BUILD_OUTPUT_SUFFIX=static_dynamic \
	-e BUILD_SHARED_LIBS=OFF \
	-e RMW_IMPLEMENTATION=rmw_fastrtps_dynamic_cpp \
	-e RMW_IMPLEMENTATION_DISABLE_RUNTIME_SELECTION=ON \
	-e STATIC_ROSIDL_TYPESUPPORT_C=rosidl_typesupport_introspection_c \
	-e STATIC_ROSIDL_TYPESUPPORT_CPP=rosidl_typesupport_introspection_cpp \
	package-artifacts
```

静态链接时 ROSIDL 只能选择一个 concrete typesupport；这里固定为 introspection C/C++ typesupport，也是上游 `get_used_typesupports.cmake` 支持的标准入口。`rmw_fastrtps_cpp` + FastRTPS typesupport 的静态产物可以构建，但在 Android JNI bridge 中启动节点时会卡在 FastDDS type object 注册；`rmw_fastrtps_dynamic_cpp` 正好是官方的 introspection 路径。

当前最小闭包实测静态构建可以完成：`work/dist/android_arm64-v8a_static_dynamic/lib` 中包含 88 个 `.a`，并残留 5 个 `.so`：`libc++_shared.so`、`librmw_dds_common.so`、`librosidl_typesupport_fastrtps_cpp.so`、`libspdlog.so`、`libyaml.so`。其中 `libc++_shared.so` 来自默认 `ANDROID_STL=c++_shared`；其余 4 个来自 Humble 源码中显式 `SHARED` 或 vendor 强制 shared 的包。继续把这些也改成 `.a` 需要上游补丁，不建议作为默认路线。

这个模式的目标不是把 `.a` 直接放进 APK，而是验证最小 ROS 2 闭包能静态到什么程度。实际集成到现有系统时，更常规的做法是把这些 `.a` 链进一个你控制的 JNI/bridge `.so`，只导出很小的业务 API，用它隔离 ROS 2 依赖和符号。Android demo 就走这条路：通过 [examples/android-ros2-demo/scripts/sync_ros2_artifacts.ps1](examples/android-ros2-demo/scripts/sync_ros2_artifacts.ps1) 维护的跳过列表，把当前 demo 用不到的 `librmw_fastrtps_cpp.a`、`libaction_msgs__*`、`libunique_identifier_msgs__*`、`libtest_msgs__*`、`librcl_logging_spdlog.a` 与 `libspdlog.so` 进一步剔除，得到 65 个 `.a` + 4 个 `.so` 的最小工件子集。更多细节见 [examples/android-ros2-demo/docs/DEPENDENCY_AUDIT.md](examples/android-ros2-demo/docs/DEPENDENCY_AUDIT.md)。

## 扩展构建

默认源码清单只覆盖最小通信链路。构建下面这些扩展包前，先拉取完整实验清单：

```bash
docker compose run --rm -e SOURCE_MANIFEST=/manifests/ros2-humble-android-full.repos fetch-sources
```

构建更多标准消息：

```bash
docker compose run --rm -e BUILD_PACKAGES="rclcpp rmw_fastrtps_cpp std_msgs sensor_msgs geometry_msgs nav_msgs" builder bash /scripts/build_android.sh
```

尝试 TF2 或图像传输：

```bash
docker compose run --rm -e BUILD_PACKAGES="tf2_ros image_transport" builder bash /scripts/build_android.sh
```

`rosbag2` 建议最后单独验证：

```bash
docker compose run --rm -e BUILD_PACKAGES="rosbag2_cpp rosbag2_storage" builder bash /scripts/build_android.sh
```

## 清理本地状态

本仓库把所有大型和机器相关内容放在忽略目录里。需要重新开始时，可以删除：

```bash
rm -rf work/build work/install work/log work/dist
```

如果要重新下载 ROS 2 源码，删除 `work/src` 后重新运行 `fetch-sources`。如果要重新准备 NDK，删除 `ndk/` 后重新运行 `prepare-ndk`。

## Android 侧注意事项

- APK 必须打包所有生成的 `.so`，Android 系统不会预装 ROS 2。
- Fast DDS 发现依赖网络能力，App 需要 `INTERNET`、`ACCESS_WIFI_STATE`、`CHANGE_WIFI_MULTICAST_STATE` 权限，并在运行时持有 `WifiManager.MulticastLock`。
- Android demo 默认使用 `ROS_DOMAIN_ID=0` 和 `RMW_IMPLEMENTATION=rmw_fastrtps_dynamic_cpp`；如果修改 domain id，Android App 输入框和 PC peer 环境变量必须保持一致。
- `rclcpp::init` 不要放在 Android UI 主线程。
- Android 后台限制很强，长期运行节点应放进 Foreground Service。
- 首轮排错优先看 `adb logcat`，并确认 APK 中 `libc++_shared.so` 和 ROS 2 相关 `.so` 都已打包。

## 示例互测

本仓库现在包含三个互补 demo：

- [examples/android-ros2-demo](examples/android-ros2-demo): Android 真机 App，使用本仓库交叉编译出的 ROS 2 Android `.so`，ROS 2 runtime 和业务逻辑在 C++ 层，Java 17 Android 层只做 UI、权限和 Foreground Service 外壳。
- [examples/pc-ros2-demo](examples/pc-ros2-demo): PC 侧官方 ROS 2 Humble peer，运行在 `osrf/ros:humble-desktop` 容器里，用标准 ROS 2 环境和 Android 节点互通。
- [examples/wsl-humble-audio-demo](examples/wsl-humble-audio-demo): PC 侧 WSL2 Ubuntu 22.04 + ROS 2 Humble 原生 demo，用 WSLg PulseAudio 录音并通过 ROS 2 发给 Android。

这两个 demo 的目标不是完整机器人应用，而是验证“本项目产出的 Android ROS 2 库能否和官方 Humble 正常发现、发布、订阅”。

### Android demo

Android demo 依赖前面 `package-artifacts` 生成的产物：

```text
work/dist/android_arm64-v8a
```

进入示例目录并复制 ROS 2 头文件、`.so` 和 manifest：

```powershell
cd examples/android-ros2-demo
.\scripts\sync_ros2_artifacts.ps1
```

或者在 POSIX shell 中运行：

```bash
cd examples/android-ros2-demo
./scripts/sync_ros2_artifacts.sh
```

Windows 下创建 `local.properties`，指向本机 Android SDK 和 NDK。示例：

```properties
sdk.dir=D\:\\ENV\\android-sdk-windows
ndk.dir=D\:\\ENV\\android-ndk-r25b-windows\\android-ndk-r25b-windows
```

构建 debug APK：

```powershell
.\scripts\build_debug.ps1
```

成功后 APK 位于：

```text
examples/android-ros2-demo/app/build/outputs/apk/debug/app-debug.apk
```

当前实测 debug APK 约 8.9 MiB；`lib/arm64-v8a/` 内只有 5 个 native 库：业务桥 `libros2_android_demo.so`（≈12.6 MiB，调试符号未 strip），以及 `libc++_shared.so`、`librmw_dds_common.so`、`librosidl_typesupport_fastrtps_cpp.so`、`libyaml.so` 共 4 个无法静态化的 ROS 2 共享库。所有 ROS 2 静态归档已在链接阶段并入业务桥，不再以独立 `.so` 形式出现。复制进 demo 的 `jniLibs/`、`ros2/`、`assets/`，以及 Gradle/CMake build 输出都已在示例 `.gitignore` 中忽略。

安装到 Android 29+、`arm64-v8a` 真机后，打开 App：

1. 确认手机和 PC 在同一 Wi-Fi 网络。
2. 确认 App 已获得网络、通知等权限。
3. 保持默认 `ROS_DOMAIN_ID=0`，节点名 `android_phone_node`。注意输入框里的 node name 不能带 `/`；ROS CLI 中看到的完整节点名会显示为 `/android_phone_node`。
4. 点击 `Start`。

Android App 预期表现：

- UI 显示 native runtime state 为 `running`。
- `publishedCount` 持续增长。
- App 持有 `WifiManager.MulticastLock`，并以前台服务方式运行。
- C++ 层发布 `/android/status`，消息类型是 `std_msgs/msg/String`。
- C++ 层订阅 `/android/command`，收到 `ping`、`reset_metrics`、`set_rate:5` 这类命令后更新 UI 状态快照。
- C++ 层订阅 `/android/audio_control` 和 `/android/audio_chunk`，把 PC 发送的 WAV 音频保存为 App 私有目录中的单个 `ros2_audio.wav`，每次传输覆盖旧文件。UI 会显示文件大小，并提供播放按钮。

### WSL Humble 原生 demo

推荐在 Windows 上用 WSL2 Ubuntu 22.04 + ROS 2 Humble 运行 PC 侧 demo。当前约定的新发行版名称是 `Ubuntu-22.04-Humble`，安装位置是 `D:\WSL\Ubuntu-22.04-Humble`。

Android App 点击 `Start` 后，运行状态/命令互测：

```powershell
wsl -d Ubuntu-22.04-Humble -- bash -lc "cd /mnt/d/Ros2Builder/examples/wsl-humble-audio-demo && WSL_DEMO_EXIT_AFTER=12 ./run_peer.sh"
```

运行 WSL 内录音、流式发送并在 Android 端实时播放：

```powershell
wsl -d Ubuntu-22.04-Humble -- bash -lc "cd /mnt/d/Ros2Builder/examples/wsl-humble-audio-demo && ./send_audio.sh --duration 3 --source RDPSource"
```

`send_audio.sh` 会先等待 Android 的两个音频订阅者完成 DDS 匹配，再倒计时 3 秒，然后打印 `START RECORDING NOW` 和 `RECORDING FINISHED`。默认使用 `--chunk-size 2048 --publish-delay 0.0`，PC 端从 `parec` 边录边发布 raw PCM，Android 端边收边用 `AudioTrack` 播放，同时保存为 App 私有目录里的 WAV 文件。

如果要先确认 WSL 内能录到音频：

```powershell
wsl -d Ubuntu-22.04-Humble -- bash -lc "cd /mnt/d/Ros2Builder/examples/wsl-humble-audio-demo && ./check_audio.sh"
```

成功后，Android 端会在传输过程中直接播放音频；传输结束后，界面上的 `Received audio file` 应显示大于 0 的字节数，点击 `Play Received Audio` 可以回放最近一次保存的音频。更完整的说明见 [examples/wsl-humble-audio-demo/README.md](examples/wsl-humble-audio-demo/README.md)。

### Docker PC peer demo

Docker PC peer 仍保留用于对比和构建环境验证；但在 Windows Docker Desktop 下，它不再是推荐的 Android 局域网 ROS 2 运行路径。实测 Docker Desktop 的 `network_mode=host` 仍处在 Docker Desktop VM 网络中，DDS 发现和 locator 可能暴露 `192.168.65.x` 这类手机不可达地址。需要真机互通时优先使用上面的 WSL Humble 原生 demo。

PC 侧可以用官方 ROS 2 Humble 容器运行 peer 节点：

```bash
docker compose run --rm ros2-demo-peer
```

默认 peer 行为：

- 使用 `ROS_DOMAIN_ID=0`，和 Android demo 的默认输入一致。
- 使用 `RMW_IMPLEMENTATION=rmw_fastrtps_cpp`。
- 使用 `best_effort` QoS，和 Android demo 默认发布/订阅 QoS 一致。
- 订阅 `/android/status`。
- 每 5 秒向 `/android/command` 发布一次 `ping`。
- 每 2 秒输出收到的 Android status 数量、平均接收频率和最近一条 status。

peer 运行后，预期日志会逐步出现类似信息：

```text
PC ROS 2 peer started. Subscribing /android/status, publishing /android/command
published command #1: ping
status_count=3 avg_rate=0.95Hz last_status=0.4s ago
last Android status: {"seq":3,"device":"android","state":"running","lastCommand":"ping"}
```

如果想让 peer 循环发送多个命令，可以这样运行：

```bash
docker compose run --rm -e ROS2_PEER_COMMANDS="ping,set_rate:5,reset_metrics" -e ROS2_PEER_COMMAND_PERIOD=5 ros2-demo-peer
```

如果要换 domain id，两边用同一个值即可。例如 Android App 输入 `7`，PC peer 这样启动：

```bash
docker compose run --rm -e ROS_DOMAIN_ID=7 ros2-demo-peer
```

如果想手动检查 ROS graph，可以打开官方 ROS 2 shell：

```bash
docker compose run --rm ros2-demo-shell
```

然后运行：

```bash
ros2 node list
ros2 topic echo /android/status
ros2 topic pub --once /android/command std_msgs/msg/String "{data: 'ping'}"
```

手动命令的预期表现：

- `ros2 node list` 能看到完整节点名 `/android_phone_node`。
- `ros2 topic echo /android/status` 能持续看到 JSON 字符串状态。
- 发布 `{data: 'ping'}` 后，Android App 的 `lastCommand` 更新为 `ping`。
- 发布 `{data: 'set_rate:5'}` 后，Android App 的 `publishRateHz` 更新为 `5.0`，PC 侧收到 status 的频率随之升高。
- 发布 `{data: 'reset_metrics'}` 后，Android App 的计数器重置。

### 音频流式保存测试

Android App 保持 `running` 后，可以让 PC 侧录音并把 WAV 字节流通过 ROS 2 发给手机：

```bash
source /opt/ros/humble/setup.bash
export ROS_DOMAIN_ID=0
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
cd /mnt/d/Ros2Builder/examples/pc-ros2-demo
python3 record_and_send_audio.py --duration 3
```

如果当前 ROS 2 Python 环境没有录音依赖，可以先发送已有 WAV 文件验证链路：

```bash
python3 record_and_send_audio.py --input-wav /path/to/input.wav
```

录音模式依赖 Python `sounddevice` 包以及系统可用的麦克风输入；缺少依赖时脚本会提示安装，或者改用 `--input-wav`。音频传输使用两个 topic：

- `/android/audio_control`: `std_msgs/msg/String`，发送 `begin` 和 `end`。
- `/android/audio_chunk`: `std_msgs/msg/UInt8MultiArray`，发送 WAV 文件字节块。

手机端预期表现：

- `audioState` 从 `receiving` 变为 `ready`。
- `audioFileBytes` 和界面上的 `Received audio file` 大于 0。
- `audioChunkCount` 大于 0。
- 点击 `Play Received Audio` 能播放最近一次收到的音频；再次发送会覆盖同一个文件。

如果要求“录音也必须发生在 Docker 容器内部”，需要先确认容器能访问主机音频输入。Windows Docker Desktop 的 Linux 容器默认通常没有 `/dev/snd`，也不能直接访问麦克风。可以运行：

```powershell
.\scripts\check_docker_audio.ps1
```

当前验证路径是：默认 `osrf/ros:humble-desktop` 容器没有 `/dev/snd`，也没有 `arecord`、`parec`、`sounddevice` 等录音能力。WSL 中存在 `/mnt/wslg/PulseServer` 时，可以启用 Docker Desktop 对该 WSL 发行版的 integration，再把 WSLg 目录挂进容器。Windows Docker Desktop 下要使用 UNC 反斜杠路径，例如 `\\wsl.localhost\Ubuntu-24.04\mnt\wslg`；如果你的发行版名称不同，运行前设置 `WSLG_DIR`。

Docker 内部录音并发送到 Android：

```powershell
$env:WSLG_DIR='\\wsl.localhost\Ubuntu-24.04\mnt\wslg'
docker compose build ros2-demo-audio
docker compose run --rm -e AUDIO_DURATION=5 ros2-demo-audio
Remove-Item Env:\WSLG_DIR
```

已验证：使用上述 WSLg PulseAudio 挂载时，容器内 `parec` 可以从 `RDPSource` 录到音频，`ros2-demo-audio` 会在容器内部生成 WAV 并发布 `/android/audio_control` 与 `/android/audio_chunk`。如果 Android 文件大小没有变化，问题通常不在录音，而在 Docker Desktop 容器到手机之间的 ROS 2/DDS 发现或 UDP 通信。

### 网络注意事项

原生 Linux Docker 使用 `network_mode=host` 通常最接近真实 PC ROS 2 环境。Docker Desktop for Windows 的多播和 host 网络行为可能不同；如果容器里发现不了 Android 节点，`ros2-demo-peer` 会持续显示 `status_count=0`。这种情况下先在 WSL 或另一台 Linux 主机上跑同样的官方 ROS 2 命令交叉验证，再继续排查 Docker Desktop 网络。

如果 PC 侧看不到 Android 节点，优先检查：

- Android App 和 PC 是否在同一局域网。
- `ROS_DOMAIN_ID` 是否一致。
- Android 是否授予网络相关权限。
- Android App 是否已经点击 `Start`，且状态为 `running`。
- 手机 Wi-Fi 是否允许组播；Android App 是否持有 `MulticastLock`。
- 防火墙、VPN、热点隔离或 Docker Desktop 网络是否阻断 UDP 多播。
- APK 是否确实打包了 `libc++_shared.so`、`librmw_dds_common.so`、`librosidl_typesupport_fastrtps_cpp.so`、`libyaml.so` 以及业务桥 `libros2_android_demo.so`（ROS 2 静态归档已链接进去）。

Windows + WSL 镜像网络下，如果 WSL 和 Windows 都显示同一个 Wi-Fi IP，但 Android 仍发现不了 PC peer，先确认手机能否访问 PC。常见现象是 Windows/WSL 可以 ping 手机，但手机 ping 不回 PC，这通常是 Windows 当前 Wi-Fi 被标为 Public 网络并阻止入站流量。可以用管理员 PowerShell 运行：

```powershell
.\scripts\enable_windows_ros2_lan.ps1 -InterfaceAlias WLAN -RemoteSubnet 192.168.1.0/24
```

该脚本会把指定网卡设为 Private，并允许同网段访问 ROS 2 domain 0 常用 DDS UDP 端口 `7400-7600` 和 ICMPv4 echo。运行后再测试 Android 到 PC 的 ping，以及 WSL/PC peer 是否能收到 `/android/status`。

如果只想快速确认 PC peer 容器能启动，可以设置自动退出时间：

```bash
docker compose run --rm -e ROS2_PEER_EXIT_AFTER=8 ros2-demo-peer
```

## 现实边界

这套配置是“源码和环境骨架”，不是保证 Humble 全量包一次过的按钮。`rclcpp + rmw_fastrtps_cpp + std_msgs` 是最适合先打通的链路；`tf2_ros`、`image_transport`、`rosbag2` 每加一层，都建议单独构建、单独验证。

公开仓库前请参考 [docs/OPEN_SOURCE_CHECKLIST.md](docs/OPEN_SOURCE_CHECKLIST.md)，尤其是敏感路径扫描和干净环境复现。

## License

This project is licensed under the Apache License 2.0. See [LICENSE](LICENSE) for details.