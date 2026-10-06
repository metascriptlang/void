import { gfxSetup, fbWidth, fbHeight } from "../../src/sokol/gpu";
import { Vec3, Vec4, vec3 } from "../../src/math/math3d";
import { RenderState, BlendMode, FilterMode, Wrap } from "../../src/gpu/state";
import { PixelFormat, LoadAction, endPass, commit } from "../../src/gpu/door";
import {
	RenderTarget, ColorAttachment, Sampler, NO_DEPTH, SWAPCHAIN_LAYOUT, beginPass, beginScreenPass,
} from "../../src/gpu/target";
import { Material, Phase, UniformBlock } from "../../src/void3d/material";
import { MeshData, MeshError, Rgba, addTexturedQuad } from "../../src/void3d/meshData";
import { TextureData, TextureId, TextureUploadError, TextureAlpha } from "../../src/void3d/texture";
import {
	Program, MATERIAL_UNIFORM_SLOT, UNLIT_MATERIAL_UNIFORM_LENGTH, VERTEX_UNIFORM_LENGTH,
	LIGHT_UNIFORM_LENGTH,
	ProgramKey,
} from "../../src/void3d/gpu3d";
import {
	DrawContext, DrawItem, MeshId, MaterialId, MeshUploadError, MaterialError,
	addMeshData, addMaterial, addTexture, addTargetTexture, reserveUniforms, writeUniforms,
} from "../../src/void3d/draw";
import { UniformError } from "../../src/void3d/uniformPool";
import {
	Scene3D, Transform3D, NodeId3D, SceneError, LightKind, LightInstance, LightError,
	addMeshNode, addLightNode, setAmbient, refresh, collectLights,
} from "../../src/void3d/scene";
import { Camera3D, CameraView, CameraError, ProjectionKind } from "../../src/void3d/camera";
import { LowResView } from "../../src/void3d/blit";
import { RendererError, openScreen, drawScreen } from "../../src/void3d/renderer";
import { screenState } from "../../src/void3d/screenFx";
import {
	PixelArtRenderer, PixelArtError, PixelArtSettings, PixelArtLook, PIXEL_ART_UNIFORM_LENGTH,
	prepareFrame,
} from "../../src/void3d/pixelArtRenderer";
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
const HALF: float32 = 0.6;
const WORLD_PER_TEXEL: float32 = 0.02;
const BLACK: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };
const WHITE: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };
const PREMULTIPLIED_GREY: Vec4 = { x: 0.5, y: 0.5, z: 0.5, w: 0.5 };
const SCREEN: LowResView = { width: 320, height: 240, scale: 1, offsetX: 0.0, offsetY: 0.0 };
// The normal (0, 0, 1) packed as n * 0.5 + 0.5, read through Copy, which writes alpha 1.
const FACING_NORMAL: int64 = 0x7F7FFFFF;
const ALPHA_X: float32 = -1.6;
const PREMULTIPLIED_X: float32 = 0.0;
const ADDITIVE_X: float32 = 1.6;
const NORMAL_FRAMES: int32 = 2;
const FRAMES: int32 = 4;
const UNLIT: ProgramKey = ProgramKey.of(Program.UnlitTextured);
const PREMULTIPLIED_UNLIT: ProgramKey = UNLIT.withPremultiplied();
let context: DrawContext = DrawContext.withUniformCapacity(
	PIXEL_ART_UNIFORM_LENGTH + 5 * UNLIT_MATERIAL_UNIFORM_LENGTH,
);
let scene: Scene3D = Scene3D.create(context);
let preset: PixelArtRenderer = makePreset();
let items: Vec<DrawItem> = [];
let cameraValues: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let copy: MaterialId = { store: 0, index: 0, generation: 0 };
let sampler: Sampler = { filter: FilterMode.Nearest, wrap: Wrap.Clamp, handle: 0 };
let premultiplied: RenderTarget = RenderTarget.unallocated(PixelFormat.Rgba8, true);
let fill: Vec<ColorAttachment> = new Array(1);
let stage: int32 = 0;

function fail(message: string): void {
	console.log(`FAIL mrt blend: stage ${stage}: ${message}`);
	voidCaptureExit(1);
}

function makePreset(): PixelArtRenderer {
	const settings: PixelArtSettings = {
		...PixelArtSettings.full(), lowResShortSide: HEIGHT, postPass: false,
	};
	const look: PixelArtLook = {
		background: BLACK,
		outline: {
			depthThreshold: 0.006, normalThreshold: 0.6, depthShade: 0.55, normalShade: 1.35,
		},
		fog: { start: 1.0, end: 1.0, strength: 0.0, color: BLACK },
		saturation: 0.0,
	};
	const made: Result<PixelArtRenderer, PixelArtError> =
		PixelArtRenderer.create(context, settings, look);
	if (made.ok) { return made.value; }
	unreachable;
}

