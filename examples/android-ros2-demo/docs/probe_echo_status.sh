#!/bin/bash
source /opt/ros/humble/setup.bash
export ROS_DOMAIN_ID=0
export FASTRTPS_DEFAULT_PROFILES_FILE=/tmp/fastdds_eth1.xml
timeout 12 ros2 topic echo --no-daemon --spin-time 10 --once /android/status 2>&1 | tail -20
