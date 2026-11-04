// A vertex stage that reads a row of a storage buffer at a slot index carried by an instance-rate
// uint32 attribute: the resident-row path of void3d. Instance 0 names row 3 and instance 1 row 1,
// so a row picked by instance_index or firstInstance instead of the slot draws the wrong colours.
// Read back on d3d11 (WARP) and Metal.

import { shaderModule, shaderProgram, shaderProgramRegister } from "../shader/program";
import { programModule, stageSource, stageWords } from "../shader/descriptor";
import { glslIr, glslLinkedIr } from "../shader/emit";
import { ShaderTarget } from "../shader/layout";
import { Vec2f, Vec4f, access, binding, builtin, vec4f } from "../shader/std";
import { Compare, Face, RenderState } from "../gpu/state";
import { DoorLayout, doorLayout } from "../gpu/doorGpu.ms";
import { Feature, featureOn } from "../gpu/feature.ms";
import { GPUSupportedFeatures, GPUSupportedLimits } from "../webgpu/types.ms";
import { storageSlotMask } from "../gpu/door";

const ROW_SLOT = 14;

struct SlotInput {
	position: Vec2f;
	slot: uint32;
}

struct RowVarying {
	@builtin(position) position: Vec4f;
	color: Vec4f;
}

struct RowFragment {
	color: Vec4f;
}

export struct WorldRow {
	row0: Vec4f;
	row1: Vec4f;
	row2: Vec4f;
	color: Vec4f;
}

struct RowBindings {
	@binding(14) @access(read) rows: WorldRow[];
}

export function rowVs(input: SlotInput, b: RowBindings): RowVarying {
	const row = b.rows[input.slot];
	return {
		position: vec4f(input.position.x + row.row0.w, input.position.y, 0.0, 1.0),
		color: row.color,
	};
}

export function rowFs(input: RowFragment): Vec4f {
	return input.color;
}

shaderModule(row, rowVs, rowFs);
shaderProgram(slotted, rowVs, rowFs);

// The mesh position at location 0 per vertex and the slot at location 1 per instance, the
// locations the IR gives SlotInput's fields in declaration order.
function slotLayout(): DoorLayout {
	return doorLayout([
		{ location: 0, format: "float32x2", buffer: 0 },
		{ location: 1, format: "uint32", buffer: 1 },
	], ["vertex", "instance"]);
}

test "the door packs a uint32 instance attribute four bytes wide in its own buffer" {
	const layout = slotLayout();
	assert layout.buffers[0].arrayStride == 8 && layout.buffers[1].arrayStride == 4;
	assert layout.buffers[1].stepMode == "instance" && layout.buffers[1].attributes[0].format == "uint32";
	assert layout.buffers[1].attributes[0].shaderLocation == 1;
}

function limitsWith(vertexStorage: int32): GPUSupportedLimits {
	return { maxStorageBuffersPerShaderStage: 8, maxStorageBuffersInVertexStage: vertexStorage };
}

test "VertexStorage reads the vertex stage's own storage limit, not the per-stage one" {
	const none: GPUSupportedFeatures = { bits: 0 };
	assert featureOn(Feature.VertexStorage, limitsWith(8), none);
	assert !featureOn(Feature.VertexStorage, limitsWith(0), none);
	assert featureOn(Feature.StorageBuffers, limitsWith(0), none);
}

function vertexText(target: ShaderTarget): string {
	const m = programModule(glslIr(rowVs), glslLinkedIr(rowFs, rowVs), []);
	if (!m.ok) { return m.error; }
	const text = stageSource(m.value, 0, target);
	return text.ok ? text.value : text.error;
}

test "every printer takes a uint32 vertex input, and GLSL ES 3.00 refuses the storage it indexes" {
	assert vertexText(ShaderTarget.Wgsl).includes("@location(1) slot_param : u32");
	assert vertexText(ShaderTarget.Hlsl5).includes("uint slot : TEXCOORD1;");
	assert vertexText(ShaderTarget.Glsl430).includes("layout(location = 1) in uint slot;");
	assert vertexText(ShaderTarget.Msl).includes("uint slot [[attribute(1)]];");
	assert vertexText(ShaderTarget.Glsl300es).endsWith("GLSL ES 3.0 has no storage resources");
	const m = programModule(glslIr(rowVs), glslLinkedIr(rowFs, rowVs), []);
	assert m.ok && stageWords(m.value, 0).ok;
}

test "a vertex stage reading rows at binding 14 declares that storage slot, in a shaderProgram too" {
	assert storageSlotMask(slotted) == ((1 as uint32) << (ROW_SLOT as uint32));
	const program = shaderProgramRegister(rowModule, slotLayout());
	assert storageSlotMask(program) == ((1 as uint32) << (ROW_SLOT as uint32));
}