function texel(rgba: uint32): TextureId {
	const data: TextureData = {
		pixels: [rgba], width: 1, height: 1, filter: FilterMode.Nearest, wrap: Wrap.Clamp,
	};
	const uploaded: Result<TextureId, TextureUploadError> = addTexture(context, data);
	if (uploaded.ok) { return uploaded.value; }
	unreachable;
}

function material(
	program: ProgramKey,
	image: TextureId,
	pass: RenderState,
	phase: Phase,
): MaterialId {
	const reserved: Result<UniformBlock, UniformError> =
		reserveUniforms(context, MATERIAL_UNIFORM_SLOT, UNLIT_MATERIAL_UNIFORM_LENGTH);
	if (!reserved.ok) { unreachable; }
	const values: Vec<float32> = [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0];
	if (!writeUniforms(context, reserved.value, values).ok) { unreachable; }
	const added: Result<MaterialId, MaterialError> = addMaterial(context, {
		...Material.keyed(program, pass, phase),
		texture: image, uniforms: reserved.value,
	});
	if (added.ok) { return added.value; }
	fail(`a material was refused: ${added.error.toString()}`);
	unreachable;
}

function quad(left: float32, right: float32, z: float32, normal: Vec3, made: MaterialId): void {
	let mesh: MeshData = MeshData.withUvs();
	const built: Result<int32, MeshError> = addTexturedQuad(
		mesh, vec3(left, -HALF, z), vec3(right, -HALF, z),
		vec3(right, HALF, z), vec3(left, HALF, z), normal, WHITE,
	);
	if (!built.ok) { unreachable; }
	const uploaded: Result<MeshId, MeshUploadError> = addMeshData(context, mesh);
	if (!uploaded.ok) { unreachable; }
	const placed: Result<NodeId3D, SceneError> =
		addMeshNode(scene, scene.rootId(), Transform3D.identity(), uploaded.value, made);
	if (!placed.ok) { unreachable; }
}

// The opaque backdrop facing the camera, and a translucent quad over its left half facing +x,
// so its normal differs from the backdrop's wherever it reached the normal attachment.
function column(x: float32, translucent: MaterialId, opaque: MaterialId): void {
	quad(x - HALF, x + HALF, -0.5, vec3(0.0, 0.0, 1.0), opaque);
	quad(x - HALF, x, 0.0, vec3(1.0, 0.0, 0.0), translucent);
}

function premultipliedTexture(): TextureId {
	premultiplied = RenderTarget.allocate(1, 1, PixelFormat.Rgba8, true);
	fill[0] = premultiplied.asColor(LoadAction.Clear, PREMULTIPLIED_GREY);
	const made: Result<TextureId, TextureUploadError> = addTargetTexture(
		context, premultiplied, FilterMode.Nearest, Wrap.Clamp, TextureAlpha.Premultiplied,
	);
	if (made.ok) { return made.value; }
	unreachable;
}

function init(): void {
	if (voidCaptureBackend() == 0) { voidCaptureExit(3); }
	gfxSetup();
	const grey: TextureId = texel(0xFF808080);
	const opaque: MaterialId =
		material(UNLIT, grey, RenderState.defaults(), Phase.Opaque);
	const translucent: RenderState = RenderState.defaults();
	const unwritten: RenderState = translucent.withDepth(false, translucent.depthTest);
	column(ALPHA_X, material(UNLIT, texel(0x80FFFFFF),
		unwritten.withBlendMode(BlendMode.Alpha), Phase.Alpha), opaque);
	column(PREMULTIPLIED_X, material(PREMULTIPLIED_UNLIT, premultipliedTexture(),
		unwritten.withBlendMode(BlendMode.AlphaAdd), Phase.Alpha), opaque);
	column(ADDITIVE_X, material(UNLIT, texel(0xFF404040),
		unwritten.withBlendMode(BlendMode.Add), Phase.Additive), opaque);
	// Behind the alpha column's backdrop: drawn only if the translucent pass lost the depth the
	// opaque pass wrote.
	quad(ALPHA_X, ALPHA_X + HALF, -1.0, vec3(1.0, 0.0, 0.0), material(UNLIT,
		texel(0xFFFFFFFF), unwritten.withBlendMode(BlendMode.Alpha), Phase.Alpha));
	const light: LightInstance = {
		kind: LightKind.Directional, color: vec3(1.0, 1.0, 1.0),
		radius: 0.0, power: 0.0, priority: 0,
	};
	const _sun: NodeId3D = addLightNode(scene, scene.rootId(), {
		...Transform3D.identity(), rotation: { x: 0.0, y: 1.0, z: 0.0, w: 0.0 },
	}, light);
	setAmbient(scene, vec3(1.0, 1.0, 1.0));
	sampler = Sampler.create(FilterMode.Nearest, Wrap.Clamp);
	const added: Result<MaterialId, MaterialError> =
		addMaterial(context, Material.plain(Program.Copy, screenState(), Phase.Opaque));
	if (!added.ok) { unreachable; }
	copy = added.value;
}

