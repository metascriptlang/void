import { approx } from "./helpers";
import { contextOf } from "./drawHelpers";
import { DrawContext, MeshId, releaseMesh } from "../void3d/draw";
import { Mat4, composeTransform, writeTo } from "../math/math3d";
import { loadGltf, GltfError } from "../void3d/gltf";
import { addGltfNodes, GltfMeshBinding, GltfSceneError } from "../void3d/gltfScene";
import { Scene3D, SceneError, syncWorld, findByName, worldOf, rootId } from "../void3d/scene";
import { MeshData, vertexCount, triangleCount, indexCount } from "../void3d/meshData";
// The buffer a test builds by hand, in the bit patterns the decoder must see: every float
// here is 0.0 (0x00000000) or 1.0 (0x3F800000), so the bytes below are the IEEE-754
// little-endian encodings of those two values and nothing else.
const F32_ZERO: uint32 = 0x00000000;
const F32_ONE: uint32 = 0x3F800000;

function pushLe32(ref out: Vec<uint8>, bits: uint32): void {
	out.push((bits & 0xFF) as uint8);
	out.push(((bits >> 8) & 0xFF) as uint8);
	out.push(((bits >> 16) & 0xFF) as uint8);
	out.push(((bits >> 24) & 0xFF) as uint8);
}

// positions at 0: (0,0,0) (1,0,0) (0,1,0); normals at 36: three times (0,0,1);
// colors at 72: (1,0,0) (0,1,0) (0,0,1); indices at 108: 0, 1, 2.
function triangleBuffer(): Vec<uint8> {
	let out: Vec<uint8> = [];
	pushLe32(out, F32_ZERO); pushLe32(out, F32_ZERO); pushLe32(out, F32_ZERO);
	pushLe32(out, F32_ONE); pushLe32(out, F32_ZERO); pushLe32(out, F32_ZERO);
	pushLe32(out, F32_ZERO); pushLe32(out, F32_ONE); pushLe32(out, F32_ZERO);
	for (let i = 0; i < 3; i++) {
		pushLe32(out, F32_ZERO); pushLe32(out, F32_ZERO); pushLe32(out, F32_ONE);
	}
	pushLe32(out, F32_ONE); pushLe32(out, F32_ZERO); pushLe32(out, F32_ZERO);
	pushLe32(out, F32_ZERO); pushLe32(out, F32_ONE); pushLe32(out, F32_ZERO);
	pushLe32(out, F32_ZERO); pushLe32(out, F32_ZERO); pushLe32(out, F32_ONE);
	out.push(0 as uint8); out.push(0 as uint8);
	out.push(1 as uint8); out.push(0 as uint8);
	out.push(2 as uint8); out.push(0 as uint8);
	return out;
}

function triangleGltf(): string {
	return "{\"asset\":{\"version\":\"2.0\"},\"scene\":0,"
		+ "\"scenes\":[{\"nodes\":[0]}],"
		+ "\"nodes\":[{\"name\":\"tri\",\"mesh\":0,"
		+ "\"translation\":[0.0,0.0,0.0],\"rotation\":[0.0,0.0,0.0,1.0],\"scale\":[1.0,1.0,1.0]}],"
		+ "\"meshes\":[{\"primitives\":[{\"attributes\":"
		+ "{\"POSITION\":0,\"NORMAL\":1,\"COLOR_0\":2},\"indices\":3}]}],"
		+ "\"accessors\":["
		+ "{\"bufferView\":0,\"componentType\":5126,\"count\":3,\"type\":\"VEC3\"},"
		+ "{\"bufferView\":1,\"componentType\":5126,\"count\":3,\"type\":\"VEC3\"},"
		+ "{\"bufferView\":2,\"componentType\":5126,\"count\":3,\"type\":\"VEC3\"},"
		+ "{\"bufferView\":3,\"componentType\":5123,\"count\":3,\"type\":\"SCALAR\"}],"
		+ "\"bufferViews\":["
		+ "{\"buffer\":0,\"byteOffset\":0,\"byteLength\":36},"
		+ "{\"buffer\":0,\"byteOffset\":36,\"byteLength\":36},"
		+ "{\"buffer\":0,\"byteOffset\":72,\"byteLength\":36},"
		+ "{\"buffer\":0,\"byteOffset\":108,\"byteLength\":6}],"
		+ "\"buffers\":[{\"byteLength\":114}]}";
}

function treeGltf(): string {
	return "{\"asset\":{\"version\":\"2.0\"},\"scene\":0,"
		+ "\"scenes\":[{\"nodes\":[0]}],"
		+ "\"nodes\":["
		+ "{\"name\":\"scaled\",\"scale\":[2.0,3.0,4.0],\"children\":[1]},"
		+ "{\"name\":\"tri\",\"mesh\":0,\"translation\":[1.0,0.0,0.0]}],"
		+ "\"meshes\":[{\"primitives\":[{\"attributes\":"
		+ "{\"POSITION\":0,\"NORMAL\":1,\"COLOR_0\":2},\"indices\":3}]}],"
		+ "\"accessors\":["
		+ "{\"bufferView\":0,\"componentType\":5126,\"count\":3,\"type\":\"VEC3\"},"
		+ "{\"bufferView\":1,\"componentType\":5126,\"count\":3,\"type\":\"VEC3\"},"
		+ "{\"bufferView\":2,\"componentType\":5126,\"count\":3,\"type\":\"VEC3\"},"
		+ "{\"bufferView\":3,\"componentType\":5123,\"count\":3,\"type\":\"SCALAR\"}],"
		+ "\"bufferViews\":["
		+ "{\"buffer\":0,\"byteOffset\":0,\"byteLength\":36},"
		+ "{\"buffer\":0,\"byteOffset\":36,\"byteLength\":36},"
		+ "{\"buffer\":0,\"byteOffset\":72,\"byteLength\":36},"
		+ "{\"buffer\":0,\"byteOffset\":108,\"byteLength\":6}],"
		+ "\"buffers\":[{\"byteLength\":114}]}";
}

function nodeOnlyGltf(node: string, root: string = "0"): string {
	return "{\"asset\":{\"version\":\"2.0\"},\"scenes\":[{\"nodes\":[" + root + "]}],"
		+ "\"nodes\":[" + node + "],\"meshes\":[],\"accessors\":[],"
		+ "\"bufferViews\":[],\"buffers\":[]}";
}


