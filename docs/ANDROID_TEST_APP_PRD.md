# Android ROS 2 Test App PRD

## 1. 背景

本项目已经初步打通 ROS 2 Humble 到 Android `arm64-v8a` 的交叉编译流程，但还缺少一个能在 Android 真机上验证基础 ROS 2 能力的测试应用。这个 PRD 定义一个轻量 Android App，用于验证 ROS 2 节点发现、话题发布订阅、服务调用、参数控制、QoS、网络恢复和 Android 生命周期行为。

应用定位不是最终机器人产品，而是构建产物的运行时验收工具。它应该能帮助开发者判断当前 Android ROS 2 包是否可用、哪里失败、失败是否来自权限、网络、DDS 发现、JNI 边界、生命周期或 C++ 逻辑。

## 2. 产品目标

- 验证 Android 设备可以作为 ROS 2 节点加入局域网 ROS graph。
- 验证 `rclcpp`、`rmw_fastrtps_cpp`、标准消息、参数和基础服务能力。
- 尽量把 ROS 2 逻辑、状态机、消息处理、错误归因放在 C++ 层。
- Android 层只负责权限申请、前后台生命周期入口、纯 UI 展示和用户输入转发。
- 提供清晰的测试结果，让用户不依赖大量 `adb logcat` 也能判断核心链路是否正常。

## 3. 非目标

- 不实现完整机器人控制 App。
- 不内置复杂地图、导航、图像处理或 rosbag 回放能力。
- 不要求第一版支持多 RMW 实现。
- 不在 Android/Kotlin 层实现 ROS 2 协议、DDS 逻辑或业务状态机。
- 不把本仓库改造成 Android Gradle 工程；测试 App 可作为后续独立示例工程接入本仓库产物。

## 4. 目标用户

- 维护 ROS 2 Android 构建链路的开发者。
- 想把 ROS 2 C++ 节点嵌入 Android App 的机器人开发者。
- 需要验证 Android 设备与 PC/机器人在同一局域网中通信能力的测试人员。

## 5. 核心原则

### 5.1 C++ 优先

C++ 层负责：

- 创建和销毁 ROS 2 context、executor、node。
- 创建 publisher、subscription、service、client 和参数。
- 管理节点状态机、连接状态、统计数据、错误分类和恢复策略。
- 解析和生成 ROS 2 消息。
- 维护测试会话结果和可导出的诊断信息。

Android 层负责：

- 展示 C++ 层输出的只读状态模型。
- 收集用户点击、输入和开关状态，并转发成简单命令。
- 申请网络、通知、震动、前台服务等 Android 权限。
- 承载 Foreground Service，保证后台测试可控运行。

### 5.2 UI 是视图，不是业务层

Android UI 不判断 ROS 2 是否健康，不拼接 ROS 消息，不维护测试用例状态机。UI 只展示 C++ 层给出的 `AppState`，并把用户操作映射成 `AppCommand`。

### 5.3 可诊断优先

每个测试场景都必须输出：

- 当前状态。
- 成功条件。
- 最近错误。
- 建议排查方向。
- 关键计数器，例如发送数、接收数、丢包估计、重连次数。

## 6. 总体架构

```text
Android UI
  - Activity / Compose UI
  - Permission prompts
  - Foreground Service shell
  - Native state rendering
  - User command forwarding

JNI Boundary
  - startSession(config)
  - stopSession()
  - sendCommand(command)
  - getSnapshot()
  - subscribeState(callback)

C++ Core
  - RosRuntime
  - AndroidTestNode
  - ScenarioManager
  - MetricsCollector
  - DiagnosticsStore
  - Native AppState reducer

ROS 2 Network
  - Android node
  - PC ROS 2 CLI or desktop helper node
  - Optional robot-side ROS 2 nodes
```

## 7. 分层边界

### 7.1 Android UI 层

职责：

- 展示首页、测试场景页、日志页和设置页。
- 显示节点名、Domain ID、RMW、IP、Wi-Fi 状态、权限状态。
- 提供启动、停止、重置、导出诊断等按钮。
- 展示 C++ 层发布的测试结果和计数器。
- 处理 Android 权限和 Foreground Service 通知。

禁止：

- 直接调用 ROS 2 C API 或 C++ API。
- 在 Kotlin/Java 层构造 ROS 2 message payload。
- 在 UI 层判断测试通过或失败。
- 在 UI 层实现重连、超时、QoS 切换状态机。

### 7.2 JNI 层

职责：

- 提供稳定、少量、粗粒度的 native API。
- 完成 Kotlin 数据结构和 C++ DTO 的转换。
- 处理 native 线程与 UI 线程的状态通知边界。
- 保证异常和错误码不会跨语言边界失控。

