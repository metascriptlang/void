// The float offsets a material writes by (MOVING_*, PBR_*, MATERIAL_*, EMISSIVE_* in gpu3d.ms) are
// the member offsets of the block the printers lay out, read off the linked program.

import { glslIr, glslLinkedIr } from "../shader/emit";
import { BlockMember } from "../shader/blockMember";
import { ResourceKind } from "../shader/ir";
import { blockMembers } from "../shader/layout";
import { linkedProgram } from "../shader/link";
import { Vec4f } from "../shader/std";
import { uniformSize, writeUniform } from "../shader/uniform";
import { programEffects } from "../void3d/programEffects";
import {
	EMISSIVE_COLOR,
	EMISSIVE_LENGTH,
	EMISSIVE_STRENGTH,
	MATERIAL_ALPHA_KILL,
	MATERIAL_COLOR,
	MATERIAL_DOUBLE_SIDED,
	MATERIAL_PARALLAX,
	MATERIAL_SATURATION,
	MATERIAL_UNIFORM_LENGTH,
	MOVING_BACK_UV_MATRIX,
	MOVING_BACK_UV_OFFSET,
	MOVING_COLOR_KEY,
	MOVING_DISSOLVE_EDGE_COLOR,
	MOVING_DISSOLVE_EDGE_WIDTH,
	MOVING_DISSOLVE_THRESHOLD,
	MOVING_FADE_FAR_END,
	MOVING_FADE_FAR_START,
	MOVING_FADE_NEAR_END,
	MOVING_FADE_NEAR_START,
	MOVING_FLIPBOOK_BLEND,
	MOVING_FLIPBOOK_COLUMNS,
	MOVING_FLIPBOOK_FRAMES,
	MOVING_FLIPBOOK_LOOP,
	MOVING_FLIPBOOK_ROWS,
	MOVING_FLIPBOOK_SPEED,
	MOVING_FLIPBOOK_START_FRAME,
	MOVING_FLIPBOOK_START_TIME,
	MOVING_LENGTH,
	MOVING_SINUS_AMPLITUDE,
	MOVING_SINUS_FREQUENCY,
	MOVING_SINUS_SPEED,
	MOVING_UV_MATRIX,
	MOVING_UV_OFFSET,
	MOVING_UV_SCROLL,
	PBR_MATERIAL_UNIFORM_LENGTH,
	PBR_METALNESS,
	PBR_OCCLUSION,
	PBR_OCCLUSION_STRENGTH,
	PBR_PARALLAX_STEPS,
	PBR_ROUGHNESS,
	PBR_UV_MATRIX,
	PBR_UV_OFFSET,
	PBR_UV_SCROLL,
	UNLIT_MATERIAL_COLOR,
	UNLIT_MATERIAL_UNIFORM_LENGTH,
} from "../void3d/gpu3d";
import {
	MovingEmissiveMaterialParams,
	MovingMaterialParams,
	MovingUnlitMaterialParams,
	PbrEmissiveMaterialParams,
	PbrMaterialParams,
	litTexturedFs,
	litTexturedVs,
	unlitTexturedFs,
	unlitTexturedVs,
} from "../void3d/shader3d";

struct ConstantRow {
	member: string;
	constant: int32;
	component: int32;
}

const LIT_TEXTURED_VS = glslIr(litTexturedVs);
const LIT_TEXTURED_FS = glslLinkedIr(litTexturedFs, litTexturedVs);
const UNLIT_TEXTURED_VS = glslIr(unlitTexturedVs);
const UNLIT_TEXTURED_FS = glslLinkedIr(unlitTexturedFs, unlitTexturedVs);

function membersOf(vertex: string, fragment: string, entry: string, features: string[],
	block: string): BlockMember[] {
	const m = linkedProgram(vertex, fragment, features, programEffects("CORE", entry, features));
	if (!m.ok) { throw new Error("internal: " + entry + " does not link: " + m.error); }
	for (let i = 0; i < m.value.resources.length; i++) {
		const r = m.value.resources[i];
		if (r.kind != ResourceKind.UniformBlock || r.name != block) { continue; }
		const members = blockMembers(m.value, i);
		if (!members.ok) { throw new Error("internal: " + block + ": " + members.error); }
		return members.value;
	}
	throw new Error("internal: " + entry + " has no uniform block " + block);
}

function litMoving(): BlockMember[] {
	return membersOf(LIT_TEXTURED_VS, LIT_TEXTURED_FS, "litTexturedFs",
		["UV_TRANSFORM", "BACK_TEXTURE", "DISSOLVE"], "movingMaterialParams");
}

function litMovingEmissive(): BlockMember[] {
	return membersOf(LIT_TEXTURED_VS, LIT_TEXTURED_FS, "litTexturedFs",
		["DISSOLVE", "EMISSIVE"], "movingEmissiveMaterialParams");
}

