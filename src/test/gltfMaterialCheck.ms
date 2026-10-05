import { FilterMode, Wrap, RenderState, Face } from "../gpu/state";
import { linearToSrgb } from "../math/math3d";
import {
	loadGltf,
	loadGlb,
	GltfData,
	GltfError,
	GltfMaterial,
	GltfAlphaMode,
	DEFAULT_MATERIAL,
} from "../void3d/gltf";
import {
	addGltfAssets,
	closeGltfAssets,
	GltfAssets,
	GltfMaterialSetup,
	GltfSceneError,
} from "../void3d/gltfScene";
import { DrawContext, reserveUniforms } from "../void3d/draw";
import {
	Program,
	MATERIAL_UNIFORM_SLOT,
	MATERIAL_UNIFORM_LENGTH,
	MATERIAL_DOUBLE_SIDED,
	MATERIAL_ALPHA_KILL,
} from "../void3d/gpu3d";
import { Material, Phase, UniformBlock } from "../void3d/material";
import { MeshData, stride, vertexCount } from "../void3d/meshData";
import { UniformError } from "../void3d/uniformPool";
import { rgbaPng, twoBlockJpeg } from "./imageBytes";

const F32_ZERO: uint32 = 0x00000000;
const F32_QUARTER: uint32 = 0x3E800000;
const F32_HALF: uint32 = 0x3F000000;
const F32_ONE: uint32 = 0x3F800000;
const IMAGE_OFFSET: int32 = 188;
const RED: uint32 = 0xFF0000FF;
const YELLOW: uint32 = 0xFF00FFFF;

function pushLe32(ref out: Vec<uint8>, bits: uint32): void {
	out.push((bits & (0xFF as uint32)) as uint8);
	out.push(((bits >> (8 as uint32)) & (0xFF as uint32)) as uint8);
	out.push(((bits >> (16 as uint32)) & (0xFF as uint32)) as uint8);
	out.push(((bits >> (24 as uint32)) & (0xFF as uint32)) as uint8);
}

function pushFloats(ref out: Vec<uint8>, bits: Readonly<Span<uint32>>): void {
	for (const b of bits) { pushLe32(out, b); }
}

// A unit quad facing +z: positions at 0, normals at 48, uvs at 96 (the texture's top row on
// the quad's top edge), colours at 128 (half grey), indices at 176, the PNG at 188 and the
// JPEG right after it.
function quadBuffer(): Vec<uint8> {
	let out: Vec<uint8> = [];
	pushFloats(out, [
		F32_ZERO, F32_ZERO, F32_ZERO, F32_ONE, F32_ZERO, F32_ZERO,
		F32_ONE, F32_ONE, F32_ZERO, F32_ZERO, F32_ONE, F32_ZERO,
	]);
	for (let i = 0; i < 4; i++) { pushFloats(out, [F32_ZERO, F32_ZERO, F32_ONE]); }
	pushFloats(out, [F32_ZERO, F32_ONE, F32_ONE, F32_ONE, F32_ONE, F32_ZERO, F32_ZERO, F32_ZERO]);
	for (let i = 0; i < 4; i++) { pushFloats(out, [F32_HALF, F32_HALF, F32_HALF]); }
	for (const index of [0, 1, 2, 0, 2, 3]) {
		out.push(index as uint8);
		out.push(0 as uint8);
	}
	for (const b of rgbaPng()) { out.push(b); }
	for (const b of twoBlockJpeg()) { out.push(b); }
	return out;
}

function pngLength(): int32 {
	return rgbaPng().length as int32;
}

function jpegLength(): int32 {
	return twoBlockJpeg().length as int32;
}

const TEXTURED_MATERIAL: string =
	"{\"pbrMetallicRoughness\":{\"baseColorFactor\":[0.5,0.25,1.0,1.0],"
	+ "\"baseColorTexture\":{\"index\":0}}}";
const NEAREST_CLAMP: string =
	"{\"magFilter\":9728,\"minFilter\":9984,\"wrapS\":33071,\"wrapT\":33071}";
const PNG_IMAGE: string = "{\"bufferView\":5,\"mimeType\":\"image/png\"}";
const ALL_ATTRIBUTES: string = "\"POSITION\":0,\"NORMAL\":1,\"TEXCOORD_0\":2,\"COLOR_0\":3";

