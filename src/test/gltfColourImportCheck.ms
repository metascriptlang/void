import { approx } from "./helpers";
import { rgbaPng } from "./imageBytes";
import { added, litShape } from "./drawHelpers";
import { linearToSrgb } from "../math/math3d";
import { RenderState } from "../gpu/state";
import { loadGltf, loadGlb, GltfData, GltfAlphaMode, GltfError } from "../void3d/gltf";
import { DrawContext, releaseMesh } from "../void3d/draw";
import {
	addGltfAssets,
	closeGltfAssets,
	addGltfNodes,
	GltfMeshBinding,
	GltfMaterialSetup,
} from "../void3d/gltfScene";
import { Phase } from "../void3d/material";
import { MATERIAL_ALPHA_KILL } from "../void3d/gpu3d";
import { Scene3D, rootId, findByName, closeScene } from "../void3d/scene";
import { vertexCount, triangleCount, stride } from "../void3d/meshData";

function pushLe32(ref out: Vec<uint8>, bits: uint32): void {
	out.push((bits & 0xFF) as uint8);
	out.push(((bits >> 8) & 0xFF) as uint8);
	out.push(((bits >> 16) & 0xFF) as uint8);
	out.push(((bits >> 24) & 0xFF) as uint8);
}

function triangleBuffer(): Vec<uint8> {
	let out: Vec<uint8> = [];
	pushLe32(out, 0); pushLe32(out, 0); pushLe32(out, 0);
	pushLe32(out, 0x3F800000); pushLe32(out, 0); pushLe32(out, 0);
	pushLe32(out, 0); pushLe32(out, 0x3F800000); pushLe32(out, 0);
	for (let i = 0; i < 3; i++) {
		pushLe32(out, 0); pushLe32(out, 0); pushLe32(out, 0x3F800000);
	}
	for (let i = 0; i < 3; i++) { out.push(i as uint8); out.push(0 as uint8); }
	out.push(0 as uint8); out.push(0 as uint8);
	return out;
}

function colourGltf(
	accessor: string,
	views: string,
	length: int32,
	mode: string,
	extraAttributes: string = "",
): string {
	return "{\"asset\":{\"version\":\"2.0\"},\"scene\":0,\"scenes\":[{\"nodes\":[0]}]," +
		"\"nodes\":[{\"name\":\"tri\",\"mesh\":0}]," +
		"\"meshes\":[{\"primitives\":[{\"attributes\":{\"POSITION\":0,\"NORMAL\":1" +
		(accessor == "" ? "" : ",\"COLOR_0\":3") + extraAttributes +
		"},\"indices\":2,\"material\":0}]}]," +
		"\"materials\":[{\"alphaMode\":\"" + mode + "\",\"alphaCutoff\":0.2," +
		"\"pbrMetallicRoughness\":{\"baseColorFactor\":[0.5,0.25,1.0,0.5]}}]," +
		"\"accessors\":[" +
		"{\"bufferView\":0,\"componentType\":5126,\"count\":3,\"type\":\"VEC3\"," +
		"\"min\":[0,0,0],\"max\":[1,1,0]}," +
		"{\"bufferView\":1,\"componentType\":5126,\"count\":3,\"type\":\"VEC3\"}," +
		"{\"bufferView\":2,\"componentType\":5123,\"count\":3,\"type\":\"SCALAR\"}" +
		(accessor == "" ? "" : "," + accessor) + "],\"bufferViews\":[" +
		"{\"buffer\":0,\"byteOffset\":0,\"byteLength\":36}," +
		"{\"buffer\":0,\"byteOffset\":36,\"byteLength\":36}," +
		"{\"buffer\":0,\"byteOffset\":72,\"byteLength\":6}" +
		(views == "" ? "" : "," + views) +
		"],\"buffers\":[{\"byteLength\":" + length.toString() + "}]}";
}

const U8_ACCESSOR: string =
	"{\"bufferView\":3,\"componentType\":5121,\"normalized\":true," +
	"\"count\":3,\"type\":\"VEC4\"}";
const U8_VIEW: string = "{\"buffer\":0,\"byteOffset\":80,\"byteLength\":24,\"byteStride\":8}";

