import { initPixellight, framePixellight } from "./pixellightScene";

@include("../sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

function main(): int32 {
	voidRun(1280, 720, initPixellight, framePixellight);
	return 0;
}

main();