function interleavedTriangleBuffer(): Vec<uint8> {
	const source = triangleBuffer();
	let out: Vec<uint8> = [];
	for (let i = 0; i < 3; i++) {
		for (let j = 0; j < 12; j++) { out.push(source[i * 12 + j]); }
		for (let j = 0; j < 12; j++) { out.push(source[36 + i * 12 + j]); }
	}
	for (let i = 72; i < source.length; i++) { out.push(source[i]); }
	return out;
}

function interleavedTriangleGltf(): string {
	return triangleGltf()
		.replace(`{"bufferView":1,"componentType":5126`,
			`{"bufferView":0,"byteOffset":12,"componentType":5126`)
		.replace(`"byteOffset":0,"byteLength":36`,
			`"byteOffset":0,"byteLength":72,"byteStride":24`);
}

function sparseTriangleGltf(): string {
	return triangleGltf()
		.replace(`{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3"}`,
			`{"componentType":5126,"count":3,"type":"VEC3","sparse":{"count":3,` +
			`"indices":{"bufferView":4,"componentType":5121},"values":{"bufferView":0}}}`)
		.replace(`{"bufferView":1,"componentType":5126,"count":3,"type":"VEC3"}`,
			`{"componentType":5126,"count":3,"type":"VEC3","sparse":{"count":3,` +
			`"indices":{"bufferView":4,"componentType":5121},"values":{"bufferView":1}}}`)
		.replace(`"byteOffset":108,"byteLength":6}]`,
			`"byteOffset":108,"byteLength":6},` +
			`{"buffer":0,"byteOffset":114,"byteLength":3}]`)
		.replace(`"buffers":[{"byteLength":114}]`, `"buffers":[{"byteLength":117}]`);
}

function sparseTriangleBuffer(): Vec<uint8> {
	let out = triangleBuffer();
	for (let i = 0; i < 3; i++) { out.push(i as uint8); }
	return out;
}

function sameTriangle(this actual: MeshData, expected: MeshData): boolean {
	if (actual.vertices.length != expected.vertices.length ||
		actual.indices.length != expected.indices.length) { return false; }
	for (let i = 0; i < actual.vertices.length; i++) {
		if (actual.vertices[i] != expected.vertices[i]) { return false; }
	}
	for (let i = 0; i < actual.indices.length; i++) {
		if (actual.indices[i] != expected.indices[i]) { return false; }
	}
	return actual.hasUvs == expected.hasUvs && actual.hasTangents == expected.hasTangents;
}

test "loadGltf interleaved and sparse positions and normals match the dense consumer" {
	const dense = loadGltf(triangleGltf(), triangleBuffer());
	assert dense.ok;
	if (!dense.ok) { return; }
	for (const sparse of [false, true]) {
		const json = sparse ? sparseTriangleGltf() : interleavedTriangleGltf();
		const bytes = sparse ? sparseTriangleBuffer() : interleavedTriangleBuffer();
		const loaded = loadGltf(json, bytes);
		assert loaded.ok;
		if (!loaded.ok) { continue; }
		assert loaded.value.meshes[0].sameTriangle(dense.value.meshes[0]);
		assert loaded.value.nodes[0].name == "tri" && loaded.value.nodes[0].mesh == 0;
	}
}

test "loadGltf sparse replacements override an existing position base" {
	const dense = loadGltf(triangleGltf(), triangleBuffer());
	assert dense.ok;
	if (!dense.ok) { return; }
	const source = triangleBuffer();
	let bytes = triangleBuffer();
	for (let i = 12; i < 36; i++) { bytes[i] = 0 as uint8; }
	bytes.push(1 as uint8);
	bytes.push(2 as uint8);
	for (let i = 12; i < 36; i++) { bytes.push(source[i]); }
	const json = triangleGltf()
		.replace(`{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3"}`,
			`{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3",` +
			`"sparse":{"count":2,"indices":{"bufferView":4,"componentType":5121},` +
			`"values":{"bufferView":5}}}`)
		.replace(`"byteOffset":108,"byteLength":6}]`,
			`"byteOffset":108,"byteLength":6},` +
			`{"buffer":0,"byteOffset":114,"byteLength":2},` +
			`{"buffer":0,"byteOffset":116,"byteLength":24}]`)
		.replace(`"buffers":[{"byteLength":114}]`, `"buffers":[{"byteLength":140}]`);
	const loaded = loadGltf(json, bytes);
	assert loaded.ok;
	if (loaded.ok) { assert loaded.value.meshes[0].sameTriangle(dense.value.meshes[0]); }
}

test "loadGltf interleaved attributes still reject invalid stride bounds count and encoding" {
	const json = interleavedTriangleGltf();
	const bytes = interleavedTriangleBuffer();
	for (const bad of [
		json.replace(`"byteStride":24`, `"byteStride":23`),
		json.replace(`"byteStride":24`, `"byteStride":8`),
		json.replace(`"byteOffset":12,`, `"byteOffset":12,"normalized":true,`),
		json.replace(`"componentType":5126`, `"componentType":5123`),
	]) {
		const loaded = loadGltf(bad, bytes);
		assert !loaded.ok;
		if (!loaded.ok) { assert loaded.error == GltfError.Unsupported; }
	}
	const short = loadGltf(json.replace(`"byteLength":72`, `"byteLength":71`), bytes);
	assert !short.ok;
	if (!short.ok) { assert short.error == GltfError.OutOfRange; }
	const count = loadGltf(json.replace(`"byteOffset":12,"componentType":5126,"count":3`,
		`"byteOffset":12,"componentType":5126,"count":2`), bytes);
	assert !count.ok;
	if (!count.ok) { assert count.error == GltfError.CountMismatch; }
}

test "loadGltf sparse geometry rejects duplicate outside indices and nonfinite replacements" {
	const json = sparseTriangleGltf();
	for (const index of [0, 3]) {
		let bytes = sparseTriangleBuffer();
		bytes[115] = index as uint8;
		const loaded = loadGltf(json, bytes);
		assert !loaded.ok;
		if (!loaded.ok) { assert loaded.error == GltfError.Unsupported; }
	}
	let bytes = sparseTriangleBuffer();
	bytes[2] = 0xc0 as uint8;
	bytes[3] = 0x7f as uint8;
	const nonfinite = loadGltf(json, bytes);
	assert !nonfinite.ok;
	if (!nonfinite.ok) { assert nonfinite.error == GltfError.OutOfRange; }
}