function u8Buffer(): Vec<uint8> {
	let out = triangleBuffer();
	for (const byte of [255, 128, 64, 128, 255, 255, 255, 255,
		64, 255, 128, 64, 255, 255, 255, 255,
		128, 64, 255, 255, 255, 255, 255, 255]) { out.push(byte as uint8); }
	return out;
}

function checkU8(mode: string, alphaMode: GltfAlphaMode): boolean {
	const loaded = loadGltf(colourGltf(U8_ACCESSOR, U8_VIEW, 104, mode), u8Buffer());
	if (!loaded.ok) { console.log(loaded.error); return false; }
	const data = loaded.value;
	const mesh = data.meshes[0];
	if (mesh.vertexCount() != 3 || mesh.triangleCount() != 1
		|| mesh.indices[0] != 0 || mesh.indices[1] != 1 || mesh.indices[2] != 2) { return false; }
	const red: Vec<float32> = [1.0, 64.0 / 255.0, 128.0 / 255.0];
	const green: Vec<float32> = [128.0 / 255.0, 1.0, 64.0 / 255.0];
	const blue: Vec<float32> = [64.0 / 255.0, 128.0 / 255.0, 1.0];
	const alpha: Vec<float32> = [128.0 / 255.0, 64.0 / 255.0, 1.0];
	for (let i = 0; i < 3; i++) {
		const expectedAlpha: float32 = alphaMode == GltfAlphaMode.Opaque ? 1.0 : alpha[i] * 0.5;
		if (!approx(mesh.vertices[i * 10 + 6], linearToSrgb(red[i] * 0.5))
			|| !approx(mesh.vertices[i * 10 + 7], linearToSrgb(green[i] * 0.25))
			|| !approx(mesh.vertices[i * 10 + 8], linearToSrgb(blue[i]))
			|| !approx(mesh.vertices[i * 10 + 9], expectedAlpha)) { return false; }
	}
	if (data.materials[0].alphaMode != alphaMode || data.meshMaterials[0] != 0) { return false; }
	let context = DrawContext.withUniformCapacity(64);
	const meshId = added(context, litShape());
	defer releaseMesh(context, meshId);
	context.meshData[meshId.index] = data.meshes[0];
	const materialData: GltfData = {
		meshes: [],
		meshMaterials: [],
		materials: data.materials,
		textures: [],
		nodes: [],
		sceneRoots: [],
	};
	const setup: GltfMaterialSetup = { pass: RenderState.defaults(), block: [0.0, 0.0, 0.0, 0.0] };
	const assets = addGltfAssets(context, materialData, setup);
	if (!assets.ok) { return false; }
	let owned = assets.value;
	defer closeGltfAssets(owned);
	let scene = Scene3D.create(context);
	defer closeScene(scene);
	const bindings: Vec<GltfMeshBinding> = [{ mesh: meshId, material: owned.materials[0] }];
	const nodes = addGltfNodes(scene, scene.rootId(), data, bindings);
	if (!nodes.ok) { return false; }
	const node = scene.findByName(scene.rootId(), "tri");
	if (!node.ok) { return false; }
	const bound = scene.meshes[scene.nodes[node.value.index].payload];
	const expectedAlpha: float32 = (
		alphaMode == GltfAlphaMode.Opaque ? 1.0 : 128.0 / 255.0 * 0.5
	) as float32;
	const cutoff: float32 = alphaMode == GltfAlphaMode.Mask ? 0.2 : 0.0;
	const material = context.materials[bound.material.index];
	return bound.mesh == meshId && bound.material == owned.materials[0]
		&& approx(context.meshData[bound.mesh.index].vertices[9], expectedAlpha)
		&& material.phase == (alphaMode == GltfAlphaMode.Blend ? Phase.Alpha : Phase.Opaque)
		&& material.pass.blends() == (alphaMode == GltfAlphaMode.Blend)
		&& approx(context.uniforms.values[material.uniforms.offset + MATERIAL_ALPHA_KILL], cutoff);
}

test "real normalized u8 strided RGBA OPAQUE ignores source and factor alpha" {
	assert checkU8("OPAQUE", GltfAlphaMode.Opaque);
}
test "real normalized u8 strided RGBA BLEND multiplies source alpha once and binds" {
	assert checkU8("BLEND", GltfAlphaMode.Blend);
}
test "real normalized u8 strided RGBA MASK preserves effective alpha and cutoff binding" {
	assert checkU8("MASK", GltfAlphaMode.Mask);
}

