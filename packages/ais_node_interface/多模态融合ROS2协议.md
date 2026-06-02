# 多模态融合ROS2协议V2.0.0

本文档以 `ais_node_interface/msg`、`ais_node_interface/srv` 下的实际接口文件以及当前 SDK 运行时代码为准。

状态标注：

- **未实现**：协议/接口预留，但当前 SDK 未创建对应 ROS2 实体或未实现对应行为。
- **未使用**：接口、字段或 publisher 已存在，但当前 SDK 运行时未发布数据或未参与实际调用。

## Topic

### 订阅 (外部 -> ais_node)

| 名称                     | 消息类型     | 说明                          |
| ------------------------ | ------------ | ----------------------------- |
| `/aisrobot/audio/raw`    | AudioCapture | 原始音频输入                  |
| `/aisrobot/vision/image` | ImageMsg     | 图像输入（人脸检测/挥手共用） |

### 发布 (ais_node -> 外部)

| 名称                         | 消息类型         | 说明                                                           |
| ---------------------------- | ---------------- | -------------------------------------------------------------- |
| `/aisrobot/audio/denoised`   | AudioCapture     | 降噪后音频（未使用：publisher 已创建，当前 SDK 未发布数据）    |
| `/aisrobot/audio/wake`       | WakeEvent        | 唤醒事件                                                       |
| `/aisrobot/audio/doa`        | DoaMsg           | 声源方向                                                       |
| `/aisrobot/audio/asr`        | AsrResult        | 语音识别结果                                                   |
| `/aisrobot/vision/face`      | FaceFeatureArray | 多人脸特征结果                                                 |
| `/aisrobot/vision/gesture`   | GestureEvent     | 手势识别结果                                                   |
| `/aisrobot/dm/output`        | DmOutput         | 对话管理输出                                                   |
| `/aisrobot/audio/kws_eval`   | KwsEvalResult    | 自定义唤醒词评估异步结果                                       |
| `/aisrobot/face_id/result`   | FaceIdResult     | FaceId 异步事件上报；service 业务回调优先同步消费，未命中等待者时发布到 topic |
| `/aisrobot/status`           | AiStatus         | 状态通知                                                       |

## Service

| 名称                | 服务类型 | 说明                                                                                                           |
| ------------------- | -------- | -------------------------------------------------------------------------------------------------------------- |
| `/aisrobot/session` | Session  | AI 运行域总控（set_language 已实现；open/close 当前为未实现占位）                                               |
| `/aisrobot/wakeup`  | Wakeup   | 唤醒域控制（set_doa/eval_kws/reset_custom_wkp/change_wakeup_word）                                             |
| `/aisrobot/dialog`  | Dialog   | 对话业务控制（start_dialog/stop_dialog/input_text）                                                            |
| `/aisrobot/tts`     | Tts      | 主动 TTS 播报控制（start/stop）                                                                                |
| `/aisrobot/face_id` | FaceId   | 人脸识别控制（register/recognize/compare/query/delete/clear 6 cmd 一次性请求-响应；face_id 由客户端生成 UUID） |

## Parameter（未实现）

当前 SDK 未注册 ROS2 Parameter。日志级别、版本号、配置来源分别通过 `config.toml`/`--config`/`CORTEX_CONFIG`、`CARGO_PKG_VERSION` 日志输出等本地机制处理。

| 参数名     | 类型   | 默认值              | 访问模式  | 说明                          |
| ---------- | ------ | ------------------- | --------- | ----------------------------- |
| `loglevel` | string | `"info"`            | mandatory | 未实现：未注册 ROS2 parameter |
| `version`  | string | `CARGO_PKG_VERSION` | read_only | 未实现：未注册 ROS2 parameter |
| `config`   | string | `"{}"`              | mandatory | 未实现：未注册 ROS2 parameter |

---

## 消息定义

### AudioCapture

音频采集数据。

| 字段           | 类型                    | 说明             |
| -------------- | ----------------------- | ---------------- |
| `stamps`       | builtin_interfaces/Time | 时间戳           |
| `mic_channels` | uint8                   | 麦克风通道数     |
| `ref_channels` | uint8                   | 回采信号通道数   |
| `info`         | AudioInfo               | 音频格式信息     |
| `data`         | AudioData               | 音频数据         |
| `pkg_name`     | string                  | 可选，发送方来源 |

### AudioInfo

