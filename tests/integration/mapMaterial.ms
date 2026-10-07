import { gfxSetup, fbWidth, fbHeight } from "../../src/sokol/gpu";
import { Vec3, Vec4, vec3, quatBetween, linearToSrgb } from "../../src/math/math3d";
import { RenderState, FilterMode, Wrap } from "../../src/gpu/state";
import { Material, Phase, UniformBlock } from "../../src/void3d/material";
import {
	MeshData, MeshError, Rgba, Uv, addTexturedVertex, addTriangle, addTangents,
} from "../../src/void3d/meshData";
import { TextureData, TextureId, TextureUploadError } from "../../src/void3d/texture";
import {
	Program, ProgramKey, MATERIAL_UNIFORM_SLOT, VERTEX_UNIFORM_LENGTH, LIGHT_UNIFORM_LENGTH,
	EMISSIVE_COLOR, EMISSIVE_STRENGTH, EMISSIVE_LENGTH, emissiveBase,
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

// The quads, left to right.
enum Quad {
	Emissive,
	HalfStrength,
	TiltX,
	TiltY,
	MirroredX,
	MirroredY,
}

const WIDTH: int32 = 320;
const HEIGHT: int32 = 240;
const HALF: float32 = 0.4;
const WORLD_PER_TEXEL: float32 = 0.02;
const BACKGROUND: Vec4 = { x: 0.1, y: 0.15, z: 0.2, w: 1.0 };
const WHITE: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };
const SCREEN: LowResView = { width: 320, height: 240, scale: 1, offsetX: 0.0, offsetY: 0.0 };
// 0xAABBGGRR texels.
const RED: uint32 = 0xFF0000FF;
const GREEN: uint32 = 0xFF00FF00;
const BLACK: uint32 = 0xFF000000;
// Tangent-space normals tilted 45 degrees toward +x and toward +y (the image's top).
const TOWARD_X: uint32 = 0xFFDA80DA;
const TOWARD_Y: uint32 = 0xFFDADA80;
const TO_LIGHT: Vec3 = { x: 1.0, y: 1.0, z: 1.5 };
const LAST_FRAME: int32 = 2;
let pixelArt: boolean = voidCaptureEnvInt("VOID_MAP_PIXEL_ART", 0) != 0;
let control: boolean = voidCaptureEnvInt("VOID_MAP_CONTROL", 0) != 0;
let context: DrawContext = DrawContext.withUniformCapacity(
	FORWARD_UNIFORM_LENGTH + PIXEL_ART_UNIFORM_LENGTH + 6 * 8,
);
let scene: Scene3D = Scene3D.create(context);
let forward: ForwardRenderer = makeForward();
let preset: PixelArtRenderer = makePreset();
let items: Vec<DrawItem> = [];
let cameraValues: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let positions: Vec<float32> = [-2.5, -1.5, -0.5, 0.5, 1.5, 2.5];
let frameIndex: int32 = 0;
let failures: int32 = 0;

function fail(message: string): void {
	const presetName: string = pixelArt ? "pixel-art" : "forward";
	console.log(`FAIL map material: ${presetName}: ${message}`);
	failures = failures + 1;
}

function makeForward(): ForwardRenderer {
	const made: Result<ForwardRenderer, ForwardError> = ForwardRenderer.create(context, BACKGROUND);
	if (made.ok) { return made.value; }
	unreachable;
}

function makePreset(): PixelArtRenderer {
	const settings: PixelArtSettings = {
		...PixelArtSettings.full(), lowResShortSide: HEIGHT, postPass: false,
	};
	const look: PixelArtLook = {
		background: BACKGROUND,
		outline: {
			depthThreshold: 0.006, normalThreshold: 0.6, depthShade: 0.55, normalShade: 1.35,
		},
		fog: { start: 1.0, end: 1.0, strength: 0.0, color: BACKGROUND },
		saturation: 0.0,
	};
	const made: Result<PixelArtRenderer, PixelArtError> =
		PixelArtRenderer.create(context, settings, look);
	if (made.ok) { return made.value; }
	unreachable;
}

function texture(pixels: Vec<uint32>): TextureId {
	const data: TextureData = {
		pixels: pixels, width: pixels.length as int32, height: 1,
		filter: FilterMode.Nearest, wrap: Wrap.Clamp,
	};
	const uploaded: Result<TextureId, TextureUploadError> = addTexture(context, data);
	if (uploaded.ok) { return uploaded.value; }
	unreachable;
}

// The control draws every quad with its key's features off and names no map.
function materialFor(key: ProgramKey, strength: float32): Material {
	const drawn: ProgramKey = control ? ProgramKey.of(key.program) : key;
	let block: Vec<float32> = [4.0, 0.0, 0.0, 0.0];
	if (drawn.emissive) {
		for (let i = 0; i < EMISSIVE_LENGTH; i++) { block.push(1.0); }
		block[emissiveBase(drawn) + EMISSIVE_STRENGTH] = strength;
	}
	const reserved: Result<UniformBlock, UniformError> =
		reserveUniforms(context, MATERIAL_UNIFORM_SLOT, block.length as int32);
	if (!reserved.ok) { unreachable; }
	if (!writeUniforms(context, reserved.value, block).ok) { unreachable; }
	const keyed: Material = Material.keyed(drawn, RenderState.defaults(), Phase.Opaque);
	return { ...keyed, uniforms: reserved.value };
}

