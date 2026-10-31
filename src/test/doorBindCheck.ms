// What the door issues per draw: a bind group is made for the slots the program reads, and a draw
// whose bindings match the last ones issues no binding call again.

import { shaderProgram } from "../shader/program";
import { Sampler, Texture2d, Vec2f, Vec4f, binding, builtin, textureSample, vec2f, vec4f } from "../shader/std";
import { Face, RenderState, Compare } from "../gpu/state";
import { PixelFormat } from "../gpu/doorGpu.ms";
import { TargetLayout } from "../gpu/target";
import { DOOR_BINDING_LENGTH, DOOR_BINDING_SAMPLER, DOOR_BINDING_VIEW } from "../gpu/doorWords";
import { endPass, programLayout } from "../gpu/door";

struct QuadInput {
	position: Vec2f;
}

struct QuadVarying {
	@builtin(position) position: Vec4f;
}

struct PictureBindings {
	@binding(0) picture: Texture2d;
	@binding(0) smoothing: Sampler;
}

function quadVs(input: QuadInput): QuadVarying {
	return { position: vec4f(input.position.x, input.position.y, 0.0, 1.0) };
}

function pictureFs(b: PictureBindings): Vec4f {
	return textureSample(b.picture, b.smoothing, vec2f(0.5, 0.5));
}

shaderProgram(picture, quadVs, pictureFs);

when (voidDummy || (windows && !voidVulkan)) {
	import { Vec4 } from "../math/math3d";
	import {
		DOOR_BUFFER_VERTEX,
		doorApplyBindings,
		doorApplyPipeline,
		doorDraw,
		doorBindStats,
		doorMakeBufferOf,
		doorMakeImage,
		doorMakeSampler,
		doorMakeTextureView,
		doorSetup,
		doorShutdown,
		LoadAction,
	} from "../gpu/doorGpu.ms";
	import { NO_DEPTH as NO_DEPTH_ATTACHMENT, RenderTarget, beginPass, layoutOf } from "../gpu/target";
	import { PipelineCache, closePipelines, pipelineFor } from "../gpu/pipeline";
}
when (windows && !voidDummy && !voidVulkan) {
	import { warpDevice, warpContext } from "./d3d11Warp.h";
	@passL("-ld3d11");
}

const RGBA8 = 2;
const NO_DEPTH = 0;
const SIZE = 8;

when (voidDummy || (windows && !voidVulkan)) {
	struct Scene {
		color: RenderTarget;
		layout: TargetLayout;
		vertices: uint32;
		view: uint32;
		sampler: uint32;
		pipeline: uint32;
		cache: PipelineCache;
	}

	function openScene(): Scene {
		when (voidDummy) {
			doorSetup(null, null, RGBA8, NO_DEPTH, 1);
		} else {
			doorSetup(warpDevice(), warpContext(), RGBA8, NO_DEPTH, 1);
		}
		const color: RenderTarget = RenderTarget.allocate(SIZE, SIZE, PixelFormat.Rgba8, false);
		const black: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };
		const layout: TargetLayout = layoutOf(
			[color.asColor(LoadAction.Clear, black)], NO_DEPTH_ATTACHMENT,
		);
		const cache: PipelineCache = PipelineCache.empty();
		const state: RenderState = RenderState.defaults().withCulling(Face.None)
			.withDepth(false, Compare.Always);
		const white: Vec<uint32> = [0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF];
		const quad: Vec<float32> = [-1, -1, 1, -1, 1, 1, -1, -1, 1, 1, -1, 1];
		return {
			color,
			layout,
			vertices: doorMakeBufferOf(DOOR_BUFFER_VERTEX, quad),
			view: doorMakeTextureView(doorMakeImage(white, 2, 2)),
			sampler: doorMakeSampler(0, 0),
			pipeline: pipelineFor(cache, picture, programLayout(picture), false, state, layout),
			cache,
		};
	}

	function closeScene(scene: Scene): void {
		closePipelines(scene.cache);
		scene.color.close();
		doorShutdown();
	}

	function beginScene(scene: Scene): void {
		const black: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };
		beginPass([scene.color.asColor(LoadAction.Clear, black)], NO_DEPTH_ATTACHMENT);
		doorApplyPipeline(scene.pipeline);
	}

	// The program reads view 0 and sampler 0; `stale` fills view slot 3 and sampler slot 5, which
	// it does not read.
	function drawWith(scene: Scene, stale: uint32): void {
		let words: Vec<uint32> = [];
		for (let i = 0; i < DOOR_BINDING_LENGTH; i++) { words.push(0); }
		words[0] = scene.vertices;
		words[DOOR_BINDING_VIEW] = scene.view;
		words[DOOR_BINDING_SAMPLER] = scene.sampler;
		words[DOOR_BINDING_VIEW + 3] = stale;
		words[DOOR_BINDING_SAMPLER + 5] = stale;
		doorApplyBindings(words, [0]);
		doorDraw(0, 6, 1);
	}

	test "two draws that differ only in slots the program does not read share one bind group" {
		const scene: Scene = openScene();
		beginScene(scene);
		drawWith(scene, 0);
		drawWith(scene, 777);
		drawWith(scene, 0);
		endPass();
		assert doorBindStats().groupsMade == 1;
		closeScene(scene);
	}
}
