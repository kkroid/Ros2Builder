# Android ↔ PC 局域网联调测试计划

本计划面向"PC（WSL2 Ubuntu-22.04 + ROS 2 Humble）+ 物理 Android 设备 + 同一 Wi-Fi 局域网"的联调场景，目标是先打通发现层，再逐项验证 [examples/android-ros2-demo](../README.md) 当前实现的话题。

> 相关文档：
> - 依赖瘦身审计：[DEPENDENCY_AUDIT.md](DEPENDENCY_AUDIT.md)
> - Demo 说明：[../README.md](../README.md)
> - 设计 PRD：[../../../docs/ANDROID_TEST_APP_PRD.md](../../../docs/ANDROID_TEST_APP_PRD.md)

## 0. 前置：解决 WSL2 多播

FastDDS 默认靠 UDP 多播做 SPDP 发现。WSL2 默认 NAT 模式下多播不可达，必须先选一条路解决，否则后面所有步骤都会"配置看着对，就是看不到对方"。

任选一条（推荐顺序）：

1. **WSL 镜像网络（推荐）**。Windows 用户目录 `%USERPROFILE%\.wslconfig` 加：

   ```ini
   [wsl2]
   networkingMode=mirrored
   ```

   然后 `wsl --shutdown` 重启。WSL 与 Windows 共享网卡，多播走真实局域网。
   - 验证：`wsl -d Ubuntu-22.04-Humble -- ip -4 addr` 应能看到与手机同网段的地址（而不是 `172.x` 这种 NAT 段）。

2. **FastDDS Discovery Server（绕过多播）**。PC 跑：

   ```bash
   fastdds discovery -i 0 -l 0.0.0.0 -p 11811
   ```

   然后两端都设 `ROS_DISCOVERY_SERVER=<PC局域网IP>:11811`。Demo 的 [native_bridge.cpp](../app/src/main/cpp/native_bridge.cpp) 已读取该环境变量，但当前默认为空。要走这条路需要先给 App 加一个 UI 输入框或 BuildConfig 字段注入。

3. **改用 Windows 原生 Humble 或独立 Linux 主机**。最稳，但取决于硬件布局。

**默认路线：方案 1**。如未确认，先不要进入 §1。

### 0.1 mirrored 模式下的两个隐藏坑（实测踩过）

走方案 1 时，WSL `ip addr` 看似正常、`ping 出站`也通，但 `ros2 node list` 仍然空。原因有三层：

1. **Hyper-V VM Switch 防火墙**：mirrored 模式在 Hyper-V 虚拟交换机上挂了一层独立防火墙，默认 `DefaultInboundAction=Block`。Windows Defender 防火墙规则对它无效，必须用 `*-NetFirewallHyperVRule` 系列单独放行。WSL 对应的 `VMCreatorId` 通常是 `{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}`（可用 `Get-NetFirewallHyperVVMSetting -PolicyStore ActiveStore` 核对）。
2. **网络配置文件 = Public**：Windows Defender 公共配置默认入站全拦。需要把承载局域网的网卡切到 Private。
3. **PC 多网卡**：FastDDS 默认会在所有网卡上广播 SPDP，多网卡下 daemon 容易 hang、`node list` 不稳。需要用 XML profile 把 participant 绑到唯一的局域网网卡。

修复脚本（管理员 PowerShell 跑一次即可，参考 [setup_wsl_fw.ps1](setup_wsl_fw.ps1)）：

```powershell
# 1) 把 LAN 网卡切到 Private（按需把 InterfaceAlias 改成实际名）
Set-NetConnectionProfile -InterfaceAlias '以太网' -NetworkCategory Private

# 2) 放行 FastDDS 入站到 WSL（UDP 7400-7600，限本网段来源）
New-NetFirewallHyperVRule `
    -Name 'ROS2_FastDDS_LAN_Inbound' `
    -DisplayName 'ROS2 FastDDS LAN Inbound (UDP 7400-7600 from 192.168.3.0/24)' `
    -VMCreatorId '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}' `
    -Direction Inbound -Protocol UDP `
    -LocalPorts 7400-7600 -RemoteAddresses 192.168.3.0/24 -Action Allow
