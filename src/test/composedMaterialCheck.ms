import {
	EMISSIVE_COLOR,
	EMISSIVE_STRENGTH,
	MATERIAL_UNIFORM_SLOT,
	MOVING_DISSOLVE_EDGE_COLOR,
	MOVING_DISSOLVE_EDGE_WIDTH,
	MOVING_DISSOLVE_THRESHOLD,
	MOVING_UV_MATRIX,
	MOVING_UV_OFFSET,
	Program,
	ProgramKey,
	emissiveBase,
	movingBase,
	uniformBlockLength,
} from "../void3d/gpu3d";
import { DrawContext, reserveBlock } from "../void3d/draw";
import { UniformBlock, movingDefaults } from "../void3d/material";
import {
	movingEmissiveParams,
	movingParams,
	movingUnlitParams,
	writeMaterialParams,
} from "../void3d/composedMaterial";
import {
	MovingEmissiveMaterialParams,
	MovingMaterialParams,
	MovingUnlitMaterialParams,
} from "../void3d/shader3d";
import { sameLanes } from "./helpers";

function movingOffsetFloats(key: ProgramKey): Vec<float32> {
	let values: Vec<float32> = movingDefaults(key);
	const base: int32 = movingBase(key);
	values[base + MOVING_UV_MATRIX] = 0.5;
	values[base + MOVING_UV_MATRIX + 3] = 2.0;
	values[base + MOVING_UV_OFFSET] = 0.25;
	values[base + MOVING_UV_OFFSET + 1] = 0.75;
	values[base + MOVING_DISSOLVE_THRESHOLD] = 0.4;
	values[base + MOVING_DISSOLVE_EDGE_WIDTH] = 0.125;
	const edge: int32 = base + MOVING_DISSOLVE_EDGE_COLOR;
	values[edge] = 1.0;
	values[edge + 1] = 0.45;
	values[edge + 2] = 0.05;
	values[edge + 3] = 1.0;
	return values;
}

function writtenFloats<T>(key: ProgramKey, params: T): Vec<float32> {
	const length: int32 = uniformBlockLength(key, MATERIAL_UNIFORM_SLOT);
	let context: DrawContext = DrawContext.withUniformCapacity(length);
	const reserved = reserveBlock<T>(context, MATERIAL_UNIFORM_SLOT);
	if (!reserved.ok) { throw new Error("internal: reserveBlock refused the block"); }
	const block: UniformBlock = reserved.value.block;
	const written = writeMaterialParams(context, block, params);
	if (!written.ok) { throw new Error("internal: writeMaterialParams refused the value"); }
	let out: Vec<float32> = new Array(length);
	for (let i = 0; i < out.length; i++) { out[i] = context.uniforms.values[block.offset + i]; }
	return out;
}

test "a lit dissolve with a UV transform writes the floats the MOVING_ offsets write" {
	const key: ProgramKey = ProgramKey.of(Program.LitTextured).withUvTransform().withBackTexture()
		.withDissolve();
	let params: MovingMaterialParams = movingParams();
	params.uvMatrix = { x: 0.5, y: 0, z: 0, w: 2 };
	params.uvMotion = { x: 0.25, y: 0.75, z: 0, w: 0 };
	params.dissolve = { x: 0.4, y: 0.125, z: 0, w: 0 };
	params.dissolveEdge = { x: 1, y: 0.45, z: 0.05, w: 1 };
	assert sameLanes(writtenFloats(key, params), movingOffsetFloats(key)), "lit moving block lanes";
}

test "an unlit dissolve with a UV transform writes the floats the MOVING_ offsets write" {
	const key: ProgramKey = ProgramKey.of(Program.UnlitTextured).withUvTransform().withBackTexture()
		.withDissolve();
	let params: MovingUnlitMaterialParams = movingUnlitParams();
	params.uvMatrix = { x: 0.5, y: 0, z: 0, w: 2 };
	params.uvMotion = { x: 0.25, y: 0.75, z: 0, w: 0 };
	params.dissolve = { x: 0.4, y: 0.125, z: 0, w: 0 };
	params.dissolveEdge = { x: 1, y: 0.45, z: 0.05, w: 1 };
	assert sameLanes(writtenFloats(key, params), movingOffsetFloats(key)),
		"unlit moving block lanes";
}

test "an emissive dissolve adds the emissive vec4 after the moving floats" {
	const key: ProgramKey =
		ProgramKey.of(Program.LitTextured).withDissolve().withEmissive();
	let params: MovingEmissiveMaterialParams = movingEmissiveParams();
	params.uvMatrix = { x: 0.5, y: 0, z: 0, w: 2 };
	params.uvMotion = { x: 0.25, y: 0.75, z: 0, w: 0 };
	params.dissolve = { x: 0.4, y: 0.125, z: 0, w: 0 };
	params.dissolveEdge = { x: 1, y: 0.45, z: 0.05, w: 1 };
	params.emissive = { x: 0.1, y: 0.2, z: 0.3, w: 5 };
	let expected: Vec<float32> = movingOffsetFloats(key);
	const at: int32 = emissiveBase(key);
	expected[at + EMISSIVE_COLOR] = 0.1;
	expected[at + EMISSIVE_COLOR + 1] = 0.2;
	expected[at + EMISSIVE_COLOR + 2] = 0.3;
	expected[at + EMISSIVE_STRENGTH] = 5.0;
	assert sameLanes(writtenFloats(key, params), expected), "emissive moving block lanes";
}

test "a value of another block's struct is refused by length" {
	const key: ProgramKey = ProgramKey.of(Program.LitTextured).withUvTransform().withBackTexture()
		.withDissolve();
	let context: DrawContext =
		DrawContext.withUniformCapacity(uniformBlockLength(key, MATERIAL_UNIFORM_SLOT));
	const block = reserveBlock<MovingMaterialParams>(context, MATERIAL_UNIFORM_SLOT);
	assert block.ok, "reserveBlock for the moving block";
	if (!block.ok) { return; }
	const written = writeMaterialParams(context, block.value.block, movingEmissiveParams());
	assert !written.ok, "a longer struct is refused by length";
}
