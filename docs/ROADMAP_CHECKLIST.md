# Ros2Builder 下阶段 Checklist

> 三个目标：
> 1. **Docker 一键化**：拉源码 + 编译 Android 一条命令完成，砍掉所有 demo / 分步服务。
> 2. **Windows 编译**：宿主 Windows + VS 2019 Build Tools，产出仅含 DLL、import lib、头文件的 `work/dist/windows/`。
> 3. **Windows C++/ImGui Demo**：与 Android demo 功能对齐，三端（Android / Windows / WSL）互通。
>
> 执行顺序建议：Phase 1 → Phase 2 → Phase 3（串行，先收口风险最小的）。

---

## Phase 1 · Docker 一键化（只做"拉源码 + 编译"）

**目标**：`podman compose run --rm android-build` 一条命令产出 `work/dist/android/`。compose 中不再保留 demo 运行时服务，也不再保留分步服务。

- [x] **1.1 删 demo profile**：从 [docker-compose.yml](../docker-compose.yml) 移除 `ros2-demo-peer`、`ros2-demo-audio`、`ros2-demo-audio-shell`、`ros2-demo-shell`。
- [x] **1.2 删除 `docker/Dockerfile.ros2-demo`**。
- [x] **1.3 删 `examples/pc-ros2-demo/` 整目录**（已被 `examples/wsl-humble-audio-demo/` 取代）。
- [x] **1.4 清理引用 pc-ros2-demo 的旁路脚本/文档**：
  - [scripts/send_audio_to_android_from_wsl.ps1](../scripts/send_audio_to_android_from_wsl.ps1) 已改指向 `examples/wsl-humble-audio-demo/`。
  - README/scripts 中的旧 Docker demo 服务残留已清理。
- [x] **1.5 删分步服务**：移除 `builder`、`prepare-ndk`、`fetch-sources`、`package-artifacts`（profile: manual）。
- [x] **1.6 改名**：`all-in-one` → `android-build`，作为唯一服务。
- [x] **1.7 入口策略二选一**：采用 A，保留 compose 内联命令，不新增包装脚本。
- [x] **1.8 精简 Dockerfile**：[docker/Dockerfile](../docker/Dockerfile) 中两段 proxy `export` 合并为单一 `ARG` 区块 + 单次 `RUN`；apt/pip 合层。
- [x] **1.9 收敛 proxy 配置**：compose 12 行 `*_PROXY` 重复 → 单一 YAML 锚点 `x-proxy-build-args` / `x-proxy-env`。
- [x] **1.10 README 同步**：删除/更新所有引用 `ros2-demo-*` / `pc-ros2-demo` 的段落，统一指向 `examples/wsl-humble-audio-demo/`。
- [x] **1.11 验证**：`podman compose run --rm android-build` 已跑通，产物写入 `work/dist/android_arm64-v8a`（77 packages finished；94 shared libraries；2469 headers）。

---

## Phase 2 · Windows 编译（产物自包含）

**目标**：宿主 Windows + VS 2019 Build Tools，产出 x64 Release 的 `work/dist/windows/`，目录内只保留 `bin/*.dll`、`lib/*.lib` 和 `include/` 头文件；最终 demo 做干净 VM 运行验收。

### 依赖策略（已锁定）
- 第三方系统库**只走 vcpkg 一条路径**。
- 用户**不需要** choco install 任何东西，也不需要 prebuilt zip 分支。
- vcpkg 在 `third_party/vcpkg/` 自举，产物落到 `third_party/windows/`，由 colcon 引用，并最终把 DLL、import lib、头文件合入 `work/dist/windows/`。