建议接口：

```text
NativeRosBridge.startSession(SessionConfig config): Result
NativeRosBridge.stopSession(): Result
NativeRosBridge.updateConfig(SessionConfig config): Result
NativeRosBridge.sendUserCommand(UserCommand command): Result
NativeRosBridge.getSnapshot(): AppState
NativeRosBridge.setStateListener(StateListener listener): void
NativeRosBridge.exportDiagnostics(): DiagnosticBundle
```

### 7.3 C++ Core 层

职责：

- 封装 `rclcpp::Context`、`rclcpp::executors::MultiThreadedExecutor` 和节点生命周期。
- 创建测试用 publisher、subscription、service、client、parameters。
- 执行场景测试状态机。
- 维护 App 可展示状态。
- 输出结构化诊断。

核心对象建议：

```text
RosRuntime
  owns rclcpp context, executor thread, init/shutdown lifecycle

AndroidTestNode
  owns publishers, subscriptions, services, parameters

ScenarioManager
  owns scenario state machines and pass/fail logic

MetricsCollector
  records counters, latency samples, discovery time, reconnects

DiagnosticsStore
  records recent events, errors, environment snapshot
```

## 8. 第一版功能需求

### 8.1 会话配置

用户可在 UI 中配置：

- `ROS_DOMAIN_ID`。
- 节点名，默认 `android_phone_node`。输入框中的 node name 不能带 `/`；ROS CLI 中显示的完整节点名为 `/android_phone_node`。
- 发布频率，默认 `1 Hz`。
- QoS 模式：`reliable` 或 `best_effort`。
- 是否后台运行。
- 是否启用震动反馈。

配置由 Android UI 传给 C++，C++ 决定是否需要重启 ROS runtime。

### 8.2 节点发现测试

Android 端启动节点后，PC 端应能看到：

```bash
ros2 node list
```

预期节点：

```text
android_phone_node
```

C++ 层记录：

- runtime 启动时间。
- 节点创建结果。
- executor 是否运行。
- 当前 ROS graph 可见节点数量。

UI 展示：

- 节点状态：未启动、启动中、运行中、停止中、失败。
- Domain ID。
- RMW 实现。
- 最近错误。

### 8.3 Topic 发布测试

Android C++ 节点周期发布：

```text
/android/status
std_msgs/msg/String
```

消息内容建议为 JSON 字符串，便于 PC 端直接观察：

```json
{"seq":123,"device":"android","battery":82,"state":"running"}
```

PC 验证：

```bash
ros2 topic echo /android/status
```

C++ 层记录：

- 已发布消息数。
- 发布频率。
- 最近一次发布时间。
- publisher 创建错误。

### 8.4 Topic 订阅测试

Android C++ 节点订阅：

```text
/android/command
std_msgs/msg/String
```

PC 发送：

```bash
ros2 topic pub --once /android/command std_msgs/msg/String "{data: 'ping'}"
```

支持命令：

- `ping`：Android 状态页显示最近收到 ping。
- `vibrate`：C++ 生成事件，Android UI 层收到事件后触发震动能力。
- `reset_metrics`：C++ 重置计数器。
- `set_rate:5`：C++ 调整发布频率。

C++ 层记录：

- 已接收命令数。
- 最近命令。
- 命令解析结果。
- 非法命令数量。

### 8.5 Service 测试

建议第二步构建加入：

```text
std_srvs
```

Android C++ 节点提供：

```text
/android/get_info
std_srvs/srv/Trigger
```

PC 调用：

```bash
ros2 service call /android/get_info std_srvs/srv/Trigger
```

返回示例：

```text
success: true
message: "abi=arm64-v8a; rmw=rmw_fastrtps_cpp; pub=123; sub=4"
```

如果第一版暂不引入 `std_srvs`，则服务测试作为 V1.1 功能，V1 先覆盖 topic 和 parameter。

### 8.6 Parameter 测试

Android C++ 节点声明参数：

```text
publish_rate_hz
device_label
enable_status_publish
qos_mode
```

PC 验证：

```bash
ros2 param list /android_phone_node
ros2 param get /android_phone_node publish_rate_hz
ros2 param set /android_phone_node publish_rate_hz 5.0
```

C++ 层负责参数校验和应用。UI 只展示当前参数快照。

### 8.7 QoS 测试

支持两种模式：

- `best_effort`：适合弱网和传感器流。
- `reliable`：适合控制和状态确认。

切换 QoS 时由 C++ 层重建相关 publisher/subscription，并输出切换事件。

UI 展示：

- 当前 QoS。
- 切换次数。
- 最近一次切换是否成功。