const SPARSE_ACCESSOR: string =
	"{\"bufferView\":3,\"componentType\":5126,\"count\":3,\"type\":\"VEC4\"," +
	"\"sparse\":{\"count\":2,\"indices\":{\"bufferView\":4,\"componentType\":5121}," +
	"\"values\":{\"bufferView\":5}}}";
const SPARSE_VIEWS: string = "{\"buffer\":0,\"byteOffset\":80,\"byteLength\":48},"
	+ "{\"buffer\":0,\"byteOffset\":128,\"byteLength\":2},"
	+ "{\"buffer\":0,\"byteOffset\":132,\"byteLength\":32}";

function sparseBuffer(): Vec<uint8> {
	let out = triangleBuffer();
	for (let i = 0; i < 3; i++) {
		pushLe32(out, 0x3F000000);
		pushLe32(out, 0x3E800000);
		pushLe32(out, 0);
		pushLe32(out, 0x3F000000);
	}
	out.push(0 as uint8); out.push(2 as uint8); out.push(0 as uint8); out.push(0 as uint8);
	pushLe32(out, 0x3E800000);
	pushLe32(out, 0x3F000000);
	pushLe32(out, 0x3F800000);
	pushLe32(out, 0x3E800000);
	pushLe32(out, 0x3F800000);
	pushLe32(out, 0x3E800000);
	pushLe32(out, 0x3F000000);
	pushLe32(out, 0x3F400000);
	return out;
}

test "real FLOAT VEC4 sparse replaces RGBA at original nonconsecutive vertex ordinals" {
	const loaded = loadGltf(
		colourGltf(SPARSE_ACCESSOR, SPARSE_VIEWS, 164, "BLEND"),
		sparseBuffer(),
	);
	if (!loaded.ok) { console.log(loaded.error); }
	assert loaded.ok;
	if (!loaded.ok) { return; }
	const mesh = loaded.value.meshes[0];
	const red: Vec<float32> = [0.25, 0.5, 1.0];
	const green: Vec<float32> = [0.5, 0.25, 0.25];
	const blue: Vec<float32> = [1.0, 0.0, 0.5];
	const alpha: Vec<float32> = [0.25, 0.5, 0.75];
	for (let i = 0; i < 3; i++) {
		assert mesh.indices[i] == i;
		assert approx(mesh.vertices[i * 10 + 6], linearToSrgb(red[i] * 0.5));
		assert approx(mesh.vertices[i * 10 + 7], linearToSrgb(green[i] * 0.25));
		assert approx(mesh.vertices[i * 10 + 8], linearToSrgb(blue[i]));
		assert approx(mesh.vertices[i * 10 + 9], alpha[i] * 0.5);
	}
}

test "real old FLOAT VEC3 white matches absent colour with factor and alpha unchanged" {
	let buffer = triangleBuffer();
	for (let i = 0; i < 9; i++) { pushLe32(buffer, 0x3F800000); }
	const white = loadGltf(colourGltf(
		"{\"bufferView\":3,\"componentType\":5126,\"count\":3,\"type\":\"VEC3\"}",
		"{\"buffer\":0,\"byteOffset\":80,\"byteLength\":36}",
		116,
		"BLEND",
	), buffer);
	const missing = loadGltf(colourGltf("", "", 80, "BLEND"), triangleBuffer());
	assert white.ok && missing.ok;
	if (!white.ok || !missing.ok) { return; }
	const a = white.value.meshes[0];
	const b = missing.value.meshes[0];
	assert a.vertices.length == b.vertices.length;
	for (let i = 0; i < a.vertices.length; i++) { assert a.vertices[i] == b.vertices[i]; }
	assert approx(a.vertices[6], linearToSrgb(0.5)) && approx(a.vertices[7], linearToSrgb(0.25));
	assert a.vertices[8] == linearToSrgb(1.0) && a.vertices[9] == 0.5;
}

test "real colour views cannot read actual tail past declared buffer length" {
	const loaded = loadGltf(colourGltf(U8_ACCESSOR, U8_VIEW, 99, "BLEND"), u8Buffer());
	assert !loaded.ok;
}