function unlitMoving(): BlockMember[] {
	return membersOf(UNLIT_TEXTURED_VS, UNLIT_TEXTURED_FS, "unlitTexturedFs",
		["UV_TRANSFORM", "BACK_TEXTURE", "DISSOLVE"], "movingUnlitMaterialParams");
}

function litPbr(): BlockMember[] {
	return membersOf(LIT_TEXTURED_VS, LIT_TEXTURED_FS, "litTexturedFs", ["PBR"],
		"pbrMaterialParams");
}

function litPbrEmissive(): BlockMember[] {
	return membersOf(LIT_TEXTURED_VS, LIT_TEXTURED_FS, "litTexturedFs", ["PBR", "EMISSIVE"],
		"pbrEmissiveMaterialParams");
}

function indexOf(members: BlockMember[], name: string): int32 {
	for (let i = 0; i < members.length; i++) {
		if (members[i].name == name) { return i; }
	}
	return -1;
}

// A constant names a float: the member's offset plus the component inside it, from `base`.
function disagreements(members: BlockMember[], base: int32, rows: ConstantRow[]): string {
	let out = "";
	for (const row of rows) {
		const name = row.member;
		const constant = row.constant;
		const component = row.component;
		const at = indexOf(members, name);
		if (at < 0) {
			out += " " + name + " is not a member;";
		} else if (members[at].offset + component != base + constant) {
			out += " " + name + "[" + String(component) + "] is at " +
				String(members[at].offset + component) + ", the constant says " +
				String(base + constant) + ";";
		}
	}
	return out;
}

function lengthOf(members: BlockMember[]): int32 {
	const last = members[members.length - 1];
	return last.offset + last.count;
}

function headRows(color: int32): ConstantRow[] {
	return [
		{ member: "material", constant: MATERIAL_PARALLAX, component: 0 },
		{ member: "material", constant: MATERIAL_SATURATION, component: 1 },
		{ member: "material", constant: MATERIAL_DOUBLE_SIDED, component: 2 },
		{ member: "material", constant: MATERIAL_ALPHA_KILL, component: 3 },
		{ member: "materialColor", constant: color, component: 0 },
	];
}

function movingRows(): ConstantRow[] {
	return [
		{ member: "uvMatrix", constant: MOVING_UV_MATRIX, component: 0 },
		{ member: "uvMotion", constant: MOVING_UV_OFFSET, component: 0 },
		{ member: "uvMotion", constant: MOVING_UV_SCROLL, component: 2 },
		{ member: "backUvMatrix", constant: MOVING_BACK_UV_MATRIX, component: 0 },
		{ member: "backUvOffset", constant: MOVING_BACK_UV_OFFSET, component: 0 },
		{ member: "dissolve", constant: MOVING_DISSOLVE_THRESHOLD, component: 0 },
		{ member: "dissolve", constant: MOVING_DISSOLVE_EDGE_WIDTH, component: 1 },
		{ member: "dissolveEdge", constant: MOVING_DISSOLVE_EDGE_COLOR, component: 0 },
		{ member: "flipbookGrid", constant: MOVING_FLIPBOOK_COLUMNS, component: 0 },
		{ member: "flipbookGrid", constant: MOVING_FLIPBOOK_ROWS, component: 1 },
		{ member: "flipbookGrid", constant: MOVING_FLIPBOOK_FRAMES, component: 2 },
		{ member: "flipbookGrid", constant: MOVING_FLIPBOOK_SPEED, component: 3 },
		{ member: "flipbookPlay", constant: MOVING_FLIPBOOK_START_TIME, component: 0 },
		{ member: "flipbookPlay", constant: MOVING_FLIPBOOK_START_FRAME, component: 1 },
		{ member: "flipbookPlay", constant: MOVING_FLIPBOOK_LOOP, component: 2 },
		{ member: "flipbookPlay", constant: MOVING_FLIPBOOK_BLEND, component: 3 },
		{ member: "distanceFade", constant: MOVING_FADE_NEAR_START, component: 0 },
		{ member: "distanceFade", constant: MOVING_FADE_NEAR_END, component: 1 },
		{ member: "distanceFade", constant: MOVING_FADE_FAR_START, component: 2 },
		{ member: "distanceFade", constant: MOVING_FADE_FAR_END, component: 3 },
		{ member: "colorKey", constant: MOVING_COLOR_KEY, component: 0 },
		{ member: "sinusDeform", constant: MOVING_SINUS_SPEED, component: 0 },
		{ member: "sinusDeform", constant: MOVING_SINUS_FREQUENCY, component: 1 },
		{ member: "sinusDeform", constant: MOVING_SINUS_AMPLITUDE, component: 2 },
	];
}

