// The gate's churn stage runs this, releasing (churnBench) and not releasing (churnControl).

import { gfxSetup } from "../sokol/gpu";
import { vec3, identityQuat } from "../math/math3d";
import {
	Program,
	MATERIAL_UNIFORM_SLOT,
	MATERIAL_UNIFORM_LENGTH,
	VERTEX_UNIFORM_LENGTH,
	LIGHT_UNIFORM_LENGTH,
} from "../void3d/gpu3d";
import { liveBuffers, liveImages, liveViews, liveSamplers } from "../gpu/door";
import { RenderState, FilterMode, Wrap } from "../gpu/state";
import { Material, MaterialKind, Phase, UniformBlock } from "../void3d/material";
import { MeshData, MeshError, Rgba, addBox, addTexturedCube } from "../void3d/meshData";
import { TextureData, TextureId, TextureUploadError, NO_TEXTURE } from "../void3d/texture";
import { UniformError } from "../void3d/uniformPool";
import { GltfData, GltfTransform, DEFAULT_MATERIAL } from "../void3d/gltf";
import {
	GltfAssets,
	GltfMaterialSetup,
	GltfSceneError,
	addGltfAssets,
	addGltfNodes,
	closeGltfAssets,
} from "../void3d/gltfScene";
import {
	DrawContext,
	DrawItem,
	MeshId,
	MaterialId,
	MaterialError,
	MeshUploadError,
	StreamError,
	HandleError,
	STREAM_INSTANCE_STRIDE,
	addMeshData,
	addMaterial,
	addTexture,
	releaseTexture,
	addStreamMesh,
	writeStream,
	releaseMesh,
	releaseMaterial,
	reserveUniforms,
	writeUniforms,
} from "../void3d/draw";
import {
	Transform3D,
	Scene3D,
	NodeId3D,
	SceneError,
	NO_NODE_3D,
	addGroup,
	addMeshNode,
	remove,
	refresh,
	NO_NODE_ID,
} from "../void3d/scene";
import {
	ForwardRenderer,
	ForwardError,
	FORWARD_UNIFORM_LENGTH,
	renderFrame,
} from "../void3d/forwardRenderer";

export enum ChurnError {
	MeshRefused,
	TextureRefused,
	StreamRefused,
	UniformsRefused,
	MaterialRefused,
	NodeRefused,
	ModelRefused,
	FirstWriteRefused,
	SecondWriteTaken,
	FrameRefused,
}

export struct ChurnStats {
	frames: int32;
	meshSlots: int32;
	materialSlots: int32;
	liveMeshes: int32;
	liveMaterials: int32;
	uniformsUsed: int32;
	freeRanges: int32;
	doomed: int32;
	liveBuffers: int32;
	textureSlots: int32;
	liveTextures: int32;
	doomedTextures: int32;
	liveImages: int32;
	liveViews: int32;
	liveSamplers: int32;
	sceneNodes: int32;
	sceneSlots: int32;
	secondWritesRefused: int32;
	stopped: boolean;
	stoppedBy: ChurnError;
}

// Room for the four blocks a frame takes in a run that never releases, so that run meets sokol's
// buffer pool, not this one.
const MAX_FRAMES: int32 = 400;
const STREAM_CAPACITY: int32 = 16;
const STREAM_WRITTEN: int32 = 4;
const WIDTH: int32 = 640;
const HEIGHT: int32 = 360;
const WHITE: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };
const NO_ID: NodeId3D = NO_NODE_ID;

let context: DrawContext = DrawContext.withUniformCapacity(
	FORWARD_UNIFORM_LENGTH + 4 * MAX_FRAMES * MATERIAL_UNIFORM_LENGTH,
);
let forward: ForwardRenderer = createForward();
let scene: Scene3D = Scene3D.create(context);
let items: Vec<DrawItem> = [];
let camera: Vec<float32> = zeros(VERTEX_UNIFORM_LENGTH);
let lights: Vec<float32> = zeros(LIGHT_UNIFORM_LENGTH);
let instances: Vec<float32> = zeros(STREAM_CAPACITY * STREAM_INSTANCE_STRIDE);
let box: MeshData = boxData();
let texturedBox: MeshData = texturedBoxData();
let model: GltfData = modelData();
let releasing: boolean = true;
let frames: int32 = 0;
let secondWritesRefused: int32 = 0;
let stopped: boolean = false;
let stoppedBy: ChurnError = ChurnError.FrameRefused;

function createForward(): ForwardRenderer {
	const created: Result<ForwardRenderer, ForwardError> =
		ForwardRenderer.create(context, { x: 0.0, y: 0.0, z: 0.0, w: 1.0 });
	if (created.ok) { return created.value; }
	unreachable;
}

