// glTF materials imported as pbr materials, opt-in: the default import is unchanged, the Pbr
// import maps pbrMetallicRoughness' factors to a pbr key and block, and a value or map the
// block cannot carry is refused by name.

import {
	loadGltf,
	loadGltfDetailed,
	GltfData,
	GltfDiagnostic,
	GltfError,
	GltfMaterialImport,
} from "../void3d/gltf";
import { gltfProgramOf } from "../void3d/gltfScene";
import {
	Program,
	PBR_METALNESS,
	PBR_OCCLUSION,
	PBR_ROUGHNESS,
	PBR_MATERIAL_UNIFORM_LENGTH,
	declares,
	withPbr,
} from "../void3d/gpu3d";
import { pbrBlock } from "../void3d/material";
import { PbrProperties } from "../void3d/pbrResponse";

const F32_ZERO: uint32 = 0x00000000;
const F32_ONE: uint32 = 0x3F800000;

function pushLe32(ref out: Vec<uint8>, bits: uint32): void {
	out.push((bits & (0xFF as uint32)) as uint8);
	out.push(((bits >> (8 as uint32)) & (0xFF as uint32)) as uint8);
	out.push(((bits >> (16 as uint32)) & (0xFF as uint32)) as uint8);
	out.push(((bits >> (24 as uint32)) & (0xFF as uint32)) as uint8);
}

// One triangle facing +z: positions at 0, normals at 36, u16 indices at 72.
function triangleBuffer(): Vec<uint8> {
	let out: Vec<uint8> = [];
	for (const bits of [
		F32_ZERO, F32_ZERO, F32_ZERO, F32_ONE, F32_ZERO, F32_ZERO, F32_ZERO, F32_ONE, F32_ZERO,
	]) { pushLe32(out, bits); }
	for (let i = 0; i < 3; i++) {
		for (const bits of [F32_ZERO, F32_ZERO, F32_ONE]) { pushLe32(out, bits); }
	}
	for (const index of [0, 1, 2, 0]) {
		out.push(index as uint8);
		out.push(0 as uint8);
	}
	return out;
}

function documentOf(material: string): string {
	return "{\"asset\":{\"version\":\"2.0\"},\"scene\":0,\"scenes\":[{\"nodes\":[0]}],"
		+ "\"nodes\":[{\"name\":\"tri\",\"mesh\":0}],"
		+ "\"meshes\":[{\"primitives\":[{\"attributes\":{\"POSITION\":0,\"NORMAL\":1},"
		+ "\"indices\":2,\"material\":0}]}],"
		+ "\"materials\":[" + material + "],"
		+ "\"accessors\":["
		+ "{\"bufferView\":0,\"componentType\":5126,\"count\":3,\"type\":\"VEC3\"},"
		+ "{\"bufferView\":1,\"componentType\":5126,\"count\":3,\"type\":\"VEC3\"},"
		+ "{\"bufferView\":2,\"componentType\":5123,\"count\":3,\"type\":\"SCALAR\"}],"
		+ "\"bufferViews\":["
		+ "{\"buffer\":0,\"byteOffset\":0,\"byteLength\":36},"
		+ "{\"buffer\":0,\"byteOffset\":36,\"byteLength\":36},"
		+ "{\"buffer\":0,\"byteOffset\":72,\"byteLength\":6}],"
		+ "\"buffers\":[{\"byteLength\":80}]}";
}

function importedAs(
	material: string,
	materials: GltfMaterialImport,
): Result<GltfData, GltfDiagnostic> {
	return loadGltfDetailed(documentOf(material), triangleBuffer(), "pbr.gltf", materials);
}

function pbrOf(material: string): Result<GltfData, GltfDiagnostic> {
	return importedAs(material, GltfMaterialImport.Pbr);
}

function refusedWith(
	material: string,
	materials: GltfMaterialImport,
	error: GltfError,
	cause: string,
): boolean {
	const result = importedAs(material, materials);
	if (result.ok) { return false; }
	return result.error.code == error && result.error.cause.includes(cause);
}

const FACTORS: string =
	"{\"pbrMetallicRoughness\":{\"baseColorFactor\":[0.5,0.25,1.0,1.0],"
	+ "\"metallicFactor\":0.25,\"roughnessFactor\":0.5}}";