```

FastDDS 单网卡绑定（参考 [fastdds_wsl_eth1.xml](fastdds_wsl_eth1.xml)，把 `192.168.3.143` 改成 WSL 实际局域网 IP）：

```bash
# 把 fastdds_wsl_eth1.xml 复制到 WSL 内任意路径，然后：
export FASTRTPS_DEFAULT_PROFILES_FILE=/tmp/fastdds_eth1.xml
# 之后 ros2 node list / topic echo / daemon 都会只用 eth1
```

**自检**：在 WSL 里 `sudo timeout 6 tcpdump -i eth1 -n 'udp and src host <手机IP>'`，应在 ~10s 内能看到来自手机 7400/7410/7411 的 UDP 包；如果计数仍为 0，说明上面 1/2 没生效。


## 1. 网络与发现层冒烟（约 5 分钟）

| #   | 步骤 | 期望 |
| --- | --- | --- |
| 1.1 | 手机连 Wi-Fi，记录手机 IP `A`（`adb shell ip -4 addr show wlan0` 或系统设置） | 与 PC 同 `/24` |
| 1.2 | WSL 里 `ip -4 addr` 记录 PC IP `P` | 与 `A` 同子网 |
| 1.3 | WSL `ping -c 3 A`；手机端 `adb shell ping -c 3 P` | 双向通 |
| 1.4 | WSL：先 `export FASTRTPS_DEFAULT_PROFILES_FILE=/tmp/fastdds_eth1.xml`（见 §0.1），再 `ros2 daemon stop && ros2 daemon start`，然后 `ROS_DOMAIN_ID=0 ros2 node list` | App 未启动时为空；daemon 启动不应 hang |
| 1.5 | 启动 App，点 Start，等 5 秒，再次 `ros2 node list` | 出现 `/android_phone_node` |
| 1.6 | `ros2 topic list -t` | 含 `/android/status [std_msgs/msg/String]`、`/android/command`、`/android/audio_control`、`/android/audio_chunk` |

> 任何一步失败：立即停止后续测试，回到 §0 排查网络。

## 2. 已实现话题的功能验证

Demo 当前实现（详见 [../README.md](../README.md) "Current Scope"）：

- 发布：`/android/status`
- 订阅：`/android/command`、`/android/audio_control`、`/android/audio_chunk`

### 2.1 `/android/status` 发布（PC ← Android）

- PC：`ros2 topic echo /android/status`，预期持续输出 JSON（`runtimeState`、`publishedCount` 等），频率与 App UI 上 `publishedCount` 增长一致。
- PC：`ros2 topic hz /android/status` 跑 10 秒，记录平均频率作为 §4 长稳基线。

### 2.2 `/android/command` 订阅（PC → Android）

- 单条：

  ```bash
  ros2 topic pub --once /android/command std_msgs/msg/String "{data: 'ping-1'}"
  ```

  期望 App UI：`receivedCount` +1，`lastCommand` 显示 `ping-1`。

- 连发：

  ```bash
  for i in 1 2 3 4 5; do
    ros2 topic pub --once /android/command std_msgs/msg/String "{data: \"ping-$i\"}"
  done
  ```

  期望计数严格 +5，`lastCommand` 显示 `ping-5`。

### 2.3 音频控制 + 块（PC → Android，流式播放 + 落盘）

协议：
- `/android/audio_control` (`std_msgs/String`)：`begin_stream:<rate>:<channels>:<sample_width>` 起流式（实时播放 + 同步保存），或 `begin` 仅保存；以 `end_stream` / `end` 结束。
- `/android/audio_chunk` (`std_msgs/UInt8MultiArray`)：raw PCM little-endian。
- 约束：App 端流式播放仅接受 **mono / 16-bit PCM**；多声道或非 16-bit 会回退到 file-only 模式。

发送脚本：[audio_stream_pub.py](audio_stream_pub.py)

```bash
# WSL 端
source /opt/ros/humble/setup.bash
export FASTRTPS_DEFAULT_PROFILES_FILE=/tmp/fastdds_eth1.xml
cd /mnt/e/github/Ros2Builder/examples/android-ros2-demo/docs

# A) 正弦波（自带 16 kHz / mono / 16-bit）
python3 audio_stream_pub.py --tone 440 --duration 3 --mode stream

# B) WSLg 麦克风录音，`--duration` 是录制时长（秒）
export PULSE_SERVER=unix:/mnt/wslg/PulseServer
python3 audio_stream_pub.py --mic --duration 5 --mode stream

# TTS-like 快合成：20 秒音频按 20x 速度发送，Android 端本地缓冲播放
python3 audio_stream_pub.py --tone 440 --duration 20 --mode stream --speed 20

# C) 任意 WAV（若非 mono 16-bit，先转码）
ffmpeg -y -i input.wav -ar 16000 -ac 1 -sample_fmt s16 /tmp/in16k.wav
python3 audio_stream_pub.py --wav /tmp/in16k.wav --mode stream --speed 20
```

期望：
- 脚本日志看到 `matched subscribers control=1 chunk=1` 与 `done: N bytes in M chunks`。
- App UI：`audioState=streaming` → `ready`，`audioBytes` ≈ WAV/tone 字节数；`logcat | grep AudioTrack` 看到 AudioTrack 创建。
- 流结束后点 `Play Received Audio` 能复播保存的 `ros2_audio.wav`。

### 2.4 音频控制 + 块（Android → PC，流式上行）

协议：
- `/wsl/audio_control` (`std_msgs/String`)：同上格式，由 App 发出。
- `/wsl/audio_chunk` (`std_msgs/UInt8MultiArray`)：App 发出。

接收脚本：[audio_stream_sub.py](audio_stream_sub.py)。WSLg 环境推荐默认的 `pacat` 后端；如果是原生 Linux 声卡，也可用 `--player aplay`。

```bash
# WSL 端
source /opt/ros/humble/setup.bash
export FASTRTPS_DEFAULT_PROFILES_FILE=/tmp/fastdds_eth1.xml
export PULSE_SERVER=unix:/mnt/wslg/PulseServer
python3 /mnt/e/github/Ros2Builder/examples/android-ros2-demo/docs/audio_stream_sub.py \
  --player pacat --save /tmp/from_phone.wav
