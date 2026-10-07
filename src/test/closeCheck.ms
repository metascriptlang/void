import { Vec4 } from "../math/math3d";
import { contextGeneration } from "../gpu/door";
import { identity } from "../math/math3d";
import { Program } from "../void3d/gpu3d";
import { RenderState } from "../gpu/state";
import { Material, Phase, UniformBlock } from "../void3d/material";
import {
	DrawContext,
	GpuMesh,
	MeshId,
	MaterialId,
	MaterialError,
	MeshUploadError,
	HandleError,
	addMesh,
	addMaterial,
	releaseMesh,
	releaseMaterial,
	reserveUniforms,
	releaseUniforms,
	closeContext,
} from "../void3d/draw";
import { UniformError } from "../void3d/uniformPool";
import {
	Scene3D,
	NodeId3D,
	SceneError,
	Transform3D,
	addMeshNode,
	addGroup,
	closeScene,
	remove,
} from "../void3d/scene";
import { contextOf } from "./drawHelpers";
import { PaletteLut, PaletteError, closePalette, releaseGpu } from "../void3d/palette";
import {
	Renderer,
	RendererError,
	RENDERER_UNIFORM_LENGTH,
	closeRenderer,
	openPrepare,
} from "../void3d/renderer";
import {
	ForwardRenderer,
	ForwardError,
	FORWARD_UNIFORM_LENGTH,
	closeForward,
} from "../void3d/forwardRenderer";
import {
	PixelArtRenderer,
	PixelArtSettings,
	PixelArtLook,
	PixelArtError,
	PIXEL_ART_UNIFORM_LENGTH,
	closePixelArt,
	endPrepared as endPixelArt,
} from "../void3d/pixelArtRenderer";
import { LowResView } from "../void3d/blit";

const BLACK: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };

function forwardOn(context: DrawContext): ForwardRenderer {
	const made: Result<ForwardRenderer, ForwardError> = ForwardRenderer.create(context, BLACK);
	if (!made.ok) { unreachable; }
	return made.value;
}

function pixelArtOn(context: DrawContext): PixelArtRenderer {
	const look: PixelArtLook = {
		background: BLACK,
		outline: {
			depthThreshold: 0.006,
			normalThreshold: 0.6,
			depthShade: 0.55,
			normalShade: 1.35,
		},
		fog: { start: 0.5, end: 0.8, strength: 0.0, color: BLACK },
		saturation: 0.0,
	};
	const made: Result<PixelArtRenderer, PixelArtError> =
		PixelArtRenderer.create(context, PixelArtSettings.full(), look);
	if (!made.ok) { unreachable; }
	return made.value;
}

test "closing the core gives its screen mesh and both blocks back, once" {
	let context: DrawContext = DrawContext.withUniformCapacity(RENDERER_UNIFORM_LENGTH);
	const made: Result<Renderer, RendererError> = Renderer.create(context);
	assert made.ok;
	if (!made.ok) { return; }
	let core: Renderer = made.value;
	assert core.context.serial == context.serial && context.liveMeshes() == 1;
	assert context.uniforms.isOwned(core.cameraBlock) && context.uniforms.isOwned(core.lightBlock);
	let alias: Renderer = core;
	closeRenderer(alias);
	assert core.isClosed() && !core.needsFrame();
	assert context.liveMeshes() == 0;
	assert !context.uniforms.holds(core.cameraBlock) && !context.uniforms.holds(core.lightBlock);
}

test "closing a forward preset gives back its copy material and closes its core" {
	let context: DrawContext = DrawContext.withUniformCapacity(FORWARD_UNIFORM_LENGTH);
	let forward: ForwardRenderer = forwardOn(context);
	assert context.liveMeshes() == 1 && context.liveMaterials() == 1;
	let alias: ForwardRenderer = forward;
	closeForward(alias);
	assert forward.isClosed() && forward.core.isClosed();
	assert context.liveMeshes() == 0 && context.liveMaterials() == 0;
	assert !context.uniforms.holds(forward.core.cameraBlock);
	assert forward.colorTarget.image == 0 && forward.sampler.handle == 0;
}

test "a forward preset skips a core an alias already closed" {
	let context: DrawContext = DrawContext.withUniformCapacity(FORWARD_UNIFORM_LENGTH);
	let forward: ForwardRenderer = forwardOn(context);
	let core: Renderer = forward.core;
	closeRenderer(core);
	assert forward.core.isClosed() && !forward.isClosed();
	closeForward(forward);
	assert forward.isClosed() && context.liveMeshes() == 0 && context.liveMaterials() == 0;
}

