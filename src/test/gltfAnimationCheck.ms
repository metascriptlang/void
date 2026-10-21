import { loadGltf, GltfData } from "../void3d/gltf";
import { sample } from "../void3d/gltfCurve";
import { GltfPose, bind, samplePose } from "../void3d/gltfPose";
import { addGltfBoundNodes } from "../void3d/gltfScene";
import { Scene3D, rootId } from "../void3d/scene";
import { DrawContext } from "../void3d/draw";

function singleton(data: Readonly<GltfData>): boolean {
	return data.animations.length == 1 && data.animations[0].tracks.length == 1;
}

function bytes(): Vec<uint8> {
	let out: Vec<uint8> = [];
	for (const bits of [0 as uint32, 0x3f800000 as uint32,
		0 as uint32, 0 as uint32, 0 as uint32, 0x3f800000 as uint32, 0 as uint32, 0 as uint32]) {
		for (let shift = 0; shift < 32; shift += 8) {
			out.push(((bits >> (shift as uint32)) & 255) as uint8);
		}
	}
	return move out;
}

function document(interpolation: string, node: int32 = 1, path: string = "translation",
	extraChannel: string = "", cubic: boolean = false, secondTransform: string = ""): string {
	const count: int32 = cubic ? 6 : 2;
	const components: int32 = path == "rotation" ? 4 : 3;
	const outputBytes: int32 = count * components * 4;
	return `{"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],`
		+ `"nodes":[{"name":"same","children":[1]},{"name":"same"${secondTransform}}],`
		+ `"buffers":[{"byteLength":${8 + outputBytes}}],`
		+ `"bufferViews":[{"buffer":0,"byteLength":8},`
		+ `{"buffer":0,"byteOffset":8,"byteLength":${outputBytes}}],"accessors":[`
		+ `{"bufferView":0,"componentType":5126,"count":2,"type":"SCALAR"},`
		+ `{"bufferView":1,"componentType":5126,"count":${count},"type":"VEC${components}"}],`
		+ `"animations":[{"name":"move","samplers":[{"input":0,"output":1${interpolation}}],`
		+ `"channels":[{"sampler":0,"target":{"node":${node},"path":"${path}"}}${extraChannel}]}]}`;
}

struct AnimationFixture {
	json: string;
	buffer: Vec<uint8>;
}

function animationFixture(path: string, mode: string): AnimationFixture {
	const cubic = mode == "CUBICSPLINE";
	const count = cubic ? 6 : 2;
	const width = path == "rotation" ? 4 : 3;
	let words: Vec<uint32> = [0, 0x40000000];
	for (let row = 0; row < count; row++) {
		const value = !cubic || row == 1 || row == 4;
		const second = row == (cubic ? 4 : 1);
		for (let component = 0; component < width; component++) {
			let bits: uint32 = 0;
			if (value) {
				if (path == "rotation") {
					if (component == (second ? 2 : 3)) { bits = 0x3f800000; }
				} else if (path == "scale" || component == 0) {
					bits = second ? 0x40000000 : 0x3f800000;
				}
			} else if (row == 2 && component == 0) { bits = 0x3f800000; }
			words.push(bits);
		}
	}
	let buffer: Vec<uint8> = [];
	for (const bits of words) {
		for (let shift = 0; shift < 32; shift += 8) {
			buffer.push(((bits >> (shift as uint32)) & 255) as uint8);
		}
	}
	return { json: document(`,"interpolation":"${mode}"`, 1, path, "", cubic),
		buffer: move buffer };
}

