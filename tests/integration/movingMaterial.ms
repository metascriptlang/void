import { gfxSetup, fbWidth, fbHeight } from "../../src/sokol/gpu";
import { Vec3, Vec4, vec3 } from "../../src/math/math3d";
import { RenderState, FilterMode, Wrap, Face } from "../../src/gpu/state";
import {
	Material, MaterialKind, Phase, UniformBlock, movingDefaults, passFor,
} from "../../src/void3d/material";
import { MeshData, MeshError, Rgba, addTexturedQuad } from "../../src/void3d/meshData";
import {
	TextureData, TextureId, TextureUploadError, NO_TEXTURE,
} from "../../src/void3d/texture";
import {
	Program, ProgramKey, MATERIAL_UNIFORM_SLOT, UNLIT_MATERIAL_COLOR, VERTEX_UNIFORM_LENGTH,
	LIGHT_UNIFORM_LENGTH, MOVING_UV_MATRIX, MOVING_UV_OFFSET, MOVING_UV_SCROLL,
	MOVING_BACK_UV_MATRIX, MOVING_BACK_UV_OFFSET, MOVING_DISSOLVE_THRESHOLD,
	MOVING_DISSOLVE_EDGE_WIDTH, MOVING_DISSOLVE_EDGE_COLOR, MOVING_UNLIT_MATERIAL_UNIFORM_LENGTH,
	MOVING_MATERIAL_UNIFORM_LENGTH, MOVING_FLIPBOOK_COLUMNS, MOVING_FLIPBOOK_ROWS,
	MOVING_FLIPBOOK_FRAMES, MOVING_FLIPBOOK_SPEED, MOVING_FLIPBOOK_START_TIME, MOVING_FLIPBOOK_LOOP,
	MOVING_FLIPBOOK_BLEND, MOVING_FADE_NEAR_START, MOVING_FADE_NEAR_END, movingBase,
} from "../../src/void3d/gpu3d";
import {
	DrawContext, DrawItem, MeshId, MaterialId, MeshUploadError, MaterialError,
	addMeshData, addMaterial, addTexture, reserveUniforms, writeUniforms,
} from "../../src/void3d/draw";
import { UniformError } from "../../src/void3d/uniformPool";
import {
	Scene3D, Transform3D, NodeId3D, SceneError, LightError,
	addMeshNode, setAmbient, refresh, collectLights,
} from "../../src/void3d/scene";
import { Camera3D, CameraView, CameraError, ProjectionKind } from "../../src/void3d/camera";
import { LowResView } from "../../src/void3d/blit";
import { Renderer, setCameraPosition, setElapsedTime } from "../../src/void3d/renderer";
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
	Affine,
	Scroll,
	Back,
	Front,
	Dissolve,
	LitDissolve,
	Flipbook,
	BlendedFlipbook,
	Fade,
}

const WIDTH: int32 = 320;
const HEIGHT: int32 = 240;
const HALF: float32 = 0.3;
const WORLD_PER_TEXEL: float32 = 0.02;
const BACKGROUND: Vec4 = { x: 0.1, y: 0.15, z: 0.2, w: 1.0 };
const WHITE: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };
const SCREEN: LowResView = { width: 320, height: 240, scale: 1, offsetX: 0.0, offsetY: 0.0 };
// 0xAABBGGRR texels.
const RED: uint32 = 0xFF0000FF;
const GREEN: uint32 = 0xFF00FF00;
const BLUE: uint32 = 0xFFFF0000;
const YELLOW: uint32 = 0xFF00FFFF;
const NOISE_LOW: uint32 = 0xFF000033;
const NOISE_HIGH: uint32 = 0xFF0000CC;
// Seconds per frame, and the scroll in u per second: 0.125 u a frame, so the two texels trade
// places every fourth frame.
const ELAPSED: float64 = 0.25;
const SCROLL: float32 = 0.5;
const LAST_FRAME: int32 = 8;
let pixelArt: boolean = voidCaptureEnvInt("VOID_MOVING_PIXEL_ART", 0) != 0;
let control: boolean = voidCaptureEnvInt("VOID_MOVING_CONTROL", 0) != 0;
let context: DrawContext = DrawContext.withUniformCapacity(
	FORWARD_UNIFORM_LENGTH + PIXEL_ART_UNIFORM_LENGTH +
	8 * MOVING_UNLIT_MATERIAL_UNIFORM_LENGTH + MOVING_MATERIAL_UNIFORM_LENGTH,
);
let scene: Scene3D = Scene3D.create(context);
let forward: ForwardRenderer = makeForward();
let preset: PixelArtRenderer = makePreset();
let items: Vec<DrawItem> = [];
let cameraValues: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let positions: Vec<float32> = [-2.8, -2.1, -1.4, -0.7, 0.0, 0.7, 1.4, 2.1, 2.8];
let frameIndex: int32 = 0;
let failures: int32 = 0;

