#!/usr/bin/env bash
set -euo pipefail

source /scripts/proxy_env.sh
configure_proxy_env

ndk_cache_dir="${NDK_CACHE_DIR:-/opt/android-ndk-cache}"
ndk_version="${NDK_VERSION:-r25b}"
ndk_url="${NDK_DOWNLOAD_URL:-https://dl.google.com/android/repository/android-ndk-r25b-linux.zip}"
ndk_home="${ANDROID_NDK_HOME:-${ndk_cache_dir}/android-ndk-${ndk_version}-linux}"
ndk_zip="${ndk_cache_dir}/android-ndk-${ndk_version}-linux.zip"
ndk_zip_part="${ndk_zip}.part"

mkdir -p "${ndk_cache_dir}"

repair_ndk_symlinks() {
  local prebuilt_dir="$1"
  python3 - "${prebuilt_dir}" <<'PY'
import os
import stat
import sys
from pathlib import Path

root = Path(sys.argv[1])
fixed = 0

for path in root.rglob("*"):
    if not path.is_file() or path.is_symlink():
        continue
    try:
        if path.stat().st_size > 256:
            continue
        data = path.read_text(encoding="utf-8").strip()
    except UnicodeDecodeError:
        continue
    if not data or "\n" in data or data.startswith("#!"):
        continue

    target = path.parent / data
    if not target.exists():
        continue

    path.unlink()
    os.symlink(data, path)
    fixed += 1

print(f"Repaired {fixed} NDK symlink-like files")
PY
}

validate_ndk() {
  local candidate_home="$1"
  local clang="${candidate_home}/toolchains/llvm/prebuilt/linux-x86_64/bin/clang"
  local toolchain="${candidate_home}/build/cmake/android.toolchain.cmake"

  [[ -f "${toolchain}" ]] || return 1
  [[ -e "${clang}" ]] || return 1
  "${clang}" --version >/dev/null 2>&1 || return 1
}

validate_archive() {
  local archive="$1"
  [[ -f "${archive}" ]] || return 1
  unzip -tq "${archive}" >/dev/null 2>&1
}

if validate_ndk "${ndk_home}"; then
  echo "Android NDK is ready: ${ndk_home}"
  exit 0
fi

if [[ -d "${ndk_home}" ]]; then
  echo "Existing NDK directory is incomplete or has broken symlinks; repairing: ${ndk_home}"
  repair_ndk_symlinks "${ndk_home}/toolchains/llvm/prebuilt/linux-x86_64"
  if validate_ndk "${ndk_home}"; then
    echo "Android NDK is ready after repair: ${ndk_home}"
    exit 0
  fi

  broken_dir="${ndk_home}.broken.$(date +%Y%m%d%H%M%S)"
  echo "Moving invalid NDK aside: ${broken_dir}"
  mv "${ndk_home}" "${broken_dir}"
fi

if [[ ! -f "${ndk_zip}" ]]; then
  print_proxy_env
  echo "Downloading Android NDK ${ndk_version}: ${ndk_url}"
  curl -fL --retry 5 --retry-delay 3 -C - -o "${ndk_zip_part}" "${ndk_url}"
  if [[ -f "${ndk_zip_part}" ]]; then
    mv "${ndk_zip_part}" "${ndk_zip}"
  elif [[ -f "${ndk_zip}" ]]; then
    echo "Download completed into existing archive path: ${ndk_zip}"
  else
    echo "NDK download finished but no archive was created: ${ndk_zip_part}" >&2
    exit 2
  fi
else
  echo "Reusing cached NDK archive: ${ndk_zip}"
fi

if ! validate_archive "${ndk_zip}"; then
  echo "Cached NDK archive is invalid: ${ndk_zip}" >&2
  rm -f "${ndk_zip}" "${ndk_zip_part}"
  exit 2
fi

extract_parent="${ndk_cache_dir}/.extract-${ndk_version}"
rm -rf "${extract_parent}"
mkdir -p "${extract_parent}"

echo "Extracting Android NDK into ${ndk_cache_dir}"
unzip -qo "${ndk_zip}" -d "${extract_parent}"

extracted_dir="$(find "${extract_parent}" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
if [[ -z "${extracted_dir}" ]]; then
  echo "NDK archive did not contain an extracted directory" >&2
  exit 2
fi

rm -rf "${ndk_home}"
mv "${extracted_dir}" "${ndk_home}"
rm -rf "${extract_parent}"

repair_ndk_symlinks "${ndk_home}/toolchains/llvm/prebuilt/linux-x86_64"

if ! validate_ndk "${ndk_home}"; then
  echo "Android NDK validation failed after extraction: ${ndk_home}" >&2
  echo "If this is a Windows bind mount that cannot store symlinks, move NDK_CACHE_DIR to a WSL/Linux filesystem path or a Docker volume." >&2
  exit 2
fi

echo "Android NDK is ready: ${ndk_home}"