// glTF 2.0 subset loader, for exactly what Hibernal's Blender generator exports
// (RENDERER-BRIEF §4.4: "position + normal + vertex colour only... do not pull in a
// general-purpose glTF library"). One buffer, one buffer view per accessor, FLOAT32
// VEC3 attributes, UNSIGNED_SHORT indices, node TRS, one primitive per mesh. Not
// loaded, by that same contract: materials, textures, skins, animations, cameras,
// morph targets, sparse accessors, interleaved buffer views, more than one buffer.
//
// The caller owns the bytes: `json` is the .gltf document and `buffer` is buffer #0's
// content, already read from wherever it lives. There is no on-disk path here —
// nothing has verified one against a real exported file, and a loader that reads files
// it has never seen is a claim this port does not make.

import { parseJson } from "std/serialize/json/parser";
import { jsonNull } from "std/serialize/json/builder";
import { asString, asInt32, asNumber, at } from "std/serialize/json/accessors";
import { JsonKind, JsonValue } from "std/serialize/json/types";
import { vec3, Vec3 } from "../math/math3d";
import { float32At } from "./gpu3d";
import { MeshData, MeshError, addVertex, addTriangle, hasRoomFor } from "./meshData";
import {
	Scene, NodeId, SceneError, Transform3D, identityTransform,
	addGroup, addMeshNode, setName, isLive,
} from "./scene";

export enum GltfError {
	BadJson,
	NotGltf,
	Unsupported,
	OutOfRange,
	CountMismatch,
	MeshTooLarge,
	BadIndex,
	BadNode,
	BadMeshBinding,
	SceneRefused,
}

const COMPONENT_FLOAT: int32 = 5126;
const COMPONENT_UNSIGNED_SHORT: int32 = 5123;
const NO_MESH: int32 = -1;

function fieldOf(obj: JsonValue, key: string): JsonValue {
	if (obj === null || obj.kind != JsonKind.Object) { return jsonNull(); }
	const count: int32 = obj.keys.length as int32;
	for (let i = 0; i < count; i++) {
		if (obj.keys[i] == key) { return obj.values[i]; }
	}
	return jsonNull();
}

function countOf(v: JsonValue): int32 {
	if (v === null || v.kind != JsonKind.Array) { return 0; }
	return v.items.length as int32;
}

function isNull(v: JsonValue): boolean {
	return v === null || v.kind == JsonKind.Null;
}

function intField(obj: JsonValue, key: string, def: int32): int32 {
	const v: JsonValue = fieldOf(obj, key);
	if (isNull(v)) { return def; }
	return v.asInt32(def);
}

function arrayOf(obj: JsonValue, key: string): JsonValue {
	const v: JsonValue = fieldOf(obj, key);
	if (v === null || v.kind != JsonKind.Array) { return jsonNull(); }
	return v;
}

export struct GltfNode {
	name: string;
	mesh: int32;
	local: Transform3D;
	children: Vec<int32>;
}

export struct GltfData {
	meshes: Vec<MeshData>;
	nodes: Vec<GltfNode>;
	sceneRoots: Vec<int32>;
}

export struct GltfMeshBinding {
	mesh: int32;
	material: int32;
}

// What a decoded accessor claims: where its floats start in the buffer and how many
// elements it holds. The subset's element types are checked before this is built, so
// the decode loops below only multiply.
struct AccessorView {
	offset: int32;
	count: int32;
}

