// T0 - the instance attributes the door registers against what generates and consumes them.
//
// scripts/instanceLayout.ms is the one description of the lanes. programs.ms builds the
// registered layouts from it, displayList.ms and batcher.ms write the records and the GPU
// struct from it, and the shader declares the same lanes by hand as attribute struct fields. The first
// three consumers share names with the generator; the shader does not, so its field
// order is read here, because a swapped pair compiles, links and draws wrong pixels.

import { programModule } from "../shader/descriptor";
import { glslIr, glslLinkedIr } from "../shader/emit";
import { Builtin, IoDirection, ShaderStage } from "../shader/ir";
import { spriteFs, spriteVs, uiFs, uiVs } from "../void2d/shader2d";
import { packUiInstance } from "../void2d/batcher";
import { floatBits } from "../void2d/floatBits";
import { doorLayout } from "../gpu/doorGpu";
import { spriteAttributes, uiAttributes } from "../void2d/programs";
import { spriteShaderModule, uiShaderModule } from "../void2d/shader2dModules";
import {
	INSTANCE_CORNER_LOCATION, SPRITE_AFFINE, SPRITE_ORIGIN_SIZE, SPRITE_UV, SPRITE_COLOR,
	SPRITE_STRIDE, SPRITE_ATTRIBUTES, SPRITE_NAMES, UI_AFFINE, UI_ORIGIN_SIZE, UI_UV_RADII,
	UI_BORDERS, UI_PARAMS0, UI_PARAMS1, UI_COLOR_FILL, UI_COLOR_BORDER, UI_COLOR_EXTRA,
	UI_STRIDE, UI_ATTRIBUTES, UI_NAMES, REC_UI_AFFINE, REC_UI_ORIGIN_SIZE, REC_UI_UV_RADII,
	REC_UI_BORDERS, REC_UI_PARAMS0, REC_UI_PARAMS1, REC_UI_COLOR_FILL, REC_UI_COLOR_BORDER,
	REC_UI_COLOR_EXTRA, REC_UI_FLOATS, REC_SPRITE_AFFINE, REC_SPRITE_ORIGIN_SIZE, REC_SPRITE_UV,
	REC_SPRITE_COLOR, REC_SPRITE_FLOATS,
} from "../void2d/instanceLayout";

const CORNER_BYTES: int32 = 8;

// The vertex stage's attributes in the IR's order, which every printer numbers locations by.
function vertexInputs(vertex: string, fragment: string): string[] {
	const m = programModule(vertex, fragment, []);
	if (!m.ok) { return []; }
	return m.value.ios.filter((io) => io.stage == ShaderStage.Vertex &&
		io.direction == IoDirection.In && io.builtin == Builtin.None).map((io) => io.name);
}

test "the UI instance buffer the door registers has the generated offsets and stride" {
	const layout = doorLayout(uiAttributes(), ["vertex", "instance"]);
	const lanes = layout.buffers[1];
	const offsets: int32[UI_ATTRIBUTES] = [
		UI_AFFINE, UI_ORIGIN_SIZE, UI_UV_RADII, UI_BORDERS, UI_PARAMS0, UI_PARAMS1,
		UI_COLOR_FILL, UI_COLOR_BORDER, UI_COLOR_EXTRA,
	];
	assert lanes.arrayStride == UI_STRIDE;
	assert layout.buffers[0].arrayStride == CORNER_BYTES;
	assert layout.buffers[0].attributes[0].shaderLocation == INSTANCE_CORNER_LOCATION;
	for (let i = 0; i < UI_ATTRIBUTES; i++) {
		assert lanes.attributes[i].offset == offsets[i];
		assert lanes.attributes[i].shaderLocation == INSTANCE_CORNER_LOCATION + 1 + i;
	}
}

test "the sprite instance buffer the door registers has the generated offsets and stride" {
	const layout = doorLayout(spriteAttributes(), ["vertex", "instance"]);
	const lanes = layout.buffers[1];
	const offsets: int32[SPRITE_ATTRIBUTES] = [
		SPRITE_AFFINE, SPRITE_ORIGIN_SIZE, SPRITE_UV, SPRITE_COLOR,
	];
	assert lanes.arrayStride == SPRITE_STRIDE;
	for (let i = 0; i < SPRITE_ATTRIBUTES; i++) {
		assert lanes.attributes[i].offset == offsets[i];
		assert lanes.attributes[i].shaderLocation == INSTANCE_CORNER_LOCATION + 1 + i;
	}
}

