# 手势检测事件（LiteHandsWaving 挥手检测）
# 对应 SDK HandDetectInfo 结构体
int32   class_id        # 类别 ID（0=hand）
int32   track_id        # 跟踪 ID（-1=未完成跟踪分配）
float32 score           # 检测置信度
int32   xmin            # 手框左上角 x
int32   ymin            # 手框左上角 y
int32   xmax            # 手框右下角 x
int32   ymax            # 手框右下角 y
bool    is_waving       # 当前是否判定为挥手
float32 waving_score    # 挥手分数（0.0~1.0）
int32   waving_count    # 轨迹窗口内检测到的水平反向次数
