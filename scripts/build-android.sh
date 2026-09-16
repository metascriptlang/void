#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

NDK="${ANDROID_NDK:-$HOME/Library/Android/sdk/ndk/28.0.13004108}"
ENTRY="${ENTRY:-src/examples/androidCubeEntry.ms}"
CC="$NDK/toolchains/llvm/prebuilt/darwin-x86_64/bin/aarch64-linux-android26-clang"
DEST="android/app/src/main/jniLibs/arm64-v8a"
mkdir -p "$DEST"

msc build "$ENTRY" --os=android --app=lib --cc="$CC" --output="$DEST/libVoidAndroid.so"
"$CC" -shared -fPIC android/app/src/main/jni/voidJni.c -L"$DEST" -lVoidAndroid -landroid -llog -o "$DEST/libVoidJni.so"

echo "OK: $DEST"
