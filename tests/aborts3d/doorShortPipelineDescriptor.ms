// expect: gpu door: makePipeline descriptor holds 18 of 19 words
import { gfxSetup } from "../../src/sokol/gpu";
import { DOOR_PIPELINE_LENGTH } from "../../src/gpu/door.h";
@include("../../src/sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;
extern function doorMakePipeline(descriptor: Span<uint32>): uint32;

let descriptor: Vec<uint32> = new Array(DOOR_PIPELINE_LENGTH - 1);

function init(): void { gfxSetup(); }
function frame(): void {
	const pipeline: uint32 = doorMakePipeline(descriptor);
	console.log(`a short pipeline descriptor through the C door returned ${pipeline}`);
	process.exit(0);
}
voidRun(64, 64, init, frame);
