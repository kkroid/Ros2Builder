#!/bin/bash
source /opt/ros/humble/setup.bash
export ROS_DOMAIN_ID=0
export FASTRTPS_DEFAULT_PROFILES_FILE=/tmp/fastdds_eth1.xml

echo "=== §2.2 baseline status (before pub) ==="
timeout 5 ros2 topic echo --once /android/status

echo ""
echo "=== §2.2 single pub ping-1 ==="
timeout 5 ros2 topic pub --once /android/command std_msgs/msg/String "{data: 'ping-1'}"
sleep 2
echo "=== status after ping-1 ==="
timeout 5 ros2 topic echo --once /android/status

echo ""
echo "=== §2.2 burst pub ping-1..5 ==="
for i in 1 2 3 4 5; do
    timeout 4 ros2 topic pub --once /android/command std_msgs/msg/String "{data: \"ping-$i\"}"
done
sleep 2
echo "=== status after burst ==="
timeout 5 ros2 topic echo --once /android/status