音频格式信息。当前音频订阅链路实际使用 `AudioCapture.mic_channels` / `ref_channels` 和 `data.data` 做转换；`AudioInfo` 中的字段不参与音频数据转换，其中 `sample_rate` / `size` 仅用于日志。

| 字段            | 类型   | 说明                                                       |
| --------------- | ------ | ---------------------------------------------------------- |
| `channels`      | uint8  | 未使用：当前转换使用 `AudioCapture.mic_channels/ref_channels` |
| `sample_rate`   | uint32 | 采样率，单位 Hz；当前仅用于日志                            |
| `size`          | uint32 | 写入大小，单位 byte；当前仅用于日志                        |
| `sample_format` | string | 未使用：当前按 S16_LE PCM 数据处理                         |
| `coding_format` | string | 未使用：当前不按该字段分支处理编码格式                     |

### AudioData

音频数据。

| 字段   | 类型    | 说明     |
| ------ | ------- | -------- |
| `data` | uint8[] | 音频数据 |


### ImageMsg

图像数据。视频订阅链路当前对压缩格式主要按 `data` 魔数嗅探；FaceId service 支持 `encoding=1`/JPEG 魔数的 JPEG，或 `encoding=0` 且 `color_format=6` 的未压缩 I420。当前视频订阅链路实际支持 RGB/BGR/NV12/YUV422/I420；PNG 及其他颜色格式未实现。

| 字段           | 类型    | 说明                                                                                                                                                                                    |
| -------------- | ------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `width`        | uint32  | 图像宽度                                                                                                                                                                                |
| `height`       | uint32  | 图像高度                                                                                                                                                                                |
| `encoding`     | uint8   | 编码格式：UNCOMPRESSED=0, JPEG=1, PNG=2；PNG 未实现；视频订阅链路当前主要按 `data` 魔数嗅探，FaceId service 会读取该字段                                                                |
| `color_format` | uint8   | 颜色格式：RGB=0, BGR=1, RGBA=2, BGRA=3, YUV420=4, YUV422=5, I420=6（当前 SDK 实际映射；历史文档曾写作 YUV444）, NV12=7, NV21=8, GRAY8=9, GRAY16=10, BAYER_RGGB=11, BAYER_BGGR=12, BAYER_GBRG=13, BAYER_GRBG=14, RS2_FORMAT_Z16=15 |
| `bit_depth`    | uint8   | 未使用：当前 SDK 不读取该字段                                                                                                                                                          |
| `data`         | uint8[] | 图像数据                                                                                                                                                                                |
| `size`         | uint64  | 未使用：当前 SDK 以 `data.len()` 为准                                                                                                                                                   |
| `timestamp_ns` | uint64  | 时间戳（纳秒）                                                                                                                                                                          |

### WakeEvent

唤醒事件。

| 字段          | 类型    | 说明                  |
| ------------- | ------- | --------------------- |
| `confidence`  | float32 | 置信度                |
| `status`      | int32   | 状态                  |
| `pinyin`      | string  | 唤醒词拼音            |
| `wakeup_word` | string  | 唤醒词                |
| `event_type`  | string  | 唤醒类型：major/minor |
| `greeting`    | string  | 问候语                |
| `record_id`   | string  | 记录 ID               |
| `doa`         | int32   | 声源方向              |

### DoaMsg

声源方向。

| 字段  | 类型  | 说明         |
| ----- | ----- | ------------ |
| `doa` | int32 | 声源方向角度 |

### AsrResult

语音识别结果。

| 字段        | 类型   | 说明           |
| ----------- | ------ | -------------- |
| `status`    | string | 状态           |
| `text`      | string | 识别文本       |
| `is_final`  | bool   | 是否为最终结果 |
| `record_id` | string | 记录 ID        |

### FaceFeatureArray

多人脸特征结果。

| 字段         | 类型            | 说明             |
| ------------ | --------------- | ---------------- |
| `header`     | std_msgs/Header | ROS 标准头       |
| `face_count` | uint32          | 检测到的人脸数量 |
| `faces`      | FaceFeature[]   | 人脸特征数组     |

### FaceFeature

单人脸特征。

