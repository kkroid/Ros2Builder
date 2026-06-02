int32   face_id
bool    is_face_detected
bool    is_speaking
float32[8] face_rectangle
float32 head_pitch
float32 head_yaw
float32 head_roll
float32 gaze_pitch
float32 gaze_yaw
bool    is_gazing                        # 是否正在注视（注视角度在阈值内）
float32 gaze_score                       # 注视置信度 0.0~1.0
int32   gender
int32   age
int32   expression
float32 expression_score
float32 mask_score
float32 bright
float32 mouth_width
float32 estimate_dist_by_camera
float32 estimate_angle_by_camera
float32 estimate_head_height_by_camera
int64   image_process_time_cost_us