function sparseAnimationFixture(
	path: string, mode: string, zeroBase: boolean, input: boolean = false,
): AnimationFixture {
	const dense = animationFixture(path, mode);
	let buffer = animationFixture(path, mode).buffer;
	const cubic = mode == "CUBICSPLINE";
	const count = input ? 2 : (cubic ? 6 : 2);
	const width = input ? 1 : (path == "rotation" ? 4 : 3);
	const view = input ? 0 : 1;
	const offset = input ? 0 : 8;
	for (let i = 0; i < count * width * 4; i++) { buffer[offset + i] = 0; }
	const slots: Vec<int32> = !input && cubic ? [1, 2, 4] : [0, 1];
	const slotsOffset = buffer.length as int32;
	for (const slot of slots) { buffer.push(slot as uint8); }
	while (buffer.length % 4 != 0) { buffer.push(0); }
	const valuesOffset = buffer.length as int32;
	for (const slot of slots) {
		for (let i = 0; i < width * 4; i++) {
			buffer.push(dense.buffer[offset + slot * width * 4 + i]);
		}
	}
	const shape = input ? "SCALAR" : `VEC${width}`;
	const base = zeroBase ? "" : `"bufferView":${view},`;
	const accessor = `{${base}"componentType":5126,"count":${count},"type":"${shape}",` +
		`"sparse":{"count":${slots.length},"indices":{"bufferView":2,"componentType":5121},` +
		`"values":{"bufferView":3}}}`;
	const json = dense.json.replace(
		`{"bufferView":${view},"componentType":5126,"count":${count},"type":"${shape}"}`,
		accessor)
		.replace(`}],"accessors":[`,
			`},{"buffer":0,"byteOffset":${slotsOffset},"byteLength":${slots.length}},` +
			`{"buffer":0,"byteOffset":${valuesOffset},"byteLength":${slots.length * width * 4}}],` +
			`"accessors":[`)
		.replace(`"buffers":[{"byteLength":${dense.buffer.length}}]`,
			`"buffers":[{"byteLength":${buffer.length}}]`);
	return { json: json, buffer: move buffer };
}

test "sparse TRS outputs preserve dense curves across interpolation modes and base storage" {
	for (const path of ["translation", "rotation", "scale"]) {
		for (const mode of ["LINEAR", "STEP", "CUBICSPLINE"]) {
			const dense = animationFixture(path, mode);
			const expected = loadGltf(dense.json, dense.buffer);
			assert expected.ok;
			if (!expected.ok) { continue; }
			for (const zeroBase of [false, true]) {
				const fixture = sparseAnimationFixture(path, mode, zeroBase);
				const loaded = loadGltf(fixture.json, fixture.buffer);
				assert loaded.ok;
				if (!loaded.ok) { continue; }
				assert singleton(loaded.value);
				assert loaded.value.animations[0].tracks[0].sourceNode == 1;
				const curve = loaded.value.animations[0].tracks[0].curve;
				const control = expected.value.animations[0].tracks[0].curve;
				assert curve.times.length == control.times.length;
				assert curve.values.length == control.values.length;
				for (let i = 0; i < curve.times.length; i++) {
					assert curve.times[i] == control.times[i];
				}
				for (let i = 0; i < curve.values.length; i++) {
					assert curve.values[i] == control.values[i];
				}
				for (const time of [-1.0, 0.5, 1.0, 3.0]) {
					const value = curve.sample(time);
					const wanted = control.sample(time);
					assert value.ok && wanted.ok;
					if (value.ok && wanted.ok) { assert value.value == wanted.value; }
				}
			}
		}
	}
}

test "sparse outputs publish independent bound poses" {
	for (const zeroBase of [false, true]) {
		const fixture = sparseAnimationFixture("translation", "LINEAR", zeroBase);
		const loaded = loadGltf(fixture.json, fixture.buffer);
		assert loaded.ok;
		if (!loaded.ok) { continue; }
		const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
		const first = addGltfBoundNodes(scene, scene.rootId(), loaded.value, []);
		const second = addGltfBoundNodes(scene, scene.rootId(), loaded.value, []);
		assert first.ok && second.ok;
		if (!first.ok || !second.ok) { continue; }
		const a = GltfPose.bind(scene, first.value.nodes, loaded.value.animations[0].tracks);
		const b = GltfPose.bind(scene, second.value.nodes, loaded.value.animations[0].tracks);
		assert a.ok && b.ok;
		if (!a.ok || !b.ok) { continue; }
		assert a.value.samplePose(0.5).ok && b.value.samplePose(1.5).ok;
		assert scene.nodes[first.value.nodes[1].index].local.position.x == 1.25;
		assert scene.nodes[second.value.nodes[1].index].local.position.x == 1.75;
	}
}