function accessorView(
	accessors: JsonValue,
	views: JsonValue,
	bufferLength: int32,
	index: int32,
	component: int32,
	typeName: string,
	components: int32,
): Result<AccessorView, GltfError> {
	if (index < 0 || index >= countOf(accessors)) {
		return Result.err(GltfError.Unsupported);
	}
	const accessor: JsonValue = accessors.at(index);
	if (isNull(accessor)) { return Result.err(GltfError.Unsupported); }
	if (intField(accessor, "componentType", 0) != component) {
		return Result.err(GltfError.Unsupported);
	}
	const typeField: JsonValue = fieldOf(accessor, "type");
	if (typeField.asString() != typeName) { return Result.err(GltfError.Unsupported); }
	if (!isNull(fieldOf(accessor, "sparse"))) { return Result.err(GltfError.Unsupported); }
	const count: int32 = intField(accessor, "count", -1);
	const viewIndex: int32 = intField(accessor, "bufferView", -1);
	if (viewIndex < 0 || viewIndex >= countOf(views)) {
		return Result.err(GltfError.Unsupported);
	}
	const view: JsonValue = views.at(viewIndex);
	if (isNull(view)) { return Result.err(GltfError.Unsupported); }
	if (intField(view, "buffer", 0) != 0) { return Result.err(GltfError.Unsupported); }
	const elementBytes: int32 = (component == COMPONENT_FLOAT ? 4 : 2) * components;
	const stride: int32 = intField(view, "byteStride", 0);
	if (stride != 0 && stride != elementBytes) { return Result.err(GltfError.Unsupported); }
	const viewOffset: int32 = intField(view, "byteOffset", 0);
	const viewLength: int32 = intField(view, "byteLength", -1);
	const accessorOffset: int32 = intField(accessor, "byteOffset", 0);
	if (viewOffset < 0 || viewLength < 0 || accessorOffset < 0 || count < 0) {
		return Result.err(GltfError.OutOfRange);
	}
	if (viewOffset > bufferLength || viewLength > bufferLength - viewOffset) {
		return Result.err(GltfError.OutOfRange);
	}
	if (accessorOffset > viewLength
		|| count > (viewLength - accessorOffset) / elementBytes) {
		return Result.err(GltfError.OutOfRange);
	}
	const out: AccessorView = { offset: viewOffset + accessorOffset, count: count };
	return Result.ok(out);
}

function vec3At(buffer: Span<uint8>, offset: int32, i: int32): Vec3 {
	const at: int32 = offset + i * 12;
	return vec3(float32At(buffer, at), float32At(buffer, at + 4), float32At(buffer, at + 8));
}


function loadMesh(
	mesh: JsonValue,
	accessors: JsonValue,
	views: JsonValue,
	buffer: Span<uint8>,
	bufferLength: int32,
): Result<MeshData, GltfError> {
	const primitives: JsonValue = arrayOf(mesh, "primitives");
	if (isNull(primitives) || countOf(primitives) != 1) {
		return Result.err(GltfError.Unsupported);
	}
	const attributes: JsonValue = fieldOf(primitives.at(0), "attributes");
	if (isNull(attributes)) { return Result.err(GltfError.Unsupported); }
	const positions: Result<AccessorView, GltfError> = accessorView(
		accessors, views, bufferLength,
		intField(attributes, "POSITION", -1), COMPONENT_FLOAT, "VEC3", 3,
	);
	if (!positions.ok) { return Result.err(positions.error); }
	const normals: Result<AccessorView, GltfError> = accessorView(
		accessors, views, bufferLength,
		intField(attributes, "NORMAL", -1), COMPONENT_FLOAT, "VEC3", 3,
	);
	if (!normals.ok) { return Result.err(normals.error); }
	if (normals.value.count != positions.value.count) {
		return Result.err(GltfError.CountMismatch);
	}
	const colors: JsonValue = fieldOf(attributes, "COLOR_0");
	let colorView: AccessorView = { offset: 0, count: 0 };
	if (!isNull(colors)) {
		const decoded: Result<AccessorView, GltfError> = accessorView(
			accessors, views, bufferLength,
			intField(attributes, "COLOR_0", -1), COMPONENT_FLOAT, "VEC3", 3,
		);
		if (!decoded.ok) { return Result.err(decoded.error); }
		if (decoded.value.count != positions.value.count) {
			return Result.err(GltfError.CountMismatch);
		}
		colorView = decoded.value;
	}
	const count: int32 = positions.value.count;
	const data: MeshData = MeshData.empty();
	if (!data.hasRoomFor(count)) { return Result.err(GltfError.MeshTooLarge); }
	for (let i = 0; i < count; i++) {
		const rgb: Vec3 = colorView.count > 0
			? vec3At(buffer, colorView.offset, i)
			: vec3(1.0, 1.0, 1.0);
		const added: Result<int32, MeshError> = addVertex(
			data,
			vec3At(buffer, positions.value.offset, i),
			vec3At(buffer, normals.value.offset, i),
			{ red: rgb.x, green: rgb.y, blue: rgb.z, alpha: 1.0 },
		);
		if (!added.ok) { return Result.err(GltfError.MeshTooLarge); }
	}
	const indicesField: JsonValue = fieldOf(primitives.at(0), "indices");
	if (!isNull(indicesField)) {
		const indices: Result<AccessorView, GltfError> = accessorView(
			accessors, views, bufferLength,
			indicesField.asInt32(-1), COMPONENT_UNSIGNED_SHORT, "SCALAR", 1,
		);
		if (!indices.ok) { return Result.err(indices.error); }
		if (indices.value.count % 3 != 0) { return Result.err(GltfError.CountMismatch); }
		for (let t = 0; t < indices.value.count; t += 3) {
			const a: int32 = uint16At(buffer, indices.value.offset, t);
			const b: int32 = uint16At(buffer, indices.value.offset, t + 1);
			const c: int32 = uint16At(buffer, indices.value.offset, t + 2);
			const tri: Result<int32, MeshError> = addTriangle(data, a, b, c);
			if (!tri.ok) { return Result.err(GltfError.BadIndex); }
		}
	}
	return Result.ok(data);
}


