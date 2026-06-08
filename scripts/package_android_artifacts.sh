#!/usr/bin/env bash
set -euo pipefail

workspace="${WORKSPACE_DIR:-/work}"
android_abi="${ANDROID_ABI:-arm64-v8a}"
android_stl="${ANDROID_STL:-c++_shared}"
ndk_home="${ANDROID_NDK_HOME:-/opt/android-ndk-cache/android-ndk-r25b-linux}"
build_output_suffix="${BUILD_OUTPUT_SUFFIX:-}"
build_label="android_${android_abi}"
if [[ -n "${build_output_suffix}" ]]; then
  build_label="${build_label}_${build_output_suffix}"
fi
install_prefix="${ANDROID_INSTALL_PREFIX:-${workspace}/install/${build_label}}"
artifact_root="${ARTIFACT_DIR:-${workspace}/dist/${build_label}}"
clean_artifact_dir="${ARTIFACT_CLEAN:-ON}"
copy_jni_libs="${ARTIFACT_WITH_JNILIBS:-ON}"
checksum_manifest="${ARTIFACT_CHECKSUMS:-OFF}"
copy_metadata="${ARTIFACT_WITH_METADATA:-OFF}"

copy_dir_contents() {
  local source_dir="$1"
  local target_dir="$2"

  if [[ -d "${source_dir}" ]]; then
    mkdir -p "${target_dir}"
    cp -R --no-preserve=mode,ownership,timestamps "${source_dir}/." "${target_dir}/"
  fi
}

copy_file() {
  local source_file="$1"
  local target_dir="$2"

  mkdir -p "${target_dir}"
  cp --no-preserve=mode,ownership,timestamps "${source_file}" "${target_dir}/"
}

should_copy_shared_lib() {
  local source_file="$1"
  local name

  if [[ "${BUILD_SHARED_LIBS:-ON}" != "OFF" ]]; then
    return 0
  fi

  name="$(basename "${source_file}")"
  case "${name}" in
    *)
      return 1
      ;;
  esac
}

existing_manifest_roots() {
  local root

  for root in include lib jniLibs share cmake manifest; do
    if [[ -e "${root}" ]]; then
      printf '%s\0' "${root}"
    fi
  done
}

if [[ ! -d "${install_prefix}" ]]; then
  echo "Missing Android install tree: ${install_prefix}" >&2
  echo "Run: docker compose run --rm android-build" >&2
  exit 2
fi

if [[ "${clean_artifact_dir}" == "ON" ]]; then
  rm -rf "${artifact_root}"
fi

mkdir -p \
  "${artifact_root}/include" \
  "${artifact_root}/lib" \
  "${artifact_root}/manifest"

copy_dir_contents "${install_prefix}/include" "${artifact_root}/include"
if [[ "${copy_metadata}" == "ON" ]]; then
  mkdir -p "${artifact_root}/share" "${artifact_root}/cmake"
  copy_dir_contents "${install_prefix}/share" "${artifact_root}/share"
  copy_dir_contents "${install_prefix}/cmake" "${artifact_root}/cmake"

  if [[ -d "${install_prefix}/lib/cmake" ]]; then
    copy_dir_contents "${install_prefix}/lib/cmake" "${artifact_root}/lib/cmake"
  fi

  if [[ -d "${install_prefix}/lib/pkgconfig" ]]; then
    copy_dir_contents "${install_prefix}/lib/pkgconfig" "${artifact_root}/lib/pkgconfig"
  fi
fi

if [[ -d "${install_prefix}/lib" ]]; then
  while IFS= read -r -d '' shared_lib; do
    if ! should_copy_shared_lib "${shared_lib}"; then
      continue
    fi
    copy_file "${shared_lib}" "${artifact_root}/lib"
  done < <(find "${install_prefix}/lib" -type f -name '*.so*' -print0 | sort -z)

  while IFS= read -r -d '' static_lib; do
    copy_file "${static_lib}" "${artifact_root}/lib"
  done < <(find "${install_prefix}/lib" -type f -name '*.a' -print0 | sort -z)
fi

