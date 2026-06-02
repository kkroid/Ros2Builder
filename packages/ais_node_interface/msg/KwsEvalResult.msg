# 自定义唤醒词评估（EVAL_KWS）异步结果
# 来源：DuiPlus 事件 EVENT_MSG_EVALUATE_KWS = 1034
# Topic：/aisrobot/audio/kws_eval
# SDK 原始 JSON：{"result":"success","keyWords":"...","score":10,"thresh":0.127297}
string  key_words      # 对应提交时的拼音
string  words          # 对应提交时的汉字（SDK 不回传，需要时由 cortex 注入，目前留空）
float32 score          # SDK 原始评分（量纲由 SDK 决定，而非固定 [0,1]）
float32 thresh         # SDK 评估阈值（score >= thresh 视为通过）
string  result         # SDK 原始 result 字符串："success" / "fail" / 其他错误描述
int32   result_code    # cortex 派生："success"→0，其他→-1（便于客户端快速判成败）
string  message        # 附加说明或错误描述
