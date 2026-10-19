import { GltfData, GltfError, loadGltf } from "../void3d/gltf";
import { indexAt, indexCount, vertexCount, rayIntersection } from "../void3d/meshData";
import { vec3 } from "../math/math3d";
import { Ray } from "../void3d/ray";
import { Face } from "../gpu/state";

function appendWord(ref bytes: Vec<uint8>, value: uint32, width: int32): void {
	for (let byte = 0; byte < width; byte++) {
		bytes.push(((value >> ((byte * 8) as uint32)) & 255) as uint8);
	}
}

function indexedFixture(
	count: int32,
	component: int32,
	indices: Readonly<Span<uint32>>,
): Result<GltfData, GltfError> {
	const width: int32 = component == 5121 ? 1 : (component == 5123 ? 2 : 4);
	let bytes: Vec<uint8> = [];
	const first: int32 = count > 65536 ? 65536 : 0;
	for (let vertex = 0; vertex < count; vertex++) {
		appendWord(bytes, vertex == first + 1 ? 0x3f800000 : 0, 4);
		appendWord(bytes, vertex == first + 2 ? 0x3f800000 : 0, 4);
		appendWord(bytes, 0, 4);
	}
	for (let vertex = 0; vertex < count; vertex++) {
		appendWord(bytes, 0, 4);
		appendWord(bytes, 0, 4);
		appendWord(bytes, 0x3f800000, 4);
	}
	for (const index of indices) { appendWord(bytes, index, width); }
	const vectorBytes: int32 = count * 12;
	const indexBytes: int32 = (indices.length as int32) * width;
	const json: string = `{"asset":{"version":"2.0"},"buffers":[{"byteLength":${bytes.length}}],` +
		`"bufferViews":[{"buffer":0,"byteLength":${vectorBytes}},` +
		`{"buffer":0,"byteOffset":${vectorBytes},"byteLength":${vectorBytes}},` +
		`{"buffer":0,"byteOffset":${vectorBytes * 2},"byteLength":${indexBytes}}],` +
		`"accessors":[{"bufferView":0,"componentType":5126,"type":"VEC3","count":${count}},` +
		`{"bufferView":1,"componentType":5126,"type":"VEC3","count":${count}},` +
		`{"bufferView":2,"componentType":${component},"type":"SCALAR",` +
		`"count":${indices.length}}],` +
		`"meshes":[{"primitives":[{"attributes":{"POSITION":0,"NORMAL":1},"indices":2}]}],` +
		`"nodes":[{"mesh":0}],"scenes":[{"nodes":[0]}],"scene":0}`;
	return loadGltf(json, bytes);
}

test "glTF uint8 indices become narrow drawable indices" {
	const loaded = indexedFixture(3, 5121, [0, 1, 2]);
	assert loaded.ok;
	if (!loaded.ok) { return; }
	assert loaded.value.meshes[0].indexCount() == 3;
	assert loaded.value.meshes[0].indexAt(2) == 2;
	assert loaded.value.meshes[0].wideIndices === null;
}

test "glTF uint16 indices keep legacy narrow storage" {
	const loaded = indexedFixture(3, 5123, [0, 1, 2]);
	assert loaded.ok;
	if (!loaded.ok) { return; }
	assert loaded.value.meshes[0].indexAt(2) == 2;
	assert loaded.value.meshes[0].wideIndices === null;
}

test "glTF uint32 source width survives even when all indices are small" {
	const loaded = indexedFixture(3, 5125, [0, 1, 2]);
	assert loaded.ok;
	if (!loaded.ok) { return; }
	assert loaded.value.meshes[0].wideIndices !== null;
	assert loaded.value.meshes[0].indices.length == 0;
	assert loaded.value.meshes[0].indexAt(2) == 2;
}

test "glTF high uint32 vertices survive import bounds and CPU picking" {
	const loaded = indexedFixture(65539, 5125, [65536, 65537, 65538]);
	assert loaded.ok;
	if (!loaded.ok) { return; }
	assert loaded.value.meshes[0].vertexCount() == 65539;
	assert loaded.value.meshes[0].indexAt(0) == 65536;
	assert loaded.value.meshes[0].indexAt(2) == 65538;
	assert loaded.value.meshes[0].wideIndices !== null;
	assert loaded.value.meshes[0].bounds.max.x == 1 && loaded.value.meshes[0].bounds.max.y == 1;
	const ray: Ray = { origin: vec3(0.25, 0.25, 1), direction: vec3(0, 0, -1) };
	assert loaded.value.meshes[0].rayIntersection(ray, Face.None).distance == 1;
}

test "glTF forbids uint8 restart value even when vertex count can address it" {
	const loaded = indexedFixture(256, 5121, [0, 1, 255]);
	assert !loaded.ok && loaded.error == GltfError.BadIndex;
}

test "glTF forbids uint16 restart value even when vertex count can address it" {
	const loaded = indexedFixture(65536, 5123, [0, 1, 65535]);
	assert !loaded.ok && loaded.error == GltfError.BadIndex;
}

test "glTF rejects full uint32 maximum before signed narrowing" {
	const values: Vec<uint32> = [0, 1, 0xffffffff as uint32];
	const loaded = indexedFixture(3, 5125, values);
	assert !loaded.ok && loaded.error == GltfError.BadIndex;
}

test "glTF uint32 count bounds are checked without wrapping indices" {
	const loaded = indexedFixture(3, 5125, [65536, 1, 2]);
	assert !loaded.ok && loaded.error == GltfError.BadIndex;
}
