import { initCampfire, frameCampfire } from "./campfireScene";

@include("../sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

function main(): int32 {
	voidRun(1280, 720, initCampfire, frameCampfire);
	return 0;
}
