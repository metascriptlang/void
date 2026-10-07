import { env } from "std/process";
import { gfxSetup, fbWidth, fbHeight } from "../../src/sokol/gpu";
import { Vec3, Vec4, vec3, srgbToLinear, linearToSrgb } from "../../src/math/math3d";
import { RenderState, BlendMode, FilterMode, Wrap } from "../../src/gpu/state";
import {
	PixelFormat, LoadAction, contextGeneration, destroyImage, destroyView, endPass,
} from "../../src/gpu/door";
import { doorBeginColorPass } from "../../src/gpu/door.h";
import { RenderTarget, ColorAttachment, NO_DEPTH, beginPass } from "../../src/gpu/target";
import { Scene2D, NodeRef } from "../../src/void2d/node";
import { create } from "../../src/void2d/scene";
import { setup2d } from "../../src/void2d/draw";
import { rgba } from "../../src/void2d/types";
import { Material, Phase, UniformBlock } from "../../src/void3d/material";
import { MeshData, MeshError, Rgba, addTexturedQuad } from "../../src/void3d/meshData";
import {
	TextureData, TextureId, TextureUploadError, TextureAlpha,
} from "../../src/void3d/texture";
import {
	Program, MATERIAL_UNIFORM_SLOT, MATERIAL_UNIFORM_LENGTH, UNLIT_MATERIAL_UNIFORM_LENGTH,
	VERTEX_UNIFORM_LENGTH, LIGHT_UNIFORM_LENGTH,
	ProgramKey,
} from "../../src/void3d/gpu3d";
import {
	DrawContext, DrawItem, MeshId, MaterialId, MeshUploadError, MaterialError,
	HandleError, addMeshData, addMaterial, addTexture, addTargetTexture, releaseMaterial,
	releaseTexture, releaseUniforms, reserveUniforms, writeUniforms,
} from "../../src/void3d/draw";
import { loseTextureAt } from "../../src/test/drawHelpers";
import { UniformError } from "../../src/void3d/uniformPool";
import {
	Scene3D, Transform3D, NodeId3D, SceneError, LightKind, LightInstance, LightError,
	addMeshNode, addLightNode, setAmbient, refresh, collectLights, closeScene,
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
const UI_WIDTH: int32 = 64;
const PREMULTIPLIED_UNLIT: ProgramKey = ProgramKey.of(Program.UnlitTextured).withPremultiplied();
const UI_HEIGHT: int32 = 32;
const RESIZED_WIDTH: int32 = 96;
const RESIZED_HEIGHT: int32 = 48;
const HALF_ALPHA: float32 = (128.0 / 255.0) as float32;
const LOW_AMBIENT: float32 = 0.2474;
const BACKDROP_TEXEL: uint32 = 0xFF20A040;
const BACKDROP_PIXEL: int64 = 0x40A020FF;
const BLACK: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };
const WHITE: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };
const SCREEN: LowResView = { width: 320, height: 240, scale: 1, offsetX: 0.0, offsetY: 0.0 };
const UNLIT_X: float32 = -1.0;
const LIT_X: float32 = 1.0;
let context: DrawContext = DrawContext.withUniformCapacity(
	FORWARD_UNIFORM_LENGTH + PIXEL_ART_UNIFORM_LENGTH + 4 * UNLIT_MATERIAL_UNIFORM_LENGTH +
	4 * MATERIAL_UNIFORM_LENGTH,
);
let scene: Scene3D = Scene3D.create(context);
let forward: ForwardRenderer = makeForward();
let preset: PixelArtRenderer = makePreset();
const ui: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 0.0));
let target: RenderTarget = RenderTarget.unallocated(PixelFormat.Rgba8, true);
let targetTexture: TextureId = { store: 0, index: 0, generation: 0 };
let backdrop: TextureId = { store: 0, index: 0, generation: 0 };
let items: Vec<DrawItem> = [];
let cameraValues: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let red: NodeRef = ui.group();
let pixelArt: boolean = false;
let control: boolean = false;
let misuse: string = "";
let litMaterial: MaterialId = { store: 0, index: 0, generation: 0 };
let sampling: Vec<MaterialId> = [];
let paintedImage: uint32 = 0;
let lostImage: uint32 = 0;
let lostAttachment: uint32 = 0;
let lostView: uint32 = 0;
let stage: int32 = 0;

function fail(message: string): void {
	console.log(`FAIL target texture: stage ${stage}: ${message}`);
	voidCaptureExit(1);
}

