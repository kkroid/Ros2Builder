# ais_msgs/msg/ImageMsg.msg
uint32 width
uint32 height

uint8 UNCOMPRESSED=0
uint8 JPEG=1
uint8 PNG=2
uint8 encoding

uint8 RGB=0
uint8 BGR=1
uint8 RGBA=2
uint8 BGRA=3
uint8 YUV420=4
uint8 YUV422=5
uint8 YUV444=6
uint8 NV12=7
uint8 NV21=8
uint8 GRAY8=9
uint8 GRAY16=10
uint8 BAYER_RGGB=11
uint8 BAYER_BGGR=12
uint8 BAYER_GBRG=13
uint8 BAYER_GRBG=14
uint8 RS2_FORMAT_Z16=15
uint8 color_format

uint8  bit_depth
uint8[] data
uint64 size
uint64 timestamp_ns