test "the UI packer writes each record lane at the byte offset the registered layout names" {
	let records: float32[] = [];
	for (let i = 0; i < REC_UI_FLOATS * 3; i++) { records.push((i + 1) as float32); }
	for (let k = 0; k < 3; k++) {
		const at = REC_UI_FLOATS * k;
		records[at + REC_UI_COLOR_FILL] = 1.0; records[at + REC_UI_COLOR_FILL + 1] = 0.0;
		records[at + REC_UI_COLOR_FILL + 2] = 0.0; records[at + REC_UI_COLOR_FILL + 3] = 1.0;
		records[at + REC_UI_COLOR_BORDER] = 0.0; records[at + REC_UI_COLOR_BORDER + 1] = 1.0;
		records[at + REC_UI_COLOR_BORDER + 2] = 0.0; records[at + REC_UI_COLOR_BORDER + 3] = 1.0;
		records[at + REC_UI_COLOR_EXTRA] = 0.0; records[at + REC_UI_COLOR_EXTRA + 1] = 0.0;
		records[at + REC_UI_COLOR_EXTRA + 2] = 1.0; records[at + REC_UI_COLOR_EXTRA + 3] = 1.0;
	}
	const words = UI_STRIDE / 4;
	const stage: uint32[] = [];
	for (let i = 0; i < words * 3; i++) { stage.push(0xDEADBEEF); }
	packUiInstance(stage, 1, records[0..records.length as int32]);
	const floatLanes: int32[6] = [
		UI_AFFINE, UI_ORIGIN_SIZE, UI_UV_RADII, UI_BORDERS, UI_PARAMS0, UI_PARAMS1,
	];
	const recordLanes: int32[6] = [
		REC_UI_AFFINE, REC_UI_ORIGIN_SIZE, REC_UI_UV_RADII, REC_UI_BORDERS, REC_UI_PARAMS0,
		REC_UI_PARAMS1,
	];
	for (let l = 0; l < 6; l++) {
		for (let c = 0; c < 4; c++) {
			assert stage[words + floatLanes[l] / 4 + c] ==
				floatBits(records[REC_UI_FLOATS + recordLanes[l] + c]);
		}
	}
	assert stage[words + UI_COLOR_FILL / 4] == 0xFF0000FF;
	assert stage[words + UI_COLOR_BORDER / 4] == 0xFF00FF00;
	assert stage[words + UI_COLOR_EXTRA / 4] == 0xFFFF0000;
	for (let i = 0; i < words; i++) {
		assert stage[i] == 0xDEADBEEF;
		assert stage[words * 2 + i] == 0xDEADBEEF;
	}
}

test "the sprite record is the sprite lane layout word for word" {
	assert SPRITE_STRIDE == REC_SPRITE_FLOATS * 4;
	assert SPRITE_AFFINE == REC_SPRITE_AFFINE * 4;
	assert SPRITE_ORIGIN_SIZE == REC_SPRITE_ORIGIN_SIZE * 4;
	assert SPRITE_UV == REC_SPRITE_UV * 4;
	assert SPRITE_COLOR == REC_SPRITE_COLOR * 4;
	assert UI_STRIDE == (REC_UI_FLOATS - 3 * 4) * 4 + 3 * 4;
}

test "the UI vertex shader declares the generated lanes in the generated order" {
	const inputs = vertexInputs(glslIr(uiVs), glslLinkedIr(uiFs, uiVs));
	assert inputs.length == UI_ATTRIBUTES + 1;
	assert inputs[INSTANCE_CORNER_LOCATION] == "corner";
	for (let i = 0; i < UI_ATTRIBUTES; i++) {
		assert inputs[INSTANCE_CORNER_LOCATION + 1 + i] == UI_NAMES[i];
	}
}

test "the sprite vertex shader declares the generated lanes in the generated order" {
	const inputs = vertexInputs(glslIr(spriteVs), glslLinkedIr(spriteFs, spriteVs));
	assert inputs.length == SPRITE_ATTRIBUTES + 1;
	assert inputs[INSTANCE_CORNER_LOCATION] == "corner";
	for (let i = 0; i < SPRITE_ATTRIBUTES; i++) {
		assert inputs[INSTANCE_CORNER_LOCATION + 1 + i] == SPRITE_NAMES[i];
	}
}

test "the compiled shader modules reflect the locations the layouts register" {
	const ui = uiShaderModule();
	for (let i = 0; i <= UI_ATTRIBUTES; i++) {
		assert ui.attributes[i].location == i;
	}
	const sprite = spriteShaderModule();
	for (let i = 0; i <= SPRITE_ATTRIBUTES; i++) {
		assert sprite.attributes[i].location == i;
	}
}