test "loadGltf decodes a hand-built triangle into one indexed MeshData" {
	const loaded = loadGltf(triangleGltf(), triangleBuffer());
	assert loaded.ok;
	if (!loaded.ok) { return; }
	const data = loaded.value;
	assert (data.meshes.length as int32) == 1;
	const mesh = data.meshes[0];
	assert mesh.vertexCount() == 3;
	assert mesh.triangleCount() == 1;
	assert mesh.indices[0] == 0 && mesh.indices[1] == 1 && mesh.indices[2] == 2;
	assert approx(mesh.vertices[3], 0.0) && approx(mesh.vertices[4], 0.0)
		&& approx(mesh.vertices[5], 1.0);
	assert approx(mesh.vertices[13], 0.0) && approx(mesh.vertices[14], 0.0)
		&& approx(mesh.vertices[15], 1.0);
	assert approx(mesh.vertices[6], 1.0) && approx(mesh.vertices[7], 0.0)
		&& approx(mesh.vertices[8], 0.0);
	assert approx(mesh.vertices[16], 0.0) && approx(mesh.vertices[17], 1.0)
		&& approx(mesh.vertices[18], 0.0);
	assert (data.sceneRoots.length as int32) == 1 && data.sceneRoots[0] == 0;
}

test "a node's TRS comes through with glTF's defaults when a field is absent" {
	const loaded = loadGltf(triangleGltf(), triangleBuffer());
	assert loaded.ok;
	if (!loaded.ok) { return; }
	const node = loaded.value.nodes[0];
	assert node.name == "tri";
	assert node.mesh == 0;
	assert approx(node.local.position.x, 0.0) && approx(node.local.position.y, 0.0);
	assert approx(node.local.rotation.w, 1.0);
	assert approx(node.local.scale.x, 1.0) && approx(node.local.scale.z, 1.0);
	const moved = loadGltf(
		"{\"asset\":{\"version\":\"2.0\"},\"scenes\":[{\"nodes\":[0]}],"
		+ "\"nodes\":[{\"name\":\"n\",\"translation\":[0.5,0.25,1.0],\"scale\":[2.0,2.0,2.0]}],"
		+ "\"meshes\":[],\"accessors\":[],\"bufferViews\":[],\"buffers\":[]}",
		[],
	);
	assert moved.ok;
	if (!moved.ok) { return; }
	const placed = moved.value.nodes[0];
	assert approx(placed.local.position.x, 0.5);
	assert approx(placed.local.position.y, 0.25);
	assert approx(placed.local.position.z, 1.0);
	assert approx(placed.local.scale.x, 2.0);
	assert placed.mesh == -1;
}

test "addGltfNodes preserves names, hierarchy, bindings and non-uniform scale" {
	let context: DrawContext = contextOf(8, 10);
	const loaded = loadGltf(treeGltf(), triangleBuffer());
	assert loaded.ok;
	if (!loaded.ok) { return; }
	let scene: Scene3D = Scene3D.create(context);
	const missing: Result<int32, GltfSceneError> =
		addGltfNodes(scene, scene.rootId(), loaded.value, []);
	assert !missing.ok;
	if (!missing.ok) { assert missing.error == GltfSceneError.BadMeshBinding; }
	const released: MeshId = context.meshAt(6);
	assert releaseMesh(context, released).ok;
	const invalidBindings: Vec<GltfMeshBinding> =
		[{ mesh: released, material: context.materialAt(9) }];
	const invalid: Result<int32, GltfSceneError> =
		addGltfNodes(scene, scene.rootId(), loaded.value, invalidBindings);
	assert !invalid.ok;
	if (!invalid.ok) { assert invalid.error == GltfSceneError.BadMeshBinding; }
	let other: DrawContext = contextOf(8, 10);
	const foreignBindings: Vec<GltfMeshBinding> =
		[{ mesh: other.meshAt(7), material: context.materialAt(9) }];
	const foreign: Result<int32, GltfSceneError> =
		addGltfNodes(scene, scene.rootId(), loaded.value, foreignBindings);
	assert !foreign.ok;
	if (!foreign.ok) { assert foreign.error == GltfSceneError.ForeignMeshBinding; }
	const bindings: Vec<GltfMeshBinding> =
		[{ mesh: context.meshAt(7), material: context.materialAt(9) }];
	const added: Result<int32, GltfSceneError> =
		addGltfNodes(scene, scene.rootId(), loaded.value, bindings);
	assert added.ok;
	if (!added.ok) { return; }
	assert added.value == 2;
	assert syncWorld(scene) == 3;
	const scaled = scene.findByName(scene.rootId(), "scaled");
	const tri = scene.findByName(scene.rootId(), "tri");
	assert scaled.ok && tri.ok;
	if (!tri.ok) { return; }
	const world: Result<Mat4, SceneError> = scene.worldOf(tri.value);
	assert world.ok;
	if (!world.ok) { return; }
	assert approx(world.value.m11, 2.0);
	assert approx(world.value.m22, 3.0);
	assert approx(world.value.m33, 4.0);
	assert approx(world.value.m41, 2.0);
	const payload: int32 = scene.nodes[tri.value.index].payload;
	assert scene.meshes[payload].mesh.index == 7;
	assert scene.meshes[payload].material.index == 9;
	assert context.meshHolders[7] == 2 && context.materialHolders[9] == 2;
}

test "COLOR_0 absent means white, and a wrong count is refused" {
	const noColor = loadGltf(
		"{\"asset\":{\"version\":\"2.0\"},\"scenes\":[{\"nodes\":[0]}],"
		+ "\"nodes\":[{\"mesh\":0}],"
		+ "\"meshes\":[{\"primitives\":[{\"attributes\":{\"POSITION\":0,\"NORMAL\":1},"
		+ "\"indices\":2}]}],"
		+ "\"accessors\":["
		+ "{\"bufferView\":0,\"componentType\":5126,\"count\":3,\"type\":\"VEC3\"},"
		+ "{\"bufferView\":1,\"componentType\":5126,\"count\":3,\"type\":\"VEC3\"},"
		+ "{\"bufferView\":2,\"componentType\":5123,\"count\":3,\"type\":\"SCALAR\"}],"
		+ "\"bufferViews\":["
		+ "{\"buffer\":0,\"byteOffset\":0,\"byteLength\":36},"
		+ "{\"buffer\":0,\"byteOffset\":36,\"byteLength\":36},"
		+ "{\"buffer\":0,\"byteOffset\":108,\"byteLength\":6}],"
		+ "\"buffers\":[{\"byteLength\":114}]}",
		triangleBuffer(),
	);
	assert noColor.ok;
	if (!noColor.ok) { return; }
	const mesh = noColor.value.meshes[0];
	assert approx(mesh.vertices[6], 1.0) && approx(mesh.vertices[7], 1.0)
		&& approx(mesh.vertices[8], 1.0);
	const mismatch = loadGltf(
		"{\"asset\":{\"version\":\"2.0\"},\"scenes\":[{\"nodes\":[0]}],"
		+ "\"nodes\":[{\"mesh\":0}],"
		+ "\"meshes\":[{\"primitives\":[{\"attributes\":{\"POSITION\":0,\"NORMAL\":1}}]}],"
		+ "\"accessors\":["
		+ "{\"bufferView\":0,\"componentType\":5126,\"count\":3,\"type\":\"VEC3\"},"
		+ "{\"bufferView\":1,\"componentType\":5126,\"count\":2,\"type\":\"VEC3\"}],"
		+ "\"bufferViews\":["
		+ "{\"buffer\":0,\"byteOffset\":0,\"byteLength\":36},"
		+ "{\"buffer\":0,\"byteOffset\":36,\"byteLength\":24}],"
		+ "\"buffers\":[{\"byteLength\":60}]}",
		triangleBuffer(),
	);
	assert !mismatch.ok;
	if (!mismatch.ok) { assert mismatch.error == GltfError.CountMismatch; }
}

