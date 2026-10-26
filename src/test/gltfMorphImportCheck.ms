import { loadGltf, GltfData, GltfError } from "../void3d/gltf";
import { sampleWeights } from "../void3d/gltfCurve";
import { MorphGeometry, bind, publishMorphGeometry } from "../void3d/morphGeometry";
import { approx } from "./helpers";
import { stride, vertexCount } from "../void3d/meshData";

const PNG_PAYLOAD: string =
	"iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAFElEQVR4nGP4z8DwHwyBNBAw"
	+ "NAAAR0sIeRPxYNAAAAAASUVORK5CYII=";
const NAN_BITS: uint32 = 0x7fc00000;

function bitsOf(value: float32): uint32 {
	if (value == 0.0) { return 0; }
	if (value == 1.0) { return 0x3f800000; }
	if (value == 2.0) { return 0x40000000; }
	if (value == 3.0) { return 0x40400000; }
	if (value == 4.0) { return 0x40800000; }
	if (value == 6.0) { return 0x40c00000; }
	if (value == 0.5) { return 0x3f000000; }
	return NAN_BITS;
}

function pushFloats(ref bytes: Vec<uint8>, values: Readonly<Span<float32>>): void {
	for (const value of values) {
		const bits: uint32 = bitsOf(value);
		for (let shift = 0; shift < 32; shift += 8) {
			bytes.push(((bits >> (shift as uint32)) & 255) as uint8);
		}
	}
}

function view(offset: int32, length: int32): string {
	return `{"buffer":0,"byteOffset":${offset},"byteLength":${length}}`;
}

function vec3Accessor(index: int32, count: int32): string {
	return `{"bufferView":${index},"componentType":5126,"count":${count},"type":"VEC3"}`;
}

function scalarAccessor(index: int32, count: int32): string {
	return `{"bufferView":${index},"componentType":5126,"count":${count},"type":"SCALAR"}`;
}

// Triangle: 0 POSITION, 1 NORMAL, 2/3 target 0 POSITION/NORMAL, 4 target 1 POSITION,
// 5 times [0,1,2], 6 LINEAR weights, 7 times [0,1], 8 CUBICSPLINE weights.
function triangleBytes(): Vec<uint8> {
	let bytes: Vec<uint8> = [];
	pushFloats(bytes, [0, 0, 0, 1, 0, 0, 0, 1, 0]);
	pushFloats(bytes, [0, 0, 1, 0, 0, 1, 0, 0, 1]);
	pushFloats(bytes, [1, 0, 0, 0, 2, 0, 0, 0, 3]);
	pushFloats(bytes, [0.5, 0, 0, 0.5, 0, 0, 0.5, 0, 0]);
	pushFloats(bytes, [0, 0, 2, 0, 0, 4, 0, 0, 6]);
	pushFloats(bytes, [0, 1, 2]);
	pushFloats(bytes, [0, 0, 1, 0.5, 0, 1]);
	pushFloats(bytes, [0, 1]);
	pushFloats(bytes, [0, 0, 0, 1, 2, 0, 0, 0, 1, 0, 0, 0]);
	return move bytes;
}

const TARGETS_TWO: string = '[{"POSITION":2,"NORMAL":3},{"POSITION":4}]';
const LINEAR_SAMPLER: string = `{"input":5,"output":6}`;

function primitive(targets: string, mode: string = ""): string {
	const targetField: string = targets == "" ? "" : `,"targets":${targets}`;
	return `{"attributes":{"POSITION":0,"NORMAL":1}${mode}${targetField}}`;
}