### 8.8 Android 生命周期测试

测试 App 需要覆盖：

- 前台启动节点。
- 切后台继续运行。
- 锁屏后继续运行或明确暂停。
- 重新回到前台后状态一致。
- 用户手动停止 Foreground Service 后 ROS runtime 正确关闭。

C++ 层维护 runtime 状态，Android 层只把生命周期事件转成命令：

```text
AppForegrounded
AppBackgrounded
ServiceStarted
ServiceStopped
```

### 8.9 网络恢复测试

测试步骤：

1. Android 和 PC 连接同一 Wi-Fi。
2. 启动 Android ROS 2 节点。
3. PC echo `/android/status`。
4. Android 关闭 Wi-Fi 10 秒。
5. Android 重新连接 Wi-Fi。
6. 观察节点是否恢复发布，PC 是否重新收到消息。

C++ 层记录：

- 网络断开事件。
- 网络恢复事件。
- 恢复后首条消息时间。
- ROS runtime 是否重启。

Android 层可以读取网络状态，但恢复策略由 C++ 层决定。

## 9. 典型应用场景

### 9.1 场景 A：手机作为 ROS 2 状态节点

目标：验证 Android 节点能被 PC 发现，并周期发布状态。

流程：

1. 用户打开 App，确认权限通过。
2. 用户点击 Start。
3. C++ 层启动 ROS runtime 和 node name `android_phone_node`，ROS graph 中显示为 `/android_phone_node`。
4. Android 节点发布 `/android/status`。
5. PC 执行 `ros2 topic echo /android/status`。
6. UI 显示 published count 持续增长。

验收：

- PC 5 分钟内持续收到状态消息。
- UI 无 native crash。
- 停止后 PC 不再收到消息，重新启动后恢复。

### 9.2 场景 B：PC 控制 Android UI 反馈

目标：验证 Android 订阅 PC 指令，并把 C++ 事件展示到 UI。

流程：

1. App 启动节点并订阅 `/android/command`。
2. PC 发布 `ping`。
3. C++ 层解析命令并更新 `lastCommand`。
4. UI 展示最近命令和接收时间。
5. PC 发布 `vibrate`。
6. C++ 层发出 `VibrateRequested` UI 事件。
7. Android 层执行震动。

验收：

- 命令计数准确增长。
- 非法命令不会导致崩溃。
- UI 只展示 C++ 结果，不自己解析 ROS 消息。

### 9.3 场景 C：PC 查询 Android 运行信息

目标：验证服务调用或等效 request/response 能力。

流程：

1. App 启动 `/android/get_info` 服务。
2. PC 调用服务。
3. C++ 层返回 ABI、RMW、Domain ID、计数器、运行时长。
4. UI 的 service counter 同步增长。

验收：

- 服务调用 10 次全部成功。
- 返回信息与 UI 展示一致。
- Android 前后台切换后服务仍可调用，或明确显示服务暂停。

### 9.4 场景 D：参数驱动行为变化

目标：验证 ROS 2 参数能控制 Android 节点行为。

流程：

1. PC 查看 `publish_rate_hz`。
2. PC 设置 `publish_rate_hz=5.0`。
3. C++ 层校验并应用参数。
4. `/android/status` 频率变为约 5 Hz。
5. UI 显示当前频率和参数更新时间。

验收：

- 合法参数生效。
- 非法参数被拒绝并返回原因。
- UI 展示值来自 C++ 状态快照。

### 9.5 场景 E：弱网和网络恢复

目标：验证 Wi-Fi 中断和恢复后的行为可解释。

流程：

1. App 正常发布状态。
2. 用户关闭 Android Wi-Fi。
3. C++ 层记录通信异常或网络事件。
4. 用户重新打开 Wi-Fi。
5. C++ 层恢复或重启 ROS runtime。
6. PC 重新收到 `/android/status`。

验收：

- App 不崩溃。
- UI 明确显示断开、恢复、重连次数。
- 恢复策略在诊断信息中可见。

### 9.6 场景 F：后台长时间运行

目标：验证 Android 生命周期和 Foreground Service 策略。

流程：

1. App 启动节点并开启后台运行。
2. 用户切到后台或锁屏。
3. Foreground Service 保持运行。
4. PC 持续 echo 状态话题。
5. 用户回到 App。
6. UI 从 C++ 获取最新状态快照。

验收：

- 后台 30 分钟内无崩溃。
- 发布计数持续增长，或暂停策略明确可见。
- 回到前台后 UI 状态不倒退、不丢关键错误。

## 10. UI 设计需求

### 10.1 首页 Dashboard

展示：

