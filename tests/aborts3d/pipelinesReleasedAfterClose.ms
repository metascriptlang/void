// expect: gpu door: releasePipelines on a pipeline cache that was closed
import { gfxSetup } from "../../src/sokol/gpu";
import { PipelineCache, closePipelines, releasePipelines } from "../../src/gpu/pipeline";
@include("../../src/sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

const cache: PipelineCache = PipelineCache.empty();

function init(): void { gfxSetup(); }
function frame(): void {
	closePipelines(cache);
	releasePipelines(cache);
	console.log("a closed pipeline cache was released again");
	process.exit(0);
}
voidRun(64, 64, init, frame);
