// glTF 2.0 subset loader: position, normal, COLOR_0, TEXCOORD_0 and TANGENT; materials with a
// base colour, emissive and normal texture and one KHR_texture_transform they share, each image
// a PNG or JPEG in the buffer. One buffer,
// one buffer view per accessor, FLOAT32 attributes, UNSIGNED_SHORT indices, node TRS, triangle
// primitives. Not loaded: skins, animations, cameras, morph targets, sparse accessors,
// interleaved buffer views, more than one buffer, images by URI, occlusion textures.
//
// A mesh with several primitives decodes into one drawable `MeshData` per primitive, and its
// node into a group whose children are one mesh node per primitive: three.js d4ea9b9
// GLTFLoader.js:4035-4053 returns the mesh itself for one primitive and a Group of them otherwise.
//
// The caller owns the bytes: `json` is the .gltf document and `buffer` is buffer #0's
// content, already read from wherever it lives, or `loadGlb` splits a .glb into the two.
// There is no on-disk path here — nothing has verified one against a real exported file, and
// a loader that reads files it has never seen is a claim this port does not make.
// PENDING3D: gltf-real-export-not-exercised

import { parseJson } from "std/serialize/json/parser";
import { jsonNull } from "std/serialize/json/builder";
import { asString, asNumber, at } from "std/serialize/json/accessors";
import { JsonKind, JsonValue } from "std/serialize/json/types";
import { vec3, Vec3, Quat, identityQuat, linearToSrgb } from "../math/math3d";
import { decodeImage, imageFormatOf, ImageError, ImageFormat, Pixels } from "../assets/image";
import { FilterMode, Wrap } from "../gpu/state";
import { float32At } from "./gltfDecode";
import { TextureData } from "./texture";
import {
	MeshData,
	MeshError,
	Rgba,
	Uv,
	addVertex,
	addTexturedVertex,
	addTriangle,
	addTangents,
	addGivenTangents,
	hasRoomFor,
} from "./meshData";

export enum GltfError {
	BadJson,
	NotGltf,
	Unsupported,
	OutOfRange,
	CountMismatch,
	MeshTooLarge,
	BadIndex,
	BadNode,
	NotGlb,
	BadReference,
	ImageByUri,
	BadImage,
	UnsupportedSampler,
	UnsupportedMaterial,
	MissingTexCoord,
}

const COMPONENT_FLOAT: int32 = 5126;
const COMPONENT_UNSIGNED_SHORT: int32 = 5123;
const NO_MESH: int32 = -1;
const INVALID_INT: int32 = -1;
const FILTER_NEAREST: int32 = 9728;
const FILTER_LINEAR: int32 = 9729;
const FILTER_NEAREST_MIPMAP_NEAREST: int32 = 9984;
const FILTER_LINEAR_MIPMAP_NEAREST: int32 = 9985;
const FILTER_NEAREST_MIPMAP_LINEAR: int32 = 9986;
const FILTER_LINEAR_MIPMAP_LINEAR: int32 = 9987;
const WRAP_CLAMP_TO_EDGE: int32 = 33071;
const WRAP_MIRRORED_REPEAT: int32 = 33648;
const WRAP_REPEAT: int32 = 10497;
const GLB_MAGIC: uint32 = 0x46546C67;
const GLB_VERSION: uint32 = 2;
const GLB_CHUNK_JSON: uint32 = 0x4E4F534A;
const GLB_CHUNK_BIN: uint32 = 0x004E4942;
const GLB_HEADER_LENGTH: int32 = 12;
const GLB_CHUNK_HEADER_LENGTH: int32 = 8;
const OPAQUE_TEXEL: uint32 = 0xFF000000;
const WHITE_TEXEL: uint32 = 0xFFFFFFFF;

export const DEFAULT_MATERIAL: int32 = -1;
export const NO_TEXTURE_INDEX: int32 = -1;

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

// The base colour factor is already in the vertex colours of every mesh that names this
// material: a glTF primitive has one material, and the lit block carries no colour.
// glTF 2.0 §3.9.4 alphaMode; the decoder stays free of the renderer, gltfScene.ms maps it.
export enum GltfAlphaMode {
	Opaque,
	Mask,
	Blend,
}

// glTF's alphaCutoff default.
export const GLTF_DEFAULT_CUTOFF: float32 = 0.5;

// `alphaKill` is `alphaCutoff` under MASK, 0 otherwise. `emissiveTexture` names a texture exactly
// when the material emits (a non-zero `emissive` and `emissiveStrength`); one with no emissive
// map of its own names the loader's 1x1 white texture, as M37's emissive key requires a map. The
// same white stands in for a base colour texture when an emitting or normal-mapped material has
// none, so `texture` is a texture whenever either role is. A material's textures share one filter
// and wrap, because the renderer reads its emissive and normal maps with the base texture's
// sampler (draw.ms textureFits); a white is made with the sampler its material's textures use.
// `emissive` is glTF's linear `emissiveFactor`; `emissiveStrength` is
// KHR_materials_emissive_strength's, default 1.
// KHR_texture_transform's properties as the file states them; identity is the extension's
// defaults.
export struct GltfTextureTransform {
	offsetU: float32;
	offsetV: float32;
	rotation: float32;
	scaleU: float32;
	scaleV: float32;
}

export const IDENTITY_TEXTURE_TRANSFORM: GltfTextureTransform = {
	offsetU: 0.0, offsetV: 0.0, rotation: 0.0, scaleU: 1.0, scaleV: 1.0,
};