function zeros(length: int32): Vec<float32> {
	let values: Vec<float32> = new Array(length);
	for (let i = 0; i < length; i++) { values[i] = 0.0; }
	return values;
}

function boxData(): MeshData {
	let data: MeshData = MeshData.empty();
	const _added: Result<int32, MeshError> = addBox(data, {
		base: vec3(0.0, 0.0, 0.0),
		size: vec3(1.0, 1.0, 1.0),
		yaw: 0.0,
		tilt: 0.0,
		color: WHITE,
	});
	return data;
}

function texturedBoxData(): MeshData {
	let data: MeshData = MeshData.withUvs();
	let _added: Result<int32, MeshError> =
		addTexturedCube(data, vec3(1.0, 1.0, 1.0), true, WHITE);
	return data;
}

function checker(): TextureData {
	return {
		pixels: [0xFFFFFFFF, 0xFF000000, 0xFF000000, 0xFFFFFFFF],
		width: 2,
		height: 2,
		filter: FilterMode.Nearest,
		wrap: Wrap.Repeat,
	};
}

function modelData(): GltfData {
	return {
		meshes: [texturedBoxData(), boxData()],
		meshMaterials: [0, DEFAULT_MATERIAL],
		materials: [
			{ texture: 0, doubleSided: true, kind: MaterialKind.Opaque, alphaKill: 0.0 },
		],
		textures: [checker()],
		nodes: [
			{ name: "cube", mesh: 0, local: modelTransform(), children: [1] },
			{ name: "box", mesh: 1, local: modelTransform(), children: [] },
		],
		sceneRoots: [0],
	};
}

function modelTransform(): GltfTransform {
	return { position: vec3(0.0, 0.0, 0.0), rotation: identityQuat(), scale: vec3(1.0, 1.0, 1.0) };
}

function modelSetup(): GltfMaterialSetup {
	return { pass: RenderState.defaults(), block: [4.0, 0.0, 0.0, 0.0] };
}

function churnErrorOf(error: GltfSceneError): ChurnError {
	return match (error) {
		GltfSceneError.TextureRefused => ChurnError.TextureRefused,
		GltfSceneError.MeshRefused => ChurnError.MeshRefused,
		GltfSceneError.UniformsFull => ChurnError.UniformsRefused,
		GltfSceneError.MaterialRefused => ChurnError.MaterialRefused,
		GltfSceneError.SceneRefused => ChurnError.NodeRefused,
		GltfSceneError.InvalidData => ChurnError.ModelRefused,
		GltfSceneError.BadMeshBinding => ChurnError.ModelRefused,
		GltfSceneError.ForeignMeshBinding => ChurnError.ModelRefused,
		GltfSceneError.BadSetup => ChurnError.ModelRefused,
	};
}

function loadModel(level: NodeId3D): Result<int32, ChurnError> {
	const assets: Result<GltfAssets, GltfSceneError> =
		addGltfAssets(context, model, modelSetup());
	if (!assets.ok) { return Result.err(churnErrorOf(assets.error)); }
	const added: Result<int32, GltfSceneError> =
		addGltfNodes(scene, level, model, assets.value.bindings);
	if (!added.ok) { return Result.err(churnErrorOf(added.error)); }
	if (releasing) {
		closeGltfAssets(assets.value);
	}
	return Result.ok(added.value);
}

export function configureChurn(release: boolean): void {
	releasing = release;
}

export function initChurn(): void {
	gfxSetup();
}

function litMaterial(program: Program, texture: TextureId): Result<MaterialId, ChurnError> {
	const reserved: Result<UniformBlock, UniformError> =
		reserveUniforms(context, MATERIAL_UNIFORM_SLOT, MATERIAL_UNIFORM_LENGTH);
	if (!reserved.ok) { return Result.err(ChurnError.UniformsRefused); }
	const levels: Vec<float32> = [4.0, 0.0, 0.0, 0.0];
	const written: Result<int32, UniformError> = writeUniforms(context, reserved.value, levels);
	if (!written.ok) { return Result.err(ChurnError.UniformsRefused); }
	const plain: Material = Material.plain(program, RenderState.defaults(), Phase.Opaque);
	const added: Result<MaterialId, MaterialError> =
		addMaterial(context, { ...plain, texture: texture, uniforms: reserved.value });
	if (!added.ok) { return Result.err(ChurnError.MaterialRefused); }
	return Result.ok(added.value);
}

function particleMaterial(): Result<MaterialId, ChurnError> {
	const plain: Material = Material.plain(Program.Particle, RenderState.defaults(), Phase.Opaque);
	const added: Result<MaterialId, MaterialError> = addMaterial(context, plain);
	if (!added.ok) { return Result.err(ChurnError.MaterialRefused); }
	return Result.ok(added.value);
}

