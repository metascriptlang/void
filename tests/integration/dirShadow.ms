import { gfxSetup, fbWidth, fbHeight } from "../../src/sokol/gpu";
import { Vec3, Vec4, vec3, quatBetween } from "../../src/math/math3d";
import {
	Material, MaterialKind, ShadowCasting, UniformBlock, movingDefaults,
} from "../../src/void3d/material";
import { MeshData, MeshError, Rgba, addQuad, addTexturedQuad } from "../../src/void3d/meshData";
import {
	Program, ProgramKey, MATERIAL_UNIFORM_SLOT, MATERIAL_UNIFORM_LENGTH, VERTEX_UNIFORM_LENGTH,
	LIGHT_UNIFORM_LENGTH, MOVING_MATERIAL_UNIFORM_LENGTH, MOVING_DISSOLVE_THRESHOLD, movingBase,
} from "../../src/void3d/gpu3d";
import {
	DrawContext, DrawItem, MeshId, MaterialId, MeshUploadError, MaterialError,
	addMeshData, addMaterial, addTexture, reserveUniforms, writeUniforms,
} from "../../src/void3d/draw";
import { TextureId, TextureUploadError, NO_TEXTURE } from "../../src/void3d/texture";
import { FilterMode, Wrap } from "../../src/gpu/state";
import { UniformError } from "../../src/void3d/uniformPool";
import {
	Scene3D, Transform3D, NodeId3D, SceneError, LightKind, LightInstance, LightError,
	addMeshNode, addLightNode, setAmbient, refresh, collectLights,
} from "../../src/void3d/scene";
import { Camera3D, CameraView, CameraError, ProjectionKind } from "../../src/void3d/camera";
import { LowResView } from "../../src/void3d/blit";
import { Renderer, attachShadow } from "../../src/void3d/renderer";
import {
	DirShadowMap, ShadowError, DIR_SHADOW_UNIFORM_LENGTH,
} from "../../src/void3d/dirShadowMap";
import {
	ForwardRenderer, ForwardError, FORWARD_UNIFORM_LENGTH, renderFrame as renderForward,
} from "../../src/void3d/forwardRenderer";
import {
	PixelArtRenderer, PixelArtError, PixelArtSettings, PixelArtLook, PIXEL_ART_UNIFORM_LENGTH,
	renderFrame as renderPixelArt,
} from "../../src/void3d/pixelArtRenderer";
import {
	voidCaptureBackend, voidCaptureGrab, voidCapturePixel, voidCaptureEnvInt, voidCaptureExit,
} from "../capture/capture.h";

@include("../../src/sokol/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, sampleCount: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

enum Case {
	Full,
	Detached,
	CastOff,
	ReceiveOff,
	ShadowOnly,
	HalfOpacity,
	// The caster dissolves its left half (M36); the control keeps the dissolve off.
	Dissolve,
	DissolveControl,
}

const WIDTH: int32 = 320;
const HEIGHT: int32 = 240;
const WORLD_PER_TEXEL: float32 = 0.02;
const GREY: Vec4 = { x: 0.2, y: 0.2, z: 0.2, w: 1.0 };
const WHITE: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };
const RED: Rgba = { red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0 };
const SCREEN: LowResView = { width: 320, height: 240, scale: 1, offsetX: 0.0, offsetY: 0.0 };
const GROUND_HALF: float32 = 3.0;
const CASTER_HALF: float32 = 0.5;
const CASTER_HEIGHT: float32 = 1.0;
const TO_LIGHT: Vec3 = { x: 1.0, y: 2.0, z: 0.0 };
const SHADOW_SIZE: int32 = 512;
const FRAMES: int32 = 3;
let pixelArt: boolean = voidCaptureEnvInt("VOID_DIR_SHADOW_PIXEL_ART", 0) != 0;
let shadowCase: Case = voidCaptureEnvInt("VOID_DIR_SHADOW_CASE", 0) as Case;
let context: DrawContext = DrawContext.withUniformCapacity(
	FORWARD_UNIFORM_LENGTH + PIXEL_ART_UNIFORM_LENGTH + DIR_SHADOW_UNIFORM_LENGTH +
	2 * MATERIAL_UNIFORM_LENGTH + MOVING_MATERIAL_UNIFORM_LENGTH,
);
let scene: Scene3D = Scene3D.create(context);
let forward: ForwardRenderer = makeForward();
let preset: PixelArtRenderer = makePreset();
let shadow: DirShadowMap = makeShadow();
let items: Vec<DrawItem> = [];
let cameraValues: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let stage: int32 = 0;

