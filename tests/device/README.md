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

After the emulator boots, `adb shell am force-stop com.metascript.voidsample` before the `am start`.
A quickboot snapshot resumes the app's old process, which then draws black at 30 fps with no
`EGL_CONTEXT_LOST` reaching Void (measured 2026-09-24 on `pixellight`; a cold start draws the
campfire). The gate's `device` stage screenshots whatever is running and fails on that frame.

Read `docs/VOID3D.md`, "The scope of every pixel claim", for what this frame does and does not
establish. The short version: it ran on the **Android emulator**, not on a device.

## `gles3Particles.png`

The M11 path on GLES3: the campfire with the night palette on, snow and embers on stream meshes,
drawn by the `Particle` program. It was taken on the **Android emulator** (`pixellight` AVD,
x86_64 running the arm64 library under translation, `ro.hardware.egl=emulation`) on 2026-09-24,
at `main` after `2936e0b` plus the campfire's framebuffer-height fix. The frame has 24 colours:
the palette's 21 plus the system navigation bar.

The entry is the Android entry with two configuration calls added before `registerVoid()`:

```
configureCampfire(PixelArtSettings.full(), true);
configureCampfireParticles(true);
```

The build, install and screenshot are the recipe above, with that entry in place of
`out/tmp/android/campfireEntry.ms` (the file used was `out/tmp/android/campfireParticlesEntry.ms`).

## `gles3GreyGround.png`

The lit program's material saturation on GLES3: the campfire with the night palette on and the
ground on its own lit material at saturation −0.75. It was taken on the **Android emulator**
(`pixellight` AVD) on 2026-09-24 from the M12 working tree. The frame has 24 colours. Against the
same build with the saturation at 0 it differs in 20 789 pixels, across the ground; two
screenshots of that ungreyed build, taken seconds apart, differ in 274, all at the fire.

The entry is the Android entry with two configuration calls added before `registerVoid()`:

```
configureCampfire(PixelArtSettings.full(), true);
configureCampfireGreyGround(-0.75, false);
```

The build, install and screenshot are the recipe above, with that entry in place of
`out/tmp/android/campfireEntry.ms` (the files used were `out/tmp/android/campfireGreyEntry.ms`
and, for the comparison, `campfireGreyOffEntry.ms`).

## `gles3Lambert.png`

M13's lighting on GLES3: every light multiplies the material's colour and the directional light
is Lambert. The campfire with the night palette on, taken on the **Android emulator**
(`pixellight` AVD, cold boot) on 2026-09-26 at `a170d81`. The frame has 23 colours. Against the
pre-M13 build of the same entry, taken on 2026-09-25 after a cold start, it differs in 13 006
pixels (6.4%); two screenshots of the M13 build, seconds apart, differ in 613. On D3D11 the same
change moves 6.9% of the palette-on frame. Before the screenshot, `grep -a` on the built
`libVoidAndroid.so` found the Lambert `max(dot(` in its GLSL and no `step(0.35`, so the library
did not link a stale shader object.

The entry is `out/tmp/android/campfireGreyOffEntry.ms`, the palette-on campfire with the ground's
saturation at 0; the build, install and screenshot are the recipe above.
