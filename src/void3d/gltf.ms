// glTF 2.0 subset loader: position, normal, COLOR_0 and TEXCOORD_0; base colour materials
// with at most one texture, its image a PNG or JPEG in the buffer. One buffer, one buffer view
// per accessor, FLOAT32 attributes, UNSIGNED_SHORT indices, node TRS, one primitive per mesh.
// Not loaded: skins, animations, cameras, morph targets, sparse accessors, interleaved buffer
// views, more than one buffer, images by URI.
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
import { vec3, Vec3, Quat, identityQuat } from "../math/math3d";
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
export struct GltfMaterial {
	texture: int32;
	doubleSided: boolean;
}

export struct GltfData {
	meshes: Vec<MeshData>;
	meshMaterials: Vec<int32>;
	materials: Vec<GltfMaterial>;
	textures: Vec<TextureData>;
	nodes: Vec<GltfNode>;
	sceneRoots: Vec<int32>;
}

struct MaterialRead {
	material: GltfMaterial;
	factor: Rgba;
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
	material: { texture: NO_TEXTURE_INDEX, doubleSided: false },
	factor: { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 },
};


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


function uvAt(buffer: Span<uint8>, offset: int32, i: int32): Uv {
	const at: int32 = offset + i * 8;
	return { u: float32At(buffer, at), v: float32At(buffer, at + 4) };
}

function primitiveOf(mesh: JsonValue): Result<JsonValue, GltfError> {
	if (!isNull(fieldOf(mesh, "weights"))) {
		return Result.err(GltfError.Unsupported);
	}
	const primitives: JsonValue = arrayOf(mesh, "primitives");
	if (isNull(primitives) || countOf(primitives) != 1) {
		return Result.err(GltfError.Unsupported);
	}
	return Result.ok(at(primitives, 0));
}

function materialIndexOf(primitive: JsonValue, materialCount: int32): Result<int32, GltfError> {
	if (isNull(fieldOf(primitive, "material"))) { return Result.ok(DEFAULT_MATERIAL); }
	const index: int32 = intField(primitive, "material", INVALID_INT);
	if (index < 0 || index >= materialCount) { return Result.err(GltfError.BadReference); }
	return Result.ok(index);
}