| 字段                             | 类型       | 说明                       |
| -------------------------------- | ---------- | -------------------------- |
| `face_id`                        | int32      | 人脸 ID                    |
| `is_face_detected`               | bool       | 是否检测到人脸             |
| `is_speaking`                    | bool       | 是否在说话                 |
| `face_rectangle`                 | float32[8] | 人脸矩形框                 |
| `head_pitch`                     | float32    | 头部俯仰角                 |
| `head_yaw`                       | float32    | 头部偏航角                 |
| `head_roll`                      | float32    | 头部翻滚角                 |
| `gaze_pitch`                     | float32    | 视线俯仰角                 |
| `gaze_yaw`                       | float32    | 视线偏航角                 |
| `is_gazing`                      | bool       | 是否正在注视               |
| `gaze_score`                     | float32    | 注视置信度，0.0~1.0        |
| `gender`                         | int32      | 性别                       |
| `age`                            | int32      | 年龄                       |
| `expression`                     | int32      | 表情                       |
| `expression_score`               | float32    | 表情置信度                 |
| `mask_score`                     | float32    | 口罩置信度                 |
| `bright`                         | float32    | 亮度                       |
| `mouth_width`                    | float32    | 嘴巴宽度                   |
| `estimate_dist_by_camera`        | float32    | 估计距离                   |
| `estimate_angle_by_camera`       | float32    | 估计角度                   |
| `estimate_head_height_by_camera` | float32    | 估计头部高度               |
| `image_process_time_cost_us`     | int64      | 图像处理耗时，单位 microsec |

### GestureEvent

手势检测事件（LiteHandsWaving 挥手检测）。

| 字段           | 类型    | 说明                         |
| -------------- | ------- | ---------------------------- |
| `class_id`     | int32   | 类别 ID，0=hand              |
| `track_id`     | int32   | 跟踪 ID，-1=未完成跟踪分配   |
| `score`        | float32 | 检测置信度                   |
| `xmin`         | int32   | 手框左上角 x                 |
| `ymin`         | int32   | 手框左上角 y                 |
| `xmax`         | int32   | 手框右下角 x                 |
| `ymax`         | int32   | 手框右下角 y                 |
| `is_waving`    | bool    | 当前是否判定为挥手           |
| `waving_score` | float32 | 挥手分数，0.0~1.0            |
| `waving_count` | int32   | 轨迹窗口内检测到的水平反向数 |

### DmOutput

对话管理输出。

| 字段                 | 类型   | 说明             |
| -------------------- | ------ | ---------------- |
| `record_id`          | string | 记录 ID          |
| `session_id`         | string | 会话 ID          |
| `speak_url`          | string | 语音播报 URL     |
| `should_end_session` | bool   | 是否结束会话     |
| `nlg`                | string | 自然语言生成文本 |
| `input`              | string | 用户输入         |
| `dm_status`          | int32  | 对话管理状态     |
| `task`               | string | 任务名           |
| `intent_name`        | string | 意图名           |
| `command_api`        | string | 命令 API         |
| `command_param_json` | string | 命令参数 JSON    |
| `skill`              | string | 技能名           |
| `skill_id`           | string | 技能 ID          |
| `error_id`           | string | 错误 ID          |
| `error_msg`          | string | 错误信息         |

### AiStatus

状态通知。

| 字段      | 类型   | 说明     |
| --------- | ------ | -------- |
| `source`  | string | 来源     |
| `err_id`  | int32  | 错误码   |
| `err_msg` | string | 错误信息 |

### KwsEvalResult

自定义唤醒词评估异步结果（对应 DuiPlus 事件 `EVENT_MSG_EVALUATE_KWS = 1034`）。

| 字段          | 类型    | 说明                                                        |
| ------------- | ------- | ----------------------------------------------------------- |
| `key_words`   | string  | 对应提交时的拼音                                            |
| `words`       | string  | 未使用：SDK 回调不回传，当前 cortex 发布时留空               |
| `score`       | float32 | SDK 原始评分，量纲由 SDK 决定，不固定为 `[0,1]`              |
| `thresh`      | float32 | SDK 评估阈值，`score >= thresh` 视为通过                    |
| `result`      | string  | SDK 原始 result 字符串：`success` / `fail` / 其他错误描述    |
| `result_code` | int32   | cortex 派生：`success` 或空字符串为 0，其他为 -1             |
| `message`     | string  | 附加说明或错误描述                                          |

### FaceIdResult

FaceId 异步事件消息。当前 SDK 会优先将 REGISTER / RECOGNIZE / COMPARE / QUERY / DELETE / CLEAR 6 个业务命令的回调派发给 `/aisrobot/face_id` service 同步响应；未命中等待者的 FaceId 事件（例如 SDK 自发 NOTIFY、DETECT 或超出同步等待窗口的事件）会发布到 `/aisrobot/face_id/result`。

