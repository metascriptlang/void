// Void — sokol native entry. Window/loop only; rendering is in rendererSokol.ms.

import { initRenderer, renderFrame } from "./rendererSokol";

@include("../sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

function main(): int32 {
	voidRun(800, 600, initRenderer, renderFrame);
	return 0;
}
