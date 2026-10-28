// Heaps' samples/Sao.hx on the core: the scene into a colour, a normal and a depth target, SAO
// over the depth and the normals, Blur over the occlusion, then the colour copied to the screen
// and the occlusion copied over it with Multiply. A box on a floor: the floor at the box's foot
// darkens, the open floor and the box's top keep their colour.

import { gfxSetup, fbWidth, fbHeight } from "../../src/sokol/gpu";
import { Vec3, Vec4, vec3, translation } from "../../src/math/math3d";
import { RenderState, BlendMode, Face, FilterMode, Wrap } from "../../src/gpu/state";
import { PixelFormat, LoadAction, StoreAction, endPass, commit } from "../../src/gpu/door";
import {
	RenderTarget,
	ColorAttachment,
	DepthAttachment,
	Sampler,
	SWAPCHAIN_LAYOUT,
	beginPass,
	beginScreenPass,
} from "../../src/gpu/target";
import { MeshData, MeshError, Rgba, addQuad, addTexturedQuad } from "../../src/void3d/meshData";
import { Material, Phase, UniformBlock } from "../../src/void3d/material";
import { TextureData, TextureId, TextureUploadError } from "../../src/void3d/texture";
import {
	Program,
	MATERIAL_UNIFORM_SLOT,
	UNLIT_MATERIAL_UNIFORM_LENGTH,
	UNLIT_MATERIAL_COLOR,
	VERTEX_UNIFORM_LENGTH,
	LIGHT_UNIFORM_LENGTH,
	SAO_UNIFORM_LENGTH,
} from "../../src/void3d/gpu3d";
import {
	DrawContext,
	DrawItem,
	MeshId,
	MaterialId,
	MaterialError,
	MeshUploadError,
	addMeshData,
	addMaterial,
	addTexture,
	reserveUniforms,
	writeUniforms,
} from "../../src/void3d/draw";
import { UniformError } from "../../src/void3d/uniformPool";
import {
	Renderer,
	RendererError,
	RENDERER_UNIFORM_LENGTH,
	beginFrame,
	drawPhase,
	drawScreen,
	closePrepare,
	openScreen,
} from "../../src/void3d/renderer";
import { screenState } from "../../src/void3d/screenFx";
import { OUTLINE_SCENE_LAYOUT } from "../../src/void3d/forwardOutline";
import { Camera3D, CameraView, CameraError, ProjectionKind } from "../../src/void3d/camera";
import { LowResView } from "../../src/void3d/blit";
import { ScalableAoPass, ScalableAoSettings } from "../../src/void3d/sao";
import { BlurPass, BlurSettings, BLUR_UNIFORM_LENGTH } from "../../src/void3d/blur";
import {
	voidCaptureBackend, voidCaptureGrab, voidCapturePixel, voidCaptureExit,
} from "../capture/capture.h";

@include("../../src/sokol/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, sampleCount: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

const WIDTH: int32 = 320;
const HEIGHT: int32 = 240;
const SCREEN: LowResView = { width: WIDTH, height: HEIGHT, scale: 1, offsetX: 0.0, offsetY: 0.0 };
const TOLERANCE: float32 = 3.0;
const SHADE: float32 = 0.6;
const GREY: Vec4 = { x: 0.2, y: 0.2, z: 0.2, w: 1.0 };
const NORMAL_CLEAR: Vec4 = { x: 0.5, y: 0.5, z: 0.5, w: 0.0 };
const WHITE: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };
const FRAMES: int32 = 3;

let context: DrawContext = DrawContext.withUniformCapacity(
	RENDERER_UNIFORM_LENGTH + UNLIT_MATERIAL_UNIFORM_LENGTH + SAO_UNIFORM_LENGTH +
		BLUR_UNIFORM_LENGTH,
);
let core: Renderer = makeCore();
let sao: ScalableAoPass = ScalableAoPass.reserve(context);
let blur: BlurPass = BlurPass.reserve(context, BlurSettings.defaults());
let copy: MaterialId = added(Material.plain(Program.Copy, screenState(), Phase.Opaque));
let multiply: MaterialId = added(Material.plain(
	Program.Copy, screenState().withBlendMode(BlendMode.Multiply), Phase.Opaque,
));
let lit: RenderTarget = RenderTarget.unallocated(PixelFormat.Rgba8, true);
let normal: RenderTarget = RenderTarget.unallocated(PixelFormat.Rgba8, true);
let depth: RenderTarget = RenderTarget.unallocated(PixelFormat.Depth, true);
let pointSampler: Sampler =
	{ filter: FilterMode.Nearest, wrap: Wrap.Clamp, handle: 0, generation: 0 };
