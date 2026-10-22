// Void — Android app entry. NativeApp.start runs MsMain, whose main calls voidRun; the app driver
// (bridgeAndroidApp.c) records the closures and returns, then adds the view that drives them.
// Compile src/sokol/androidAppEntry.c with the app for NativeApp's JNI entry points.

import { init2d, frame2d } from "./renderer2d";

@include("../sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

function main(): int32 {
	voidRun(800, 600, init2d, frame2d);
	return 0;
}

main();
