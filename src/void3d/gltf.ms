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
import {
	vec3, Vec3, Quat, Mat4, identity, identityQuat, linearToSrgb,
	quatOfRotation, determinant3x3, toMatrix, writeTo,
} from "../math/math3d";
import { decodeImage, imageFormatOf, ImageError, ImageFormat, Pixels } from "../assets/image";
import { FilterMode, Wrap } from "../gpu/state";
import {
	GltfAccessorBuffer,
	GltfAccessorError,
	GltfAccessorView,
	GltfAccessorSource,
	GltfAccessorShape,
	GltfAccessorRole,
	GltfSparseSource,
	GltfAccessorValues,
	GltfAccessorIndices,
	fromAccessor as readIndices,
	decode,
} from "./gltfAccessor";
import { GltfColour, GltfColourError, GltfLinearRgba, fromAccessor } from "./gltfColour";
import { GltfCurve, GltfCurvePath, GltfCurveMode, GltfPoseTrack, forValues } from "./gltfCurve";
import { SkinInfluences, fromAccessor as readSkinInfluences } from "./skinInfluences";
import { SkinPartition, fromTriangles } from "./skinPartition";
import { TextureData } from "./texture";
import {
	MeshData,
	MeshError,
	Rgba,
	Uv,
	addVertex,
	addTexturedVertex,
	addTriangle,
	addTangentsWithSources,
	addGivenTangents,
	addSkinAttributes,
	vertexCount,
	indexAt,
	indexCount,
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
	NoImageDecoderOnJs,
}

export struct GltfDiagnostic {
	code: GltfError;
	source: string;
	location: string;
	name: string;
	cause: string;
}

export function describe(this error: Readonly<GltfDiagnostic>): string {
	const named: string = error.name == "" ? "" : ` (${error.name})`;
	return `${error.source}: ${error.code.toString()} at ${error.location}${named}: ${error.cause}`;
}

function gltfCause(code: GltfError): string {
	return match (code) {
		GltfError.BadJson => "JSON could not be parsed",
		GltfError.NotGltf => "glTF 2.0 asset or selected scene is missing or invalid",
		GltfError.Unsupported => "feature, accessor component, shape, or layout is unsupported",
		GltfError.OutOfRange => "buffer range or accessor count exceeds available bytes",
		GltfError.CountMismatch => "attribute counts differ or vertex/index count is incomplete",
		GltfError.MeshTooLarge => "mesh exceeds vertex storage or index draw capacity",
		GltfError.BadIndex => "index >= vertex count or equals component maximum restart value",
		GltfError.BadNode => "node transform is invalid or not representable",
		GltfError.NotGlb => "GLB header or aligned JSON/BIN chunk layout is invalid",
		GltfError.BadReference => "node, mesh, material, texture, or graph reference is invalid",
		GltfError.ImageByUri => "URI image loading is not supported; supply an embedded image",
		GltfError.BadImage => "embedded PNG/JPEG bytes or image dimensions are invalid",
		GltfError.UnsupportedSampler => "sampler filter or wrap is unsupported or incompatible",
		GltfError.UnsupportedMaterial => "material property or texture combination is unsupported",
		GltfError.MissingTexCoord => "textured material requires a valid TEXCOORD_0 attribute",
		GltfError.NoImageDecoderOnJs => "embedded images cannot be decoded on the JS target",
	};
}

function gltfFailure(
	code: GltfError, source: string, location: string, name: string = "", cause: string = "",
): GltfDiagnostic {
	return {
		code: code, source: source, location: location, name: name,
		cause: cause == "" ? gltfCause(code) : cause,
	};
}

function sourceName(value: JsonValue): string {
	const name = fieldOf(value, "name");
	return name.kind == JsonKind.String ? name.strVal : "";
}

