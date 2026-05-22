#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "${script_dir}/.." && pwd)"
artifact_root="${1:-$(cd "${project_root}/../.." && pwd)/work/dist/android_arm64-v8a}"

source_jni_libs="${artifact_root}/jniLibs/arm64-v8a"
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
target_include="${project_root}/app/src/main/ros2/include"
target_manifest="${project_root}/app/src/main/assets/ros2-manifest"

rm -rf "${target_jni_libs}" "${target_include}" "${target_manifest}"
mkdir -p "${target_jni_libs}" "${target_include}" "${target_manifest}"

cp -R "${source_jni_libs}/." "${target_jni_libs}/"
cp -R "${source_include}/." "${target_include}/"
if [[ -d "${source_manifest}" ]]; then
  cp -R "${source_manifest}/." "${target_manifest}/"
fi

so_count="$(find "${target_jni_libs}" -type f -name '*.so*' | wc -l)"
header_count="$(find "${target_include}" -type f | wc -l)"

echo "Copied ROS 2 artifacts from ${artifact_root}"
echo "Shared libraries: ${so_count}"
echo "Header files: ${header_count}"