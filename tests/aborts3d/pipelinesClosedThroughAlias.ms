// expect: gpu door: pipelineFor on a pipeline cache that was closed
import { gfxSetup } from "../../src/sokol/gpu";
import { RenderState } from "../../src/gpu/state";
import { SWAPCHAIN_LAYOUT } from "../../src/gpu/target";
import { PipelineCache, closePipelines } from "../../src/gpu/pipeline";
import {
	Program,
	VertexLayout,
	pipelineFor,
	MATERIAL_UNIFORM_LENGTH,
} from "../../src/void3d/gpu3d";
import { DrawContext } from "../../src/void3d/draw";
@include("../../src/sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

struct PassHolder {
	pipelines: PipelineCache;
}

const context: DrawContext = DrawContext.withUniformCapacity(MATERIAL_UNIFORM_LENGTH);

function copyPipeline(cache: PipelineCache): uint32 {
	return pipelineFor(
		cache,
		Program.Copy,
		VertexLayout.Fullscreen,
		false,
		RenderState.defaults(),
		SWAPCHAIN_LAYOUT,
	);
}

function init(): void { gfxSetup(); }
function frame(): void {
	const first: uint32 = copyPipeline(context.pipelines);
	const held: PassHolder = { pipelines: context.pipelines };
	closePipelines(context.pipelines);
	console.log(`a closed cache made pipeline ${copyPipeline(held.pipelines)} after ${first}`);
	process.exit(0);
}
voidRun(64, 64, init, frame);