export struct GltfMaterial {
	texture: int32;
	doubleSided: boolean;
	alphaMode: GltfAlphaMode;
	alphaKill: float32;
	emissiveTexture: int32;
	emissive: Vec3;
	emissiveStrength: float32;
	normalTexture: int32;
	uvTransform: GltfTextureTransform;
}

export struct GltfData {
	meshes: Vec<MeshData>;
	meshMaterials: Vec<int32>;
	materials: Vec<GltfMaterial>;
	textures: Vec<TextureData>;
	nodes: Vec<GltfNode>;
	sceneRoots: Vec<int32>;
}

// `realUvs`: some role names an image, so its primitives need their TEXCOORD_0; a material that
// only emits through the white texture reads no UV.
struct MaterialRead {
	material: GltfMaterial;
	factor: Rgba;
	realUvs: boolean;
	emits: boolean;
	transformRead: boolean;
}

struct ImageView {
	offset: int32;
	length: int32;
	format: ImageFormat;
}

struct Sampling {
	filter: FilterMode;
	wrap: Wrap;
}

const DEFAULT_READ: MaterialRead = {
	material: {
		texture: NO_TEXTURE_INDEX, doubleSided: false,
		alphaMode: GltfAlphaMode.Opaque, alphaKill: 0.0,
		emissiveTexture: NO_TEXTURE_INDEX, emissive: { x: 0.0, y: 0.0, z: 0.0 },
		emissiveStrength: 1.0, normalTexture: NO_TEXTURE_INDEX,
		uvTransform: IDENTITY_TEXTURE_TRANSFORM,
	},
	factor: { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 },
	realUvs: false,
	emits: false,
	transformRead: false,
};


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
	const componentBytes: int32 = component == COMPONENT_FLOAT ? 4 : 2;
	const elementBytes: int32 = componentBytes * components;
	const stride: int32 = intField(view, "byteStride", 0);
	if ((component == COMPONENT_UNSIGNED_SHORT && stride != 0)
		|| (stride != 0 && stride != elementBytes)) {
		return Result.err(GltfError.Unsupported);
	}
	const viewOffset: int32 = intField(view, "byteOffset", 0);
	const viewLength: int32 = intField(view, "byteLength", -1);
	const accessorOffset: int32 = intField(accessor, "byteOffset", 0);
	if (viewOffset < 0 || viewLength < 0 || accessorOffset < 0 || count <= 0) {
		return Result.err(GltfError.OutOfRange);
	}
	if (viewOffset > bufferLength || viewLength > bufferLength - viewOffset) {
		return Result.err(GltfError.OutOfRange);
	}
	if (accessorOffset > viewLength
		|| count > (viewLength - accessorOffset) / elementBytes) {
		return Result.err(GltfError.OutOfRange);
	}
	if (viewOffset % componentBytes != 0 || accessorOffset % componentBytes != 0) {
		return Result.err(GltfError.Unsupported);
	}
	const out: AccessorView = { offset: viewOffset + accessorOffset, count: count };
	return Result.ok(out);
}

function vec3At(buffer: Readonly<Span<uint8>>, offset: int32, i: int32): Vec3 {
	const at: int32 = offset + i * 12;
	return vec3(float32At(buffer, at), float32At(buffer, at + 4), float32At(buffer, at + 8));
}

function isFiniteVec3(value: Vec3): boolean {
	return value.x - value.x == 0.0
		&& value.y - value.y == 0.0
		&& value.z - value.z == 0.0;
}


function uvAt(buffer: Readonly<Span<uint8>>, offset: int32, i: int32): Uv {
	const at: int32 = offset + i * 8;
	return { u: float32At(buffer, at), v: float32At(buffer, at + 4) };
}

function primitivesOf(mesh: JsonValue): Result<JsonValue, GltfError> {
	if (!isNull(fieldOf(mesh, "weights"))) {
		return Result.err(GltfError.Unsupported);
	}
	const primitives: JsonValue = arrayOf(mesh, "primitives");
	if (isNull(primitives) || countOf(primitives) < 1) {
		return Result.err(GltfError.Unsupported);
	}
	return Result.ok(primitives);
}

// Where one glTF mesh's primitives sit in `GltfData.meshes`.
struct PrimitiveRun {
	names: Vec<string>;
	first: int32;
	count: int32;
}

// three.js createUniqueName (GLTFLoader.js:3810-3819): a name's first use is itself, later uses
// add `_1`, `_2`, counted over the whole file. Only mesh names take part here; three.js counts
// node names in the same table.
function uniqueName(ref used: Vec<string>, ref counts: Vec<int32>, base: string): string {
	for (let i = 0; i < (used.length as int32); i++) {
		if (used[i] != base) { continue; }
		counts[i] = counts[i] + 1;
		return `${base}_${counts[i]}`;
	}
	used.push(base);
	counts.push(0);
	return base;
}

function identityTransform(): GltfTransform {
	return { position: vec3(0.0, 0.0, 0.0), rotation: identityQuat(), scale: vec3(1.0, 1.0, 1.0) };
}