// A quad facing the camera, counter-clockwise; `mirrored` runs u from right to left.
function quadMesh(mirrored: boolean, tangents: boolean): MeshData {
	let mesh: MeshData = MeshData.withUvs();
	const normal: Vec3 = vec3(0.0, 0.0, 1.0);
	const left: float32 = mirrored ? 1.0 : 0.0;
	const right: float32 = mirrored ? 0.0 : 1.0;
	const corners: Vec<Vec3> = [
		vec3(-HALF, -HALF, 0.0), vec3(HALF, -HALF, 0.0),
		vec3(HALF, HALF, 0.0), vec3(-HALF, HALF, 0.0),
	];
	const uvs: Vec<Uv> = [
		{ u: left, v: 1.0 }, { u: right, v: 1.0 }, { u: right, v: 0.0 }, { u: left, v: 0.0 },
	];
	for (let i = 0; i < 4; i++) {
		if (!addTexturedVertex(mesh, corners[i], normal, uvs[i], WHITE).ok) { unreachable; }
	}
	if (!addTriangle(mesh, 0, 1, 2).ok || !addTriangle(mesh, 0, 2, 3).ok) { unreachable; }
	if (tangents && !addTangents(mesh).ok) { unreachable; }
	return mesh;
}

function place(quad: Quad, material: Material, mirrored: boolean): void {
	const added: Result<MaterialId, MaterialError> = addMaterial(context, material);
	if (!added.ok) {
		console.log(`FAIL map material: ${quad.toString()} refused: ${added.error.toString()}`);
		voidCaptureExit(1);
		return;
	}
	const uploaded: Result<MeshId, MeshUploadError> =
		addMeshData(context, quadMesh(mirrored, material.program.normalMap));
	if (!uploaded.ok) { unreachable; }
	const at: Vec3 = vec3(positions[quad as int32], 0.0, 0.0);
	const placed: Result<NodeId3D, SceneError> = addMeshNode(
		scene, scene.rootId(), Transform3D.fromTranslation(at), uploaded.value, added.value,
	);
	if (!placed.ok) { unreachable; }
}

function emissive(quad: Quad, base: TextureId, emitted: TextureId, strength: float32): void {
	const key: ProgramKey = ProgramKey.of(Program.LitTextured).withEmissive();
	const material: Material = { ...materialFor(key, strength), texture: base };
	place(quad, control ? material : { ...material, emissiveTexture: emitted }, false);
}

function normalMapped(quad: Quad, base: TextureId, normals: TextureId, mirrored: boolean): void {
	const key: ProgramKey = ProgramKey.of(Program.LitTextured).withNormalMap();
	const material: Material = { ...materialFor(key, 1.0), texture: base };
	place(quad, control ? material : { ...material, normalTexture: normals }, mirrored);
}

function init(): void {
	if (voidCaptureBackend() == 0) { voidCaptureExit(3); }
	gfxSetup();
	const black: TextureId = texture([BLACK]);
	const white: TextureId = texture([0xFFFFFFFF]);
	const halves: TextureId = texture([RED, GREEN]);
	emissive(Quad.Emissive, black, halves, 1.0);
	emissive(Quad.HalfStrength, black, white, 0.5);
	const towardX: TextureId = texture([TOWARD_X]);
	const towardY: TextureId = texture([TOWARD_Y]);
	normalMapped(Quad.TiltX, white, towardX, false);
	normalMapped(Quad.TiltY, white, towardY, false);
	normalMapped(Quad.MirroredX, white, towardX, true);
	normalMapped(Quad.MirroredY, white, towardY, true);
	const sun: LightInstance = {
		kind: LightKind.Directional, color: vec3(1.0, 1.0, 1.0),
		radius: 0.0, power: 1.0, priority: 0,
	};
	const front: Vec3 = vec3(0.0, 0.0, 0.0) - TO_LIGHT.normalized();
	const _sun: NodeId3D = addLightNode(scene, scene.rootId(), {
		...Transform3D.identity(), rotation: quatBetween(vec3(0.0, 0.0, 1.0), front),
	}, sun);
	setAmbient(scene, vec3(0.0, 0.0, 0.0));
}

function viewOf(): CameraView {
	const camera: Camera3D = {
		position: vec3(0.0, 0.0, 4.0), yaw: 0.0, pitch: 0.0,
		nearPlane: 0.1, farPlane: 10.0,
		projection: {
			kind: ProjectionKind.Orthographic, worldPerTexel: WORLD_PER_TEXEL, snap: false,
		},
	};
	const resolved: Result<CameraView, CameraError> = camera.resolve(WIDTH, HEIGHT);
	if (resolved.ok) { return resolved.value; }
	unreachable;
}