// positions at 0: (0,0,0) (1,0,0) (0,1,0) (0,0,1); indices at 48: 0 1 2, 0 3 1, 0 1 1.
function bentBuffer(): Vec<uint8> {
	let out: Vec<uint8> = [];
	for (const bits of [
		F32_ZERO, F32_ZERO, F32_ZERO, F32_ONE, F32_ZERO, F32_ZERO,
		F32_ZERO, F32_ONE, F32_ZERO, F32_ZERO, F32_ZERO, F32_ONE,
	]) { pushLe32(out, bits); }
	for (const index of [0, 1, 2, 0, 3, 1, 0, 1, 1]) {
		out.push(index as uint8); out.push(0 as uint8);
	}
	return out;
}

function bentDocument(primitive: string): string {
	return "{\"asset\":{\"version\":\"2.0\"},\"scenes\":[{\"nodes\":[0]}],"
		+ "\"nodes\":[{\"mesh\":0}],"
		+ "\"meshes\":[{\"primitives\":[{\"attributes\":{\"POSITION\":0}" + primitive + "}]}],"
		+ "\"accessors\":["
		+ "{\"bufferView\":0,\"componentType\":5126,\"count\":4,\"type\":\"VEC3\"},"
		+ "{\"bufferView\":1,\"componentType\":5123,\"count\":9,\"type\":\"SCALAR\"}],"
		+ "\"bufferViews\":["
		+ "{\"buffer\":0,\"byteOffset\":0,\"byteLength\":48},"
		+ "{\"buffer\":0,\"byteOffset\":48,\"byteLength\":18}],"
		+ "\"buffers\":[{\"byteLength\":66}]}";
}

function normalIs(mesh: MeshData, vertex: int32, x: float32, y: float32, z: float32): boolean {
	const at: int32 = vertex * 10 + 3;
	return approx(mesh.vertices[at], x) && approx(mesh.vertices[at + 1], y)
		&& approx(mesh.vertices[at + 2], z);
}

test "a primitive without NORMAL gets a vertex per corner and its triangle's flat normal" {
	const indexed = loadGltf(bentDocument(",\"indices\":1"), bentBuffer());
	assert indexed.ok;
	if (!indexed.ok) { return; }
	const mesh: MeshData = indexed.value.meshes[0];
	assert mesh.vertexCount() == 9 && mesh.indexCount() == 0;
	for (let corner = 0; corner < 3; corner++) {
		assert normalIs(mesh, corner, 0.0, 0.0, 1.0);
		assert normalIs(mesh, corner + 3, 0.0, 1.0, 0.0);
		assert normalIs(mesh, corner + 6, 0.0, 0.0, 0.0);
	}
	assert approx(mesh.vertices[40], 0.0) && approx(mesh.vertices[42], 1.0);
	const half: float32 = Math.sqrt(1.0 / 3.0) as float32;
	const strip = loadGltf(bentDocument(",\"mode\":5"), bentBuffer());
	assert strip.ok;
	if (!strip.ok) { return; }
	assert strip.value.meshes[0].vertexCount() == 6;
	assert normalIs(strip.value.meshes[0], 0, 0.0, 0.0, 1.0);
	assert normalIs(strip.value.meshes[0], 4, -half, -half, -half);
	assert !normalIs(strip.value.meshes[0], 4, 0.0, 0.0, 1.0);
}

// triangleBuffer() in base64.
const TRIANGLE_BASE64: string =
	"AAAAAAAAAAAAAAAAAACAPwAAAAAAAAAAAAAAAAAAgD8AAAAAAAAAAAAAAAAAAIA/AAAAAAAAAAAAAIA/"
	+ "AAAAAAAAAAAAAIA/AACAPwAAAAAAAAAAAAAAAAAAgD8AAAAAAAAAAAAAAAAAAIA/AAABAAIA";

function embedded(uri: string): string {
	return "{\"asset\":{\"version\":\"2.0\"},\"scenes\":[{\"nodes\":[0]}],"
		+ "\"nodes\":[{\"mesh\":0}],"
		+ "\"meshes\":[{\"primitives\":[{\"attributes\":{\"POSITION\":0,\"NORMAL\":1},"
		+ "\"indices\":2}]}],"
		+ "\"accessors\":["
		+ "{\"bufferView\":0,\"componentType\":5126,\"count\":3,\"type\":\"VEC3\"},"
		+ "{\"bufferView\":1,\"componentType\":5126,\"count\":3,\"type\":\"VEC3\"},"
		+ "{\"bufferView\":2,\"componentType\":5123,\"count\":3,\"type\":\"SCALAR\"}],"
		+ "\"bufferViews\":["
		+ "{\"buffer\":0,\"byteOffset\":0,\"byteLength\":36},"
		+ "{\"buffer\":0,\"byteOffset\":36,\"byteLength\":36},"
		+ "{\"buffer\":0,\"byteOffset\":108,\"byteLength\":6}],"
		+ "\"buffers\":[{\"byteLength\":114,\"uri\":\"" + uri + "\"}]}";
}

