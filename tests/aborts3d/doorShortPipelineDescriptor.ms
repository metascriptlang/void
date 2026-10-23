// expect: gpu door: makePipeline descriptor holds 18 of 19 words
import { gfxSetup } from "../../src/sokol/gpu";
import { DOOR_PIPELINE_LENGTH } from "../../src/gpu/door.h";
import { doorMakePipeline } from "../../src/gpu/doorGpu";
@include("../../src/sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

let descriptor: Vec<uint32> = new Array(DOOR_PIPELINE_LENGTH - 1);

function init(): void { gfxSetup(); }
function frame(): void {
	const pipeline: uint32 = doorMakePipeline(descriptor);
	console.log(`a short pipeline descriptor through the door returned ${pipeline}`);
	process.exit(0);
}
voidRun(64, 64, init, frame);
