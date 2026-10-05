import { gfxSetup, fbWidth, fbHeight } from "../../src/sokol/gpu";
import { Vec3, Vec4, vec3 } from "../../src/math/math3d";
import { FilterMode, Wrap } from "../../src/gpu/state";
import { Material, MaterialKind, UniformBlock, alphaKillFor } from "../../src/void3d/material";
import { MeshData, MeshError, Rgba, addQuad, addTexturedQuad } from "../../src/void3d/meshData";
import {
	TextureData, TextureId, TextureUploadError, NO_TEXTURE,
} from "../../src/void3d/texture";
import {
	Program, MATERIAL_UNIFORM_SLOT, MATERIAL_UNIFORM_LENGTH, MATERIAL_ALPHA_KILL,
	UNLIT_MATERIAL_UNIFORM_LENGTH, VERTEX_UNIFORM_LENGTH, LIGHT_UNIFORM_LENGTH,
} from "../../src/void3d/gpu3d";
import {
	DrawContext, DrawItem, MeshId, MaterialId, MeshUploadError, MaterialError,
	addMeshData, addMaterial, addTexture, reserveUniforms, writeUniforms,
} from "../../src/void3d/draw";
import { UniformError } from "../../src/void3d/uniformPool";
import {
	Scene3D, Transform3D, NodeId3D, SceneError, LightKind, LightInstance, LightError,
	addMeshNode, addLightNode, setAmbient, refresh, collectLights,
} from "../../src/void3d/scene";
import { Camera3D, CameraView, CameraError, ProjectionKind } from "../../src/void3d/camera";
import { LowResView } from "../../src/void3d/blit";
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

const WIDTH: int32 = 320;
const HEIGHT: int32 = 240;
const HALF: float32 = 0.6;
const WORLD_PER_TEXEL: float32 = 0.02;
const GREY: Vec4 = { x: 0.2, y: 0.2, z: 0.2, w: 1.0 };
const WHITE: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };
const QUARTER: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 0.25 };
const THREE_QUARTERS: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 0.75 };
const SCREEN: LowResView = { width: 320, height: 240, scale: 1, offsetX: 0.0, offsetY: 0.0 };
const UNLIT_X: float32 = -1.6;
const LIT_X: float32 = 0.0;
const VERTEX_X: float32 = 1.6;
const GAP_X: float32 = 0.8;
const OPAQUE_WHITE: int64 = 0xFFFFFF;
const FRAMES: int32 = 3;
let pixelArt: boolean = voidCaptureEnvInt("VOID_ALPHA_KILL_PIXEL_ART", 0) != 0;
let control: boolean = voidCaptureEnvInt("VOID_ALPHA_KILL_CONTROL", 0) != 0;
let context: DrawContext = DrawContext.withUniformCapacity(
	FORWARD_UNIFORM_LENGTH + PIXEL_ART_UNIFORM_LENGTH + 2 * UNLIT_MATERIAL_UNIFORM_LENGTH +
	2 * MATERIAL_UNIFORM_LENGTH,
);
let scene: Scene3D = Scene3D.create(context);
let forward: ForwardRenderer = makeForward();
let preset: PixelArtRenderer = makePreset();
let items: Vec<DrawItem> = [];
let cameraValues: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let stage: int32 = 0;