when (voidDummy || (windows && !voidVulkan) || macos) {
	import { Vec4 } from "../math/math3d";
	import {
		DOOR_BUFFER_STORAGE,
		DOOR_BUFFER_VERTEX,
		DoorStorageBinding,
		LoadAction,
		PixelFormat,
		doorMakeBufferOf,
		doorReadTexture,
		doorSetup,
		doorShutdown,
	} from "../gpu/doorGpu.ms";
	import { endPass, programLayout } from "../gpu/door";
	import { BINDING_LENGTH, BINDING_VERTEX_BUFFER, applyPipeline, applyStorageBindings, draw } from "../gpu/draw";
	import { ColorAttachment, NO_DEPTH, RenderTarget, beginPass, layoutOf } from "../gpu/target";
	import { PipelineCache, closePipelines, pipelineFor } from "../gpu/pipeline";
	import { hasFeature } from "../gpu/feature.ms";
}
when (windows && !voidDummy && !voidVulkan) {
	import { warpDevice, warpContext } from "./d3d11Warp.h";
	@passL("-ld3d11");
}
when (macos && !voidDummy) {
	import { metalSystemDevice } from "./metalDevice.h";
	@compile("./metalDevice.m");
}

const RGBA8 = 2;
const NO_DEPTH_FORMAT = 0;
const SIZE = 8;
const RED: uint32 = 0xFF0000FF;
const GREEN: uint32 = 0xFF00FF00;

when (voidDummy || (windows && !voidVulkan) || macos) {
	function openDoor(): void {
		when (voidDummy) {
			doorSetup(null, null, RGBA8, NO_DEPTH_FORMAT, 1);
		} else when (windows) {
			doorSetup(warpDevice(), warpContext(), RGBA8, NO_DEPTH_FORMAT, 1);
		} else {
			doorSetup(metalSystemDevice(), null, RGBA8, NO_DEPTH_FORMAT, 1);
		}
	}

	// A quad over the left half of the target; a row's row0.w moves it right by that much.
	function leftQuad(): Vec<float32> {
		return [-1, -1, 0, -1, 0, 1, -1, -1, 0, 1, -1, 1];
	}

	// Rows 0 and 2 blue at the left, row 1 green moved right, row 3 red at the left.
	function rows(): Vec<float32> {
		let floats: Vec<float32> = new Array(64);
		for (let i = 0; i < 64; i++) { floats[i] = 0.0; }
		for (let r = 0; r < 4; r++) { floats[r * 16 + 15] = 1.0; }
		floats[0 * 16 + 14] = 1.0;
		floats[2 * 16 + 14] = 1.0;
		floats[1 * 16 + 3] = 1.0;
		floats[1 * 16 + 13] = 1.0;
		floats[3 * 16 + 12] = 1.0;
		return floats;
	}

	// The pixel of column `x` and row `y` as 0xAABBGGRR.
	function pixelAt(image: uint32, x: int32, y: int32): uint32 {
		let out: Vec<uint8> = new Array(SIZE * SIZE * 4);
		if (doorReadTexture(image, 0, 0, SIZE, SIZE, out) != 1) {
			console.log("doorVertexStorageCheck: readTexture refused the target");
			unreachable;
		}
		const at: int32 = (y * SIZE + x) * 4;
		return (out[at] as uint32) | ((out[at + 1] as uint32) << 8) |
			((out[at + 2] as uint32) << 16) | ((out[at + 3] as uint32) << 24);
	}

	test "each instance reads the row its uint32 slot names, not the row of its instance index" {
		openDoor();
		assert hasFeature(Feature.VertexStorage);
		const black: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };
		const color: RenderTarget = RenderTarget.allocate(SIZE, SIZE, PixelFormat.Rgba8, false);
		const colors: Vec<ColorAttachment> = [color.asColor(LoadAction.Clear, black)];
		let cache = PipelineCache.empty();
		const program = shaderProgramRegister(rowModule, slotLayout());
		const slots: Vec<uint32> = [3, 1];
		let words: Vec<uint32> = [];
		for (let i = 0; i < BINDING_LENGTH; i++) { words.push(0); }
		words[BINDING_VERTEX_BUFFER] = doorMakeBufferOf(DOOR_BUFFER_VERTEX, leftQuad());
		words[BINDING_VERTEX_BUFFER + 1] = doorMakeBufferOf(DOOR_BUFFER_VERTEX, slots);
		let storage: Vec<DoorStorageBinding> = [];
		for (let i = 0; i <= ROW_SLOT; i++) { storage.push({ buffer: 0, offset: 0, size: 0 }); }
		storage[ROW_SLOT] = { buffer: doorMakeBufferOf(DOOR_BUFFER_STORAGE, rows()), offset: 0, size: 256 };
		const state = RenderState.defaults().withCulling(Face.None).withDepth(false, Compare.Always);
		beginPass(colors, NO_DEPTH);
		applyPipeline(pipelineFor(cache, program, programLayout(program), false, state, layoutOf(colors, NO_DEPTH)));
		applyStorageBindings(words, storage);
		draw(0, 6, 2);
		endPass();
		when (!voidDummy) {
			assert pixelAt(color.image, 2, 4) == RED;
			assert pixelAt(color.image, 6, 4) == GREEN;
		}
		closePipelines(cache);
		color.close();
		doorShutdown();
	}
}
