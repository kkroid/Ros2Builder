# ROS 2 Humble Android Builder

这个仓库提供一套用 Docker Compose 交叉编译 ROS 2 Humble 到 Android 的构建工作区。它只保存构建环境、源码清单和辅助脚本，不提交 ROS 2 源码、Android NDK、构建目录或二进制产物。

当前默认目标是 Android `arm64-v8a` / API 29，默认构建包集合是：

```text
rclcpp rmw_fastrtps_cpp std_msgs
```

## 当前状态

- 已初步走通 Android 版本编译流程。
- 运行时集成、APK 打包和真机通信测试仍待验证。
- `tf2_ros`、`image_transport`、`rosbag2` 等扩展包建议逐个开启、逐个排错。
- 本仓库使用 Apache License 2.0 开源，详见 [LICENSE](LICENSE)。

## 目录

- [docker-compose.yml](docker-compose.yml): 构建容器和挂载配置。
- [docker/Dockerfile](docker/Dockerfile): Ubuntu 22.04 + CMake + colcon + vcstool + Python 生成工具。
- [manifests/ros2-humble-android.repos](manifests/ros2-humble-android.repos): 可直接 `vcs import` 的 Humble 源码仓库清单。
- [scripts/ensure_ndk.sh](scripts/ensure_ndk.sh): 下载、解压、校验 Linux Android NDK，并尝试修复 Windows 解压造成的符号链接问题。
- [scripts/fetch_sources.sh](scripts/fetch_sources.sh): 校验 manifest，检查重复仓库和已有 checkout，然后下载源码到 `/work/src`。
- [scripts/validate_sources.py](scripts/validate_sources.py): 校验 `.repos` 里的仓库地址、版本、重复项和外部源码目录。
- [scripts/build_android.sh](scripts/build_android.sh): 使用 NDK CMake toolchain 构建 Android `arm64-v8a`。
- [scripts/apply_android_patches.sh](scripts/apply_android_patches.sh): 对已知 Android 构建问题应用本地、幂等补丁。
- [scripts/package_android_artifacts.sh](scripts/package_android_artifacts.sh): 从 install tree 聚合头文件、动态库、`jniLibs` 和 manifest。
- [DEPENDENCIES.md](DEPENDENCIES.md): 对你原始依赖清单的校准和仓库映射。
- [CONTRIBUTING.md](CONTRIBUTING.md): 贡献约定和仓库卫生说明。
- [docs/OPEN_SOURCE_CHECKLIST.md](docs/OPEN_SOURCE_CHECKLIST.md): 公开仓库前的检查清单。

## 前置要求

- Docker Desktop 或 Docker Engine，支持 Docker Compose v2。
- 可访问 GitHub、ROS 2 源码仓库和 Android NDK 下载地址的网络环境。
- 足够的磁盘空间。`work/` 会保存源码、build、install、log 和 dist；`ndk/` 会保存 NDK 缓存。
- Windows 用户建议让 NDK 由容器下载并在 Linux 环境里解压，避免 Windows 解压破坏 NDK 内部符号链接。

## 快速开始

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

3. 构建 Docker 镜像。

```bash
docker compose build
```

4. 准备 NDK。已有 zip 或已解压目录会复用；如果检测到 Windows 解压造成的坏符号链接，会尝试修复。

```bash
docker compose run --rm prepare-ndk
```

5. 下载源码到外部挂载的 `work/src`。

```bash
docker compose run --rm fetch-sources
```

6. 构建最小可验证集合。

```bash
docker compose run --rm builder bash /scripts/build_android.sh
```

生成结果在：

```text
work/install/android_arm64-v8a
```

7. 聚合可分发产物。

```bash
docker compose run --rm package-artifacts
```

输出目录默认是：

```text
work/dist/android_arm64-v8a
```

## 网络和代理

如果 Docker Hub 拉取 `ubuntu:22.04` 失败，可以在 `.env` 中临时使用镜像源：

