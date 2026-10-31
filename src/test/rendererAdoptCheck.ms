// beginFrame's answer that the GPU context is new, through a frame the renderer refuses after
// adopting it. Adopting rebuilds GPU buffers, so this runs on a device: WARP on Windows, the
// dummy device under -d:voidDummy.

when (voidDummy || (windows && !voidVulkan)) {
	import { doorSetup, doorShutdown } from "../gpu/doorGpu.ms";
	import { frameIndex } from "../gpu/door";
	import {
		DrawContext, DrawItem, MeshId, VertexStorage, closeContext, releaseMesh,
	} from "../void3d/draw";
	import { added, litShape } from "./drawHelpers";
	import { LIGHT_UNIFORM_LENGTH, VERTEX_UNIFORM_LENGTH } from "../void3d/gpu3d";
	import {
		Renderer, RendererError, RENDERER_UNIFORM_LENGTH, beginFrame, closeRenderer,
	} from "../void3d/renderer";
}
when (windows && !voidDummy && !voidVulkan) {
	import { warpDevice, warpContext } from "./d3d11Warp.h";
	@passL("-ld3d11");
}

const RGBA8 = 2;
const NO_DEPTH = 0;

when (voidDummy || (windows && !voidVulkan)) {
	test "a frame refused after a context switch leaves the switch to the next accepted frame" {
		when (voidDummy) {
			doorSetup(null, null, RGBA8, NO_DEPTH, 1);
		} else {
			doorSetup(warpDevice(), warpContext(), RGBA8, NO_DEPTH, 1);
		}
		const context: DrawContext = DrawContext.withUniformCapacity(RENDERER_UNIFORM_LENGTH);
		const made: Result<Renderer, RendererError> = Renderer.create(context);
		assert made.ok;
		if (!made.ok) { return; }
		const renderer: Renderer = made.value;
		const dynamic: MeshId = added(context, litShape());
		context.meshStorage[dynamic.index] = VertexStorage.Pending;
		context.meshes[dynamic.index].writtenFrame = frameIndex();
		const camera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
		const lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
		const items: Vec<DrawItem> = [];
		const refused: Result<boolean, RendererError> = beginFrame(renderer, items, camera, lights);
		assert !refused.ok && refused.error == RendererError.MeshWrite;
		context.meshStorage[dynamic.index] = VertexStorage.Dynamic;
		const adopted: Result<boolean, RendererError> = beginFrame(renderer, items, camera, lights);
		assert adopted.ok && adopted.value;
		const settled: Result<boolean, RendererError> = beginFrame(renderer, items, camera, lights);
		assert settled.ok && !settled.value;
		assert releaseMesh(context, dynamic).ok;
		closeRenderer(renderer);
		closeContext(context);
		doorShutdown();
	}
}