function triangleDocument(
	primitives: string, meshExtra: string = "", nodeExtra: string = "",
	animations: string = "", t0Count: int32 = 3, byteLength: int32 = 272,
	extraViews: string = "", extraAccessors: string = "",
): string {
	return `{"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0,1]}],`
		+ `"nodes":[{"mesh":0${nodeExtra}},{"name":"plain"}],`
		+ `"meshes":[{"primitives":[${primitives}]${meshExtra}}],`
		+ `"buffers":[{"byteLength":${byteLength}}],"bufferViews":[`
		+ view(0, 36) + "," + view(36, 36) + "," + view(72, 36) + "," + view(108, 36) + ","
		+ view(144, 36) + "," + view(180, 12) + "," + view(192, 24) + "," + view(216, 8) + ","
		+ view(224, 48) + extraViews + `],"accessors":[`
		+ vec3Accessor(0, 3) + "," + vec3Accessor(1, 3) + "," + vec3Accessor(2, t0Count) + ","
		+ vec3Accessor(3, 3) + "," + vec3Accessor(4, 3) + "," + scalarAccessor(5, 3) + ","
		+ scalarAccessor(6, 6) + "," + scalarAccessor(7, 2) + "," + scalarAccessor(8, 12)
		+ extraAccessors + `]${animations}}`;
}

function animation(sampler: string, node: int32 = 0, extraChannel: string = ""): string {
	return `,"animations":[{"samplers":[${sampler}],`
		+ `"channels":[{"sampler":0,"target":{"node":${node},"path":"weights"}}${extraChannel}]}]`;
}

function refuses(json: string, bytes: Readonly<Span<uint8>>, code: GltfError): boolean {
	const result = loadGltf(json, bytes);
	if (result.ok) { return false; }
	return result.error == code;
}

function triangle(): Result<GltfData, GltfError> {
	return loadGltf(triangleDocument(primitive(TARGETS_TWO)), triangleBytes());
}

test "glTF morph targets decode POSITION and NORMAL deltas per source vertex" {
	const loaded = triangle();
	assert loaded.ok;
	if (!loaded.ok) { return; }
	const data: GltfData = loaded.value;
	assert data.morphs.length == 1 && data.morphs[0].targetCount == 2;
	assert data.morphs[0].firstPrimitive == 0 && data.morphs[0].meshIndex == 0;
	const xyz = data.morphs[0].data.primitives[0].targetVertexXyz;
	assert xyz.length == 2 * 3 * 9;
	assert xyz[9] == 0 && xyz[10] == 2 && xyz[11] == 0;
	assert xyz[12] == 0.5 && xyz[13] == 0 && xyz[14] == 0;
	assert xyz[15] == 0 && xyz[16] == 0 && xyz[17] == 0;
	assert xyz[(1 * 3 + 2) * 9 + 2] == 6;
	assert xyz[(1 * 3 + 2) * 9 + 3] == 0 && xyz[(1 * 3 + 2) * 9 + 5] == 0;
	assert data.nodes[0].morph == 0 && data.nodes[1].morph === null;
	assert data.nodes[0].weights.length == 2 && data.nodes[0].weights[0] == 0 &&
		data.nodes[0].weights[1] == 0;
	assert data.nodes[1].weights.length == 0;
}

test "decoded morph data feeds MorphData bind and publishes the deformed triangle" {
	const loaded = triangle();
	assert loaded.ok;
	if (!loaded.ok) { return; }
	const morph = loaded.value.morphs[0];
	const made = MorphGeometry.bind(morph.data);
	assert made.ok;
	if (!made.ok) { return; }
	let geometry: MorphGeometry = made.value;
	const published = publishMorphGeometry(geometry, [1.0, 0.5]);
	assert published.ok;
	const mesh = geometry.meshes[0];
	const stride: int32 = mesh.stride();
	assert approx(mesh.vertices[stride], 1.0) && approx(mesh.vertices[stride + 1], 2.0) &&
		approx(mesh.vertices[stride + 2], 2.0);
	assert approx(mesh.vertices[stride + 3], 0.5) && approx(mesh.vertices[stride + 5], 1.0);
	assert approx(mesh.vertices[2 * stride + 2], 3.0 + 3.0);
	assert published.ok && published.value == 1;
}

