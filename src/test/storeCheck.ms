import { Program, VERTEX_UNIFORM_LENGTH, LIGHT_UNIFORM_LENGTH } from "../void3d/gpu3d";
import { RenderState } from "../gpu/state";
import { Vec4, identity } from "../math/math3d";
import { Material, Phase, UniformBlock } from "../void3d/material";
import { TextureId } from "../void3d/texture";
import {
	UniformPool,
	UniformError,
	reserveRange,
	writeRange,
	ownRange,
	disownRange,
	releaseRange,
} from "../void3d/uniformPool";
import {
	DrawContext,
	DrawItem,
	MeshId,
	MaterialId,
	MaterialError,
	HandleError,
	addMaterial,
	retainMesh,
	releaseMesh,
	pinMesh,
	unpinMesh,
	retainMaterial,
	releaseMaterial,
	pinMaterial,
	unpinMaterial,
	retainTexture,
	releaseTexture,
	reserveUniforms,
} from "../void3d/draw";
import { Renderer, RendererError, RENDERER_UNIFORM_LENGTH, beginFrame } from "../void3d/renderer";
import {
	ForwardRenderer,
	ForwardError,
	FORWARD_UNIFORM_LENGTH,
	renderFrame,
} from "../void3d/forwardRenderer";
import {
	PixelArtRenderer,
	PixelArtSettings,
	PixelArtLook,
	PixelArtError,
	PIXEL_ART_UNIFORM_LENGTH,
	renderFrame as renderPixelArt,
} from "../void3d/pixelArtRenderer";
import { LowResView } from "../void3d/blit";
import {
	Scene3D,
	NodeId3D,
	SceneError,
	Transform3D,
	addMeshNode,
	setMeshOf,
	setName,
} from "../void3d/scene";
import {
	AnimationClock,
	AnimationError,
	Interpolation,
	MeshFrameAnimation,
	bindMeshFrames,
	syncMeshFrame,
} from "../void3d/animation";
import { contextOf } from "./drawHelpers";

function refused(result: Result<int32, HandleError>, expected: HandleError): boolean {
	return !result.ok && result.error == expected;
}

function poolRefused(result: Result<int32, UniformError>, expected: UniformError): boolean {
	return !result.ok && result.error == expected;
}

test "two contexts name the same slots and refuse each other's meshes and materials by name" {
	let a: DrawContext = contextOf(2, 2);
	let b: DrawContext = contextOf(2, 2);
	const mesh: MeshId = a.meshAt(0);
	const material: MaterialId = a.materialAt(0);
	assert mesh.index == b.meshAt(0).index && mesh.generation == b.meshAt(0).generation;
	assert a.issuedMesh(mesh) && !b.issuedMesh(mesh) && !b.issuedMaterial(material);
	assert !b.hasMesh(mesh) && !b.hasMaterial(material) && b.hasMesh(b.meshAt(0));
	assert refused(retainMesh(b, mesh), HandleError.ForeignMesh);
	assert refused(pinMesh(b, mesh), HandleError.ForeignMesh);
	assert refused(unpinMesh(b, mesh), HandleError.ForeignMesh);
	assert refused(releaseMesh(b, mesh), HandleError.ForeignMesh);
	assert refused(retainMaterial(b, material), HandleError.ForeignMaterial);
	assert refused(pinMaterial(b, material), HandleError.ForeignMaterial);
	assert refused(unpinMaterial(b, material), HandleError.ForeignMaterial);
	assert refused(releaseMaterial(b, material), HandleError.ForeignMaterial);
	assert b.meshPinned(mesh) == 0 && b.meshHolders[0] == 1 && b.materialHolders[0] == 1;
	assert a.liveMeshes() == 2 && b.liveMeshes() == 2 && b.liveMaterials() == 2;
	const texture: TextureId = { store: a.serial, index: 0, generation: 1 };
	assert !b.hasTexture(texture) && refused(retainTexture(b, texture), HandleError.ForeignTexture);
	assert refused(releaseTexture(b, texture), HandleError.ForeignTexture);
	assert refused(releaseTexture(a, texture), HandleError.StaleTexture);
}

