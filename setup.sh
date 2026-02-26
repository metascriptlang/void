#!/bin/sh
set -e

DAWN_VERSION="7187"
DAWN_REPO="eliemichel/dawn-prebuilt"
DAWN_TAG="chromium/${DAWN_VERSION}"

# Detect platform
OS=$(uname -s)
ARCH=$(uname -m)

case "${OS}-${ARCH}" in
	Darwin-arm64)  PLATFORM="macos-aarch64" ;;
	Darwin-x86_64) PLATFORM="macos-x64" ;;
	Linux-x86_64)  PLATFORM="linux-x64" ;;
	*)             echo "Unsupported: ${OS}-${ARCH}"; exit 1 ;;
esac

# --- Dawn ---
DAWN_DEST="deps/dawn"
if [ -d "$DAWN_DEST" ]; then
	echo "Dawn already at ${DAWN_DEST}"
else
	ASSET="Dawn-${DAWN_VERSION}-${PLATFORM}-Release.zip"
	echo "Downloading Dawn ${DAWN_VERSION} for ${PLATFORM}..."
	mkdir -p deps
	gh release download "$DAWN_TAG" -R "$DAWN_REPO" -p "$ASSET" -D /tmp --clobber
	unzip -q "/tmp/${ASSET}" -d "$DAWN_DEST"
	rm "/tmp/${ASSET}"
	echo "Dawn installed"
fi

# --- sdl3webgpu (pre-compile, needs ObjC on macOS) ---
SDL3WEBGPU_OBJ="deps/sdl3webgpu/sdl3webgpu.o"
if [ -f "$SDL3WEBGPU_OBJ" ]; then
	echo "sdl3webgpu already compiled"
else
	echo "Compiling sdl3webgpu..."
	SDL3_INC="$(brew --prefix sdl3)/include"
	DAWN_INC="deps/dawn/include"
	case "$OS" in
		Darwin)
			clang -c deps/sdl3webgpu/sdl3webgpu_bridge.m \
				-o "$SDL3WEBGPU_OBJ" -fno-objc-arc \
				-I"$SDL3_INC" -I"$DAWN_INC" -I deps/sdl3webgpu
			;;
		Linux)
			cc -c deps/sdl3webgpu/sdl3webgpu.c -o "$SDL3WEBGPU_OBJ" \
				-I"$SDL3_INC" -I"$DAWN_INC" -I deps/sdl3webgpu
			;;
	esac
	echo "sdl3webgpu compiled"
fi

echo "--- Setup complete ---"