function stripBytes(): Vec<uint8> {
	let bytes: Vec<uint8> = [];
	pushFloats(bytes, [0, 0, 0, 1, 0, 0, 0, 1, 0, 1, 1, 0]);
	pushFloats(bytes, [0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1]);
	pushFloats(bytes, [0, 0, 1, 0, 0, 2, 0, 0, 3, 0, 0, 4]);
	return move bytes;
}

function stripDocument(mode: int32): string {
	return `{"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],`
		+ `"nodes":[{"mesh":0}],"meshes":[{"primitives":[{"mode":${mode},`
		+ `"attributes":{"POSITION":0,"NORMAL":1},"targets":[{"POSITION":2}]}]}],`
		+ `"buffers":[{"byteLength":144}],"bufferViews":[${view(0, 48)},${view(48, 48)},`
		+ `${view(96, 48)}],"accessors":[${vec3Accessor(0, 4)},${vec3Accessor(1, 4)},`
		+ `${vec3Accessor(2, 4)}]}`;
}

test "glTF strip and fan targets keep one delta per source vertex through the expanded corners" {
	for (const mode of [5, 6]) {
		const loaded = loadGltf(stripDocument(mode), stripBytes());
		assert loaded.ok;
		if (!loaded.ok) { return; }
		const mesh = loaded.value.meshes[0];
		assert mesh.vertexCount() == 4 && mesh.indices.length == 6;
		const made = MorphGeometry.bind(loaded.value.morphs[0].data);
		assert made.ok;
		if (!made.ok) { return; }
		let geometry: MorphGeometry = made.value;
		const published = publishMorphGeometry(geometry, [1.0]);
		assert published.ok;
		const deformed = geometry.meshes[0];
		for (let corner = 0; corner < 6; corner++) {
			const vertex: int32 = deformed.indices[corner] as int32;
			assert vertex == mesh.indices[corner] as int32;
			const z: float32 = deformed.vertices[vertex * deformed.stride() + 2];
			assert approx(z, (vertex + 1) as float32);
		}
	}
}

function quadBytes(): Vec<uint8> {
	let bytes: Vec<uint8> = [];
	pushFloats(bytes, [0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0]);
	pushFloats(bytes, [0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1]);
	pushFloats(bytes, [0, 0, 1, 0, 1, 1, 1, 0]);
	pushFloats(bytes, [0, 0, 1, 0, 0, 2, 0, 0, 3, 0, 0, 4]);
	for (const index of [0, 1, 2, 0, 2, 3]) { bytes.push(index as uint8); bytes.push(0); }
	return move bytes;
}

test "morph targets refuse generated tangents instead of leaving their deltas zero" {
	const json = `{"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],`
		+ `"nodes":[{"mesh":0}],"meshes":[{"primitives":[{"indices":4,"material":0,`
		+ `"attributes":{"POSITION":0,"NORMAL":1,"TEXCOORD_0":2},"targets":[{"POSITION":3}]}]}],`
		+ `"materials":[{"normalTexture":{"index":0}}],"textures":[{"source":0}],`
		+ `"images":[{"uri":"data:image/png;base64,${PNG_PAYLOAD}"}],`
		+ `"buffers":[{"byteLength":${48 + 48 + 32 + 48 + 12}}],"bufferViews":[${view(0, 48)},`
		+ `${view(48, 48)},${view(96, 32)},${view(128, 48)},${view(176, 12)}],"accessors":[`
		+ vec3Accessor(0, 4) + "," + vec3Accessor(1, 4)
		+ `,{"bufferView":2,"componentType":5126,"count":4,"type":"VEC2"},` + vec3Accessor(3, 4)
		+ `,{"bufferView":4,"componentType":5123,"count":6,"type":"SCALAR"}]}`;
	assert refuses(json, quadBytes(), GltfError.Unsupported);
}