test "the default import keeps every material legacy and ignores the factors" {
	const legacy = loadGltf(documentOf(FACTORS), triangleBuffer());
	assert legacy.ok;
	if (!legacy.ok) { return; }
	assert legacy.value.materials[0].pbr === null;
	assert !gltfProgramOf(legacy.value.materials[0]).pbr;
	const explicit = importedAs(FACTORS, GltfMaterialImport.Legacy);
	assert explicit.ok;
	if (!explicit.ok) { return; }
	assert explicit.value.materials[0].pbr === null;
	assert explicit.value.meshes[0].vertices == legacy.value.meshes[0].vertices;
	assert refusedWith("{\"occlusionTexture\":{\"index\":0}}", GltfMaterialImport.Legacy,
		GltfError.UnsupportedMaterial, "unsupported");
}

test "the Pbr import reads the factors into a pbr key and block" {
	const result = pbrOf(FACTORS);
	assert result.ok;
	if (!result.ok) { return; }
	const pbr = result.value.materials[0].pbr;
	assert pbr !== null;
	if (pbr === null) { return; }
	assert pbr.metallic == 0.25 && pbr.roughness == 0.5;
	const key = gltfProgramOf(result.value.materials[0]).withPbr();
	assert key.pbr && key.program == Program.Lit && declares(key);
	const properties = PbrProperties.gltfMap(pbr.metallic, pbr.roughness);
	assert properties.ok;
	if (!properties.ok) { return; }
	const block = pbrBlock(key, properties.value);
	assert block.ok;
	if (!block.ok) { return; }
	assert (block.value.length as int32) == PBR_MATERIAL_UNIFORM_LENGTH;
	assert block.value[PBR_METALNESS] == 0.25 && block.value[PBR_ROUGHNESS] == 0.5;
	assert block.value[PBR_OCCLUSION] == 1.0;
}

test "absent factors take the glTF defaults, 1 and 1, not Heaps' metalness 0" {
	for (const material of ["{}", "{\"pbrMetallicRoughness\":{}}",
		"{\"pbrMetallicRoughness\":{\"baseColorFactor\":[1.0,1.0,1.0,1.0]}}"]) {
		const result = pbrOf(material);
		assert result.ok;
		if (!result.ok) { return; }
		const pbr = result.value.materials[0].pbr;
		assert pbr !== null;
		if (pbr === null) { return; }
		assert pbr.metallic == 1.0 && pbr.roughness == 1.0;
	}
	const partial = pbrOf("{\"pbrMetallicRoughness\":{\"metallicFactor\":0.0}}");
	assert partial.ok;
	if (!partial.ok) { return; }
	const only = partial.value.materials[0].pbr;
	assert only !== null && only.metallic == 0.0 && only.roughness == 1.0;
}

test "a factor outside 0..1, not a number, or roughness 0 is refused by name" {
	const pbr = GltfMaterialImport.Pbr;
	assert refusedWith("{\"pbrMetallicRoughness\":{\"metallicFactor\":1.5}}", pbr,
		GltfError.OutOfRange, "metallicFactor 1.5 is outside 0..1");
	assert refusedWith("{\"pbrMetallicRoughness\":{\"roughnessFactor\":-0.5}}", pbr,
		GltfError.OutOfRange, "roughnessFactor -0.5 is outside 0..1");
	assert refusedWith("{\"pbrMetallicRoughness\":{\"metallicFactor\":1e999}}", pbr,
		GltfError.OutOfRange, "");
	assert refusedWith("{\"pbrMetallicRoughness\":{\"roughnessFactor\":\"rough\"}}", pbr,
		GltfError.Unsupported, "");
	assert refusedWith("{\"pbrMetallicRoughness\":{\"roughnessFactor\":0.0}}", pbr,
		GltfError.UnsupportedMaterial, "roughnessFactor 0");
	const legacyZero = importedAs("{\"pbrMetallicRoughness\":{\"roughnessFactor\":0.0}}",
		GltfMaterialImport.Legacy);
	assert legacyZero.ok;
}

test "a map the pbr block cannot carry is refused, not dropped" {
	const pbr = GltfMaterialImport.Pbr;
	assert refusedWith("{\"occlusionTexture\":{\"index\":0}}", pbr,
		GltfError.UnsupportedMaterial, "occlusionTexture");
	assert refusedWith(
		"{\"pbrMetallicRoughness\":{\"metallicRoughnessTexture\":{\"index\":0}}}", pbr,
		GltfError.UnsupportedMaterial, "metallicRoughnessTexture");
}
