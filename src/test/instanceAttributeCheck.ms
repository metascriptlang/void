// T0 - the instance attributes the door registers against what generates and consumes them.
//
// scripts/instanceLayout.ms is the one description of the lanes. programs.ms builds the
// registered layouts from it, displayList.ms and batcher.c write the records and the GPU
// struct from it, and the shader declares the same lanes by hand as `in` variables. The first
// three consumers share names with the generator; the shader does not, so its declaration
// order is read here, because a swapped pair compiles, links and draws wrong pixels.

import { readFile } from "std/fs";
import {
	void2dUiInstanceOffset, void2dSpriteInstanceOffset,
} from "../void2d/batcher.h";
import { uiInstanceStride, spriteInstanceStride } from "../void2d/draw";
import { doorLayout } from "../gpu/doorGpu";
import { spriteAttributes, uiAttributes } from "../void2d/programs";
import { spriteShaderModule, uiShaderModule } from "../void2d/shader2dModules";
import {
	INSTANCE_CORNER_LOCATION, SPRITE_AFFINE, SPRITE_ORIGIN_SIZE, SPRITE_UV, SPRITE_COLOR,
	SPRITE_STRIDE, SPRITE_ATTRIBUTES, SPRITE_NAMES, UI_AFFINE, UI_ORIGIN_SIZE, UI_UV_RADII,
	UI_BORDERS, UI_PARAMS0, UI_PARAMS1, UI_COLOR_FILL, UI_COLOR_BORDER, UI_COLOR_EXTRA,
	UI_STRIDE, UI_ATTRIBUTES, UI_NAMES,
} from "../void2d/instanceLayout";

const SHADER: string = "src/void2d/shader2dGen.glsl";
const CORNER_BYTES: int32 = 8;

// The `in` variables of one @vs block, in declaration order.
function vertexInputs(block: string): string[] {
	const names: string[] = [];
	const source = readFile(SHADER);
	if (!source.ok) { return names; }
	let inside = false;
	for (const line of source.value.split("\n")) {
		if (line.startsWith("@vs " + block)) { inside = true; continue; }
		if (inside && line.startsWith("@end")) { break; }
		if (inside && line.startsWith("in ")) {
			const parts = line.trim().split(" ");
			names.push(parts[2].replace(";", ""));
		}
	}
	return names;
}

test "the UI instance buffer the door registers has the generated offsets and stride" {
	assert uiInstanceStride() == UI_STRIDE;
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
		assert void2dUiInstanceOffset(i) == offsets[i];
		assert lanes.attributes[i].offset == offsets[i];
		assert lanes.attributes[i].shaderLocation == INSTANCE_CORNER_LOCATION + 1 + i;
	}
}

test "the sprite instance buffer the door registers has the generated offsets and stride" {
	assert spriteInstanceStride() == SPRITE_STRIDE;
	const layout = doorLayout(spriteAttributes(), ["vertex", "instance"]);
	const lanes = layout.buffers[1];
	const offsets: int32[SPRITE_ATTRIBUTES] = [
		SPRITE_AFFINE, SPRITE_ORIGIN_SIZE, SPRITE_UV, SPRITE_COLOR,
	];
	assert lanes.arrayStride == SPRITE_STRIDE;
	for (let i = 0; i < SPRITE_ATTRIBUTES; i++) {
		assert void2dSpriteInstanceOffset(i) == offsets[i];
		assert lanes.attributes[i].offset == offsets[i];
		assert lanes.attributes[i].shaderLocation == INSTANCE_CORNER_LOCATION + 1 + i;
	}
}

test "the UI vertex shader declares the generated lanes in the generated order" {
	const inputs = vertexInputs("uiVs");
	assert inputs.length == UI_ATTRIBUTES + 1;
	assert inputs[INSTANCE_CORNER_LOCATION] == "corner";
	for (let i = 0; i < UI_ATTRIBUTES; i++) {
		assert inputs[INSTANCE_CORNER_LOCATION + 1 + i] == UI_NAMES[i];
	}
}

test "the sprite vertex shader declares the generated lanes in the generated order" {
	const inputs = vertexInputs("spriteVs");
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