// A node of a mesh with several primitives keeps its transform and children and gains one child
// per primitive ahead of them, named as three.js names a mesh's primitives (createUniqueName,
// GLTFLoader.js:3817): the mesh's name, then `_1`, `_2`. A mesh index with no run is left past
// the end of `meshes`, where validateGltfGraph refuses it as BadNode.
function placePrimitives(
	ref data: GltfData,
	runs: Readonly<Span<PrimitiveRun>>,
	first: int32,
): void {
	const meshCount: int32 = data.meshes.length as int32;
	for (let i = 0; i < first; i++) {
		const mesh: int32 = data.nodes[i].mesh;
		if (mesh < 0) { continue; }
		if (mesh >= (runs.length as int32)) {
			data.nodes[i].mesh = meshCount;
			continue;
		}
		const run: Readonly<PrimitiveRun> = runs[mesh];
		data.nodes[i].mesh = run.first;
		if (run.count == 1) { continue; }
		let children: Vec<int32> = [];
		for (let k = 0; k < run.count; k++) {
			children.push(data.nodes.length as int32);
			data.nodes.push({
				name: run.names[k],
				mesh: run.first + k,
				local: identityTransform(),
				children: [],
			});
		}
		for (const child of data.nodes[i].children) { children.push(child); }
		data.nodes[i].mesh = NO_MESH;
		data.nodes[i].children = children;
	}
}

function materialIndexOf(primitive: JsonValue, materialCount: int32): Result<int32, GltfError> {
	if (isNull(fieldOf(primitive, "material"))) { return Result.ok(DEFAULT_MATERIAL); }
	const index: int32 = intField(primitive, "material", INVALID_INT);
	if (index < 0 || index >= materialCount) { return Result.err(GltfError.BadReference); }
	return Result.ok(index);
}

// glTF 2.0 §3.7.2.1 TANGENT: xyz a unit vector, w the bitangent's sign, +1 or -1.
function pushTangent(
	ref tangents: Vec<float32>,
	buffer: Readonly<Span<uint8>>,
	offset: int32,
	i: int32,
): Result<int32, GltfError> {
	const at: int32 = offset + i * 16;
	const direction: Vec3 = vec3At(buffer, at, 0);
	const sign: float32 = float32At(buffer, at + 12);
	if (!isFiniteVec3(direction)) { return Result.err(GltfError.OutOfRange); }
	const lengthSquared: float32 =
		direction.x * direction.x + direction.y * direction.y + direction.z * direction.z;
	if (lengthSquared < 0.999 || lengthSquared > 1.001 || (sign != 1.0 && sign != -1.0)) {
		return Result.err(GltfError.Unsupported);
	}
	tangents.push(direction.x);
	tangents.push(direction.y);
	tangents.push(direction.z);
	tangents.push(sign);
	return Result.ok(i);
}