let sceneColors: Vec<ColorAttachment> = new Array(2);
let items: Vec<DrawItem> = [];
let cameraValues: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let frames: int32 = 0;

function fail(message: string): void {
	console.log(`FAIL sao: ${message}`);
	voidCaptureExit(1);
}

function makeCore(): Renderer {
	const made: Result<Renderer, RendererError> = Renderer.create(context);
	if (made.ok) { return made.value; }
	unreachable;
}

function added(material: Material): MaterialId {
	const id: Result<MaterialId, MaterialError> = addMaterial(context, material);
	if (id.ok) { return id.value; }
	fail(`a material was refused: ${id.error.toString()}`);
	unreachable;
}

function upload(data: MeshData): MeshId {
	const uploaded: Result<MeshId, MeshUploadError> = addMeshData(context, data);
	if (uploaded.ok) { return uploaded.value; }
	unreachable;
}

function face(ref data: MeshData, a: Vec3, b: Vec3, c: Vec3, d: Vec3, toward: Vec3): void {
	if (!addQuad(data, a, b, c, d, toward, WHITE).ok) { unreachable; }
}

function floor(): MeshId {
	let data: MeshData = MeshData.withUvs();
	const built: Result<int32, MeshError> = addTexturedQuad(
		data, vec3(-6.0, 0.0, 6.0), vec3(6.0, 0.0, 6.0), vec3(6.0, 0.0, -6.0),
		vec3(-6.0, 0.0, -6.0), vec3(0.0, 1.0, 0.0), WHITE,
	);
	if (!built.ok) { unreachable; }
	return upload(data);
}

// A unit box standing on the floor, every face wound outward.
function box(): MeshId {
	let data: MeshData = MeshData.withUvs();
	const lo: float32 = -0.5;
	const hi: float32 = 0.5;
	face(data, vec3(lo, 0.0, hi), vec3(hi, 0.0, hi), vec3(hi, 1.0, hi), vec3(lo, 1.0, hi),
		vec3(0.0, 0.0, 1.0));
	face(data, vec3(hi, 0.0, lo), vec3(lo, 0.0, lo), vec3(lo, 1.0, lo), vec3(hi, 1.0, lo),
		vec3(0.0, 0.0, -1.0));
	face(data, vec3(hi, 0.0, hi), vec3(hi, 0.0, lo), vec3(hi, 1.0, lo), vec3(hi, 1.0, hi),
		vec3(1.0, 0.0, 0.0));
	face(data, vec3(lo, 0.0, lo), vec3(lo, 0.0, hi), vec3(lo, 1.0, hi), vec3(lo, 1.0, lo),
		vec3(-1.0, 0.0, 0.0));
	face(data, vec3(lo, 1.0, hi), vec3(hi, 1.0, hi), vec3(hi, 1.0, lo), vec3(lo, 1.0, lo),
		vec3(0.0, 1.0, 0.0));
	return upload(data);
}

function white(): TextureId {
	const data: TextureData = {
		pixels: [0xFFFFFFFF], width: 1, height: 1, filter: FilterMode.Nearest, wrap: Wrap.Clamp,
	};
	const uploaded: Result<TextureId, TextureUploadError> = addTexture(context, data);
	if (uploaded.ok) { return uploaded.value; }
	unreachable;
}

function shaded(texture: TextureId): MaterialId {
	let values: Vec<float32> = new Array(UNLIT_MATERIAL_UNIFORM_LENGTH);
	for (let i = 0; i < 4; i++) { values[UNLIT_MATERIAL_COLOR + i] = i == 3 ? 1.0 : SHADE; }
	const block: Result<UniformBlock, UniformError> =
		reserveUniforms(context, MATERIAL_UNIFORM_SLOT, UNLIT_MATERIAL_UNIFORM_LENGTH);
	if (!block.ok) { unreachable; }
	if (!writeUniforms(context, block.value, values).ok) { unreachable; }
	const state: RenderState = RenderState.defaults().withCulling(Face.None);
	return added({
		...Material.plain(Program.UnlitTextured, state, Phase.Opaque),
		texture: texture, uniforms: block.value,
	});
}