function fail(message: string): void {
	const presetName: string = pixelArt ? "pixel-art" : "forward";
	console.log(`FAIL moving material: ${presetName} frame ${frameIndex}: ${message}`);
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
		fog: { start: 0.0, end: 1.0, strength: 0.0, color: BACKGROUND },
		saturation: 0.0,
	};
	const made: Result<PixelArtRenderer, PixelArtError> =
		PixelArtRenderer.create(context, settings, look);
	if (made.ok) { return made.value; }
	unreachable;
}

function core(): Renderer {
	return pixelArt ? preset.core : forward.core;
}

function texture(pixels: Vec<uint32>, wrap: Wrap): TextureId {
	const data: TextureData = {
		pixels: pixels, width: pixels.length as int32, height: 1,
		filter: FilterMode.Nearest, wrap: wrap,
	};
	const uploaded: Result<TextureId, TextureUploadError> = addTexture(context, data);
	if (uploaded.ok) { return uploaded.value; }
	unreachable;
}

// The control draws every quad with its key's features off, over the plain block.
function materialFor(key: ProgramKey, values: Vec<float32>, front: boolean): Material {
	return blendedFor(key, values, front, false);
}

function blendedFor(
	key: ProgramKey,
	values: Vec<float32>,
	front: boolean,
	blended: boolean,
): Material {
	const drawn: ProgramKey = control ? ProgramKey.of(key.program) : key;
	const unlit: boolean = key.program == Program.UnlitTextured;
	let block: Vec<float32> = values;
	if (control) {
		block = [unlit ? 0.0 : 4.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0];
	}
	const reserved: Result<UniformBlock, UniformError> =
		reserveUniforms(context, MATERIAL_UNIFORM_SLOT, block.length as int32);
	if (!reserved.ok) { unreachable; }
	if (!writeUniforms(context, reserved.value, block).ok) { unreachable; }
	const faces: RenderState = RenderState.defaults().withCulling(front ? Face.Back : Face.None);
	const pass: RenderState = blended ? passFor(MaterialKind.Alpha, faces) : faces;
	const phase: Phase = blended ? Phase.Alpha : Phase.Opaque;
	return { ...Material.keyed(drawn, pass, phase), uniforms: reserved.value };
}

// The key's block with the unlit colour white, or the lit block's ramp levels at 4.
function valuesOf(key: ProgramKey): Vec<float32> {
	let values: Vec<float32> = movingDefaults(key);
	if (key.program == Program.UnlitTextured) {
		for (let i = 0; i < 4; i++) { values[UNLIT_MATERIAL_COLOR + i] = 1.0; }
	} else {
		values[0] = 4.0;
	}
	return values;
}

function flipbookValues(key: ProgramKey, start: float32, blend: float32): Vec<float32> {
	let values: Vec<float32> = valuesOf(key);
	const base: int32 = movingBase(key);
	values[base + MOVING_FLIPBOOK_COLUMNS] = 2.0;
	values[base + MOVING_FLIPBOOK_ROWS] = 1.0;
	values[base + MOVING_FLIPBOOK_FRAMES] = 2.0;
	values[base + MOVING_FLIPBOOK_SPEED] = 1.0;
	values[base + MOVING_FLIPBOOK_START_TIME] = start;
	values[base + MOVING_FLIPBOOK_LOOP] = 1.0;
	values[base + MOVING_FLIPBOOK_BLEND] = blend;
	return values;
}