function makeForward(): ForwardRenderer {
	const made: Result<ForwardRenderer, ForwardError> = ForwardRenderer.create(context, BLACK);
	if (made.ok) { return made.value; }
	unreachable;
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

function block(lit: boolean): UniformBlock {
	const length: int32 = lit ? MATERIAL_UNIFORM_LENGTH : UNLIT_MATERIAL_UNIFORM_LENGTH;
	const reserved: Result<UniformBlock, UniformError> =
		reserveUniforms(context, MATERIAL_UNIFORM_SLOT, length);
	if (!reserved.ok) { unreachable; }
	const values: Vec<float32> = lit ? [4.0, 0.0, 0.0, 0.0] :
		[0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0];
	if (!writeUniforms(context, reserved.value, values).ok) { unreachable; }
	return reserved.value;
}

function premultipliedPass(): RenderState {
	const pass: RenderState = RenderState.defaults();
	return pass.withDepth(false, pass.depthTest).withBlendMode(BlendMode.AlphaAdd);
}

function refused(material: Material, expected: MaterialError, what: string): void {
	const added: Result<MaterialId, MaterialError> = addMaterial(context, material);
	if (added.ok) { fail(`${what} was accepted`); }
	if (!added.ok && added.error != expected) {
		fail(`${what} was refused with ${added.error.toString()}, not ${expected.toString()}`);
	}
	if (!releaseUniforms(context, material.uniforms).ok) { fail(`${what} kept its uniforms`); }
}

function quad(x: float32, z: float32, half: float32, left: float32): MeshId {
	let mesh: MeshData = MeshData.withUvs();
	const built: Result<int32, MeshError> = addTexturedQuad(
		mesh, vec3(x + left, -half, z), vec3(x + half, -half, z),
		vec3(x + half, half, z), vec3(x + left, half, z), vec3(0.0, 0.0, 1.0), WHITE,
	);
	if (!built.ok) { unreachable; }
	const uploaded: Result<MeshId, MeshUploadError> = addMeshData(context, mesh);
	if (uploaded.ok) { return uploaded.value; }
	unreachable;
}

function place(mesh: MeshId, material: MaterialId): void {
	const placed: Result<NodeId3D, SceneError> =
		addMeshNode(scene, scene.rootId(), Transform3D.identity(), mesh, material);
	if (!placed.ok) { unreachable; }
}

function added(material: Material): MaterialId {
	const made: Result<MaterialId, MaterialError> = addMaterial(context, material);
	if (made.ok) { return made.value; }
	fail(`a material was refused: ${made.error.toString()}`);
	unreachable;
}

function targetMaterial(program: ProgramKey, lit: boolean): Material {
	return {
		...Material.keyed(program, premultipliedPass(), Phase.Alpha),
		texture: targetTexture, uniforms: block(lit),
	};
}

function straightControl(): Material {
	return {
		...Material.plain(Program.LitTextured, premultipliedPass(), Phase.Alpha),
		texture0: target.asTexture(), sampler0: context.textures[targetTexture.index].sampler,
		uniforms: block(true),
	};
}

function init(): void {
	if (voidCaptureBackend() == 0) { voidCaptureExit(3); }
	gfxSetup();
	setup2d();
	pixelArt = env.get("VOID_TARGET_TEXTURE_PRESET").equals("pixelArt");
	control = env.get("VOID_TARGET_TEXTURE_STRAIGHT_CONTROL").equals("1");
	misuse = env.get("VOID_TARGET_TEXTURE_MISUSE");
	red = ui.rect((UI_WIDTH / 2) as float32, UI_HEIGHT as float32, rgba(1.0, 0.0, 0.0, 0.5));
	ui.add(red);
	target = RenderTarget.allocate(UI_WIDTH, UI_HEIGHT, PixelFormat.Rgba8, true);
	const unsampled: RenderTarget = RenderTarget.allocate(8, 8, PixelFormat.Rgba8, false);
	const notSampled: Result<TextureId, TextureUploadError> = addTargetTexture(
		context, unsampled, FilterMode.Nearest, Wrap.Clamp, TextureAlpha.Premultiplied,
	);
	if (notSampled.ok || notSampled.error != TextureUploadError.TargetNotSampled) {
		fail("a target without a texture view was accepted");
	}
	unsampled.close();
	const made: Result<TextureId, TextureUploadError> = addTargetTexture(
		context, target, FilterMode.Nearest, Wrap.Clamp, TextureAlpha.Premultiplied,
	);
	if (!made.ok) { fail(`addTargetTexture refused: ${made.error.toString()}`); }
	if (made.ok) { targetTexture = made.value; }
	const data: TextureData = {
		pixels: [BACKDROP_TEXEL], width: 1, height: 1, filter: FilterMode.Nearest, wrap: Wrap.Clamp,
	};
	const uploaded: Result<TextureId, TextureUploadError> = addTexture(context, data);
	if (!uploaded.ok) { unreachable; }
	backdrop = uploaded.value;

	refused({ ...targetMaterial(ProgramKey.of(Program.UnlitTextured), false) },
		MaterialError.PremultipliedTexture, "a straight program over a premultiplied target");
	refused({ ...targetMaterial(PREMULTIPLIED_UNLIT, false), texture: backdrop },
		MaterialError.StraightTexture, "a premultiplied program over a straight texture");
	refused({
		...targetMaterial(PREMULTIPLIED_UNLIT, false),
		pass: RenderState.defaults().withBlendMode(BlendMode.Alpha),
	}, MaterialError.StraightBlend, "a premultiplied program blending straight alpha");

	const backdropMaterial: MaterialId = added({
		...Material.plain(Program.UnlitTextured, RenderState.defaults(), Phase.Opaque),
		texture: backdrop, uniforms: block(false),
	});
	place(quad(UNLIT_X, -0.5, HALF, 0.0), backdropMaterial);
	place(quad(LIT_X, -0.5, HALF, 0.0), backdropMaterial);
	const unlitMaterial: MaterialId =
		added(targetMaterial(PREMULTIPLIED_UNLIT, false));
	place(quad(UNLIT_X, 0.0, HALF, -HALF), unlitMaterial);
	sampling.push(unlitMaterial);
	litMaterial = added(control ? straightControl() :
		targetMaterial(ProgramKey.of(Program.LitTextured).withPremultiplied(), true));
	place(quad(LIT_X, 0.0, HALF, -HALF), litMaterial);
	if (!control) { sampling.push(litMaterial); }
	const light: LightInstance = {
		kind: LightKind.Directional, color: vec3(1.0, 1.0, 1.0),
		radius: 0.0, power: 0.0, priority: 0,
	};
	const _sun: NodeId3D = addLightNode(scene, scene.rootId(), {
		...Transform3D.identity(), rotation: { x: 0.0, y: 1.0, z: 0.0, w: 0.0 },
	}, light);
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

function expectedRed(light: float32): int32 {
	return Math.round(linearToSrgb(srgbToLinear(1.0) * light) * HALF_ALPHA * 255.0) as int32;
}

function checkRed(
	view: CameraView,
	x: float32,
	expected: int32,
	exact: boolean,
	what: string,
): void {
	const pixel: int64 = pixelAt(view, x - HALF / 2.0);
	const redByte: int32 = ((pixel >> 24) & 255) as int32;
	const rest: int64 = pixel & 0x00FFFF00;
	const off: int32 = Math.abs(redByte - expected) as int32;
	if (rest != 0 || off > (exact ? 0 : 1)) {
		fail(`${what}: the premultiplied half-red texel drew ${pixel}, expected red ${expected}`);
	}
}

function checkTransparent(view: CameraView, x: float32, what: string): void {
	const pixel: int64 = pixelAt(view, x + HALF / 2.0);
	if (pixel != BACKDROP_PIXEL) {
		fail(`${what}: a zero-alpha texel changed the backdrop to ${pixel}`);
	}
}

function holdsUnchanged(): void {
	const pins: int32 = sampling.length as int32;
	if (!context.hasTexture(targetTexture) || context.texturePinned(targetTexture) != pins ||
		context.textureHolders[targetTexture.index] != pins + 1) {
		fail(`the target texture's holds moved: pinned ${context.texturePinned(targetTexture)}, ` +
			`held ${context.textureHolders[targetTexture.index]}`);
	}
}

// Both ways a pass opens on a target: the door's descriptor pass (3D) and its colour pass (2D).
function checkOpenPassViews(): void {
	if (target.isAttachedToOpenPass()) { fail("a target is attached with no pass open"); }
	const colors: Vec<ColorAttachment> = [target.asColor(LoadAction.Load, BLACK)];
	beginPass(colors, NO_DEPTH);
	if (!target.isAttachedToOpenPass()) { fail("the 3D pass path does not report its attachment"); }
	endPass();
	if (target.isAttachedToOpenPass()) { fail("endPass left the 3D pass's attachment recorded"); }
	doorBeginColorPass(target.attachment, 0.0, 0.0, 0.0, 0.0);
	if (!target.isAttachedToOpenPass()) { fail("the 2D pass path does not report its attachment"); }
	endPass();
	if (target.isAttachedToOpenPass()) { fail("endPass left the 2D pass's attachment recorded"); }
}

function sampleOwnScene(): void {
	const sceneTarget: RenderTarget = pixelArt ? preset.colorTarget : forward.colorTarget;
	const made: Result<TextureId, TextureUploadError> = addTargetTexture(
		context, sceneTarget, FilterMode.Nearest, Wrap.Clamp, TextureAlpha.Straight,
	);
	if (!made.ok) { fail(`the scene target was refused: ${made.error.toString()}`); }
	if (!made.ok) { return; }
	place(quad(UNLIT_X, 0.5, HALF / 2.0, -HALF / 2.0), added({
		...Material.plain(Program.UnlitTextured, RenderState.defaults(), Phase.Opaque),
		texture: made.value, uniforms: block(false),
	}));
}

function loseContext(): void {
	lostImage = target.image;
	lostAttachment = target.attachment;
	lostView = target.texture;
	target.generation = 0;
	target.attachment = pixelArt ? preset.colorTarget.attachment : forward.colorTarget.attachment;
	for (let i = 0; i < (context.meshes.length as int32); i++) {
		if (context.meshData[i].vertexCount() > 0) { context.meshes[i].generation = 0; }
	}
	for (let i = 0; i < (context.textures.length as int32); i++) {
		loseTextureAt(context, i);
	}
	context.samplerGeneration = 0;
	forward.core.generation = 0;
	preset.core.generation = 0;
}

function remakeTarget(): void {
	destroyView(lostView);
	destroyView(lostAttachment);
	destroyImage(lostImage);
	target.resize(RESIZED_WIDTH, RESIZED_HEIGHT);
	if (target.image == lostImage || target.generation != contextGeneration()) {
		fail("the owner's resize did not remake the target after the lost context");
	}
}

function produce(): void {
	if (target.generation != contextGeneration() || target.image == paintedImage) { return; }
	ui.prepare(target.width as float32, target.height as float32, 1.0);
	red.setSize((target.width / 2) as float32, target.height as float32);
	ui.drawTarget(target);
	paintedImage = target.image;
}

function render(): void {
	const quads: int32 = misuse.equals("feedback") && stage >= 2 ? 5 : 4;
	if (refresh(scene, items) != quads) { fail("the scene does not draw its quads"); }
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
}

function frame(): void {
	if (fbWidth() != WIDTH || fbHeight() != HEIGHT) { fail("the framebuffer size changed"); }
	const low: boolean = stage == 1;
	setAmbient(scene, low ? vec3(LOW_AMBIENT, LOW_AMBIENT, LOW_AMBIENT) : vec3(1.0, 1.0, 1.0));
	if (stage == 2) {
		const held: TextureId = targetTexture;
		target.resize(RESIZED_WIDTH, RESIZED_HEIGHT);
		if (!context.hasTexture(held)) { fail("a resize invalidated the texture id"); }
	}
	if (stage == 1) {
		checkOpenPassViews();
		paintedImage = 0;
	}
	if (misuse.equals("feedback") && stage == 2) { sampleOwnScene(); }
	if (stage == 3) { loseContext(); }
	if (stage == 4) { remakeTarget(); }
	if (misuse.equals("closed") && stage == 2) { target.close(); }
	if (misuse.equals("program") && stage == 2) {
		context.materials[litMaterial.index].program = ProgramKey.of(Program.LitTextured);
	}
	produce();
	render();
	if (voidCaptureGrab(0) == 0) { fail("readback failed"); }
	const view: CameraView = viewOf();
	if (stage == 3) {
		const pixel: int64 = pixelAt(view, UNLIT_X - HALF / 2.0);
		if (pixel != 0x000000FF) {
			fail(`a target of the lost context drew ${pixel} before its owner remade it`);
		}
		checkTransparent(view, UNLIT_X, "lost context");
	} else {
		checkRed(view, UNLIT_X, expectedRed(1.0), true, "unlit");
		const light: float32 = low ? srgbToLinear(LOW_AMBIENT) : 1.0;
		checkRed(view, LIT_X, expectedRed(light), !low, "lit");
		checkTransparent(view, UNLIT_X, "unlit");
		checkTransparent(view, LIT_X, "lit");
	}
	holdsUnchanged();
	console.log(`target texture: stage ${stage} checked`);
	stage = stage + 1;
	if (stage < 5) { return; }
	closeScene(scene);
	for (const material of sampling) {
		const released: Result<int32, HandleError> = releaseMaterial(context, material);
		if (!released.ok || released.value != 0) { fail("a sampling material outlived its holds"); }
	}
	const left: Result<int32, HandleError> = releaseTexture(context, targetTexture);
	if (!left.ok || left.value != 0 || context.hasTexture(targetTexture)) {
		fail("the caller's hold was not the target texture's last");
	}
	target.close();
	console.log("PASS target texture: checked id, unpremultiply/decode/re-premultiply, " +
		"zero alpha, resize, lost context, holds");
	voidCaptureExit(0);
}

voidRunConfigured(WIDTH, HEIGHT, 1, 0, init, frame);