test "closing a pixel-art preset gives back both screen materials and closes its table and core" {
	let context: DrawContext = DrawContext.withUniformCapacity(PIXEL_ART_UNIFORM_LENGTH);
	let pixelArt: PixelArtRenderer = pixelArtOn(context);
	assert context.liveMeshes() == 1 && context.liveMaterials() == 2;
	let palette: PaletteLut = pixelArt.palette;
	closePixelArt(pixelArt);
	assert pixelArt.isClosed() && pixelArt.core.isClosed() && palette.isClosed();
	assert context.liveMeshes() == 0 && context.liveMaterials() == 0;
	assert !context.uniforms.holds(pixelArt.postBlock);
	assert !context.uniforms.holds(pixelArt.blitBlock);
	let view: LowResView = { width: 32, height: 24, scale: 1, offsetX: 0.0, offsetY: 0.0 };
	assert !pixelArt.needsFrame(view);
}

test "a pixel-art preset's prepared frame ends with endPrepared and may be prepared again" {
	let context: DrawContext = DrawContext.withUniformCapacity(PIXEL_ART_UNIFORM_LENGTH);
	let pixelArt: PixelArtRenderer = pixelArtOn(context);
	pixelArt.core.prepared = true;
	endPixelArt(pixelArt);
	assert !pixelArt.core.prepared;
	pixelArt.core.openPrepare();
	closePixelArt(pixelArt);
}

test "a pixel-art preset skips a table an alias already closed" {
	let context: DrawContext = DrawContext.withUniformCapacity(PIXEL_ART_UNIFORM_LENGTH);
	let pixelArt: PixelArtRenderer = pixelArtOn(context);
	closePalette(pixelArt.palette);
	closePixelArt(pixelArt);
	assert pixelArt.isClosed() && context.liveMaterials() == 0;
}

test "a palette table made under an older GPU context forgets its image instead of destroying it" {
	const made: Result<PaletteLut, PaletteError> = PaletteLut.withLevels(4);
	assert made.ok;
	if (!made.ok) { return; }
	let lut: PaletteLut = made.value;
	let alias: PaletteLut = lut;
	alias.image = 7;
	alias.texture = 9;
	alias.generation = contextGeneration() + 1;
	alias.dirty = false;
	releaseGpu(lut);
	assert alias.image == 0 && alias.texture == 0 && alias.generation == 0 && alias.dirty;
	alias.image = 7;
	alias.texture = 9;
	alias.generation = contextGeneration() + 1;
	closePalette(alias);
	assert lut.isClosed() && lut.image == 0 && lut.texture == 0;
}

test "a renderer made under an older GPU context forgets its screen buffer, destroying nothing" {
	let context: DrawContext = DrawContext.withUniformCapacity(RENDERER_UNIFORM_LENGTH);
	const made: Result<Renderer, RendererError> = Renderer.create(context);
	assert made.ok;
	if (!made.ok) { return; }
	let core: Renderer = made.value;
	const screen: int32 = core.screenMesh.index;
	context.meshes[screen].vertexBuffer = 7;
	core.generation = contextGeneration() + 1;
	closeRenderer(core);
	assert core.isClosed() && context.meshes[screen].vertexBuffer == 0;
	assert context.liveMeshes() == 0;
}

test "closing a scene unpins every node's mesh and material, and its queries answer false" {
	let context: DrawContext = contextOf(2, 1);
	let scene: Scene3D = Scene3D.create(context);
	const group: NodeId3D = addGroup(scene, scene.rootId(), Transform3D.identity());
	const node: Result<NodeId3D, SceneError> = addMeshNode(
		scene, group, Transform3D.identity(), context.meshAt(0), context.materialAt(0),
	);
	assert node.ok;
	if (!node.ok) { return; }
	assert context.meshPinned(context.meshAt(0)) == 1;
	let alias: Scene3D = scene;
	closeScene(alias);
	assert scene.isClosed() && scene.nodeCount() == 0 && !scene.isLive(node.value);
	assert context.meshPinned(context.meshAt(0)) == 0;
	assert context.materialPins[0] == 0;
	assert !scene.nameOf(group).ok && !scene.worldOf(group).ok;
}

