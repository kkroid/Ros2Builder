#!/usr/bin/env bash
set -euo pipefail

set +u
source /opt/ros/humble/setup.bash
set -u
export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-0}"
export RMW_IMPLEMENTATION="${RMW_IMPLEMENTATION:-rmw_fastrtps_cpp}"
export WSL_DEMO_QOS="${WSL_DEMO_QOS:-best_effort}"

exec python3 "$(dirname "$0")/peer_node.py"