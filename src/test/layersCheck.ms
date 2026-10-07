import {
	DEFAULT_LAYERS,
	ALL_LAYERS,
	layerBit,
	layersEnable,
	layersDisable,
	layersToggle,
	layersTest,
	layersHas,
} from "../void3d/layers";
import { vec3 } from "../math/math3d";
import { LIGHT_UNIFORM_LENGTH, MAX_POINT_LIGHTS, Program, ProgramKey } from "../void3d/gpu3d";
import { Material, Phase } from "../void3d/material";
import { RenderState, BlendMode } from "../gpu/state";
import { addMaterial, MaterialId, MaterialError } from "../void3d/draw";
import { DrawContext, DrawItem } from "../void3d/draw";
import {
	Scene3D,
	NodeId3D,
	Transform3D,
	SceneError,
	NO_NODE_ID,
	addGroup,
	addMeshNode,
	addCameraNode,
	setActiveCamera,
	setVisible,
	setLocal,
	cameraOf,
	cameraViewOf,
	collectDrawList,
	collectDrawListFor,
	collectLights,
	setLightPower,
	collectLightsFor,
	addLightNode,
	LightError,
	LightKind,
	LightInstance,
	refresh,
	refreshFor,
	layersOf,
	setLayers,
	setLayer,
	enableLayer,
	disableLayer,
	toggleLayer,
	cameraLayersOf,
	setCameraLayers,
} from "../void3d/scene";
import { Camera3D, CameraError, ProjectionKind } from "../void3d/camera";
import { Vec4 } from "../math/math3d";
import {
	ForwardRenderer,
	ForwardError,
	FORWARD_UNIFORM_LENGTH,
	closeForward,
	endPrepared,
} from "../void3d/forwardRenderer";
import { openPrepare } from "../void3d/renderer";
import { contextOf } from "./drawHelpers";

test "a new mask is layer 0 alone, as three's Layers constructor sets it" {
	assert DEFAULT_LAYERS == 1;
	assert layersHas(DEFAULT_LAYERS, 0);
	assert !layersHas(DEFAULT_LAYERS, 1);
	assert ALL_LAYERS == 0xFFFFFFFF;
}

test "layer 31 is a bit of the mask and not a sign" {
	assert layerBit(0) == 1;
	assert layerBit(31) == 0x80000000;
	assert layersHas(layerBit(31), 31);
	assert !layersHas(layerBit(31), 30);
}

test "enable adds a layer, disable removes it, toggle flips it" {
	let mask: uint32 = DEFAULT_LAYERS;
	mask = layersEnable(mask, 3);
	assert mask == 9;
	mask = layersEnable(mask, 3);
	assert mask == 9;
	mask = layersDisable(mask, 0);
	assert mask == 8;
	mask = layersDisable(mask, 0);
	assert mask == 8;
	mask = layersToggle(mask, 3);
	assert mask == 0;
	mask = layersToggle(mask, 31);
	assert mask == 0x80000000;
	mask = layersDisable(mask, 31);
	assert mask == 0;
}

test "two masks see each other when they share at least one layer" {
	assert layersTest(layerBit(2) | layerBit(5), layerBit(5));
	assert !layersTest(layerBit(2), layerBit(5));
	assert !layersTest(0, ALL_LAYERS);
	assert layersTest(ALL_LAYERS, layerBit(31));
}

function request(): Camera3D {
	return {
		position: vec3(0.0, 0.0, 4.0), yaw: 0.0, pitch: 0.0,
		nearPlane: 0.1, farPlane: 40.0,
		projection: { kind: ProjectionKind.Perspective, fovY: 1.0 },
	};
}

// A mesh node under `parent`, drawing the mesh at index `mesh`, so a list tells its items apart.
function meshUnder(scene: Scene3D, context: DrawContext, parent: NodeId3D, mesh: int32): NodeId3D {
	const added: Result<NodeId3D, SceneError> = addMeshNode(
		scene, parent, Transform3D.identity(), context.meshAt(mesh), context.materialAt(0),
	);
	return added.ok ? added.value : NO_NODE_ID;
}

function meshesOf(items: Vec<DrawItem>): int32 {
	let bits: int32 = 0;
	for (const item of items) { bits = bits | (1 << item.mesh.index); }
	return bits;
}