function fail(message: string): void {
	const presetName: string = pixelArt ? "pixel-art" : "forward";
	const name: string = shadowCase.toString();
	console.log(`FAIL dir shadow: ${presetName} ${name} stage ${stage}: ${message}`);
	voidCaptureExit(1);
}

function makeForward(): ForwardRenderer {
	const made: Result<ForwardRenderer, ForwardError> = ForwardRenderer.create(context, GREY);
	if (made.ok) { return made.value; }
	unreachable;
}

function makePreset(): PixelArtRenderer {
	const settings: PixelArtSettings = {
		...PixelArtSettings.full(), lowResShortSide: HEIGHT, postPass: false,
	};
	const look: PixelArtLook = {
		background: GREY,
		outline: {
			depthThreshold: 0.006, normalThreshold: 0.6, depthShade: 0.55, normalShade: 1.35,
		},
		fog: { start: 1.0, end: 1.0, strength: 0.0, color: GREY },
		saturation: 0.0,
	};
	const made: Result<PixelArtRenderer, PixelArtError> =
		PixelArtRenderer.create(context, settings, look);
	if (made.ok) { return made.value; }
	unreachable;
}

function makeShadow(): DirShadowMap {
	const made: Result<DirShadowMap, ShadowError> = DirShadowMap.create(context, SHADOW_SIZE);
	if (made.ok) { return made.value; }
	unreachable;
}

function material(cast: ShadowCasting, receive: boolean): MaterialId {
	const reserved: Result<UniformBlock, UniformError> =
		reserveUniforms(context, MATERIAL_UNIFORM_SLOT, MATERIAL_UNIFORM_LENGTH);
	if (!reserved.ok) { unreachable; }
	const values: Vec<float32> = [4.0, 0.0, 0.0, 0.0];
	if (!writeUniforms(context, reserved.value, values).ok) { unreachable; }
	const added: Result<MaterialId, MaterialError> = addMaterial(context, {
		...Material.ofKind(Program.Lit, MaterialKind.Opaque).withShadows(cast, receive),
		uniforms: reserved.value,
	});
	if (added.ok) { return added.value; }
	fail(`a material was refused: ${added.error.toString()}`);
	unreachable;
}

function horizontal(half: float32, y: float32, color: Rgba, made: MaterialId): void {
	let mesh: MeshData = MeshData.empty();
	const built: Result<int32, MeshError> = addQuad(
		mesh, vec3(-half, y, half), vec3(half, y, half), vec3(half, y, -half),
		vec3(-half, y, -half), vec3(0.0, 1.0, 0.0), color,
	);
	if (!built.ok) { unreachable; }
	const uploaded: Result<MeshId, MeshUploadError> = addMeshData(context, mesh);
	if (!uploaded.ok) { unreachable; }
	const placed: Result<NodeId3D, SceneError> =
		addMeshNode(scene, scene.rootId(), Transform3D.identity(), uploaded.value, made);
	if (!placed.ok) { unreachable; }
}

