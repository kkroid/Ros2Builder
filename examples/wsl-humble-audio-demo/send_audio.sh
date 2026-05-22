#!/usr/bin/env bash
set -euo pipefail

set +u
source /opt/ros/humble/setup.bash
set -u
export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-0}"
export RMW_IMPLEMENTATION="${RMW_IMPLEMENTATION:-rmw_fastrtps_cpp}"
export PULSE_SOURCE="${PULSE_SOURCE:-RDPSource}"

exec python3 "$(dirname "$0")/send_audio.py" "$@"