test "a node starts on layer 0 and a layer call changes only that node" {
	const context: DrawContext = contextOf(2, 1);
	const scene: Scene3D = Scene3D.create(context);
	const a: NodeId3D = meshUnder(scene, context, scene.rootId(), 0);
	const b: NodeId3D = meshUnder(scene, context, scene.rootId(), 1);
	assert layersOf(scene, a) == DEFAULT_LAYERS && layersOf(scene, scene.rootId()) == DEFAULT_LAYERS;
	enableLayer(scene, a, 4);
	assert layersOf(scene, a) == 17 && layersOf(scene, b) == 1;
	disableLayer(scene, a, 0);
	assert layersOf(scene, a) == 16;
	toggleLayer(scene, a, 4);
	assert layersOf(scene, a) == 0;
	setLayer(scene, a, 2);
	assert layersOf(scene, a) == 4;
	setLayers(scene, a, ALL_LAYERS);
	assert layersOf(scene, a) == ALL_LAYERS;
}

test "the draw list holds the nodes whose layers meet the camera's, and no camera means layer 0" {
	const context: DrawContext = contextOf(3, 1);
	const scene: Scene3D = Scene3D.create(context);
	const a: NodeId3D = meshUnder(scene, context, scene.rootId(), 0);
	const b: NodeId3D = meshUnder(scene, context, scene.rootId(), 1);
	const c: NodeId3D = meshUnder(scene, context, scene.rootId(), 2);
	setLayer(scene, b, 1);
	setLayers(scene, c, layerBit(0) | layerBit(1));
	let items: Vec<DrawItem> = [];
	assert collectDrawList(scene, items) == 2;
	assert meshesOf(items) == 5;
	const camera: NodeId3D = addCameraNode(scene, null, Transform3D.identity(), request());
	setActiveCamera(scene, camera);
	assert cameraLayersOf(scene, camera) == DEFAULT_LAYERS;
	assert collectDrawList(scene, items) == 2;
	setCameraLayers(scene, camera, layerBit(1));
	assert collectDrawList(scene, items) == 2;
	assert meshesOf(items) == 6;
	setCameraLayers(scene, camera, 0);
	assert collectDrawList(scene, items) == 0;
	setCameraLayers(scene, camera, ALL_LAYERS);
	assert collectDrawList(scene, items) == 3;
}

test "layers are not inherited: a hidden-by-layer group still shows its children" {
	const context: DrawContext = contextOf(3, 1);
	const scene: Scene3D = Scene3D.create(context);
	const group: NodeId3D = addGroup(scene, scene.rootId(), Transform3D.identity());
	const inside: NodeId3D = meshUnder(scene, context, group, 0);
	const apart: NodeId3D = meshUnder(scene, context, group, 1);
	const other: NodeId3D = meshUnder(scene, context, scene.rootId(), 2);
	setLayer(scene, group, 5);
	setLayer(scene, apart, 5);
	setLayer(scene, other, 5);
	let items: Vec<DrawItem> = [];
	assert collectDrawList(scene, items) == 1;
	assert meshesOf(items) == 1;
	setLayers(scene, group, DEFAULT_LAYERS);
	setLayers(scene, inside, layerBit(5));
	setLayers(scene, apart, DEFAULT_LAYERS);
	assert collectDrawList(scene, items) == 1;
	assert meshesOf(items) == 2;
}

test "visible still hides a whole subtree, which a layer never does" {
	const context: DrawContext = contextOf(2, 1);
	const scene: Scene3D = Scene3D.create(context);
	const group: NodeId3D = addGroup(scene, scene.rootId(), Transform3D.identity());
	const inside: NodeId3D = meshUnder(scene, context, group, 0);
	const outside: NodeId3D = meshUnder(scene, context, scene.rootId(), 1);
	setVisible(scene, group, false);
	let items: Vec<DrawItem> = [];
	assert collectDrawList(scene, items) == 1;
	assert meshesOf(items) == 2;
}

test "refresh keeps the layer test on the steady path, and a layer change rebuilds the list" {
	const context: DrawContext = contextOf(2, 1);
	const scene: Scene3D = Scene3D.create(context);
	const a: NodeId3D = meshUnder(scene, context, scene.rootId(), 0);
	const b: NodeId3D = meshUnder(scene, context, scene.rootId(), 1);
	setLayer(scene, b, 3);
	let items: Vec<DrawItem> = [];
	assert refresh(scene, items) == 1;
	setLocal(scene, a, Transform3D.fromTranslation(vec3(2.0, 0.0, 0.0)));
	assert refresh(scene, items) == 1;
	assert items[0].world.m41 == 2.0;
	assert !scene.structureChanged;
	enableLayer(scene, b, 0);
	assert scene.structureChanged;
	assert refresh(scene, items) == 2;
	setLayer(scene, a, 3);
	assert refresh(scene, items) == 1;
	assert meshesOf(items) == 2;
	const camera: NodeId3D = addCameraNode(scene, null, Transform3D.identity(), request());
	setActiveCamera(scene, camera);
	setCameraLayers(scene, camera, layerBit(3));
	assert refresh(scene, items) == 2;
	setActiveCamera(scene, null);
	assert refresh(scene, items) == 1;
}