function loadMesh(
	primitive: JsonValue,
	read: MaterialRead,
	accessors: JsonValue,
	views: JsonValue,
	buffer: Readonly<Span<uint8>>,
	bufferLength: int32,
): Result<MeshData, GltfError> {
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
	const textured: boolean = read.material.texture != NO_TEXTURE_INDEX;
	let uvView: AccessorView = { offset: 0, count: 0 };
	if (read.realUvs) {
		if (isNull(fieldOf(attributes, "TEXCOORD_0"))) {
			return Result.err(GltfError.MissingTexCoord);
		}
		const decoded: Result<AccessorView, GltfError> = accessorView(
			accessors, views, bufferLength,
			intField(attributes, "TEXCOORD_0", -1), COMPONENT_FLOAT, "VEC2", 2,
		);
		if (!decoded.ok) { return Result.err(decoded.error); }
		if (decoded.value.count != positions.value.count) {
			return Result.err(GltfError.CountMismatch);
		}
		uvView = decoded.value;
	}
	const tangented: boolean = read.material.normalTexture != NO_TEXTURE_INDEX;
	let tangentView: AccessorView = { offset: 0, count: 0 };
	if (tangented && !isNull(fieldOf(attributes, "TANGENT"))) {
		const decoded: Result<AccessorView, GltfError> = accessorView(
			accessors, views, bufferLength,
			intField(attributes, "TANGENT", -1), COMPONENT_FLOAT, "VEC4", 4,
		);
		if (!decoded.ok) { return Result.err(decoded.error); }
		if (decoded.value.count != positions.value.count) {
			return Result.err(GltfError.CountMismatch);
		}
		tangentView = decoded.value;
	}
	const count: int32 = positions.value.count;
	let tangents: Vec<float32> = [];
	let data: MeshData = textured ? MeshData.withUvs() : MeshData.empty();
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
		const uv: Uv = read.realUvs ? uvAt(buffer, uvView.offset, i) : { u: 0.0, v: 0.0 };
		if (uv.u - uv.u != 0.0 || uv.v - uv.v != 0.0) {
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
		// glTF's COLOR_0 and baseColorFactor are linear; the API's colours are gamma-encoded.
		const color: Rgba = {
			red: linearToSrgb(rgb.x * read.factor.red),
			green: linearToSrgb(rgb.y * read.factor.green),
			blue: linearToSrgb(rgb.z * read.factor.blue),
			alpha: read.material.alphaMode == GltfAlphaMode.Opaque ? 1.0 : read.factor.alpha,
		};
		const added: Result<int32, MeshError> = textured
			? addTexturedVertex(data, position, normal, uv, color)
			: addVertex(data, position, normal, color);
		if (!added.ok) { return Result.err(GltfError.MeshTooLarge); }
		if (tangentView.count > 0) {
			const tangent: Result<int32, GltfError> =
				pushTangent(tangents, buffer, tangentView.offset, i);
			if (!tangent.ok) { return Result.err(tangent.error); }
		}
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
	if (tangented) {
		const closed: Result<int32, MeshError> =
			tangentView.count > 0 ? addGivenTangents(data, tangents) : addTangents(data);
		if (!closed.ok) { return Result.err(GltfError.Unsupported); }
	}
	return Result.ok(data);
}


function uint16At(buffer: Readonly<Span<uint8>>, offset: int32, i: int32): int32 {
	const at: int32 = offset + i * 2;
	return (buffer[at] as int32) | ((buffer[at + 1] as int32) << 8);
}

function numberAt(values: JsonValue, index: int32): Result<float32, GltfError> {
	return numberOf(at(values, index));
}

function numberOf(value: JsonValue): Result<float32, GltfError> {
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
	let local: GltfTransform = {
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
	let children: Vec<int32> = [];
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

function filterBase(code: int32): int32 {
	return match (code) {
		FILTER_NEAREST | FILTER_NEAREST_MIPMAP_NEAREST
			| FILTER_NEAREST_MIPMAP_LINEAR => FILTER_NEAREST,
		FILTER_LINEAR | FILTER_LINEAR_MIPMAP_NEAREST
			| FILTER_LINEAR_MIPMAP_LINEAR => FILTER_LINEAR,
		_ => INVALID_INT,
	};
}

function wrapOf(code: int32): int32 {
	return match (code) {
		WRAP_CLAMP_TO_EDGE => Wrap.Clamp as int32,
		WRAP_REPEAT => Wrap.Repeat as int32,
		WRAP_MIRRORED_REPEAT => Wrap.Mirror as int32,
		_ => INVALID_INT,
	};
}

function loadSampler(sampler: JsonValue): Result<Sampling, GltfError> {
	if (sampler === null || sampler.kind != JsonKind.Object) {
		return Result.err(GltfError.UnsupportedSampler);
	}
	const magField: JsonValue = fieldOf(sampler, "magFilter");
	const minField: JsonValue = fieldOf(sampler, "minFilter");
	const mag: int32 = isNull(magField) ? FILTER_LINEAR : intValue(magField);
	const min: int32 = isNull(minField) ? mag : filterBase(intValue(minField));
	if (mag != FILTER_NEAREST && mag != FILTER_LINEAR) {
		return Result.err(GltfError.UnsupportedSampler);
	}
	if (min == INVALID_INT) { return Result.err(GltfError.UnsupportedSampler); }
	if (!isNull(magField) && min != mag) { return Result.err(GltfError.UnsupportedSampler); }
	const wrapS: int32 = wrapOf(intField(sampler, "wrapS", WRAP_REPEAT));
	const wrapT: int32 = wrapOf(intField(sampler, "wrapT", WRAP_REPEAT));
	if (wrapS == INVALID_INT || wrapS != wrapT) { return Result.err(GltfError.UnsupportedSampler); }
	const out: Sampling = {
		filter: min == FILTER_NEAREST ? FilterMode.Nearest : FilterMode.Linear,
		wrap: wrapS as Wrap,
	};
	return Result.ok(out);
}

function loadImageView(
	image: JsonValue,
	views: JsonValue,
	bufferLength: int32,
): Result<ImageView, GltfError> {
	if (image === null || image.kind != JsonKind.Object) {
		return Result.err(GltfError.Unsupported);
	}
	if (!isNull(fieldOf(image, "uri"))) { return Result.err(GltfError.ImageByUri); }
	const viewIndex: int32 = intField(image, "bufferView", INVALID_INT);
	if (viewIndex < 0 || viewIndex >= countOf(views)) {
		return Result.err(GltfError.BadReference);
	}
	const format: Result<ImageFormat, GltfError> = match (fieldOf(image, "mimeType").asString()) {
		"image/png" => Result.ok(ImageFormat.Png),
		"image/jpeg" => Result.ok(ImageFormat.Jpeg),
		_ => Result.err(GltfError.BadImage),
	};
	if (!format.ok) { return Result.err(format.error); }
	const view: JsonValue = views.at(viewIndex);
	if (isNull(view) || intField(view, "buffer", 0) != 0
		|| !isNull(fieldOf(view, "byteStride"))) {
		return Result.err(GltfError.Unsupported);
	}
	const offset: int32 = intField(view, "byteOffset", 0);
	const length: int32 = intField(view, "byteLength", INVALID_INT);
	if (offset < 0 || length <= 0 || offset > bufferLength || length > bufferLength - offset) {
		return Result.err(GltfError.OutOfRange);
	}
	const out: ImageView = { offset: offset, length: length, format: format.value };
	return Result.ok(out);
}

function loadTexture(
	texture: JsonValue,
	images: Readonly<Span<ImageView>>,
	samplers: Readonly<Span<Sampling>>,
	buffer: Readonly<Span<uint8>>,
): Result<TextureData, GltfError> {
	if (texture === null || texture.kind != JsonKind.Object) {
		return Result.err(GltfError.Unsupported);
	}
	if (isNull(fieldOf(texture, "source"))) { return Result.err(GltfError.Unsupported); }
	const source: int32 = intField(texture, "source", INVALID_INT);
	if (source < 0 || source >= (images.length as int32)) {
		return Result.err(GltfError.BadReference);
	}
	let sampling: Sampling = { filter: FilterMode.Linear, wrap: Wrap.Repeat };
	if (!isNull(fieldOf(texture, "sampler"))) {
		const index: int32 = intField(texture, "sampler", INVALID_INT);
		if (index < 0 || index >= (samplers.length as int32)) {
			return Result.err(GltfError.BadReference);
		}
		sampling = samplers[index];
	}
	const view: ImageView = images[source];
	const bytes: Readonly<Span<uint8>> = buffer[view.offset..view.offset + view.length];
	const format: Result<ImageFormat, ImageError> = imageFormatOf(bytes);
	if (!format.ok || format.value != view.format) { return Result.err(GltfError.BadImage); }
	const decoded: Result<Pixels, ImageError> = decodeImage(bytes);
	if (!decoded.ok) { return Result.err(GltfError.BadImage); }
	return Result.ok({
		pixels: decoded.value.pixels,
		width: decoded.value.width,
		height: decoded.value.height,
		filter: sampling.filter,
		wrap: sampling.wrap,
	});
}

function unitNumberAt(values: JsonValue, index: int32): Result<float32, GltfError> {
	const value: float32 = try numberAt(values, index);
	if (value < 0.0 || value > 1.0) { return Result.err(GltfError.OutOfRange); }
	return Result.ok(value);
}

// glTF 2.0 §3.9.4: an OPAQUE material ignores alpha. A texture keeps its alpha when a MASK or
// BLEND material samples it; one sampled both ways cannot be both, and is refused.
function keepsAlpha(
	materials: Readonly<Span<GltfMaterial>>,
	texture: int32,
): Result<boolean, GltfError> {
	let opaque: boolean = false;
	let translucent: boolean = false;
	for (const material of materials) {
		if (material.texture != texture && material.emissiveTexture != texture) { continue; }
		if (material.alphaMode == GltfAlphaMode.Opaque) {
			opaque = true;
		} else {
			translucent = true;
		}
	}
	if (opaque && translucent) { return Result.err(GltfError.UnsupportedMaterial); }
	return Result.ok(translucent);
}

function sharedSampling(
	textures: Readonly<Span<TextureData>>,
	material: GltfMaterial,
): Result<Sampling, GltfError> {
	let shared: Sampling = { filter: FilterMode.Linear, wrap: Wrap.Clamp };
	let found: boolean = false;
	for (const index of [material.texture, material.emissiveTexture, material.normalTexture]) {
		if (index == NO_TEXTURE_INDEX) { continue; }
		const sampling: Sampling =
			{ filter: textures[index].filter, wrap: textures[index].wrap };
		if (found && (sampling.filter != shared.filter || sampling.wrap != shared.wrap)) {
			return Result.err(GltfError.UnsupportedSampler);
		}
		shared = sampling;
		found = true;
	}
	return Result.ok(shared);
}

function whiteFor(ref data: GltfData, ref whites: Vec<int32>, sampling: Sampling): int32 {
	for (const index of whites) {
		if (data.textures[index].filter == sampling.filter
			&& data.textures[index].wrap == sampling.wrap) {
			return index;
		}
	}
	const index: int32 = data.textures.length as int32;
	data.textures.push({
		pixels: [WHITE_TEXEL], width: 1, height: 1, filter: sampling.filter, wrap: sampling.wrap,
	});
	whites.push(index);
	return index;
}

// Gives a material the white texture for each role it needs and has no image for: the emissive
// map of an emitting one, and the base texture of an emitting or normal-mapped one.
function substituteWhites(
	ref data: GltfData,
	ref reads: Vec<MaterialRead>,
): Result<int32, GltfError> {
	let whites: Vec<int32> = [];
	for (let i = 0; i < (reads.length as int32); i++) {
		const material: GltfMaterial = data.materials[i];
		const sampling: Sampling = try sharedSampling(data.textures, material);
		const wantsEmissive: boolean =
			reads[i].emits && material.emissiveTexture == NO_TEXTURE_INDEX;
		const wantsBase: boolean = (reads[i].emits || material.normalTexture != NO_TEXTURE_INDEX)
			&& material.texture == NO_TEXTURE_INDEX;
		if (wantsEmissive || wantsBase) {
			const white: int32 = whiteFor(data, whites, sampling);
			if (wantsEmissive) { data.materials[i].emissiveTexture = white; }
			if (wantsBase) { data.materials[i].texture = white; }
		}
		reads[i].material = data.materials[i];
	}
	return Result.ok(0);
}

function forceOpaque(texels: Span<uint32>): void {
	for (let i = 0; i < (texels.length as int32); i++) { texels[i] = texels[i] | OPAQUE_TEXEL; }
}

function alphaCutoffOf(material: JsonValue): Result<float32, GltfError> {
	const cutoff: JsonValue = fieldOf(material, "alphaCutoff");
	if (isNull(cutoff)) { return Result.ok(GLTF_DEFAULT_CUTOFF); }
	const value: float32 = try numberOf(cutoff);
	if (value < 0.0) { return Result.err(GltfError.OutOfRange); }
	return Result.ok(value);
}

// A textureInfo: the index of a texture sampled at TEXCOORD_0. The renderer's textured layout
// carries one UV set, so another set is refused rather than sampled at the wrong place.
function textureInfoIndex(info: JsonValue, textureCount: int32): Result<int32, GltfError> {
	if (info.kind != JsonKind.Object) { return Result.err(GltfError.Unsupported); }
	if (intField(info, "texCoord", 0) != 0) { return Result.err(GltfError.UnsupportedMaterial); }
	const index: int32 = intField(info, "index", INVALID_INT);
	if (index < 0 || index >= textureCount) { return Result.err(GltfError.BadReference); }
	return Result.ok(index);
}

// A textureInfo's KHR_texture_transform, the only extension a texture reference may carry here.
// Its texCoord override is held to 0 like the textureInfo's own.
function textureTransformOf(info: JsonValue): Result<GltfTextureTransform, GltfError> {
	const extensions: JsonValue = fieldOf(info, "extensions");
	if (isNull(extensions)) { return Result.ok(IDENTITY_TEXTURE_TRANSFORM); }
	if (extensions.kind != JsonKind.Object) { return Result.err(GltfError.Unsupported); }
	for (const name of extensions.keys) {
		if (name != "KHR_texture_transform") { return Result.err(GltfError.UnsupportedMaterial); }
	}
	const extension: JsonValue = fieldOf(extensions, "KHR_texture_transform");
	if (extension.kind != JsonKind.Object) { return Result.err(GltfError.Unsupported); }
	if (intField(extension, "texCoord", 0) != 0) {
		return Result.err(GltfError.UnsupportedMaterial);
	}
	let transform: GltfTextureTransform = IDENTITY_TEXTURE_TRANSFORM;
	const offset: JsonValue = fieldOf(extension, "offset");
	if (!isNull(offset)) {
		if (offset.kind != JsonKind.Array || countOf(offset) != 2) {
			return Result.err(GltfError.Unsupported);
		}
		transform.offsetU = try numberAt(offset, 0);
		transform.offsetV = try numberAt(offset, 1);
	}
	const rotation: JsonValue = fieldOf(extension, "rotation");
	if (!isNull(rotation)) { transform.rotation = try numberOf(rotation); }
	const scale: JsonValue = fieldOf(extension, "scale");
	if (!isNull(scale)) {
		if (scale.kind != JsonKind.Array || countOf(scale) != 2) {
			return Result.err(GltfError.Unsupported);
		}
		transform.scaleU = try numberAt(scale, 0);
		transform.scaleV = try numberAt(scale, 1);
	}
	return Result.ok(transform);
}

// The material's textures share the one UV transform its program reads (Bevy takes the base
// colour's and warns on another, bevy_gltf loader/mod.rs:1301-1350); one that differs is refused.
function shareTransform(info: JsonValue, ref read: MaterialRead): Result<boolean, GltfError> {
	const transform: GltfTextureTransform = try textureTransformOf(info);
	if (!read.transformRead) {
		read.material.uvTransform = transform;
		read.transformRead = true;
		return Result.ok(true);
	}
	if (transform != read.material.uvTransform) {
		return Result.err(GltfError.UnsupportedMaterial);
	}
	return Result.ok(true);
}

// glTF 2.0 §3.9.2: emissiveFactor defaults to 0 and the emitted colour is factor times the map,
// so a factor of 0 emits nothing whatever the map is (three.js GLTFLoader.js:3774-3784 sets the
// same two terms). KHR_materials_emissive_strength scales it (GLTFLoader.js:878).
function emissiveStrengthOf(material: JsonValue): Result<float32, GltfError> {
	const extensions: JsonValue = fieldOf(material, "extensions");
	const extension: JsonValue = fieldOf(extensions, "KHR_materials_emissive_strength");
	const strength: JsonValue = fieldOf(extension, "emissiveStrength");
	if (isNull(strength)) { return Result.ok(1.0); }
	const value: float32 = try numberOf(strength);
	if (value < 0.0) { return Result.err(GltfError.OutOfRange); }
	return Result.ok(value);
}

function loadEmission(
	material: JsonValue,
	textureCount: int32,
	ref read: MaterialRead,
): Result<boolean, GltfError> {
	let factor: Vec3 = vec3(0.0, 0.0, 0.0);
	const field: JsonValue = fieldOf(material, "emissiveFactor");
	if (!isNull(field)) {
		if (field.kind != JsonKind.Array || countOf(field) != 3) {
			return Result.err(GltfError.Unsupported);
		}
		const red: float32 = try unitNumberAt(field, 0);
		const green: float32 = try unitNumberAt(field, 1);
		const blue: float32 = try unitNumberAt(field, 2);
		factor = vec3(red, green, blue);
	}
	const strength: float32 = try emissiveStrengthOf(material);
	let index: int32 = NO_TEXTURE_INDEX;
	const info: JsonValue = fieldOf(material, "emissiveTexture");
	if (!isNull(info)) { index = try textureInfoIndex(info, textureCount); }
	const lit: boolean = factor.x != 0.0 || factor.y != 0.0 || factor.z != 0.0;
	if (!lit || strength == 0.0) { return Result.ok(false); }
	read.material.emissive = factor;
	read.material.emissiveStrength = strength;
	read.material.emissiveTexture = index;
	read.emits = true;
	if (index != NO_TEXTURE_INDEX) {
		read.realUvs = true;
		const _shared: boolean = try shareTransform(info, read);
	}
	return Result.ok(true);
}

// glTF 2.0 §3.9.3 normalTexture: `scale` multiplies the map's xy (three.js GLTFLoader.js:3747-3756
// sets normalScale from it). The normal-map key has no scale, so one other than 1 is refused.
function loadNormalTexture(
	material: JsonValue,
	textureCount: int32,
	ref read: MaterialRead,
): Result<boolean, GltfError> {
	const info: JsonValue = fieldOf(material, "normalTexture");
	if (isNull(info)) { return Result.ok(false); }
	const index: int32 = try textureInfoIndex(info, textureCount);
	const scale: JsonValue = fieldOf(info, "scale");
	if (!isNull(scale)) {
		const value: float32 = try numberOf(scale);
		if (value != 1.0) { return Result.err(GltfError.UnsupportedMaterial); }
	}
	read.material.normalTexture = index;
	read.realUvs = true;
	const _shared: boolean = try shareTransform(info, read);
	return Result.ok(true);
}

function loadMaterial(material: JsonValue, textureCount: int32): Result<MaterialRead, GltfError> {
	if (material === null || material.kind != JsonKind.Object) {
		return Result.err(GltfError.Unsupported);
	}
	if (!isNull(fieldOf(material, "occlusionTexture"))) {
		return Result.err(GltfError.UnsupportedMaterial);
	}
	let read: MaterialRead = DEFAULT_READ;
	const _emits: boolean = try loadEmission(material, textureCount, read);
	const _normals: boolean = try loadNormalTexture(material, textureCount, read);
	const alphaMode: JsonValue = fieldOf(material, "alphaMode");
	if (!isNull(alphaMode)) {
		if (alphaMode.kind != JsonKind.String) { return Result.err(GltfError.Unsupported); }
		const mode: string = alphaMode.strVal;
		if (mode == "MASK") {
			read.material.alphaMode = GltfAlphaMode.Mask;
		} else if (mode == "BLEND") {
			read.material.alphaMode = GltfAlphaMode.Blend;
		} else if (mode != "OPAQUE") {
			return Result.err(GltfError.Unsupported);
		}
	}
	if (read.material.alphaMode == GltfAlphaMode.Mask) {
		read.material.alphaKill = try alphaCutoffOf(material);
		if (read.material.alphaKill == 0.0) { read.material.alphaMode = GltfAlphaMode.Opaque; }
	}
	const doubleSided: JsonValue = fieldOf(material, "doubleSided");
	if (!isNull(doubleSided)) {
		if (doubleSided.kind != JsonKind.Bool) { return Result.err(GltfError.Unsupported); }
		read.material.doubleSided = doubleSided.boolVal;
	}
	const pbr: JsonValue = fieldOf(material, "pbrMetallicRoughness");
	if (isNull(pbr)) { return Result.ok(read); }
	if (pbr.kind != JsonKind.Object) { return Result.err(GltfError.Unsupported); }
	const factor: JsonValue = fieldOf(pbr, "baseColorFactor");
	if (!isNull(factor)) {
		if (factor.kind != JsonKind.Array || countOf(factor) != 4) {
			return Result.err(GltfError.Unsupported);
		}
		read.factor = {
			red: try unitNumberAt(factor, 0),
			green: try unitNumberAt(factor, 1),
			blue: try unitNumberAt(factor, 2),
			alpha: try unitNumberAt(factor, 3),
		};
	}
	const info: JsonValue = fieldOf(pbr, "baseColorTexture");
	if (isNull(info)) { return Result.ok(read); }
	read.material.texture = try textureInfoIndex(info, textureCount);
	read.realUvs = true;
	const _shared: boolean = try shareTransform(info, read);
	return Result.ok(read);
}

export function validateGltfGraph(data: GltfData): Result<int32, GltfError> {
	let states: Vec<int32> = new Array(data.nodes.length as int32);
	for (let i = 0; i < (states.length as int32); i++) { states[i] = 0; }
	let stack: Vec<int32> = [];
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

function decodeGltf(
	json: string,
	buffer: Readonly<Span<uint8>>,
	fromGlb: boolean,
): Result<GltfData, GltfError> {
	const parsed: Result<JsonValue, string> = parseJson(json);
	if (!parsed.ok) { return Result.err(GltfError.BadJson); }
	const root: JsonValue = parsed.value;
	const asset: JsonValue = fieldOf(root, "asset");
	if (isNull(asset)) { return Result.err(GltfError.NotGltf); }
	const versionField: JsonValue = fieldOf(asset, "version");
	const version: string = versionField.asString();
	if (version != "2.0") { return Result.err(GltfError.NotGltf); }
	const requiredExtensions: JsonValue = fieldOf(root, "extensionsRequired");
	if (!isNull(requiredExtensions)) {
		if (requiredExtensions.kind != JsonKind.Array) { return Result.err(GltfError.Unsupported); }
		for (let i = 0; i < countOf(requiredExtensions); i++) {
			const name: JsonValue = at(requiredExtensions, i);
			if (name.kind != JsonKind.String || name.strVal != "KHR_texture_transform") {
				return Result.err(GltfError.Unsupported);
			}
		}
	}
	if (!isArrayOrAbsent(root, "accessors")
		|| !isArrayOrAbsent(root, "bufferViews")
		|| !isArrayOrAbsent(root, "meshes")
		|| !isArrayOrAbsent(root, "nodes")
		|| !isArrayOrAbsent(root, "buffers")
		|| !isArrayOrAbsent(root, "images")
		|| !isArrayOrAbsent(root, "samplers")
		|| !isArrayOrAbsent(root, "textures")
		|| !isArrayOrAbsent(root, "materials")) {
		return Result.err(GltfError.Unsupported);
	}
	const accessors: JsonValue = arrayOf(root, "accessors");
	const views: JsonValue = arrayOf(root, "bufferViews");
	let data: GltfData = {
		meshes: [],
		meshMaterials: [],
		materials: [],
		textures: [],
		nodes: [],
		sceneRoots: [],
	};
	const meshArray: JsonValue = arrayOf(root, "meshes");
	const meshCount: int32 = countOf(meshArray);
	const imageArray: JsonValue = arrayOf(root, "images");
	const imageCount: int32 = countOf(imageArray);
	const buffers: JsonValue = arrayOf(root, "buffers");
	const bufferCount: int32 = countOf(buffers);
	if (bufferCount > 1 || ((meshCount > 0 || imageCount > 0) && bufferCount != 1)) {
		return Result.err(GltfError.Unsupported);
	}
	let declaredLength: int32 = 0;
	if (bufferCount == 1) {
		const bufferInfo: JsonValue = at(buffers, 0);
		if (fromGlb && !isNull(fieldOf(bufferInfo, "uri"))) {
			return Result.err(GltfError.Unsupported);
		}
		declaredLength = intField(bufferInfo, "byteLength", -1);
		const actualLength: int32 = buffer.length as int32;
		if (declaredLength < 0 || declaredLength > actualLength) {
			return Result.err(GltfError.OutOfRange);
		}
	}
	const samplerArray: JsonValue = arrayOf(root, "samplers");
	let samplers: Vec<Sampling> = [];
	for (let i = 0; i < countOf(samplerArray); i++) {
		samplers.push(try loadSampler(samplerArray.at(i)));
	}
	let images: Vec<ImageView> = [];
	for (let i = 0; i < imageCount; i++) {
		images.push(try loadImageView(imageArray.at(i), views, declaredLength));
	}
	const textureArray: JsonValue = arrayOf(root, "textures");
	const textureCount: int32 = countOf(textureArray);
	for (let i = 0; i < textureCount; i++) {
		data.textures.push(try loadTexture(textureArray.at(i), images, samplers, buffer));
	}
	const materialArray: JsonValue = arrayOf(root, "materials");
	const materialCount: int32 = countOf(materialArray);
	let reads: Vec<MaterialRead> = [];
	for (let i = 0; i < materialCount; i++) {
		const read: MaterialRead = try loadMaterial(materialArray.at(i), textureCount);
		reads.push(read);
		data.materials.push(read.material);
	}
	for (let i = 0; i < textureCount; i++) {
		if (!(try keepsAlpha(data.materials, i))) { forceOpaque(data.textures[i].pixels); }
	}
	const _whites: int32 = try substituteWhites(data, reads);
	let runs: Vec<PrimitiveRun> = [];
	let usedNames: Vec<string> = [];
	let usedCounts: Vec<int32> = [];
	for (let i = 0; i < meshCount; i++) {
		const primitives: JsonValue = try primitivesOf(meshArray.at(i));
		const nameField: JsonValue = fieldOf(meshArray.at(i), "name");
		if (!isNull(nameField) && nameField.kind != JsonKind.String) {
			return Result.err(GltfError.Unsupported);
		}
		const base: string = isNull(nameField) ? `mesh_${i}` : nameField.asString();
		let names: Vec<string> = [];
		for (let p = 0; p < countOf(primitives); p++) {
			names.push(uniqueName(usedNames, usedCounts, base));
		}
		runs.push({ names: names, first: data.meshes.length as int32, count: countOf(primitives) });
		for (let p = 0; p < countOf(primitives); p++) {
			const primitive: JsonValue = primitives.at(p);
			const material: int32 = try materialIndexOf(primitive, materialCount);
			const read: MaterialRead =
				material == DEFAULT_MATERIAL ? DEFAULT_READ : reads[material];
			const mesh: Result<MeshData, GltfError> =
				loadMesh(primitive, read, accessors, views, buffer, declaredLength);
			if (!mesh.ok) { return Result.err(mesh.error); }
			data.meshes.push(mesh.value);
			data.meshMaterials.push(material);
		}
	}
	const nodeArray: JsonValue = arrayOf(root, "nodes");
	const nodeCount: int32 = countOf(nodeArray);
	for (let i = 0; i < nodeCount; i++) {
		const node: Result<GltfNode, GltfError> = loadNode(nodeArray.at(i));
		if (!node.ok) { return Result.err(node.error); }
		data.nodes.push(node.value);
	}
	placePrimitives(data, runs, nodeCount);
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

export function loadGltf(json: string, buffer: Readonly<Span<uint8>>): Result<GltfData, GltfError> {
	return decodeGltf(json, buffer, false);
}

function uint32At(bytes: Readonly<Span<uint8>>, at: int32): uint32 {
	return (bytes[at] as uint32)
		| ((bytes[at + 1] as uint32) << (8 as uint32))
		| ((bytes[at + 2] as uint32) << (16 as uint32))
		| ((bytes[at + 3] as uint32) << (24 as uint32));
}

// Chunk layout and checks from glTF 2.0.1 §4.4: a JSON chunk first, an optional BIN chunk
// second, every chunk 4-byte aligned, unknown chunks after those two ignored.
export function loadGlb(bytes: Readonly<Span<uint8>>): Result<GltfData, GltfError> {
	const total: int32 = bytes.length as int32;
	if (total < GLB_HEADER_LENGTH + GLB_CHUNK_HEADER_LENGTH) {
		return Result.err(GltfError.NotGlb);
	}
	if (uint32At(bytes, 0) != GLB_MAGIC || uint32At(bytes, 4) != GLB_VERSION
		|| uint32At(bytes, 8) != (total as uint32)) {
		return Result.err(GltfError.NotGlb);
	}
	let at: int32 = GLB_HEADER_LENGTH;
	let json: string = "";
	let binaryStart: int32 = 0;
	let binaryEnd: int32 = 0;
	let chunk: int32 = 0;
	while (at < total) {
		if (total - at < GLB_CHUNK_HEADER_LENGTH) { return Result.err(GltfError.NotGlb); }
		const length: uint32 = uint32At(bytes, at);
		const kind: uint32 = uint32At(bytes, at + 4);
		const start: int32 = at + GLB_CHUNK_HEADER_LENGTH;
		if (length > ((total - start) as uint32) || length % (4 as uint32) != 0) {
			return Result.err(GltfError.NotGlb);
		}
		const end: int32 = start + (length as int32);
		if (chunk == 0) {
			if (kind != GLB_CHUNK_JSON) { return Result.err(GltfError.NotGlb); }
			let text: uint8[] = [];
			for (let i = start; i < end; i++) { text.push(bytes[i]); }
			json = text.asString();
		} else if (chunk == 1 && kind == GLB_CHUNK_BIN) {
			binaryStart = start;
			binaryEnd = end;
		} else if (kind == GLB_CHUNK_JSON || kind == GLB_CHUNK_BIN) {
			return Result.err(GltfError.NotGlb);
		}
		at = end;
		chunk = chunk + 1;
	}
	return decodeGltf(json, bytes[binaryStart..binaryEnd], true);
}