// A LitTextured caster whose noise is low on its left half: a dissolve at 0.5 removes that half.
function dissolvingCaster(): void {
	const key: ProgramKey = shadowCase == Case.Dissolve ?
		ProgramKey.of(Program.LitTextured).withDissolve() : ProgramKey.of(Program.LitTextured);
	let values: Vec<float32> = [4.0, 0.0, 0.0, 0.0];
	if (key.dissolve) {
		values = movingDefaults(key);
		values[0] = 4.0;
		values[movingBase(key) + MOVING_DISSOLVE_THRESHOLD] = 0.5;
	}
	const reserved: Result<UniformBlock, UniformError> =
		reserveUniforms(context, MATERIAL_UNIFORM_SLOT, values.length as int32);
	if (!reserved.ok) { unreachable; }
	if (!writeUniforms(context, reserved.value, values).ok) { unreachable; }
	const white: Result<TextureId, TextureUploadError> = addTexture(context, {
		pixels: [0xFFFFFFFF], width: 1, height: 1, filter: FilterMode.Nearest, wrap: Wrap.Clamp,
	});
	const noise: Result<TextureId, TextureUploadError> = addTexture(context, {
		pixels: [0xFF000033, 0xFF0000CC], width: 2, height: 1,
		filter: FilterMode.Nearest, wrap: Wrap.Clamp,
	});
	if (!white.ok || !noise.ok) { unreachable; }
	const lit: Material = Material.ofKind(Program.LitTextured, MaterialKind.Opaque);
	const added: Result<MaterialId, MaterialError> = addMaterial(context, {
		...lit,
		program: { ...key, shadowed: true },
		texture: white.value,
		dissolveTexture: key.dissolve ? noise.value : NO_TEXTURE,
		uniforms: reserved.value,
	});
	if (!added.ok) { fail(`the caster was refused: ${added.error.toString()}`); }
	if (!added.ok) { return; }
	let mesh: MeshData = MeshData.withUvs();
	const half: float32 = CASTER_HALF;
	const y: float32 = CASTER_HEIGHT;
	const built: Result<int32, MeshError> = addTexturedQuad(
		mesh, vec3(-half, y, half), vec3(half, y, half), vec3(half, y, -half),
		vec3(-half, y, -half), vec3(0.0, 1.0, 0.0), RED,
	);
	if (!built.ok) { unreachable; }
	const uploaded: Result<MeshId, MeshUploadError> = addMeshData(context, mesh);
	if (!uploaded.ok) { unreachable; }
	const placed: Result<NodeId3D, SceneError> =
		addMeshNode(scene, scene.rootId(), Transform3D.identity(), uploaded.value, added.value);
	if (!placed.ok) { unreachable; }
}

function init(): void {
	if (voidCaptureBackend() == 0) { voidCaptureExit(3); }
	gfxSetup();
	const casting: ShadowCasting = match (shadowCase) {
		Case.Full => ShadowCasting.On,
		Case.Detached => ShadowCasting.On,
		Case.CastOff => ShadowCasting.Off,
		Case.ReceiveOff => ShadowCasting.On,
		Case.ShadowOnly => ShadowCasting.Only,
		Case.HalfOpacity => ShadowCasting.On,
		Case.Dissolve => ShadowCasting.On,
		Case.DissolveControl => ShadowCasting.On,
	};
	horizontal(GROUND_HALF, 0.0, WHITE, material(ShadowCasting.On, shadowCase != Case.ReceiveOff));
	if (shadowCase == Case.Dissolve || shadowCase == Case.DissolveControl) {
		dissolvingCaster();
	} else {
		horizontal(CASTER_HALF, CASTER_HEIGHT, RED, material(casting, true));
	}
	const sun: LightInstance = {
		kind: LightKind.Directional, color: vec3(1.0, 1.0, 1.0),
		radius: 0.0, power: 1.0, priority: 0,
	};
	const front: Vec3 = vec3(0.0, 0.0, 0.0) - TO_LIGHT.normalized();
	const _sun: NodeId3D = addLightNode(scene, scene.rootId(), {
		...Transform3D.identity(), rotation: quatBetween(vec3(0.0, 0.0, 1.0), front),
	}, sun);
	setAmbient(scene, vec3(0.3, 0.3, 0.3));
	if (shadowCase == Case.HalfOpacity) { shadow.opacity = 0.5; }
	if (shadowCase != Case.Detached) {
		const core: Renderer = pixelArt ? preset.core : forward.core;
		attachShadow(core, shadow);
	}
}

function viewOf(): CameraView {
	const camera: Camera3D = {
		position: vec3(0.0, 4.0, 4.0), yaw: 0.0, pitch: 0.785398,
		nearPlane: 0.1, farPlane: 20.0,
		projection: {
			kind: ProjectionKind.Orthographic, worldPerTexel: WORLD_PER_TEXEL, snap: false,
		},
	};
	const view: Result<CameraView, CameraError> = camera.resolve(WIDTH, HEIGHT);
	if (view.ok) { return view.value; }
	unreachable;
}

function rgbAt(view: CameraView, point: Vec3): int64 {
	const at: Vec3 = view.project(point, SCREEN, true);
	return voidCapturePixel(0, at.x as int32, at.y as int32) >> 8;
}

