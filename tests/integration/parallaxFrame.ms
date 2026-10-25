import { gfxSetup, fbWidth, fbHeight } from "../../src/sokol/gpu";
import { Vec3, Vec4, vec3, quatBetween } from "../../src/math/math3d";
import { RenderState, FilterMode, Wrap } from "../../src/gpu/state";
import { Material, Phase, UniformBlock, pbrBlock } from "../../src/void3d/material";
import { PbrResponseError } from "../../src/void3d/pbrResponse";
import { MeshData, MeshError, Rgba, addTexturedQuad, addTangents } from "../../src/void3d/meshData";
import { TextureData, TextureId, TextureUploadError } from "../../src/void3d/texture";
import {
	Program, ProgramKey, MATERIAL_UNIFORM_SLOT, MATERIAL_PARALLAX, VERTEX_UNIFORM_LENGTH,
	LIGHT_UNIFORM_LENGTH, PBR_MATERIAL_UNIFORM_LENGTH,
} from "../../src/void3d/gpu3d";
import {
	DrawContext, DrawItem, MeshId, MaterialId, MeshUploadError, MaterialError,
	addMeshData, addMaterial, addTexture, reserveUniforms, writeUniforms,
} from "../../src/void3d/draw";
import { UniformError } from "../../src/void3d/uniformPool";
import {
	Scene3D, Transform3D, NodeId3D, SceneError, LightError, LightInstance, LightKind,
	addMeshNode, addLightNode, setAmbient, refresh, collectLights,
} from "../../src/void3d/scene";
import { Camera3D, CameraView, CameraError, ProjectionKind } from "../../src/void3d/camera";
import { LowResView } from "../../src/void3d/blit";
import { setCameraView, setCameraPosition } from "../../src/void3d/renderer";
import {
	ForwardRenderer, ForwardError, FORWARD_UNIFORM_LENGTH, renderFrame as renderForward,
} from "../../src/void3d/forwardRenderer";
import {
	voidCaptureBackend, voidCaptureGrab, voidCapturePixel, voidCaptureEnvInt, voidCaptureExit,
} from "../capture/capture.h";

@include("../../src/sokol/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, sampleCount: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

const WIDTH: int32 = 320;
const HEIGHT: int32 = 240;
const WORLD_PER_TEXEL: float32 = 0.02;
const GREY: Vec4 = { x: 0.2, y: 0.2, z: 0.2, w: 1.0 };
const WHITE: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };
const SCREEN: LowResView = { width: 320, height: 240, scale: 1, offsetX: 0.0, offsetY: 0.0 };
const HALF: float32 = 1.0;
const EYE: Vec3 = { x: 0.0, y: 4.0, z: 4.0 };
// 0xAABBGGRR texels: the base is red at v 0 and blue at v 1, so its edge runs along z = 0. The
// pbr-maps texel holds roughness 1 and metalness 0, and in alpha a height of one half.
const RED: uint32 = 0xFF0000FF;
const BLUE: uint32 = 0xFFFF0000;
const HALF_HEIGHT: uint32 = 0x8000FF00;
const FLAT_NORMAL: uint32 = 0xFFFF8080;
// Seen from EYE the view leans toward +z as much as up, so at a depth of one half the UV steps
// back by half the amount along v: 0.2 of v, 0.4 of z on the quad.
const AMOUNT: float32 = 0.4;
const FRAMES: int32 = 3;
let control: boolean = voidCaptureEnvInt("VOID_PARALLAX_CONTROL", 0) != 0;
let context: DrawContext = DrawContext.withUniformCapacity(
	FORWARD_UNIFORM_LENGTH + PBR_MATERIAL_UNIFORM_LENGTH,
);
let scene: Scene3D = Scene3D.create(context);
let forward: ForwardRenderer = makeForward();
let items: Vec<DrawItem> = [];
let cameraValues: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let stage: int32 = 0;

function fail(message: string): void {
	const mode: string = control ? " control" : "";
	console.log(`FAIL parallax:${mode} stage ${stage}: ${message}`);
	voidCaptureExit(1);
}

function makeForward(): ForwardRenderer {
	const made: Result<ForwardRenderer, ForwardError> = ForwardRenderer.create(context, GREY);
	if (made.ok) { return made.value; }
	unreachable;
}

function texture(pixels: Vec<uint32>, height: int32): TextureId {
	const data: TextureData = {
		pixels: pixels, width: 1, height: height, filter: FilterMode.Nearest, wrap: Wrap.Clamp,
	};
	const uploaded: Result<TextureId, TextureUploadError> = addTexture(context, data);
	if (uploaded.ok) { return uploaded.value; }
	unreachable;
}