test "an alias of a context is the context, and a release through it counts once" {
	let context: DrawContext = contextOf(1, 1);
	let alias: DrawContext = context;
	const mesh: MeshId = context.meshAt(0);
	assert alias.serial == context.serial;
	assert releaseMesh(alias, mesh).ok;
	assert !context.hasMesh(mesh) && context.liveMeshes() == 0;
	assert refused(releaseMesh(context, mesh), HandleError.StaleMesh);
	let held: DrawContext = DrawContext.withUniformCapacity(8);
	let pool: UniformPool = held.uniforms;
	const block: Result<UniformBlock, UniformError> = reserveUniforms(held, 2, 4);
	assert block.ok;
	if (!block.ok) { return; }
	assert pool.holds(block.value) && pool.used == 4;
	assert releaseRange(pool, block.value).ok && !held.uniforms.holds(block.value);
}

test "a uniform block names its pool, and another pool refuses it by name" {
	let first: UniformPool = UniformPool.withCapacity(8);
	let second: UniformPool = UniformPool.withCapacity(8);
	const block: Result<UniformBlock, UniformError> = reserveRange(first, 2, 4);
	const twin: Result<UniformBlock, UniformError> = reserveRange(second, 2, 4);
	assert block.ok && twin.ok;
	if (!block.ok || !twin.ok) { return; }
	assert block.value.offset == twin.value.offset && block.value.store != twin.value.store;
	assert first.holds(block.value) && !second.holds(block.value) && !second.isOwned(block.value);
	const values: Vec<float32> = [1.0, 2.0, 3.0, 4.0];
	assert poolRefused(writeRange(second, block.value, values), UniformError.Foreign);
	assert poolRefused(ownRange(second, block.value), UniformError.Foreign);
	assert poolRefused(disownRange(second, block.value), UniformError.Foreign);
	assert poolRefused(releaseRange(second, block.value), UniformError.Foreign);
	assert second.holds(twin.value) && first.holds(block.value);
	const nothing: Result<UniformBlock, UniformError> = reserveRange(first, 2, 0);
	assert nothing.ok;
	if (!nothing.ok) { return; }
	assert second.holds(nothing.value) && ownRange(second, nothing.value).ok;
}

test "a context refuses a material that names another context's texture or block" {
	let a: DrawContext = DrawContext.withUniformCapacity(8);
	let b: DrawContext = DrawContext.withUniformCapacity(8);
	const block: Result<UniformBlock, UniformError> = reserveUniforms(a, 3, 4);
	assert block.ok;
	if (!block.ok) { return; }
	const blocked: Material = {
		...Material.plain(Program.Lit, RenderState.defaults(), Phase.Opaque),
		uniforms: block.value,
	};
	const taken: Result<MaterialId, MaterialError> = addMaterial(b, blocked);
	assert !taken.ok && taken.error == MaterialError.ForeignUniforms;
	const textured: Material = {
		...Material.plain(Program.LitTextured, RenderState.defaults(), Phase.Opaque),
		texture: { store: a.serial, index: 0, generation: 1 },
	};
	const named: Result<MaterialId, MaterialError> = addMaterial(b, textured);
	assert !named.ok && named.error == MaterialError.ForeignTexture;
	assert b.liveMaterials() == 0 && a.uniforms.holds(block.value);
	assert !a.uniforms.isOwned(block.value);
}

