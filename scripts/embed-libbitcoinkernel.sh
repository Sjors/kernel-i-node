#!/usr/bin/env bash

set -euo pipefail

step="initializing"

on_error() {
  local status="$1"
  echo "error: libbitcoinkernel ${step} failed for ${platform:-unknown platform} (exit ${status})." >&2
  echo "error: Inspect the 'Embed libbitcoinkernel' build phase log for details." >&2
  exit "${status}"
}

trap 'on_error $?' ERR

platform="${1:-${PLATFORM_NAME:-}}"
srcroot="${2:-${SRCROOT:-}}"
target_build_dir="${3:-${TARGET_BUILD_DIR:-}}"
frameworks_folder_path="${4:-${FRAMEWORKS_FOLDER_PATH:-}}"
code_sign_identity="${5:-${EXPANDED_CODE_SIGN_IDENTITY:-}}"
derived_file_dir="${6:-${DERIVED_FILE_DIR:-}}"
target_temp_dir="${7:-${TARGET_TEMP_DIR:-}}"

require_value() {
  local name="$1"
  local value="$2"

  if [[ -z "${value}" ]]; then
    echo "error: Missing required build setting '${name}'." >&2
    exit 1
  fi
}

require_value "PLATFORM_NAME" "${platform}"
require_value "SRCROOT" "${srcroot}"
require_value "TARGET_BUILD_DIR" "${target_build_dir}"
require_value "FRAMEWORKS_FOLDER_PATH" "${frameworks_folder_path}"
require_value "DERIVED_FILE_DIR" "${derived_file_dir}"
require_value "TARGET_TEMP_DIR" "${target_temp_dir}"

kernel_build_root="${target_temp_dir}/libbitcoinkernel"
kernel_install_root="${derived_file_dir}/libbitcoinkernel"

case "${platform}" in
  macosx)
    platform_slug="macos"
    ;;
  iphonesimulator)
    platform_slug="iossim"
    ;;
  iphoneos)
    platform_slug="ios"
    ;;
  *)
    echo "note: Skipping libbitcoinkernel embed for ${platform}; kernel sync is currently unsupported on this platform."
    exit 0
    ;;
esac

build_dir="${kernel_build_root}/${platform_slug}"
install_prefix="${kernel_install_root}/${platform_slug}"
source_lib="${install_prefix}/lib/libbitcoinkernel.dylib"

step="building libbitcoinkernel"
/bin/bash "${srcroot}/scripts/build-libbitcoinkernel.sh" "${platform}" "${srcroot}" "${build_dir}" "${install_prefix}"

dest_dir="${target_build_dir}/${frameworks_folder_path}"
dest_lib="${dest_dir}/libbitcoinkernel.dylib"

step="verifying libbitcoinkernel output"
if [[ ! -f "${source_lib}" ]]; then
  echo "error: Missing libbitcoinkernel at ${source_lib} after build." >&2
  exit 1
fi

step="embedding libbitcoinkernel"
mkdir -p "${dest_dir}"
cp -f "${source_lib}" "${dest_lib}"
chmod 755 "${dest_lib}"

if [[ -n "${code_sign_identity}" ]]; then
  step="codesigning libbitcoinkernel"
  /usr/bin/codesign --force --sign "${code_sign_identity}" --timestamp=none "${dest_lib}"
fi