```dotenv
BASE_IMAGE=docker.m.daocloud.io/library/ubuntu:22.04
```

如果你本地有代理，先在 `.env` 里设置代理。Docker Desktop 下容器访问宿主机代理通常用 `host.docker.internal`：

```dotenv
HTTP_PROXY=http://host.docker.internal:7890
HTTPS_PROXY=http://host.docker.internal:7890
ALL_PROXY=socks5h://host.docker.internal:7891
NO_PROXY=localhost,127.0.0.1,::1,host.docker.internal
```

`HTTP_PROXY` 和 `HTTPS_PROXY` 会用于镜像构建阶段的 `apt`、`pip`，也会用于运行阶段的 `pip`、`git`、`vcs`。`ALL_PROXY=socks5h://...` 适合 Git/pip 这类 libcurl 或 Python 工具；`apt` 对 SOCKS 支持不稳定，建议给 apt 准备 HTTP 代理端口。

如果容器里连不上本地代理，检查你的代理软件是否允许来自 Docker 网络的连接。有些 Windows 代理客户端需要开启 `Allow LAN`，或把监听地址从 `127.0.0.1` 改成 `0.0.0.0`。可以先测试：

```bash
docker compose run --rm builder bash -lc "curl -I https://github.com && git ls-remote https://github.com/ros2/rclcpp.git HEAD"
```

## 源码清单

下载过程会先检查 [manifests/ros2-humble-android.repos](manifests/ros2-humble-android.repos)：

- 每个仓库必须有固定的 `url` 和 `version`。
- 不允许重复路径。
- 不允许同一个 Git URL 重复出现，尤其是不同版本重复。
- 如果 `work/src` 里已经有同名目录，必须是 Git checkout，且 remote 必须和 manifest 一致。
- 已存在的仓库不会重复 clone，`vcs import` 使用 `--skip-existing`。
- 拉取完成后会生成 `work/source-inventory.tsv`，记录路径、URL、manifest version 和当前 commit。

如果只想检查清单和已有源码，不下载新仓库：

```bash
docker compose run --rm builder python3 /scripts/validate_sources.py --manifest /manifests/ros2-humble-android.repos --src /work/src --check-existing
```

也可以显式指定另一个 manifest：

```bash
docker compose run --rm -e SOURCE_MANIFEST=/manifests/ros2-humble-android.repos fetch-sources
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
| `BUILD_PACKAGES` | `rclcpp rmw_fastrtps_cpp std_msgs` | 传给 `colcon --packages-up-to` 的包列表。 |
| `PARALLEL_WORKERS` | `nproc` | colcon 并行 worker 数。 |
| `NDK_VERSION` | `r25b` | 下载和缓存的 Android NDK 版本。 |
| `ROS2_ANDROID_WORKDIR` | `./work` | 宿主机上的源码、构建、安装和日志目录。 |

## 扩展构建

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
- 建议在 native 初始化前设置 `ROS_DOMAIN_ID` 和 `RMW_IMPLEMENTATION=rmw_fastrtps_cpp`。
- `rclcpp::init` 不要放在 Android UI 主线程。
- Android 后台限制很强，长期运行节点应放进 Foreground Service。
- 首轮排错优先看 `adb logcat`，并确认 APK 中 `libc++_shared.so` 和 ROS 2 相关 `.so` 都已打包。

## 现实边界

这套配置是“源码和环境骨架”，不是保证 Humble 全量包一次过的按钮。`rclcpp + rmw_fastrtps_cpp + std_msgs` 是最适合先打通的链路；`tf2_ros`、`image_transport`、`rosbag2` 每加一层，都建议单独构建、单独验证。

公开仓库前请参考 [docs/OPEN_SOURCE_CHECKLIST.md](docs/OPEN_SOURCE_CHECKLIST.md)，尤其是敏感路径扫描和干净环境复现。

## License

This project is licensed under the Apache License 2.0. See [LICENSE](LICENSE) for details.