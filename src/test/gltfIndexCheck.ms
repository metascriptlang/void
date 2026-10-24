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

struct IndexFixture {
	json: string;
	bytes: Vec<uint8>;
}

function indexFixture(
	count: int32,
	component: int32,
	indices: Readonly<Span<uint32>>,
	sparseSlots: Readonly<Span<uint32>>,
	zeroBase: boolean,
): IndexFixture {
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
	let sparseViews = "";
	let sparse = "";
	if (sparseSlots.length > 0) {
		const slotsOffset = bytes.length as int32;
		for (const slot of sparseSlots) { appendWord(bytes, slot, width); }
		const valuesOffset = bytes.length as int32;
		for (const slot of sparseSlots) { appendWord(bytes, indices[slot as int32], width); }
		const length = (sparseSlots.length as int32) * width;
		sparseViews = `,{"buffer":0,"byteOffset":${slotsOffset},"byteLength":${length}},` +
			`{"buffer":0,"byteOffset":${valuesOffset},"byteLength":${length}}`;
		sparse = `,"sparse":{"count":${sparseSlots.length},` +
			`"indices":{"bufferView":3,"componentType":${component}},` +
			`"values":{"bufferView":4}}`;
	}
	const base = zeroBase ? "" : `"bufferView":2,`;
	const json: string = `{"asset":{"version":"2.0"},"buffers":[{"byteLength":${bytes.length}}],` +
		`"bufferViews":[{"buffer":0,"byteLength":${vectorBytes}},` +
		`{"buffer":0,"byteOffset":${vectorBytes},"byteLength":${vectorBytes}},` +
		`{"buffer":0,"byteOffset":${vectorBytes * 2},"byteLength":${indexBytes}}${sparseViews}],` +
		`"accessors":[{"bufferView":0,"componentType":5126,"type":"VEC3","count":${count}},` +
		`{"bufferView":1,"componentType":5126,"type":"VEC3","count":${count}},` +
		`{${base}"componentType":${component},"type":"SCALAR",` +
		`"count":${indices.length}${sparse}}],` +
		`"meshes":[{"primitives":[{"attributes":{"POSITION":0,"NORMAL":1},"indices":2}]}],` +
		`"nodes":[{"mesh":0}],"scenes":[{"nodes":[0]}],"scene":0}`;
	return { json: json, bytes: move bytes };
}

function stripFixture(
	count: int32,
	component: int32,
	indices: Readonly<Span<uint32>>,
	sparseSlots: Readonly<Span<uint32>>,
	zeroBase: boolean,
): IndexFixture {
	let fixture = indexFixture(count, component, indices, sparseSlots, zeroBase);
	const first: int32 = count > 65536 ? 65536 : 0;
	const rows: Vec<uint32> = [0, 0x3f800000, 0x40000000];
	for (let vertex = 0; vertex < 6 && first + vertex < count; vertex++) {
		const bits: Vec<uint32> = [vertex % 2 == 0 ? 0 : 0x3f800000, rows[vertex / 2], 0];
		for (let axis = 0; axis < 3; axis++) {
			for (let byte = 0; byte < 4; byte++) {
				fixture.bytes[(first + vertex) * 12 + axis * 4 + byte] =
					((bits[axis] >> ((byte * 8) as uint32)) & 255) as uint8;
			}
		}
	}
	fixture.json = fixture.json.replace(`"attributes":`, `"mode":5,"attributes":`);
	return fixture;
}

function fanFixture(
	count: int32,
	component: int32,
	indices: Readonly<Span<uint32>>,
	sparseSlots: Readonly<Span<uint32>>,
	zeroBase: boolean,
): IndexFixture {
	let fixture = indexFixture(count, component, indices, sparseSlots, zeroBase);
	const first: int32 = count > 65536 ? 65536 : 0;
	const coordinates: Vec<uint32> = [
		0, 0, 0x3f800000, 0, 0, 0x3f800000,
		0xbf800000, 0, 0, 0xbf800000, 0x3f800000, 0,
	];
	for (let vertex = 0; vertex < 6 && first + vertex < count; vertex++) {
		for (let axis = 0; axis < 2; axis++) {
			for (let byte = 0; byte < 4; byte++) {
				fixture.bytes[(first + vertex) * 12 + axis * 4 + byte] =
					((coordinates[vertex * 2 + axis] >> ((byte * 8) as uint32)) & 255) as uint8;
			}
		}
	}
	fixture.json = fixture.json.replace(`"attributes":`, `"mode":6,"attributes":`);
	return fixture;
}

