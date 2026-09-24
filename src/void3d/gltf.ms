// glTF 2.0 subset loader for low-poly meshes coloured per vertex: position, normal and
// COLOR_0, with no textures. One buffer, one buffer view per accessor, FLOAT32
// VEC3 attributes, UNSIGNED_SHORT indices, node TRS, one primitive per mesh. Not
// loaded: materials, textures, skins, animations, cameras,
// morph targets, sparse accessors, interleaved buffer views, more than one buffer.
//
// The caller owns the bytes: `json` is the .gltf document and `buffer` is buffer #0's
// content, already read from wherever it lives. There is no on-disk path here —
// nothing has verified one against a real exported file, and a loader that reads files
// it has never seen is a claim this port does not make.
// PENDING3D: gltf-real-export-not-exercised

import { parseJson } from "std/serialize/json/parser";
import { jsonNull } from "std/serialize/json/builder";
import { asString, asNumber, at } from "std/serialize/json/accessors";
import { JsonKind, JsonValue } from "std/serialize/json/types";
import { vec3, Vec3, Quat, identityQuat } from "../math/math3d";
import { float32At } from "./gltfDecode";
import { MeshData, MeshError, addVertex, addTriangle, hasRoomFor } from "./meshData";

export enum GltfError {
	BadJson,
	NotGltf,
	Unsupported,
	OutOfRange,
	CountMismatch,
	MeshTooLarge,
	BadIndex,
	BadNode,
}

const COMPONENT_FLOAT: int32 = 5126;
const COMPONENT_UNSIGNED_SHORT: int32 = 5123;
const NO_MESH: int32 = -1;
const INVALID_INT: int32 = -1;

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

function intValue(v: JsonValue): int32 {
	if (v === null || v.kind != JsonKind.Int
		|| v.intVal < (-2147483647 as int64) - 1
		|| v.intVal > 2147483647 as int64) {
		return INVALID_INT;
	}
	return v.intVal as int32;
}

function intField(obj: JsonValue, key: string, def: int32): int32 {
	const v: JsonValue = fieldOf(obj, key);
	if (isNull(v)) { return def; }
	return intValue(v);
}

function arrayOf(obj: JsonValue, key: string): JsonValue {
	const v: JsonValue = fieldOf(obj, key);
	if (v === null || v.kind != JsonKind.Array) { return jsonNull(); }
	return v;
}

function isArrayOrAbsent(obj: JsonValue, key: string): boolean {
	const v: JsonValue = fieldOf(obj, key);
	return isNull(v) || v.kind == JsonKind.Array;
}

export struct GltfTransform {
	position: Vec3;
	rotation: Quat;
	scale: Vec3;
}

export struct GltfNode {
	name: string;
	mesh: int32;
	local: GltfTransform;
	children: Vec<int32>;
}

export struct GltfData {
	meshes: Vec<MeshData>;
	nodes: Vec<GltfNode>;
	sceneRoots: Vec<int32>;
}


// What a decoded accessor claims: where its floats start in the buffer and how many
// elements it holds. The subset's element types are checked before this is built, so
// the decode loops below only multiply.
struct AccessorView {
	offset: int32;
	count: int32;
}