function green(rgb: int64): int64 {
	return (rgb >> 8) & 0xFF;
}

// The sun moves a shadow 0.5 toward -x per unit of height: the caster's left half shades the
// ground over x in [-1, -0.5], its right half over [-0.5, 0].
function checkDissolve(view: CameraView): void {
	const gone: int64 = rgbAt(view, vec3(-0.75, 0.0, 0.0));
	const kept: int64 = rgbAt(view, vec3(-0.25, 0.0, 0.0));
	const keptTop: int64 = rgbAt(view, vec3(0.25, CASTER_HEIGHT, 0.0));
	const goneTop: int64 = rgbAt(view, vec3(-0.25, CASTER_HEIGHT, 0.0));
	console.log(`dir shadow: dissolved ${gone}, kept ${kept}, tops ${goneTop} ${keptTop}`);
	if (green(gone) < 240) { fail(`the dissolved half still cast a shadow: ${gone}`); }
	if (green(kept) > 100) { fail(`the kept half cast no shadow: ${kept}`); }
	if ((keptTop >> 16) < 200 || green(keptTop) > 60) { fail(`the kept half drew ${keptTop}`); }
	if ((goneTop >> 16) > 200 && green(goneTop) < 60) { fail("the dissolved half drew red"); }
}

function check(view: CameraView): void {
	if (shadowCase == Case.Dissolve || shadowCase == Case.DissolveControl) {
		checkDissolve(view);
		return;
	}
	const under: int64 = rgbAt(view, vec3(-0.5, 0.0, 0.0));
	const open: int64 = rgbAt(view, vec3(1.8, 0.0, 0.0));
	const top: int64 = rgbAt(view, vec3(0.0, CASTER_HEIGHT, 0.0));
	console.log(`dir shadow: under ${under}, open ${open}, caster top ${top}`);
	if (green(open) < 240) { fail(`the open ground drew ${open}, darker than full light`); }
	const shadowed: boolean = shadowCase == Case.Full || shadowCase == Case.ShadowOnly ||
		shadowCase == Case.HalfOpacity || shadowCase == Case.Detached;
	if (shadowed && shadowCase != Case.HalfOpacity && green(under) > 100) {
		fail(`no shadow under the caster: ${under} against the open ground's ${open}`);
	}
	if (shadowCase == Case.HalfOpacity && (green(under) < 140 || green(under) > 230)) {
		fail(`half opacity drew ${under} under the caster, not between shadow and light`);
	}
	if (!shadowed && under != open) {
		fail(`the ground under a caster that should not shade it drew ${under}, not ${open}`);
	}
	const drawn: boolean = (top >> 16) > 200 && green(top) < 60;
	if (shadowCase == Case.ShadowOnly && drawn) { fail("the shadow-only caster drew its colour"); }
	if (shadowCase != Case.ShadowOnly && !drawn) { fail(`the caster drew ${top}, not red`); }
}

function frame(): void {
	if (fbWidth() != WIDTH || fbHeight() != HEIGHT) { fail("the framebuffer size changed"); }
	if (refresh(scene, items) != 2) { fail("the scene does not draw its two meshes"); }
	const collected: Result<int32, LightError> = collectLights(scene, lights);
	if (!collected.ok) { unreachable; }
	const view: CameraView = viewOf();
	view.writeCameraBlock(cameraValues);
	if (pixelArt) {
		const drawn: Result<int32, PixelArtError> =
			renderPixelArt(preset, items, cameraValues, lights, SCREEN);
		if (!drawn.ok) { fail(`pixel-art refused: ${drawn.error.toString()}`); }
	} else {
		const drawn: Result<int32, ForwardError> =
			renderForward(forward, items, cameraValues, lights, WIDTH, HEIGHT);
		if (!drawn.ok) { fail(`forward refused: ${drawn.error.toString()}`); }
	}
	if (voidCaptureGrab(0) == 0) { fail("readback failed"); }
	check(view);
	stage = stage + 1;
	if (stage < FRAMES) { return; }
	console.log(`PASS dir shadow: ${shadowCase.toString()}`);
	voidCaptureExit(0);
}

voidRunConfigured(WIDTH, HEIGHT, 1, 0, init, frame);