function indexedFixture(
	count: int32,
	component: int32,
	indices: Readonly<Span<uint32>>,
): Result<GltfData, GltfError> {
	const fixture = indexFixture(count, component, indices, [], false);
	return loadGltf(fixture.json, fixture.bytes);
}

test "glTF sparse triangle indices overlay dense and zero bases at every source width" {
	for (const component of [5121, 5123, 5125]) {
		for (const zeroBase of [false, true]) {
			const fixture = indexFixture(3, component, [0, 1, 2], [1, 2], zeroBase);
			const loaded = loadGltf(fixture.json, fixture.bytes);
			assert loaded.ok;
			if (!loaded.ok) { continue; }
			const mesh = loaded.value.meshes[0];
			assert mesh.vertexCount() == 3 && mesh.indexCount() == 3;
			assert (mesh.wideIndices !== null) == (component == 5125);
			for (let i = 0; i < 3; i++) { assert mesh.indexAt(i) == i as uint32; }
			const ray: Ray = { origin: vec3(0.25, 0.25, 1), direction: vec3(0, 0, -1) };
			assert mesh.rayIntersection(ray, Face.None).distance == 1;
		}
	}
}

test "glTF sparse indices validate replaced values rather than discarded dense values" {
	for (const component of [5121, 5123, 5125]) {
		const width = component == 5121 ? 1 : (component == 5123 ? 2 : 4);
		let fixture = indexFixture(3, component, [0, 1, 2], [1, 2], false);
		for (let i = 0; i < width; i++) { fixture.bytes[72 + width + i] = 255 as uint8; }
		const loaded = loadGltf(fixture.json, fixture.bytes);
		assert loaded.ok;
		if (loaded.ok) { assert loaded.value.meshes[0].indexAt(1) == 1; }
		const valuesOffset = 72 + 5 * width;
		for (let i = 0; i < width; i++) { fixture.bytes[valuesOffset + i] = 255 as uint8; }
		const bad = loadGltf(fixture.json, fixture.bytes);
		assert !bad.ok;
		if (!bad.ok) { assert bad.error == GltfError.BadIndex; }
	}
}

test "glTF sparse uint32 indices retain high vertices and picking" {
	for (const zeroBase of [false, true]) {
		const fixture = indexFixture(65539, 5125, [65536, 65537, 65538], [0, 1, 2], zeroBase);
		const loaded = loadGltf(fixture.json, fixture.bytes);
		assert loaded.ok;
		if (!loaded.ok) { continue; }
		const mesh = loaded.value.meshes[0];
		assert mesh.wideIndices !== null && mesh.indexAt(0) == 65536 && mesh.indexAt(2) == 65538;
		const ray: Ray = { origin: vec3(0.25, 0.25, 1), direction: vec3(0, 0, -1) };
		assert mesh.rayIntersection(ray, Face.None).distance == 1;
	}
}

test "glTF sparse restart values remain forbidden when vertices can address them" {
	for (const wide of [false, true]) {
		const maximum: uint32 = wide ? 65535 : 255;
		const fixture = indexFixture((maximum as int32) + 1, wide ? 5123 : 5121,
			[0, 1, maximum], [2], false);
		const loaded = loadGltf(fixture.json, fixture.bytes);
		assert !loaded.ok;
		if (!loaded.ok) { assert loaded.error == GltfError.BadIndex; }
	}
	const short = indexFixture(3, 5123, [0, 1], [0, 1], true);
	const loaded = loadGltf(short.json, short.bytes);
	assert !loaded.ok;
	if (!loaded.ok) { assert loaded.error == GltfError.CountMismatch; }
}