test "a node id names its scene: another scene's id at a live index is not live" {
	let context: DrawContext = DrawContext.withUniformCapacity(0);
	let first: Scene3D = Scene3D.create(context);
	let second: Scene3D = Scene3D.create(context);
	const theirs: NodeId3D = addGroup(first, first.rootId(), Transform3D.identity());
	const ours: NodeId3D = addGroup(second, second.rootId(), Transform3D.identity());
	assert theirs.index == ours.index && theirs.generation == ours.generation;
	assert first.serial != second.serial && theirs.scene == first.serial;
	assert !second.isLive(theirs) && second.isLive(ours);
	assert !second.findByName(theirs, "").ok;
}

test "a pool counts the ranges it handed out and has not had back" {
	let context: DrawContext = DrawContext.withUniformCapacity(12);
	const first: Result<UniformBlock, UniformError> = reserveUniforms(context, 2, 4);
	const second: Result<UniformBlock, UniformError> = reserveUniforms(context, 2, 4);
	assert first.ok && second.ok;
	if (!first.ok || !second.ok) { return; }
	assert context.uniforms.liveRanges() == 2;
	assert releaseUniforms(context, first.value).ok;
	assert context.uniforms.liveRanges() == 1;
	assert releaseUniforms(context, second.value).ok;
	assert context.uniforms.liveRanges() == 0;
}

test "an emptied context closes with its pool and its pipeline cache, and answers false after" {
	let context: DrawContext = DrawContext.withUniformCapacity(4);
	const mesh: Result<MeshId, MeshUploadError> = addMesh(context, GpuMesh.fullscreen(0, 3));
	const plain: Material = Material.plain(Program.Lit, RenderState.defaults(), Phase.Opaque);
	const material: Result<MaterialId, MaterialError> = addMaterial(context, plain);
	assert mesh.ok && material.ok;
	if (!mesh.ok || !material.ok) { return; }
	const meshLeft: Result<int32, HandleError> = releaseMesh(context, mesh.value);
	assert meshLeft.ok;
	let alias: DrawContext = context;
	assert context.liveMeshes() == 0 && context.liveMaterials() == 1;
	closeContextOnceEmpty(alias, material.value);
	assert context.isClosed() && context.uniforms.isClosed() && context.pipelines.closed;
	assert !context.hasMesh(mesh.value) && !context.hasMaterial(material.value);
}

function closeContextOnceEmpty(context: DrawContext, material: MaterialId): void {
	const left: Result<int32, HandleError> = releaseMaterial(context, material);
	if (!left.ok) { unreachable; }
	closeContext(context);
}

test "closing a scene releases every never-attached subtree and its sole resource pins" {
	const context: DrawContext = contextOf(2, 1);
	const scene: Scene3D = Scene3D.create(context);
	const group: NodeId3D = addGroup(scene, null, Transform3D.identity());
	for (let i = 0; i < 2; i++) {
		const parent: NodeId3D | null = i == 0 ? group : null;
		assert addMeshNode(
			scene, parent, Transform3D.identity(), context.meshAt(i), context.materialAt(0),
		).ok;
		assert releaseMesh(context, context.meshAt(i)).ok;
	}
	assert releaseMaterial(context, context.materialAt(0)).ok;
	closeScene(scene);
	assert context.liveMeshes() == 0 && context.liveMaterials() == 0;
	assert scene.meshes.length == 0;
	closeContext(context);
	assert context.isClosed();
}

test "removing a detached subtree releases it without touching another detached owner" {
	const context: DrawContext = contextOf(2, 1);
	const scene: Scene3D = Scene3D.create(context);
	const gone: NodeId3D = addGroup(scene, null, Transform3D.identity());
	const kept: NodeId3D = addGroup(scene, null, Transform3D.identity());
	assert addMeshNode(
		scene, gone, Transform3D.identity(), context.meshAt(0), context.materialAt(0),
	).ok;
	assert addMeshNode(
		scene, kept, Transform3D.identity(), context.meshAt(1), context.materialAt(0),
	).ok;
	assert remove(scene, gone) == 2;
	assert context.meshPinned(context.meshAt(0)) == 0;
	assert context.meshPinned(context.meshAt(1)) == 1;
	const replacement: NodeId3D = addGroup(scene, null, Transform3D.identity());
	assert replacement != gone;
	closeScene(scene);
	assert context.meshPinned(context.meshAt(1)) == 0;
	assert context.materialPins[0] == 0;
}