test "a buffer embedded as a base64 data: URI loads as the same bytes supplied would" {
	const supplied = loadGltf(embedded("triangle.bin"), triangleBuffer());
	assert supplied.ok;
	if (!supplied.ok) { return; }
	for (const mime of ["application/octet-stream", "application/gltf-buffer"]) {
		const inline = loadGltf(embedded(`data:${mime};base64,${TRIANGLE_BASE64}`), []);
		assert inline.ok;
		if (!inline.ok) { continue; }
		const mesh: MeshData = inline.value.meshes[0];
		assert mesh.vertexCount() == 3 && mesh.indexCount() == 3;
		for (let i = 0; i < mesh.vertices.length; i++) {
			assert mesh.vertices[i] == supplied.value.meshes[0].vertices[i];
		}
	}
	const both = loadGltf(embedded(`data:application/octet-stream;base64,${TRIANGLE_BASE64}`),
		triangleBuffer());
	assert !both.ok && both.error == GltfError.Unsupported;
	for (const uri of [
		`data:image/png;base64,${TRIANGLE_BASE64}`,
		`data:application/octet-stream,${TRIANGLE_BASE64}`,
		`data:application/octet-stream;base64,${TRIANGLE_BASE64.substring(1)}`,
	]) {
		const refused = loadGltf(embedded(uri), []);
		assert !refused.ok && refused.error == GltfError.Unsupported;
	}
	const short = loadGltf(embedded("data:application/gltf-buffer;base64,AAAA"), []);
	assert !short.ok && short.error == GltfError.OutOfRange;
}

function twoBuffers(first: string, second: string, normals: int32, secondLength: int32): string {
	return "{\"asset\":{\"version\":\"2.0\"},\"scenes\":[{\"nodes\":[0]}],"
		+ "\"nodes\":[{\"mesh\":0}],"
		+ "\"meshes\":[{\"primitives\":[{\"attributes\":{\"POSITION\":0,\"NORMAL\":1},"
		+ "\"indices\":2}]}],"
		+ "\"accessors\":["
		+ "{\"bufferView\":0,\"componentType\":5126,\"count\":3,\"type\":\"VEC3\"},"
		+ "{\"bufferView\":1,\"componentType\":5126,\"count\":3,\"type\":\"VEC3\"},"
		+ "{\"bufferView\":2,\"componentType\":5123,\"count\":3,\"type\":\"SCALAR\"}],"
		+ "\"bufferViews\":["
		+ "{\"buffer\":0,\"byteOffset\":0,\"byteLength\":36},"
		+ `{"buffer":${normals},"byteOffset":36,"byteLength":36},`
		+ "{\"buffer\":0,\"byteOffset\":108,\"byteLength\":6}],"
		+ "\"buffers\":[{\"byteLength\":114,\"uri\":\"" + first + "\"},"
		+ `{"byteLength":${secondLength},"uri":"${second}"}]}`;
}

test "a view reads the buffer it names, the first supplied or embedded and the rest embedded" {
	const one = loadGltf(embedded("triangle.bin"), triangleBuffer());
	assert one.ok;
	if (!one.ok) { return; }
	const inline: string = `data:application/octet-stream;base64,${TRIANGLE_BASE64}`;
	for (const first of ["triangle.bin", inline]) {
		const supplied: Vec<uint8> = first == inline ? [] : triangleBuffer();
		const split = loadGltf(twoBuffers(first, inline, 1, 114), supplied);
		assert split.ok;
		if (!split.ok) { continue; }
		const mesh: MeshData = split.value.meshes[0];
		assert mesh.vertexCount() == 3 && mesh.indexCount() == 3;
		for (let i = 0; i < mesh.vertices.length; i++) {
			assert mesh.vertices[i] == one.value.meshes[0].vertices[i];
		}
	}
	const external = loadGltf(twoBuffers("triangle.bin", "second.bin", 1, 114), triangleBuffer());
	assert !external.ok && external.error == GltfError.BufferByUri;
	const missing = loadGltf(twoBuffers("triangle.bin", inline, 2, 114), triangleBuffer());
	assert !missing.ok && missing.error == GltfError.BadReference;
	const short = loadGltf(twoBuffers("triangle.bin", inline, 1, 60), triangleBuffer());
	assert !short.ok && short.error == GltfError.OutOfRange;
}