function accessorError(error: GltfError): Result<AccessorView, GltfError> {
	const result: Result<AccessorView, GltfError> = Result.err(error);
	return result;
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
		return accessorError(GltfError.Unsupported);
	}
	const accessor: JsonValue = accessors.at(index);
	if (isNull(accessor)) { return accessorError(GltfError.Unsupported); }
	if (intField(accessor, "componentType", 0) != component) {
		return accessorError(GltfError.Unsupported);
	}
	const typeField: JsonValue = fieldOf(accessor, "type");
	if (typeField.asString() != typeName) { return accessorError(GltfError.Unsupported); }
	if (!isNull(fieldOf(accessor, "sparse"))) { return accessorError(GltfError.Unsupported); }
	const count: int32 = intField(accessor, "count", -1);
	const viewIndex: int32 = intField(accessor, "bufferView", -1);
	if (viewIndex < 0 || viewIndex >= countOf(views)) {
		return accessorError(GltfError.Unsupported);
	}
	const view: JsonValue = views.at(viewIndex);
	if (isNull(view)) { return accessorError(GltfError.Unsupported); }
	if (intField(view, "buffer", 0) != 0) { return accessorError(GltfError.Unsupported); }
	const componentBytes: int32 = component == COMPONENT_FLOAT ? 4 : 2;
	const elementBytes: int32 = componentBytes * components;
	const stride: int32 = intField(view, "byteStride", 0);
	if ((component == COMPONENT_UNSIGNED_SHORT && stride != 0)
		|| (stride != 0 && stride != elementBytes)) {
		return accessorError(GltfError.Unsupported);
	}
	const viewOffset: int32 = intField(view, "byteOffset", 0);
	const viewLength: int32 = intField(view, "byteLength", -1);
	const accessorOffset: int32 = intField(accessor, "byteOffset", 0);
	if (viewOffset < 0 || viewLength < 0 || accessorOffset < 0 || count <= 0) {
		return accessorError(GltfError.OutOfRange);
	}
	if (viewOffset > bufferLength || viewLength > bufferLength - viewOffset) {
		return accessorError(GltfError.OutOfRange);
	}
	if (accessorOffset > viewLength
		|| count > (viewLength - accessorOffset) / elementBytes) {
		return accessorError(GltfError.OutOfRange);
	}
	if (viewOffset % componentBytes != 0 || accessorOffset % componentBytes != 0) {
		return accessorError(GltfError.Unsupported);
	}
	const out: AccessorView = { offset: viewOffset + accessorOffset, count: count };
	return Result.ok(out);
}

function vec3At(buffer: Span<uint8>, offset: int32, i: int32): Vec3 {
	const at: int32 = offset + i * 12;
	return vec3(float32At(buffer, at), float32At(buffer, at + 4), float32At(buffer, at + 8));
}

function isFiniteVec3(value: Vec3): boolean {
	return value.x - value.x == 0.0
		&& value.y - value.y == 0.0
		&& value.z - value.z == 0.0;
}


function loadMesh(
	mesh: JsonValue,
	accessors: JsonValue,
	views: JsonValue,
	buffer: Span<uint8>,
	bufferLength: int32,
): Result<MeshData, GltfError> {
	if (!isNull(fieldOf(mesh, "weights"))) {
		return Result.err(GltfError.Unsupported);
	}
	const primitives: JsonValue = arrayOf(mesh, "primitives");
	if (isNull(primitives) || countOf(primitives) != 1) {
		return Result.err(GltfError.Unsupported);
	}
	const primitive: JsonValue = at(primitives, 0);
	if (!isNull(fieldOf(primitive, "targets"))) {
		return Result.err(GltfError.Unsupported);
	}
	if (intField(primitive, "mode", 4) != 4) {
		return Result.err(GltfError.Unsupported);
	}
	const attributes: JsonValue = fieldOf(primitive, "attributes");
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
		const position: Vec3 = vec3At(buffer, positions.value.offset, i);
		const normal: Vec3 = vec3At(buffer, normals.value.offset, i);
		const rgb: Vec3 = colorView.count > 0
			? vec3At(buffer, colorView.offset, i)
			: vec3(1.0, 1.0, 1.0);
		if (!isFiniteVec3(position) || !isFiniteVec3(normal) || !isFiniteVec3(rgb)) {
			return Result.err(GltfError.OutOfRange);
		}
		if (colorView.count > 0
			&& (rgb.x < 0.0 || rgb.x > 1.0
				|| rgb.y < 0.0 || rgb.y > 1.0
				|| rgb.z < 0.0 || rgb.z > 1.0)) {
			return Result.err(GltfError.Unsupported);
		}
		const normalLength: float32 =
			normal.x * normal.x + normal.y * normal.y + normal.z * normal.z;
		if (normalLength < 0.999 || normalLength > 1.001) {
			return Result.err(GltfError.Unsupported);
		}
		const added: Result<int32, MeshError> = addVertex(
			data, position, normal,
			{ red: rgb.x, green: rgb.y, blue: rgb.z, alpha: 1.0 },
		);
		if (!added.ok) { return Result.err(GltfError.MeshTooLarge); }
	}
	const indexAccessor: int32 = intField(primitive, "indices", -1);
	if (indexAccessor < 0) { return Result.err(GltfError.Unsupported); }
	const indices: Result<AccessorView, GltfError> = accessorView(
		accessors, views, bufferLength,
		indexAccessor, COMPONENT_UNSIGNED_SHORT, "SCALAR", 1,
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
	const number: number = asNumber(value, 0.0);
	const narrowed: float32 = number as float32;
	if (number - number != 0.0 || narrowed - narrowed != 0.0) {
		return Result.err(GltfError.OutOfRange);
	}
	return Result.ok(narrowed);
}