### Checklist
- [x] **2.1 环境探测脚本** [scripts/windows/ensure_windows_deps.ps1](../scripts/windows/ensure_windows_deps.ps1)
  - 检查：VS 2019 Build Tools (MSVC v142 + Windows SDK)、CMake ≥ 3.20、Ninja、Git、Python 3.8/3.10。
  - 支持 `-PythonExe` / `-NinjaExe` 显式指定工具路径。
  - 缺失项报错并打印官方下载链接，**不自动安装系统级组件**。
  - 已创建 conda 环境 `ros2builder-humble-win`，提供 Python 3.10.20 + Ninja 1.13.1；显式传参后本机探测通过。
- [x] **2.2 Python 依赖**：由 [scripts/windows/build_windows.ps1](../scripts/windows/build_windows.ps1) 用指定 Python 安装 `colcon-common-extensions vcstool empy==3.3.4 lark catkin_pkg numpy<2 packaging PyYAML setuptools==59.6.0`（安装到指定 Python/conda 环境）。
- [x] **2.3 vcpkg 引导** [scripts/windows/setup_vcpkg.ps1](../scripts/windows/setup_vcpkg.ps1)
  - 若 `third_party/vcpkg/` 不存在则 `git clone` + `bootstrap-vcpkg.bat`。
  - 钉死 vcpkg commit（仓库根 `vcpkg.json` 中的 `builtin-baseline`），保证可复现。
  - vcpkg 安装前显式导入 VS2019 `vcvarsall`，并支持 `-ExtraPath` 暴露 conda 工具目录，避免 vcpkg 自动选到更高版本 MSVC 或重复下载 pkgconf。
  - 支持 `-GitProxy` 临时覆盖 GitHub 代理；`-GitProxy ''` 可绕过失效的全局 GitHub proxy，不修改用户全局 Git 配置。
  - 支持 `-DownloadProxy` 临时设置 vcpkg 下载 CMake/源码包所需的 HTTP(S) 代理。
- [x] **2.4 vcpkg manifest** [vcpkg.json](../vcpkg.json)
  - Triplet：`x64-windows`（DLL）。
  - 产出目录：`third_party/windows/{include,lib,bin}`。
  - **初始依赖（最小集，按构建报错逐步增补）**：`openssl`、`asio`、`tinyxml2`、`eigen3`、`foonathan-memory`。
  - **暂不纳入**（按需追加，避免拉无用大依赖）：`bullet3`（仅 collision_detection 用）、`log4cxx`（可由 rcl_logging_spdlog 替代）、`qt5`、`opencv`。
  - `tinyxml-usestl` 是官方 Windows/Chocolatey 依赖名，不作为 vcpkg 初始 port 写入。
  - 验收准则：vcpkg install 完后 `third_party/windows/bin` 里 DLL 数量在 20 个以内为佳。
- [x] **2.5 源码清单**：复用现有 [manifests/ros2-humble-android.repos](../manifests/ros2-humble-android.repos)（包子集与 Android 一致）。Phase 2.4 的依赖列表要与本清单实际包集合反推对齐；若 Android 清单未包含 log4cxx/bullet，则 vcpkg 也不必拉。
- [x] **2.6 构建脚本** [scripts/windows/build_windows.ps1](../scripts/windows/build_windows.ps1)
  - 参数：`-Workdir`, `-Manifest`, `-BuildType Release`, `-Arch x64`, `-PythonExe`, `-NinjaExe`, `-GitProxy`, `-DownloadProxy`。
  - 流程：`vcstool import` → `vcvarsall x64` → `CMAKE_PREFIX_PATH` 注入 `third_party/windows` → `colcon build --merge-install --cmake-args -G "Ninja" -DBUILD_SHARED_LIBS=ON -DCMAKE_BUILD_TYPE=Release`。
  - RMW：`rmw_fastrtps_cpp`（与 Android 一致）。
- [x] **2.7 打包脚本** [scripts/windows/package_windows_artifacts.ps1](../scripts/windows/package_windows_artifacts.ps1)
  - 整理为 `work/dist/windows/`：只复制 `bin/*.dll`、`lib/*.lib`、`include/`。
  - 不复制 `share/`、`cmake/`、`Lib/`、`Scripts/`、`debug/`、`tools/`、`manifest/`、`manifest.json`、`.pc` 或 vcpkg 元数据。