function camera(): Camera3D {
	return {
		position: vec3(0.0, 3.0, 4.0), yaw: 0.0, pitch: 0.6435011, orientation: null,
		nearPlane: 0.5, farPlane: 20.0,
		projection: { kind: ProjectionKind.Perspective, fovY: 1.0471976 },
	};
}

function viewOf(): CameraView {
	const view: Result<CameraView, CameraError> = camera().resolve(WIDTH, HEIGHT);
	if (view.ok) { return view.value; }
	unreachable;
}

function init(): void {
	if (voidCaptureBackend() == 0) { voidCaptureExit(3); }
	gfxSetup();
	const material: MaterialId = shaded(white());
	items.push({ mesh: floor(), material: material, world: translation(0.0, 0.0, 0.0), order: 0 });
	items.push({ mesh: box(), material: material, world: translation(0.0, 0.0, 0.0), order: 0 });
	const settings: ScalableAoSettings = { ...ScalableAoSettings.defaults(), sampleRadius: 0.5 };
	sao.setSettings(settings);
}

function green(point: Vec3): float32 {
	const at: Vec3 = viewOf().project(point, SCREEN, true);
	return ((voidCapturePixel(0, at.x as int32, at.y as int32) >> 16) & 255) as float32;
}

function check(): void {
	const open: float32 = green(vec3(1.8, 0.0, 2.2));
	const top: float32 = green(vec3(0.0, 1.0, 0.0));
	const foot: float32 = green(vec3(0.0, 0.0, 0.6));
	if (open < 60.0) { fail(`the open floor drew ${open}, too dark to see occlusion on`); }
	if (Math.abs(top - open) > TOLERANCE) {
		fail(`the box's top drew ${top} and the open floor ${open}; neither is occluded`);
	}
	if (foot > open * 0.85) {
		fail(`the floor at the box's foot drew ${foot}, not darker than the open floor ${open}`);
	}
	console.log(`sao: open floor ${open}, box top ${top}, the box's foot ${foot}`);
}

function frame(): void {
	if (fbWidth() != WIDTH || fbHeight() != HEIGHT) { fail("the framebuffer size changed"); }
	const view: CameraView = viewOf();
	view.writeCameraBlock(cameraValues);
	core.normalMrt = true;
	const began: Result<boolean, RendererError> = beginFrame(core, items, cameraValues, lights);
	if (!began.ok) {
		fail(`beginFrame refused: ${began.error.toString()}`);
		return;
	}
	if (began.value || pointSampler.handle == 0) {
		pointSampler = Sampler.create(FilterMode.Nearest, Wrap.Clamp);
		sao.adoptContext();
		blur.adoptContext();
	}
	lit.resize(WIDTH, HEIGHT);
	normal.resize(WIDTH, HEIGHT);
	depth.resize(WIDTH, HEIGHT);
	sao.resize(WIDTH, HEIGHT);
	sceneColors[0] = lit.asColor(LoadAction.Clear, GREY);
	sceneColors[1] = normal.asColor(LoadAction.Clear, NORMAL_CLEAR);
	const sceneDepth: DepthAttachment = depth.asDepth(LoadAction.Clear, 1.0, StoreAction.Store);
	beginPass(sceneColors, sceneDepth);
	drawPhase(core, Phase.Opaque, items, OUTLINE_SCENE_LAYOUT);
	endPass();
	closePrepare(core);
	sao.draw(core, depth, normal, camera(), view);
	blur.draw(core, sao.occlusion);
	context.materials[copy.index].texture0 = lit.asTexture();
	context.materials[copy.index].sampler0 = pointSampler.asHandle();
	context.materials[multiply.index].texture0 = sao.occlusion.asTexture();
	context.materials[multiply.index].sampler0 = pointSampler.asHandle();
	beginScreenPass(GREY);
	openScreen(core);
	if (!drawScreen(core, copy, SWAPCHAIN_LAYOUT).ok) { fail("the colour copy was refused"); }
	if (!drawScreen(core, multiply, SWAPCHAIN_LAYOUT).ok) { fail("the Multiply copy was refused"); }
	endPass();
	commit();
	frames = frames + 1;
	if (frames < FRAMES) { return; }
	if (voidCaptureGrab(0) == 0) { fail("readback failed"); }
	check();
	console.log("PASS sao: SAO over the scene's depth and normals, blurred and multiplied over " +
		"its colour, darkens the floor at the box's foot and leaves the open floor and the box's " +
		"top as they are");
	voidCaptureExit(0);
}

voidRunConfigured(WIDTH, HEIGHT, 1, 0, init, frame);
