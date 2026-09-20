# Device evidence

`gles3Campfire.png` is the first frame this port has ever produced outside D3D11.

Committed rather than left in gitignored `out/tmp` because it is not a baseline — nothing is
compared against it byte for byte, and it cannot be: the surface is 320x640 where the D3D11
captures are 1280x720. It is here because "the GLES3 path has never executed" was true of this
port through M3, M4, M5 and M6, and a single image is the cheapest durable proof that it stopped
being true, and of exactly how far that goes.

What produced it, so it can be reproduced:

```
msc build out/tmp/android/campfireEntry.ms --os=android --app=lib \
  --cc="$NDK/.../clang.exe --target=aarch64-linux-android26" \
  --output=android/app/src/main/jniLibs/arm64-v8a/libVoidAndroid.so
$CC --target=aarch64-linux-android26 -shared -fPIC android/app/src/main/jni/voidJni.c \
  -Landroid/app/src/main/jniLibs/arm64-v8a -lVoidAndroid -landroid -llog \
  -o android/app/src/main/jniLibs/arm64-v8a/libVoidJni.so
(cd android && ANDROID_HOME=... ./gradlew assembleDebug)
adb install -r android/app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n com.metascript.voidsample/.MainActivity
adb exec-out screencap -p > gles3Campfire.png
```

Read `docs/VOID3D.md`, "The scope of every pixel claim", for what this frame does and does not
establish. The short version: it ran on the **Android emulator**, not on a device.
