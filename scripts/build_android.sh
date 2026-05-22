#!/usr/bin/env bash
set -euo pipefail

workspace="${WORKSPACE_DIR:-/work}"
ndk_home="${ANDROID_NDK_HOME:-/opt/android-ndk-cache/android-ndk-r25b-linux}"
android_abi="${ANDROID_ABI:-arm64-v8a}"
android_api="${ANDROID_API:-29}"
build_shared_libs="${BUILD_SHARED_LIBS:-ON}"
build_packages="${BUILD_PACKAGES:-rclcpp rmw_fastrtps_cpp std_msgs}"
parallel_workers="${PARALLEL_WORKERS:-$(nproc)}"
read -r -a build_package_args <<< "${build_packages}"

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
  echo "Run: docker compose run --rm prepare-ndk" >&2
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
echo "Target: ${android_abi}, android-${android_api}, shared libs: ${build_shared_libs}"
print_proxy_env

colcon --log-base "${workspace}/log/android_${android_abi}" build \
  --merge-install \
  --build-base "${workspace}/build/android_${android_abi}" \
  --install-base "${workspace}/install/android_${android_abi}" \
  --parallel-workers "${parallel_workers}" \
  --packages-up-to "${build_package_args[@]}" \
  --cmake-force-configure \
  --cmake-args \
    -GNinja \
    -DCMAKE_TOOLCHAIN_FILE="${toolchain_file}" \
    -DANDROID_ABI="${android_abi}" \
    -DANDROID_PLATFORM="android-${android_api}" \
    -DANDROID_STL=c++_shared \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH \
    -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=BOTH \
    -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH \
    -DROSIDL_GENERATOR_PY_DISABLE=ON \
    -DBUILD_SHARED_LIBS="${build_shared_libs}" \
    -DBUILD_TESTING=OFF \
    -DSECURITY=OFF \
    -DSHM_TRANSPORT_DEFAULT=OFF \
    -DTHIRDPARTY=ON \
    -DRMW_IMPLEMENTATION=rmw_fastrtps_cpp

echo "Android install tree: ${workspace}/install/android_${android_abi}"