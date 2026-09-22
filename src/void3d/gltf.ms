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
import { asString, asInt32, asNumber, at, length } from "std/serialize/json/accessors";
import { JsonKind, JsonValue } from "std/serialize/json/types";
import { vec3, Vec3 } from "../math/math3d";
import { float32At } from "./gpu3d";
import { MeshData, MeshError, Rgba, addVertex, addTriangle, hasRoomFor } from "./meshData";
import { Transform3D, identityTransform } from "./scene";

export enum GltfError {
	BadJson,
	NotGltf,
	Unsupported,
	OutOfRange,
	CountMismatch,
	MeshTooLarge,
	BadIndex,
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
	const accessor: JsonValue = accessors.at(index);
	if (isNull(accessor)) { return Result.err(GltfError.Unsupported); }
	if (intField(accessor, "componentType", 0) != component) {
		return Result.err(GltfError.Unsupported);
	}
	const typeField: JsonValue = fieldOf(accessor, "type");
	if (typeField.asString() != typeName) { return Result.err(GltfError.Unsupported); }
	if (!isNull(fieldOf(accessor, "sparse"))) { return Result.err(GltfError.Unsupported); }
	const count: int32 = intField(accessor, "count", 0);
	const viewIndex: int32 = intField(accessor, "bufferView", 0);
	const view: JsonValue = views.at(viewIndex);
	if (isNull(view)) { return Result.err(GltfError.Unsupported); }
	if (intField(view, "buffer", 0) != 0) { return Result.err(GltfError.Unsupported); }
	const elementBytes: int32 = (component == COMPONENT_FLOAT ? 4 : 2) * components;
	const stride: int32 = intField(view, "byteStride", 0);
	if (stride != 0 && stride != elementBytes) { return Result.err(GltfError.Unsupported); }
	const offset: int32 = intField(view, "byteOffset", 0) + intField(accessor, "byteOffset", 0);
	if (offset < 0 || count < 0 || offset + count * elementBytes > bufferLength) {
		return Result.err(GltfError.OutOfRange);
	}
	const out: AccessorView = { offset: offset, count: count };
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
): Result<MeshData, GltfError> {
	const primitives: JsonValue = arrayOf(mesh, "primitives");
	if (isNull(primitives) || countOf(primitives) != 1) {
		return Result.err(GltfError.Unsupported);
	}
	const attributes: JsonValue = fieldOf(primitives.at(0), "attributes");
	if (isNull(attributes)) { return Result.err(GltfError.Unsupported); }
	const positions: Result<AccessorView, GltfError> = accessorView(
		accessors, views, buffer.length as int32,
		intField(attributes, "POSITION", -1), COMPONENT_FLOAT, "VEC3", 3,
	);
	if (!positions.ok) { return Result.err(positions.error); }
	const normals: Result<AccessorView, GltfError> = accessorView(
		accessors, views, buffer.length as int32,
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
			accessors, views, buffer.length as int32,
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
			accessors, views, buffer.length as int32,
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

function loadNode(node: JsonValue): GltfNode {
	const local: Transform3D = identityTransform();
	const translation: JsonValue = arrayOf(node, "translation");
	if (!isNull(translation) && countOf(translation) == 3) {
		local.position = vec3(
			translation.at(0).asNumber(0.0) as float32,
			translation.at(1).asNumber(0.0) as float32,
			translation.at(2).asNumber(0.0) as float32,
		);
	}
	const rotation: JsonValue = arrayOf(node, "rotation");
	if (!isNull(rotation) && countOf(rotation) == 4) {
		local.rotation = {
			x: rotation.at(0).asNumber(0.0) as float32,
			y: rotation.at(1).asNumber(0.0) as float32,
			z: rotation.at(2).asNumber(0.0) as float32,
			w: rotation.at(3).asNumber(1.0) as float32,
		};
	}
	const scale: JsonValue = arrayOf(node, "scale");
	if (!isNull(scale) && countOf(scale) == 3) {
		local.scale = vec3(
			scale.at(0).asNumber(1.0) as float32,
			scale.at(1).asNumber(1.0) as float32,
			scale.at(2).asNumber(1.0) as float32,
		);
	}
	const children: Vec<int32> = [];
	const childArray: JsonValue = arrayOf(node, "children");
	const childCount: int32 = countOf(childArray) as int32;
	for (let i = 0; i < childCount; i++) {
		children.push(childArray.at(i).asInt32(-1));
	}
	const nameField: JsonValue = fieldOf(node, "name");
	const nameOfNode: string = nameField.asString();
	const meshField: JsonValue = fieldOf(node, "mesh");
	return {
		name: nameOfNode,
		mesh: isNull(meshField) ? NO_MESH : meshField.asInt32(NO_MESH),
		local: local,
		children: children,
	};
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
	const meshCount: int32 = countOf(meshArray) as int32;
	for (let i = 0; i < meshCount; i++) {
		const mesh: Result<MeshData, GltfError> =
			loadMesh(meshArray.at(i), accessors, views, buffer);
		if (!mesh.ok) { return Result.err(mesh.error); }
		data.meshes.push(mesh.value);
	}
	const nodeArray: JsonValue = arrayOf(root, "nodes");
	const nodeCount: int32 = countOf(nodeArray) as int32;
	for (let i = 0; i < nodeCount; i++) {
		data.nodes.push(loadNode(nodeArray.at(i)));
	}
	const scenes: JsonValue = arrayOf(root, "scenes");
	if (isNull(scenes)) { return Result.err(GltfError.NotGltf); }
	const sceneIndex: int32 = fieldOf(root, "scene").asInt32(0);
	const scene: JsonValue = scenes.at(sceneIndex);
	if (isNull(scene)) { return Result.err(GltfError.NotGltf); }
	const roots: JsonValue = arrayOf(scene, "nodes");
	const rootCount: int32 = countOf(roots) as int32;
	for (let i = 0; i < rootCount; i++) {
		data.sceneRoots.push(roots.at(i).asInt32(-1));
	}
	return Result.ok(data);
}
