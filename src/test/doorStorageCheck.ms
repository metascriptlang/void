// Storage through the door: a render program whose vertex stage reads a storage buffer declares
// its slot, a draw binds a range of the buffer at an offset, and an indexed indirect draw reads the
// same binding. The colours are read back on d3d11, which executes the draws.

import { shaderProgram } from "../shader/program";
import { Vec2f, Vec4f, access, binding, builtin, vec4f } from "../shader/std";
import { Compare, Face, RenderState } from "../gpu/state";
import { PassState, PixelFormat, renderCallRefusal } from "../gpu/doorGpu.ms";
import { TargetLayout } from "../gpu/target";
import { programLayout, storageSlotMask, textureSlotMask } from "../gpu/door";

const STORAGE_SLOT = 2;

struct QuadInput {
	position: Vec2f;
}

struct TintVarying {
	@builtin(position) position: Vec4f;
	color: Vec4f;
}

struct TintFragment {
	color: Vec4f;
}

export struct Tint {
	color: Vec4f;
}

struct TintBindings {
	@binding(2) @access(read) tints: Tint[];
}

function tintVs(input: QuadInput, b: TintBindings): TintVarying {
	return {
		position: vec4f(input.position.x, input.position.y, 0.0, 1.0),
		color: b.tints[0].color,
	};
}

function tintFs(input: TintFragment): Vec4f {
	return input.color;
}

shaderProgram(tinted, tintVs, tintFs);

function plain(): RenderState {
	return RenderState.defaults().withCulling(Face.None).withDepth(false, Compare.Always);
}

test "a program whose vertex stage reads a storage buffer declares that view slot and no texture" {
	assert storageSlotMask(tinted) == ((1 as uint32) << (STORAGE_SLOT as uint32));
	assert textureSlotMask(tinted) == 0;
}

test "drawIndirect inside a compute pass is refused naming the call" {
	assert renderCallRefusal("drawIndirect", PassState.Compute)
		== "drawIndirect inside a compute pass; endComputePass ends it";
	assert renderCallRefusal("drawIndirect", PassState.Target) == "";
}

when (voidDummy || (windows && !voidVulkan)) {
	import { Vec4 } from "../math/math3d";
	import {
		DOOR_BUFFER_INDEX,
		DOOR_BUFFER_INDIRECT,
		DOOR_BUFFER_STORAGE,
		DOOR_BUFFER_VERTEX,
		DoorStorageBinding,
		LoadAction,
		doorMakeBufferOf,
		doorReadTexture,
		doorSetup,
		doorShutdown,
	} from "../gpu/doorGpu.ms";
	import { endPass } from "../gpu/door";
	import { BINDING_INDEX_BUFFER, BINDING_LENGTH, applyPipeline, applyStorageBindings, draw, drawIndirect } from "../gpu/draw";
	import { ColorAttachment, NO_DEPTH, RenderTarget, beginPass, layoutOf } from "../gpu/target";
	import { PipelineCache, closePipelines, pipelineFor } from "../gpu/pipeline";
}
when (windows && !voidDummy && !voidVulkan) {
	import { warpDevice, warpContext } from "./d3d11Warp.h";
	@passL("-ld3d11");
}

const RGBA8 = 2;
const NO_DEPTH_FORMAT = 0;
const SIZE = 8;
const SECOND_TINT_BYTES: int64 = 256;

