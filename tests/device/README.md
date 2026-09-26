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
(`pixellight` AVD, cold boot) on 2026-09-26 at `a170d81`. The frame has 23 colours.

Both builds were installed and cold-started in one boot, two screenshots each, seconds apart:

| pair | pixels that differ |
|---|---|
| pre-M13 against M13, first shots / second shots | 13 306 / 13 540 |
| two shots of the pre-M13 build | 1 245 |
| two shots of the M13 build | 694 |
| the pre-M13 build, this boot against a cold start the day before | 446 |
| the M13 build against the committed image, another boot | 728 |

The change is ten times the largest noise. On D3D11 the same change moves 6.9% of the palette-on
frame; here 13 306 is 6.5%. The pre-M13 build is the tree with `shader3d.glsl.h` of `e070605`.
Each build first evicted the objects built from `gpu3d.c`, and `grep -a` on each
`libVoidAndroid.so` tells them apart: the directional step, `step(0.3499999940395355`, is in the
pre-M13 library 6 times and in the M13 library 0 times.

The entry is the Android entry with two configuration calls added before `registerVoid()`:

```
configureCampfire(PixelArtSettings.full(), true);
configureCampfireGreyGround(0.0, false);
```

The build, install and screenshot are the recipe above, with that entry in place of
`out/tmp/android/campfireEntry.ms` (the file used was `out/tmp/android/campfireGreyOffEntry.ms`).

## `gles3Forward.png`

M14's forward preset on GLES3: the campfire drawn with the core's own `Lit` and `Particle`
programs into the preset's colour and depth targets, then `Copy` to the swapchain. The Android
swapchain has no depth buffer (`src/sokol/bridgeAndroid.c` sets `depth_format` to none), which is
why the preset draws the scene into targets of its own; this frame is that path running, stones
occluding each other and the snow. Taken on the **Android emulator** (`pixellight` AVD) on
2026-09-26 at `bec89e5`. The frame has 385 colours: the core's lights are continuous and there
is no palette. Two screenshots seconds apart differ in 7 914 pixels, the snow and embers moving.
`grep -a` finds the copy program's `sourceTexture` in the built `libVoidAndroid.so` 13 times.

The entry is the Android entry with three configuration calls added before `registerVoid()`:

```
configureCampfire(PixelArtSettings.full(), true);
configureCampfireParticles(true);
configureCampfireForward(true);
```

The build, install and screenshot are the recipe above, with that entry in place of
`out/tmp/android/campfireEntry.ms` (the file used was `out/tmp/android/campfireForwardEntry.ms`).

## `gles3Billboard.png`

M15's core billboard on GLES3: the forward preset draws the grass and the flame with `Program.Billboard`,
the grass lit through the core's lights and the flame unlit. Taken on the **Android emulator**
(`pixellight` AVD, cold boot) on 2026-09-26 at `d7e9fdb`, msc `598ca62e`. The frame has 2 223 colours; two
screenshots two seconds apart differ in 7 346 pixels, the snow, the embers and the flicker. The flame's
three texel colours are there exactly (3, 13 and 9 pixels in this shot), as the gate's `unlit` stage holds
on D3D11; `gles3Forward.png`, M14's, has none of them. `grep -a` finds the billboard's `towardCamera` 32 times
in the built `libVoidAndroid.so`. The entry is `out/tmp/android/campfireForwardEntry.ms`, as for
`gles3Forward.png`.

The pixel-art preset's form was run the same way, in the same boot: `campfireGreyOffEntry.ms` built from
M14 (`cf1b92f`) and from M15 (`d7e9fdb`) on one msc, two screenshots each. M15 against M14 differs in 666 to
2 034 pixels; two shots of one build differ in 374 (M14) and 1 792 (M15). In all five pairs the
differences fall inside one box of about 197×125 pixels around the fire, which flickers, and nothing
differs outside it. That is an emulator claim, not a pixel comparison, and those screenshots are not kept.
