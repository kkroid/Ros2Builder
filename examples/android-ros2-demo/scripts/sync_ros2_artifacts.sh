#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "${script_dir}/.." && pwd)"
artifact_root="${1:-$(cd "${project_root}/../.." && pwd)/work/dist/android_arm64-v8a_static_dynamic}"

source_jni_libs="${artifact_root}/jniLibs/arm64-v8a"
source_lib="${artifact_root}/lib"
source_include="${artifact_root}/include"
source_manifest="${artifact_root}/manifest"

if [[ ! -d "${source_jni_libs}" ]]; then
  echo "Missing ROS 2 jniLibs directory: ${source_jni_libs}" >&2
  exit 2
fi
if [[ ! -d "${source_include}" ]]; then
  echo "Missing ROS 2 include directory: ${source_include}" >&2
  exit 2
fi

target_jni_libs="${project_root}/app/src/main/jniLibs/arm64-v8a"
target_lib="${project_root}/app/src/main/ros2/lib/arm64-v8a"
target_include="${project_root}/app/src/main/ros2/include"
target_manifest="${project_root}/app/src/main/assets/ros2-manifest"

rm -rf "${target_jni_libs}" "${target_lib}" "${target_include}" "${target_manifest}"
mkdir -p "${target_jni_libs}" "${target_lib}" "${target_include}" "${target_manifest}"

# Packages/libs not required by the audio demo. Keep in sync with sync_ros2_artifacts.ps1
# and the EXCLUDE regex in app/src/main/cpp/CMakeLists.txt.
skip_static=(
  'librmw_fastrtps_cpp.a'
  'libaction_msgs__*.a'
  'libunique_identifier_msgs__*.a'
  'libtest_msgs__*.a'
  'librcl_logging_spdlog.a'
)
skip_include_dirs=(
  'action_msgs'
  'unique_identifier_msgs'
  'test_msgs'
  'spdlog'
)
skip_jni_libs=(
  'libspdlog.so'
)

for f in "${source_jni_libs}"/*; do
  [[ -f "$f" ]] || continue
  name="$(basename "$f")"
  skip=0
  for s in "${skip_jni_libs[@]}"; do
    if [[ "${name}" == "${s}" ]]; then
      skip=1
      break
    fi
  done
  if [[ ${skip} -eq 0 ]]; then
    cp "$f" "${target_jni_libs}/"
  fi
done
if [[ -d "${source_lib}" ]]; then
  while IFS= read -r -d '' f; do
    name="$(basename "$f")"
    skip=0
    for pat in "${skip_static[@]}"; do
      # shellcheck disable=SC2053
      if [[ "${name}" == ${pat} ]]; then
        skip=1
        break
      fi
    done
    if [[ ${skip} -eq 0 ]]; then
      cp "${f}" "${target_lib}/"
    fi
  done < <(find "${source_lib}" -maxdepth 1 -type f -name '*.a' -print0)
fi
for entry in "${source_include}"/* "${source_include}"/.[!.]*; do
  [[ -e "${entry}" ]] || continue
  name="$(basename "${entry}")"
  if [[ -d "${entry}" ]]; then
    skip=0
    for s in "${skip_include_dirs[@]}"; do
      if [[ "${name}" == "${s}" ]]; then
        skip=1
        break
      fi
    done
    if [[ ${skip} -eq 0 ]]; then
      cp -R "${entry}" "${target_include}/"
    fi
  else
    cp "${entry}" "${target_include}/"
  fi
done
if [[ -d "${source_manifest}" ]]; then
  cp -R "${source_manifest}/." "${target_manifest}/"
fi

so_count="$(find "${target_jni_libs}" -type f -name '*.so*' | wc -l)"
static_count="$(find "${target_lib}" -type f -name '*.a' | wc -l)"
header_count="$(find "${target_include}" -type f | wc -l)"

echo "Copied ROS 2 artifacts from ${artifact_root}"
echo "Shared libraries: ${so_count}"
echo "Static libraries: ${static_count}"
echo "Header files: ${header_count}"