test "real sparse colour refuses duplicate replacement indices" {
	let buffer = sparseBuffer();
	buffer[129] = 0 as uint8;
	const loaded = loadGltf(colourGltf(SPARSE_ACCESSOR, SPARSE_VIEWS, 164, "BLEND"), buffer);
	assert !loaded.ok;
}

test "real normalized colour refuses explicit null normalized" {
	const loaded = loadGltf(colourGltf(
		"{\"bufferView\":3,\"componentType\":5121,\"normalized\":null," +
		"\"count\":3,\"type\":\"VEC4\"}",
		U8_VIEW,
		104,
		"BLEND",
	), u8Buffer());
	assert !loaded.ok;
}

function colourGlb(json: string, bin: Readonly<Span<uint8>>): Vec<uint8> {
	let text: Vec<uint8> = [];
	for (let i = 0; i < json.byteLength(); i++) { text.push(json.byteAt(i) as uint8); }
	while ((text.length as int32) % 4 != 0) { text.push(0x20 as uint8); }
	let binary: Vec<uint8> = [];
	for (const byte of bin) { binary.push(byte); }
	while ((binary.length as int32) % 4 != 0) { binary.push(0 as uint8); }
	let out: Vec<uint8> = [];
	pushLe32(out, 0x46546C67); pushLe32(out, 2);
	pushLe32(out, (28 + text.length + binary.length) as uint32);
	pushLe32(out, text.length as uint32); pushLe32(out, 0x4E4F534A);
	for (const byte of text) { out.push(byte); }
	pushLe32(out, binary.length as uint32); pushLe32(out, 0x004E4942);
	for (const byte of binary) { out.push(byte); }
	return out;
}

test "real normalized u16 VEC3 GLB matches glTF exactly and supplies alpha one" {
	let buffer = triangleBuffer();
	const components: Vec<uint32> = [65535, 32768, 16384, 65535,
		16384, 65535, 32768, 65535, 32768, 16384, 65535, 65535];
	for (const value of components) {
		buffer.push((value & 255) as uint8); buffer.push((value >> 8) as uint8);
	}
	const json: string = colourGltf(
		"{\"bufferView\":3,\"componentType\":5123,\"normalized\":true," +
		"\"count\":3,\"type\":\"VEC3\"}",
		U8_VIEW,
		104,
		"BLEND",
	);
	const text = loadGltf(json, buffer);
	const binary = loadGlb(colourGlb(json, buffer));
	assert text.ok && binary.ok;
	if (!text.ok || !binary.ok) { return; }
	const a = text.value.meshes[0];
	const b = binary.value.meshes[0];
	assert a.vertices.length == b.vertices.length;
	for (let i = 0; i < a.vertices.length; i++) { assert a.vertices[i] == b.vertices[i]; }
	for (let i = 0; i < 3; i++) {
		const r: float32 = components[i * 4] as float32 / 65535.0;
		const g: float32 = components[i * 4 + 1] as float32 / 65535.0;
		const blue: float32 = components[i * 4 + 2] as float32 / 65535.0;
		assert approx(a.vertices[i * 10 + 6], linearToSrgb(r * 0.5));
		assert approx(a.vertices[i * 10 + 7], linearToSrgb(g * 0.25));
		assert approx(a.vertices[i * 10 + 8], linearToSrgb(blue));
		assert a.vertices[i * 10 + 9] == 0.5;
		assert a.indices[i] == b.indices[i] && a.indices[i] == i;
	}
}

test "real old FLOAT VEC3 keeps nonfinite and exhausted accessor OutOfRange errors" {
	const bits: Vec<uint32> = [0x7FC00000, 0x7F800000];
	for (const value of bits) {
		let buffer = triangleBuffer();
		pushLe32(buffer, value);
		for (let i = 1; i < 9; i++) { pushLe32(buffer, 0x3F800000); }
		const loaded = loadGltf(colourGltf(
			"{\"bufferView\":3,\"componentType\":5126,\"count\":3,\"type\":\"VEC3\"}",
			"{\"buffer\":0,\"byteOffset\":80,\"byteLength\":36}",
			116,
			"BLEND",
		), buffer);
		assert !loaded.ok;
		if (!loaded.ok) { assert loaded.error == GltfError.OutOfRange; }
	}
	let buffer = triangleBuffer();
	for (let i = 0; i < 9; i++) { pushLe32(buffer, 0x3F800000); }
	const loaded = loadGltf(colourGltf(
		"{\"bufferView\":3,\"byteOffset\":4,\"componentType\":5126," +
		"\"count\":3,\"type\":\"VEC3\"}",
		"{\"buffer\":0,\"byteOffset\":80,\"byteLength\":36}",
		116,
		"BLEND",
	), buffer);
	assert !loaded.ok;
	if (!loaded.ok) { assert loaded.error == GltfError.OutOfRange; }
}