test "malformed TRS, cyclic nodes and accessors past their buffer view fail loudly" {
	const badScale = loadGltf(
		"{\"asset\":{\"version\":\"2.0\"},\"scenes\":[{\"nodes\":[0]}],"
		+ "\"nodes\":[{\"scale\":[1.0,2.0]}],\"meshes\":[],"
		+ "\"accessors\":[],\"bufferViews\":[],\"buffers\":[]}",
		[],
	);
	assert !badScale.ok;
	if (!badScale.ok) { assert badScale.error == GltfError.Unsupported; }
	const cycle = loadGltf(
		"{\"asset\":{\"version\":\"2.0\"},\"scenes\":[{\"nodes\":[0]}],"
		+ "\"nodes\":[{\"children\":[0]}],\"meshes\":[],"
		+ "\"accessors\":[],\"bufferViews\":[],\"buffers\":[]}",
		[],
	);
	assert !cycle.ok;
	if (!cycle.ok) { assert cycle.error == GltfError.BadNode; }
	const lines = loadGltf(
		"{\"asset\":{\"version\":\"2.0\"},\"scenes\":[{\"nodes\":[0]}],"
		+ "\"nodes\":[{\"mesh\":0}],"
		+ "\"meshes\":[{\"primitives\":[{\"mode\":1,\"attributes\":{}}]}],"
		+ "\"accessors\":[],\"bufferViews\":[],\"buffers\":[{\"byteLength\":0}]}",
		[],
	);
	assert !lines.ok;
	if (!lines.ok) { assert lines.error == GltfError.Unsupported; }
	const fractionalMode = loadGltf(
		"{\"asset\":{\"version\":\"2.0\"},\"scenes\":[{\"nodes\":[0]}],"
		+ "\"nodes\":[{\"mesh\":0}],"
		+ "\"meshes\":[{\"primitives\":[{\"mode\":4.5,\"attributes\":{}}]}],"
		+ "\"accessors\":[],\"bufferViews\":[],\"buffers\":[{\"byteLength\":0}]}",
		[],
	);
	assert !fractionalMode.ok;
	if (!fractionalMode.ok) { assert fractionalMode.error == GltfError.Unsupported; }
	const escapedView = loadGltf(
		"{\"asset\":{\"version\":\"2.0\"},\"scenes\":[{\"nodes\":[0]}],"
		+ "\"nodes\":[{\"mesh\":0}],"
		+ "\"meshes\":[{\"primitives\":[{\"attributes\":{\"POSITION\":0,\"NORMAL\":1}}]}],"
		+ "\"accessors\":["
		+ "{\"bufferView\":0,\"componentType\":5126,\"count\":3,\"type\":\"VEC3\"},"
		+ "{\"bufferView\":1,\"componentType\":5126,\"count\":3,\"type\":\"VEC3\"}],"
		+ "\"bufferViews\":["
		+ "{\"buffer\":0,\"byteOffset\":0,\"byteLength\":35},"
		+ "{\"buffer\":0,\"byteOffset\":36,\"byteLength\":36}],"
		+ "\"buffers\":[{\"byteLength\":72}]}",
		triangleBuffer(),
	);
	assert !escapedView.ok;
	if (!escapedView.ok) { assert escapedView.error == GltfError.OutOfRange; }
	const zeroCount = loadGltf(
		"{\"asset\":{\"version\":\"2.0\"},\"scenes\":[{\"nodes\":[0]}],"
		+ "\"nodes\":[{\"mesh\":0}],"
		+ "\"meshes\":[{\"primitives\":[{\"attributes\":{\"POSITION\":0,\"NORMAL\":0},"
		+ "\"indices\":1}]}],"
		+ "\"accessors\":["
		+ "{\"bufferView\":0,\"componentType\":5126,\"count\":0,\"type\":\"VEC3\"},"
		+ "{\"bufferView\":1,\"componentType\":5123,\"count\":3,\"type\":\"SCALAR\"}],"
		+ "\"bufferViews\":[{\"buffer\":0,\"byteLength\":0},{\"buffer\":0,\"byteLength\":6}],"
		+ "\"buffers\":[{\"byteLength\":6}]}",
		triangleBuffer(),
	);
	assert !zeroCount.ok;
	const misaligned = loadGltf(
		"{\"asset\":{\"version\":\"2.0\"},\"scenes\":[{\"nodes\":[0]}],"
		+ "\"nodes\":[{\"mesh\":0}],"
		+ "\"meshes\":[{\"primitives\":[{\"attributes\":{\"POSITION\":0,\"NORMAL\":0},"
		+ "\"indices\":1}]}],"
		+ "\"accessors\":["
		+ "{\"bufferView\":0,\"byteOffset\":2,\"componentType\":5126,\"count\":1,"
		+ "\"type\":\"VEC3\"},"
		+ "{\"bufferView\":1,\"componentType\":5123,\"count\":3,\"type\":\"SCALAR\"}],"
		+ "\"bufferViews\":[{\"buffer\":0,\"byteLength\":14},"
		+ "{\"buffer\":0,\"byteOffset\":14,\"byteLength\":6}],"
		+ "\"buffers\":[{\"byteLength\":20}]}",
		triangleBuffer(),
	);
	assert !misaligned.ok;
}

