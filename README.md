# Node

This project is a SwiftUI proof of concept for feeding signet blocks from mempool.space into `libbitcoinkernel`.

![Node app screenshot](screenshot.png)

It expects a local Bitcoin Core checkout to be available at `./bitcoin-core` and a locally built kernel library at:

`./local/bitcoinkernel/lib/libbitcoinkernel.dylib`

For iPhone Simulator builds it instead expects:

`./local/bitcoinkernel-iossim/lib/libbitcoinkernel.dylib`

The Xcode project embeds the matching dylib into the app bundle at build time. You do not need to set `BTCK_LIB_PATH` if the local kernel has been built in the expected location.

## Prerequisites

Install the build tools and the non-IPC dependencies used by the kernel build:

```sh
brew install cmake ninja boost pkgconf libevent
```

IPC is not needed for this project, so the commands below build Bitcoin Core with `-DENABLE_IPC=OFF`.

## Clone Bitcoin Core

Clone upstream Bitcoin Core into `bitcoin-core` in this repository root:

```sh
git clone https://github.com/bitcoin/bitcoin.git bitcoin-core
```

If you already have a checkout elsewhere, a symlink also works:

```sh
ln -s /path/to/bitcoin bitcoin-core
```

## Build libbitcoinkernel

From this repository root, configure a kernel-only build for macOS:

```sh
cmake -S bitcoin-core -B build-bitcoinkernel -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$PWD/local/bitcoinkernel" \
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
  -DWITH_CCACHE=OFF
```

Build just the kernel library:

```sh
cmake --build build-bitcoinkernel --target bitcoinkernel -j4
```

Install only the `libbitcoinkernel` component into the local project prefix:

```sh
cmake --install build-bitcoinkernel --component libbitcoinkernel
```

After that, these files should exist:

```text
local/bitcoinkernel/lib/libbitcoinkernel.dylib
local/bitcoinkernel/include/bitcoinkernel.h
local/bitcoinkernel/lib/pkgconfig/libbitcoinkernel.pc
```

## Build libbitcoinkernel For iPhone Simulator

The simulator build is almost the same, with an iPhone Simulator sysroot, arm64 simulator architecture, and a different install prefix:

```sh
cmake -S bitcoin-core -B build-bitcoinkernel-iossim -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$PWD/local/bitcoinkernel-iossim" \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphonesimulator \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
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
  -DWITH_CCACHE=OFF
```

Build and install the simulator library:

```sh
cmake --build build-bitcoinkernel-iossim --target bitcoinkernel -j4
cmake --install build-bitcoinkernel-iossim --component libbitcoinkernel
```

After that, these files should exist:

```text
local/bitcoinkernel-iossim/lib/libbitcoinkernel.dylib
local/bitcoinkernel-iossim/include/bitcoinkernel.h
local/bitcoinkernel-iossim/lib/pkgconfig/libbitcoinkernel.pc
```

## Run The App

Open the Xcode project and run the `Node` app target normally.

During the build, Xcode copies the matching local kernel dylib into the app bundle's `Frameworks` directory:

- macOS: `./local/bitcoinkernel/lib/libbitcoinkernel.dylib`
- iPhone Simulator: `./local/bitcoinkernel-iossim/lib/libbitcoinkernel.dylib`

This avoids the sandbox issues you get when trying to `dlopen` a dylib directly from the project folder. If the required kernel library is missing, the app build should fail with a clear error from the `Embed libbitcoinkernel` build phase.

## Notes

- This app uses `https://mempool.space/signet/api` as a block source.
- This is not a full P2P node. `libbitcoinkernel` validates and stores blocks, while block download is done externally.
- The `libbitcoinkernel` API is experimental and may change as Bitcoin Core evolves.