const COMPONENT_FLOAT: int32 = 5126;
const COMPONENT_UNSIGNED_BYTE: int32 = 5121;
const COMPONENT_UNSIGNED_SHORT: int32 = 5123;
const COMPONENT_UNSIGNED_INT: int32 = 5125;
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
		|| v.intVal > (2147483647 as int64)) {
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
	skin: int32 | null;
	skinMeshes: Vec<int32>;
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

export struct GltfAnimation {
	name: string;
	tracks: Vec<GltfPoseTrack>;
}

export struct GltfSkin {
	joints: Vec<int32>;
	inverseBindMatrices: Vec<Mat4>;
	skeleton: int32 | null;
}

export struct GltfSkinMesh {
	vertexSources: Vec<int32>;
	mesh: MeshData;
	influences: SkinInfluences;
	partition: SkinPartition;
}

export struct GltfData {
	skins: Vec<GltfSkin>;
	skinMeshes: Vec<GltfSkinMesh | null>;
	meshes: Vec<MeshData>;
	meshMaterials: Vec<int32>;
	materials: Vec<GltfMaterial>;
	textures: Vec<TextureData>;
	nodes: Vec<GltfNode>;
	sceneRoots: Vec<int32>;
	animations: Vec<GltfAnimation>;
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


function animationPath(value: JsonValue): Result<GltfCurvePath, GltfError> {
	if (value.kind != JsonKind.String) { return Result.err(GltfError.Unsupported); }
	return match (value.strVal) {
		"translation" => Result.ok(GltfCurvePath.Translation),
		"rotation" => Result.ok(GltfCurvePath.Rotation),
		"scale" => Result.ok(GltfCurvePath.Scale),
		_ => Result.err(GltfError.Unsupported),
	};
}

function animationMode(value: JsonValue): Result<GltfCurveMode, GltfError> {
	if (isNull(value)) { return Result.ok(GltfCurveMode.Linear); }
	if (value.kind != JsonKind.String) { return Result.err(GltfError.Unsupported); }
	return match (value.strVal) {
		"STEP" => Result.ok(GltfCurveMode.Step),
		"LINEAR" => Result.ok(GltfCurveMode.Linear),
		"CUBICSPLINE" => Result.ok(GltfCurveMode.CubicSpline),
		_ => Result.err(GltfError.Unsupported),
	};
}

function animationValues(
	accessors: JsonValue, views: JsonValue, buffer: Readonly<Span<uint8>>,
	bufferLength: int32, index: int32, components: int32,
	ref buffers: Vec<GltfAccessorBuffer>, ref accessorViews: Vec<GltfAccessorView>,
): Result<Vec<float32>, GltfError> {
	const source = try accessorSource(accessors, index, GltfAccessorRole.Other);
	const shape = components == 1 ? GltfAccessorShape.Scalar :
		(components == 3 ? GltfAccessorShape.Vec3 : GltfAccessorShape.Vec4);
	if (source.componentType != COMPONENT_FLOAT || source.normalized || source.shape != shape ||
		(components == 1 && source.sparse !== null)) {
		return Result.err(GltfError.Unsupported);
	}
	if (buffers.length == 0) {
		accessorViews = try colourAccessorViews(views, bufferLength);
		let bytes: Vec<uint8> = new Array(bufferLength);
		for (let i = 0; i < bufferLength; i++) { bytes[i] = buffer[i]; }
		buffers.push({ bytes: move bytes, byteLength: bufferLength });
	}
	const decoded = GltfAccessorValues.decode(source, buffers, accessorViews);
	if (!decoded.ok) {
		return Result.err(match (decoded.error) {
			GltfAccessorError.Bounds | GltfAccessorError.Count => GltfError.OutOfRange,
			_ => GltfError.Unsupported,
		});
	}
	let values: Vec<float32> = [];
	for (const value of decoded.value.values) { values.push(value as float32); }
	return Result.ok(move values);
}

function loadAnimations(
	root: JsonValue, accessors: JsonValue, views: JsonValue, buffer: Readonly<Span<uint8>>,
	bufferLength: int32, nodeCount: int32,
	ref buffers: Vec<GltfAccessorBuffer>, ref accessorViews: Vec<GltfAccessorView>,
): Result<Vec<GltfAnimation>, GltfError> {
	let clips: Vec<GltfAnimation> = [];
	const animations = arrayOf(root, "animations");
	for (let index = 0; index < countOf(animations); index++) {
		const animation = animations.at(index);
		const channels = arrayOf(animation, "channels");
		const samplers = arrayOf(animation, "samplers");
		const name = fieldOf(animation, "name");
		if (countOf(channels) < 1 || countOf(samplers) < 1 ||
			(!isNull(name) && name.kind != JsonKind.String)) {
			return Result.err(GltfError.Unsupported);
		}
		let clip: GltfAnimation = { name: isNull(name) ? "" : name.asString(), tracks: [] };
		for (let channelIndex = 0; channelIndex < countOf(channels); channelIndex++) {
			const channel = channels.at(channelIndex);
			const target = fieldOf(channel, "target");
			const node: int32 = intField(target, "node", -1);
			const samplerIndex: int32 = intField(channel, "sampler", -1);
			if (node < 0 || node >= nodeCount || samplerIndex < 0 ||
				samplerIndex >= countOf(samplers)) {
				return Result.err(GltfError.BadReference);
			}
			const path = try animationPath(fieldOf(target, "path"));
			if (hasField(arrayOf(root, "nodes").at(node), "matrix")) {
				return Result.err(GltfError.Unsupported);
			}
			for (const previous of clip.tracks) {
				if (previous.sourceNode == node && previous.curve.path == path) {
					return Result.err(GltfError.Unsupported);
				}
			}
			const sampler = samplers.at(samplerIndex);
			const mode = try animationMode(fieldOf(sampler, "interpolation"));
			const times = try animationValues(accessors, views, buffer, bufferLength,
				intField(sampler, "input", -1), 1, buffers, accessorViews);
			const values = try animationValues(accessors, views, buffer, bufferLength,
				intField(sampler, "output", -1), path == GltfCurvePath.Rotation ? 4 : 3,
				buffers, accessorViews);
			const curve = GltfCurve.forValues(path, mode, times, values);
			if (!curve.ok) { return Result.err(GltfError.Unsupported); }
			clip.tracks.push({ sourceNode: node, curve: curve.value });
		}
		clips.push(move clip);
	}
	return Result.ok(move clips);
}

function vec3At(values: Readonly<Span<float64>>, i: int32): Vec3 {
	const at: int32 = i * 3;
	return vec3(values[at] as float32, values[at + 1] as float32, values[at + 2] as float32);
}

function isFiniteVec3(value: Vec3): boolean {
	return value.x - value.x == 0.0
		&& value.y - value.y == 0.0
		&& value.z - value.z == 0.0;
}


function uvAt(values: Readonly<Span<float64>>, i: int32): Uv {
	const at: int32 = i * 2;
	return { u: values[at] as float32, v: values[at + 1] as float32 };
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
		if (data.nodes[i].skin !== null) {
			for (let primitive = 0; primitive < run.count; primitive++) {
				data.nodes[i].skinMeshes.push(run.first + primitive);
			}
			data.nodes[i].mesh = NO_MESH;
			continue;
		}
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
	values: Readonly<Span<float64>>,
	i: int32,
): Result<int32, GltfError> {
	const at: int32 = i * 4;
	const direction: Vec3 = vec3(
		values[at] as float32, values[at + 1] as float32, values[at + 2] as float32,
	);
	const sign: float32 = values[at + 3] as float32;
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

function hasField(obj: JsonValue, key: string): boolean {
	if (obj === null || obj.kind != JsonKind.Object) { return false; }
	for (const name of obj.keys) { if (name == key) { return true; } }
	return false;
}

function colourIntField(obj: JsonValue, key: string, fallback: int32): Result<int32, GltfError> {
	if (!hasField(obj, key)) { return Result.ok(fallback); }
	const value: int32 = intValue(fieldOf(obj, key));
	if (value == INVALID_INT) { return Result.err(GltfError.Unsupported); }
	return Result.ok(value);
}

function colourOptionalInt(obj: JsonValue, key: string): Result<int32 | null, GltfError> {
	if (!hasField(obj, key)) { return Result.ok(null); }
	const value: int32 = try colourIntField(obj, key, 0);
	return Result.ok(value as (int32 | null));
}

function colourAccessorViews(
	views: JsonValue,
	bufferLength: int32,
): Result<Vec<GltfAccessorView>, GltfError> {
	let result: Vec<GltfAccessorView> = [];
	for (let i = 0; i < countOf(views); i++) {
		const view: JsonValue = views.at(i);
		if (view === null || view.kind != JsonKind.Object) {
			return Result.err(GltfError.Unsupported);
		}
		const buffer: int32 = try colourIntField(view, "buffer", -1);
		if (buffer != 0) { return Result.err(GltfError.Unsupported); }
		const offset: int32 = try colourIntField(view, "byteOffset", 0);
		const length: int32 = try colourIntField(view, "byteLength", -1);
		if (offset < 0 || length < 0 || offset > bufferLength || length > bufferLength - offset) {
			return Result.err(GltfError.OutOfRange);
		}
		result.push({
			buffer: buffer, byteOffset: offset, byteLength: length,
			byteStride: try colourOptionalInt(view, "byteStride"),
			target: try colourOptionalInt(view, "target"),
		});
	}
	return Result.ok(move result);
}

function accessorSource(
	accessors: JsonValue,
	index: int32,
	role: GltfAccessorRole = GltfAccessorRole.Attribute,
): Result<GltfAccessorSource, GltfError> {
	if (index < 0 || index >= countOf(accessors)) { return Result.err(GltfError.Unsupported); }
	const accessor: JsonValue = accessors.at(index);
	if (accessor === null || accessor.kind != JsonKind.Object) {
		return Result.err(GltfError.Unsupported);
	}
	const shape: JsonValue = fieldOf(accessor, "type");
	if (shape === null || shape.kind != JsonKind.String
		|| (shape.strVal != "SCALAR" && shape.strVal != "VEC2" && shape.strVal != "VEC3" &&
			shape.strVal != "VEC4" && shape.strVal != "MAT4")) {
		return Result.err(GltfError.Unsupported);
	}
	let normalized: boolean = false;
	if (hasField(accessor, "normalized")) {
		const value: JsonValue = fieldOf(accessor, "normalized");
		if (value === null || value.kind != JsonKind.Bool) {
			return Result.err(GltfError.Unsupported);
		}
		normalized = value.boolVal;
	}
	let sparse: GltfSparseSource | null = null;
	if (hasField(accessor, "sparse")) {
		const value: JsonValue = fieldOf(accessor, "sparse");
		if (value === null || value.kind != JsonKind.Object) {
			return Result.err(GltfError.Unsupported);
		}
		const indices: JsonValue = fieldOf(value, "indices");
		const replacements: JsonValue = fieldOf(value, "values");
		if (indices === null || indices.kind != JsonKind.Object
			|| replacements === null || replacements.kind != JsonKind.Object) {
			return Result.err(GltfError.Unsupported);
		}
		sparse = {
			count: try colourIntField(value, "count", -1),
			indicesView: try colourIntField(indices, "bufferView", -1),
			indicesByteOffset: try colourIntField(indices, "byteOffset", 0),
			indicesComponentType: try colourIntField(indices, "componentType", -1),
			valuesView: try colourIntField(replacements, "bufferView", -1),
			valuesByteOffset: try colourIntField(replacements, "byteOffset", 0),
		};
	}
	return Result.ok({
		bufferView: try colourOptionalInt(accessor, "bufferView"),
		byteOffset: try colourOptionalInt(accessor, "byteOffset"),
		componentType: try colourIntField(accessor, "componentType", -1),
		shape: match (shape.strVal) {
			"SCALAR" => GltfAccessorShape.Scalar,
			"VEC2" => GltfAccessorShape.Vec2,
			"VEC3" => GltfAccessorShape.Vec3,
			"VEC4" => GltfAccessorShape.Vec4,
			_ => GltfAccessorShape.Mat4,
		},
		normalized: normalized, count: try colourIntField(accessor, "count", -1),
		role: role, sparse: sparse,
	});
}

function loadSkins(
	root: JsonValue,
	accessors: JsonValue,
	views: JsonValue,
	buffer: Readonly<Span<uint8>>,
	bufferLength: int32,
	nodeCount: int32,
	ref buffers: Vec<GltfAccessorBuffer>,
	ref accessorViews: Vec<GltfAccessorView>,
	source: string,
): Result<Vec<GltfSkin>, GltfDiagnostic> {
	const skins = arrayOf(root, "skins");
	let result: Vec<GltfSkin> = [];
	if (countOf(skins) == 0) { return Result.ok(move result); }
	let seen: Vec<int32> = [];
	for (let node = 0; node < nodeCount; node++) { seen.push(-1); }
	for (let index = 0; index < countOf(skins); index++) {
		const value = skins.at(index);
		const location: string = `$.skins[${index}]`;
		const name: string = sourceName(value);
		const joints = arrayOf(value, "joints");
		if (countOf(joints) < 1) {
			return Result.err(gltfFailure(GltfError.Unsupported, source, location + ".joints",
				name, "skin requires a nonempty joints array"));
		}
		const skeletonRead = colourOptionalInt(value, "skeleton");
		if (!skeletonRead.ok) {
			return Result.err(gltfFailure(skeletonRead.error, source, location + ".skeleton",
				name, "skeleton must be a node index"));
		}
		let skin: GltfSkin = {
			joints: [], inverseBindMatrices: [], skeleton: skeletonRead.value,
		};
		const skeleton = skin.skeleton;
		if (skeleton !== null && (skeleton < 0 || skeleton >= nodeCount)) {
			return Result.err(gltfFailure(GltfError.BadNode, source, location + ".skeleton",
				name, "skeleton references a missing node"));
		}
		for (let slot = 0; slot < countOf(joints); slot++) {
			const node: int32 = intValue(joints.at(slot));
			if (node < 0 || node >= nodeCount || seen[node] == index) {
				return Result.err(gltfFailure(GltfError.BadNode, source,
					location + `.joints[${slot}]`, name, "joint node is missing or duplicated"));
			}
			seen[node] = index;
			skin.joints.push(node);
		}
		if (!hasField(value, "inverseBindMatrices")) {
			for (let joint = 0; joint < skin.joints.length; joint++) {
				skin.inverseBindMatrices.push(identity());
			}
		} else {
			const matrixLocation: string = location + ".inverseBindMatrices";
			const indexRead = colourIntField(value, "inverseBindMatrices", -1);
			if (!indexRead.ok) {
				return Result.err(gltfFailure(indexRead.error, source, matrixLocation, name));
			}
			const matrixRead = accessorSource(accessors, indexRead.value, GltfAccessorRole.Other);
			if (!matrixRead.ok) {
				return Result.err(gltfFailure(matrixRead.error, source, matrixLocation, name,
					"inverse bind matrices reference an invalid accessor"));
			}
			const matrices = matrixRead.value;
			if (matrices.shape != GltfAccessorShape.Mat4
				|| matrices.componentType != COMPONENT_FLOAT || matrices.normalized
				|| matrices.count < skin.joints.length) {
				return Result.err(gltfFailure(GltfError.Unsupported, source, matrixLocation, name,
					"inverse bind accessor must be float MAT4 with at least one row per joint"));
			}
			if (buffers.length == 0) {
				const decodedViews = colourAccessorViews(views, bufferLength);
				if (!decodedViews.ok) {
					return Result.err(gltfFailure(decodedViews.error, source,
						matrixLocation, name, "inverse bind buffer views are invalid"));
				}
				accessorViews = move decodedViews.value;
				let bytes: Vec<uint8> = new Array(bufferLength);
				for (let i = 0; i < bufferLength; i++) { bytes[i] = buffer[i]; }
				buffers.push({ bytes: move bytes, byteLength: bufferLength });
			}
			const decoded = GltfAccessorValues.decode(matrices, buffers, accessorViews);
			if (!decoded.ok) {
				return Result.err(gltfFailure(GltfError.Unsupported, source, matrixLocation,
					name, "inverse bind accessor: " + decoded.error.toString()));
			}
			const values = decoded.value.values;
			for (let joint = 0; joint < matrices.count; joint++) {
				const at: int32 = joint * 16;
				if (values[at + 3] != 0 || values[at + 7] != 0 || values[at + 11] != 0
					|| values[at + 15] != 1) {
					return Result.err(gltfFailure(GltfError.Unsupported, source, matrixLocation,
						name, `inverse bind matrix ${joint} must have affine row [0,0,0,1]`));
				}
				if (joint >= skin.joints.length) { continue; }
				skin.inverseBindMatrices.push({
					m11: values[at] as float32, m12: values[at + 1] as float32,
					m13: values[at + 2] as float32, m14: values[at + 3] as float32,
					m21: values[at + 4] as float32, m22: values[at + 5] as float32,
					m23: values[at + 6] as float32, m24: values[at + 7] as float32,
					m31: values[at + 8] as float32, m32: values[at + 9] as float32,
					m33: values[at + 10] as float32, m34: values[at + 11] as float32,
					m41: values[at + 12] as float32, m42: values[at + 13] as float32,
					m43: values[at + 14] as float32, m44: values[at + 15] as float32,
				});
			}
		}
		result.push(move skin);
	}
	return Result.ok(move result);
}

function loadSkinMesh(
	primitive: JsonValue,
	source: MeshData,
	tangentSources: Readonly<Span<int32>>,
	accessors: JsonValue,
	views: JsonValue,
	buffer: Readonly<Span<uint8>>,
	bufferLength: int32,
	ref buffers: Vec<GltfAccessorBuffer>,
	ref accessorViews: Vec<GltfAccessorView>,
): Result<GltfSkinMesh | null, GltfError> {
	const attributes = fieldOf(primitive, "attributes");
	if (attributes === null || attributes.kind != JsonKind.Object) {
		return Result.err(GltfError.Unsupported);
	}
	const hasJoints: boolean = hasField(attributes, "JOINTS_0");
	const hasWeights: boolean = hasField(attributes, "WEIGHTS_0");
	if (!hasJoints && !hasWeights) { return Result.ok(null); }
	if (!hasJoints || !hasWeights) { return Result.err(GltfError.Unsupported); }
	for (const name of attributes.keys) {
		if ((name.startsWith("JOINTS_") && name != "JOINTS_0")
			|| (name.startsWith("WEIGHTS_") && name != "WEIGHTS_0")) {
			return Result.err(GltfError.Unsupported);
		}
	}
	const joints = try accessorSource(accessors, try colourIntField(attributes, "JOINTS_0", -1));
	const weights = try accessorSource(accessors, try colourIntField(attributes, "WEIGHTS_0", -1));
	const original: int32 = source.vertexCount() - tangentSources.length as int32;
	if (joints.count != original || weights.count != original) {
		return Result.err(GltfError.CountMismatch);
	}
	if (buffers.length == 0) {
		accessorViews = try colourAccessorViews(views, bufferLength);
		let bytes: Vec<uint8> = new Array(bufferLength);
		for (let i = 0; i < bufferLength; i++) { bytes[i] = buffer[i]; }
		buffers.push({ bytes: move bytes, byteLength: bufferLength });
	}
	const read = SkinInfluences.readSkinInfluences(joints, weights, buffers, accessorViews, 65536);
	if (!read.ok) { return Result.err(GltfError.Unsupported); }
	let canonical: SkinInfluences = read.value;
	let vertexSources: Vec<int32> = [];
	for (let vertex = 0; vertex < original; vertex++) { vertexSources.push(vertex); }
	for (const vertex of tangentSources) {
		if (vertex < 0 || vertex >= original) { return Result.err(GltfError.OutOfRange); }
		vertexSources.push(vertex);
		for (let slot = 0; slot < 4; slot++) {
			canonical.joints.push(canonical.joints[vertex * 4 + slot]);
			canonical.weights.push(canonical.weights[vertex * 4 + slot]);
		}
	}
	let jointCount: int32 = 1;
	for (const joint of canonical.joints) {
		if (joint >= jointCount) { jointCount = joint + 1; }
	}
	let topology: MeshData = source;
	if (topology.indexCount() == 0) {
		for (let corner = 0; corner < topology.vertexCount(); corner += 3) {
			const added = addTriangle(topology, corner, corner + 1, corner + 2);
			if (!added.ok) { return Result.err(GltfError.BadIndex); }
		}
	}
	const split = topology.wideIndices === null
		? SkinPartition.fromTriangles(canonical.joints, canonical.weights,
			topology.indices, jointCount)
		: SkinPartition.fromTriangles(canonical.joints, canonical.weights,
			topology.indices, jointCount, [], topology.wideIndices);
	if (!split.ok) { return Result.err(GltfError.Unsupported); }
	let mesh: MeshData = topology;
	mesh.indices = [];
	if (mesh.wideIndices !== null) { mesh.wideIndices = []; }
	for (const part of split.value.parts) {
		for (const triangle of part.triangles) {
			const corner: int32 = triangle * 3;
			const added = addTriangle(mesh, topology.indexAt(corner) as int32,
				topology.indexAt(corner + 1) as int32, topology.indexAt(corner + 2) as int32);
			if (!added.ok) { return Result.err(GltfError.BadIndex); }
		}
	}
	const added = addSkinAttributes(mesh, split.value.remappedJoints, canonical.weights);
	if (!added.ok) { return Result.err(GltfError.Unsupported); }
	const skin: GltfSkinMesh = {
		vertexSources: move vertexSources,
		mesh: mesh, influences: canonical, partition: split.value,
	};
	return Result.ok(skin as (GltfSkinMesh | null));
}

function geometryAttribute(
	this source: GltfAccessorSource,
	shape: GltfAccessorShape,
	count: int32,
	views: JsonValue,
	buffer: Readonly<Span<uint8>>,
	bufferLength: int32,
	ref buffers: Vec<GltfAccessorBuffer>,
	ref accessorViews: Vec<GltfAccessorView>,
): Result<GltfAccessorValues, GltfError> {
	const floats = source.componentType == COMPONENT_FLOAT && !source.normalized;
	const normalizedUvs = shape == GltfAccessorShape.Vec2 && source.normalized &&
		(source.componentType == COMPONENT_UNSIGNED_BYTE ||
			source.componentType == COMPONENT_UNSIGNED_SHORT);
	if (source.shape != shape || (!floats && !normalizedUvs)) {
		return Result.err(GltfError.Unsupported);
	}
	if (source.count < 1) { return Result.err(GltfError.OutOfRange); }
	if (source.count != count) { return Result.err(GltfError.CountMismatch); }
	const dense = source.bufferView;
	if (dense !== null && (dense < 0 || dense >= countOf(views))) {
		return Result.err(GltfError.Unsupported);
	}
	if (buffers.length == 0) {
		accessorViews = try colourAccessorViews(views, bufferLength);
		let bytes: Vec<uint8> = new Array(bufferLength);
		for (let i = 0; i < bufferLength; i++) { bytes[i] = buffer[i]; }
		buffers.push({ bytes: move bytes, byteLength: bufferLength });
	}
	let decoded = GltfAccessorValues.decode(source, buffers, accessorViews);
	if (!decoded.ok) {
		return Result.err(match (decoded.error) {
			GltfAccessorError.Bounds | GltfAccessorError.NonFinite | GltfAccessorError.Count =>
				GltfError.OutOfRange,
			_ => GltfError.Unsupported,
		});
	}
	return Result.ok(move decoded.value);
}

function loadMesh(
	primitive: JsonValue,
	read: MaterialRead,
	accessors: JsonValue,
	views: JsonValue,
	buffer: Readonly<Span<uint8>>,
	bufferLength: int32,
	ref colourBuffers: Vec<GltfAccessorBuffer>,
	ref colourViews: Vec<GltfAccessorView>,
	ref tangentSources: Vec<int32>,
): Result<MeshData, GltfError> {
	if (!isNull(fieldOf(primitive, "targets"))) {
		return Result.err(GltfError.Unsupported);
	}
	const mode: int32 = try colourIntField(primitive, "mode", 4);
	const strip: boolean = mode == 5;
	if (mode != 4 && !strip) {
		return Result.err(GltfError.Unsupported);
	}
	const attributes: JsonValue = fieldOf(primitive, "attributes");
	if (isNull(attributes)) { return Result.err(GltfError.Unsupported); }
	const positionSource = try accessorSource(accessors,
		try colourIntField(attributes, "POSITION", -1));
	const count = positionSource.count;
	if (count < 1) { return Result.err(GltfError.OutOfRange); }
	const textured: boolean = read.material.texture != NO_TEXTURE_INDEX;
	let data: MeshData = textured ? MeshData.withUvs() : MeshData.empty();
	if (!data.hasRoomFor(count)) { return Result.err(GltfError.MeshTooLarge); }
	const positions = try positionSource.geometryAttribute(GltfAccessorShape.Vec3, count,
		views, buffer, bufferLength, colourBuffers, colourViews);
	const normalSource = try accessorSource(accessors,
		try colourIntField(attributes, "NORMAL", -1));
	const normals = try normalSource.geometryAttribute(GltfAccessorShape.Vec3, count,
		views, buffer, bufferLength, colourBuffers, colourViews);
	let colors: Vec<GltfLinearRgba> = [];
	if (hasField(attributes, "COLOR_0")) {
		const source: GltfAccessorSource = try accessorSource(accessors,
			try colourIntField(attributes, "COLOR_0", -1));
		if (source.count < 1) { return Result.err(GltfError.OutOfRange); }
		const denseView = source.bufferView;
		if (denseView !== null && (denseView < 0 || denseView >= countOf(views))) {
			return Result.err(GltfError.Unsupported);
		}
		const decoded = GltfColour.fromAccessor(source, colourBuffers, colourViews, count);
		if (!decoded.ok) {
			if (decoded.error == GltfColourError.Count) {
				return Result.err(GltfError.CountMismatch);
			}
			if (decoded.error == GltfColourError.Bounds ||
				decoded.error == GltfColourError.NonFinite) {
				return Result.err(GltfError.OutOfRange);
			}
			return Result.err(GltfError.Unsupported);
		}
		colors = decoded.value.values;
	}
	let uvValues: Vec<float64> = [];
	if (read.realUvs) {
		if (isNull(fieldOf(attributes, "TEXCOORD_0"))) {
			return Result.err(GltfError.MissingTexCoord);
		}
		const source = try accessorSource(accessors,
			try colourIntField(attributes, "TEXCOORD_0", -1));
		let decoded = try source.geometryAttribute(GltfAccessorShape.Vec2, count,
			views, buffer, bufferLength, colourBuffers, colourViews);
		uvValues = move decoded.values;
	}
	const tangented: boolean = read.material.normalTexture != NO_TEXTURE_INDEX;
	let tangentValues: Vec<float64> = [];
	if (tangented && !isNull(fieldOf(attributes, "TANGENT"))) {
		const source = try accessorSource(accessors,
			try colourIntField(attributes, "TANGENT", -1));
		let decoded = try source.geometryAttribute(GltfAccessorShape.Vec4, count,
			views, buffer, bufferLength, colourBuffers, colourViews);
		tangentValues = move decoded.values;
	}
	let tangents: Vec<float32> = [];
	for (let i = 0; i < count; i++) {
		const position: Vec3 = vec3At(positions.values, i);
		const normal: Vec3 = vec3At(normals.values, i);
		const rgba: GltfLinearRgba = colors.length > 0
			? colors[i] : { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };
		if (!isFiniteVec3(position) || !isFiniteVec3(normal)) {
			return Result.err(GltfError.OutOfRange);
		}
		const uv: Uv = read.realUvs ? uvAt(uvValues, i) : { u: 0.0, v: 0.0 };
		if (uv.u - uv.u != 0.0 || uv.v - uv.v != 0.0) {
			return Result.err(GltfError.OutOfRange);
		}
		const normalLength: float32 =
			normal.x * normal.x + normal.y * normal.y + normal.z * normal.z;
		if (normalLength < 0.999 || normalLength > 1.001) {
			return Result.err(GltfError.Unsupported);
		}
		// glTF's COLOR_0 and baseColorFactor are linear; the API's colours are gamma-encoded.
		const color: Rgba = {
			red: linearToSrgb(rgba.red * read.factor.red),
			green: linearToSrgb(rgba.green * read.factor.green),
			blue: linearToSrgb(rgba.blue * read.factor.blue),
			alpha: read.material.alphaMode == GltfAlphaMode.Opaque
				? 1.0
				: rgba.alpha * read.factor.alpha,
		};
		const added: Result<int32, MeshError> = textured
			? addTexturedVertex(data, position, normal, uv, color)
			: addVertex(data, position, normal, color);
		if (!added.ok) { return Result.err(GltfError.MeshTooLarge); }
		if (tangentValues.length > 0) {
			const tangent: Result<int32, GltfError> = pushTangent(tangents, tangentValues, i);
			if (!tangent.ok) { return Result.err(tangent.error); }
		}
	}
	if (!hasField(primitive, "indices")) {
		if (strip ? count < 3 : count % 3 != 0) { return Result.err(GltfError.CountMismatch); }
		if (strip) {
			for (let t = 0; t < count - 2; t++) {
				const odd: int32 = t % 2;
				const tri = addTriangle(data, t + odd, t + 1 - odd, t + 2);
				if (!tri.ok) { return Result.err(GltfError.BadIndex); }
			}
		}
	} else {
		const source = try accessorSource(accessors,
			try colourIntField(primitive, "indices", -1), GltfAccessorRole.Indices);
		if (strip && source.count > 0x7fffffff / 3 + 2) {
			return Result.err(GltfError.MeshTooLarge);
		}
		const indices = GltfAccessorIndices.readIndices(source, colourBuffers, colourViews,
			count as uint32);
		if (!indices.ok) {
			return Result.err(match (indices.error) {
				GltfAccessorError.Index => GltfError.BadIndex,
				GltfAccessorError.Bounds | GltfAccessorError.Count | GltfAccessorError.NonFinite =>
					GltfError.OutOfRange,
				_ => GltfError.Unsupported,
			});
		}
		const corners: int32 = indices.value.values.length as int32;
		if (strip ? corners < 3 : corners % 3 != 0) {
			return Result.err(GltfError.CountMismatch);
		}
		if (source.componentType == COMPONENT_UNSIGNED_INT) { data.wideIndices = []; }
		const step: int32 = strip ? 1 : 3;
		for (let t = 0; t < corners - 2; t += step) {
			const odd: int32 = strip ? t % 2 : 0;
			const tri = addTriangle(data, indices.value.values[t + odd] as int32,
				indices.value.values[t + 1 - odd] as int32, indices.value.values[t + 2] as int32);
			if (!tri.ok) { return Result.err(GltfError.BadIndex); }
		}
	}
	if (tangented) {
		const closed: Result<int32, MeshError> =
			tangentValues.length > 0 ? addGivenTangents(data, tangents) :
				addTangentsWithSources(data, tangentSources);
		if (!closed.ok) { return Result.err(GltfError.Unsupported); }
	}
	return Result.ok(data);
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

const MATRIX_ROUNDTRIP_TOLERANCE: float32 = 0.00001;

function matrixTransform(value: JsonValue): Result<GltfTransform, GltfError> {
	if (value === null || value.kind != JsonKind.Array || countOf(value) != 16) {
		return Result.err(GltfError.Unsupported);
	}
	let values: Vec<float32> = [];
	for (let i = 0; i < 16; i++) { values.push(try numberAt(value, i)); }
	if (values[3] != 0 || values[7] != 0 || values[11] != 0 || values[15] != 1) {
		return Result.err(GltfError.Unsupported);
	}
	let scales: Vec<float32> = [];
	for (let axis = 0; axis < 3; axis++) {
		let squared: float64 = 0;
		for (let component = 0; component < 3; component++) {
			const element: float64 = values[axis * 4 + component] as float64;
			squared += element * element;
		}
		const scale: float32 = Math.sqrt(squared) as float32;
		if (!Number.isFinite(scale) || scale <= 0) {
			return Result.err(GltfError.Unsupported);
		}
		scales.push(scale);
		for (let component = 0; component < 3; component++) {
			const at: int32 = axis * 4 + component;
			values[at] /= scale;
		}
	}
	const scaleProduct: float32 = scales[0] * scales[1] * scales[2];
	if (!Number.isFinite(scaleProduct) || scaleProduct <= 1e-10) {
		return Result.err(GltfError.Unsupported);
	}
	const axes: Mat4 = {
		m11: values[0], m12: values[1], m13: values[2], m14: 0,
		m21: values[4], m22: values[5], m23: values[6], m24: 0,
		m31: values[8], m32: values[9], m33: values[10], m34: 0,
		m41: 0, m42: 0, m43: 0, m44: 1,
	};
	if (axes.determinant3x3() <= 0) { return Result.err(GltfError.Unsupported); }
	const rotation = quatOfRotation(axes);
	let rebuilt: Vec<float32> = new Array(16);
	rotation.toMatrix().writeTo(rebuilt, 0);
	for (let i = 0; i < 12; i++) {
		if (!Number.isFinite(rebuilt[i]) ||
			Math.abs(rebuilt[i] - values[i]) > MATRIX_ROUNDTRIP_TOLERANCE) {
			return Result.err(GltfError.Unsupported);
		}
	}
	return Result.ok({
		position: vec3(values[12], values[13], values[14]),
		rotation: rotation, scale: vec3(scales[0], scales[1], scales[2]),
	});
}

function loadNode(node: JsonValue): Result<GltfNode, GltfError> {
	if (node === null || node.kind != JsonKind.Object) {
		return Result.err(GltfError.Unsupported);
	}
	if (!isNull(fieldOf(node, "weights"))) { return Result.err(GltfError.Unsupported); }
	const hasMatrix: boolean = hasField(node, "matrix");
	if (hasMatrix && (hasField(node, "translation") || hasField(node, "rotation") ||
		hasField(node, "scale"))) {
		return Result.err(GltfError.Unsupported);
	}
	let local: GltfTransform = {
		position: vec3(0.0, 0.0, 0.0),
		rotation: identityQuat(),
		scale: vec3(1.0, 1.0, 1.0),
	};
	if (hasMatrix) { local = try matrixTransform(fieldOf(node, "matrix")); }
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
		skin: try colourOptionalInt(node, "skin"), skinMeshes: [],
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
	if (!decoded.ok) {
		if (decoded.error == ImageError.NoDecoderOnJs) { return Result.err(GltfError.NoImageDecoderOnJs); }
		return Result.err(GltfError.BadImage);
	}
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
	const base: int32 = hasField(info, "texCoord") ? intValue(fieldOf(info, "texCoord")) : 0;
	const transform: JsonValue = fieldOf(fieldOf(info, "extensions"), "KHR_texture_transform");
	const effective: int32 = hasField(transform, "texCoord")
		? intValue(fieldOf(transform, "texCoord")) : base;
	if (base < 0 || effective != 0) { return Result.err(GltfError.UnsupportedMaterial); }
	const index: int32 = intField(info, "index", INVALID_INT);
	if (index < 0 || index >= textureCount) { return Result.err(GltfError.BadReference); }
	return Result.ok(index);
}

// A textureInfo's KHR_texture_transform, the only extension a texture reference may carry here.
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
	if (!hasField(material, "extensions")) { return Result.ok(1.0); }
	const extensions: JsonValue = fieldOf(material, "extensions");
	if (extensions.kind != JsonKind.Object) { return Result.err(GltfError.Unsupported); }
	if (!hasField(extensions, "KHR_materials_emissive_strength")) { return Result.ok(1.0); }
	const extension: JsonValue = fieldOf(extensions, "KHR_materials_emissive_strength");
	if (extension.kind != JsonKind.Object) { return Result.err(GltfError.Unsupported); }
	if (!hasField(extension, "emissiveStrength")) { return Result.ok(1.0); }
	const strength: JsonValue = fieldOf(extension, "emissiveStrength");
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
	const skinned: boolean = data.skins.length > 0;
	let parents: Vec<int32> = [];
	let roots: Vec<int32> = [];
	if (skinned) {
		for (let i = 0; i < data.nodes.length; i++) { parents.push(-1); roots.push(-1); }
	}
	let stack: Vec<int32> = [];
	for (let i = (data.sceneRoots.length as int32) - 1; i >= 0; i--) {
		const root: int32 = data.sceneRoots[i];
		if (root < 0 || root >= data.nodes.length) { return Result.err(GltfError.BadNode); }
		if (skinned) { roots[root] = root; }
		stack.push(root);
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
			const child: int32 = data.nodes[index].children[i];
			if (child < 0 || child >= data.nodes.length) { return Result.err(GltfError.BadNode); }
			if (skinned) {
				parents[child] = index;
				roots[child] = roots[index];
			}
			stack.push(child);
		}
	}
	for (let node = 0; node < data.nodes.length; node++) {
		const skinIndex = data.nodes[node].skin;
		if (states[node] == 0 || skinIndex === null) { continue; }
		if (skinIndex < 0 || skinIndex >= data.skins.length
			|| data.nodes[node].skinMeshes.length < 1) { return Result.err(GltfError.BadNode); }
		const skin = data.skins[skinIndex];
		if (skin.joints.length < 1 || skin.inverseBindMatrices.length != skin.joints.length) {
			return Result.err(GltfError.BadNode);
		}
		let commonRoot: int32 = -1;
		const skeleton = skin.skeleton;
		for (const joint of skin.joints) {
			if (joint < 0 || joint >= states.length || states[joint] == 0) {
				return Result.err(GltfError.BadNode);
			}
			if (commonRoot < 0) { commonRoot = roots[joint]; }
			if (roots[joint] != commonRoot) { return Result.err(GltfError.BadNode); }
			if (skeleton !== null) {
				let ancestor: int32 = joint;
				while (ancestor >= 0 && ancestor != skeleton) { ancestor = parents[ancestor]; }
				if (ancestor < 0) { return Result.err(GltfError.BadNode); }
			}
		}
		for (const mesh of data.nodes[node].skinMeshes) {
			if (mesh < 0 || mesh >= data.skinMeshes.length) {
				return Result.err(GltfError.BadNode);
			}
			const input = data.skinMeshes[mesh];
			if (input === null) { return Result.err(GltfError.BadNode); }
			if (input.influences.joints.length != input.mesh.vertexCount() * 4
				|| input.influences.weights.length != input.influences.joints.length) {
				return Result.err(GltfError.BadNode);
			}
			for (const joint of input.influences.joints) {
				if (joint < 0 || joint >= skin.joints.length) {
					return Result.err(GltfError.BadNode);
				}
			}
		}
	}
	return Result.ok(count);
}

function validateAttributeStrides(
	meshes: JsonValue,
	accessors: JsonValue,
	views: JsonValue,
	source: string,
): Result<void, GltfDiagnostic> {
	let owners: Vec<int32> = [];
	for (let view = 0; view < countOf(views); view++) { owners.push(-1); }
	for (let mesh = 0; mesh < countOf(meshes); mesh++) {
		const primitives = arrayOf(meshes.at(mesh), "primitives");
		for (let primitive = 0; primitive < countOf(primitives); primitive++) {
			const attributes = fieldOf(primitives.at(primitive), "attributes");
			if (attributes === null || attributes.kind != JsonKind.Object) { continue; }
			for (let attribute = 0; attribute < (attributes.values.length as int32); attribute++) {
				const accessor: int32 = intValue(attributes.values[attribute]);
				if (accessor < 0 || accessor >= countOf(accessors)) {
					return Result.err(gltfFailure(GltfError.Unsupported, source,
						`$.meshes[${mesh}].primitives[${primitive}].attributes.` +
						attributes.keys[attribute], sourceName(meshes.at(mesh)),
						"attribute accessor reference is invalid"));
				}
				const view: int32 = intField(accessors.at(accessor), "bufferView", -1);
				if (view < 0) { continue; }
				if (view >= countOf(views)) {
					return Result.err(gltfFailure(GltfError.Unsupported, source,
						`$.accessors[${accessor}].bufferView`, sourceName(meshes.at(mesh)),
						"attribute references a missing bufferView"));
				}
				if (intField(views.at(view), "byteStride", 0) > 0) { continue; }
				if (owners[view] >= 0 && owners[view] != accessor) {
					return Result.err(gltfFailure(GltfError.Unsupported, source,
						`$.meshes[${mesh}].primitives[${primitive}].attributes.` +
						attributes.keys[attribute], sourceName(meshes.at(mesh)),
						`accessors[${accessor}] shares bufferViews[${view}] with ` +
						`accessors[${owners[view]}] without byteStride`));
				}
				owners[view] = accessor;
			}
		}
	}
	return Result.ok(null);
}

function decodeGltf(
	json: string,
	buffer: Readonly<Span<uint8>>,
	fromGlb: boolean,
	source: string = "<memory>",
): Result<GltfData, GltfDiagnostic> {
	const parsed: Result<JsonValue, string> = parseJson(json);
	if (!parsed.ok) {
		return Result.err(gltfFailure(GltfError.BadJson, source, "$", "", parsed.error));
	}
	const root: JsonValue = parsed.value;
	const asset: JsonValue = fieldOf(root, "asset");
	if (isNull(asset)) { return Result.err(gltfFailure(GltfError.NotGltf, source, "$.asset")); }
	const versionField: JsonValue = fieldOf(asset, "version");
	const version: string = versionField.asString();
	if (version != "2.0") {
		return Result.err(gltfFailure(GltfError.NotGltf, source, "$.asset.version"));
	}
	const requiredExtensions: JsonValue = fieldOf(root, "extensionsRequired");
	if (!isNull(requiredExtensions)) {
		if (requiredExtensions.kind != JsonKind.Array) {
			return Result.err(gltfFailure(GltfError.Unsupported, source, "$.extensionsRequired"));
		}
		for (let i = 0; i < countOf(requiredExtensions); i++) {
			const name: JsonValue = at(requiredExtensions, i);
			if (name.kind != JsonKind.String || (name.strVal != "KHR_texture_transform"
				&& name.strVal != "KHR_materials_emissive_strength")) {
				return Result.err(gltfFailure(GltfError.Unsupported, source,
					`$.extensionsRequired[${i}]`, name.asString()));
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
		|| !isArrayOrAbsent(root, "materials")
		|| !isArrayOrAbsent(root, "animations")
		|| !isArrayOrAbsent(root, "skins")) {
		return Result.err(gltfFailure(GltfError.Unsupported, source, "$", "",
			"accessors, views, meshes, nodes, buffers, images, samplers, textures, " +
			"materials, animations and skins must be arrays when present"));
	}
	const accessors: JsonValue = arrayOf(root, "accessors");
	const views: JsonValue = arrayOf(root, "bufferViews");
	let data: GltfData = {
		skins: [], skinMeshes: [],
		meshes: [],
		meshMaterials: [],
		materials: [],
		textures: [],
		nodes: [],
		sceneRoots: [],
		animations: [],
	};
	const meshArray: JsonValue = arrayOf(root, "meshes");
	const strides = validateAttributeStrides(meshArray, accessors, views, source);
	if (!strides.ok) { return Result.err(strides.error); }
	const meshCount: int32 = countOf(meshArray);
	const imageArray: JsonValue = arrayOf(root, "images");
	const imageCount: int32 = countOf(imageArray);
	const buffers: JsonValue = arrayOf(root, "buffers");
	const bufferCount: int32 = countOf(buffers);
	if (bufferCount > 1 || ((meshCount > 0 || imageCount > 0) && bufferCount != 1)) {
		return Result.err(gltfFailure(GltfError.Unsupported, source, "$.buffers", "",
			"this loader requires one supplied buffer for meshes or images"));
	}
	let declaredLength: int32 = 0;
	if (bufferCount == 1) {
		const bufferInfo: JsonValue = at(buffers, 0);
		if (fromGlb && !isNull(fieldOf(bufferInfo, "uri"))) {
			return Result.err(gltfFailure(GltfError.Unsupported, source, "$.buffers[0].uri"));
		}
		declaredLength = intField(bufferInfo, "byteLength", -1);
		const actualLength: int32 = buffer.length as int32;
		if (declaredLength < 0 || declaredLength > actualLength) {
			return Result.err(gltfFailure(GltfError.OutOfRange, source, "$.buffers[0].byteLength"));
		}
	}
	const samplerArray: JsonValue = arrayOf(root, "samplers");
	let samplers: Vec<Sampling> = [];
	for (let i = 0; i < countOf(samplerArray); i++) {
		const sampler = loadSampler(samplerArray.at(i));
		if (!sampler.ok) {
			return Result.err(gltfFailure(sampler.error, source, `$.samplers[${i}]`,
				sourceName(samplerArray.at(i))));
		}
		samplers.push(sampler.value);
	}
	let images: Vec<ImageView> = [];
	for (let i = 0; i < imageCount; i++) {
		const image = loadImageView(imageArray.at(i), views, declaredLength);
		if (!image.ok) {
			return Result.err(gltfFailure(image.error, source, `$.images[${i}]`,
				sourceName(imageArray.at(i))));
		}
		images.push(image.value);
	}
	const textureArray: JsonValue = arrayOf(root, "textures");
	const textureCount: int32 = countOf(textureArray);
	for (let i = 0; i < textureCount; i++) {
		let texture = loadTexture(textureArray.at(i), images, samplers, buffer);
		if (!texture.ok) {
			return Result.err(gltfFailure(texture.error, source, `$.textures[${i}]`,
				sourceName(textureArray.at(i))));
		}
		data.textures.push(move texture.value);
	}
	const materialArray: JsonValue = arrayOf(root, "materials");
	const materialCount: int32 = countOf(materialArray);
	let reads: Vec<MaterialRead> = [];
	for (let i = 0; i < materialCount; i++) {
		const material = loadMaterial(materialArray.at(i), textureCount);
		if (!material.ok) {
			return Result.err(gltfFailure(material.error, source, `$.materials[${i}]`,
				sourceName(materialArray.at(i))));
		}
		reads.push(material.value);
		data.materials.push(material.value.material);
	}
	for (let i = 0; i < textureCount; i++) {
		const alpha = keepsAlpha(data.materials, i);
		if (!alpha.ok) {
			return Result.err(gltfFailure(alpha.error, source, `$.textures[${i}]`));
		}
		if (!alpha.value) { forceOpaque(data.textures[i].pixels); }
	}
	const whites = substituteWhites(data, reads);
	if (!whites.ok) { return Result.err(gltfFailure(whites.error, source, "$.materials")); }
	let colourBuffers: Vec<GltfAccessorBuffer> = [];
	let colourViews: Vec<GltfAccessorView> = [];
	let runs: Vec<PrimitiveRun> = [];
	let usedNames: Vec<string> = [];
	let usedCounts: Vec<int32> = [];
	for (let i = 0; i < meshCount; i++) {
		const primitiveRead = primitivesOf(meshArray.at(i));
		if (!primitiveRead.ok) {
			return Result.err(gltfFailure(primitiveRead.error, source, `$.meshes[${i}]`,
				sourceName(meshArray.at(i))));
		}
		const primitives: JsonValue = primitiveRead.value;
		const nameField: JsonValue = fieldOf(meshArray.at(i), "name");
		if (!isNull(nameField) && nameField.kind != JsonKind.String) {
			return Result.err(gltfFailure(GltfError.Unsupported, source, `$.meshes[${i}].name`));
		}
		const base: string = isNull(nameField) ? `mesh_${i}` : nameField.asString();
		let names: Vec<string> = [];
		for (let p = 0; p < countOf(primitives); p++) {
			names.push(uniqueName(usedNames, usedCounts, base));
		}
		runs.push({ names: names, first: data.meshes.length as int32, count: countOf(primitives) });
		for (let p = 0; p < countOf(primitives); p++) {
			const primitive: JsonValue = primitives.at(p);
			const materialRead = materialIndexOf(primitive, materialCount);
			if (!materialRead.ok) {
				return Result.err(gltfFailure(materialRead.error, source,
					`$.meshes[${i}].primitives[${p}].material`, base));
			}
			const material: int32 = materialRead.value;
			const read: MaterialRead =
				material == DEFAULT_MATERIAL ? DEFAULT_READ : reads[material];
			let tangentSources: Vec<int32> = [];
			const mesh: Result<MeshData, GltfError> =
				loadMesh(
					primitive,
					read,
					accessors,
					views,
					buffer,
					declaredLength,
					colourBuffers,
					colourViews,
					tangentSources,
				);
			if (!mesh.ok) {
				return Result.err(gltfFailure(mesh.error, source,
					`$.meshes[${i}].primitives[${p}]`, base));
			}
			const skinMesh = loadSkinMesh(primitive, mesh.value, tangentSources, accessors, views,
				buffer, declaredLength, colourBuffers, colourViews);
			if (!skinMesh.ok) {
				return Result.err(gltfFailure(skinMesh.error, source,
					`$.meshes[${i}].primitives[${p}].attributes`, base,
					"skin joints, weights, or palette topology are invalid"));
			}
			data.meshes.push(mesh.value);
			data.skinMeshes.push(skinMesh.value);
			data.meshMaterials.push(material);
		}
	}
	const nodeArray: JsonValue = arrayOf(root, "nodes");
	const nodeCount: int32 = countOf(nodeArray);
	for (let i = 0; i < nodeCount; i++) {
		const node: Result<GltfNode, GltfError> = loadNode(nodeArray.at(i));
		if (!node.ok) {
			return Result.err(gltfFailure(node.error, source, `$.nodes[${i}]`,
				sourceName(nodeArray.at(i))));
		}
		const skin = node.value.skin;
		if (skin !== null && (skin < 0 || skin >= countOf(arrayOf(root, "skins"))
			|| node.value.mesh < 0)) {
			return Result.err(gltfFailure(GltfError.BadNode, source, `$.nodes[${i}]`,
				sourceName(nodeArray.at(i)),
				"skin node requires a mesh and a valid skin reference"));
		}
		data.nodes.push(node.value);
	}
	data.skins = try loadSkins(root, accessors, views, buffer, declaredLength, nodeCount,
		colourBuffers, colourViews, source);
	let animations = loadAnimations(root, accessors, views, buffer, declaredLength, nodeCount,
		colourBuffers, colourViews);
	if (!animations.ok) {
		return Result.err(gltfFailure(animations.error, source, "$.animations"));
	}
	data.animations = move animations.value;
	placePrimitives(data, runs, nodeCount);
	const scenes: JsonValue = arrayOf(root, "scenes");
	if (isNull(scenes)) { return Result.err(gltfFailure(GltfError.NotGltf, source, "$.scenes")); }
	const sceneIndex: int32 = intField(root, "scene", 0);
	const scene: JsonValue = scenes.at(sceneIndex);
	if (isNull(scene) || scene.kind != JsonKind.Object) {
		return Result.err(gltfFailure(GltfError.NotGltf, source, "$.scene"));
	}
	if (!isArrayOrAbsent(scene, "nodes")) {
		return Result.err(gltfFailure(GltfError.Unsupported, source,
			`$.scenes[${sceneIndex}].nodes`));
	}
	const roots: JsonValue = arrayOf(scene, "nodes");
	const rootCount: int32 = countOf(roots);
	for (let i = 0; i < rootCount; i++) {
		const rootNode: int32 = intValue(roots.at(i));
		if (rootNode < 0) {
			return Result.err(gltfFailure(GltfError.Unsupported, source,
				`$.scenes[${sceneIndex}].nodes[${i}]`));
		}
		data.sceneRoots.push(rootNode);
	}
	const valid: Result<int32, GltfError> = validateGltfGraph(data);
	if (!valid.ok) {
		return Result.err(gltfFailure(valid.error, source, "$.nodes", "",
			"node graph, skin references, joint hierarchy, or canonical influences are invalid"));
	}
	return Result.ok(data);
}

export function loadGltf(json: string, buffer: Readonly<Span<uint8>>): Result<GltfData, GltfError> {
	let decoded = decodeGltf(json, buffer, false);
	if (!decoded.ok) { return Result.err(decoded.error.code); }
	return Result.ok(move decoded.value);
}

export function loadGltfDetailed(
	json: string, buffer: Readonly<Span<uint8>>, source: string = "<memory>",
): Result<GltfData, GltfDiagnostic> {
	return decodeGltf(json, buffer, false, source);
}

function uint32At(bytes: Readonly<Span<uint8>>, at: int32): uint32 {
	return (bytes[at] as uint32)
		| ((bytes[at + 1] as uint32) << (8 as uint32))
		| ((bytes[at + 2] as uint32) << (16 as uint32))
		| ((bytes[at + 3] as uint32) << (24 as uint32));
}

// Chunk layout and checks from glTF 2.0.1 §4.4: a JSON chunk first, an optional BIN chunk
// second, every chunk 4-byte aligned, unknown chunks after those two ignored.
export function loadGlbDetailed(
	bytes: Readonly<Span<uint8>>, source: string = "<memory>",
): Result<GltfData, GltfDiagnostic> {
	const total: int32 = bytes.length as int32;
	if (total < GLB_HEADER_LENGTH + GLB_CHUNK_HEADER_LENGTH) {
		return Result.err(gltfFailure(GltfError.NotGlb, source, "$.glb.header"));
	}
	if (uint32At(bytes, 0) != GLB_MAGIC || uint32At(bytes, 4) != GLB_VERSION
		|| uint32At(bytes, 8) != (total as uint32)) {
		return Result.err(gltfFailure(GltfError.NotGlb, source, "$.glb.header"));
	}
	let at: int32 = GLB_HEADER_LENGTH;
	let json: string = "";
	let binaryStart: int32 = 0;
	let binaryEnd: int32 = 0;
	let chunk: int32 = 0;
	while (at < total) {
		if (total - at < GLB_CHUNK_HEADER_LENGTH) {
			return Result.err(gltfFailure(GltfError.NotGlb, source, `$.glb.chunks[${chunk}]`));
		}
		const length: uint32 = uint32At(bytes, at);
		const kind: uint32 = uint32At(bytes, at + 4);
		const start: int32 = at + GLB_CHUNK_HEADER_LENGTH;
		if (length > ((total - start) as uint32) || length % (4 as uint32) != 0) {
			const cause: string = `chunk length ${length} at byte ${at} exceeds file bounds ` +
				"or is not 4-byte aligned";
			return Result.err(gltfFailure(GltfError.NotGlb, source,
				`$.glb.chunks[${chunk}]`, "", cause));
		}
		const end: int32 = start + (length as int32);
		if (chunk == 0) {
			if (kind != GLB_CHUNK_JSON) {
				return Result.err(gltfFailure(GltfError.NotGlb, source, "$.glb.chunks[0]", "",
					"first chunk must contain JSON"));
			}
			let text: uint8[] = [];
			for (let i = start; i < end; i++) { text.push(bytes[i]); }
			json = text.asString();
		} else if (chunk == 1 && kind == GLB_CHUNK_BIN) {
			binaryStart = start;
			binaryEnd = end;
		} else if (kind == GLB_CHUNK_JSON || kind == GLB_CHUNK_BIN) {
			return Result.err(gltfFailure(GltfError.NotGlb, source, `$.glb.chunks[${chunk}]`, "",
				"JSON or BIN chunk is duplicated or out of order"));
		}
		at = end;
		chunk = chunk + 1;
	}
	return decodeGltf(json, bytes[binaryStart..binaryEnd], true, source);
}

export function loadGlb(bytes: Readonly<Span<uint8>>): Result<GltfData, GltfError> {
	let decoded = loadGlbDetailed(bytes);
	if (!decoded.ok) { return Result.err(decoded.error.code); }
	return Result.ok(move decoded.value);
}