function fail(message: string): void {
	const preset: string = pixelArt ? "pixel-art" : "forward";
	console.log(`FAIL alpha kill: ${preset} stage ${stage}: ${message}`);
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

function texel(rgba: uint32): TextureId {
	const data: TextureData = {
		pixels: [rgba], width: 1, height: 1, filter: FilterMode.Nearest, wrap: Wrap.Clamp,
	};
	const uploaded: Result<TextureId, TextureUploadError> = addTexture(context, data);
	if (uploaded.ok) { return uploaded.value; }
	unreachable;
}

// A quarter-alpha white texel left, a three-quarter one right, sampled nearest.
function halves(): TextureId {
	const data: TextureData = {
		pixels: [0x40FFFFFF, 0xC0FFFFFF], width: 2, height: 1,
		filter: FilterMode.Nearest, wrap: Wrap.Clamp,
	};
	const uploaded: Result<TextureId, TextureUploadError> = addTexture(context, data);
	if (uploaded.ok) { return uploaded.value; }
	unreachable;
}

function material(
	program: Program,
	kind: MaterialKind,
	values: Readonly<Span<float32>>,
	image: TextureId,
): MaterialId {
	const reserved: Result<UniformBlock, UniformError> =
		reserveUniforms(context, MATERIAL_UNIFORM_SLOT, values.length as int32);
	if (!reserved.ok) { unreachable; }
	if (!writeUniforms(context, reserved.value, values).ok) { unreachable; }
	const added: Result<MaterialId, MaterialError> = addMaterial(context, {
		...Material.ofKind(program, kind), texture: image, uniforms: reserved.value,
	});
	if (added.ok) { return added.value; }
	fail(`a material was refused: ${added.error.toString()}`);
	unreachable;
}

function place(mesh: MeshData, made: MaterialId): void {
	const uploaded: Result<MeshId, MeshUploadError> = addMeshData(context, mesh);
	if (!uploaded.ok) { unreachable; }
	const placed: Result<NodeId3D, SceneError> =
		addMeshNode(scene, scene.rootId(), Transform3D.identity(), uploaded.value, made);
	if (!placed.ok) { unreachable; }
}

function quad(x: float32, half: float32, z: float32, made: MaterialId): void {
	let mesh: MeshData = MeshData.withUvs();
	const built: Result<int32, MeshError> = addTexturedQuad(
		mesh, vec3(x - half, -HALF, z), vec3(x + half, -HALF, z),
		vec3(x + half, HALF, z), vec3(x - half, HALF, z), vec3(0.0, 0.0, 1.0), WHITE,
	);
	if (!built.ok) { unreachable; }
	place(mesh, made);
}

// Untextured: the left half's vertices carry a quarter alpha, the right half's three quarters.
function vertexAlphaQuad(x: float32, made: MaterialId): void {
	let mesh: MeshData = MeshData.empty();
	const left: Result<int32, MeshError> = addQuad(
		mesh, vec3(x - HALF, -HALF, 0.0), vec3(x, -HALF, 0.0), vec3(x, HALF, 0.0),
		vec3(x - HALF, HALF, 0.0), vec3(0.0, 0.0, 1.0), QUARTER,
	);
	const right: Result<int32, MeshError> = addQuad(
		mesh, vec3(x, -HALF, 0.0), vec3(x + HALF, -HALF, 0.0), vec3(x + HALF, HALF, 0.0),
		vec3(x, HALF, 0.0), vec3(0.0, 0.0, 1.0), THREE_QUARTERS,
	);
	if (!left.ok || !right.ok) { unreachable; }
	place(mesh, made);
}

function init(): void {
	if (voidCaptureBackend() == 0) { voidCaptureExit(3); }
	gfxSetup();
	const image: TextureId = halves();
	const kind: MaterialKind = control ? MaterialKind.Opaque : MaterialKind.AlphaKill;
	let unlit: Vec<float32> = [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0];
	unlit[MATERIAL_ALPHA_KILL] = alphaKillFor(kind);
	let lit: Vec<float32> = [4.0, 0.0, 0.0, 0.0];
	lit[MATERIAL_ALPHA_KILL] = alphaKillFor(kind);
	quad(UNLIT_X, HALF, 0.0, material(Program.UnlitTextured, kind, unlit, image));
	quad(LIT_X, HALF, 0.0, material(Program.LitTextured, kind, lit, image));
	vertexAlphaQuad(VERTEX_X, material(Program.Lit, kind, lit, NO_TEXTURE));
	const backdrop: Vec<float32> = [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0];
	quad(0.0, 3.0, -0.5, material(Program.UnlitTextured, MaterialKind.Opaque, backdrop,
		texel(0xFF808080)));
	const light: LightInstance = {
		kind: LightKind.Directional, color: vec3(1.0, 1.0, 1.0),
		radius: 0.0, power: 1.0, priority: 0,
	};
	const _sun: NodeId3D = addLightNode(scene, scene.rootId(), {
		...Transform3D.identity(), rotation: { x: 0.0, y: 1.0, z: 0.0, w: 0.0 },
	}, light);
	setAmbient(scene, vec3(0.5, 0.5, 0.5));
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

function rgbAt(view: CameraView, x: float32): int64 {
	const at: Vec3 = view.project(vec3(x, 0.0, 0.0), SCREEN, true);
	return voidCapturePixel(0, at.x as int32, at.y as int32) >> 8;
}

// The backdrop behind every quad draws after them, so a cut pixel that still wrote depth
// would show the clear colour where the backdrop belongs.
function check(view: CameraView): void {
	const backdrop: int64 = rgbAt(view, GAP_X);
	const columns: Vec<float32> = [UNLIT_X, LIT_X, VERTEX_X];
	const names: Vec<string> = ["unlit textured", "lit textured", "lit vertex-alpha"];
	for (let i = 0; i < 3; i++) {
		const cut: int64 = rgbAt(view, columns[i] - HALF / 2.0);
		const kept: int64 = rgbAt(view, columns[i] + HALF / 2.0);
		console.log(`alpha kill: ${names[i]}: backdrop ${backdrop}, cut ${cut}, kept ${kept}`);
		if (cut != backdrop) {
			fail(`the ${names[i]} quarter-alpha texel drew ${cut}, not the backdrop ${backdrop}`);
		}
		if (kept == backdrop) { fail(`the ${names[i]} three-quarter texel was cut`); }
	}
	const white: int64 = rgbAt(view, UNLIT_X + HALF / 2.0);
	if (white != OPAQUE_WHITE) {
		fail(`the unlit three-quarter texel drew ${white}, not unblended white`);
	}
}

function frame(): void {
	if (fbWidth() != WIDTH || fbHeight() != HEIGHT) { fail("the framebuffer size changed"); }
	if (refresh(scene, items) != 4) { fail("the scene does not draw its four meshes"); }
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
	console.log("PASS alpha kill: below the threshold cut to the backdrop, above it unblended");
	voidCaptureExit(0);
}

voidRunConfigured(WIDTH, HEIGHT, 1, 0, init, frame);
