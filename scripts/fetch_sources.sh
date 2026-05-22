#!/usr/bin/env bash
set -euo pipefail

manifest="${1:-${SOURCE_MANIFEST:-/manifests/ros2-humble-android.repos}}"
workspace="${WORKSPACE_DIR:-/work}"
src_dir="${workspace}/src"
inventory_file="${workspace}/source-inventory.tsv"

source /scripts/proxy_env.sh
configure_proxy_env

mkdir -p "${src_dir}"

print_proxy_env
echo "Validating manifest and existing checkouts"
python3 /scripts/validate_sources.py \
	--manifest "${manifest}" \
	--src "${src_dir}" \
	--check-existing

echo "Importing sources from ${manifest} into ${workspace}/src"
vcs import --recursive --skip-existing "${src_dir}" < "${manifest}"

echo "Validating imported sources and writing inventory"
python3 /scripts/validate_sources.py \
	--manifest "${manifest}" \
	--src "${src_dir}" \
	--check-existing \
	--write-inventory "${inventory_file}"

echo "Source checkout complete. Inventory: ${inventory_file}"
echo "To update later, run: vcs pull ${src_dir}"