function uint16At(buffer: Span<uint8>, offset: int32, i: int32): int32 {
	const at: int32 = offset + i * 2;
	return (buffer[at] as int32) | ((buffer[at + 1] as int32) << 8);
}

function numberAt(values: JsonValue, index: int32): Result<float32, GltfError> {
	const value: JsonValue = at(values, index);
	if (value === null || (value.kind != JsonKind.Number && value.kind != JsonKind.Int)) {
		return Result.err(GltfError.Unsupported);
	}
	return Result.ok(asNumber(value, 0.0) as float32);
}

function loadNode(node: JsonValue): Result<GltfNode, GltfError> {
	if (node === null || node.kind != JsonKind.Object) {
		return Result.err(GltfError.Unsupported);
	}
	const local: Transform3D = identityTransform();
	const translation: JsonValue = fieldOf(node, "translation");
	if (!isNull(translation)) {
		if (translation.kind != JsonKind.Array || countOf(translation) != 3) {
			return Result.err(GltfError.Unsupported);
		}
		const x: Result<float32, GltfError> = numberAt(translation, 0);
		const y: Result<float32, GltfError> = numberAt(translation, 1);
		const z: Result<float32, GltfError> = numberAt(translation, 2);
		if (!x.ok) { return Result.err(x.error); }
		if (!y.ok) { return Result.err(y.error); }
		if (!z.ok) { return Result.err(z.error); }
		local.position = vec3(x.value, y.value, z.value);
	}
	const rotation: JsonValue = fieldOf(node, "rotation");
	if (!isNull(rotation)) {
		if (rotation.kind != JsonKind.Array || countOf(rotation) != 4) {
			return Result.err(GltfError.Unsupported);
		}
		const x: Result<float32, GltfError> = numberAt(rotation, 0);
		const y: Result<float32, GltfError> = numberAt(rotation, 1);
		const z: Result<float32, GltfError> = numberAt(rotation, 2);
		const w: Result<float32, GltfError> = numberAt(rotation, 3);
		if (!x.ok) { return Result.err(x.error); }
		if (!y.ok) { return Result.err(y.error); }
		if (!z.ok) { return Result.err(z.error); }
		if (!w.ok) { return Result.err(w.error); }
		local.rotation = { x: x.value, y: y.value, z: z.value, w: w.value };
	}
	const scale: JsonValue = fieldOf(node, "scale");
	if (!isNull(scale)) {
		if (scale.kind != JsonKind.Array || countOf(scale) != 3) {
			return Result.err(GltfError.Unsupported);
		}
		const x: Result<float32, GltfError> = numberAt(scale, 0);
		const y: Result<float32, GltfError> = numberAt(scale, 1);
		const z: Result<float32, GltfError> = numberAt(scale, 2);
		if (!x.ok) { return Result.err(x.error); }
		if (!y.ok) { return Result.err(y.error); }
		if (!z.ok) { return Result.err(z.error); }
		local.scale = vec3(x.value, y.value, z.value);
	}
	const children: Vec<int32> = [];
	const childField: JsonValue = fieldOf(node, "children");
	if (!isNull(childField)) {
		if (childField.kind != JsonKind.Array) {
			return Result.err(GltfError.Unsupported);
		}
		const childCount: int32 = countOf(childField);
		for (let i = 0; i < childCount; i++) {
			const child: JsonValue = at(childField, i);
			if (child === null || child.kind != JsonKind.Int) {
				return Result.err(GltfError.Unsupported);
			}
			children.push(asInt32(child, -1));
		}
	}
	const nameField: JsonValue = fieldOf(node, "name");
	if (!isNull(nameField) && nameField.kind != JsonKind.String) {
		return Result.err(GltfError.Unsupported);
	}
	const meshField: JsonValue = fieldOf(node, "mesh");
	if (!isNull(meshField) && meshField.kind != JsonKind.Int) {
		return Result.err(GltfError.Unsupported);
	}
	return Result.ok({
		name: isNull(nameField) ? "" : nameField.asString(),
		mesh: isNull(meshField) ? NO_MESH : meshField.asInt32(NO_MESH),
		local: local,
		children: children,
	});
}