function pbrRows(): ConstantRow[] {
	return [
		{ member: "pbr", constant: PBR_METALNESS, component: 0 },
		{ member: "pbr", constant: PBR_ROUGHNESS, component: 1 },
		{ member: "pbr", constant: PBR_OCCLUSION, component: 2 },
		{ member: "pbr", constant: PBR_OCCLUSION_STRENGTH, component: 3 },
		{ member: "uvMatrix", constant: PBR_UV_MATRIX, component: 0 },
		{ member: "uvMotion", constant: PBR_UV_OFFSET, component: 0 },
		{ member: "uvMotion", constant: PBR_UV_SCROLL, component: 2 },
		{ member: "parallax", constant: PBR_PARALLAX_STEPS, component: 0 },
	];
}

function emissiveRows(): ConstantRow[] {
	return [
		{ member: "emissive", constant: EMISSIVE_COLOR, component: 0 },
		{ member: "emissive", constant: EMISSIVE_STRENGTH, component: 3 },
	];
}

test "a moving key block holds the floats the MOVING_ constants name" {
	const members = litMoving();
	assert members.length == 13;
	assert disagreements(members, 0, headRows(MATERIAL_COLOR)) == "";
	assert disagreements(members, MATERIAL_UNIFORM_LENGTH, movingRows()) == "";
	assert lengthOf(members) == MATERIAL_UNIFORM_LENGTH + MOVING_LENGTH;
}

test "an unlit moving block shares the offsets, from its own base" {
	const members = unlitMoving();
	assert members.length == 13;
	assert disagreements(members, 0, headRows(UNLIT_MATERIAL_COLOR)) == "";
	assert disagreements(members, UNLIT_MATERIAL_UNIFORM_LENGTH, movingRows()) == "";
	assert lengthOf(members) == UNLIT_MATERIAL_UNIFORM_LENGTH + MOVING_LENGTH;
}

test "an emissive moving block is the moving block and then the emissive vec4" {
	const members = litMovingEmissive();
	const plain = litMoving();
	assert members.length == plain.length + 1;
	for (let i = 0; i < plain.length; i++) {
		assert members[i].name == plain[i].name;
		assert members[i].offset == plain[i].offset;
		assert members[i].count == plain[i].count;
	}
	assert disagreements(members, MATERIAL_UNIFORM_LENGTH + MOVING_LENGTH, emissiveRows()) == "";
	assert lengthOf(members) == MATERIAL_UNIFORM_LENGTH + MOVING_LENGTH + EMISSIVE_LENGTH;
}

test "a pbr key block holds the floats the PBR_ constants name" {
	const members = litPbr();
	assert members.length == 6;
	assert disagreements(members, 0, headRows(MATERIAL_COLOR)) == "";
	assert disagreements(members, 0, pbrRows()) == "";
	assert lengthOf(members) == PBR_MATERIAL_UNIFORM_LENGTH;
}

test "an emissive pbr block is the pbr block and then the emissive vec4" {
	const members = litPbrEmissive();
	const plain = litPbr();
	assert members.length == plain.length + 1;
	for (let i = 0; i < plain.length; i++) {
		assert members[i].offset == plain[i].offset;
	}
	assert disagreements(members, PBR_MATERIAL_UNIFORM_LENGTH, emissiveRows()) == "";
	assert lengthOf(members) == PBR_MATERIAL_UNIFORM_LENGTH + EMISSIVE_LENGTH;
}

// A host write of a block struct against the block the printers lay out. Member k of the struct
// holds the lanes 10 * (k + 1) to 10 * (k + 1) + 3, so a lane read at a printed offset names the
// member it came from.
function stamp(k: int32): Vec4f {
	const at: float32 = (10 * (k + 1)) as float32;
	return { x: at, y: at + 1, z: at + 2, w: at + 3 };
}

const MOVING_FIELDS: string[] = [
	"material", "materialColor", "uvMatrix", "uvMotion", "backUvMatrix", "backUvOffset",
	"dissolve", "dissolveEdge", "flipbookGrid", "flipbookPlay", "distanceFade", "colorKey",
	"sinusDeform", "emissive",
];
const PBR_FIELDS: string[] = [
	"material", "materialColor", "pbr", "uvMatrix", "uvMotion", "parallax", "emissive",
];

function bufferOf(size: int32): Vec<float32> {
	let values: Vec<float32> = new Array(size / 4);
	for (let i = 0; i < values.length; i++) { values[i] = -7.0; }
	return values;
}