test "real colour adapter refuses explicit null and wrong encoding instead of defaulting" {
	const accessors: Vec<string> = [
		"{\"bufferView\":null,\"componentType\":5121,\"normalized\":true," +
		"\"count\":3,\"type\":\"VEC4\"}",
		"{\"bufferView\":3,\"byteOffset\":null,\"componentType\":5121," +
		"\"normalized\":true,\"count\":3,\"type\":\"VEC4\"}",
		"{\"bufferView\":3,\"byteOffset\":1,\"componentType\":5121," +
		"\"normalized\":true,\"count\":3,\"type\":\"VEC4\"}",
		"{\"bufferView\":3,\"componentType\":5121,\"normalized\":true," +
		"\"count\":3,\"type\":\"VEC4\",\"sparse\":null}",
		"{\"bufferView\":3,\"componentType\":5121,\"normalized\":0,\"count\":3,\"type\":\"VEC4\"}",
		"{\"bufferView\":3,\"componentType\":5121,\"count\":3,\"type\":\"VEC4\"}",
		"{\"bufferView\":3,\"componentType\":5122,\"normalized\":true," +
		"\"count\":3,\"type\":\"VEC4\"}",
		"{\"bufferView\":3,\"componentType\":5126,\"normalized\":true," +
		"\"count\":3,\"type\":\"VEC4\"}",
	];
	for (const accessor of accessors) {
		const loaded = loadGltf(colourGltf(accessor, U8_VIEW, 104, "BLEND"), u8Buffer());
		assert !loaded.ok;
		if (!loaded.ok) { assert loaded.error == GltfError.Unsupported; }
	}
}

function strideFixture(
	shared: boolean,
	declared: boolean,
	reused: boolean = false,
): Result<GltfData, GltfError> {
	let bytes = triangleBuffer();
	for (let vertex = 0; vertex < 3; vertex++) {
		for (const value of [255, 128, 64, 255]) { bytes.push(value as uint8); }
		if (shared) {
			for (const value of [0, 255, 0, 0]) { bytes.push(value as uint8); }
		}
	}
	const length: int32 = shared ? 24 : 12;
	const stride: int32 = shared ? 8 : 4;
	const view: string = `{"buffer":0,"byteOffset":80,"byteLength":${length}`
		+ (declared ? `,"byteStride":${stride}}` : "}");
	const accessor: string = U8_ACCESSOR + (shared ?
		`,{"bufferView":3,"byteOffset":4,"componentType":5121,`
		+ `"normalized":true,"count":3,"type":"VEC4"}` : "");
	const extra: string = shared ? ',"COLOR_1":4' : reused ? ',"COLOR_1":3' : "";
	return loadGltf(colourGltf(accessor, view, 80 + length, "BLEND", extra), bytes);
}

test "own attribute view with no stride is tightly packed like Khronos Validator" {
	const loaded = strideFixture(false, false);
	assert loaded.ok;
	if (!loaded.ok) { return; }
	for (let vertex = 0; vertex < 3; vertex++) {
		assert approx(loaded.value.meshes[0].vertices[vertex * 10 + 7],
			linearToSrgb(128.0 / 255.0 * 0.25));
	}
}

test "own attribute view with explicit stride preserves decoded colour" {
	assert strideFixture(false, true).ok;
}

test "shared vertex accessor view without byteStride remains refused" {
	const loaded = strideFixture(true, false);
	assert !loaded.ok;
	if (!loaded.ok) { assert loaded.error == GltfError.Unsupported; }
}