function validateGraph(data: GltfData): Result<int32, GltfError> {
	const states: Vec<int32> = new Array(data.nodes.length as int32);
	for (let i = 0; i < (states.length as int32); i++) { states[i] = 0; }
	const stack: Vec<int32> = [];
	for (let i = (data.sceneRoots.length as int32) - 1; i >= 0; i--) {
		stack.push(data.sceneRoots[i]);
	}
	let count: int32 = 0;
	while ((stack.length as int32) > 0) {
		const last: int32 = (stack.length as int32) - 1;
		const index: int32 = stack[last];
		stack.pop();
		if (index < 0 || index >= (data.nodes.length as int32) || states[index] != 0) {
			return Result.err(GltfError.BadNode);
		}
		const mesh: int32 = data.nodes[index].mesh;
		if (mesh < NO_MESH || mesh >= (data.meshes.length as int32)) {
			return Result.err(GltfError.BadNode);
		}
		states[index] = 1;
		count = count + 1;
		const childCount: int32 = data.nodes[index].children.length as int32;
		for (let i = childCount - 1; i >= 0; i--) {
			stack.push(data.nodes[index].children[i]);
		}
	}
	return Result.ok(count);
}

export function addGltfNodes(
	ref scene: Scene,
	parent: NodeId,
	data: GltfData,
	bindings: Span<GltfMeshBinding>,
): Result<int32, GltfError> {
	if (!isLive(scene, parent)) { return Result.err(GltfError.SceneRefused); }
	if ((bindings.length as int32) != (data.meshes.length as int32)) {
		return Result.err(GltfError.BadMeshBinding);
	}
	const valid: Result<int32, GltfError> = validateGraph(data);
	if (!valid.ok) { return Result.err(valid.error); }
	const nodes: Vec<int32> = [];
	const parents: Vec<NodeId> = [];
	for (let i = (data.sceneRoots.length as int32) - 1; i >= 0; i--) {
		nodes.push(data.sceneRoots[i]);
		parents.push(parent);
	}
	let count: int32 = 0;
	while ((nodes.length as int32) > 0) {
		const last: int32 = (nodes.length as int32) - 1;
		const index: int32 = nodes[last];
		const under: NodeId = parents[last];
		nodes.pop();
		parents.pop();
		let id: NodeId = { index: -1, generation: 0 };
		const mesh: int32 = data.nodes[index].mesh;
		if (mesh == NO_MESH) {
			const added: Result<NodeId, SceneError> =
				addGroup(scene, under, data.nodes[index].local);
			if (!added.ok) { return Result.err(GltfError.SceneRefused); }
			id = added.value;
		} else {
			const added: Result<NodeId, SceneError> = addMeshNode(
				scene, under, data.nodes[index].local,
				bindings[mesh].mesh, bindings[mesh].material,
			);
			if (!added.ok) { return Result.err(GltfError.SceneRefused); }
			id = added.value;
		}
		const named: Result<int32, SceneError> = setName(scene, id, data.nodes[index].name);
		if (!named.ok) { return Result.err(GltfError.SceneRefused); }
		count = count + 1;
		const childCount: int32 = data.nodes[index].children.length as int32;
		for (let i = childCount - 1; i >= 0; i--) {
			nodes.push(data.nodes[index].children[i]);
			parents.push(id);
		}
	}
	return Result.ok(count);
}



