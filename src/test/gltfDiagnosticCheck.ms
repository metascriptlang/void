import {
	GltfError, loadGltf, loadGltfDetailed, loadGlb, loadGlbDetailed, describe,
} from "../void3d/gltf";

const EMPTY: string = `{"asset":{"version":"2.0"},"nodes":[],"scenes":[{"nodes":[]}]}`;

test "detailed glTF success keeps legacy decoded meaning" {
	const legacy = loadGltf(EMPTY, []);
	const detailed = loadGltfDetailed(EMPTY, [], "empty.gltf");
	assert legacy.ok && detailed.ok;
	if (legacy.ok && detailed.ok) {
		assert detailed.value.meshes.length == legacy.value.meshes.length;
		assert detailed.value.nodes.length == legacy.value.nodes.length;
		assert detailed.value.sceneRoots.length == legacy.value.sceneRoots.length;
	}
}

test "glTF syntax failure retains parser cause and input name" {
	const result = loadGltfDetailed("{", [], "broken.gltf");
	assert !result.ok;
	if (result.ok) { return; }
	assert result.error.code == GltfError.BadJson;
	assert result.error.source == "broken.gltf";
	assert result.error.location == "$";
	assert result.error.cause.length > 0;
	const text = result.error.describe();
	assert text.includes("broken.gltf") && text.includes("BadJson") && text.includes("$");
}

test "glTF version diagnostic points at asset version without changing legacy error" {
	const json: string = `{"asset":{"version":"1.0"}}`;
	const legacy = loadGltf(json, []);
	const result = loadGltfDetailed(json, [], "old.gltf");
	assert !legacy.ok && !result.ok;
	if (legacy.ok || result.ok) { return; }
	assert legacy.error == result.error.code && legacy.error == GltfError.NotGltf;
	assert result.error.location == "$.asset.version";
	assert result.error.cause.includes("2.0");
}

test "glTF sampler failure names exact failed object rather than first neighbour" {
	const json: string = `{"asset":{"version":"2.0"},"samplers":[{},` +
		`{"name":"broken nearest","minFilter":3}],"scenes":[{"nodes":[]}]}`;
	const result = loadGltfDetailed(json, [], "samplers.gltf");
	assert !result.ok;
	if (result.ok) { return; }
	assert result.error.code == GltfError.UnsupportedSampler;
	assert result.error.location == "$.samplers[1]";
	assert result.error.name == "broken nearest";
	assert result.error.cause.length > 0;
}

test "glTF stride preflight locates exact conflicting attribute accessor and buffer view" {
	const json: string = `{"asset":{"version":"2.0"},"buffers":[{"byteLength":72}],` +
		`"bufferViews":[{"buffer":0,"byteLength":72}],"accessors":[` +
		`{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3"},` +
		`{"bufferView":0,"byteOffset":36,"componentType":5126,"count":3,"type":"VEC3"}],` +
		`"meshes":[{"name":"SharedView","primitives":[` +
		`{"attributes":{"POSITION":0,"NORMAL":1},"indices":2}]}],` +
		`"scenes":[{"nodes":[]}]}`;
	const bytes: Vec<uint8> = new Array(72);
	const result = loadGltfDetailed(json, bytes, "stride.gltf");
	assert !result.ok;
	if (result.ok) { return; }
	assert result.error.code == GltfError.Unsupported;
	assert result.error.location == "$.meshes[0].primitives[0].attributes.NORMAL";
	assert result.error.name == "SharedView";
	assert result.error.cause.includes("accessors[1]");
	assert result.error.cause.includes("bufferViews[0]");
	assert result.error.cause.includes("byteStride");
}

