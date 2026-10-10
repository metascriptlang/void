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
	extraChannel: string = "", cubic: boolean = false): string {
	const count: int32 = cubic ? 6 : 2;
	const components: int32 = path == "rotation" ? 4 : 3;
	const outputBytes: int32 = count * components * 4;
	return `{"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],`
		+ `"nodes":[{"name":"same","children":[1]},{"name":"same"}],`
		+ `"buffers":[{"byteLength":${8 + outputBytes}}],`
		+ `"bufferViews":[{"buffer":0,"byteLength":8},`
		+ `{"buffer":0,"byteOffset":8,"byteLength":${outputBytes}}],"accessors":[`
		+ `{"bufferView":0,"componentType":5126,"count":2,"type":"SCALAR"},`
		+ `{"bufferView":1,"componentType":5126,"count":${count},"type":"VEC${components}"}],`
		+ `"animations":[{"name":"move","samplers":[{"input":0,"output":1${interpolation}}],`
		+ `"channels":[{"sampler":0,"target":{"node":${node},"path":"${path}"}}${extraChannel}]}]}`;
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

test "glTF animation refuses descending timestamp input" {
	let buffer = bytes();
	for (let i = 0; i < 4; i++) { buffer[i] = buffer[i + 4]; buffer[i + 4] = 0; }
	assert !loadGltf(document(""), buffer).ok;
}