export function loadGltf(json: string, buffer: Span<uint8>): Result<GltfData, GltfError> {
	const parsed: Result<JsonValue, string> = parseJson(json);
	if (!parsed.ok) { return Result.err(GltfError.BadJson); }
	const root: JsonValue = parsed.value;
	const asset: JsonValue = fieldOf(root, "asset");
	if (isNull(asset)) { return Result.err(GltfError.NotGltf); }
	const versionField: JsonValue = fieldOf(asset, "version");
	const version: string = versionField.asString();
	if (version.length < 1 || version[0] != '2') { return Result.err(GltfError.NotGltf); }
	const accessors: JsonValue = arrayOf(root, "accessors");
	const views: JsonValue = arrayOf(root, "bufferViews");
	const data: GltfData = { meshes: [], nodes: [], sceneRoots: [] };
	const meshArray: JsonValue = arrayOf(root, "meshes");
	const meshCount: int32 = countOf(meshArray);
	const buffers: JsonValue = arrayOf(root, "buffers");
	const bufferCount: int32 = countOf(buffers);
	if (bufferCount > 1 || (meshCount > 0 && bufferCount != 1)) {
		return Result.err(GltfError.Unsupported);
	}
	let declaredLength: int32 = 0;
	if (bufferCount == 1) {
		const bufferInfo: JsonValue = at(buffers, 0);
		declaredLength = intField(bufferInfo, "byteLength", -1);
		const actualLength: int32 = buffer.length as int32;
		if (declaredLength < 0 || declaredLength > actualLength) {
			return Result.err(GltfError.OutOfRange);
		}
	}
	for (let i = 0; i < meshCount; i++) {
		const mesh: Result<MeshData, GltfError> =
			loadMesh(meshArray.at(i), accessors, views, buffer, declaredLength);
		if (!mesh.ok) { return Result.err(mesh.error); }
		data.meshes.push(mesh.value);
	}
	const nodeArray: JsonValue = arrayOf(root, "nodes");
	const nodeCount: int32 = countOf(nodeArray);
	for (let i = 0; i < nodeCount; i++) {
		const node: Result<GltfNode, GltfError> = loadNode(nodeArray.at(i));
		if (!node.ok) { return Result.err(node.error); }
		data.nodes.push(node.value);
	}
	const scenes: JsonValue = arrayOf(root, "scenes");
	if (isNull(scenes)) { return Result.err(GltfError.NotGltf); }
	const sceneIndex: int32 = fieldOf(root, "scene").asInt32(0);
	const scene: JsonValue = scenes.at(sceneIndex);
	if (isNull(scene)) { return Result.err(GltfError.NotGltf); }
	const roots: JsonValue = arrayOf(scene, "nodes");
	const rootCount: int32 = countOf(roots);
	for (let i = 0; i < rootCount; i++) {
		const rootNode: JsonValue = roots.at(i);
		if (rootNode === null || rootNode.kind != JsonKind.Int) {
			return Result.err(GltfError.Unsupported);
		}
		data.sceneRoots.push(asInt32(rootNode, -1));
	}
	const valid: Result<int32, GltfError> = validateGraph(data);
	if (!valid.ok) { return Result.err(valid.error); }
	return Result.ok(data);
}