- Start / Stop。
- 节点状态。
- Domain ID。
- RMW。
- Wi-Fi 状态。
- 发布数、接收数、服务调用数。
- 最近错误。

### 10.2 场景页 Scenarios

展示每个场景的：

- 运行状态。
- 成功条件。
- 当前步骤。
- 关键计数器。
- 最近一次失败原因。

### 10.3 参数页 Parameters

展示：

- 当前参数快照。
- 可编辑参数输入控件。
- 参数应用结果。

参数校验失败原因来自 C++。

### 10.4 诊断页 Diagnostics

展示：

- 最近事件列表。
- native runtime 信息。
- 构建 ABI 和 Android API。
- ROS_DOMAIN_ID、RMW_IMPLEMENTATION。
- 可复制或导出诊断文本。

## 11. 数据模型建议

### 11.1 SessionConfig

```text
domainId: int
nodeName: string
publishRateHz: double
qosMode: enum { BestEffort, Reliable }
runInBackground: bool
enableVibration: bool
```

### 11.2 AppState

```text
runtimeState: enum { Stopped, Starting, Running, Stopping, Failed }
nodeName: string
domainId: int
rmwImplementation: string
networkState: enum { Unknown, Connected, Disconnected }
publishedCount: uint64
receivedCommandCount: uint64
serviceCallCount: uint64
reconnectCount: uint64
lastCommand: string
lastError: DiagnosticEvent?
scenarios: list<ScenarioState>
parameters: map<string, ParameterValue>
```

### 11.3 UserCommand

```text
type: enum { Start, Stop, ResetMetrics, ApplyConfig, ExportDiagnostics }
payload: string or structured DTO
```

## 12. 权限和 Android 能力

必须：

- `INTERNET`
- `ACCESS_WIFI_STATE`
- `CHANGE_WIFI_MULTICAST_STATE`

建议：

- Foreground Service 相关权限。
- Android 13+ 通知权限。
- 震动权限，如果支持 `vibrate` 命令。

运行时必须持有 `WifiManager.MulticastLock`，否则 Fast DDS 发现可能不稳定。

## 13. 构建包需求

V1 最小包：

```text
rclcpp rmw_fastrtps_cpp std_msgs
```

V1.1 建议增加：

```text
std_srvs
```

后续扩展：

```text
sensor_msgs geometry_msgs nav_msgs tf2_ros image_transport
```

## 14. 验收标准

V1 必须满足：

- Android 真机 App 能启动 native ROS 2 runtime。
- PC 能通过 `ros2 node list` 发现 Android 节点。
- PC 能 echo Android 发布的 `/android/status`。
- Android 能接收 PC 发布到 `/android/command` 的消息。
- 参数至少支持读取和修改 `publish_rate_hz`。
- App 前后台切换不导致 native 崩溃。
- 停止测试后 C++ 层能正确 shutdown ROS runtime。
- UI 展示状态全部来自 C++ `AppState`。

V1.1 必须满足：

- 支持 `/android/get_info` 服务。
- 支持 QoS 模式切换。
- 支持诊断信息导出。
- 支持 Wi-Fi 中断恢复测试。

## 15. 里程碑

### M1：Native Smoke Test

- 完成 C++ runtime、node、publisher、subscription。
- Android UI 只提供 Start / Stop 和状态展示。
- PC 可完成 node list、topic echo、topic pub。

### M2：参数和诊断

- C++ 支持参数声明、读取、设置和校验。
- UI 展示参数和最近错误。
- 支持导出诊断文本。

### M3：服务和 QoS

- 增加 `std_srvs` 构建。
- 支持 `/android/get_info`。
- 支持 reliable / best_effort 切换。

### M4：生命周期和弱网

- 接入 Foreground Service。
- 支持后台运行测试。
- 支持 Wi-Fi 中断恢复统计。

## 16. 风险

- Fast DDS 发现依赖 Wi-Fi、多播和 Android 网络策略，真机差异可能明显。
- Android 后台限制会影响长时间运行，需要 Foreground Service。
- JNI 状态回调需要避免线程、生命周期和内存释放问题。
- `std_srvs` 或后续消息包可能扩大当前构建范围，需要单独验证。
- 不同 Android 厂商 ROM 对后台网络和多播支持不一致。

## 17. 待确认问题

- 第一版是否把 `std_srvs` 纳入默认构建包。
- 测试 App 是放在独立仓库，还是作为本仓库 `examples/android-smoke-test` 后续加入。
- UI 技术栈使用原生 View、Jetpack Compose 还是简单 Activity。
- 是否需要提供 PC 端 helper node，还是完全依赖 ROS 2 CLI。
- 是否需要支持有线 USB reverse/tethering 网络场景。