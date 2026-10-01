// expect: gpu door: forgetPipelines on a pipeline cache that was closed
import { gfxSetup } from "../../src/sokol/gpu";
import { PipelineCache, closePipelines, forgetPipelines } from "../../src/gpu/pipeline";
@include("../../src/sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

const cache: PipelineCache = PipelineCache.empty();

function init(): void { gfxSetup(); }
function frame(): void {
	closePipelines(cache);
	forgetPipelines(cache);
	console.log("a closed pipeline cache forgot its pipelines again");
	process.exit(0);
}
voidRun(64, 64, init, frame);