struct Parts {
	attributes: string;
	primitiveMaterial: string;
	materials: string;
	textures: string;
	samplers: string;
	images: string;
}

function texturedParts(): Parts {
	return {
		attributes: ALL_ATTRIBUTES,
		primitiveMaterial: ",\"material\":0",
		materials: TEXTURED_MATERIAL,
		textures: "{\"source\":0,\"sampler\":0}",
		samplers: NEAREST_CLAMP,
		images: PNG_IMAGE,
	};
}

function documentOf(parts: Parts, bufferExtra: string = ""): string {
	const imageEnd: int32 = IMAGE_OFFSET + pngLength();
	return "{\"asset\":{\"version\":\"2.0\"},\"scene\":0,"
		+ "\"scenes\":[{\"nodes\":[0]}],"
		+ "\"nodes\":[{\"name\":\"quad\",\"mesh\":0}],"
		+ "\"meshes\":[{\"primitives\":[{\"attributes\":{" + parts.attributes + "},"
		+ "\"indices\":4" + parts.primitiveMaterial + "}]}],"
		+ "\"materials\":[" + parts.materials + "],"
		+ "\"textures\":[" + parts.textures + "],"
		+ "\"samplers\":[" + parts.samplers + "],"
		+ "\"images\":[" + parts.images + "],"
		+ "\"accessors\":["
		+ "{\"bufferView\":0,\"componentType\":5126,\"count\":4,\"type\":\"VEC3\"},"
		+ "{\"bufferView\":1,\"componentType\":5126,\"count\":4,\"type\":\"VEC3\"},"
		+ "{\"bufferView\":2,\"componentType\":5126,\"count\":4,\"type\":\"VEC2\"},"
		+ "{\"bufferView\":3,\"componentType\":5126,\"count\":4,\"type\":\"VEC3\"},"
		+ "{\"bufferView\":4,\"componentType\":5123,\"count\":6,\"type\":\"SCALAR\"},"
		+ "{\"bufferView\":2,\"componentType\":5123,\"normalized\":true,\"count\":4,"
		+ "\"type\":\"VEC2\"}],"
		+ "\"bufferViews\":["
		+ "{\"buffer\":0,\"byteOffset\":0,\"byteLength\":48},"
		+ "{\"buffer\":0,\"byteOffset\":48,\"byteLength\":48},"
		+ "{\"buffer\":0,\"byteOffset\":96,\"byteLength\":32},"
		+ "{\"buffer\":0,\"byteOffset\":128,\"byteLength\":48},"
		+ "{\"buffer\":0,\"byteOffset\":176,\"byteLength\":12},"
		+ "{\"buffer\":0,\"byteOffset\":" + `${IMAGE_OFFSET}` + ",\"byteLength\":"
		+ `${pngLength()}` + "},"
		+ "{\"buffer\":0,\"byteOffset\":" + `${imageEnd}` + ",\"byteLength\":"
		+ `${jpegLength()}` + "}],"
		+ "\"buffers\":[{\"byteLength\":" + `${imageEnd + jpegLength()}` + bufferExtra + "}]}";
}

function loaded(parts: Parts): Result<GltfData, GltfError> {
	return loadGltf(documentOf(parts), quadBuffer());
}

function refusedAs(parts: Parts, error: GltfError): boolean {
	const result: Result<GltfData, GltfError> = loaded(parts);
	if (result.ok) { return false; }
	return result.error == error;
}

function samplingOf(sampler: string): Result<GltfData, GltfError> {
	return loaded({ ...texturedParts(), samplers: sampler });
}

// glTF 2.0.1 section 4.4: a 12-byte header, then chunks of (length, type, data), each padded
// to four bytes, the JSON with spaces and the BIN with zeros.
function glbOf(
	json: string,
	bin: Readonly<Span<uint8>>,
	chunks: Readonly<Span<uint32>>,
): Vec<uint8> {
	let text: Vec<uint8> = [];
	for (let i = 0; i < json.byteLength(); i++) { text.push(json.byteAt(i) as uint8); }
	while ((text.length as int32) % 4 != 0) { text.push(0x20 as uint8); }
	let binary: Vec<uint8> = [];
	for (const b of bin) { binary.push(b); }
	while ((binary.length as int32) % 4 != 0) { binary.push(0 as uint8); }
	let body: Vec<uint8> = [];
	for (const kind of chunks) {
		const payload: Vec<uint8> = kind == (0x4E4F534A as uint32) ? text : binary;
		pushLe32(body, payload.length as uint32);
		pushLe32(body, kind);
		for (const b of payload) { body.push(b); }
	}
	let out: Vec<uint8> = [];
	pushLe32(out, 0x46546C67 as uint32);
	pushLe32(out, 2 as uint32);
	pushLe32(out, (12 + (body.length as int32)) as uint32);
	for (const b of body) { out.push(b); }
	return out;
}