test "a second camera collects its own list and leaves the first one's alone" {
	const context: DrawContext = contextOf(3, 1);
	const scene: Scene3D = Scene3D.create(context);
	const a: NodeId3D = meshUnder(scene, context, scene.rootId(), 0);
	const b: NodeId3D = meshUnder(scene, context, scene.rootId(), 1);
	const c: NodeId3D = meshUnder(scene, context, scene.rootId(), 2);
	setLayer(scene, b, 1);
	setLayer(scene, c, 1);
	const main: NodeId3D = addCameraNode(scene, null, Transform3D.identity(), request());
	const second: NodeId3D = addCameraNode(scene, null, Transform3D.identity(), request());
	setActiveCamera(scene, main);
	setCameraLayers(scene, second, layerBit(1));
	let first: Vec<DrawItem> = [];
	let overlay: Vec<DrawItem> = [];
	assert refresh(scene, first) == 1;
	assert refreshFor(scene, second, overlay) == 2;
	assert meshesOf(first) == 1 && meshesOf(overlay) == 6;
	assert !scene.structureChanged;
	setLocal(scene, b, Transform3D.fromTranslation(vec3(0.0, 3.0, 0.0)));
	assert refresh(scene, first) == 1;
	assert refreshFor(scene, second, overlay) == 2;
	assert overlay[0].world.m42 == 3.0;
	assert collectDrawListFor(scene, main, overlay) == 1;
	assert !scene.structureChanged;
}

test "the second camera's view is resolved from its own node and not the active one's" {
	const scene: Scene3D = Scene3D.create(DrawContext.withUniformCapacity(0));
	const main: NodeId3D = addCameraNode(
		scene, scene.rootId(), Transform3D.fromTranslation(vec3(1.0, 0.0, 0.0)), request(),
	);
	const second: NodeId3D = addCameraNode(
		scene, scene.rootId(), Transform3D.fromTranslation(vec3(0.0, 7.0, 0.0)), request(),
	);
	setActiveCamera(scene, main);
	const seen: Result<Camera3D, CameraError> = cameraViewOf(scene, second);
	assert seen.ok;
	if (seen.ok) { assert seen.value.position == vec3(0.0, 7.0, 0.0); }
	const active: Result<Camera3D, CameraError> = cameraOf(scene, request());
	assert active.ok;
	if (active.ok) { assert active.value.position == vec3(1.0, 0.0, 0.0); }
}

const OPAQUE_BLACK: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };
const CLEAR: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 0.0 };

test "a second forward preset on one context has its own blocks and a transparent clear" {
	const context: DrawContext = DrawContext.withUniformCapacity(2 * FORWARD_UNIFORM_LENGTH);
	const first: Result<ForwardRenderer, ForwardError> =
		ForwardRenderer.create(context, OPAQUE_BLACK);
	const second: Result<ForwardRenderer, ForwardError> = ForwardRenderer.create(context, CLEAR);
	assert first.ok && second.ok;
	if (first.ok && second.ok) {
		assert second.value.background.w == 0.0 && first.value.background.w == 1.0;
		assert second.value.core.cameraBlock.offset != first.value.core.cameraBlock.offset;
		assert second.value.colorTarget.sampled;
		assert second.value.copyMaterial.index != first.value.copyMaterial.index;
		closeForward(second.value);
		closeForward(first.value);
	}
}

test "a prepared frame the caller composites itself is ended, and the next prepare is allowed" {
	const context: DrawContext = DrawContext.withUniformCapacity(2 * FORWARD_UNIFORM_LENGTH);
	const second: Result<ForwardRenderer, ForwardError> = ForwardRenderer.create(context, CLEAR);
	assert second.ok;
	if (!second.ok) { return; }
	let overlay: ForwardRenderer = second.value;
	overlay.core.prepared = true;
	endPrepared(overlay);
	assert !overlay.core.prepared;
	overlay.core.openPrepare();
	closeForward(overlay);
}

test "a pool sized for one forward preset refuses the second by name" {
	const context: DrawContext = DrawContext.withUniformCapacity(FORWARD_UNIFORM_LENGTH);
	const first: Result<ForwardRenderer, ForwardError> =
		ForwardRenderer.create(context, OPAQUE_BLACK);
	assert first.ok;
	const second: Result<ForwardRenderer, ForwardError> = ForwardRenderer.create(context, CLEAR);
	assert !second.ok;
	if (!second.ok) { assert second.error == ForwardError.UniformPoolFull; }
	if (first.ok) { closeForward(first.value); }
}