test "glTF sparse triangle indices reject malformed slots counts and layouts" {
	const fixture = indexFixture(3, 5121, [0, 1, 2], [1, 2], false);
	for (const slots of [[1, 1], [2, 1], [1, 3]]) {
		let invalid = indexFixture(3, 5121, [0, 1, 2], [1, 2], false);
		invalid.bytes[75] = slots[0] as uint8;
		invalid.bytes[76] = slots[1] as uint8;
		assert !loadGltf(invalid.json, invalid.bytes).ok;
	}
	for (const json of [
		fixture.json.replace(`"type":"SCALAR","count":3`, `"type":"SCALAR","count":2`),
		fixture.json.replace(`"sparse":{"count":2`, `"sparse":{"count":4`),
		fixture.json.replace(`"type":"SCALAR"`, `"type":"VEC2"`),
		fixture.json.replace(`"type":"SCALAR"`, `"type":"SCALAR","normalized":true`),
		fixture.json.replace(`"byteOffset":72,"byteLength":3`,
			`"byteOffset":72,"byteLength":3,"byteStride":4`),
		fixture.json.replace(`"byteOffset":72,"byteLength":3`,
			`"byteOffset":72,"byteLength":3,"target":34962`),
		fixture.json.replace(`"byteOffset":75,"byteLength":2`,
			`"byteOffset":75,"byteLength":2,"target":34963`),
		fixture.json.replace(`"byteOffset":77,"byteLength":2`,
			`"byteOffset":77,"byteLength":1`),
	]) { assert !loadGltf(json, fixture.bytes).ok; }
}

test "glTF absent indices preserve sequential triangles and CPU picking" {
	for (const count of [3, 6]) {
		const fixture = indexFixture(count, 5123, [0, 1, 2], [], false);
		const json = fixture.json.replace(`,"indices":2`, "");
		const loaded = loadGltf(json, fixture.bytes);
		assert loaded.ok;
		if (!loaded.ok) { continue; }
		const mesh = loaded.value.meshes[0];
		assert mesh.vertexCount() == count && mesh.indexCount() == 0;
		assert mesh.wideIndices === null;
		const ray: Ray = { origin: vec3(0.25, 0.25, 1), direction: vec3(0, 0, -1) };
		assert mesh.rayIntersection(ray, Face.None).distance == 1;
	}
}

test "glTF missing indices do not excuse incomplete triangles or invalid explicit indices" {
	const short = indexFixture(4, 5123, [0, 1, 2], [], false);
	assert !loadGltf(short.json.replace(`,"indices":2`, ""), short.bytes).ok;
	const fixture = indexFixture(3, 5123, [0, 1, 2], [], false);
	for (const value of ["null", "-1", "99", "1.5", "true"]) {
		assert !loadGltf(fixture.json.replace(`"indices":2`, `"indices":${value}`),
			fixture.bytes).ok;
	}
}

test "glTF absent and explicit triangle modes preserve both index layouts" {
	const fixture = indexFixture(3, 5123, [0, 1, 2], [], false);
	for (const indexed of [false, true]) {
		const json = indexed ? fixture.json : fixture.json.replace(`,"indices":2`, "");
		for (const doc of [json, json.replace(`"attributes":`, `"mode":4,"attributes":`)]) {
			const loaded = loadGltf(doc, fixture.bytes);
			assert loaded.ok;
			if (loaded.ok) {
				assert loaded.value.meshes[0].vertexCount() == 3;
				assert loaded.value.meshes[0].indexCount() == (indexed ? 3 : 0);
			}
		}
	}
}

test "glTF explicit invalid primitive modes never default to triangles" {
	const fixture = indexFixture(3, 5123, [0, 1, 2], [], false);
	for (const indexed of [false, true]) {
		const json = indexed ? fixture.json : fixture.json.replace(`,"indices":2`, "");
		for (const mode of ["null", "true", `"4"`, "4.5", "-1", "7", "4294967300"]) {
			const loaded = loadGltf(
				json.replace(`"attributes":`, `"mode":${mode},"attributes":`), fixture.bytes);
			assert !loaded.ok;
			if (!loaded.ok) { assert loaded.error == GltfError.Unsupported; }
		}
	}
}