test "sparse animation inputs remain refused beside supported output storage" {
	for (const zeroBase of [false, true]) {
		const input = sparseAnimationFixture("translation", "LINEAR", zeroBase, true);
		assert !loadGltf(input.json, input.buffer).ok;
	}
}

test "sparse animation outputs retain layout format finite and quaternion refusal" {
	const fixture = sparseAnimationFixture("translation", "LINEAR", false);
	for (const json of [
		fixture.json.replace(`"count":2,"type":"VEC3"`, `"count":3,"type":"VEC3"`),
		fixture.json.replace(`"type":"VEC3"`, `"type":"VEC4"`),
		fixture.json.replace(`"type":"VEC3"`, `"type":"VEC3","normalized":true`),
		fixture.json.replace(`"componentType":5126,"count":2,"type":"VEC3"`,
			`"componentType":5123,"count":2,"type":"VEC3"`),
		fixture.json.replace(`"sparse":{"count":2`, `"sparse":{"count":3`),
		fixture.json.replace(`"byteOffset":8,"byteLength":24`,
			`"byteOffset":8,"byteLength":24,"byteStride":12`),
		fixture.json.replace(`"byteOffset":8,"byteLength":24`,
			`"byteOffset":8,"byteLength":24,"target":34962`),
		fixture.json.replace(`"byteOffset":36,"byteLength":24`,
			`"byteOffset":36,"byteLength":24,"byteStride":12`),
		fixture.json.replace(`"byteOffset":36,"byteLength":24`,
			`"byteOffset":36,"byteLength":24,"target":34962`),
		fixture.json.replace(`"byteOffset":36,"byteLength":24`,
			`"byteOffset":36,"byteLength":23`),
	]) { assert !loadGltf(json, fixture.buffer).ok; }
	for (const slots of [[1, 1], [1, 0], [0, 2]]) {
		let invalid = sparseAnimationFixture("translation", "LINEAR", false);
		invalid.buffer[32] = slots[0] as uint8;
		invalid.buffer[33] = slots[1] as uint8;
		assert !loadGltf(invalid.json, invalid.buffer).ok;
	}
	let nonFinite = sparseAnimationFixture("translation", "LINEAR", true);
	nonFinite.buffer[38] = 192;
	nonFinite.buffer[39] = 127;
	assert !loadGltf(nonFinite.json, nonFinite.buffer).ok;
	let rotation = sparseAnimationFixture("rotation", "LINEAR", true);
	for (let i = 56; i < 60; i++) { rotation.buffer[i] = 0; }
	assert !loadGltf(rotation.json, rotation.buffer).ok;
}

test "glTF animation default LINEAR retains source ids and drives a real bound scene instance" {
	const loaded = loadGltf(document(""), bytes());
	assert loaded.ok;
	if (!loaded.ok) { return; }
	assert singleton(loaded.value);
	if (!singleton(loaded.value)) { return; }
	assert loaded.value.animations[0].name == "move";
	assert loaded.value.animations[0].tracks[0].sourceNode == 1;
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	const bound = addGltfBoundNodes(scene, scene.rootId(), loaded.value, []);
	assert bound.ok;
	if (!bound.ok) { return; }
	const pose = GltfPose.bind(scene, bound.value.nodes, loaded.value.animations[0].tracks);
	assert pose.ok;
	if (!pose.ok) { return; }
	assert pose.value.samplePose(0.25).ok;
	assert scene.nodes[bound.value.nodes[1].index].local.position.x == 0.25;
	assert scene.nodes[bound.value.nodes[0].index].local.position.x == 0.0;
}