test "shared vertex accessor view with byteStride preserves interleaved values" {
	const loaded = strideFixture(true, true);
	assert loaded.ok;
	if (!loaded.ok) { return; }
	for (let vertex = 0; vertex < 3; vertex++) {
		assert approx(loaded.value.meshes[0].vertices[vertex * 10 + 7],
			linearToSrgb(128.0 / 255.0 * 0.25));
	}
}

test "reusing one accessor as two attributes does not make two accessor view owners" {
	assert strideFixture(false, false, true).ok;
}

test "real colour adapter keeps attribute stride alignment target and metadata refusal" {
	const views: Vec<string> = [
		"{\"buffer\":0,\"byteOffset\":80,\"byteLength\":24,\"byteStride\":2}",
		"{\"buffer\":0,\"byteOffset\":80,\"byteLength\":24,\"byteStride\":6}",
		"{\"buffer\":0,\"byteOffset\":80,\"byteLength\":24,\"byteStride\":8,\"target\":34963}",
		"{\"buffer\":0,\"byteOffset\":80,\"byteLength\":24,\"byteStride\":null}",
		"{\"buffer\":0,\"byteOffset\":80,\"byteLength\":24,\"byteStride\":8,\"target\":null}",
		"{\"buffer\":0,\"byteOffset\":null,\"byteLength\":24,\"byteStride\":8}",
	];
	for (const view of views) {
		const loaded = loadGltf(colourGltf(U8_ACCESSOR, view, 104, "BLEND"), u8Buffer());
		assert !loaded.ok;
		if (!loaded.ok) { assert loaded.error == GltfError.Unsupported; }
	}
}

test "real old FLOAT VEC3 count and dense view keep legacy public error classes" {
	let buffer = triangleBuffer();
	for (let i = 0; i < 9; i++) { pushLe32(buffer, 0x3F800000); }
	const view: string = "{\"buffer\":0,\"byteOffset\":80,\"byteLength\":36}";
	const mismatch = loadGltf(colourGltf(
		"{\"bufferView\":3,\"componentType\":5126,\"count\":2,\"type\":\"VEC3\"}",
		view,
		116,
		"BLEND",
	), buffer);
	assert !mismatch.ok;
	if (!mismatch.ok) { assert mismatch.error == GltfError.CountMismatch; }
	const empty = loadGltf(colourGltf(
		"{\"bufferView\":3,\"componentType\":5126,\"count\":0,\"type\":\"VEC3\"}",
		view,
		116,
		"BLEND",
	), buffer);
	assert !empty.ok;
	if (!empty.ok) { assert empty.error == GltfError.OutOfRange; }
	const escaped = loadGltf(colourGltf(
		"{\"bufferView\":99,\"componentType\":5126,\"count\":3,\"type\":\"VEC3\"}",
		view,
		116,
		"BLEND",
	), buffer);
	assert !escaped.ok;
	if (!escaped.ok) { assert escaped.error == GltfError.Unsupported; }
}