function jsonThenBin(): Vec<uint32> {
	return [0x4E4F534A as uint32, 0x004E4942 as uint32];
}

test "a textured primitive decodes with uvs, its material and its texture, alpha ignored" {
	const result: Result<GltfData, GltfError> = loaded(texturedParts());
	assert result.ok;
	if (!result.ok) { return; }
	const data: GltfData = result.value;
	assert (data.meshes.length as int32) == 1 && (data.meshMaterials.length as int32) == 1;
	assert data.meshMaterials[0] == 0;
	assert data.meshes[0].hasUvs && data.meshes[0].stride() == 12;
	assert data.meshes[0].vertexCount() == 4;
	assert data.meshes[0].vertices[6] == 0.0 && data.meshes[0].vertices[7] == 1.0;
	assert data.meshes[0].vertices[8] == linearToSrgb(0.25);
	assert data.meshes[0].vertices[9] == linearToSrgb(0.125);
	assert data.meshes[0].vertices[10] == linearToSrgb(0.5);
	assert data.meshes[0].vertices[11] == 1.0;
	assert data.meshes[0].vertices[12 + 6] == 1.0 && data.meshes[0].vertices[12 + 7] == 1.0;
	assert (data.materials.length as int32) == 1;
	assert data.materials[0].texture == 0 && !data.materials[0].doubleSided;
	assert (data.textures.length as int32) == 1;
	assert data.textures[0].width == 2 && data.textures[0].height == 2;
	assert data.textures[0].pixels[0] == RED;
	assert data.textures[0].pixels[3] == YELLOW;
	assert data.textures[0].filter == FilterMode.Nearest;
	assert data.textures[0].wrap == Wrap.Clamp;
}

test "loadGlb reads the same document from a binary container" {
	const buffer: Vec<uint8> = quadBuffer();
	const glb: Vec<uint8> = glbOf(documentOf(texturedParts()), buffer, jsonThenBin());
	const result: Result<GltfData, GltfError> = loadGlb(glb);
	assert result.ok;
	if (!result.ok) { return; }
	assert result.value.meshes[0].vertices[9] == linearToSrgb(0.125);
	assert result.value.textures[0].pixels[3] == YELLOW;
	const trailing: Vec<uint32> =
		[0x4E4F534A as uint32, 0x004E4942 as uint32, 0x12345678 as uint32];
	assert loadGlb(glbOf(documentOf(texturedParts()), buffer, trailing)).ok;
}

test "a sampler maps to one filter and one wrap, a mipmap min filter to its base" {
	const absent = loaded({ ...texturedParts(), textures: "{\"source\":0}" });
	assert absent.ok;
	if (absent.ok) {
		assert absent.value.textures[0].filter == FilterMode.Linear;
		assert absent.value.textures[0].wrap == Wrap.Repeat;
	}
	const trilinear = samplingOf("{\"magFilter\":9729,\"minFilter\":9987}");
	assert trilinear.ok;
	if (trilinear.ok) { assert trilinear.value.textures[0].filter == FilterMode.Linear; }
	const minOnly = samplingOf("{\"minFilter\":9986,\"wrapS\":33648,\"wrapT\":33648}");
	assert minOnly.ok;
	if (minOnly.ok) {
		assert minOnly.value.textures[0].filter == FilterMode.Nearest;
		assert minOnly.value.textures[0].wrap == Wrap.Mirror;
	}
	const noFilters = samplingOf("{}");
	assert noFilters.ok;
	if (noFilters.ok) { assert noFilters.value.textures[0].filter == FilterMode.Linear; }
	for (const sampler of [
		"{\"magFilter\":9728,\"minFilter\":9729}",
		"{\"wrapS\":33071,\"wrapT\":10497}",
		"{\"magFilter\":9984}",
		"{\"minFilter\":1234}",
		"{\"wrapS\":1234,\"wrapT\":1234}",
	]) {
		const refused = samplingOf(sampler);
		assert !refused.ok;
		if (!refused.ok) { assert refused.error == GltfError.UnsupportedSampler; }
	}
}