| 常量                | 值  | 说明                                                       |
| ------------------- | --- | ---------------------------------------------------------- |
| `EVENT_DETECT`      | 0  | Rust 侧常量，来源 SDK event=1156；当前 `.msg` 未声明该常量 |
| `EVENT_REGISTER`    | 1  | 来源 SDK event=1157                                        |
| `EVENT_RECOGNITION` | 2  | 来源 SDK event=1158                                        |
| `EVENT_COMPARE`     | 3  | 来源 SDK event=1159                                        |
| `EVENT_NOTIFY`      | 4  | 来源 SDK event=1160，常规值                                |
| `EVENT_QUERY`       | 5  | 来源 SDK event=1161                                        |
| `EVENT_DELETE`      | 6  | 来源 SDK event=1162                                        |
| `EVENT_CLEAR`       | 7  | 来源 SDK event=1163                                        |

| 字段             | 类型      | 说明                                                       |
| ---------------- | --------- | ---------------------------------------------------------- |
| `event_type`     | uint8     | 事件类型，见上方常量                                       |
| `sdk_event_id`   | int32     | SDK 原始 event ID，1156~1163                               |
| `success`        | bool      | 本次结果是否成功                                           |
| `code`           | int32     | SDK 错误码；0=成功                                         |
| `face_id`        | string    | 身份标识，客户端注册时传入的 UUID，含 `persist.` 前缀表示持久化身份 |
| `score`          | float32   | 相似度/置信度，0.0~1.0；不适用时为 0                       |
| `face_count`     | int32     | 检测到的人脸数量                                           |
| `face_rectangle` | float32[] | 人脸框 `[x1,y1,x2,y2]`；不适用时为空                       |
| `face_id_list`   | string[]  | 已注册的 face_id 列表；不适用时为空                        |
| `result_json`    | string    | SDK 原始 JSON 全文                                         |
| `timestamp_ns`   | uint64    | cortex 侧生成的纳秒时间戳                                  |

---

## 服务定义

服务按“领域”拆分：`Session` 负责 AI 运行域总控，`Wakeup` 负责唤醒域控制，`Dialog` 负责对话业务控制，`Tts` 负责主动播报，`FaceId` 负责人脸识别一次性请求-响应。

### Session

路径：`/aisrobot/session`　·　类型：`ais_node_interface/srv/Session`

AI 运行域总控：AI 能力总开关 + 全局运行期状态切换。

**命令表**

| cmd | 命名         | 入参字段 | 说明                                             |
| --- | ------------ | -------- | ------------------------------------------------ |
| 0   | OPEN_AI      | （无）   | 未实现：当前仅返回成功，不实际启用 SDK 能力       |
| 1   | CLOSE_AI     | （无）   | 未实现：当前仅返回成功，不实际关闭 SDK 能力       |
| 2   | SET_LANGUAGE | `lang`   | 运行期切换语种，影响 ASR / TTS / NLU / 唤醒资源 |

> `OPEN_SESSION=2` / `CLOSE_SESSION=3` 已移除；会话轮次级别起停请使用 `Dialog` 服务的 `START_DIALOG` / `STOP_DIALOG`。

**请求**

| 字段  | 类型   | 使用范围     | 说明                                      |
| ----- | ------ | ------------ | ----------------------------------------- |
| `cmd` | uint8  | 所有         | 命令类型                                  |
| `lang` | string | SET_LANGUAGE | `Chinese` / `English`，大小写敏感；其他命令填空串 |

**响应**

| 字段      | 类型   | 说明                                                        |
| --------- | ------ | ----------------------------------------------------------- |
| `success` | bool   | true=成功；false=失败                                       |
| `code`    | int32  | 0=成功；-1=未知命令；-40=lang 非法；-41=语种切换配置禁用；-42=duiPlus 未启用；-43=SDK 切换失败 |
| `message` | string | 成功描述或错误信息                                          |

### Wakeup

路径：`/aisrobot/wakeup`　·　类型：`ais_node_interface/srv/Wakeup`

唤醒域控制。字段语义随 `cmd` 变化。

**命令表**

| cmd | 命名               | 入参字段                       | 说明                                    |
| --- | ------------------ | ------------------------------ | --------------------------------------- |
| 0   | SET_DOA            | `doa_angle`                    | 设置环 4mic 选区，值只能为 0/90/180/270 |
| 1   | EVAL_KWS           | `key_words` / `words` / `mode` | 自定义唤醒词评估；同步仅返回已受理，评分走 topic `/aisrobot/audio/kws_eval` |
| 2   | RESET_CUSTOM_WKP   | （无）                         | 重置唤醒词为默认配置                    |
| 3   | CHANGE_WAKEUP_WORD | `wakeup_name`                  | 切换唤醒词资源槽                        |