```

操作：
1. 准备一份 WAV 推到手机 `adb push input.wav /sdcard/Download/`（mono 16-bit 最稳）。
2. App 点 `Send Audio File to PC` → 文件选择器 → 选刚才推的 WAV。
3. App UI `Send to PC: ...` 显示进度；WSL 端 `pacat` 实时播放并写入 `from_phone.wav`。

无人值守自动触发（debug 包）：

```bash
# 先把 WAV 放进 App 私有目录，避免 Android 13+ 外部存储 EACCES
adb push input.wav /data/local/tmp/input.wav
adb shell run-as com.example.ros2demo cp /data/local/tmp/input.wav files/input.wav

# 冷启动 App 并自动发送该文件
adb shell am force-stop com.example.ros2demo
adb shell am start -n com.example.ros2demo/.MainActivity \
  --ez autoStart true \
  --es sendAudioFile /data/user/0/com.example.ros2demo/files/input.wav \
  --es sendSpeed 20
```

期望：
- WSL 看到 `begin_stream:RATE:CH:WIDTH` 日志；快发时 `playback buffer=...s` 会增长，结束后 `draining playback buffer` 再平滑播完。
- 结束时看到 `stream end: N bytes in M chunks` 与 `wrote /tmp/from_phone.wav`。
- `wc -c /tmp/from_phone.wav` 与 App 端读取的 PCM 字节数（不含 WAV 头则相差 44）一致。
- 若 WSLg 无法出声，可在 Windows 端直接播 `/tmp/from_phone.wav` 验证数据。

## 3. 负面 / 边界用例

- **多播锁**：当前 App 已通过 `WifiManager.MulticastLock` 锁住多播。临时注释掉相关代码复测，确认能复现"PC 看不到 node"，建立对该症状的认知。
- **手机灭屏 / App 切后台**：保持 Foreground Service 运行 5 分钟，PC 端 `ros2 topic echo /android/status` 应继续更新。验证系统省电策略下网络是否仍稳。
- **Wi-Fi 切换**：手机断开 Wi-Fi 30 秒再连上，观察 App 是否自动恢复 publish 还是停在错误态。验证 FastDDS 重发现行为。
- **不同 `ROS_DOMAIN_ID`**：PC 改 `ROS_DOMAIN_ID=42` 应看不到 node；改回 0 又能看到。App 当前 domain id 固定为 0（见 [native_bridge.cpp](../app/src/main/cpp/native_bridge.cpp) env 设置）。

## 4. 长稳与基线（可选，约 30 分钟挂机）

- `/android/status` 跑 30 分钟，记录起止 `publishedCount`，算实际频率与目标频率差值。
- `adb shell dumpsys meminfo com.example.ros2demo` 在 0 / 15 / 30 分钟各采一次，看 native heap 是否泄漏。
- `ros2 topic bw /android/status` 取带宽基线。
- 数据用于后续 release build / 增加话题时的对比。

## 5. 通过标准（验收 Checklist）

- [ ] §1.1–§1.6 全部 Pass。
- [ ] §2.1 `topic echo` 持续输出，`topic hz` 与 App UI `publishedCount` 增速一致。
- [ ] §2.2 单条与连发命令的 `receivedCount` / `lastCommand` 一一对应。
- [ ] §2.3 PC→Android：脚本 `done` 字节数与 App `audioBytes` 一致，`Play Received Audio` 可播。
- [ ] §2.4 Android→PC：App 进度日志走到结束，WSL 端 `from_phone.wav` 字节数与发送一致且可播。
- [ ] §3 灭屏 5 分钟仍正常发布。
- [ ] §3 域 ID 隔离生效。

## 6. 数据采集模板

每次执行测试时填写以下信息，便于回归对比：

```
日期：YYYY-MM-DD
APK：<git short SHA> / <构建类型 debug|release>
PC：WSL2 mirrored / discovery-server / native
PC IP：
手机型号 / Android 版本：
手机 IP：
ROS_DOMAIN_ID：
§1 结果：
§2.1 hz 平均值：
§2.2 receivedCount 增量 vs 期望：
§2.3 字节数一致 / 播放 OK：
§3 各项结果：
§4 30min publishedCount / 内存采样：
备注 / 异常：
```
