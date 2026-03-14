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

if [[ $# -lt 4 ]]; then
  echo "usage: $0 <platform> <srcroot> <build-dir> <install-prefix>" >&2
  exit 1
fi

platform="$1"
srcroot="$2"
build_dir="$3"
install_prefix="$4"

bitcoin_core_dir="${srcroot}/bitcoin-core"

export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"

resolve_command() {
  local command_name="$1"
  local install_hint="$2"
  local candidate

  for candidate in "/opt/homebrew/bin/${command_name}" "/usr/local/bin/${command_name}"; do
    if [[ -x "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  if candidate="$(command -v "${command_name}" 2>/dev/null)"; then
    printf '%s\n' "${candidate}"
    return 0
  fi

  echo "error: Missing required tool '${command_name}'. ${install_hint}" >&2
  exit 1
}

step="checking prerequisites"
brew_bin="$(resolve_command brew "Install Homebrew first from https://brew.sh/.")"
cmake_bin="$(resolve_command cmake "Install it first, for example with 'brew install cmake'.")"
ninja_bin="$(resolve_command ninja "Install it first, for example with 'brew install ninja'.")"

if command -v ccache >/dev/null 2>&1; then
  with_ccache=ON
else
  with_ccache=OFF
fi

if [[ ! -d "${bitcoin_core_dir}" ]]; then
  echo "error: Missing bitcoin-core checkout at ${bitcoin_core_dir}. Clone or symlink Bitcoin Core there before building." >&2
  exit 1
fi

find_boost_prefix() {
  local candidate

  for candidate in /opt/homebrew/opt/boost /usr/local/opt/boost; do
    if [[ -d "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  if [[ -x "${brew_bin}" ]]; then
    local prefix
    prefix="$("${brew_bin}" --prefix boost 2>/dev/null || true)"
    if [[ -n "${prefix}" && -d "${prefix}" ]]; then
      printf '%s\n' "${prefix}"
      return 0
    fi
  fi

  return 1
}

boost_prefix="$(find_boost_prefix || true)"
boost_args=()
probe_warning_args=(
  -Werror=unknown-warning-option
  -Werror=unused-command-line-argument
)
probe_warning_flags="${probe_warning_args[*]}"

if [[ -n "${boost_prefix}" ]]; then
  shopt -s nullglob
  boost_dir_matches=("${boost_prefix}"/lib/cmake/Boost-*)
  boost_headers_matches=("${boost_prefix}"/lib/cmake/boost_headers-*)
  shopt -u nullglob

  if [[ ${#boost_dir_matches[@]} -gt 0 ]]; then
    boost_args+=("-DBoost_DIR=${boost_dir_matches[0]}")
  fi

  if [[ ${#boost_headers_matches[@]} -gt 0 ]]; then
    boost_args+=("-Dboost_headers_DIR=${boost_headers_matches[0]}")
  fi
fi

case "${platform}" in
  macosx)
    platform_args=()
    ;;
  iphonesimulator)
    platform_args=(
      -DCMAKE_SYSTEM_NAME=iOS
      -DCMAKE_OSX_SYSROOT=iphonesimulator
      -DCMAKE_OSX_ARCHITECTURES=arm64
    )
    ;;
  iphoneos)
    platform_args=(
      -DCMAKE_SYSTEM_NAME=iOS
      -DCMAKE_OSX_SYSROOT=iphoneos
      -DCMAKE_OSX_ARCHITECTURES=arm64
    )
    ;;
  *)
    echo "note: Skipping libbitcoinkernel build for unsupported platform ${platform}." >&2
    exit 0
    ;;
esac

echo "note: Building libbitcoinkernel for ${platform}..." >&2

step="preparing build directories"
mkdir -p "${build_dir}" "${install_prefix}"

step="configuring Bitcoin Core kernel build"
"${cmake_bin}" -S "${bitcoin_core_dir}" -B "${build_dir}" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${install_prefix}" \
  -DCMAKE_MAKE_PROGRAM="${ninja_bin}" \
  "-DCMAKE_C_FLAGS=${probe_warning_flags}" \
  "-DCMAKE_CXX_FLAGS=${probe_warning_flags}" \
  "${platform_args[@]}" \
  "${boost_args[@]}" \
  -DBUILD_SHARED_LIBS=ON \
  -DBUILD_BITCOIN_BIN=OFF \
  -DBUILD_DAEMON=OFF \
  -DBUILD_GUI=OFF \
  -DBUILD_CLI=OFF \
  -DBUILD_TESTS=OFF \
  -DBUILD_TX=OFF \
  -DBUILD_UTIL=OFF \
  -DBUILD_UTIL_CHAINSTATE=OFF \
  -DBUILD_KERNEL_LIB=ON \
  -DBUILD_KERNEL_TEST=OFF \
  -DENABLE_IPC=OFF \
  -DENABLE_WALLET=OFF \
  -DWITH_ZMQ=OFF \
  -DBUILD_BENCH=OFF \
  "-DWITH_CCACHE=${with_ccache}"

step="building libbitcoinkernel"
"${cmake_bin}" --build "${build_dir}" --target bitcoinkernel -j4

step="installing libbitcoinkernel"
"${cmake_bin}" --install "${build_dir}" --component libbitcoinkernel

echo "note: libbitcoinkernel ready at ${install_prefix}/lib/libbitcoinkernel.dylib" >&2