// Facing the camera with u growing to the right, or facing away with u growing to the left.
// The control's keys sample no back or noise texture, so it names none.
function place(quad: Quad, material: Material, facingAway: boolean): void {
	const named: Material = control ?
		{ ...material, backTexture: NO_TEXTURE, dissolveTexture: NO_TEXTURE } : material;
	const added: Result<MaterialId, MaterialError> = addMaterial(context, named);
	if (!added.ok) {
		console.log(`FAIL moving material: ${quad.toString()} refused: ${added.error.toString()}`);
		voidCaptureExit(1);
		return;
	}
	const sign: float32 = facingAway ? -1.0 : 1.0;
	let mesh: MeshData = MeshData.withUvs();
	const built: Result<int32, MeshError> = addTexturedQuad(
		mesh, vec3(-HALF * sign, -HALF, 0.0), vec3(HALF * sign, -HALF, 0.0),
		vec3(HALF * sign, HALF, 0.0), vec3(-HALF * sign, HALF, 0.0), vec3(0.0, 0.0, sign), WHITE,
	);
	if (!built.ok) { unreachable; }
	const uploaded: Result<MeshId, MeshUploadError> = addMeshData(context, mesh);
	if (!uploaded.ok) { unreachable; }
	const at: Vec3 = vec3(positions[quad as int32], 0.0, 0.0);
	const placed: Result<NodeId3D, SceneError> = addMeshNode(
		scene, scene.rootId(), Transform3D.fromTranslation(at), uploaded.value, added.value,
	);
	if (!placed.ok) { unreachable; }
}

