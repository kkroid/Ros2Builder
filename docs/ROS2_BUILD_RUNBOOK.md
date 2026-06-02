# ROS 2 Build Runbook

本文档记录当前 `harix_ros2_bridge` 使用的 ROS 2 Humble 构建步骤。目标不是构建通用 ROS 2 SDK，而是稳定产出可被 bridge 静态链接的 dist：

- Android: `work/dist/android_arm64-v8a`
- Windows: `work/dist/windows_x64_static`

当前封版目标包含：`rclcpp`、Fast DDS RMW、`std_msgs`、本地接口包 `ais_node_interface`。`ais_node_interface/msg/AudioCapture` 必须在编译期进入 typesupport，不能依赖运行时动态加载。

## 成功标准

Android 静态 dist：

- 路径：`E:\github\Ros2Builder\work\dist\android_arm64-v8a`
- `lib/` 下应有 `97` 个 `.a`
- `lib/` 下只允许这 3 个非 ROS `.so`：
  - `libc++_shared.so`
  - `libspdlog.so`
  - `libyaml.so`
- 不允许出现 `libais_node_interface*.so`、`librosidl*.so`、`librcl*.so`、`librmw*.so`

Windows 静态 dist：

- 路径：`E:\github\Ros2Builder\work\dist\windows_x64_static`
- `bin/` 下应为 `0` 个 ROS 2 DLL
- `lib/` 下应包含 `ais_node_interface__rosidl_* .lib`
- 供 `harix_ros2_bridge.dll` 链接时使用 `/MT` 静态 CRT

## 通用准备

所有命令默认在 Windows PowerShell 中从仓库根目录执行：

```powershell
cd E:\github\Ros2Builder
```

确认本地接口包存在。当前来源是 core 仓库：

```powershell
Remove-Item -LiteralPath .\packages\ais_node_interface -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item -LiteralPath D:\cloudminds\code\harix-rcu-core-mtls\interfaces\ais_node_interface `
  -Destination .\packages\ais_node_interface `
  -Recurse
```

如果接口包 `.msg/.srv` 改过，必须清掉旧拷贝，否则 `apply_android_patches.sh` 会认为本地包已经存在，不会覆盖：

```powershell
Remove-Item -LiteralPath .\work\src\ais_node_interface -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath .\work\windows\src\ais_node_interface -Recurse -Force -ErrorAction SilentlyContinue
```

切换 shared/static 构建模式，或怀疑 install 里有旧 `.so` 残留时，做一次干净 Android 构建清理：

```powershell
Remove-Item -LiteralPath .\work\build\android_arm64-v8a -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath .\work\install\android_arm64-v8a -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath .\work\dist\android_arm64-v8a -Recurse -Force -ErrorAction SilentlyContinue
```

## Python 环境

### Android 容器构建

Android 构建使用容器内 Python，不使用宿主机 conda。容器镜像里固定安装：

```text
python3
colcon-common-extensions
vcstool
empy==3.3.4
lark
catkin_pkg
packaging
PyYAML
setuptools==59.6.0
```

宿主机只需要 Docker Desktop 或 Podman 能运行 Linux 容器。

### Windows 原生构建

Windows 原生构建使用独立 conda 环境，避免系统 Python 污染：

```powershell
conda create -y -n ros2builder-humble-win python=3.10 ninja pip
conda activate ros2builder-humble-win
python -m pip install --upgrade pip wheel
python -m pip install `
  colcon-common-extensions `
  vcstool `
  empy==3.3.4 `
  lark `
  catkin_pkg `
  "numpy<2" `
  packaging `
  PyYAML `
  setuptools==59.6.0
```

脚本参数中统一用这两个路径：

```powershell
$PythonExe = "$env:USERPROFILE\miniconda3\envs\ros2builder-humble-win\python.exe"
$NinjaExe = "$env:USERPROFILE\miniconda3\envs\ros2builder-humble-win\Library\bin\ninja.exe"
```

先做环境检查：

```powershell
.\scripts\windows\ensure_windows_deps.ps1 `
  -PythonExe $PythonExe `
  -NinjaExe $NinjaExe