function loadMesh(
	primitive: JsonValue,
	read: MaterialRead,
	accessors: JsonValue,
	views: JsonValue,
	buffer: Span<uint8>,
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
	if (textured) {
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
	const count: int32 = positions.value.count;
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
		const uv: Uv = textured ? uvAt(buffer, uvView.offset, i) : { u: 0.0, v: 0.0 };
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
		const color: Rgba = {
			red: rgb.x * read.factor.red,
			green: rgb.y * read.factor.green,
			blue: rgb.z * read.factor.blue,
			alpha: 1.0,
		};
		const added: Result<int32, MeshError> = textured
			? addTexturedVertex(data, position, normal, uv, color)
			: addVertex(data, position, normal, color);
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

function samplingError(): Result<Sampling, GltfError> {
	const result: Result<Sampling, GltfError> = Result.err(GltfError.UnsupportedSampler);
	return result;
}

function loadSampler(sampler: JsonValue): Result<Sampling, GltfError> {
	if (sampler === null || sampler.kind != JsonKind.Object) { return samplingError(); }
	const magField: JsonValue = fieldOf(sampler, "magFilter");
	const minField: JsonValue = fieldOf(sampler, "minFilter");
	const mag: int32 = isNull(magField) ? FILTER_LINEAR : intValue(magField);
	const min: int32 = isNull(minField) ? mag : filterBase(intValue(minField));
	if (mag != FILTER_NEAREST && mag != FILTER_LINEAR) { return samplingError(); }
	if (min == INVALID_INT) { return samplingError(); }
	if (!isNull(magField) && min != mag) { return samplingError(); }
	const wrapS: int32 = wrapOf(intField(sampler, "wrapS", WRAP_REPEAT));
	const wrapT: int32 = wrapOf(intField(sampler, "wrapT", WRAP_REPEAT));
	if (wrapS == INVALID_INT || wrapS != wrapT) { return samplingError(); }
	const out: Sampling = {
		filter: min == FILTER_NEAREST ? FilterMode.Nearest : FilterMode.Linear,
		wrap: wrapS as Wrap,
	};
	return Result.ok(out);
}

function imageError(error: GltfError): Result<ImageView, GltfError> {
	const result: Result<ImageView, GltfError> = Result.err(error);
	return result;
}

function loadImageView(
	image: JsonValue,
	views: JsonValue,
	bufferLength: int32,
): Result<ImageView, GltfError> {
	if (image === null || image.kind != JsonKind.Object) {
		return imageError(GltfError.Unsupported);
	}
	if (!isNull(fieldOf(image, "uri"))) { return imageError(GltfError.ImageByUri); }
	const viewIndex: int32 = intField(image, "bufferView", INVALID_INT);
	if (viewIndex < 0 || viewIndex >= countOf(views)) {
		return imageError(GltfError.BadReference);
	}
	const mimeType: string = fieldOf(image, "mimeType").asString();
	let format: ImageFormat = ImageFormat.Png;
	if (mimeType == "image/jpeg") {
		format = ImageFormat.Jpeg;
	} else if (mimeType != "image/png") {
		return imageError(GltfError.BadImage);
	}
	const view: JsonValue = views.at(viewIndex);
	if (isNull(view) || intField(view, "buffer", 0) != 0
		|| !isNull(fieldOf(view, "byteStride"))) {
		return imageError(GltfError.Unsupported);
	}
	const offset: int32 = intField(view, "byteOffset", 0);
	const length: int32 = intField(view, "byteLength", INVALID_INT);
	if (offset < 0 || length <= 0 || offset > bufferLength || length > bufferLength - offset) {
		return imageError(GltfError.OutOfRange);
	}
	const out: ImageView = { offset: offset, length: length, format: format };
	return Result.ok(out);
}

function loadTexture(
	texture: JsonValue,
	images: Span<ImageView>,
	samplers: Span<Sampling>,
	buffer: Span<uint8>,
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
	const bytes: Span<uint8> = buffer[view.offset..view.offset + view.length];
	const format: Result<ImageFormat, ImageError> = imageFormatOf(bytes);
	if (!format.ok || format.value != view.format) { return Result.err(GltfError.BadImage); }
	const decoded: Result<Pixels, ImageError> = decodeImage(bytes);
	if (!decoded.ok) { return Result.err(GltfError.BadImage); }
	// glTF 2.0 §3.9.4: an OPAQUE material ignores alpha, and loadMaterial refuses MASK and BLEND.
	let pixels: Vec<uint32> = decoded.value.pixels;
	for (let i = 0; i < (pixels.length as int32); i++) { pixels[i] = pixels[i] | OPAQUE_TEXEL; }
	return Result.ok({
		pixels: pixels,
		width: decoded.value.width,
		height: decoded.value.height,
		filter: sampling.filter,
		wrap: sampling.wrap,
	});
}

function materialError(error: GltfError): Result<MaterialRead, GltfError> {
	const result: Result<MaterialRead, GltfError> = Result.err(error);
	return result;
}

function unitNumberAt(values: JsonValue, index: int32): Result<float32, GltfError> {
	const value: float32 = try numberAt(values, index);
	if (value < 0.0 || value > 1.0) { return Result.err(GltfError.OutOfRange); }
	return Result.ok(value);
}

function loadMaterial(material: JsonValue, textureCount: int32): Result<MaterialRead, GltfError> {
	if (material === null || material.kind != JsonKind.Object) {
		return materialError(GltfError.Unsupported);
	}
	if (!isNull(fieldOf(material, "normalTexture"))
		|| !isNull(fieldOf(material, "occlusionTexture"))
		|| !isNull(fieldOf(material, "emissiveTexture"))) {
		return materialError(GltfError.UnsupportedMaterial);
	}
	const emissive: JsonValue = fieldOf(material, "emissiveFactor");
	if (!isNull(emissive)) {
		if (emissive.kind != JsonKind.Array || countOf(emissive) != 3) {
			return materialError(GltfError.Unsupported);
		}
		for (let i = 0; i < 3; i++) {
			const channel: float32 = try unitNumberAt(emissive, i);
			if (channel != 0.0) { return materialError(GltfError.UnsupportedMaterial); }
		}
	}
	const alphaMode: JsonValue = fieldOf(material, "alphaMode");
	if (!isNull(alphaMode) && alphaMode.asString() != "OPAQUE") {
		return materialError(GltfError.UnsupportedMaterial);
	}
	let read: MaterialRead = DEFAULT_READ;
	const doubleSided: JsonValue = fieldOf(material, "doubleSided");
	if (!isNull(doubleSided)) {
		if (doubleSided.kind != JsonKind.Bool) { return materialError(GltfError.Unsupported); }
		read.material.doubleSided = doubleSided.boolVal;
	}
	const pbr: JsonValue = fieldOf(material, "pbrMetallicRoughness");
	if (isNull(pbr)) { return Result.ok(read); }
	if (pbr.kind != JsonKind.Object) { return materialError(GltfError.Unsupported); }
	const factor: JsonValue = fieldOf(pbr, "baseColorFactor");
	if (!isNull(factor)) {
		if (factor.kind != JsonKind.Array || countOf(factor) != 4) {
			return materialError(GltfError.Unsupported);
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
	if (info.kind != JsonKind.Object) { return materialError(GltfError.Unsupported); }
	if (intField(info, "texCoord", 0) != 0 || !isNull(fieldOf(info, "extensions"))) {
		return materialError(GltfError.UnsupportedMaterial);
	}
	const index: int32 = intField(info, "index", INVALID_INT);
	if (index < 0 || index >= textureCount) { return materialError(GltfError.BadReference); }
	read.material.texture = index;
	return Result.ok(read);
}

export function validateGltfGraph(data: GltfData): Result<int32, GltfError> {
	let states: Vec<int32> = new Array(data.nodes.length as int32);
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

function decodeGltf(
	json: string,
	buffer: Span<uint8>,
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
	if (!isNull(requiredExtensions)
		&& (requiredExtensions.kind != JsonKind.Array || countOf(requiredExtensions) > 0)) {
		return Result.err(GltfError.Unsupported);
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
	for (let i = 0; i < meshCount; i++) {
		const primitive: JsonValue = try primitiveOf(meshArray.at(i));
		const material: int32 = try materialIndexOf(primitive, materialCount);
		const read: MaterialRead = material == DEFAULT_MATERIAL ? DEFAULT_READ : reads[material];
		const mesh: Result<MeshData, GltfError> =
			loadMesh(primitive, read, accessors, views, buffer, declaredLength);
		if (!mesh.ok) { return Result.err(mesh.error); }
		data.meshes.push(mesh.value);
		data.meshMaterials.push(material);
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

export function loadGltf(json: string, buffer: Span<uint8>): Result<GltfData, GltfError> {
	return decodeGltf(json, buffer, false);
}

function uint32At(bytes: Span<uint8>, at: int32): uint32 {
	return (bytes[at] as uint32)
		| ((bytes[at + 1] as uint32) << (8 as uint32))
		| ((bytes[at + 2] as uint32) << (16 as uint32))
		| ((bytes[at + 3] as uint32) << (24 as uint32));
}

// Chunk layout and checks from glTF 2.0.1 §4.4: a JSON chunk first, an optional BIN chunk
// second, every chunk 4-byte aligned, unknown chunks after those two ignored.
export function loadGlb(bytes: Span<uint8>): Result<GltfData, GltfError> {
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
	let binary: Span<uint8> = bytes[0..0];
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
			binary = bytes[start..end];
		} else if (kind == GLB_CHUNK_JSON || kind == GLB_CHUNK_BIN) {
			return Result.err(GltfError.NotGlb);
		}
		at = end;
		chunk = chunk + 1;
	}
	return decodeGltf(json, binary, true);
}
