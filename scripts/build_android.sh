#!/usr/bin/env bash
set -euo pipefail

workspace="${WORKSPACE_DIR:-/work}"
ndk_home="${ANDROID_NDK_HOME:-/opt/android-ndk-cache/android-ndk-r25b-linux}"
android_abi="${ANDROID_ABI:-arm64-v8a}"
android_api="${ANDROID_API:-29}"
android_stl="${ANDROID_STL:-c++_shared}"
build_shared_libs="${BUILD_SHARED_LIBS:-ON}"
build_packages="${BUILD_PACKAGES:-rclcpp rmw_fastrtps_cpp std_msgs}"
build_output_suffix="${BUILD_OUTPUT_SUFFIX:-}"
rmw_implementation="${RMW_IMPLEMENTATION:-rmw_fastrtps_cpp}"
rmw_runtime_selection="${RMW_IMPLEMENTATION_DISABLE_RUNTIME_SELECTION:-}"
position_independent_code="${CMAKE_POSITION_INDEPENDENT_CODE:-}"
static_typesupport_c="${STATIC_ROSIDL_TYPESUPPORT_C:-}"
static_typesupport_cpp="${STATIC_ROSIDL_TYPESUPPORT_CPP:-}"
parallel_workers="${PARALLEL_WORKERS:-$(nproc)}"
read -r -a build_package_args <<< "${build_packages}"

build_label="android_${android_abi}"
if [[ -n "${build_output_suffix}" ]]; then
  build_label="${build_label}_${build_output_suffix}"
fi

log_base="${ANDROID_LOG_BASE:-${workspace}/log/${build_label}}"
build_base="${ANDROID_BUILD_BASE:-${workspace}/build/${build_label}}"
install_base="${ANDROID_INSTALL_PREFIX:-${workspace}/install/${build_label}}"

source /scripts/proxy_env.sh
configure_proxy_env

bash /scripts/ensure_ndk.sh

toolchain_file="${ndk_home}/build/cmake/android.toolchain.cmake"
linux_clang="${ndk_home}/toolchains/llvm/prebuilt/linux-x86_64/bin/clang"

if [[ ! -f "${toolchain_file}" ]]; then
  echo "Android NDK toolchain was not found: ${toolchain_file}" >&2
  echo "Check NDK_CACHE_DIR, NDK_DOWNLOAD_URL, or ANDROID_NDK_HOME in .env." >&2
  exit 2
fi

if [[ ! -x "${linux_clang}" ]]; then
  echo "Linux Android NDK clang was not found: ${linux_clang}" >&2
  echo "Run: docker compose run --rm android-build" >&2
  exit 2
fi

if [[ ! -d "${workspace}/src" ]]; then
  echo "Missing ${workspace}/src. Run /scripts/fetch_sources.sh first." >&2
  exit 2
fi

if [[ ${#build_package_args[@]} -eq 0 ]]; then
  echo "BUILD_PACKAGES is empty. Set at least one package name." >&2
  exit 2
fi

bash /scripts/apply_android_patches.sh

cd "${workspace}"

echo "Building packages up to: ${build_packages}"
echo "Target: ${android_abi}, android-${android_api}, STL: ${android_stl}, shared libs: ${build_shared_libs}"
echo "RMW implementation: ${rmw_implementation}"
echo "Build base: ${build_base}"
echo "Install base: ${install_base}"
print_proxy_env

cmake_args=(
  -GNinja
  -DCMAKE_TOOLCHAIN_FILE="${toolchain_file}"
  -DANDROID_ABI="${android_abi}"
  -DANDROID_PLATFORM="android-${android_api}"
  -DANDROID_STL="${android_stl}"
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH
  -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=BOTH
  -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH
  -DROSIDL_GENERATOR_PY_DISABLE=ON
  -DBUILD_SHARED_LIBS="${build_shared_libs}"
  -DBUILD_TESTING=OFF
  -DSECURITY=OFF
  -DSHM_TRANSPORT_DEFAULT=OFF
  -DTHIRDPARTY=ON
  -DRMW_IMPLEMENTATION="${rmw_implementation}"
)

if [[ -n "${rmw_runtime_selection}" ]]; then
  cmake_args+=(-DRMW_IMPLEMENTATION_DISABLE_RUNTIME_SELECTION="${rmw_runtime_selection}")
fi

if [[ -n "${position_independent_code}" ]]; then
  cmake_args+=(-DCMAKE_POSITION_INDEPENDENT_CODE="${position_independent_code}")
fi

if [[ -n "${static_typesupport_c}" ]]; then
  cmake_args+=(-DSTATIC_ROSIDL_TYPESUPPORT_C="${static_typesupport_c}")
fi

if [[ -n "${static_typesupport_cpp}" ]]; then
  cmake_args+=(-DSTATIC_ROSIDL_TYPESUPPORT_CPP="${static_typesupport_cpp}")
fi

colcon --log-base "${log_base}" build \
  --merge-install \
  --build-base "${build_base}" \
  --install-base "${install_base}" \
  --base-paths src \
  --parallel-workers "${parallel_workers}" \
  --packages-up-to "${build_package_args[@]}" \
  --cmake-force-configure \
  --cmake-args \
    "${cmake_args[@]}"

echo "Android install tree: ${install_base}"