test "the core refuses another context's mesh or material by name before it writes" {
	let a: DrawContext = contextOf(1, 1);
	let b: DrawContext = DrawContext.withUniformCapacity(RENDERER_UNIFORM_LENGTH);
	const created: Result<Renderer, RendererError> = Renderer.create(b);
	assert created.ok;
	if (!created.ok) { return; }
	let core: Renderer = created.value;
	let camera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
	let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
	const foreignMesh: Vec<DrawItem> =
		[{ mesh: a.meshAt(0), material: a.materialAt(0), world: identity() }];
	const meshFrame: Result<boolean, RendererError> =
		beginFrame(core, b, foreignMesh, camera, lights);
	assert !meshFrame.ok && meshFrame.error == RendererError.ForeignMesh;
	const foreignMaterial: Vec<DrawItem> =
		[{ mesh: b.meshAt(0), material: a.materialAt(0), world: identity() }];
	const materialFrame: Result<boolean, RendererError> =
		beginFrame(core, b, foreignMaterial, camera, lights);
	assert !materialFrame.ok && materialFrame.error == RendererError.ForeignMaterial;
	assert core.generation == 0 && core.drawn.length == 0;
}

test "both presets refuse a frame through a context that did not make them" {
	let camera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
	let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
	let none: Vec<DrawItem> = [];
	let background: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };
	let made: DrawContext = DrawContext.withUniformCapacity(FORWARD_UNIFORM_LENGTH);
	let other: DrawContext = DrawContext.withUniformCapacity(FORWARD_UNIFORM_LENGTH);
	const forward: Result<ForwardRenderer, ForwardError> = ForwardRenderer.create(made, background);
	assert forward.ok;
	if (!forward.ok) { return; }
	let copy: ForwardRenderer = forward.value;
	const copied: Result<int32, ForwardError> =
		renderFrame(copy, other, none, camera, lights, 640, 480);
	assert !copied.ok && copied.error == ForwardError.ForeignMaterial;
	let look: PixelArtLook = {
		background: background,
		outline: {
			depthThreshold: 0.006,
			normalThreshold: 0.6,
			depthShade: 0.55,
			normalShade: 1.35,
		},
		fog: { start: 0.5, end: 0.8, strength: 0.0, color: background },
		saturation: 0.0,
	};
	let view: LowResView = { width: 320, height: 240, scale: 1, offsetX: 0.0, offsetY: 0.0 };
	let pixelContext: DrawContext = DrawContext.withUniformCapacity(PIXEL_ART_UNIFORM_LENGTH);
	let pixelOther: DrawContext = DrawContext.withUniformCapacity(PIXEL_ART_UNIFORM_LENGTH);
	const preset: Result<PixelArtRenderer, PixelArtError> =
		PixelArtRenderer.create(pixelContext, PixelArtSettings.full(), look);
	assert preset.ok;
	if (!preset.ok) { return; }
	let pixelArt: PixelArtRenderer = preset.value;
	const drawn: Result<int32, PixelArtError> =
		renderPixelArt(pixelArt, pixelOther, none, camera, lights, view);
	assert !drawn.ok && drawn.error == PixelArtError.ForeignMaterial;
}

test "a scene refuses another context's mesh or material by name and keeps its pins" {
	let a: DrawContext = contextOf(2, 2);
	let b: DrawContext = contextOf(2, 2);
	let scene: Scene3D = Scene3D.create();
	const meshNode: Result<NodeId3D, SceneError> =
		addMeshNode(scene, b, scene.rootId(), Transform3D.identity(), a.meshAt(0), b.materialAt(0));
	assert !meshNode.ok && meshNode.error == SceneError.ForeignMesh;
	const materialNode: Result<NodeId3D, SceneError> =
		addMeshNode(scene, b, scene.rootId(), Transform3D.identity(), b.meshAt(0), a.materialAt(0));
	assert !materialNode.ok && materialNode.error == SceneError.ForeignMaterial;
	const own: Result<NodeId3D, SceneError> =
		addMeshNode(scene, b, scene.rootId(), Transform3D.identity(), b.meshAt(0), b.materialAt(0));
	assert own.ok;
	if (!own.ok) { return; }
	const swapped: Result<int32, SceneError> = setMeshOf(scene, b, own.value, a.meshAt(1));
	assert !swapped.ok && swapped.error == SceneError.ForeignMesh;
	assert b.meshPinned(b.meshAt(0)) == 1 && a.meshPinned(a.meshAt(1)) == 0;
}