function viewOf(): CameraView {
	const camera: Camera3D = {
		position: vec3(0.0, 0.0, 4.0), yaw: 0.0, pitch: 0.0,
		nearPlane: 0.1, farPlane: 10.0,
		projection: {
			kind: ProjectionKind.Orthographic, worldPerTexel: WORLD_PER_TEXEL, snap: false,
		},
	};
	const view: Result<CameraView, CameraError> = camera.resolve(WIDTH, HEIGHT);
	if (view.ok) { return view.value; }
	unreachable;
}

function pixelAt(view: CameraView, x: float32): int64 {
	const at: Vec3 = view.project(vec3(x, 0.0, 0.0), SCREEN, true);
	return voidCapturePixel(0, at.x as int32, at.y as int32);
}

function checkNormals(view: CameraView): void {
	const columns: Vec<float32> = [ALPHA_X, PREMULTIPLIED_X, ADDITIVE_X];
	const names: Vec<string> = ["an Alpha", "a premultiplied AlphaAdd", "an Add"];
	for (let i = 0; i < 3; i++) {
		const behind: int64 = pixelAt(view, columns[i] + HALF / 2.0);
		const under: int64 = pixelAt(view, columns[i] - HALF / 2.0);
		console.log(`mrt blend: ${names[i]} column: backdrop normal ${behind}, under ${under}`);
		if (behind != FACING_NORMAL) {
			fail(`the backdrop normal is ${behind}, not ${FACING_NORMAL}`);
		}
		if (under != FACING_NORMAL) {
			fail(`${names[i]}-blended material changed the normal attachment: ${under}`);
		}
	}
}

function checkColors(view: CameraView): void {
	const backdrop: int64 = pixelAt(view, PREMULTIPLIED_X + HALF / 2.0);
	const columns: Vec<float32> = [ALPHA_X, PREMULTIPLIED_X, ADDITIVE_X];
	for (let i = 0; i < 3; i++) {
		const behind: int64 = pixelAt(view, columns[i] + HALF / 2.0);
		const under: int64 = pixelAt(view, columns[i] - HALF / 2.0);
		console.log(`mrt blend: column ${i}: backdrop color ${behind}, under ${under}`);
		if (behind != backdrop) {
			fail(`column ${i} backdrop is ${behind}, not ${backdrop}: depth was not kept`);
		}
		if (under == backdrop) {
			fail(`column ${i}: the translucent quad did not reach the color target`);
		}
	}
}

function frame(): void {
	if (fbWidth() != WIDTH || fbHeight() != HEIGHT) { fail("the framebuffer size changed"); }
	if (refresh(scene, items) != 7) { fail("the scene does not draw its seven quads"); }
	const collected: Result<int32, LightError> = collectLights(scene, lights);
	if (!collected.ok) { unreachable; }
	beginPass(fill, NO_DEPTH);
	endPass();
	const view: CameraView = viewOf();
	view.writeCameraBlock(cameraValues);
	const prepared: Result<int32, PixelArtError> =
		prepareFrame(preset, items, cameraValues, lights, SCREEN);
	if (!prepared.ok) { fail(`the preset refused the frame: ${prepared.error.toString()}`); }
	const normals: boolean = stage < NORMAL_FRAMES;
	context.materials[copy.index].texture0 = normals ?
		preset.normalTarget.asTexture() :
		preset.colorTarget.asTexture();
	context.materials[copy.index].sampler0 = sampler.asHandle();
	beginScreenPass(BLACK);
	openScreen(preset.core);
	const drawn: Result<int32, RendererError> = drawScreen(preset.core, copy, SWAPCHAIN_LAYOUT);
	if (!drawn.ok) { fail(`the copy was refused: ${drawn.error.toString()}`); }
	endPass();
	commit();
	if (voidCaptureGrab(0) == 0) { fail("readback failed"); }
	if (normals) {
		checkNormals(view);
	} else {
		checkColors(view);
	}
	stage = stage + 1;
	if (stage < FRAMES) { return; }
	console.log("PASS mrt blend: blended materials reach the color target alone, " +
		"over the opaque depth");
	voidCaptureExit(0);
}

voidRunConfigured(WIDTH, HEIGHT, 1, 0, init, frame);