test "glTF matrix nodes round trip identity, rotations and nonuniform scales" {
	const matrices: Vec<Vec<float32>> = [
		[1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
		[0, 2, 0, 0, -3, 0, 0, 0, 0, 0, 4, 0, 5, 6, 7, 1],
		[0.72, 1.6, -0.96, 0, -1.44, 1.8, 1.92, 0, 3.2, 0, 2.4, 0, 5, 6, 7, 1],
		[2, 0, 0, 0, 0, -3, 0, 0, 0, 0, -4, 0, 5, 6, 7, 1],
		[-2, 0, 0, 0, 0, 3, 0, 0, 0, 0, -4, 0, 5, 6, 7, 1],
		[-2, 0, 0, 0, 0, -3, 0, 0, 0, 0, 4, 0, 5, 6, 7, 1],
		[1e20, 0, 0, 0, 0, 1e-10, 0, 0, 0, 0, 1, 0, 5, 6, 7, 1],
	];
	for (const values of matrices) {
		let text: string = "";
		for (let i = 0; i < 16; i++) {
			if (i != 0) { text += ","; }
			text += values[i].toString();
		}
		const loaded = loadGltf(nodeOnlyGltf("{\"matrix\":[" + text + "]}"), []);
		assert loaded.ok;
		if (!loaded.ok) { continue; }
		const local = loaded.value.nodes[0].local;
		let actual: Vec<float32> = new Array(16);
		composeTransform(local.position, local.rotation, local.scale).writeTo(actual, 0);
		for (let i = 0; i < 16; i++) {
			const tolerance: float32 = (Math.abs(values[i]) * 0.00001) as float32;
			assert Math.abs(actual[i] - values[i]) <= (values[i] == 0 ? 0.00001 : tolerance);
		}
	}
}

test "glTF matrix parent reaches retained child world transform" {
	const json = "{\"asset\":{\"version\":\"2.0\"},\"scenes\":[{\"nodes\":[0]}],"
		+ "\"nodes\":[{\"matrix\":[0,2,0,0,-3,0,0,0,0,0,4,0,5,6,7,1],\"children\":[1]},"
		+ "{\"name\":\"child\",\"translation\":[1,2,3]}],\"meshes\":[],\"buffers\":[]}";
	const loaded = loadGltf(json, []);
	assert loaded.ok;
	if (!loaded.ok) { return; }
	const scene = Scene3D.create(contextOf(0, 0));
	assert addGltfNodes(scene, scene.rootId(), loaded.value, []).ok;
	assert syncWorld(scene) == 3;
	const child = scene.findByName(scene.rootId(), "child");
	assert child.ok;
	if (!child.ok) { return; }
	const world = scene.worldOf(child.value);
	assert world.ok;
	if (!world.ok) { return; }
	assert approx(world.value.m41, -1.0);
	assert approx(world.value.m42, 8.0);
	assert approx(world.value.m43, 19.0);
}

test "glTF matrix nodes refuse nonaffine shear singular mirrored and mixed TRS input" {
	const invalid: Vec<string> = [
		"{\"matrix\":[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0]}",
		"{\"matrix\":[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,2]}",
		"{\"matrix\":[1,0,0,0.1,0,1,0,0,0,0,1,0,0,0,0,1]}",
		"{\"matrix\":[1,0.01,0,0,0,1,0,0,0,0,1,0,0,0,0,1]}",
		"{\"matrix\":[1,0.0001,0,0,0,1,0,0,0,0,1,0,1e20,0,0,1]}",
		"{\"matrix\":[1,0,0,0,0,1,0,0,0,0,0,0,0,0,0,1]}",
		"{\"matrix\":[-1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]}",
		"{\"matrix\":[1e-4,0,0,0,0,1e-4,0,0,0,0,1e-4,0,0,0,0,1]}",
		"{\"matrix\":[1e999,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]}",
		"{\"matrix\":[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],\"translation\":[0,0,0]}",
		"{\"matrix\":[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],\"rotation\":[0,0,0,1]}",
		"{\"matrix\":[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],\"scale\":[1,1,1]}",
	];
	for (const node of invalid) { assert !loadGltf(nodeOnlyGltf(node), []).ok; }
}

test "unsupported inputs fail loudly beside valid non-indexed geometry" {
	const skinned = loadGltf(nodeOnlyGltf("{\"skin\":0}"), []);
	assert !skinned.ok;
	const zeroScale = loadGltf(nodeOnlyGltf("{\"scale\":[1,1,0]}"), []);
	assert !zeroScale.ok;
	const mirroredScale = loadGltf(nodeOnlyGltf("{\"scale\":[-1,1,1]}"), []);
	assert !mirroredScale.ok;
	const badRotation = loadGltf(nodeOnlyGltf("{\"rotation\":[0,0,0,0]}"), []);
	assert !badRotation.ok;
	const infiniteTranslation = loadGltf(nodeOnlyGltf("{\"translation\":[1e999,0,0]}"), []);
	assert !infiniteTranslation.ok;
	const wideRoot = loadGltf(nodeOnlyGltf("{}", "4294967296"), []);
	assert !wideRoot.ok;
	const targets = loadGltf(
		"{\"asset\":{\"version\":\"2.0\"},\"scenes\":[{\"nodes\":[0]}],"
		+ "\"nodes\":[{\"mesh\":0}],\"meshes\":[{\"primitives\":[{\"targets\":[]}]}],"
		+ "\"accessors\":[],\"bufferViews\":[],\"buffers\":[{\"byteLength\":0}]}",
		[],
	);
	assert !targets.ok;
	const requiredExtension = loadGltf(
		"{\"asset\":{\"version\":\"2.0\"},\"extensionsRequired\":[\"EXT_mesh_gpu_instancing\"],"
		+ "\"scenes\":[{\"nodes\":[]}],\"nodes\":[],\"meshes\":[],\"accessors\":[],"
		+ "\"bufferViews\":[],\"buffers\":[]}",
		[],
	);
	assert !requiredExtension.ok;
	const noIndices = loadGltf(
		"{\"asset\":{\"version\":\"2.0\"},\"scenes\":[{\"nodes\":[0]}],"
		+ "\"nodes\":[{\"mesh\":0}],"
		+ "\"meshes\":[{\"primitives\":[{\"attributes\":{\"POSITION\":0,\"NORMAL\":1}}]}],"
		+ "\"accessors\":["
		+ "{\"bufferView\":0,\"componentType\":5126,\"count\":3,\"type\":\"VEC3\"},"
		+ "{\"bufferView\":1,\"componentType\":5126,\"count\":3,\"type\":\"VEC3\"}],"
		+ "\"bufferViews\":["
		+ "{\"buffer\":0,\"byteOffset\":0,\"byteLength\":36},"
		+ "{\"buffer\":0,\"byteOffset\":36,\"byteLength\":36}],"
		+ "\"buffers\":[{\"byteLength\":72}]}",
		triangleBuffer(),
	);
	assert noIndices.ok;
	if (noIndices.ok) {
		assert noIndices.value.meshes[0].indices.length == 0;
		assert noIndices.value.meshes[0].wideIndices === null;
	}
	let nonFinite = triangleBuffer();
	nonFinite[2] = 192 as uint8;
	nonFinite[3] = 127 as uint8;
	const nonFiniteMesh = loadGltf(triangleGltf(), nonFinite);
	assert !nonFiniteMesh.ok;
	let zeroNormal = triangleBuffer();
	zeroNormal[46] = 0 as uint8;
	zeroNormal[47] = 0 as uint8;
	const zeroNormalMesh = loadGltf(triangleGltf(), zeroNormal);
	assert !zeroNormalMesh.ok;
	let overbrightColor = triangleBuffer();
	overbrightColor[74] = 0 as uint8;
	overbrightColor[75] = 64 as uint8;
	const overbrightMesh = loadGltf(triangleGltf(), overbrightColor);
	assert !overbrightMesh.ok;
}

test "not glTF, bad JSON, short buffer and missing POSITION each say which one" {
	const wrongVersion = loadGltf(
		"{\"asset\":{\"version\":\"1.0\"}}", [],
	);
	assert !wrongVersion.ok;
	if (!wrongVersion.ok) { assert wrongVersion.error == GltfError.NotGltf; }
	const malformedVersion = loadGltf(
		"{\"asset\":{\"version\":\"2bad\"}}", [],
	);
	assert !malformedVersion.ok;
	if (!malformedVersion.ok) { assert malformedVersion.error == GltfError.NotGltf; }
	const badJson = loadGltf("{not json", []);
	assert !badJson.ok;
	if (!badJson.ok) { assert badJson.error == GltfError.BadJson; }
	const short = loadGltf(triangleGltf(), []);
	assert !short.ok;
	if (!short.ok) { assert short.error == GltfError.OutOfRange; }
	const noPosition = loadGltf(
		"{\"asset\":{\"version\":\"2.0\"},\"scenes\":[{\"nodes\":[0]}],"
		+ "\"nodes\":[{\"mesh\":0}],"
		+ "\"meshes\":[{\"primitives\":[{\"attributes\":{\"NORMAL\":1}}]}],"
		+ "\"accessors\":[{\"bufferView\":0,\"componentType\":5126,\"count\":3,\"type\":\"VEC3\"}],"
		+ "\"bufferViews\":[{\"buffer\":0,\"byteOffset\":0,\"byteLength\":36}],"
		+ "\"buffers\":[{\"byteLength\":36}]}",
		triangleBuffer(),
	);
	assert !noPosition.ok;
	if (!noPosition.ok) { assert noPosition.error == GltfError.Unsupported; }
}

function pairGltf(meshName: string): string {
	return "{\"asset\":{\"version\":\"2.0\"},\"scene\":0,"
		+ "\"scenes\":[{\"nodes\":[0,2]}],"
		+ "\"nodes\":["
		+ "{\"name\":\"pair\",\"mesh\":0,\"translation\":[1.0,0.0,0.0],\"children\":[1]},"
		+ "{\"name\":\"child\"},"
		+ "{\"name\":\"again\",\"mesh\":0}],"
		+ "\"meshes\":[{" + meshName + "\"primitives\":["
		+ "{\"attributes\":{\"POSITION\":0,\"NORMAL\":1,\"COLOR_0\":2},\"indices\":3},"
		+ "{\"attributes\":{\"POSITION\":0,\"NORMAL\":1},\"indices\":3}]}],"
		+ "\"accessors\":["
		+ "{\"bufferView\":0,\"componentType\":5126,\"count\":3,\"type\":\"VEC3\"},"
		+ "{\"bufferView\":1,\"componentType\":5126,\"count\":3,\"type\":\"VEC3\"},"
		+ "{\"bufferView\":2,\"componentType\":5126,\"count\":3,\"type\":\"VEC3\"},"
		+ "{\"bufferView\":3,\"componentType\":5123,\"count\":3,\"type\":\"SCALAR\"}],"
		+ "\"bufferViews\":["
		+ "{\"buffer\":0,\"byteOffset\":0,\"byteLength\":36},"
		+ "{\"buffer\":0,\"byteOffset\":36,\"byteLength\":36},"
		+ "{\"buffer\":0,\"byteOffset\":72,\"byteLength\":36},"
		+ "{\"buffer\":0,\"byteOffset\":108,\"byteLength\":6}],"
		+ "\"buffers\":[{\"byteLength\":114}]}";
}

test "a mesh with several primitives is one drawable each, under a group at its node" {
	const loaded = loadGltf(pairGltf("\"name\":\"duo\","), triangleBuffer());
	assert loaded.ok;
	if (!loaded.ok) { return; }
	const data = loaded.value;
	assert (data.meshes.length as int32) == 2 && (data.meshMaterials.length as int32) == 2;
	assert approx(data.meshes[0].vertices[6], 1.0) && approx(data.meshes[1].vertices[6], 1.0);
	assert approx(data.meshes[0].vertices[7], 0.0) && approx(data.meshes[0].vertices[8], 0.0);
	assert (data.nodes.length as int32) == 7;
	assert data.nodes[0].mesh == -1 && data.nodes[0].name == "pair";
	assert approx(data.nodes[0].local.position.x, 1.0);
	assert (data.nodes[0].children.length as int32) == 3;
	assert data.nodes[0].children[0] == 3 && data.nodes[0].children[1] == 4;
	assert data.nodes[0].children[2] == 1;
	assert data.nodes[3].name == "duo" && data.nodes[3].mesh == 0;
	assert data.nodes[4].name == "duo_1" && data.nodes[4].mesh == 1;
	assert data.nodes[3].local.scale.x == 1.0 && data.nodes[3].local.position.x == 0.0;
	assert data.nodes[2].mesh == -1 && (data.nodes[2].children.length as int32) == 2;
	assert data.nodes[5].mesh == 0 && data.nodes[6].mesh == 1;
	const unnamed = loadGltf(pairGltf(""), triangleBuffer());
	assert unnamed.ok;
	if (unnamed.ok) { assert unnamed.value.nodes[3].name == "mesh_0"; }
}

test "addGltfNodes puts each primitive of a mesh under its node with its own binding" {
	let context: DrawContext = contextOf(8, 10);
	const loaded = loadGltf(pairGltf(""), triangleBuffer());
	assert loaded.ok;
	if (!loaded.ok) { return; }
	let scene: Scene3D = Scene3D.create(context);
	const bindings: Vec<GltfMeshBinding> = [
		{ mesh: context.meshAt(1), material: context.materialAt(2) },
		{ mesh: context.meshAt(3), material: context.materialAt(4) },
	];
	const added: Result<int32, GltfSceneError> =
		addGltfNodes(scene, scene.rootId(), loaded.value, bindings);
	assert added.ok;
	if (!added.ok) { return; }
	assert added.value == 7;
	const first = scene.findByName(scene.rootId(), "mesh_0");
	const second = scene.findByName(scene.rootId(), "mesh_0_1");
	const pair = scene.findByName(scene.rootId(), "pair");
	assert first.ok && second.ok && pair.ok;
	if (!first.ok || !second.ok || !pair.ok) { return; }
	assert scene.meshes[scene.nodes[first.value.index].payload].mesh.index == 1;
	assert scene.meshes[scene.nodes[first.value.index].payload].material.index == 2;
	assert scene.meshes[scene.nodes[second.value.index].payload].mesh.index == 3;
	assert scene.meshes[scene.nodes[second.value.index].payload].material.index == 4;
	assert syncWorld(scene) == 8;
	const world: Result<Mat4, SceneError> = scene.worldOf(second.value);
	assert world.ok;
	if (world.ok) { assert approx(world.value.m41, 1.0); }
}

function twinMeshGltf(): string {
	const primitive: string =
		"{\"attributes\":{\"POSITION\":0,\"NORMAL\":1},\"indices\":3}";
	const mesh: string = "{\"name\":\"m\",\"primitives\":[" + primitive + "," + primitive + "]}";
	return "{\"asset\":{\"version\":\"2.0\"},\"scene\":0,"
		+ "\"scenes\":[{\"nodes\":[0,1]}],"
		+ "\"nodes\":[{\"mesh\":0},{\"mesh\":1}],"
		+ "\"meshes\":[" + mesh + "," + mesh + "],"
		+ "\"accessors\":["
		+ "{\"bufferView\":0,\"componentType\":5126,\"count\":3,\"type\":\"VEC3\"},"
		+ "{\"bufferView\":1,\"componentType\":5126,\"count\":3,\"type\":\"VEC3\"},"
		+ "{\"bufferView\":2,\"componentType\":5126,\"count\":3,\"type\":\"VEC3\"},"
		+ "{\"bufferView\":3,\"componentType\":5123,\"count\":3,\"type\":\"SCALAR\"}],"
		+ "\"bufferViews\":["
		+ "{\"buffer\":0,\"byteOffset\":0,\"byteLength\":36},"
		+ "{\"buffer\":0,\"byteOffset\":36,\"byteLength\":36},"
		+ "{\"buffer\":0,\"byteOffset\":72,\"byteLength\":36},"
		+ "{\"buffer\":0,\"byteOffset\":108,\"byteLength\":6}],"
		+ "\"buffers\":[{\"byteLength\":114}]}";
}

test "primitive names are unique across the file as three.js createUniqueName counts them" {
	const loaded = loadGltf(twinMeshGltf(), triangleBuffer());
	assert loaded.ok;
	if (!loaded.ok) { return; }
	const nodes = loaded.value.nodes;
	assert nodes[2].name == "m" && nodes[3].name == "m_1";
	assert nodes[4].name == "m_2" && nodes[5].name == "m_3";
	assert nodes[4].mesh == 2 && nodes[5].mesh == 3;
}
