// What the door issues per draw: a bind group is made for the slots the program reads, a draw
// whose bindings match the last ones issues no binding call again, and the uniform blocks applied
// before a draw reach the device in one write.

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

struct ColorBlock {
	color: Vec4f;
}

struct GainBlock {
	gain: Vec4f;
}

struct TintBindings {
	@binding(0) colorBlock: ColorBlock;
	@binding(1) gainBlock: GainBlock;
}

function tintFs(b: TintBindings): Vec4f {
	return b.colorBlock.color * b.gainBlock.gain;
}

shaderProgram(tinted, quadVs, tintFs);

when (voidDummy || (windows && !voidVulkan)) {
	import { Vec4 } from "../math/math3d";
	import {
		DOOR_BUFFER_VERTEX,
		doorApplyBindings,
		doorApplyPipeline,
		doorApplyUniformsOf,
		doorDraw,
		doorReadTexture,
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
		tintPipeline: uint32;
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
		const quad: Vec<float32> = [
			-1, -1, 1, -1, 1, 1, -1, -1, 1, 1, -1, 1,
			-1, -1, 0, -1, 0, 1, -1, -1, 0, 1, -1, 1,
			0, -1, 1, -1, 1, 1, 0, -1, 1, 1, 0, 1,
		];
		return {
			color,
			layout,
			vertices: doorMakeBufferOf(DOOR_BUFFER_VERTEX, quad),
			view: doorMakeTextureView(doorMakeImage(white, 2, 2)),
			sampler: doorMakeSampler(0, 0),
			pipeline: pipelineFor(cache, picture, programLayout(picture), false, state, layout),
			tintPipeline: pipelineFor(cache, tinted, programLayout(tinted), false, state, layout),
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

	test "a draw that changes only slots its program does not read issues no binding call, and a new pass binds again" {
		const scene: Scene = openScene();
		beginScene(scene);
		drawWith(scene, 0);
		const vertexAndGroup: int64 = doorBindStats().bindCalls;
		assert vertexAndGroup == 2;
		drawWith(scene, 0);
		drawWith(scene, 777);
		assert doorBindStats().bindCalls == vertexAndGroup;
		endPass();
		beginScene(scene);
		drawWith(scene, 0);
		assert doorBindStats().bindCalls == vertexAndGroup * 2;
		endPass();
		closeScene(scene);
	}

	const LEFT = 6;
	const RIGHT = 12;

	function tintDraw(scene: Scene, color: Vec<float32>, first: int32): void {
		doorApplyUniformsOf(0, color);
		doorApplyUniformsOf(1, [1, 1, 1, 1]);
		let words: Vec<uint32> = [];
		for (let i = 0; i < DOOR_BINDING_LENGTH; i++) { words.push(0); }
		words[0] = scene.vertices;
		doorApplyBindings(words, [0]);
		doorDraw(first, 6, 1);
	}

	test "the uniform blocks applied before a draw reach the device in one write and one group bind" {
		const scene: Scene = openScene();
		const black: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };
		beginPass([scene.color.asColor(LoadAction.Clear, black)], NO_DEPTH_ATTACHMENT);
		doorApplyPipeline(scene.tintPipeline);
		const before: int64 = doorBindStats().bindCalls;
		tintDraw(scene, [1, 0, 0, 1], LEFT);
		tintDraw(scene, [0, 1, 0, 1], RIGHT);
		endPass();
		assert doorBindStats().uniformWrites == 2;
		assert doorBindStats().bindCalls == before + 3;
		when (windows && !voidDummy) {
			assert pixelAt(scene, 1, 4) == 0xFF0000FF && pixelAt(scene, 6, 4) == 0xFF00FF00;
		}
		closeScene(scene);
	}

	// The pixel of column `x` and row `y` as 0xAABBGGRR.
	function pixelAt(scene: Scene, x: int32, y: int32): uint32 {
		let out: Vec<uint8> = new Array(SIZE * SIZE * 4);
		if (doorReadTexture(scene.color.image, 0, 0, SIZE, SIZE, out) != 1) {
			console.log("doorBindCheck: readTexture refused the target");
			unreachable;
		}
		const at: int32 = (y * SIZE + x) * 4;
		return (out[at] as uint32) | ((out[at + 1] as uint32) << 8) |
			((out[at + 2] as uint32) << 16) | ((out[at + 3] as uint32) << 24);
	}
}