// 0xRRGGBB at the quad's left (-1) or right (1) quarter.
function rgbAt(camera: CameraView, quad: Quad, side: float32): int64 {
	const at: Vec3 = camera.project(
		vec3(positions[quad as int32] + side * HALF * 0.5, 0.0, 0.0), SCREEN, true,
	);
	return voidCapturePixel(0, at.x as int32, at.y as int32) >> 8;
}

function near(value: int64, expected: int64, tolerance: int64): boolean {
	return value - expected <= tolerance && expected - value <= tolerance;
}

function isGrey(rgb: int64, level: int64): boolean {
	return near((rgb >> 16) & 0xFF, level, 3) && near((rgb >> 8) & 0xFF, level, 3) &&
		near(rgb & 0xFF, level, 3);
}

function isColor(rgb: int64, texel: uint32): boolean {
	return near((rgb >> 16) & 0xFF, (texel & 0xFF) as int64, 2) &&
		near((rgb >> 8) & 0xFF, ((texel >> 8) & 0xFF) as int64, 2) &&
		near(rgb & 0xFF, ((texel >> 16) & 0xFF) as int64, 2);
}

// The grey a white surface takes under the sun alone with world normal `normal`.
function litGrey(normal: Vec3): int64 {
	const lambert: float32 = normal.normalized().dot(TO_LIGHT.normalized());
	const shade: float32 = lambert > 0.0 ? lambert : 0.0;
	return (linearToSrgb(shade) * 255.0 + 0.5) as int64;
}

function decoded(texel: uint32): Vec3 {
	const x: float32 = ((texel & 0xFF) as float32) / 255.0 * 2.0 - 1.0;
	const y: float32 = (((texel >> 8) & 0xFF) as float32) / 255.0 * 2.0 - 1.0;
	const z: float32 = (((texel >> 16) & 0xFF) as float32) / 255.0 * 2.0 - 1.0;
	return vec3(x, y, z);
}

function checkGrey(camera: CameraView, quad: Quad, normal: Vec3, message: string): void {
	const rgb: int64 = rgbAt(camera, quad, 0.0);
	const expected: int64 = litGrey(normal);
	if (!isGrey(rgb, expected)) { fail(`${message}: ${rgb}, expected grey ${expected}`); }
}

function check(camera: CameraView): void {
	const left: int64 = rgbAt(camera, Quad.Emissive, -1.0);
	const right: int64 = rgbAt(camera, Quad.Emissive, 1.0);
	if (!isColor(left, RED) || !isColor(right, GREEN)) {
		fail(`the black quad did not emit its emissive map: ${left} ${right}`);
	}
	const half: int64 = (linearToSrgb(0.5) * 255.0 + 0.5) as int64;
	const scaled: int64 = rgbAt(camera, Quad.HalfStrength, 0.0);
	if (!isGrey(scaled, half)) { fail(`the half strength emitted ${scaled}, not grey ${half}`); }
	const x: Vec3 = decoded(TOWARD_X);
	const y: Vec3 = decoded(TOWARD_Y);
	checkGrey(camera, Quad.TiltX, x, "the normal map did not tilt toward +x");
	checkGrey(camera, Quad.TiltY, y, "the normal map did not tilt toward +y");
	checkGrey(camera, Quad.MirroredX, vec3(0.0 - x.x, x.y, x.z),
		"the mirrored island did not turn its tangent");
	checkGrey(camera, Quad.MirroredY, y, "the mirrored island turned its bitangent");
}

function frame(): void {
	if (fbWidth() != WIDTH || fbHeight() != HEIGHT) { fail("the framebuffer size changed"); }
	frameIndex = frameIndex + 1;
	if (refresh(scene, items) != 6) { fail("the scene does not draw its six quads"); }
	const collected: Result<int32, LightError> = collectLights(scene, lights);
	if (!collected.ok) { unreachable; }
	const camera: CameraView = viewOf();
	camera.writeCameraBlock(cameraValues);
	if (pixelArt) {
		const drawn: Result<int32, PixelArtError> =
			renderPixelArt(preset, items, cameraValues, lights, SCREEN);
		if (!drawn.ok) { fail(`pixel-art refused: ${drawn.error.toString()}`); }
	} else {
		const drawn: Result<int32, ForwardError> =
			renderForward(forward, items, cameraValues, lights, WIDTH, HEIGHT);
		if (!drawn.ok) { fail(`forward refused: ${drawn.error.toString()}`); }
	}
	if (frameIndex < LAST_FRAME) { return; }
	if (voidCaptureGrab(0) == 0) { fail("readback failed"); }
	check(camera);
	if (failures > 0) { voidCaptureExit(1); }
	console.log("PASS map material: emissive map and strength, normal map with its tangent frame");
	voidCaptureExit(0);
}

voidRunConfigured(WIDTH, HEIGHT, 1, 0, init, frame);