test "glTF strips preserve winding across dense and sparse index widths" {
	const expected: Vec<uint32> = [0, 1, 2, 2, 1, 3, 2, 3, 4, 4, 3, 5];
	for (const component of [5121, 5123, 5125]) {
		for (const layout of [0, 1, 2]) {
			const slots: Vec<uint32> = layout == 0 ? [] : [1, 2, 3, 4, 5];
			const fixture = stripFixture(6, component, [0, 1, 2, 3, 4, 5], slots, layout == 2);
			const loaded = loadGltf(fixture.json, fixture.bytes);
			assert loaded.ok;
			if (!loaded.ok) { continue; }
			const mesh = loaded.value.meshes[0];
			assert mesh.vertexCount() == 6 && mesh.indexCount() == 12;
			assert (mesh.wideIndices !== null) == (component == 5125);
			for (let i = 0; i < expected.length; i++) {
				assert mesh.indexAt(i as int32) == expected[i];
			}
			for (const row of [0, 1]) {
				for (const offset of [0.25 as float32, 0.75 as float32]) {
					const ray: Ray = {
						origin: vec3(offset, (row as float32) + offset, 1),
						direction: vec3(0, 0, -1),
					};
					assert mesh.rayIntersection(ray, Face.Back).distance == 1;
					assert mesh.rayIntersection(ray, Face.Front).distance < 0;
				}
			}
		}
	}
}

test "glTF implicit strips promote at the existing narrow index boundary" {
	for (const count of [3, 4, 6, 65535, 65536]) {
		const fixture = stripFixture(count, 5123, [0, 1, 2], [], false);
		const loaded = loadGltf(fixture.json.replace(`,"indices":2`, ""), fixture.bytes);
		assert loaded.ok;
		if (!loaded.ok) { continue; }
		const mesh = loaded.value.meshes[0];
		assert mesh.vertexCount() == count && mesh.indexCount() == (count - 2) * 3;
		assert (mesh.wideIndices !== null) == (count == 65536);
		for (let triangle = 0; triangle < count - 2; triangle++) {
			const first = triangle % 2 == 0 ? triangle : triangle + 1;
			const second = triangle % 2 == 0 ? triangle + 1 : triangle;
			assert mesh.indexAt(triangle * 3) == first as uint32;
			assert mesh.indexAt(triangle * 3 + 1) == second as uint32;
			assert mesh.indexAt(triangle * 3 + 2) == (triangle + 2) as uint32;
		}
	}
}

test "glTF uint32 strips retain high source ids and odd-triangle picking" {
	const indices: Vec<uint32> = [65536, 65537, 65538, 65539];
	const expected: Vec<uint32> = [65536, 65537, 65538, 65538, 65537, 65539];
	for (const zeroBase of [false, true]) {
		const fixture = stripFixture(65540, 5125, indices, [0, 1, 2, 3], zeroBase);
		const loaded = loadGltf(fixture.json, fixture.bytes);
		assert loaded.ok;
		if (!loaded.ok) { continue; }
		const mesh = loaded.value.meshes[0];
		assert mesh.wideIndices !== null && mesh.indexCount() == 6;
		for (let i = 0; i < expected.length; i++) {
			assert mesh.indexAt(i as int32) == expected[i];
		}
		const ray: Ray = { origin: vec3(0.75, 0.75, 1), direction: vec3(0, 0, -1) };
		assert mesh.rayIntersection(ray, Face.Back).distance == 1;
	}
}

test "glTF strip degenerate windows retain parity for later faces" {
	const fixture = stripFixture(4, 5123, [0, 1, 2, 1, 3], [], false);
	const expected: Vec<uint32> = [0, 1, 2, 2, 1, 1, 2, 1, 3];
	const loaded = loadGltf(fixture.json, fixture.bytes);
	assert loaded.ok;
	if (!loaded.ok) { return; }
	const mesh = loaded.value.meshes[0];
	assert mesh.indexCount() == expected.length;
	for (let i = 0; i < expected.length; i++) {
		assert mesh.indexAt(i as int32) == expected[i];
	}
	const ray: Ray = { origin: vec3(0.75, 0.75, 1), direction: vec3(0, 0, -1) };
	assert mesh.rayIntersection(ray, Face.Back).distance == 1;
	assert mesh.rayIntersection(ray, Face.Front).distance < 0;
}

