import { Scene2D } from "../../src/void2d/node";
import { add } from "../../src/void2d/scene";
import { Color, tile } from "../../src/void2d/types";
import { Vec4, vec3 } from "../../src/math/math3d";
import { RenderState } from "../../src/gpu/state";
import { RenderTarget } from "../../src/gpu/target";
import {
	Program,
	MATERIAL_UNIFORM_SLOT,
	MATERIAL_UNIFORM_LENGTH,
	VERTEX_UNIFORM_LENGTH,
	LIGHT_UNIFORM_LENGTH,
} from "../../src/void3d/gpu3d";
import { Material, Phase, UniformBlock } from "../../src/void3d/material";
import { MeshData, MeshError, Rgba, addBox } from "../../src/void3d/meshData";
import { UniformError } from "../../src/void3d/uniformPool";
import {
	DrawContext,
	DrawItem,
	MeshId,
	MaterialId,
	MaterialError,
	MeshUploadError,
	addMeshData,
	addMaterial,
	reserveUniforms,
	writeUniforms,
} from "../../src/void3d/draw";
import {
	Transform3D,
	Scene3D,
	NodeId3D,
	SceneError,
	LightError,
	LightKind,
	LightInstance,
	addMeshNode,
	addLightNode,
	refresh,
	collectLights,
} from "../../src/void3d/scene";
import { Camera3D, ProjectionKind, CameraView, CameraError } from "../../src/void3d/camera";
import {
	ForwardRenderer,
	ForwardError,
	FORWARD_UNIFORM_LENGTH,
	prepareFrame,
} from "../../src/void3d/forwardRenderer";

const TARGET_WIDTH: int32 = 160;
const TARGET_HEIGHT: int32 = 120;
const TARGET_X: float32 = 48.0;
const TARGET_Y: float32 = 20.0;
const WORLD_ON_HEIGHT: float32 = 3.0;
const BACKGROUND_3D: Vec4 = { x: 0.10, y: 0.14, z: 0.24, w: 1.0 };
const CLEAR_2D: Color = { r: 0.08, g: 0.09, b: 0.12, a: 1.0 };
const HIGH_BOX: Rgba = { red: 0.95, green: 0.55, blue: 0.2, alpha: 1.0 };
const LOW_BOX: Rgba = { red: 0.2, green: 0.75, blue: 0.6, alpha: 1.0 };

let context: DrawContext = DrawContext.withUniformCapacity(
	FORWARD_UNIFORM_LENGTH + MATERIAL_UNIFORM_LENGTH,
);
let forward: ForwardRenderer = createForward();
let scene: Scene3D = Scene3D.create();
let items: Vec<DrawItem> = [];
let camera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);

function createForward(): ForwardRenderer {
	const created: Result<ForwardRenderer, ForwardError> =
		ForwardRenderer.create(context, BACKGROUND_3D);
	if (created.ok) { return created.value; }
	unreachable;
}

function litMaterial(): MaterialId {
	const reserved: Result<UniformBlock, UniformError> =
		reserveUniforms(context, MATERIAL_UNIFORM_SLOT, MATERIAL_UNIFORM_LENGTH);
	if (!reserved.ok) { unreachable; }
	const levels: Vec<float32> = [4.0, 0.0, 0.0, 0.0];
	const written: Result<int32, UniformError> = writeUniforms(context, reserved.value, levels);
	if (!written.ok) { unreachable; }
	const plain: Material = Material.plain(Program.Lit, RenderState.defaults(), Phase.Opaque);
	const added: Result<MaterialId, MaterialError> =
		addMaterial(context, { ...plain, uniforms: reserved.value });
	if (!added.ok) { unreachable; }
	return added.value;
}

function twoBoxes(): MeshData {
	let data: MeshData = MeshData.empty();
	const high: Result<int32, MeshError> = addBox(data, {
		base: vec3(-0.7, 0.3, 0.0),
		size: vec3(0.8, 0.8, 0.8),
		yaw: 0.6,
		tilt: 0.0,
		color: HIGH_BOX,
	});
	if (!high.ok) { unreachable; }
	const low: Result<int32, MeshError> = addBox(data, {
		base: vec3(0.6, -1.2, 0.0),
		size: vec3(0.6, 0.5, 0.6),
		yaw: 0.2,
		tilt: 0.0,
		color: LOW_BOX,
	});
	if (!low.ok) { unreachable; }
	return data;
}

function buildBoxes(): void {
	const mesh: Result<MeshId, MeshUploadError> = addMeshData(context, twoBoxes());
	if (!mesh.ok) { unreachable; }
	const material: MaterialId = litMaterial();
	const placed: Result<NodeId3D, SceneError> =
		addMeshNode(scene, context, scene.rootId(), Transform3D.identity(), mesh.value, material);
	if (!placed.ok) { unreachable; }
	const sun: LightInstance = {
		kind: LightKind.Directional,
		color: vec3(1.0, 1.0, 1.0),
		radius: 0.0,
		power: 1.0,
		priority: 0,
	};
	const _lit: NodeId3D = addLightNode(scene, scene.rootId(), Transform3D.identity(), sun);
	const _drawn: int32 = refresh(scene, items);
	const collected: Result<int32, LightError> = collectLights(scene, lights);
	if (!collected.ok) { unreachable; }
	const view: Camera3D = {
		position: vec3(0.0, 0.0, 0.0),
		yaw: 0.5,
		pitch: 0.5,
		projection: {
			kind: ProjectionKind.Orthographic,
			worldPerTexel: WORLD_ON_HEIGHT / (TARGET_HEIGHT as float32),
			snap: false,
		},
		nearPlane: -10.0,
		farPlane: 10.0,
	};
	const resolved: Result<CameraView, CameraError> = view.resolve(TARGET_WIDTH, TARGET_HEIGHT);
	if (!resolved.ok) { unreachable; }
	resolved.value.writeCameraBlock(camera);
}

export function mixedVoid3dTarget(): Scene2D {
	buildBoxes();
	const prepared: Result<int32, ForwardError> =
		prepareFrame(forward, context, items, camera, lights, TARGET_WIDTH, TARGET_HEIGHT);
	if (!prepared.ok) {
		console.log(`FAIL mixed/void3dTarget: the 3D frame was refused, ${prepared.error.toString()}`);
		unreachable;
	}
	const s = Scene2D.create(CLEAR_2D);
	const view = tile(
		forward.colorTarget.asTexture(),
		TARGET_WIDTH as float32,
		TARGET_HEIGHT as float32,
	).premultiplied();
	s.add(s.sprite(view).at(TARGET_X, TARGET_Y));
	return s;
}
