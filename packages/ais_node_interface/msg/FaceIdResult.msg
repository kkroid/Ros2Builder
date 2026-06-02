# FaceId 异步通知消息（仅用于 SDK 自发 NOTIFY）
# Topic: /aisrobot/face_id/result
#
# v2.5.0 设计收窄：
#   REGISTER / RECOGNIZE / COMPARE / QUERY / DELETE / CLEAR 6 个业务命令均走
#   service call 同步返回业务结果，**不再走此 topic**。
#   本 topic 仅承载 SDK 自发的 NOTIFY 状态/错误通知（EVENT_NOTIFY）。
#
# 来源：DuiPlus LiteFaceId SDK event=1160 (LiteFaceIdNotify)。
# 其余 6 个事件 1157~1159 / 1161~1163 由 service handler 内部等待消费，不进入本 topic。

# 事件类型常量（与 protocol/event.rs FACE_ID_EVENT_* 对齐；保留全量便于排障）
uint8 EVENT_REGISTER=1      # 来源 SDK event=1157 —— 正常情况不出现（service 消费）
uint8 EVENT_RECOGNITION=2   # 来源 SDK event=1158 —— 正常情况不出现
uint8 EVENT_COMPARE=3       # 来源 SDK event=1159 —— 正常情况不出现
uint8 EVENT_NOTIFY=4        # 来源 SDK event=1160（状态/错误通知，本 topic 常规值）
uint8 EVENT_QUERY=5         # 来源 SDK event=1161 —— 正常情况不出现
uint8 EVENT_DELETE=6        # 来源 SDK event=1162 —— 正常情况不出现
uint8 EVENT_CLEAR=7         # 来源 SDK event=1163 —— 正常情况不出现

uint8   event_type          # 事件类型，见上常量
int32   sdk_event_id        # SDK 原始 event ID（1157~1163），便于排障
bool    success             # 本次结果是否成功（从 SDK JSON error/errorCode 字段提取）
int32   code                # SDK 错误码；0=成功

# —— 业务结果字段（NOTIFY 场景多数为空；保留用于未来扩展与排障） ——
string  face_id             # 身份标识（客户端注册时传入的 UUID，含 persist. 前缀时表示持久化身份）
float32 score               # 相似度/置信度（0.0~1.0；不适用时为 0）
int32   face_count          # 检测到的人脸数量
float32[] face_rectangle    # 人脸框 [x1,y1,x2,y2]（4 个 float）；不适用时为空
string[] face_id_list       # 已注册的 face_id(UUID) 列表（不适用时为空）

# SDK 原始 JSON 全文，兼容后续字段扩展；调用方可按需再解析
string  result_json

uint64  timestamp_ns        # cortex 侧生成的纳秒时间戳