test "glTF strips still reject short streams malformed indices and restart sentinels" {
	const short = stripFixture(2, 5123, [0, 1], [], false);
	for (const indexed of [false, true]) {
		const json = indexed ? short.json : short.json.replace(`,"indices":2`, "");
		const loaded = loadGltf(json, short.bytes);
		assert !loaded.ok;
		if (!loaded.ok) { assert loaded.error == GltfError.CountMismatch; }
	}
	const fixture = stripFixture(4, 5123, [0, 1, 2, 3], [], false);
	for (const value of ["null", "-1", "99", "1.5", "true"]) {
		assert !loadGltf(fixture.json.replace(`"indices":2`, `"indices":${value}`),
			fixture.bytes).ok;
	}
	for (const component of [5121, 5123, 5125]) {
		const maximum: uint32 = component == 5121 ? 255 :
			(component == 5123 ? 65535 : 0xffffffff);
		const bad = stripFixture(4, component, [0, 1, 2, maximum], [3], false);
		const loaded = loadGltf(bad.json, bad.bytes);
		assert !loaded.ok;
		if (!loaded.ok) { assert loaded.error == GltfError.BadIndex; }
	}
	const oversized = loadGltf(fixture.json.replace(`"type":"SCALAR","count":4`,
		`"type":"SCALAR","count":715827885`), fixture.bytes);
	assert !oversized.ok;
	if (!oversized.ok) { assert oversized.error == GltfError.MeshTooLarge; }
	for (const count of ["-2147483648", "0", "715827884"]) {
		const loaded = loadGltf(fixture.json.replace(`"type":"SCALAR","count":4`,
			`"type":"SCALAR","count":${count}`), fixture.bytes);
		assert !loaded.ok;
		if (!loaded.ok) { assert loaded.error == GltfError.OutOfRange; }
	}
	for (const mode of [0, 1, 2, 3]) {
		const loaded = loadGltf(fixture.json.replace(`"mode":5`, `"mode":${mode}`),
			fixture.bytes);
		assert !loaded.ok;
		if (!loaded.ok) { assert loaded.error == GltfError.Unsupported; }
	}
}

test "glTF fans preserve fixed anchors winding and sparse index widths" {
	const expected: Vec<uint32> = [1, 2, 0, 2, 3, 0, 3, 4, 0, 4, 5, 0];
	for (const component of [5121, 5123, 5125]) {
		for (const layout of [0, 1, 2]) {
			const slots: Vec<uint32> = layout == 0 ? [] : [0, 1, 2, 3, 4, 5];
			const fixture = fanFixture(6, component, [0, 1, 2, 3, 4, 5], slots, layout == 2);
			const loaded = loadGltf(fixture.json, fixture.bytes);
			assert loaded.ok;
			if (!loaded.ok) { continue; }
			const mesh = loaded.value.meshes[0];
			assert mesh.vertexCount() == 6 && mesh.indexCount() == 12;
			assert (mesh.wideIndices !== null) == (component == 5125);
			for (let i = 0; i < expected.length; i++) {
				assert mesh.indexAt(i as int32) == expected[i];
			}
			for (const x of [-0.25 as float32, 0.25 as float32]) {
				for (const y of [-0.25 as float32, 0.25 as float32]) {
					const ray: Ray = { origin: vec3(x, y, 1), direction: vec3(0, 0, -1) };
					assert mesh.rayIntersection(ray, Face.Back).distance == 1;
					assert mesh.rayIntersection(ray, Face.Front).distance < 0;
				}
			}
		}
	}
}

