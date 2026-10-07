import { fbWidth, fbHeight } from "../sokol/gpu";
import { setupCardTable, frameCardTable } from "./cardTableScene";

@include("../sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

let frames: int32 = 0;

function init(): void {
	setupCardTable(false);
}

function frame(): void {
	const drawn = frameCardTable(frames, fbWidth(), fbHeight());
	if (!drawn.ok) {
		console.log(`card table: frame ${frames} stopped, ${drawn.error.toString()}`);
		unreachable;
	}
	frames = frames + 1;
}

function main(): int32 {
	voidRun(960, 720, init, frame);
	return 0;
}

main();