- [x] **2.8 .gitignore**：忽略 `third_party/vcpkg/`、`third_party/vcpkg_installed/`、`third_party/windows/`、`work/dist/windows/`、`*.vcxproj.user`、`out/`、`CMakeUserPresets.json`。
- [x] **2.9 compose 不留 Windows 占位**（已确认）。
- [x] **2.10 验证**
  - Windows build 已跑通：`77 packages finished [6min 37s]`。
  - `work/dist/windows/` 根目录只剩 `bin/`、`include/`、`lib/`。
  - 当前产物：103 个 DLL、103 个 import lib、3846 个 header。
  - `dumpbin /dependents` 已检查 `rclcpp.dll`、`rmw_fastrtps_cpp.dll`、`rmw_fastrtps_shared_cpp.dll`、`fastrtps-2.6.dll`、`tinyxml2.dll`，依赖列表为 ROS 2/Fast DDS/vcpkg DLL 与 Windows/MSVC runtime，不含 vcpkg 缓存绝对路径。
  - 已扫描 dist 文本元数据，未发现 `work/windows` 或 `third_party/vcpkg_installed` 运行引用；pkg-config prefix 已相对化。
  - 干净 Windows VM 运行验收等待 Phase 3 demo 产出后执行，避免在没有最终 exe 时做伪验证。

---

## Phase 3 · Windows C++/ImGui Demo

**目标**：[examples/windows-ros2-demo/](../examples/windows-ros2-demo/)，DX11 + Win32 backend，链接 Phase 2 的制品，与 Android demo 功能对齐。

### 3.1 项目骨架
- [x] `CMakeLists.txt`：C++17；`find_package(ament_cmake rclcpp std_msgs REQUIRED)`；构建输入使用 `work/windows/install/windows_x64` 和 `third_party/windows`；Post-build 复制 ROS 2/vcpkg DLL 到 exe 目录。
- [x] `third_party/imgui/`：ImGui v1.90.9 已 vendor 进 `examples/windows-ros2-demo/third_party/imgui/`（含 Win32/DX11 backend）。
- [x] `scripts/fetch_imgui.ps1`：用于以后重新拉取 ImGui vendor 源码。
- [x] `scripts/build_debug.ps1`：加载 VS2019 + `work/windows/install/windows_x64/setup.ps1`，Ninja 构建 `windows_ros2_demo.exe`。

### 3.2 ROS 桥（对齐 Android `native_bridge.cpp`）
- [x] `src/ros_bridge.{h,cpp}`：
  - 已实现 `start / stop / snapshot_json / send_command / send_wav_file / cancel_audio_tx`。
  - 订阅：`/android/status`、`/wsl/audio_control`、`/wsl/audio_chunk`。
  - 发布：`/android/command`、`/android/audio_control`、`/android/audio_chunk`。
  - Topic 方向按真实 Android 互通路径调整：Windows 作为 PC peer 给 Android 发命令/音频，并接收 Android 发往 WSL/PC 的音频。
- [ ] **FastDDS 配置文件**：在 demo 启动时把与 Android 等价的 FastDDS XML（参考 `examples/android-ros2-demo/docs/fastdds_wsl_eth1.xml`）写入 `%LOCALAPPDATA%/Ros2Builder/fastdds.xml`，并设置 `FASTRTPS_DEFAULT_PROFILES_FILE` 指向它。
- [ ] Discovery Server 参数走与 Android 相同协议（`ROS_DISCOVERY_SERVER=ip:port`）。