function writeDisagreements(members: BlockMember[], fields: string[], written: Vec<float32>,
	size: int32): string {
	let out = "";
	if (members.length > fields.length) { out += " the program has more members;"; }
	if (lengthOf(members) * 4 != size) {
		out += " the program is " + String(lengthOf(members) * 4) + " bytes, the struct " +
			String(size) + ";";
	}
	for (const member of members) {
		let k = -1;
		for (let i = 0; i < fields.length; i++) {
			if (fields[i] == member.name) { k = i; }
		}
		if (k < 0) {
			out += " " + member.name + " is not a field;";
			continue;
		}
		if (member.count != 4) { out += " " + member.name + " is not four floats;"; }
		for (let lane = 0; lane < member.count; lane++) {
			if (written[member.offset + lane] != (10 * (k + 1) + lane) as float32) {
				out += " " + member.name + "[" + String(lane) + "] is not at " +
					String(member.offset + lane) + ";";
			}
		}
	}
	return out;
}

test "a MovingMaterialParams write lands where the lit moving block lays its members" {
	const value: MovingMaterialParams = {
		material: stamp(0), materialColor: stamp(1), uvMatrix: stamp(2), uvMotion: stamp(3),
		backUvMatrix: stamp(4), backUvOffset: stamp(5), dissolve: stamp(6),
		dissolveEdge: stamp(7), flipbookGrid: stamp(8), flipbookPlay: stamp(9),
		distanceFade: stamp(10), colorKey: stamp(11), sinusDeform: stamp(12),
	};
	let values: Vec<float32> = bufferOf(uniformSize<MovingMaterialParams>());
	writeUniform<MovingMaterialParams>(values, 0, value);
	assert writeDisagreements(litMoving(), MOVING_FIELDS, values,
		uniformSize<MovingMaterialParams>()) == "";
}

test "a MovingUnlitMaterialParams write lands where the unlit moving block lays its members" {
	const value: MovingUnlitMaterialParams = {
		material: stamp(0), materialColor: stamp(1), uvMatrix: stamp(2), uvMotion: stamp(3),
		backUvMatrix: stamp(4), backUvOffset: stamp(5), dissolve: stamp(6),
		dissolveEdge: stamp(7), flipbookGrid: stamp(8), flipbookPlay: stamp(9),
		distanceFade: stamp(10), colorKey: stamp(11), sinusDeform: stamp(12),
	};
	let values: Vec<float32> = bufferOf(uniformSize<MovingUnlitMaterialParams>());
	writeUniform<MovingUnlitMaterialParams>(values, 0, value);
	assert writeDisagreements(unlitMoving(), MOVING_FIELDS, values,
		uniformSize<MovingUnlitMaterialParams>()) == "";
}

test "a MovingEmissiveMaterialParams write lands where the emissive moving block lays its members" {
	const value: MovingEmissiveMaterialParams = {
		material: stamp(0), materialColor: stamp(1), uvMatrix: stamp(2), uvMotion: stamp(3),
		backUvMatrix: stamp(4), backUvOffset: stamp(5), dissolve: stamp(6),
		dissolveEdge: stamp(7), flipbookGrid: stamp(8), flipbookPlay: stamp(9),
		distanceFade: stamp(10), colorKey: stamp(11), sinusDeform: stamp(12), emissive: stamp(13),
	};
	let values: Vec<float32> = bufferOf(uniformSize<MovingEmissiveMaterialParams>());
	writeUniform<MovingEmissiveMaterialParams>(values, 0, value);
	assert writeDisagreements(litMovingEmissive(), MOVING_FIELDS, values,
		uniformSize<MovingEmissiveMaterialParams>()) == "";
}

test "a PbrMaterialParams write lands where the pbr block lays its members" {
	const value: PbrMaterialParams = {
		material: stamp(0), materialColor: stamp(1), pbr: stamp(2), uvMatrix: stamp(3),
		uvMotion: stamp(4), parallax: stamp(5),
	};
	let values: Vec<float32> = bufferOf(uniformSize<PbrMaterialParams>());
	writeUniform<PbrMaterialParams>(values, 0, value);
	assert writeDisagreements(litPbr(), PBR_FIELDS, values, uniformSize<PbrMaterialParams>()) == "";
}

test "a PbrEmissiveMaterialParams write lands where the emissive pbr block lays its members" {
	const value: PbrEmissiveMaterialParams = {
		material: stamp(0), materialColor: stamp(1), pbr: stamp(2), uvMatrix: stamp(3),
		uvMotion: stamp(4), parallax: stamp(5), emissive: stamp(6),
	};
	let values: Vec<float32> = bufferOf(uniformSize<PbrEmissiveMaterialParams>());
	writeUniform<PbrEmissiveMaterialParams>(values, 0, value);
	assert writeDisagreements(litPbrEmissive(), PBR_FIELDS, values,
		uniformSize<PbrEmissiveMaterialParams>()) == "";
}