> `CHANGE_WAKEUP_WORD` 因 r2r bindgen 类型编号偏移问题未写成 `.srv` 常量；命令行调用时直接传 `cmd: 3`。

**请求**

| 字段          | 类型   | 使用范围           | 说明                                                                 |
| ------------- | ------ | ------------------ | -------------------------------------------------------------------- |
| `cmd`         | uint8  | 所有               | 命令类型                                                             |
| `doa_angle`   | int32  | SET_DOA            | 0 / 90 / 180 / 270                                                    |
| `key_words`   | string | EVAL_KWS           | 拼音，如 `ni3 hao3 xiao3 chi2`                                       |
| `words`       | string | EVAL_KWS           | 汉字，如 `你好小驰`                                                   |
| `mode`        | uint8  | EVAL_KWS           | 评估模式，默认 0                                                      |
| `wakeup_name` | string | CHANGE_WAKEUP_WORD | 唤醒资源槽名，例如 `xiao_zhi` / `default_av`                          |

**响应**

| 字段      | 类型   | 说明                  |
| --------- | ------ | --------------------- |
| `success` | bool   | true=成功；false=失败 |
| `code`    | int32  | 0=成功；负数为错误码  |
| `message` | string | 成功描述或错误信息    |

### Dialog

路径：`/aisrobot/dialog`　·　类型：`ais_node_interface/srv/Dialog`

对话业务控制。异步 ASR/DM 结果通过 `/aisrobot/audio/asr` 和 `/aisrobot/dm/output` 发布。

**命令表**

| cmd | 命名         | 入参字段                           | 说明                              |
| --- | ------------ | ---------------------------------- | --------------------------------- |
| 0   | START_DIALOG | （无）                             | 主动起一轮对话，跳过唤醒进入倾听  |
| 1   | STOP_DIALOG  | （无）                             | 主动停止当前对话                  |
| 2   | INPUT_TEXT   | `text` / `round_type` / `language` | 直接注入文本触发 NLU/DM，跳过 ASR |

**请求**

| 字段         | 类型   | 使用范围   | 说明                                                    |
| ------------ | ------ | ---------- | ------------------------------------------------------- |
| `cmd`        | uint8  | 所有       | 命令类型                                                |
| `text`       | string | INPUT_TEXT | 注入的文本内容，必填                                    |
| `round_type` | string | INPUT_TEXT | 未使用：当前 SDK 仅记录日志，不下发给 duiPlus             |
| `language`   | string | INPUT_TEXT | 空串=跟随 Session 当前语言；`English`（大小写不敏感）下发英文；其他值按中文空串处理 |

**响应**

| 字段      | 类型   | 说明                                                                        |
| --------- | ------ | --------------------------------------------------------------------------- |
| `success` | bool   | true=成功受理；false=参数/状态错误                                          |
| `code`    | int32  | 0=成功；-1=未知命令；-50=text 为空；-51=SDK 调用失败；-52=duiPlus 未启用    |
| `message` | string | 成功描述或错误信息                                                          |

### Tts

路径：`/aisrobot/tts`　·　类型：`ais_node_interface/srv/Tts`

主动 TTS 播报控制。播报事件 `/aisrobot/audio/player_event` 未实现；当前 SDK 不向 ROS2 转发 TTS 播报事件。

**命令表**

| cmd | 命名  | 入参字段                                                        | 说明         |
| --- | ----- | --------------------------------------------------------------- | ------------ |
| 0   | START | `text` / `voice_id` / `speed` / `volume` / `sample_rate` / `return_url` | 启动主动播报 |
| 1   | STOP  | （无）                                                          | 停止当前播报 |

**请求**

| 字段          | 类型   | 使用范围 | 说明                                                     |
| ------------- | ------ | -------- | -------------------------------------------------------- |
| `cmd`         | uint8  | 所有     | 命令类型                                                 |
| `text`        | string | START    | 待播报文本，必填                                         |
| `voice_id`    | string | START    | 空串=使用 `config.toml` 默认 voice_id                    |
| `speed`       | int32  | START    | 0=使用默认；非 0 直接下发（当前 SDK 不校验范围）          |
| `volume`      | int32  | START    | 0=使用默认；非 0 直接下发（当前 SDK 不校验范围）          |
| `sample_rate` | int32  | START    | 未使用：当前读取请求/默认值，但未写入 `duiPlusSpeak` 参数 |
| `return_url`  | bool   | START    | true=SDK 返回 URL 不下音频流，对应 `returnUrl` 参数       |