// The control draws the same key at amount 0, so only the amount moves the edge.
function material(): MaterialId {
	const key: ProgramKey = ProgramKey.of(Program.LitTextured).withPbr().withPbrMaps()
		.withNormalMap().withParallax();
	const values: Result<Vec<float32>, PbrResponseError> =
		pbrBlock(key, { metalness: 0.0, roughness: 1.0, occlusion: 1.0 });
	if (!values.ok) { unreachable; }
	let block: Vec<float32> = values.value;
	block[MATERIAL_PARALLAX] = control ? 0.0 : AMOUNT;
	const reserved: Result<UniformBlock, UniformError> =
		reserveUniforms(context, MATERIAL_UNIFORM_SLOT, PBR_MATERIAL_UNIFORM_LENGTH);
	if (!reserved.ok) { unreachable; }
	if (!writeUniforms(context, reserved.value, block).ok) { unreachable; }
	const white: TextureId = texture([0xFFFFFFFF], 1);
	const added: Result<MaterialId, MaterialError> = addMaterial(context, {
		...Material.keyed(key, RenderState.defaults(), Phase.Opaque),
		texture: texture([RED, BLUE], 2),
		normalTexture: texture([FLAT_NORMAL], 1),
		metalRoughTexture: texture([HALF_HEIGHT], 1),
		occlusionTexture: white,
		uniforms: reserved.value,
	});
	if (added.ok) { return added.value; }
	fail(`the parallax material was refused: ${added.error.toString()}`);
	unreachable;
}

function init(): void {
	if (voidCaptureBackend() == 0) { voidCaptureExit(3); }
	gfxSetup();
	let mesh: MeshData = MeshData.withUvs();
	const built: Result<int32, MeshError> = addTexturedQuad(
		mesh, vec3(-HALF, 0.0, HALF), vec3(HALF, 0.0, HALF), vec3(HALF, 0.0, -HALF),
		vec3(-HALF, 0.0, -HALF), vec3(0.0, 1.0, 0.0), WHITE,
	);
	if (!built.ok || !addTangents(mesh).ok) { unreachable; }
	const uploaded: Result<MeshId, MeshUploadError> = addMeshData(context, mesh);
	if (!uploaded.ok) { unreachable; }
	const placed: Result<NodeId3D, SceneError> = addMeshNode(
		scene, scene.rootId(), Transform3D.identity(), uploaded.value, material(),
	);
	if (!placed.ok) { unreachable; }
	const sun: LightInstance = {
		kind: LightKind.Directional, color: vec3(1.0, 1.0, 1.0),
		radius: 0.0, power: 1.0, priority: 0,
	};
	const _sun: NodeId3D = addLightNode(scene, scene.rootId(), {
		...Transform3D.identity(),
		rotation: quatBetween(vec3(0.0, 0.0, 1.0), vec3(0.0, -1.0, 0.0)),
	}, sun);
	setAmbient(scene, vec3(0.3, 0.3, 0.3));
}

function viewOf(): CameraView {
	const camera: Camera3D = {
		position: EYE, yaw: 0.0, pitch: 0.785398, nearPlane: 0.1, farPlane: 20.0,
		projection: {
			kind: ProjectionKind.Orthographic, worldPerTexel: WORLD_PER_TEXEL, snap: false,
		},
	};
	const view: Result<CameraView, CameraError> = camera.resolve(WIDTH, HEIGHT);
	if (view.ok) { return view.value; }
	unreachable;
}

// Whether the quad at z reads the base's blue half, from the pixel's blue against its red.
function blueAt(view: CameraView, z: float32): boolean {
	const at: Vec3 = view.project(vec3(0.0, 0.0, z), SCREEN, true);
	const rgb: int64 = voidCapturePixel(0, at.x as int32, at.y as int32) >> 8;
	return (rgb & 0xFF) > ((rgb >> 16) & 0xFF);
}

// The edge sits at z 0 in the control; parallax moves it to about z 0.4, so z 0.2 turns red
// while -0.2 and 0.6 keep their side.
function check(view: CameraView): void {
	const behind: boolean = blueAt(view, -0.2);
	const between: boolean = blueAt(view, 0.2);
	const beyond: boolean = blueAt(view, 0.6);
	console.log(`parallax: blue at -0.2 ${behind}, 0.2 ${between}, 0.6 ${beyond}`);
	if (behind) { fail("z -0.2 read the blue half"); }
	if (!beyond) { fail("z 0.6 read the red half"); }
	if (control && !between) { fail("without parallax z 0.2 read the red half"); }
	if (!control && between) { fail("with parallax z 0.2 still read the blue half"); }
}

function frame(): void {
	if (fbWidth() != WIDTH || fbHeight() != HEIGHT) { fail("the framebuffer size changed"); }
	if (refresh(scene, items) != 1) { fail("the scene lost its mesh"); }
	const collected: Result<int32, LightError> = collectLights(scene, lights);
	if (!collected.ok) { unreachable; }
	const view: CameraView = viewOf();
	view.writeCameraBlock(cameraValues);
	setCameraView(forward.core, view);
	setCameraPosition(forward.core, EYE);
	const drawn: Result<int32, ForwardError> =
		renderForward(forward, items, cameraValues, lights, WIDTH, HEIGHT);
	if (!drawn.ok) { fail(`forward refused: ${drawn.error.toString()}`); }
	if (voidCaptureGrab(0) == 0) { fail("readback failed"); }
	check(view);
	stage = stage + 1;
	if (stage < FRAMES) { return; }
	console.log(`PASS parallax${control ? " control" : ""}`);
	voidCaptureExit(0);
}

voidRunConfigured(WIDTH, HEIGHT, 1, 0, init, frame);