test "glTF implicit fans expand sequential sources and promote at the narrow boundary" {
	for (const count of [3, 4, 6, 65535, 65536]) {
		const fixture = fanFixture(count, 5123, [0, 1, 2], [], false);
		const loaded = loadGltf(fixture.json.replace(`,"indices":2`, ""), fixture.bytes);
		assert loaded.ok;
		if (!loaded.ok) { continue; }
		const mesh = loaded.value.meshes[0];
		assert mesh.vertexCount() == count && mesh.indexCount() == (count - 2) * 3;
		assert (mesh.wideIndices !== null) == (count == 65536);
		for (let triangle = 0; triangle < count - 2; triangle++) {
			assert mesh.indexAt(triangle * 3) == (triangle + 1) as uint32;
			assert mesh.indexAt(triangle * 3 + 1) == (triangle + 2) as uint32;
			assert mesh.indexAt(triangle * 3 + 2) == 0 as uint32;
		}
	}
}

test "glTF uint32 fans keep nonzero high anchors through dense and zero base sparse data" {
	const indices: Vec<uint32> = [65536, 65537, 65538, 65539, 65540, 65541];
	const expected: Vec<uint32> = [65537, 65538, 65536, 65538, 65539, 65536,
		65539, 65540, 65536, 65540, 65541, 65536];
	for (const zeroBase of [false, true]) {
		const fixture = fanFixture(65542, 5125, indices, [0, 1, 2, 3, 4, 5], zeroBase);
		const loaded = loadGltf(fixture.json, fixture.bytes);
		assert loaded.ok;
		if (!loaded.ok) { continue; }
		const mesh = loaded.value.meshes[0];
		assert mesh.wideIndices !== null && mesh.indexCount() == 12;
		for (let i = 0; i < expected.length; i++) {
			assert mesh.indexAt(i as int32) == expected[i];
		}
		const ray: Ray = { origin: vec3(-0.25, -0.25, 1), direction: vec3(0, 0, -1) };
		assert mesh.rayIntersection(ray, Face.Back).distance == 1;
	}
}

test "glTF fan degenerates retain the anchor and later nondegenerate faces" {
	const fixture = fanFixture(6, 5123, [0, 1, 2, 2, 3, 4, 5], [], false);
	const expected: Vec<uint32> = [1, 2, 0, 2, 2, 0, 2, 3, 0, 3, 4, 0, 4, 5, 0];
	const loaded = loadGltf(fixture.json, fixture.bytes);
	assert loaded.ok;
	if (!loaded.ok) { return; }
	const mesh = loaded.value.meshes[0];
	assert mesh.indexCount() == expected.length;
	for (let i = 0; i < expected.length; i++) {
		assert mesh.indexAt(i as int32) == expected[i];
	}
	const ray: Ray = { origin: vec3(-0.25, -0.25, 1), direction: vec3(0, 0, -1) };
	assert mesh.rayIntersection(ray, Face.Back).distance == 1;
}

test "glTF fan expansion preserves short count index range and restart guards" {
	const short = fanFixture(2, 5123, [0, 1], [], false);
	for (const indexed of [false, true]) {
		const json = indexed ? short.json : short.json.replace(`,"indices":2`, "");
		const loaded = loadGltf(json, short.bytes);
		assert !loaded.ok;
		if (!loaded.ok) { assert loaded.error == GltfError.CountMismatch; }
	}
	const fixture = fanFixture(6, 5123, [0, 1, 6], [], false);
	const outside = loadGltf(fixture.json, fixture.bytes);
	assert !outside.ok;
	if (!outside.ok) { assert outside.error == GltfError.BadIndex; }
	for (const component of [5121, 5123, 5125]) {
		const maximum: uint32 = component == 5121 ? 255 :
			(component == 5123 ? 65535 : 0xffffffff);
		const bad = fanFixture(6, component, [0, 1, maximum], [], false);
		const loaded = loadGltf(bad.json, bad.bytes);
		assert !loaded.ok;
		if (!loaded.ok) { assert loaded.error == GltfError.BadIndex; }
	}
	const oversized = loadGltf(fixture.json.replace(`"type":"SCALAR","count":3`,
		`"type":"SCALAR","count":715827885`), fixture.bytes);
	assert !oversized.ok;
	if (!oversized.ok) { assert oversized.error == GltfError.MeshTooLarge; }
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