test "glTF index failures report named mesh primitive and concrete rejection cause" {
	const json: string = `{"asset":{"version":"2.0"},"buffers":[{"byteLength":75}],` +
		`"bufferViews":[{"buffer":0,"byteLength":36},` +
		`{"buffer":0,"byteOffset":36,"byteLength":36},` +
		`{"buffer":0,"byteOffset":72,"byteLength":3}],"accessors":[` +
		`{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3"},` +
		`{"bufferView":1,"componentType":5126,"count":3,"type":"VEC3"},` +
		`{"bufferView":2,"componentType":5121,"count":3,"type":"SCALAR"}],` +
		`"meshes":[{"name":"BrokenMesh","primitives":[` +
		`{"attributes":{"POSITION":0,"NORMAL":1},"indices":2}]}],` +
		`"scenes":[{"nodes":[]}]}`;
	let bytes: Vec<uint8> = new Array(75);
	for (let normal = 0; normal < 3; normal++) {
		bytes[36 + normal * 12 + 10] = 128;
		bytes[36 + normal * 12 + 11] = 63;
	}
	bytes[73] = 1;
	bytes[74] = 3;
	const result = loadGltfDetailed(json, bytes, "indices.gltf");
	assert !result.ok;
	if (result.ok) { return; }
	assert result.error.code == GltfError.BadIndex;
	assert result.error.location == "$.meshes[0].primitives[0]";
	assert result.error.name == "BrokenMesh";
	assert result.error.cause.includes(">= vertex count");
	const countJson = json.replace(`"count":3,"type":"SCALAR"`, `"count":2,"type":"SCALAR"`);
	for (const mode of [4, 5, 6]) {
		const mismatched = loadGltfDetailed(countJson.replace(`"attributes":`,
			`"mode":${mode},"attributes":`), bytes, "count.gltf");
		assert !mismatched.ok;
		if (mismatched.ok) { continue; }
		assert mismatched.error.code == GltfError.CountMismatch;
		assert mismatched.error.location == "$.meshes[0].primitives[0]";
		assert mismatched.error.name == "BrokenMesh";
		assert mismatched.error.cause.includes("index count");
	}
}

function jsonGlb(json: string): Vec<uint8> {
	const text = json.asBytes();
	const length: int32 = ((text.length as int32) + 3) & ~3;
	const words: Vec<uint32> = [0x46546c67, 2, (length + 20) as uint32,
		length as uint32, 0x4e4f534a];
	let bytes: Vec<uint8> = [];
	for (const word of words) {
		for (let byte = 0; byte < 4; byte++) {
			bytes.push(((word >> ((byte * 8) as uint32)) & 255) as uint8);
		}
	}
	for (const byte of text) { bytes.push(byte); }
	while (bytes.length < length + 20) { bytes.push(32); }
	return bytes;
}

test "GLB detailed header failure retains legacy code and named container location" {
	const legacy = loadGlb([]);
	const result = loadGlbDetailed([], "empty.glb");
	assert !legacy.ok && !result.ok;
	if (legacy.ok || result.ok) { return; }
	assert result.error.code == legacy.error && legacy.error == GltfError.NotGlb;
	assert result.error.source == "empty.glb" && result.error.location == "$.glb.header";
}

test "GLB detailed API forwards JSON causes and preserves valid legacy success" {
	const good = jsonGlb(EMPTY);
	assert loadGlb(good).ok && loadGlbDetailed(good, "valid.glb").ok;
	const bad = loadGlbDetailed(jsonGlb("{"), "syntax.glb");
	assert !bad.ok;
	if (!bad.ok) {
		assert bad.error.code == GltfError.BadJson;
		assert bad.error.source == "syntax.glb" && bad.error.location == "$";
		assert bad.error.cause.length > 0;
	}
}

test "glTF failed named node retains source object identity and reason" {
	const json: string = `{"asset":{"version":"2.0"},"nodes":[{},` +
		`{"name":"Hero","skin":0}],"scenes":[{"nodes":[0,1]}]}`;
	const result = loadGltfDetailed(json, [], "hero.gltf");
	assert !result.ok;
	if (result.ok) { return; }
	assert result.error.code == GltfError.BadNode;
	assert result.error.location == "$.nodes[1]";
	assert result.error.name == "Hero";
	assert result.error.cause.includes("skin");
	assert result.error.describe().includes("Hero");
}