test "real normal mapped RGBA GLB keeps source colours across Mikk mirror seam splits" {
	let buffer: Vec<uint8> = [];
	const x: Vec<uint32> = [0, 0x3F800000, 0x40000000];
	for (let i = 0; i < 6; i++) {
		pushLe32(buffer, x[i % 3]);
		pushLe32(buffer, (i < 3 ? 0 : 0x3F800000) as uint32); pushLe32(buffer, 0);
	}
	for (let i = 0; i < 6; i++) {
		pushLe32(buffer, 0); pushLe32(buffer, 0); pushLe32(buffer, 0x3F800000);
	}
	for (let i = 0; i < 6; i++) {
		pushLe32(buffer, (i % 3 == 1 ? 0 : 0x3F800000) as uint32);
		pushLe32(buffer, (i < 3 ? 0x3F800000 : 0) as uint32);
	}
	const colors: Vec<uint8> = [255, 128, 64, 32, 64, 255, 128, 64, 128, 64, 255, 96,
		255, 64, 128, 128, 64, 128, 255, 192, 128, 255, 64, 255];
	for (const byte of colors) { buffer.push(byte); }
	const indices: Vec<uint8> = [0, 1, 4, 0, 4, 3, 1, 2, 5, 1, 5, 4];
	for (const index of indices) { buffer.push(index); buffer.push(0 as uint8); }
	const png = rgbaPng();
	for (const byte of png) { buffer.push(byte); }
	const json: string =
		"{\"asset\":{\"version\":\"2.0\"},\"scene\":0,\"scenes\":[{\"nodes\":[0]}]," +
		"\"nodes\":[{\"mesh\":0}],\"meshes\":[{\"primitives\":[{\"attributes\":{" +
		"\"POSITION\":0,\"NORMAL\":1,\"TEXCOORD_0\":2,\"COLOR_0\":3}," +
		"\"indices\":4,\"material\":0}]}]," +
		"\"materials\":[{\"alphaMode\":\"MASK\",\"alphaCutoff\":0.2," +
		"\"normalTexture\":{\"index\":0}," +
		"\"pbrMetallicRoughness\":{\"baseColorFactor\":[0.5,0.25,1.0,0.5]," +
		"\"baseColorTexture\":{\"index\":0}}}]," +
		"\"textures\":[{\"source\":0}],\"images\":[{\"bufferView\":5," +
		"\"mimeType\":\"image/png\"}]," +
		"\"accessors\":[{\"bufferView\":0,\"componentType\":5126,\"count\":6," +
		"\"type\":\"VEC3\",\"min\":[0,0,0],\"max\":[2,1,0]}," +
		"{\"bufferView\":1,\"componentType\":5126,\"count\":6,\"type\":\"VEC3\"}," +
		"{\"bufferView\":2,\"componentType\":5126,\"count\":6,\"type\":\"VEC2\"}," +
		"{\"bufferView\":3,\"componentType\":5121,\"normalized\":true," +
		"\"count\":6,\"type\":\"VEC4\"}," +
		"{\"bufferView\":4,\"componentType\":5123,\"count\":12,\"type\":\"SCALAR\"}]," +
		"\"bufferViews\":[{\"buffer\":0,\"byteOffset\":0,\"byteLength\":72}," +
		"{\"buffer\":0,\"byteOffset\":72,\"byteLength\":72}," +
		"{\"buffer\":0,\"byteOffset\":144,\"byteLength\":48}," +
		"{\"buffer\":0,\"byteOffset\":192,\"byteLength\":24,\"byteStride\":4}," +
		"{\"buffer\":0,\"byteOffset\":216,\"byteLength\":24}," +
		"{\"buffer\":0,\"byteOffset\":240,\"byteLength\":" + png.length.toString() +
		"}],\"buffers\":[{\"byteLength\":" + buffer.length.toString() + "}]}";
	const loaded = loadGlb(colourGlb(json, buffer));
	assert loaded.ok;
	if (!loaded.ok) { return; }
	const data = loaded.value;
	const mesh = data.meshes[0];
	assert mesh.hasTangents && mesh.vertexCount() == 8 && mesh.stride() == 16;
	assert data.materials[0].normalTexture == 0 &&
		data.materials[0].alphaMode == GltfAlphaMode.Mask;
	assert (data.textures[0].pixels[3] >> 24) == 128;
	for (let i = 0; i < mesh.vertexCount(); i++) {
		const at: int32 = i * mesh.stride();
		const source: int32 = mesh.vertices[at] as int32 + (mesh.vertices[at + 1] == 0.0 ? 0 : 3);
		const r: float32 = colors[source * 4] as float32 / 255.0;
		const g: float32 = colors[source * 4 + 1] as float32 / 255.0;
		const b: float32 = colors[source * 4 + 2] as float32 / 255.0;
		const a: float32 = colors[source * 4 + 3] as float32 / 255.0;
		assert approx(mesh.vertices[at + 8], linearToSrgb(r * 0.5));
		assert approx(mesh.vertices[at + 9], linearToSrgb(g * 0.25));
		assert approx(mesh.vertices[at + 10], linearToSrgb(b));
		assert approx(mesh.vertices[at + 11], a * 0.5);
	}
	for (let corner = 0; corner < 12; corner++) {
		const at: int32 = (mesh.indices[corner] as int32) * mesh.stride();
		const source: int32 = mesh.vertices[at] as int32 + (mesh.vertices[at + 1] == 0.0 ? 0 : 3);
		assert source == indices[corner] as int32;
		assert mesh.vertices[at + 15] == (corner < 6 ? -1.0 : 1.0);
	}
}
