// expect: gpu door: program id 2000000000 was never registered
import "../../src/sokol/gpu";
import { PipelineCache, pipelineFor } from "../../src/gpu/pipeline";
import { RenderState } from "../../src/gpu/state";
import { SWAPCHAIN_LAYOUT } from "../../src/gpu/target";

let cache: PipelineCache = PipelineCache.empty();
const pipeline: uint32 = pipelineFor(
	cache, 2000000000, 0, false, RenderState.defaults(), SWAPCHAIN_LAYOUT,
);
console.log(`an unregistered program made pipeline ${pipeline}`);