when (voidDummy || (windows && !voidVulkan)) {
	struct Scene {
		color: RenderTarget;
		layout: TargetLayout;
		vertices: uint32;
		tints: uint32;
		cache: PipelineCache;
	}

	function quad(): Vec<float32> {
		return [-1, -1, 1, -1, 1, 1, -1, -1, 1, 1, -1, 1];
	}

	// Green at byte 0 and red at byte 256, so only a binding at the offset draws red.
	function tintWords(): Vec<float32> {
		let floats: Vec<float32> = new Array(128);
		for (let i = 0; i < 128; i++) { floats[i] = 0.0; }
		floats[1] = 1.0;
		floats[3] = 1.0;
		floats[64] = 1.0;
		floats[67] = 1.0;
		return floats;
	}

	function openScene(): Scene {
		when (voidDummy) {
			doorSetup(null, null, RGBA8, NO_DEPTH_FORMAT, 1);
		} else {
			doorSetup(warpDevice(), warpContext(), RGBA8, NO_DEPTH_FORMAT, 1);
		}
		const color: RenderTarget = RenderTarget.allocate(SIZE, SIZE, PixelFormat.Rgba8, false);
		const black: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };
		return {
			color,
			layout: layoutOf([color.asColor(LoadAction.Clear, black)], NO_DEPTH),
			vertices: doorMakeBufferOf(DOOR_BUFFER_VERTEX, quad()),
			tints: doorMakeBufferOf(DOOR_BUFFER_STORAGE, tintWords()),
			cache: PipelineCache.empty(),
		};
	}

	function closeScene(scene: Scene): void {
		closePipelines(scene.cache);
		scene.color.close();
		doorShutdown();
	}

	function beginColorPass(scene: Scene): void {
		const black: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };
		const colors: Vec<ColorAttachment> = [scene.color.asColor(LoadAction.Clear, black)];
		beginPass(colors, NO_DEPTH);
	}

	function bindingWords(scene: Scene, indices: uint32): Vec<uint32> {
		let words: Vec<uint32> = [];
		for (let i = 0; i < BINDING_LENGTH; i++) { words.push(0); }
		words[0] = scene.vertices;
		words[BINDING_INDEX_BUFFER] = indices;
		return words;
	}

	function secondTint(scene: Scene): Vec<DoorStorageBinding> {
		let storage: Vec<DoorStorageBinding> = [];
		for (let i = 0; i <= STORAGE_SLOT; i++) { storage.push({ buffer: 0, offset: 0, size: 0 }); }
		storage[STORAGE_SLOT] = { buffer: scene.tints, offset: SECOND_TINT_BYTES, size: 16 };
		return storage;
	}

	function drawTinted(scene: Scene): void {
		applyPipeline(pipelineFor(scene.cache, tinted, programLayout(tinted), false, plain(), scene.layout));
		applyStorageBindings(bindingWords(scene, 0), secondTint(scene));
		draw(0, 6, 1);
	}

	function drawTintedIndirect(scene: Scene): void {
		const indices: Vec<uint16> = [0, 1, 2, 3, 4, 5];
		const record: Vec<uint32> = [6, 1, 0, 0, 0];
		applyPipeline(pipelineFor(scene.cache, tinted, programLayout(tinted), true, plain(), scene.layout));
		applyStorageBindings(
			bindingWords(scene, doorMakeBufferOf(DOOR_BUFFER_INDEX, indices)),
			secondTint(scene),
		);
		drawIndirect(doorMakeBufferOf(DOOR_BUFFER_INDIRECT, record), 0, 1);
	}

	test "a vertex stage reads the storage range bound at an offset, drawn directly and indirectly" {
		const scene: Scene = openScene();
		beginColorPass(scene);
		drawTinted(scene);
		endPass();
		when (windows && !voidDummy) { assert pixelAt(scene.color.image, 4, 4) == RED; }
		beginColorPass(scene);
		drawTintedIndirect(scene);
		endPass();
		when (windows && !voidDummy) { assert pixelAt(scene.color.image, 4, 4) == RED; }
		closeScene(scene);
	}
}

when (windows && !voidDummy && !voidVulkan) {
	const RED: uint32 = 0xFF0000FF;

	// The pixel of column `x` and row `y` as 0xAABBGGRR.
	function pixelAt(image: uint32, x: int32, y: int32): uint32 {
		let out: Vec<uint8> = new Array(SIZE * SIZE * 4);
		if (doorReadTexture(image, 0, 0, SIZE, SIZE, out) != 1) {
			console.log("doorStorageCheck: readTexture refused the target");
			unreachable;
		}
		const at: int32 = (y * SIZE + x) * 4;
		return (out[at] as uint32) | ((out[at + 1] as uint32) << 8) |
			((out[at + 2] as uint32) << 16) | ((out[at + 3] as uint32) << 24);
	}
}