if [[ "${android_stl}" == "c++_shared" ]]; then
  libcpp_shared=""
  for candidate in \
    "${ndk_home}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so" \
    "${ndk_home}/sources/cxx-stl/llvm-libc++/libs/${android_abi}/libc++_shared.so"; do
    if [[ -f "${candidate}" ]]; then
      libcpp_shared="${candidate}"
      break
    fi
  done

  if [[ -z "${libcpp_shared}" ]]; then
    libcpp_shared="$(find "${ndk_home}" -path "*/${android_abi}/libc++_shared.so" -o -path "*/aarch64-linux-android/libc++_shared.so" | head -n 1 || true)"
  fi

  if [[ -n "${libcpp_shared}" && -f "${libcpp_shared}" ]]; then
    copy_file "${libcpp_shared}" "${artifact_root}/lib"
  else
    echo "Warning: libc++_shared.so was not found under ${ndk_home}" >&2
  fi
fi

if [[ "${copy_jni_libs}" == "ON" ]]; then
  mkdir -p "${artifact_root}/jniLibs/${android_abi}"
  while IFS= read -r -d '' shared_lib; do
    copy_file "${shared_lib}" "${artifact_root}/jniLibs/${android_abi}"
  done < <(find "${artifact_root}/lib" -maxdepth 1 -type f -name '*.so*' -print0 | sort -z)
fi

cat > "${artifact_root}/manifest/build-info.txt" <<EOF
ROS_DISTRO=${ROS_DISTRO:-humble}
ANDROID_ABI=${android_abi}
ANDROID_API=${ANDROID_API:-29}
ANDROID_STL=${android_stl}
BUILD_SHARED_LIBS=${BUILD_SHARED_LIBS:-ON}
RMW_IMPLEMENTATION=${RMW_IMPLEMENTATION:-rmw_cyclonedds_cpp}
RMW_IMPLEMENTATION_DISABLE_RUNTIME_SELECTION=${RMW_IMPLEMENTATION_DISABLE_RUNTIME_SELECTION:-}
STATIC_ROSIDL_TYPESUPPORT_C=${STATIC_ROSIDL_TYPESUPPORT_C:-}
STATIC_ROSIDL_TYPESUPPORT_CPP=${STATIC_ROSIDL_TYPESUPPORT_CPP:-}
INSTALL_PREFIX=${install_prefix}
ARTIFACT_ROOT=${artifact_root}
ARTIFACT_WITH_METADATA=${copy_metadata}
EOF

if [[ -f "${workspace}/source-inventory.tsv" ]]; then
  copy_file "${workspace}/source-inventory.tsv" "${artifact_root}/manifest"
fi

(
  cd "${artifact_root}"
  manifest_roots=()
  while IFS= read -r -d '' root; do
    manifest_roots+=("${root}")
  done < <(existing_manifest_roots)

  if [[ "${checksum_manifest}" == "ON" ]]; then
    printf 'sha256\tsize\tpath\n'
    find "${manifest_roots[@]}" -type f -print | sort | while IFS= read -r file; do
      checksum="$(sha256sum "${file}" | awk '{print $1}')"
      size="$(stat -c '%s' "${file}")"
      printf '%s\t%s\t%s\n' "${checksum}" "${size}" "${file}"
    done
  else
    printf 'size\tpath\n'
    find "${manifest_roots[@]}" -type f -print | sort | while IFS= read -r file; do
      size="$(stat -c '%s' "${file}")"
      printf '%s\t%s\n' "${size}" "${file}"
    done
  fi
) > "${artifact_root}/manifest/artifact-manifest.tsv"

so_count="$(find "${artifact_root}/lib" -maxdepth 1 -type f -name '*.so*' | wc -l)"
static_count="$(find "${artifact_root}/lib" -maxdepth 1 -type f -name '*.a' | wc -l)"
header_count="$(find "${artifact_root}/include" -type f | wc -l)"
total_bytes="$(du -sb "${artifact_root}" | awk '{print $1}')"

echo "Android artifact package: ${artifact_root}"
echo "Shared libraries: ${so_count}"
echo "Static libraries: ${static_count}"
echo "Header files: ${header_count}"
echo "Size bytes: ${total_bytes}"
if [[ "${copy_jni_libs}" == "ON" ]]; then
  echo "Android Studio jniLibs: ${artifact_root}/jniLibs/${android_abi}"
fi