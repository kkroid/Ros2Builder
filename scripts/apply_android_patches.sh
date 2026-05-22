#!/usr/bin/env bash
set -euo pipefail

workspace="${WORKSPACE_DIR:-/work}"
filewatch_header="${workspace}/src/eProsima/Fast-DDS/thirdparty/filewatch/FileWatch.hpp"
register_py_cmake="${workspace}/src/ros2/rosidl_python/rosidl_generator_py/cmake/register_py.cmake"

if [[ ! -f "${filewatch_header}" ]]; then
  echo "Skipping Fast-DDS filewatch patch; header not found: ${filewatch_header}"
elif grep -q 'duration_cast<std::chrono::system_clock::duration>(std::chrono::nanoseconds(result.st_mtim.tv_nsec))' "${filewatch_header}"; then
  echo "Fast-DDS filewatch Android chrono patch already applied"
else
  echo "Applying Fast-DDS filewatch Android chrono patch"
  perl -0pi -e 's/current_time \+= std::chrono::nanoseconds\(result\.st_mtim\.tv_nsec\);/current_time += std::chrono::duration_cast<std::chrono::system_clock::duration>(std::chrono::nanoseconds(result.st_mtim.tv_nsec));/' "${filewatch_header}"
  perl -0pi -e 's/last_write_time_ \+= std::chrono::nanoseconds\(result\.st_mtim\.tv_nsec\);/last_write_time_ += std::chrono::duration_cast<std::chrono::system_clock::duration>(std::chrono::nanoseconds(result.st_mtim.tv_nsec));/' "${filewatch_header}"

  if ! grep -q 'duration_cast<std::chrono::system_clock::duration>(std::chrono::nanoseconds(result.st_mtim.tv_nsec))' "${filewatch_header}"; then
    echo "Failed to apply Fast-DDS filewatch Android chrono patch" >&2
    exit 2
  fi
fi

if [[ ! -f "${register_py_cmake}" ]]; then
  echo "Skipping rosidl_generator_py Android patch; file not found: ${register_py_cmake}"
  exit 0
fi

if grep -q 'ROSIDL_GENERATOR_PY_DISABLE' "${register_py_cmake}"; then
  echo "rosidl_generator_py Android disable patch already applied"
  exit 0
fi

echo "Applying rosidl_generator_py Android disable patch"
perl -0pi -e 's/  ament_register_extension\(\n    "rosidl_generate_idl_interfaces"\n    "rosidl_generator_py"\n    "rosidl_generator_py_generate_interfaces\.cmake"\)/  if(NOT ROSIDL_GENERATOR_PY_DISABLE)\n    ament_register_extension(\n      "rosidl_generate_idl_interfaces"\n      "rosidl_generator_py"\n      "rosidl_generator_py_generate_interfaces.cmake")\n  endif()/s' "${register_py_cmake}"

if ! grep -q 'ROSIDL_GENERATOR_PY_DISABLE' "${register_py_cmake}"; then
  echo "Failed to apply rosidl_generator_py Android disable patch" >&2
  exit 2
fi