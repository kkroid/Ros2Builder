#!/usr/bin/env bash
set -euo pipefail

workspace="${WORKSPACE_DIR:-/work}"

# -------------------------------------------------------------------------
# Copy local packages (not from git) into the colcon workspace.
# Add new local packages here as needed.
# -------------------------------------------------------------------------
local_packages_dir="/opt/packages"
if [[ -d "${local_packages_dir}" ]]; then
  for pkg in "${local_packages_dir}"/*/; do
    pkg_name="$(basename "${pkg}")"
    pkg_dst="${workspace}/src/${pkg_name}"
    if [[ ! -d "${pkg_dst}" ]]; then
      echo "Installing local package: ${pkg_name}"
      cp -a "${pkg}" "${pkg_dst}"
    else
      echo "Local package already present: ${pkg_name}"
    fi
  done
fi

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
elif grep -q 'ROSIDL_GENERATOR_PY_DISABLE' "${register_py_cmake}"; then
  echo "rosidl_generator_py Android disable patch already applied"
fi

echo "Applying rosidl_generator_py Android disable patch"
perl -0pi -e 's/  ament_register_extension\(\n    "rosidl_generate_idl_interfaces"\n    "rosidl_generator_py"\n    "rosidl_generator_py_generate_interfaces\.cmake"\)/  if(NOT ROSIDL_GENERATOR_PY_DISABLE)\n    ament_register_extension(\n      "rosidl_generate_idl_interfaces"\n      "rosidl_generator_py"\n      "rosidl_generator_py_generate_interfaces.cmake")\n  endif()/s' "${register_py_cmake}"

if ! grep -q 'ROSIDL_GENERATOR_PY_DISABLE' "${register_py_cmake}"; then
  echo "Failed to apply rosidl_generator_py Android disable patch" >&2
  exit 2
fi

# -------------------------------------------------------------------------
# Patch 3: rmw_dds_common — force static when BUILD_SHARED_LIBS=OFF
# -------------------------------------------------------------------------
rmw_dds_common_cmake="${workspace}/src/ros2/rmw_dds_common/rmw_dds_common/CMakeLists.txt"

if [[ ! -f "${rmw_dds_common_cmake}" ]]; then
  echo "Skipping rmw_dds_common static patch; file not found: ${rmw_dds_common_cmake}"
elif grep -q 'add_library(${PROJECT_NAME}_library' "${rmw_dds_common_cmake}" && \
     ! grep -q 'add_library(${PROJECT_NAME}_library SHARED' "${rmw_dds_common_cmake}"; then
  echo "rmw_dds_common static patch already applied"
else
  echo "Applying rmw_dds_common static patch (remove forced SHARED)"
  perl -pi -e 's/add_library\(\$\{PROJECT_NAME\}_library SHARED/add_library(\$\{PROJECT_NAME\}_library/' "${rmw_dds_common_cmake}"
  if grep -q 'add_library(${PROJECT_NAME}_library SHARED' "${rmw_dds_common_cmake}"; then
    echo "Failed to apply rmw_dds_common static patch" >&2
    exit 2
  fi
fi

# -------------------------------------------------------------------------
# Patch 4: rosidl_typesupport_fastrtps_cpp — force static when BUILD_SHARED_LIBS=OFF
# -------------------------------------------------------------------------
rosidl_ts_cmake="${workspace}/src/ros2/rosidl_typesupport_fastrtps/rosidl_typesupport_fastrtps_cpp/CMakeLists.txt"

if [[ ! -f "${rosidl_ts_cmake}" ]]; then
  echo "Skipping rosidl_typesupport_fastrtps_cpp static patch; file not found: ${rosidl_ts_cmake}"
elif grep -q 'add_library(${PROJECT_NAME}' "${rosidl_ts_cmake}" && \
     ! grep -q 'add_library(${PROJECT_NAME} SHARED' "${rosidl_ts_cmake}"; then
  echo "rosidl_typesupport_fastrtps_cpp static patch already applied"
else
  echo "Applying rosidl_typesupport_fastrtps_cpp static patch (remove forced SHARED)"
  perl -pi -e 's/add_library\(\$\{PROJECT_NAME\} SHARED/add_library(\$\{PROJECT_NAME\}/' "${rosidl_ts_cmake}"
  if grep -q 'add_library(${PROJECT_NAME} SHARED' "${rosidl_ts_cmake}"; then
    echo "Failed to apply rosidl_typesupport_fastrtps_cpp static patch" >&2
    exit 2
  fi
fi

# -------------------------------------------------------------------------
# Patch 5: libyaml_vendor — force bundled libyaml static + export YAML_DECLARE_STATIC
# libyaml_vendor hard-codes -DBUILD_SHARED_LIBS=ON for its bundled libyaml
# ExternalProject, so it always emits a shared yaml even in an otherwise static
# build. Force it static and export YAML_DECLARE_STATIC so consumers
# (rcl_yaml_param_parser) compile yaml.h as plain declarations. On non-Windows
# YAML_DECLARE_STATIC is a harmless no-op.
# -------------------------------------------------------------------------
libyaml_cmake="${workspace}/src/ros2/libyaml_vendor/CMakeLists.txt"

if [[ ! -f "${libyaml_cmake}" ]]; then
  echo "Skipping libyaml_vendor static patch; file not found: ${libyaml_cmake}"
else
  if grep -q 'BUILD_SHARED_LIBS=ON' "${libyaml_cmake}"; then
    echo "Applying libyaml_vendor static patch (force bundled libyaml static)"
    perl -pi -e 's/-DBUILD_SHARED_LIBS=ON/-DBUILD_SHARED_LIBS=OFF/' "${libyaml_cmake}"
  else
    echo "libyaml_vendor bundled libyaml already static"
  fi
  if ! grep -q 'ament_export_definitions(YAML_DECLARE_STATIC)' "${libyaml_cmake}"; then
    echo "Applying libyaml_vendor YAML_DECLARE_STATIC export patch"
    perl -0pi -e 's/ament_export_libraries\(yaml\)/ament_export_libraries(yaml)\nament_export_definitions(YAML_DECLARE_STATIC)/' "${libyaml_cmake}"
  else
    echo "libyaml_vendor YAML_DECLARE_STATIC export already applied"
  fi
  if grep -q 'BUILD_SHARED_LIBS=ON' "${libyaml_cmake}"; then
    echo "Failed to apply libyaml_vendor static patch" >&2
    exit 2
  fi
fi

# -------------------------------------------------------------------------
# Patch 6: spdlog_vendor — remove forced SPDLOG_BUILD_SHARED=ON for non-Windows.
# spdlog_vendor hard-codes -DSPDLOG_BUILD_SHARED=ON for !WIN32, which overrides
# BUILD_SHARED_LIBS=OFF. Remove the forced setting so spdlog is built static.
# -------------------------------------------------------------------------
spdlog_cmake="${workspace}/src/ros2/spdlog_vendor/CMakeLists.txt"

if [[ ! -f "${spdlog_cmake}" ]]; then
  echo "Skipping spdlog_vendor static patch; file not found: ${spdlog_cmake}"
elif grep -q 'SPDLOG_BUILD_SHARED=ON' "${spdlog_cmake}"; then
  echo "Applying spdlog_vendor static patch (remove forced SPDLOG_BUILD_SHARED=ON)"
  perl -pi -e 's/-DSPDLOG_BUILD_SHARED=ON/-DSPDLOG_BUILD_SHARED=OFF/' "${spdlog_cmake}"
  if grep -q 'SPDLOG_BUILD_SHARED=ON' "${spdlog_cmake}"; then
    echo "Failed to apply spdlog_vendor static patch" >&2
    exit 2
  fi
else
  echo "spdlog_vendor already static"
fi

# -------------------------------------------------------------------------
# Patch 7: CycloneDDS — always define dummy security_core INTERFACE target
# When ENABLE_SECURITY=OFF, security_core is never defined but the cmake
# install(EXPORT CycloneDDS) for ddsc may still reference it, causing:
#   CMake Error: install(EXPORT "CycloneDDS" ...) includes target "ddsc"
#   which requires target "security_core" that is not in any export set.
# Workaround: always create a dummy INTERFACE library for security_core.
# -------------------------------------------------------------------------
cyclonedds_security_cmake="${workspace}/src/eclipse-cyclonedds/cyclonedds/src/security/CMakeLists.txt"

if [[ ! -f "${cyclonedds_security_cmake}" ]]; then
  echo "Skipping CycloneDDS security_core patch; file not found: ${cyclonedds_security_cmake}"
elif grep -q 'CYCLONEDDS_ANDROID_SECURITY_DUMMY' "${cyclonedds_security_cmake}"; then
  echo "CycloneDDS security_core dummy patch already applied"
else
  echo "Applying CycloneDDS security_core dummy patch (ensure security_core exists when ENABLE_SECURITY=OFF)"
  cat >> "${cyclonedds_security_cmake}" << 'CDDSEOF'

# Android patch: ensure security_core target always exists so the
# install(EXPORT CycloneDDS) does not fail when ENABLE_SECURITY=OFF.
# CYCLONEDDS_ANDROID_SECURITY_DUMMY — do not remove this marker.
if(NOT ENABLE_SECURITY)
  add_library(security_core INTERFACE)
endif()
CDDSEOF
  if ! grep -q 'CYCLONEDDS_ANDROID_SECURITY_DUMMY' "${cyclonedds_security_cmake}"; then
    echo "Failed to apply CycloneDDS security_core dummy patch" >&2
    exit 2
  fi
fi