**响应**

| 字段      | 类型   | 说明                                                                     |
| --------- | ------ | ------------------------------------------------------------------------ |
| `success` | bool   | true=成功受理；false=参数/状态错误                                       |
| `code`    | int32  | 0=成功；-1=未知命令；-60=text 为空；-61=SDK 调用失败；-62=duiPlus 未启用 |
| `message` | string | 成功描述或错误信息                                                       |

### FaceId

路径：`/aisrobot/face_id`　·　类型：`ais_node_interface/srv/FaceId`

人脸识别一次性请求-响应。REGISTER / RECOGNIZE / COMPARE 请求携带图像并等待 SDK 回调后同步返回业务结果；QUERY / DELETE / CLEAR 为轻量命令。FaceId 回调优先由 service 等待者消费，未命中等待者的事件通过 `/aisrobot/face_id/result` 异步上报。

**命令表**

| cmd | 命名      | 入参字段              | 说明                                      |
| --- | --------- | --------------------- | ----------------------------------------- |
| 0   | REGISTER  | `face_id` / `image`   | 注册：建立 face_id(UUID) 与特征映射       |
| 1   | RECOGNIZE | `image`               | 识别：匹配已注册库，返回 face_id 和相似度 |
| 2   | COMPARE   | `image` / `image_b`   | 比对：两张图相似度                        |
| 3   | QUERY     | （无）                | 查询已注册 face_id 列表                   |
| 4   | DELETE    | `face_id`             | 删除指定身份                              |
| 5   | CLEAR     | （无）                | 清空已注册身份                            |

> `.srv` 内仅定义 `REGISTER=0`、`RECOGNIZE=1`、`COMPARE=2` 常量；`QUERY=3`、`DELETE=4`、`CLEAR=5` 在 Rust 侧常量化。

**请求**

| 字段      | 类型     | 使用范围                         | 说明                                                        |
| --------- | -------- | -------------------------------- | ----------------------------------------------------------- |
| `cmd`     | uint8    | 所有                             | 命令类型                                                    |
| `face_id` | string   | REGISTER / DELETE                | REGISTER 为客户端生成的 UUID；DELETE 建议传 `face_id_out`   |
| `image`   | ImageMsg | REGISTER / RECOGNIZE / COMPARE   | 主图，JPEG 或 I420 编码；QUERY / DELETE / CLEAR 忽略        |
| `image_b` | ImageMsg | COMPARE                          | 第二张图；其他命令忽略                                      |

**响应**

| 字段           | 类型     | 使用范围                    | 说明                                                        |
| -------------- | -------- | --------------------------- | ----------------------------------------------------------- |
| `success`      | bool     | 所有                        | true=业务成功；false=参数/状态/SDK 错误                     |
| `code`         | int32    | 所有                        | 0=成功；负数为错误码                                        |
| `message`      | string   | 所有                        | 成功描述或错误信息                                          |
| `face_id_out`  | string   | REGISTER / RECOGNIZE / DELETE | SDK 实际存储或匹配到的 face_id，持久化时可能含 `persist.` 前缀 |
| `score`        | float32  | RECOGNIZE / COMPARE         | 相似度，0.0~1.0                                             |
| `face_count`   | int32    | REGISTER / RECOGNIZE        | SDK 检测到的人脸数量                                        |
| `face_id_list` | string[] | QUERY                       | 已注册的 face_id 列表                                       |
| `result_json`  | string   | 所有                        | SDK 原始 JSON 全文                                          |

**错误码**

| code | 含义                                                     |
| ---- | -------------------------------------------------------- |
| `0`  | 成功                                                     |
| `-1` | 未知 cmd                                                 |
| `-80` | duiPlus engine 未启用 / face_id index 未创建            |
| `-81` | SDK 调用失败                                             |
| `-82` | REGISTER 缺 face_id                                      |
| `-83` | DELETE 缺 face_id                                        |
| `-85` | 图像解码失败                                             |
| `-86` | 缺必填图像                                               |
| `-87` | SDK 回调超时                                             |
| `-88` | 等待者被覆盖 / 等待者被取消                              |
