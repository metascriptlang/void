// expect: gpu door: releasePipelines with a pass already open; endPass ends it
import { gfxSetup } from "../../src/sokol/gpu";
import { RenderState } from "../../src/gpu/state";
import { SWAPCHAIN_LAYOUT, beginScreenPass } from "../../src/gpu/target";
import { PipelineCache, releasePipelines } from "../../src/gpu/pipeline";
import { Program, VertexLayout, pipelineFor } from "../../src/void3d/gpu3d";
@include("../../src/sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

const cache: PipelineCache = PipelineCache.empty();

function init(): void { gfxSetup(); }
function frame(): void {
	const made: uint32 = pipelineFor(
		cache,
		Program.Copy,
		VertexLayout.Fullscreen,
		false,
		RenderState.defaults(),
		SWAPCHAIN_LAYOUT,
	);
	beginScreenPass({ x: 0.0, y: 0.0, z: 0.0, w: 1.0 });
	releasePipelines(cache);
	console.log(`pipeline ${made} was destroyed inside the screen pass`);
	process.exit(0);
}
voidRun(64, 64, init, frame);