test "morph default weights take node over mesh over zeros" {
	const meshOnly = loadGltf(
		triangleDocument(primitive(TARGETS_TWO), `,"weights":[0.5,1]`), triangleBytes());
	assert meshOnly.ok;
	if (meshOnly.ok) {
		assert meshOnly.value.morphs[0].meshWeights[0] == 0.5 &&
			meshOnly.value.morphs[0].meshWeights[1] == 1;
		assert meshOnly.value.nodes[0].weights[0] == 0.5 && meshOnly.value.nodes[0].weights[1] == 1;
	}
	const both = loadGltf(
		triangleDocument(primitive(TARGETS_TWO), `,"weights":[0.5,1]`, `,"weights":[2,3]`),
		triangleBytes());
	assert both.ok;
	if (both.ok) {
		assert both.value.nodes[0].weights[0] == 2 && both.value.nodes[0].weights[1] == 3;
		assert both.value.morphs[0].meshWeights[0] == 0.5;
	}
	const nodeOnly = loadGltf(
		triangleDocument(primitive(TARGETS_TWO), "", `,"weights":[3,2]`), triangleBytes());
	assert nodeOnly.ok;
	if (nodeOnly.ok) {
		assert nodeOnly.value.nodes[0].weights[0] == 3 && nodeOnly.value.morphs[0].meshWeights[0] == 0;
	}
}

test "weights animation decodes LINEAR STEP and CUBICSPLINE with one value per target" {
	const linear = loadGltf(
		triangleDocument(primitive(TARGETS_TWO), "", "", animation(LINEAR_SAMPLER)), triangleBytes());
	assert linear.ok;
	if (!linear.ok) { return; }
	assert linear.value.animations[0].tracks.length == 0;
	assert linear.value.animations[0].weightTracks.length == 1;
	assert linear.value.animations[0].weightTracks[0].sourceNode == 0;
	const curve = linear.value.animations[0].weightTracks[0].curve;
	const half = curve.sampleWeights(0.5);
	assert half.ok;
	if (half.ok) {
		assert half.value.length == 2 && approx(half.value[0], 0.5) && approx(half.value[1], 0.25);
	}
	const later = curve.sampleWeights(1.5);
	assert later.ok;
	if (later.ok) { assert approx(later.value[0], 0.5) && approx(later.value[1], 0.75); }
	const past = curve.sampleWeights(9.0);
	assert past.ok;
	if (past.ok) { assert approx(past.value[0], 0.0) && approx(past.value[1], 1.0); }
	const step = loadGltf(triangleDocument(primitive(TARGETS_TWO), "", "",
		animation(`{"input":5,"output":6,"interpolation":"STEP"}`)), triangleBytes());
	assert step.ok;
	if (step.ok) {
		const held = step.value.animations[0].weightTracks[0].curve.sampleWeights(0.5);
		assert held.ok;
		if (held.ok) { assert approx(held.value[0], 0.0) && approx(held.value[1], 0.0); }
	}
	const cubic = loadGltf(triangleDocument(primitive(TARGETS_TWO), "", "",
		animation(`{"input":7,"output":8,"interpolation":"CUBICSPLINE"}`)), triangleBytes());
	assert cubic.ok;
	if (cubic.ok) {
		const mid = cubic.value.animations[0].weightTracks[0].curve.sampleWeights(0.5);
		assert mid.ok;
		if (mid.ok) { assert approx(mid.value[0], 0.75) && approx(mid.value[1], 0.5); }
	}
}

// Accessor 9 holds the LINEAR weights [0,0, 1,0.5, 0,1] as normalized ubytes (128 for 0.5),
// accessor 10 as normalized shorts (16384), the encodings glTF's sampler table allows.
function quantizedWeights(componentType: int32, normalized: boolean): Result<GltfData, GltfError> {
	let bytes = triangleBytes();
	for (const value of [0, 0, 255, 128, 0, 255, 0, 0]) { bytes.push(value as uint8); }
	for (const value of [0, 0, 32767, 16384, 0, 32767]) {
		bytes.push((value & 255) as uint8);
		bytes.push(((value >> 8) & 255) as uint8);
	}
	const accessor: int32 = componentType == 5121 ? 9 : 10;
	const flag: string = normalized ? `,"normalized":true` : "";
	const accessors: string =
		`,{"bufferView":9,"componentType":${componentType},"count":6,"type":"SCALAR"${flag}}`
		+ `,{"bufferView":10,"componentType":${componentType},"count":6,"type":"SCALAR"${flag}}`;
	return loadGltf(triangleDocument(primitive(TARGETS_TWO), "", "",
		animation(`{"input":5,"output":${accessor}}`), 3, 292, "," + view(272, 6) + ","
		+ view(280, 12), accessors), bytes);
}

