#!/bin/bash
source /opt/ros/humble/setup.bash
export ROS_DOMAIN_ID=0
export FASTRTPS_DEFAULT_PROFILES_FILE=/tmp/fastdds_eth1.xml
echo "--- pub final-check-A ---"
timeout 6 ros2 topic pub -1 /android/command std_msgs/msg/String "{data: 'final-check-A'}" 2>&1 | tail -3
sleep 3
echo "--- echo status ---"
timeout 12 ros2 topic echo --no-daemon --spin-time 10 --once /android/status 2>&1 | tail -3