test "an untextured factor, the default material and double sides" {
	const plain = loaded({
		...texturedParts(),
		materials: "{\"doubleSided\":true,"
			+ "\"pbrMetallicRoughness\":{\"baseColorFactor\":[0.5,1.0,0.25,1.0]}}",
	});
	assert plain.ok;
	if (plain.ok) {
		assert !plain.value.meshes[0].hasUvs && plain.value.meshes[0].stride() == 10;
		assert plain.value.meshes[0].vertices[6] == linearToSrgb(0.25);
		assert plain.value.meshes[0].vertices[7] == linearToSrgb(0.5);
		assert plain.value.meshes[0].vertices[8] == linearToSrgb(0.125);
		assert plain.value.materials[0].doubleSided && plain.value.materials[0].texture == -1;
		assert (plain.value.textures.length as int32) == 1;
	}
	const unnamed = loaded({ ...texturedParts(), primitiveMaterial: "" });
	assert unnamed.ok;
	if (unnamed.ok) {
		assert unnamed.value.meshMaterials[0] == DEFAULT_MATERIAL;
		assert !unnamed.value.meshes[0].hasUvs;
		assert unnamed.value.meshes[0].vertices[6] == linearToSrgb(0.5);
	}
	const blackEmissive = loaded({
		...texturedParts(),
		materials: "{\"emissiveFactor\":[0.0,0.0,0.0]}",
	});
	assert blackEmissive.ok;
}

function kindOf(material: string): Result<GltfMaterial, GltfError> {
	const read = loaded({ ...texturedParts(), materials: material });
	if (!read.ok) { return Result.err(read.error); }
	return Result.ok(read.value.materials[0]);
}

test "alphaMode is the material's kind, MASK with its cutoff" {
	const opaque = kindOf("{\"alphaMode\":\"OPAQUE\",\"alphaCutoff\":0.25}");
	assert opaque.ok && opaque.value.alphaMode == GltfAlphaMode.Opaque;
	assert opaque.ok && opaque.value.alphaKill == 0.0;
	const mask = kindOf("{\"alphaMode\":\"MASK\"}");
	assert mask.ok && mask.value.alphaMode == GltfAlphaMode.Mask && mask.value.alphaKill == 0.5;
	const cut = kindOf("{\"alphaMode\":\"MASK\",\"alphaCutoff\":0.25}");
	assert cut.ok && cut.value.alphaMode == GltfAlphaMode.Mask && cut.value.alphaKill == 0.25;
	const blend = kindOf("{\"alphaMode\":\"BLEND\",\"alphaCutoff\":0.25}");
	assert blend.ok && blend.value.alphaMode == GltfAlphaMode.Blend && blend.value.alphaKill == 0.0;
	for (const material of ["{\"alphaMode\":\"CUTOUT\"}", "{\"alphaMode\":1}",
		"{\"alphaMode\":\"MASK\",\"alphaCutoff\":\"half\"}"]) {
		assert refusedAs({ ...texturedParts(), materials: material }, GltfError.Unsupported);
	}
	const negative = "{\"alphaMode\":\"MASK\",\"alphaCutoff\":-0.5}";
	assert refusedAs({ ...texturedParts(), materials: negative }, GltfError.OutOfRange);
}

function translucentMaterial(mode: string): string {
	return "{\"alphaMode\":\"" + mode + "\",\"pbrMetallicRoughness\":"
		+ "{\"baseColorFactor\":[0.5,0.25,1.0,0.5],\"baseColorTexture\":{\"index\":0}}}";
}