test "weights animation reads normalized ubyte and short outputs, not plain integers" {
	for (const componentType of [5121, 5122]) {
		const loaded = quantizedWeights(componentType, true);
		assert loaded.ok;
		if (!loaded.ok) { continue; }
		const half = loaded.value.animations[0].weightTracks[0].curve.sampleWeights(0.5);
		assert half.ok;
		if (half.ok) { assert approx(half.value[0], 0.5) && approx(half.value[1], 0.25); }
		const past = loaded.value.animations[0].weightTracks[0].curve.sampleWeights(9.0);
		assert past.ok;
		if (past.ok) { assert approx(past.value[0], 0.0) && approx(past.value[1], 1.0); }
		const plain = quantizedWeights(componentType, false);
		assert !plain.ok && plain.error == GltfError.Unsupported;
	}
}

test "morph import refuses by name and never drops a target or channel" {
	const bytes = triangleBytes();
	const two = primitive(TARGETS_TWO);
	assert refuses(triangleDocument(two, `,"weights":[1]`), bytes, GltfError.CountMismatch);
	assert refuses(triangleDocument(two, "", `,"weights":[1,2,3]`), bytes, GltfError.CountMismatch);
	assert refuses(triangleDocument(two, "", `,"weights":[1e999,0]`), bytes, GltfError.OutOfRange);
	assert refuses(triangleDocument(two, "", `,"weights":[]`), bytes, GltfError.Unsupported);
	assert loadGltf(triangleDocument(primitive("")), bytes).ok;
	assert refuses(triangleDocument(primitive(""), `,"weights":[1]`), bytes,
		GltfError.CountMismatch);
	assert refuses(triangleDocument(primitive(""), "", `,"weights":[1]`), bytes, GltfError.BadNode);
	assert refuses(triangleDocument(two + "," + primitive("")), bytes, GltfError.CountMismatch);
	assert refuses(triangleDocument(primitive("") + "," + two), bytes, GltfError.CountMismatch);
	assert refuses(triangleDocument(two + "," + primitive('[{"POSITION":2}]')), bytes,
		GltfError.CountMismatch);
	assert refuses(triangleDocument(primitive('[{"POSITION":2,"TEXCOORD_0":3}]')), bytes,
		GltfError.Unsupported);
	assert refuses(triangleDocument(primitive('[{"TANGENT":2}]')), bytes, GltfError.BadReference);
	assert refuses(triangleDocument(primitive('[]')), bytes, GltfError.Unsupported);
	assert refuses(triangleDocument(primitive('[{}]')), bytes, GltfError.Unsupported);
	assert refuses(triangleDocument(two, "", "", "", 2), bytes, GltfError.CountMismatch);
	let nan = triangleBytes();
	const nanBits: uint32 = NAN_BITS;
	for (let byte = 0; byte < 4; byte++) {
		nan[72 + byte] = ((nanBits >> ((byte * 8) as uint32)) & 255) as uint8;
	}
	assert refuses(triangleDocument(two), nan, GltfError.OutOfRange);
	assert refuses(triangleDocument(two, "", "", animation(LINEAR_SAMPLER, 1)), bytes,
		GltfError.BadReference);
	assert refuses(triangleDocument(two, "", "", animation(`{"input":7,"output":6}`)), bytes,
		GltfError.CountMismatch);
	assert refuses(triangleDocument(two, "", "", animation(LINEAR_SAMPLER, 0,
		`,{"sampler":0,"target":{"node":0,"path":"weights"}}`)), bytes, GltfError.Unsupported);
}
