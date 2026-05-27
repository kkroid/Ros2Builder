#!/bin/bash
source /opt/ros/humble/setup.bash
export ROS_DOMAIN_ID=0
export FASTRTPS_DEFAULT_PROFILES_FILE=/tmp/fastdds_eth1.xml

pkill -9 -f _ros2_daemon 2>/dev/null
sleep 1
echo "=== start daemon ==="
ros2 daemon start
sleep 3
echo "=== node list (via daemon) ==="
timeout 15 ros2 node list
echo "=== topic list (via daemon) ==="
timeout 10 ros2 topic list
echo "=== §2.1 hz over 10s ==="
timeout 12 ros2 topic hz /android/status
echo "exit=$?"