test "MASK and BLEND keep the texture's and the factor's alpha, OPAQUE ignores both" {
	for (const mode of ["MASK", "BLEND"]) {
		const kept = loaded({ ...texturedParts(), materials: translucentMaterial(mode) });
		assert kept.ok;
		if (!kept.ok) { continue; }
		assert kept.value.textures[0].pixels[3] == (0x8000FFFF as uint32);
		assert kept.value.textures[0].pixels[0] == RED;
		assert kept.value.meshes[0].vertices[11] == 0.5;
	}
	const ignored = loaded(texturedParts());
	assert ignored.ok;
	if (ignored.ok) {
		assert ignored.value.textures[0].pixels[3] == YELLOW;
		assert ignored.value.meshes[0].vertices[11] == 1.0;
	}
	const zero = loaded({
		...texturedParts(),
		materials: "{\"alphaMode\":\"MASK\",\"alphaCutoff\":0,"
			+ "\"pbrMetallicRoughness\":{\"baseColorTexture\":{\"index\":0}}}",
	});
	assert zero.ok;
	if (zero.ok) {
		assert zero.value.materials[0].alphaMode == GltfAlphaMode.Opaque;
		assert zero.value.materials[0].alphaKill == 0.0;
		assert zero.value.textures[0].pixels[3] == YELLOW;
	}
	const shared: Parts = {
		...texturedParts(), materials: TEXTURED_MATERIAL + "," + translucentMaterial("BLEND"),
	};
	assert refusedAs(shared, GltfError.UnsupportedMaterial);
}

test "a material this renderer cannot draw is refused by name" {
	for (const material of [
		"{\"normalTexture\":{\"index\":0}}",
		"{\"occlusionTexture\":{\"index\":0}}",
		"{\"emissiveTexture\":{\"index\":0}}",
		"{\"emissiveFactor\":[0.1,0.0,0.0]}",
		"{\"pbrMetallicRoughness\":{\"baseColorTexture\":{\"index\":0,\"texCoord\":1}}}",
		"{\"pbrMetallicRoughness\":{\"baseColorTexture\":{\"index\":0,"
			+ "\"extensions\":{\"KHR_texture_transform\":{\"scale\":[2.0,2.0]}}}}}",
	]) {
		const parts: Parts = { ...texturedParts(), materials: material };
		assert refusedAs(parts, GltfError.UnsupportedMaterial);
	}
	const factor = "{\"pbrMetallicRoughness\":{\"baseColorFactor\":[1.5,1.0,1.0,1.0]}}";
	assert refusedAs({ ...texturedParts(), materials: factor }, GltfError.OutOfRange);
	const sides = "{\"doubleSided\":\"yes\"}";
	assert refusedAs({ ...texturedParts(), materials: sides }, GltfError.Unsupported);
}

test "images, uvs and references that cannot be read are refused by name" {
	const withoutUvs = "\"POSITION\":0,\"NORMAL\":1,\"COLOR_0\":3";
	assert refusedAs({ ...texturedParts(), attributes: withoutUvs }, GltfError.MissingTexCoord);
	const integerUvs = "\"POSITION\":0,\"NORMAL\":1,\"TEXCOORD_0\":5,\"COLOR_0\":3";
	assert refusedAs({ ...texturedParts(), attributes: integerUvs }, GltfError.Unsupported);
	const byUri = "{\"uri\":\"texture.png\"}";
	assert refusedAs({ ...texturedParts(), images: byUri }, GltfError.ImageByUri);
	const gif = "{\"bufferView\":5,\"mimeType\":\"image/gif\"}";
	assert refusedAs({ ...texturedParts(), images: gif }, GltfError.BadImage);
	const mislabelled = "{\"bufferView\":6,\"mimeType\":\"image/png\"}";
	assert refusedAs({ ...texturedParts(), images: mislabelled }, GltfError.BadImage);
	const headers = "{\"bufferView\":0,\"mimeType\":\"image/png\"}";
	assert refusedAs({ ...texturedParts(), images: headers }, GltfError.BadImage);
	const noView = "{\"bufferView\":9,\"mimeType\":\"image/png\"}";
	assert refusedAs({ ...texturedParts(), images: noView }, GltfError.BadReference);
	const noSource = "{\"sampler\":0}";
	assert refusedAs({ ...texturedParts(), textures: noSource }, GltfError.Unsupported);
	const farSource = "{\"source\":3}";
	assert refusedAs({ ...texturedParts(), textures: farSource }, GltfError.BadReference);
	const farSampler = "{\"source\":0,\"sampler\":2}";
	assert refusedAs({ ...texturedParts(), textures: farSampler }, GltfError.BadReference);
	const farTexture = "{\"pbrMetallicRoughness\":{\"baseColorTexture\":{\"index\":4}}}";
	assert refusedAs({ ...texturedParts(), materials: farTexture }, GltfError.BadReference);
	const farMaterial = ",\"material\":7";
	const unnamed: Parts = { ...texturedParts(), primitiveMaterial: farMaterial };
	assert refusedAs(unnamed, GltfError.BadReference);
}

