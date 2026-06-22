// Void — sokol native entry for the 2D batcher demo. Window/loop only.

import { init2d, frame2d } from "./renderer2d";

@include("../sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

function main(): int32 {
	voidRun(800, 600, init2d, frame2d);
	return 0;
}