function loadNode(node: JsonValue): Result<GltfNode, GltfError> {
	if (node === null || node.kind != JsonKind.Object) {
		return Result.err(GltfError.Unsupported);
	}
	if (!isNull(fieldOf(node, "matrix"))
		|| !isNull(fieldOf(node, "skin"))
		|| !isNull(fieldOf(node, "weights"))) {
		return Result.err(GltfError.Unsupported);
	}
	const local: GltfTransform = {
		position: vec3(0.0, 0.0, 0.0),
		rotation: identityQuat(),
		scale: vec3(1.0, 1.0, 1.0),
	};
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
		const lengthSquared: float32 =
			x.value * x.value + y.value * y.value + z.value * z.value + w.value * w.value;
		if (lengthSquared < 0.999 || lengthSquared > 1.001) {
			return Result.err(GltfError.Unsupported);
		}
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
		const determinant: float32 = x.value * y.value * z.value;
		if (determinant - determinant != 0.0 || determinant <= 1e-10) {
			return Result.err(GltfError.Unsupported);
		}
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
			const childIndex: int32 = intValue(at(childField, i));
			if (childIndex < 0) {
				return Result.err(GltfError.Unsupported);
			}
			children.push(childIndex);
		}
	}
	const nameField: JsonValue = fieldOf(node, "name");
	if (!isNull(nameField) && nameField.kind != JsonKind.String) {
		return Result.err(GltfError.Unsupported);
	}
	const meshField: JsonValue = fieldOf(node, "mesh");
	let mesh: int32 = NO_MESH;
	if (!isNull(meshField)) {
		mesh = intValue(meshField);
		if (mesh < 0) { return Result.err(GltfError.Unsupported); }
	}
	return Result.ok({
		name: isNull(nameField) ? "" : nameField.asString(),
		mesh: mesh,
		local: local,
		children: children,
	});
}

export function validateGltfGraph(data: GltfData): Result<int32, GltfError> {
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




export function loadGltf(json: string, buffer: Span<uint8>): Result<GltfData, GltfError> {
	const parsed: Result<JsonValue, string> = parseJson(json);
	if (!parsed.ok) { return Result.err(GltfError.BadJson); }
	const root: JsonValue = parsed.value;
	const asset: JsonValue = fieldOf(root, "asset");
	if (isNull(asset)) { return Result.err(GltfError.NotGltf); }
	const versionField: JsonValue = fieldOf(asset, "version");
	const version: string = versionField.asString();
	if (version != "2.0") { return Result.err(GltfError.NotGltf); }
	const requiredExtensions: JsonValue = fieldOf(root, "extensionsRequired");
	if (!isNull(requiredExtensions)
		&& (requiredExtensions.kind != JsonKind.Array || countOf(requiredExtensions) > 0)) {
		return Result.err(GltfError.Unsupported);
	}
	if (!isArrayOrAbsent(root, "accessors")
		|| !isArrayOrAbsent(root, "bufferViews")
		|| !isArrayOrAbsent(root, "meshes")
		|| !isArrayOrAbsent(root, "nodes")
		|| !isArrayOrAbsent(root, "buffers")) {
		return Result.err(GltfError.Unsupported);
	}
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
	const sceneIndex: int32 = intField(root, "scene", 0);
	const scene: JsonValue = scenes.at(sceneIndex);
	if (isNull(scene) || scene.kind != JsonKind.Object) {
		return Result.err(GltfError.NotGltf);
	}
	if (!isArrayOrAbsent(scene, "nodes")) { return Result.err(GltfError.Unsupported); }
	const roots: JsonValue = arrayOf(scene, "nodes");
	const rootCount: int32 = countOf(roots);
	for (let i = 0; i < rootCount; i++) {
		const rootNode: int32 = intValue(roots.at(i));
		if (rootNode < 0) {
			return Result.err(GltfError.Unsupported);
		}
		data.sceneRoots.push(rootNode);
	}
	const valid: Result<int32, GltfError> = validateGltfGraph(data);
	if (!valid.ok) { return Result.err(valid.error); }
	return Result.ok(data);
}
