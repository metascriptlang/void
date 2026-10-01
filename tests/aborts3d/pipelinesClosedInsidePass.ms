// expect: gpu door: closePipelines with a pass already open; endPass ends it
import { gfxSetup } from "../../src/sokol/gpu";
import { beginScreenPass } from "../../src/gpu/target";
import { PipelineCache, closePipelines } from "../../src/gpu/pipeline";
@include("../../src/sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

const cache: PipelineCache = PipelineCache.empty();

function init(): void { gfxSetup(); }
function frame(): void {
	beginScreenPass({ x: 0.0, y: 0.0, z: 0.0, w: 1.0 });
	closePipelines(cache);
	console.log("a pipeline cache closed inside the screen pass");
	process.exit(0);
}
voidRun(64, 64, init, frame);
