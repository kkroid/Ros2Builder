#!/usr/bin/env bash
set -euo pipefail

if [[ -f /opt/ros/humble/setup.bash ]]; then
  set +u
  source /opt/ros/humble/setup.bash
  set -u
fi

echo "ROS_DISTRO=${ROS_DISTRO:-unset}"
echo "PULSE_SERVER=${PULSE_SERVER:-unset}"
echo "PulseAudio sources:"
pactl list short sources

source_name="${PULSE_SOURCE:-RDPSource}"
output_path="${1:-/tmp/wsl_humble_audio_check.raw}"
timeout 2s parec --device="${source_name}" --format=s16le --rate=16000 --channels=1 >"${output_path}" || true
wc -c "${output_path}"