### 3.3 音频 I/O（WASAPI）
- [ ] `src/audio_player.{h,cpp}`：WASAPI shared-mode render；缓冲队列 + 播放线程，行为对齐 Python `audio_stream_sub.py`（buffered drain）。
- [x] `src/audio_capturer.{h,cpp}`：WASAPI shared-mode capture；默认输入设备采集，转换为 mono 16-bit PCM，并发出 `begin_stream` / PCM chunks / `end_stream`。
- [x] `src/wav_io.{h,cpp}`：本地 WAV 解析（16-bit mono PCM）+ 接收落盘 WAV header 写回。
- [x] **接收音频落盘路径约定**：`%LOCALAPPDATA%/Ros2Builder/received/received_<yyyymmdd_HHMMSS>.wav`；最近一次路径在 UI 显示，`Play Received` 默认播这个。

### 3.4 ImGui UI 面板（= Android demo 功能集）
- [x] **Runtime**：Domain ID / Node Name / Publish Rate / QoS / Discovery Server 输入；Start / Stop。
- [x] **Status**：实时展示 `snapshot_json`，包含 Android status、TX/RX 计数、last error。
- [x] **Command**：输入框 + Send，发布到 `/android/command`。
- [x] **Audio RX**：累计字节 / `Play Received` / 保存路径。
- [x] **Audio TX**：`GetOpenFileName` 选 WAV + `Send Speed` 滑块（1.0–32.0）+ Send / Cancel。
- [x] **Mic TX**：默认输入设备 + Duration + Record & Send / Stop。

### 3.5 CLI（对齐 Android intent extras）
- [x] `--auto-start`、`--audio-file <path>`、`--send-speed <n>`、`--discovery-server <ip:port>`、`--domain-id <n>`。

### 3.6 验证
- [ ] **DDS 发现先行验证**：Windows demo 先用与 Android/WSL 同样的 FastDDS XML / Discovery Server 设置打通发现（`ros2 topic list` 跨端可见），再做后续音频/命令测试。
- [x] 本机构建验证：`examples/windows-ros2-demo/scripts/build_debug.ps1` 已成功生成 `examples/windows-ros2-demo/build/windows_ros2_demo.exe`。
- [x] exe 依赖验证：Post-build 已复制 ROS 2/vcpkg DLL；`dumpbin /dependents windows_ros2_demo.exe` 依赖为 ROS 2 DLL、D3D/WinMM/系统/MSVC runtime。
- [ ] Windows demo ↔ Android demo：双向音频 + 命令收发。
- [ ] Windows demo ↔ WSL `wsl-humble-audio-demo`：双向音频 + 命令收发。
- [ ] `--send-speed 20` 与 Android 端结果对齐（20 s WAV ≈ 1.2 s 发完）。

### 3.7 文档
- [ ] `examples/windows-ros2-demo/README.md`：依赖 / 构建 / 运行 / 与 Android demo 功能对照表。
- [ ] 顶层 [README.md](../README.md) 加 Windows 章节并更新拓扑图。

---

## 决策快照（已确认）

| 项 | 决定 |
|---|---|
| Docker 是否保留 demo 服务 | 不保留，删 |
| `examples/pc-ros2-demo/` | 整目录删 |
| Docker 是否覆盖 Windows | 不覆盖，Windows 走宿主 PowerShell |
| compose 是否给 Windows 留占位 | 不留 |
| Windows ROS 2 编译宿主 | Windows + VS 2019 Build Tools |
| Windows 第三方依赖来源 | 仅 vcpkg 一条路径 |
| Windows 产物形态 | x64 Release，DLL + import lib + headers，自包含 |
| Windows 源码清单 | 复用 `manifests/ros2-humble-android.repos` |
| ImGui 后端 | DirectX 11 + Win32 |
| ImGui 引入方式 | 源码 vendor 进仓库 `third_party/imgui/` |
| Demo 目录 | `examples/windows-ros2-demo/` |

---

## 待你最终拍板
- [x] 整体 checklist 已确认按此推进。
- [x] 执行顺序已确认按 **Phase 1 → 2 → 3** 串行推进。