function init(): void {
	if (voidCaptureBackend() == 0) { voidCaptureExit(3); }
	gfxSetup();
	const halves: TextureId = texture([RED, GREEN], Wrap.Repeat);
	const red: TextureId = texture([RED], Wrap.Clamp);
	const white: TextureId = texture([0xFFFFFFFF], Wrap.Clamp);
	const backTexture: TextureId = texture([BLUE, YELLOW], Wrap.Clamp);
	const noise: TextureId = texture([NOISE_LOW, NOISE_HIGH], Wrap.Clamp);

	// u' = 0.5 u + 0.5 reads only the right texel.
	const affine: ProgramKey = ProgramKey.of(Program.UnlitTextured).withUvTransform();
	let affineValues: Vec<float32> = valuesOf(affine);
	affineValues[movingBase(affine) + MOVING_UV_MATRIX] = 0.5;
	affineValues[movingBase(affine) + MOVING_UV_OFFSET] = 0.5;
	place(Quad.Affine, { ...materialFor(affine, affineValues, true), texture: halves }, false);

	const scroll: ProgramKey = ProgramKey.of(Program.UnlitTextured).withUvTransform();
	let scrollValues: Vec<float32> = valuesOf(scroll);
	scrollValues[movingBase(scroll) + MOVING_UV_SCROLL] = SCROLL;
	place(Quad.Scroll, { ...materialFor(scroll, scrollValues, true), texture: halves }, false);

	// Back faces mirror u (Godot's card does `1.0 - uv.x`), so the back reads left to right.
	const back: ProgramKey = ProgramKey.of(Program.UnlitTextured).withBackTexture();
	let backValues: Vec<float32> = valuesOf(back);
	backValues[movingBase(back) + MOVING_BACK_UV_MATRIX] = -1.0;
	backValues[movingBase(back) + MOVING_BACK_UV_OFFSET] = 1.0;
	place(Quad.Back, {
		...materialFor(back, backValues, false), texture: red, backTexture: backTexture,
	}, true);
	place(Quad.Front, {
		...materialFor(back, backValues, false), texture: red, backTexture: backTexture,
	}, false);

	const dissolve: ProgramKey = ProgramKey.of(Program.UnlitTextured).withDissolve();
	let dissolveValues: Vec<float32> = valuesOf(dissolve);
	const base: int32 = movingBase(dissolve);
	dissolveValues[base + MOVING_DISSOLVE_THRESHOLD] = 0.5;
	dissolveValues[base + MOVING_DISSOLVE_EDGE_WIDTH] = 0.4;
	dissolveValues[base + MOVING_DISSOLVE_EDGE_COLOR] = 1.0;
	dissolveValues[base + MOVING_DISSOLVE_EDGE_COLOR + 2] = 1.0;
	dissolveValues[base + MOVING_DISSOLVE_EDGE_COLOR + 3] = 1.0;
	place(Quad.Dissolve, {
		...materialFor(dissolve, dissolveValues, true), texture: white, dissolveTexture: noise,
	}, false);

	const litDissolve: ProgramKey = ProgramKey.of(Program.LitTextured).withDissolve();
	let litValues: Vec<float32> = valuesOf(litDissolve);
	litValues[movingBase(litDissolve) + MOVING_DISSOLVE_THRESHOLD] = 0.5;
	litValues[movingBase(litDissolve) + MOVING_DISSOLVE_EDGE_WIDTH] = 0.1;
	place(Quad.LitDissolve, {
		...materialFor(litDissolve, litValues, true), texture: white, dissolveTexture: noise,
	}, false);

	// Two frames side by side, a frame a second; at 1.5 s and 2.5 s the first reads 1 then 0.
	const flipbook: ProgramKey = ProgramKey.of(Program.UnlitTextured).withUvTransform();
	const frames: TextureId = texture([BLUE, YELLOW], Wrap.Clamp);
	place(Quad.Flipbook, {
		...materialFor(flipbook, flipbookValues(flipbook, -0.5, 0.0), true), texture: frames,
	}, false);
	place(Quad.BlendedFlipbook, {
		...materialFor(flipbook, flipbookValues(flipbook, -0.25, 1.0), true), texture: frames,
	}, false);

	// About 4.9 from the eye, inside a near fade from 4 to 6: a bit under half its alpha.
	let fadeValues: Vec<float32> = valuesOf(flipbook);
	fadeValues[movingBase(flipbook) + MOVING_FADE_NEAR_START] = 4.0;
	fadeValues[movingBase(flipbook) + MOVING_FADE_NEAR_END] = 6.0;
	place(Quad.Fade, { ...blendedFor(flipbook, fadeValues, true, true), texture: red }, false);

	setAmbient(scene, vec3(1.0, 1.0, 1.0));
	setCameraPosition(core(), vec3(0.0, 0.0, 4.0));
	setElapsedTime(core(), ELAPSED);
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

function near(value: int64, expected: int64): boolean {
	return value - expected <= 2 && expected - value <= 2;
}

function isColor(rgb: int64, texel: uint32): boolean {
	return near((rgb >> 16) & 0xFF, (texel & 0xFF) as int64) &&
		near((rgb >> 8) & 0xFF, ((texel >> 8) & 0xFF) as int64) &&
		near(rgb & 0xFF, ((texel >> 16) & 0xFF) as int64);
}

function isBackground(rgb: int64): boolean {
	return near((rgb >> 16) & 0xFF, 26) && near(rgb & 0xFF, 51);
}

function check(camera: CameraView, swapped: boolean): void {
	const mappedLeft: int64 = rgbAt(camera, Quad.Affine, -1.0);
	if (!isColor(mappedLeft, GREEN) || !isColor(rgbAt(camera, Quad.Affine, 1.0), GREEN)) {
		fail(`the UV transform did not map the quad onto the right texel: ${mappedLeft}`);
	}
	const left: int64 = rgbAt(camera, Quad.Scroll, -1.0);
	const right: int64 = rgbAt(camera, Quad.Scroll, 1.0);
	console.log(`moving material: time ${core().time}, scroll ${left} ${right}`);
	const leftTexel: uint32 = swapped ? GREEN : RED;
	if (!isColor(left, leftTexel) || !isColor(right, swapped ? RED : GREEN)) {
		fail(`the scroll did not move with the time: ${left} ${right}`);
	}
	const backLeft: int64 = rgbAt(camera, Quad.Back, -1.0);
	const backRight: int64 = rgbAt(camera, Quad.Back, 1.0);
	if (!isColor(backLeft, BLUE) || !isColor(backRight, YELLOW)) {
		fail(`the back face drew ${backLeft} ${backRight}, not its mirrored back texture`);
	}
	if (!isColor(rgbAt(camera, Quad.Front, -1.0), RED)) {
		fail("the front face did not draw the front texture");
	}
	const kept: int64 = rgbAt(camera, Quad.Dissolve, 1.0);
	if (!isBackground(rgbAt(camera, Quad.Dissolve, -1.0))) {
		fail("the dissolved half drew");
	}
	if (!isColor(kept, 0xFFFF00FF)) { fail(`the edge band drew ${kept}, not its edge colour`); }
	const litKept: int64 = rgbAt(camera, Quad.LitDissolve, 1.0);
	if (!isBackground(rgbAt(camera, Quad.LitDissolve, -1.0))) {
		fail("the lit dissolved half drew");
	}
	if (isBackground(litKept) || isColor(litKept, 0xFFFF00FF)) {
		fail(`the lit kept half drew ${litKept}, outside its narrow edge band`);
	}
	checkFlipbooks(camera, swapped);
	const faded: int64 = rgbAt(camera, Quad.Fade, 0.0);
	const fadedRed: int64 = (faded >> 16) & 0xFF;
	if (fadedRed < 60 || fadedRed > 200 || (faded & 0xFF) < 20) {
		fail(`the faded quad drew ${faded}, not red over the background at about half alpha`);
	}
}

// The plain flipbook holds one frame over the whole quad; the blended one leans a quarter of the
// way to the next frame, so it is mostly yellow at 1.25 s and mostly blue at 2.25 s.
function checkFlipbooks(camera: CameraView, first: boolean): void {
	const held: uint32 = first ? YELLOW : BLUE;
	const left: int64 = rgbAt(camera, Quad.Flipbook, -1.0);
	const right: int64 = rgbAt(camera, Quad.Flipbook, 1.0);
	if (!isColor(left, held) || !isColor(right, held)) {
		fail(`the flipbook drew ${left} ${right}, not one frame over the quad`);
	}
	const mixed: int64 = rgbAt(camera, Quad.BlendedFlipbook, -1.0);
	const red: int64 = (mixed >> 16) & 0xFF;
	const blue: int64 = mixed & 0xFF;
	const leaning: boolean = first ? red > blue + 40 : blue > red + 40;
	if (isColor(mixed, YELLOW) || isColor(mixed, BLUE) || !leaning) {
		fail(`the blended flipbook drew ${mixed}, not a quarter of the way to the next frame`);
	}
}

function frame(): void {
	if (fbWidth() != WIDTH || fbHeight() != HEIGHT) { fail("the framebuffer size changed"); }
	frameIndex = frameIndex + 1;
	if (refresh(scene, items) != 9) { fail("the scene does not draw its nine quads"); }
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
	if (frameIndex == 4 || frameIndex == LAST_FRAME) {
		if (core().time != ELAPSED * (frameIndex as float64)) {
			fail(`the time is ${core().time} after ${frameIndex} frames`);
		}
		if (voidCaptureGrab(0) == 0) { fail("readback failed"); }
		check(camera, frameIndex == 4);
	}
	if (frameIndex < LAST_FRAME) { return; }
	if (failures > 0) { voidCaptureExit(1); }
	console.log("PASS moving material: affine, scroll, back texture, dissolve, flipbook, fade");
	voidCaptureExit(0);
}

voidRunConfigured(WIDTH, HEIGHT, 1, 0, init, frame);
