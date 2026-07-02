// Void — Android embed entry (M2 headless render proof). Registers renderer2d's
// init2d/frame2d, then hands control to the C driver (voidAndroidM2Run) which owns the
// EGL pbuffer + render loop + PNG readback. The real RN path (M3) drives frames from a
// SurfaceView instead; the MetaScript side is identical.

import { init2d, frame2d } from "./renderer2d";

@include("bridge.h");
extern function voidEmbedRegister(init: () => void, frame: () => void): void;
extern function voidAndroidM2Run(): void;

function main(): int32 {
	voidEmbedRegister(init2d, frame2d);
	voidAndroidM2Run();
	return 0;
}

main();
