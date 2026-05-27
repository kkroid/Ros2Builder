#!/bin/bash
source /opt/ros/humble/setup.bash
export ROS_DOMAIN_ID=0
export FASTRTPS_DEFAULT_PROFILES_FILE=/tmp/fastdds_eth1.xml

echo "=== §2.1 status echo (3 messages) ==="
timeout 12 ros2 topic echo --no-daemon --spin-time 10 --once /android/status
echo ""
echo "=== §2.1 status hz (10s window) ==="
timeout 15 ros2 topic hz --no-daemon /android/status &
HZ_PID=$!
sleep 12
kill $HZ_PID 2>/dev/null
wait $HZ_PID 2>/dev/null