```

必须通过：Git、CMake >= 3.20、Ninja、Python 3.8/3.10、VS 2019 Build Tools v142、Windows 10 SDK。

## Android: Windows + Docker Desktop

Docker Desktop 使用 `host.docker.internal` 访问 Windows 宿主代理。无代理时这些变量留空即可。

```powershell
Copy-Item .env.example .env -ErrorAction SilentlyContinue
```

`.env` 代理示例：

```dotenv
HTTP_PROXY=http://host.docker.internal:7890
HTTPS_PROXY=http://host.docker.internal:7890
ALL_PROXY=socks5h://host.docker.internal:7891
NO_PROXY=localhost,127.0.0.1,::1,host.docker.internal,host.containers.internal
```

首次或镜像变更时构建镜像：

```powershell
docker compose build android-build
```

干净全量构建 Android 静态 dist：

```powershell
docker compose run --rm `
  -e BUILD_SHARED_LIBS=OFF `
  -e BUILD_PACKAGES="rclcpp rmw_fastrtps_cpp std_msgs ais_node_interface" `
  -e RMW_IMPLEMENTATION=rmw_fastrtps_cpp `
  -e RMW_IMPLEMENTATION_DISABLE_RUNTIME_SELECTION=ON `
  -e CMAKE_POSITION_INDEPENDENT_CODE=ON `
  -e STATIC_ROSIDL_TYPESUPPORT_C=rosidl_typesupport_fastrtps_c `
  -e STATIC_ROSIDL_TYPESUPPORT_CPP=rosidl_typesupport_fastrtps_cpp `
  android-build
```

这条命令会依次执行：

```text
/scripts/ensure_ndk.sh
/scripts/fetch_sources.sh
/scripts/build_android.sh
/scripts/package_android_artifacts.sh
```

注意：`apply_android_patches.sh` 在 `build_android.sh` 内执行，并会把 `/opt/packages/ais_node_interface` 复制到 `/work/src/ais_node_interface`。如果 `/work/src/ais_node_interface` 已存在，它不会覆盖，所以接口包变更后必须先按“通用准备”清理旧目录。

## Android: Windows + Podman

Podman 使用 `host.containers.internal` 访问 Windows 宿主代理。无代理时留空。

```dotenv
HTTP_PROXY=http://host.containers.internal:7890
HTTPS_PROXY=http://host.containers.internal:7890
ALL_PROXY=socks5h://host.containers.internal:7891
NO_PROXY=localhost,127.0.0.1,::1,host.docker.internal,host.containers.internal
```

启动 Podman machine：

```powershell
podman machine start
podman version
```

如果本机 `podman compose` 可用，命令与 Docker Desktop 相同，只把 `docker` 换成 `podman`：

```powershell
podman compose build android-build
podman compose run --rm `
  -e BUILD_SHARED_LIBS=OFF `
  -e BUILD_PACKAGES="rclcpp rmw_fastrtps_cpp std_msgs ais_node_interface" `
  -e RMW_IMPLEMENTATION=rmw_fastrtps_cpp `
  -e RMW_IMPLEMENTATION_DISABLE_RUNTIME_SELECTION=ON `
  -e CMAKE_POSITION_INDEPENDENT_CODE=ON `
  -e STATIC_ROSIDL_TYPESUPPORT_C=rosidl_typesupport_fastrtps_c `
  -e STATIC_ROSIDL_TYPESUPPORT_CPP=rosidl_typesupport_fastrtps_cpp `
  android-build
```

如果走本机已经验证过的 `podman-machine-default`，使用直接 `podman run`。这条是全量静态构建命令：

```powershell
wsl -d podman-machine-default -- bash -lc "cd /mnt/e/github/Ros2Builder && podman build -t ros2-humble-android-builder:latest -f docker/Dockerfile ."
```

如果镜像构建也需要代理，在上面的 `podman build` 后追加 `--build-arg HTTP_PROXY=... --build-arg HTTPS_PROXY=... --build-arg ALL_PROXY=...`。

```powershell
wsl -d podman-machine-default -- bash -lc "podman run --rm \
  -v /mnt/e/github/Ros2Builder/work:/work \
  -v /mnt/e/github/Ros2Builder/ndk:/opt/android-ndk-cache \
  -v /mnt/e/github/Ros2Builder/scripts:/scripts:ro \
  -v /mnt/e/github/Ros2Builder/manifests:/manifests:ro \
  -v /mnt/e/github/Ros2Builder/packages:/opt/packages:ro \
  -e ANDROID_NDK_HOME=/opt/android-ndk-cache/android-ndk-r25b-linux \
  -e ANDROID_ABI=arm64-v8a \
  -e ANDROID_API=29 \
  -e ANDROID_STL=c++_shared \
  -e BUILD_SHARED_LIBS=OFF \
  -e BUILD_PACKAGES='rclcpp rmw_fastrtps_cpp std_msgs ais_node_interface' \
  -e RMW_IMPLEMENTATION=rmw_fastrtps_cpp \
  -e RMW_IMPLEMENTATION_DISABLE_RUNTIME_SELECTION=ON \
  -e CMAKE_POSITION_INDEPENDENT_CODE=ON \
  -e STATIC_ROSIDL_TYPESUPPORT_C=rosidl_typesupport_fastrtps_c \
  -e STATIC_ROSIDL_TYPESUPPORT_CPP=rosidl_typesupport_fastrtps_cpp \
  -e SOURCE_MANIFEST=/manifests/ros2-humble-android.repos \
  -w /work \
  ros2-humble-android-builder:latest \
  bash -lc 'set -euo pipefail; /scripts/ensure_ndk.sh; /scripts/fetch_sources.sh; rm -rf /work/src/ais_node_interface; cp -a /opt/packages/ais_node_interface /work/src/; /scripts/build_android.sh; /scripts/package_android_artifacts.sh'"