test "mesh frames refuse another context's meshes by name" {
	let a: DrawContext = contextOf(2, 1);
	let b: DrawContext = contextOf(2, 1);
	const clock: Result<AnimationClock, AnimationError> =
		AnimationClock.forFrames(1, 12.0, Interpolation.Step);
	assert clock.ok;
	if (!clock.ok) { return; }
	const foreign: Vec<MeshId> = [a.meshAt(0)];
	const refusedFrames: Result<MeshFrameAnimation, AnimationError> =
		MeshFrameAnimation.forMeshes(b, clock.value, "pet", foreign);
	assert !refusedFrames.ok && refusedFrames.error == AnimationError.ForeignMesh;
	const made: Result<MeshFrameAnimation, AnimationError> =
		MeshFrameAnimation.forMeshes(a, clock.value, "pet", foreign);
	assert made.ok;
	if (!made.ok) { return; }
	let animation: MeshFrameAnimation = made.value;
	let scene: Scene3D = Scene3D.create();
	const node: Result<NodeId3D, SceneError> =
		addMeshNode(scene, b, scene.rootId(), Transform3D.identity(), b.meshAt(1), b.materialAt(0));
	assert node.ok;
	if (!node.ok) { return; }
	setName(scene, node.value, "pet");
	assert bindMeshFrames(animation, scene, scene.rootId()).ok;
	const synced: Result<int32, AnimationError> = syncMeshFrame(animation, scene, b);
	assert !synced.ok && synced.error == AnimationError.ForeignMesh;
	assert b.meshPinned(b.meshAt(1)) == 1;
}

test "both presets refuse a frame whose own screen material's block was replaced, before any pass" {
	let camera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
	let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
	let none: Vec<DrawItem> = [];
	let background: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };
	let made: DrawContext = DrawContext.withUniformCapacity(FORWARD_UNIFORM_LENGTH + 4);
	const forward: Result<ForwardRenderer, ForwardError> = ForwardRenderer.create(made, background);
	const spare: Result<UniformBlock, UniformError> = reserveUniforms(made, 3, 4);
	assert forward.ok && spare.ok;
	if (!forward.ok || !spare.ok) { return; }
	let copy: ForwardRenderer = forward.value;
	made.materials[copy.copyMaterial.index].uniforms = spare.value;
	const copied: Result<int32, ForwardError> =
		renderFrame(copy, made, none, camera, lights, 640, 480);
	assert !copied.ok && copied.error == ForwardError.UniformsReplaced;
	assert copy.core.generation == 0 && copy.colorTarget.image == 0;
	let look: PixelArtLook = {
		background: background,
		outline: {
			depthThreshold: 0.006,
			normalThreshold: 0.6,
			depthShade: 0.55,
			normalShade: 1.35,
		},
		fog: { start: 0.5, end: 0.8, strength: 0.0, color: background },
		saturation: 0.0,
	};
	let view: LowResView = { width: 320, height: 240, scale: 1, offsetX: 0.0, offsetY: 0.0 };
	for (const post of [true, false]) {
		let context: DrawContext = DrawContext.withUniformCapacity(PIXEL_ART_UNIFORM_LENGTH + 4);
		const preset: Result<PixelArtRenderer, PixelArtError> =
			PixelArtRenderer.create(context, PixelArtSettings.full(), look);
		const block: Result<UniformBlock, UniformError> = reserveUniforms(context, 3, 4);
		assert preset.ok && block.ok;
		if (!preset.ok || !block.ok) { return; }
		let pixelArt: PixelArtRenderer = preset.value;
		const screen: MaterialId = post ? pixelArt.postMaterial : pixelArt.blitMaterial;
		context.materials[screen.index].uniforms = block.value;
		const drawn: Result<int32, PixelArtError> =
			renderPixelArt(pixelArt, context, none, camera, lights, view);
		assert !drawn.ok && drawn.error == PixelArtError.UniformsReplaced;
		assert pixelArt.core.generation == 0;
	}
}
