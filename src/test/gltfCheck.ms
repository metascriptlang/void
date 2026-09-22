import { approx } from "./helpers";
import { Mat4 } from "../math/math3d";
import { addGltfNodes, loadGltf, GltfError, GltfMeshBinding } from "../void3d/gltf";
import { Scene, SceneError, syncWorld, findByName, worldOf, rootId } from "../void3d/scene";
import { vertexCount, triangleCount } from "../void3d/meshData";
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
	const out: Vec<uint8> = [];
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
	assert approx(mesh.vertices[3], 0.0) && approx(mesh.vertices[4], 0.0) && approx(mesh.vertices[5], 1.0);
	assert approx(mesh.vertices[13], 0.0) && approx(mesh.vertices[14], 0.0) && approx(mesh.vertices[15], 1.0);
	assert approx(mesh.vertices[6], 1.0) && approx(mesh.vertices[7], 0.0) && approx(mesh.vertices[8], 0.0);
	assert approx(mesh.vertices[16], 0.0) && approx(mesh.vertices[17], 1.0) && approx(mesh.vertices[18], 0.0);
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
	const loaded = loadGltf(treeGltf(), triangleBuffer());
	assert loaded.ok;
	if (!loaded.ok) { return; }
	let scene: Scene = Scene.create();
	const missing: Result<int32, GltfError> =
		addGltfNodes(scene, scene.rootId(), loaded.value, []);
	assert !missing.ok;
	if (!missing.ok) { assert missing.error == GltfError.BadMeshBinding; }
	const bindings: Vec<GltfMeshBinding> = [{ mesh: 7, material: 9 }];
	const added: Result<int32, GltfError> =
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
	assert scene.meshes[payload].mesh == 7;
	assert scene.meshes[payload].material == 9;
}

test "COLOR_0 absent means white, and a wrong count is refused" {
	const noColor = loadGltf(
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
	assert noColor.ok;
	if (!noColor.ok) { return; }
	const mesh = noColor.value.meshes[0];
	assert approx(mesh.vertices[6], 1.0) && approx(mesh.vertices[7], 1.0) && approx(mesh.vertices[8], 1.0);
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
}

test "not glTF, bad JSON, short buffer and missing POSITION each say which one" {
	const wrongVersion = loadGltf(
		"{\"asset\":{\"version\":\"1.0\"}}", [],
	);
	assert !wrongVersion.ok;
	if (!wrongVersion.ok) { assert wrongVersion.error == GltfError.NotGltf; }
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