```

如果 `fetch_sources.sh` 也需要代理，在 `podman run` 参数里追加 `-e HTTP_PROXY=http://host.containers.internal:7890 -e HTTPS_PROXY=http://host.containers.internal:7890 -e ALL_PROXY=socks5h://host.containers.internal:7891`。

这次实际用于快速补编 `ais_node_interface` 的命令如下。它依赖已有的 ROS 2 base install，只适合本地接口包变更后重编，不适合空目录首次构建：

```powershell
wsl -d podman-machine-default -- bash -lc "podman run --rm \
  -v /mnt/e/github/Ros2Builder/work:/work \
  -v /mnt/e/github/Ros2Builder/ndk:/opt/android-ndk-cache \
  -v /mnt/e/github/Ros2Builder/scripts:/scripts:ro \
  -v /mnt/e/github/Ros2Builder/packages:/opt/packages:ro \
  -e ANDROID_NDK_HOME=/opt/android-ndk-cache/android-ndk-r25b-linux \
  -e ANDROID_ABI=arm64-v8a \
  -e ANDROID_API=29 \
  -e ANDROID_STL=c++_shared \
  -e BUILD_SHARED_LIBS=OFF \
  -e BUILD_PACKAGES='ais_node_interface' \
  -e RMW_IMPLEMENTATION=rmw_fastrtps_cpp \
  -e RMW_IMPLEMENTATION_DISABLE_RUNTIME_SELECTION=ON \
  -e CMAKE_POSITION_INDEPENDENT_CODE=ON \
  -e STATIC_ROSIDL_TYPESUPPORT_C=rosidl_typesupport_fastrtps_c \
  -e STATIC_ROSIDL_TYPESUPPORT_CPP=rosidl_typesupport_fastrtps_cpp \
  -w /work \
  ros2-humble-android-builder:latest \
  bash -lc 'set -euo pipefail; rm -rf /work/build/android_arm64-v8a/ais_node_interface; rm -f /work/install/android_arm64-v8a/lib/libais_node_interface*.so /work/install/android_arm64-v8a/lib/libais_node_interface*.a; rm -rf /work/src/ais_node_interface; cp -a /opt/packages/ais_node_interface /work/src/; /scripts/build_android.sh; /scripts/package_android_artifacts.sh'"
```

## Windows 原生静态构建

Windows 原生构建不用 Docker/Podman，必须使用 VS 2019 Build Tools v142。先准备 vcpkg 静态依赖：

```powershell
$PythonExe = "$env:USERPROFILE\miniconda3\envs\ros2builder-humble-win\python.exe"
$NinjaExe = "$env:USERPROFILE\miniconda3\envs\ros2builder-humble-win\Library\bin\ninja.exe"
$NinjaDir = Split-Path $NinjaExe -Parent

.\scripts\windows\setup_vcpkg.ps1 `
  -Triplet x64-windows-static `
  -ExtraPath $NinjaDir `
  -GitProxy '' `
  -DownloadProxy http://127.0.0.1:1082
```

代理说明：

- `-GitProxy ''` 表示临时忽略可能失效的全局 Git 代理，不修改全局配置。
- 如果 GitHub 必须走代理，改成实际地址，例如 `-GitProxy http://127.0.0.1:1082`。
- `-DownloadProxy` 用于 vcpkg 下载 CMake/源码包等 HTTP(S) 资源；没有代理时删掉该参数。

