#!/bin/bash
source /opt/ros/humble/setup.bash
pkill -9 -f _ros2_daemon 2>/dev/null
sleep 1
export ROS_DOMAIN_ID=0
export FASTRTPS_DEFAULT_PROFILES_FILE=/tmp/fastdds_eth1.xml
echo "PROFILES=$FASTRTPS_DEFAULT_PROFILES_FILE"
echo "RMW=${RMW_IMPLEMENTATION:-default(fastrtps_cpp)}"
echo "--- node list (no daemon, 10s spin) ---"
timeout 15 ros2 node list --no-daemon --spin-time 10
echo "node_exit=$?"
echo "--- topic list ---"
timeout 10 ros2 topic list --no-daemon --spin-time 8
echo "topic_exit=$?"