test "a binary container that is not one is refused as NotGlb" {
	const buffer: Vec<uint8> = quadBuffer();
	const json: string = documentOf(texturedParts());
	let wrongMagic: Vec<uint8> = glbOf(json, buffer, jsonThenBin());
	wrongMagic[0] = 0x66 as uint8;
	let wrongVersion: Vec<uint8> = glbOf(json, buffer, jsonThenBin());
	wrongVersion[4] = 1 as uint8;
	let wrongLength: Vec<uint8> = glbOf(json, buffer, jsonThenBin());
	wrongLength.push(0 as uint8);
	let misaligned: Vec<uint8> = glbOf(json, buffer, jsonThenBin());
	misaligned[12] = ((misaligned[12] as int32) + 1) as uint8;
	let overrun: Vec<uint8> = glbOf(json, buffer, jsonThenBin());
	overrun[15] = 0x10 as uint8;
	const binFirst: Vec<uint32> = [0x004E4942 as uint32, 0x4E4F534A as uint32];
	const binThird: Vec<uint32> =
		[0x4E4F534A as uint32, 0x12345678 as uint32, 0x004E4942 as uint32];
	for (const bytes of [
		wrongMagic,
		wrongVersion,
		wrongLength,
		misaligned,
		overrun,
		glbOf(json, buffer, binFirst),
		glbOf(json, buffer, binThird),
	]) {
		const result: Result<GltfData, GltfError> = loadGlb(bytes);
		assert !result.ok;
		if (!result.ok) { assert result.error == GltfError.NotGlb; }
	}
	const external = loadGlb(glbOf(documentOf(texturedParts(), ",\"uri\":\"quad.bin\""), buffer,
		jsonThenBin()));
	assert !external.ok;
	if (!external.ok) { assert external.error == GltfError.Unsupported; }
	const noBin = loadGlb(glbOf(json, buffer, [0x4E4F534A as uint32]));
	assert !noBin.ok;
	if (!noBin.ok) { assert noBin.error == GltfError.OutOfRange; }
}

function setupOf(values: Readonly<Span<float32>>): GltfMaterialSetup {
	let block: Vec<float32> = [];
	for (const value of values) { block.push(value); }
	return { pass: RenderState.defaults(), block: block };
}

function materialsOnly(materials: Readonly<Span<GltfMaterial>>): GltfData {
	let list: Vec<GltfMaterial> = [];
	for (const material of materials) { list.push(material); }
	return {
		meshes: [],
		meshMaterials: [],
		materials: list,
		textures: [],
		nodes: [],
		sceneRoots: [],
	};
}

function twoMaterials(): GltfData {
	return materialsOnly([
		{ texture: -1, doubleSided: false, alphaMode: GltfAlphaMode.Opaque, alphaKill: 0.0 },
		{ texture: -1, doubleSided: true, alphaMode: GltfAlphaMode.Opaque, alphaKill: 0.0 },
	]);
}

function kinds(): GltfData {
	return materialsOnly([
		{ texture: -1, doubleSided: false, alphaMode: GltfAlphaMode.Mask, alphaKill: 0.25 },
		{ texture: -1, doubleSided: true, alphaMode: GltfAlphaMode.Blend, alphaKill: 0.0 },
	]);
}

test "addGltfAssets refuses a setup or data it cannot use before it makes anything" {
	let context: DrawContext = DrawContext.withUniformCapacity(64);
	const short: Result<GltfAssets, GltfSceneError> =
		addGltfAssets(context, twoMaterials(), setupOf([0.0, 0.0, 0.0]));
	assert !short.ok;
	if (!short.ok) { assert short.error == GltfSceneError.BadSetup; }
	const flagged: Result<GltfAssets, GltfSceneError> =
		addGltfAssets(context, twoMaterials(), setupOf([0.0, 0.0, 1.0, 0.0]));
	assert !flagged.ok;
	if (!flagged.ok) { assert flagged.error == GltfSceneError.BadSetup; }
	const killing: Result<GltfAssets, GltfSceneError> =
		addGltfAssets(context, twoMaterials(), setupOf([0.0, 0.0, 0.0, 0.5]));
	assert !killing.ok;
	if (!killing.ok) { assert killing.error == GltfSceneError.BadSetup; }
	let texturedWithoutUvs: GltfData = materialsOnly([
		{ texture: 0, doubleSided: false, alphaMode: GltfAlphaMode.Opaque, alphaKill: 0.0 },
	]);
	texturedWithoutUvs.meshes.push(MeshData.empty());
	texturedWithoutUvs.meshMaterials.push(0);
	let farTexture: GltfData = materialsOnly([
		{ texture: 3, doubleSided: false, alphaMode: GltfAlphaMode.Opaque, alphaKill: 0.0 },
	]);
	let unmatched: GltfData = twoMaterials();
	unmatched.meshes.push(MeshData.empty());
	let uvsUntextured: GltfData = twoMaterials();
	uvsUntextured.meshes.push(MeshData.withUvs());
	uvsUntextured.meshMaterials.push(0);
	for (const data of [texturedWithoutUvs, farTexture, unmatched, uvsUntextured]) {
		const refused = addGltfAssets(context, data, setupOf([0.0, 0.0, 0.0, 0.0]));
		assert !refused.ok;
		if (!refused.ok) { assert refused.error == GltfSceneError.InvalidData; }
	}
	assert context.liveMaterials() == 0 && context.liveTextures() == 0;
}