把本地接口包放进 Windows colcon workspace：

```powershell
New-Item -ItemType Directory -Force .\work\windows\src | Out-Null
Remove-Item -LiteralPath .\work\windows\src\ais_node_interface -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item -LiteralPath .\packages\ais_node_interface `
  -Destination .\work\windows\src\ais_node_interface `
  -Recurse
```

Windows 静态构建命令分两类。

首次拉源码或补齐缺失源码时，使用下面命令，不加 `-SkipFetch`：

```powershell
.\scripts\windows\build_windows.ps1 `
  -Static `
  -SkipVcpkg `
  -SkipPythonPackages `
  -PythonExe $PythonExe `
  -NinjaExe $NinjaExe `
  -GitProxy '' `
  -DownloadProxy http://127.0.0.1:1082 `
  -BuildPackages 'rclcpp rmw_fastrtps_dynamic_cpp std_msgs ais_node_interface'
```

已有源码和 vcpkg 后，使用下面命令避免每次构建都碰网络：

```powershell
.\scripts\windows\build_windows.ps1 `
  -Static `
  -SkipVcpkg `
  -SkipPythonPackages `
  -SkipFetch `
  -PythonExe $PythonExe `
  -NinjaExe $NinjaExe `
  -BuildPackages 'rclcpp rmw_fastrtps_dynamic_cpp std_msgs ais_node_interface'
```

这条命令要求以下内容已经存在：

- `third_party/windows` 已由 `setup_vcpkg.ps1 -Triplet x64-windows-static` 准备好
- `work/windows/src` 已经有 ROS 2 manifest 源码
- `work/windows/src/ais_node_interface` 已经由上一步复制进去
- Python 依赖已装好，所以可以安全使用 `-SkipPythonPackages`

如果是第一次拉源码，不能加 `-SkipFetch`。推荐先修好网络/代理，执行一次非 skip 构建；如果 Git 在 fetch 阶段报 `128`，它只是拉源码失败，不代表编译失败。已有源码时再回到上面的 `-SkipFetch` 命令，避免每次构建都碰网络。

## 验证命令

Android dist 检查：

```powershell
$AndroidLib = '.\work\dist\android_arm64-v8a\lib'
(Get-ChildItem $AndroidLib -Filter '*.a' -File | Measure-Object).Count
Get-ChildItem $AndroidLib -Filter '*.so' -File | Select-Object Name
Get-ChildItem $AndroidLib -Filter 'libais_node_interface*.so' -File
```

预期：第一个命令输出 `97`；第二个命令只列出 `libc++_shared.so`、`libspdlog.so`、`libyaml.so`；第三个命令无输出。

Windows dist 检查：

```powershell
$WinDist = '.\work\dist\windows_x64_static'
Get-ChildItem "$WinDist\bin" -Filter '*.dll' -File -ErrorAction SilentlyContinue
Get-ChildItem "$WinDist\lib" -Filter 'ais_node_interface__rosidl_*.lib' -File | Select-Object Name
```

预期：第一个命令无输出；第二个命令能看到 `ais_node_interface` 的 generated/type-support `.lib`。

## 常见错误处理

`git exited with code 128`：这是 fetch/update 阶段的网络或代理问题，不是编译错误。已有源码时使用 `-SkipFetch`；没有源码时先修代理。

Android NDK 缺 clang 或 toolchain：不要在 Windows 手工解压 Linux NDK。让容器执行 `ensure_ndk.sh` 下载和解压；如果缓存坏了，删掉 `ndk/android-ndk-r25b-linux` 后重跑。

Android dist 里出现 ROS 2 `.so`：确认构建命令里有 `BUILD_SHARED_LIBS=OFF`，并确认 `scripts/package_android_artifacts.sh` 的静态过滤逻辑仍在。必要时删除 `work/build/android_arm64-v8a`、`work/install/android_arm64-v8a`、`work/dist/android_arm64-v8a` 后重来。

`ais_node_interface` 改了但产物没变：删除 `work/src/ais_node_interface` 和 `work/windows/src/ais_node_interface`，重新复制 `packages/ais_node_interface`。Android 的本地包复制是“目标不存在才复制”。

Windows 静态链接出现 CRT mismatch：确认使用 `-Static`，vcpkg triplet 是 `x64-windows-static`，并且没有混入旧的 shared build 目录。

Windows fetch 每次失败：不要把源码目录删掉。已有 `work/windows/src` 后用 `-SkipFetch` 走编译闭环。