function fillStream(stream: MeshId): Result<int32, ChurnError> {
	const first: Result<int32, StreamError> =
		writeStream(context, stream, instances, STREAM_WRITTEN);
	if (!first.ok) { return Result.err(ChurnError.FirstWriteRefused); }
	const second: Result<int32, StreamError> =
		writeStream(context, stream, instances, STREAM_WRITTEN);
	if (second.ok || second.error != StreamError.WrittenThisFrame) {
		return Result.err(ChurnError.SecondWriteTaken);
	}
	secondWritesRefused = secondWritesRefused + 1;
	return Result.ok(STREAM_WRITTEN);
}

function place(level: NodeId3D, mesh: MeshId, material: MaterialId): Result<NodeId3D, ChurnError> {
	const placed: Result<NodeId3D, SceneError> =
		addMeshNode(scene, level, Transform3D.identity(), mesh, material);
	if (!placed.ok) { return Result.err(ChurnError.NodeRefused); }
	return Result.ok(placed.value);
}

function loadLevel(): Result<NodeId3D, ChurnError> {
	const level: NodeId3D = addGroup(scene, scene.rootId(), Transform3D.identity());
	const mesh: Result<MeshId, MeshUploadError> = addMeshData(context, box);
	if (!mesh.ok) { return Result.err(ChurnError.MeshRefused); }
	const stream: Result<MeshId, StreamError> = addStreamMesh(context, STREAM_CAPACITY);
	if (!stream.ok) { return Result.err(ChurnError.StreamRefused); }
	let texturedMesh: Result<MeshId, MeshUploadError> = addMeshData(context, texturedBox);
	if (!texturedMesh.ok) { return Result.err(ChurnError.MeshRefused); }
	let texture: Result<TextureId, TextureUploadError> = addTexture(context, checker());
	if (!texture.ok) { return Result.err(ChurnError.TextureRefused); }
	const lit: MaterialId = try litMaterial(Program.Lit, NO_TEXTURE);
	let textured: MaterialId = try litMaterial(Program.LitTextured, texture.value);
	const particles: MaterialId = try particleMaterial();
	const _box: NodeId3D = try place(level, mesh.value, lit);
	let _texturedBox: NodeId3D = try place(level, texturedMesh.value, textured);
	const _stream: NodeId3D = try place(level, stream.value, particles);
	const _written: int32 = try fillStream(stream.value);
	const _model: int32 = try loadModel(level);
	if (releasing) {
		const _mesh: Result<int32, HandleError> = releaseMesh(context, mesh.value);
		let _texturedMesh: Result<int32, HandleError> = releaseMesh(context, texturedMesh.value);
		const _particles: Result<int32, HandleError> = releaseMesh(context, stream.value);
		let _texture: Result<int32, HandleError> = releaseTexture(context, texture.value);
		const _lit: Result<int32, HandleError> = releaseMaterial(context, lit);
		let _textured: Result<int32, HandleError> = releaseMaterial(context, textured);
		const _particle: Result<int32, HandleError> = releaseMaterial(context, particles);
	}
	return Result.ok(level);
}

function stop(error: ChurnError): void {
	stopped = true;
	stoppedBy = error;
}

export function frameChurn(): void {
	if (stopped) { return; }
	const loaded: Result<NodeId3D, ChurnError> = loadLevel();
	if (!loaded.ok) {
		stop(loaded.error);
		return;
	}
	const _drawn: int32 = refresh(scene, items);
	const rendered: Result<int32, ForwardError> =
		renderFrame(forward, items, camera, lights, WIDTH, HEIGHT);
	if (!rendered.ok) {
		console.log(`churn: the frame was refused, ${rendered.error.toString()}`);
		stop(ChurnError.FrameRefused);
		return;
	}
	if (releasing) {
		const _removed: int32 = remove(scene, loaded.value);
	}
	frames = frames + 1;
}

export function churnStats(): ChurnStats {
	return {
		frames: frames,
		meshSlots: context.meshes.length as int32,
		materialSlots: context.materials.length as int32,
		liveMeshes: context.liveMeshes(),
		liveMaterials: context.liveMaterials(),
		uniformsUsed: context.uniforms.used,
		freeRanges: context.uniforms.freeRanges(),
		doomed: context.doomed.length as int32,
		liveBuffers: liveBuffers(),
		textureSlots: context.textures.length as int32,
		liveTextures: context.liveTextures(),
		doomedTextures: context.doomedTextures.length as int32,
		liveImages: liveImages(),
		liveViews: liveViews(),
		liveSamplers: liveSamplers(),
		sceneNodes: scene.nodeCount(),
		sceneSlots: scene.nodes.length as int32,
		secondWritesRefused: secondWritesRefused,
		stopped: stopped,
		stoppedBy: stoppedBy,
	};
}