test "a glTF material is the setup's block and culling, double sides unculled and flagged" {
	let context: DrawContext = DrawContext.withUniformCapacity(64);
	const made: Result<GltfAssets, GltfSceneError> =
		addGltfAssets(context, twoMaterials(), setupOf([3.0, -1.0, 0.0, 0.0]));
	assert made.ok;
	if (!made.ok) { return; }
	assert (made.value.materials.length as int32) == 2 && context.liveMaterials() == 2;
	const single: Material = context.materials[made.value.materials[0].index];
	const double: Material = context.materials[made.value.materials[1].index];
	assert single.program == Program.Lit && double.program == Program.Lit;
	assert single.pass.culling == Face.Back && double.pass.culling == Face.None;
	assert !single.namesTexture();
	const values: Vec<float32> = context.uniforms.values;
	assert values[single.uniforms.offset] == 3.0 && values[single.uniforms.offset + 1] == -1.0;
	assert values[single.uniforms.offset + MATERIAL_DOUBLE_SIDED] == 0.0;
	assert values[double.uniforms.offset + MATERIAL_DOUBLE_SIDED] == 1.0;
	assert values[double.uniforms.offset + MATERIAL_ALPHA_KILL] == 0.0;
	let alias: GltfAssets = made.value;
	closeGltfAssets(alias);
	assert made.value.isClosed() && context.liveMaterials() == 0;
}

test "a glTF material's kind sets its phase, blend and alpha kill over the setup's pass" {
	let context: DrawContext = DrawContext.withUniformCapacity(64);
	const made: Result<GltfAssets, GltfSceneError> =
		addGltfAssets(context, kinds(), setupOf([3.0, -1.0, 0.0, 0.0]));
	assert made.ok;
	if (!made.ok) { return; }
	const cut: Material = context.materials[made.value.materials[0].index];
	const blended: Material = context.materials[made.value.materials[1].index];
	assert cut.phase == Phase.Opaque && !cut.pass.blends() && cut.pass.depthWrite;
	assert cut.program == Program.LitCutout && blended.program == Program.Lit;
	assert blended.phase == Phase.Alpha && blended.pass.blends() && blended.pass.depthWrite;
	assert blended.pass.culling == Face.None;
	const values: Vec<float32> = context.uniforms.values;
	assert values[cut.uniforms.offset + MATERIAL_ALPHA_KILL] == 0.25;
	assert values[blended.uniforms.offset + MATERIAL_ALPHA_KILL] == 0.0;
	let alias: GltfAssets = made.value;
	closeGltfAssets(alias);
}

test "a full uniform pool is named and gives back the materials already made" {
	let context: DrawContext = DrawContext.withUniformCapacity(MATERIAL_UNIFORM_LENGTH);
	const full: Result<GltfAssets, GltfSceneError> =
		addGltfAssets(context, twoMaterials(), setupOf([0.0, 0.0, 0.0, 0.0]));
	assert !full.ok;
	if (!full.ok) { assert full.error == GltfSceneError.UniformsFull; }
	assert context.liveMaterials() == 0;
	const reserved: Result<UniformBlock, UniformError> =
		reserveUniforms(context, MATERIAL_UNIFORM_SLOT, MATERIAL_UNIFORM_LENGTH);
	assert reserved.ok;
}