function lightOf(kind: LightKind): LightInstance {
	return { kind: kind, color: vec3(1.0, 1.0, 1.0), radius: 5.0, power: 1.0, priority: 0 };
}

function lightOn(scene: Scene3D, parent: NodeId3D, kind: LightKind, layer: int32): NodeId3D {
	const id: NodeId3D = addLightNode(scene, parent, Transform3D.identity(), lightOf(kind));
	setLayer(scene, id, layer);
	return id;
}

test "a directional light on another layer is not the camera's second directional" {
	const scene: Scene3D = Scene3D.create(DrawContext.withUniformCapacity(0));
	const _sun: NodeId3D = lightOn(scene, scene.rootId(), LightKind.Directional, 0);
	const _lamp: NodeId3D = lightOn(scene, scene.rootId(), LightKind.Directional, 1);
	let block: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
	const main: Result<int32, LightError> = collectLightsFor(scene, layerBit(0), block);
	assert main.ok;
	const overlay: Result<int32, LightError> = collectLightsFor(scene, layerBit(1), block);
	assert overlay.ok;
	const both: Result<int32, LightError> = collectLightsFor(scene, ALL_LAYERS, block);
	assert !both.ok;
	if (!both.ok) { assert both.error == LightError.TooManyDirectionalLights; }
	const none: Result<int32, LightError> = collectLightsFor(scene, layerBit(9), block);
	assert none.ok && block[7] == 0.0;
}

test "a layer-1 camera is lit by its own directional alone" {
	const scene: Scene3D = Scene3D.create(DrawContext.withUniformCapacity(0));
	const sun: NodeId3D = lightOn(scene, scene.rootId(), LightKind.Directional, 0);
	const lamp: NodeId3D = lightOn(scene, scene.rootId(), LightKind.Directional, 1);
	const camera: NodeId3D = addCameraNode(scene, scene.rootId(), Transform3D.identity(), request());
	let block: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
	setLightPower(scene, sun, 0.25);
	setLightPower(scene, lamp, 0.75);
	setActiveCamera(scene, camera);
	assert collectLights(scene, block).ok && block[7] == 0.25;
	setCameraLayers(scene, camera, layerBit(1));
	assert collectLights(scene, block).ok && block[7] == 0.75;
}

test "a light on another layer does not stop its children being walked, or count as a fifth point" {
	const scene: Scene3D = Scene3D.create(DrawContext.withUniformCapacity(0));
	const off: NodeId3D = lightOn(scene, scene.rootId(), LightKind.Point, 1);
	for (let i = 0; i < MAX_POINT_LIGHTS; i++) {
		const _point: NodeId3D = lightOn(scene, off, LightKind.Point, 0);
	}
	let block: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
	const lit: Result<int32, LightError> = collectLightsFor(scene, layerBit(0), block);
	assert lit.ok;
	if (lit.ok) { assert lit.value == MAX_POINT_LIGHTS; }
	const over: Result<int32, LightError> = collectLightsFor(scene, ALL_LAYERS, block);
	assert !over.ok;
	if (!over.ok) { assert over.error == LightError.TooManyPointLights; }
}

test "setLayers on a camera node is the node's own mask and not what the camera draws" {
	const scene: Scene3D = Scene3D.create(DrawContext.withUniformCapacity(0));
	const camera: NodeId3D = addCameraNode(scene, scene.rootId(), Transform3D.identity(), request());
	setLayers(scene, camera, layerBit(5));
	assert layersOf(scene, camera) == layerBit(5);
	assert cameraLayersOf(scene, camera) == DEFAULT_LAYERS;
}

test "the composite of a second view is a premultiplied textured material over, and straight is refused" {
	let context: DrawContext = DrawContext.withUniformCapacity(0);
	const over: RenderState = RenderState.defaults().withBlendMode(BlendMode.AlphaAdd);
	for (const program of [Program.UnlitTextured, Program.LitTextured]) {
		const kept: Result<MaterialId, MaterialError> = addMaterial(context, Material.keyed(
			ProgramKey.of(program).withPremultiplied(), over, Phase.Alpha,
		));
		assert kept.ok;
	}
	const straight: Result<MaterialId, MaterialError> = addMaterial(context, Material.keyed(
		ProgramKey.of(Program.UnlitTextured).withPremultiplied(),
		RenderState.defaults().withBlendMode(BlendMode.Alpha), Phase.Alpha,
	));
	assert !straight.ok && straight.error == MaterialError.StraightBlend;
}