test "glTF animation STEP is exact and endpoints clamp" {
	const loaded = loadGltf(document(',"interpolation":"STEP"'), bytes());
	assert loaded.ok;
	if (!loaded.ok) { return; }
	assert singleton(loaded.value);
	if (!singleton(loaded.value)) { return; }
	const curve = loaded.value.animations[0].tracks[0].curve;
	const before = curve.sample(-1);
	const mid = curve.sample(0.75);
	const end = curve.sample(3);
	assert before.ok && mid.ok && end.ok;
	if (before.ok && mid.ok && end.ok) {
		assert before.value.x == 0 && mid.value.x == 0 && end.value.x == 1;
	}
}

test "glTF animation refuses unknown mode, missing target, morph tracks and cubic shape mismatch" {
	assert !loadGltf(document(',"interpolation":"BEZIER"'), bytes()).ok;
	assert !loadGltf(document("", 2), bytes()).ok;
	assert !loadGltf(document("", 1, "weights"), bytes()).ok;
	assert !loadGltf(document(',"interpolation":"CUBICSPLINE"'), bytes()).ok;
}

test "glTF scale channels decode and duplicate targets refuse before binding" {
	const scale = loadGltf(document("", 1, "scale"), bytes());
	assert scale.ok;
	if (scale.ok) {
		assert singleton(scale.value);
		if (!singleton(scale.value)) { return; }
		const value = scale.value.animations[0].tracks[0].curve.sample(0.5);
		assert value.ok;
		if (value.ok) { assert value.value.x == 0.5; }
	}
	const duplicate = ',{"sampler":0,"target":{"node":1,"path":"translation"}}';
	assert !loadGltf(document("", 1, "translation", duplicate), bytes()).ok;
}

test "glTF cubic triplets retain tangents and decode Hermite rather than LINEAR" {
	let buffer: Vec<uint8> = [];
	for (let i = 0; i < 80; i++) { buffer.push(0); }
	buffer[6] = 128; buffer[7] = 63;
	buffer[58] = 128; buffer[59] = 63;
	const loaded = loadGltf(document(',"interpolation":"CUBICSPLINE"', 1,
		"translation", "", true), buffer);
	assert loaded.ok;
	if (!loaded.ok) { return; }
	assert singleton(loaded.value);
	if (!singleton(loaded.value)) { return; }
	const value = loaded.value.animations[0].tracks[0].curve.sample(0.25);
	assert value.ok;
	if (value.ok) { assert value.value.x == 0.15625; }
}

test "glTF rotation output is four components and samples unit SLERP" {
	let buffer: Vec<uint8> = [];
	for (let i = 0; i < 40; i++) { buffer.push(0); }
	buffer[6] = 128; buffer[7] = 63;
	buffer[22] = 128; buffer[23] = 63;
	buffer[34] = 128; buffer[35] = 63;
	const loaded = loadGltf(document("", 1, "rotation"), buffer);
	assert loaded.ok;
	if (!loaded.ok) { return; }
	assert singleton(loaded.value);
	if (!singleton(loaded.value)) { return; }
	const value = loaded.value.animations[0].tracks[0].curve.sample(0.5);
	assert value.ok;
	if (value.ok) {
		assert Math.abs(value.value.z - 0.70710678) < 0.00001;
		assert Math.abs(value.value.w - 0.70710678) < 0.00001;
	}
}

test "glTF TRS channels refuse matrix targets but allow other targets beside matrix nodes" {
	const transform = ',"matrix":[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]';
	for (const path of ["translation", "rotation", "scale"]) {
		let buffer = bytes();
		if (path == "rotation") {
			buffer = [];
			for (let i = 0; i < 40; i++) { buffer.push(0); }
			buffer[6] = 128; buffer[7] = 63;
			buffer[22] = 128; buffer[23] = 63;
			buffer[38] = 128; buffer[39] = 63;
		}
		assert loadGltf(document("", 0, path, "", false, transform), buffer).ok;
		assert !loadGltf(document("", 1, path, "", false, transform), buffer).ok;
	}
}

test "glTF animation refuses descending timestamp input" {
	let buffer = bytes();
	for (let i = 0; i < 4; i++) { buffer[i] = buffer[i + 4]; buffer[i + 4] = 0; }
	assert !loadGltf(document(""), buffer).ok;
}
