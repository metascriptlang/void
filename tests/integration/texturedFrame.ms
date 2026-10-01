import { gfxSetup, fbWidth, fbHeight } from "../../src/sokol/gpu";
import { Vec3, Vec4, vec3, eulerQuat } from "../../src/math/math3d";
import { RenderState, FilterMode, Wrap } from "../../src/gpu/state";
import { beginScreenPass } from "../../src/gpu/target";
import {
	endPass,
	commit,
	contextGeneration,
	liveImages,
	liveViews,
	liveSamplers,
} from "../../src/gpu/door";
import { Material, Phase, UniformBlock } from "../../src/void3d/material";
import { MeshData, MeshError, Rgba, addTexturedCube } from "../../src/void3d/meshData";
import { TextureData, TextureId, GpuTexture, TextureUploadError } from "../../src/void3d/texture";
import { UniformError } from "../../src/void3d/uniformPool";
import {
	Program,
	MATERIAL_UNIFORM_SLOT,
	MATERIAL_UNIFORM_LENGTH,
	VERTEX_UNIFORM_LENGTH,
	LIGHT_UNIFORM_LENGTH,
} from "../../src/void3d/gpu3d";
import {
	DrawContext,
	DrawItem,
	MeshId,
	MaterialId,
	MaterialError,
	MeshUploadError,
	HandleError,
	addMeshData,
	addMaterial,
	addTexture,
	retainTexture,
	releaseTexture,
	releaseMaterial,
	reserveUniforms,
	writeUniforms,
	rebuildMeshes,
	rebuildTextures,
	buryDoomed,
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
	setLocal,
	setAmbient,
	setLightPower,
	refresh,
	collectLights,
} from "../../src/void3d/scene";
import { Camera3D, ProjectionKind, CameraView, CameraError } from "../../src/void3d/camera";
import { LowResView } from "../../src/void3d/blit";
import {
	ForwardRenderer,
	ForwardError,
	FORWARD_UNIFORM_LENGTH,
	prepareFrame,
	drawToScreen,
} from "../../src/void3d/forwardRenderer";
import {
	PixelArtRenderer,
	PixelArtSettings,
	PixelArtLook,
	PixelArtError,
	PIXEL_ART_UNIFORM_LENGTH,
	renderFrame as renderPixelArt,
} from "../../src/void3d/pixelArtRenderer";
import {
	voidCaptureBackend,
	voidCaptureGrab,
	voidCapturePixel,
	voidCaptureSlotsDiffer,
	voidCaptureExit,
} from "../capture/capture.h";

let WIDTH: int32 = 320;
let HEIGHT: int32 = 240;
let BACKGROUND: Vec4 = { x: 0.025, y: 0.05, z: 0.1, w: 1.0 };
let WHITE: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };
let RED: uint32 = 0xFF0000FF;
let GREEN: uint32 = 0xFF00FF00;
let BLUE: uint32 = 0xFFFF0000;
let YELLOW: uint32 = 0xFF00FFFF;
let HALF: float32 = 0.6;
let DEPTH_THRESHOLD: float32 = 0.006;
let DEPTH_SHADE: float32 = 0.55;
let SCREEN_MAPPING: LowResView = {
	width: 320, height: 240, scale: 1, offsetX: 0.0, offsetY: 0.0,
};
let context: DrawContext = DrawContext.withUniformCapacity(
	FORWARD_UNIFORM_LENGTH + 2 * PIXEL_ART_UNIFORM_LENGTH + 3 * MATERIAL_UNIFORM_LENGTH,
);
let forward: ForwardRenderer = createForward();
let preset: PixelArtRenderer = createPreset(false);
let outlinedPreset: PixelArtRenderer = createPreset(true);
let scene: Scene3D = Scene3D.create();
let items: Vec<DrawItem> = [];
let cube: NodeId3D = { index: 0, generation: 0 };
let sun: NodeId3D = { index: 0, generation: 0 };
let lamp: NodeId3D = { index: 0, generation: 0 };
let texture: TextureId = { index: 0, generation: 0 };
let cameraBlock: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let pixelArt: boolean = false;
let outlined: boolean = false;
let rebuildAt: int32 = -1;
let viewBefore: uint32 = 0;
let samplerBefore: uint32 = 0;

function createForward(): ForwardRenderer {
	let created: Result<ForwardRenderer, ForwardError> =
		ForwardRenderer.create(context, BACKGROUND);
	if (created.ok) { return created.value; }
	unreachable;
}

function createPreset(postPass: boolean): PixelArtRenderer {
	let settings: PixelArtSettings = { ...PixelArtSettings.full(), postPass: postPass };
	let look: PixelArtLook = {
		background: BACKGROUND,
		outline: {
			depthThreshold: DEPTH_THRESHOLD,
			normalThreshold: 0.6,
			depthShade: DEPTH_SHADE,
			normalShade: 1.35,
		},
		fog: { start: 1.0, end: 1.0, strength: 0.0, color: BACKGROUND },
		saturation: 0.0,
	};
	let created: Result<PixelArtRenderer, PixelArtError> =
		PixelArtRenderer.create(context, settings, look);
	if (created.ok) { return created.value; }
	unreachable;
}

function fail(message: string): void {
	console.log(`FAIL textured frame: ${message}`);
	voidCaptureExit(1);
}

export function configureTextured(
	throughPixelArt: boolean,
	withOutline: boolean,
	rebuildFrame: int32,
): void {
	pixelArt = throughPixelArt || withOutline;
	outlined = withOutline;
	rebuildAt = rebuildFrame;
}


function quadrants(): TextureData {
	return {
		pixels: [RED, GREEN, BLUE, YELLOW],
		width: 2,
		height: 2,
		filter: FilterMode.Nearest,
		wrap: Wrap.Clamp,
	};
}

function texturedMaterial(image: TextureId): MaterialId {
	let reserved: Result<UniformBlock, UniformError> =
		reserveUniforms(context, MATERIAL_UNIFORM_SLOT, MATERIAL_UNIFORM_LENGTH);
	if (!reserved.ok) { unreachable; }
	let levels: Vec<float32> = [4.0, 0.0, 0.0, 0.0];
	if (!writeUniforms(context, reserved.value, levels).ok) { unreachable; }
	let plain: Material =
		Material.plain(Program.LitTextured, RenderState.defaults(), Phase.Opaque);
	let added: Result<MaterialId, MaterialError> =
		addMaterial(context, { ...plain, texture: image, uniforms: reserved.value });
	if (!added.ok) {
		fail(`the textured material was refused: ${added.error.toString()}`);
		unreachable;
	}
	return added.value;
}

function holders(result: Result<int32, HandleError>): int32 {
	if (result.ok) { return result.value; }
	fail(`a texture hold was refused: ${result.error.toString()}`);
	unreachable;
}

function made(data: TextureData): TextureId {
	let added: Result<TextureId, TextureUploadError> = addTexture(context, data);
	if (added.ok) { return added.value; }
	fail(`the driver refused a two-by-two texture: ${added.error.toString()}`);
	unreachable;
}

function releasedMaterial(material: MaterialId): int32 {
	let freed: Result<int32, HandleError> = releaseMaterial(context, material);
	if (freed.ok) { return freed.value; }
	fail(`a material release was refused: ${freed.error.toString()}`);
	unreachable;
}

function checkLifetime(): void {
	let images: int32 = liveImages();
	let views: int32 = liveViews();
	let samplers: int32 = liveSamplers();
	let first: TextureId = made(quadrants());
	let second: TextureId = made(quadrants());
	if (liveImages() != images + 2 || liveViews() != views + 2 || liveSamplers() != samplers + 1) {
		fail(
			`two textures on one filter and wrap made images=${liveImages() - images} ` +
			`views=${liveViews() - views} samplers=${liveSamplers() - samplers}, expected 2 2 1`,
		);
	}
	let linear: TextureId = made({ ...quadrants(), filter: FilterMode.Linear, wrap: Wrap.Repeat });
	let mirrored: TextureId = made({ ...quadrants(), wrap: Wrap.Mirror });
	if (liveSamplers() != samplers + 3) {
		fail(`three filter and wrap settings made ${liveSamplers() - samplers} samplers, not 3`);
	}
	if (holders(retainTexture(context, first)) != 2) { fail("a retain added no holder"); }
	if (holders(releaseTexture(context, first)) != 1) { fail("a release let none go"); }
	let once: MaterialId = texturedMaterial(first);
	if (context.texturePinned(first) != 1) { fail("the material does not pin its texture"); }
	if (holders(releaseTexture(context, first)) != 1) { fail("the release took the pin"); }
	let pinned: Result<int32, HandleError> = releaseTexture(context, first);
	if (pinned.ok || pinned.error != HandleError.OnlyPinned) {
		fail("a release past the loader's hold was taken while the material pins the texture");
	}
	let twice: MaterialId = texturedMaterial(first);
	if (context.texturePinned(first) != 2) { fail("a second material did not pin the texture"); }
	if (releasedMaterial(once) != 0 || !context.hasTexture(first)) {
		fail("freeing one of two materials freed the texture both pin");
	}
	if (releasedMaterial(twice) != 0 || context.hasTexture(first)) {
		fail("freeing the last material did not free the texture it pinned");
	}
	let stale: Result<int32, HandleError> = retainTexture(context, first);
	if (stale.ok || stale.error != HandleError.StaleTexture) {
		fail("a freed texture's id was not refused as stale");
	}
	let held: MaterialId = texturedMaterial(second);
	if (releasedMaterial(held) != 0 || !context.hasTexture(second)) {
		fail("freeing a material freed the texture its caller still holds");
	}
	if (holders(releaseTexture(context, second)) != 0) { fail("the caller's release kept it"); }
	if (holders(releaseTexture(context, linear)) != 0) { fail("a linear texture outlived it"); }
	if (holders(releaseTexture(context, mirrored)) != 0) { fail("a mirrored one outlived it"); }
	if (context.liveTextures() != 0) { fail("a released texture is still live"); }
	if (liveImages() != images + 4 || liveViews() != views + 4) {
		fail("a freed texture's image or view was destroyed before it was buried");
	}
	if (buryDoomed(context, contextGeneration()) != 4) {
		fail("the four freed textures were not buried");
	}
	if (liveImages() != images || liveViews() != views || liveSamplers() != samplers + 3) {
		fail("burying the freed textures left an image or view, or took a shared sampler");
	}
}

export function initTextured(): void {
	if (voidCaptureBackend() != 1) {
		console.log("SKIP textured frame: this consumer requires D3D11 readback");
		voidCaptureExit(3);
	}
	gfxSetup();
	checkLifetime();
	let made: Result<TextureId, TextureUploadError> = addTexture(context, quadrants());
	if (!made.ok) {
		fail("the driver refused the cube's texture");
		return;
	}
	texture = made.value;
	let data: MeshData = MeshData.withUvs();
	let edge: float32 = 2.0 * HALF;
	let built: Result<int32, MeshError> =
		addTexturedCube(data, vec3(edge, edge, edge), true, WHITE);
	if (!built.ok) { unreachable; }
	let mesh: Result<MeshId, MeshUploadError> = addMeshData(context, data);
	if (!mesh.ok) { unreachable; }
	let material: MaterialId = texturedMaterial(texture);
	let placed: Result<NodeId3D, SceneError> = addMeshNode(
		scene, context, scene.rootId(), Transform3D.identity(), mesh.value, material,
	);
	if (!placed.ok) { unreachable; }
	cube = placed.value;
	if (holders(releaseTexture(context, texture)) != 1) { fail("the loader's hold was not one"); }
	let light: LightInstance = {
		kind: LightKind.Directional,
		color: vec3(1.0, 1.0, 1.0),
		radius: 0.0,
		power: 0.0,
		priority: 0,
	};
	let towardCamera: Transform3D = {
		...Transform3D.identity(), rotation: { x: 0.0, y: 1.0, z: 0.0, w: 0.0 },
	};
	sun = addLightNode(scene, scene.rootId(), towardCamera, light);
	let point: LightInstance = { ...light, kind: LightKind.Point, radius: 2.5 };
	lamp = addLightNode(
		scene, scene.rootId(), Transform3D.fromTranslation(vec3(0.0, 0.0, 1.6)), point,
	);
}

// The outlined configuration looks orthographically: the pixel-art programs write clip z as their
// depth, which is [0, 1] only when w is 1 (VOID3D.md, "M22 as built", still missing).
function viewOf(): CameraView {
	let perspective: Camera3D = {
		position: vec3(0.0, 0.0, 3.0),
		yaw: 0.0,
		pitch: 0.0,
		nearPlane: 0.5,
		farPlane: 30.0,
		projection: { kind: ProjectionKind.Perspective, fovY: 1.0471975512 },
	};
	let orthographic: Camera3D = {
		...perspective,
		farPlane: 6.0,
		projection: { kind: ProjectionKind.Orthographic, worldPerTexel: 0.01, snap: false },
	};
	let camera: Camera3D = outlined ? orthographic : perspective;
	let resolved: Result<CameraView, CameraError> = camera.resolve(WIDTH, HEIGHT);
	if (resolved.ok) { return resolved.value; }
	unreachable;
}

function stage(frameIndex: int32): int32 {
	if (frameIndex < 5) { return 0; }
	if (frameIndex < 10) { return 1; }
	if (frameIndex < 15) { return 2; }
	return 3;
}

function pose(frameIndex: int32): void {
	let turn: float32 = stage(frameIndex) == 1 || stage(frameIndex) == 2 ? 0.6 : 0.0;
	let tip: float32 = stage(frameIndex) == 2 ? 0.5 : 0.0;
	setLocal(scene, cube, { ...Transform3D.identity(), rotation: eulerQuat(tip, turn, 0.0) });
	let lit: boolean = stage(frameIndex) == 3;
	let lamplit: boolean = lit && pixelArt;
	let sunlit: boolean = lit && !pixelArt;
	let ambient: float32 = lamplit ? 0.0 : sunlit ? 0.25 : 1.0;
	setAmbient(scene, vec3(ambient, ambient, ambient));
	setLightPower(scene, sun, sunlit ? 0.25 : 0.0);
	setLightPower(scene, lamp, lamplit ? 3.0 : 0.0);
}

function rgbOf(pixel: int64): uint32 {
	return ((pixel >> 8) & 0xFFFFFF) as uint32;
}

function rgbOfTexel(texel: uint32): uint32 {
	return ((texel & 0xFF) << 16) | (texel & 0xFF00) | ((texel >> 16) & 0xFF);
}

function channelOf(rgb: uint32, shift: uint32): int32 {
	return ((rgb >> shift) & 0xFF) as int32;
}

function isHalfOf(got: uint32, texel: uint32): boolean {
	let want: uint32 = rgbOfTexel(texel);
	let shifts: Vec<uint32> = [16, 8, 0];
	for (const shift of shifts) {
		let difference: int32 = channelOf(got, shift) - (channelOf(want, shift) + 1) / 2;
		if (difference < -1 || difference > 1) { return false; }
	}
	return true;
}

function pixelAt(view: CameraView, point: Vec3): uint32 {
	let at: Vec3 = view.project(point, SCREEN_MAPPING, true);
	return rgbOf(voidCapturePixel(0, at.x as int32, at.y as int32));
}

function checkQuadrants(view: CameraView, lit: boolean): void {
	let corner: float32 = HALF * 0.5;
	let expected: Vec<uint32> = [RED, GREEN, BLUE, YELLOW];
	let points: Vec<Vec3> = [
		vec3(-corner, corner, HALF), vec3(corner, corner, HALF),
		vec3(-corner, -corner, HALF), vec3(corner, -corner, HALF),
	];
	for (let i = 0; i < 4; i++) {
		let got: uint32 = pixelAt(view, points[i]);
		let right: boolean = lit ? isHalfOf(got, expected[i]) : got == rgbOfTexel(expected[i]);
		if (!right) {
			fail(`front quadrant ${i} is ${got}, not its texel ${rgbOfTexel(expected[i])}`);
		}
	}
}

function isRampLevel(channel: int32): boolean {
	for (let level = 0; level <= 4; level++) {
		let difference: int32 = channel - (level * 255 + 2) / 4;
		if (difference >= -1 && difference <= 1) { return true; }
	}
	return false;
}

// The pixel-art preset steps a point light to the material's four ramp levels, where the core's
// program lights smoothly: every pixel of the red quadrant is red at one of those levels.
function checkStepped(view: CameraView): void {
	let from: Vec3 = view.project(vec3(-HALF, HALF, HALF), SCREEN_MAPPING, true);
	let to: Vec3 = view.project(vec3(0.0, 0.0, HALF), SCREEN_MAPPING, true);
	let levels: Vec<int32> = [0, 0, 0, 0, 0];
	for (let y = (from.y as int32) + 2; y < (to.y as int32) - 2; y++) {
		for (let x = (from.x as int32) + 2; x < (to.x as int32) - 2; x++) {
			let got: uint32 = rgbOf(voidCapturePixel(0, x, y));
			let red: int32 = channelOf(got, 16);
			if (channelOf(got, 8) != 0 || channelOf(got, 0) != 0 || !isRampLevel(red)) {
				fail(`pixel (${x}, ${y}) is ${got}, not the red texel at a ramp level`);
				return;
			}
			levels[(red * 4 + 127) / 255] = 1;
		}
	}
	if (levels[0] + levels[1] + levels[2] + levels[3] + levels[4] < 2) {
		fail("the point light shows one level on the red quadrant, so nothing was stepped");
	}
}

// Nearest sampling and no MSAA: under full light every pixel is the background or a texel.
function checkOnlyTexels(): void {
	let background: uint32 = rgbOf(voidCapturePixel(0, 2, 2));
	let seen: Vec<int32> = [0, 0, 0, 0];
	let texels: Vec<uint32> = [
		rgbOfTexel(RED), rgbOfTexel(GREEN), rgbOfTexel(BLUE), rgbOfTexel(YELLOW),
	];
	for (let y = 0; y < HEIGHT; y++) {
		for (let x = 0; x < WIDTH; x++) {
			let got: uint32 = rgbOf(voidCapturePixel(0, x, y));
			if (got == background) { continue; }
			let found: int32 = -1;
			for (let i = 0; i < 4; i++) {
				if (got == texels[i]) { found = i; }
			}
			if (found < 0) {
				fail(`pixel (${x}, ${y}) is ${got}, neither a texel nor the background`);
				return;
			}
			seen[found] = seen[found] + 1;
		}
	}
	for (let i = 0; i < 4; i++) {
		if (seen[i] == 0) { fail(`texel ${i} shows nowhere on the cube`); }
	}
}

function isShadeOf(channel: int32, full: float32): boolean {
	let difference: int32 = channel - ((full * 255.0 + 0.5) as int32);
	return difference >= -1 && difference <= 1;
}

// postFs shades a pixel whose neighbour lies behind it by the depth shade, which needs the
// program's depth in the normal target's alpha; and lifts a crease, where the normals it wrote
// part, by `rgb * normalShade + 0.02`, which leaves a texel's zero channels at 5.
function checkOutline(silhouette: boolean): void {
	let found: int32 = 0;
	for (let y = 0; y < HEIGHT; y++) {
		for (let x = 0; x < WIDTH; x++) {
			let got: uint32 = rgbOf(voidCapturePixel(0, x, y));
			let shaded: int32 = 0;
			let clear: int32 = 0;
			let shifts: Vec<uint32> = [16, 8, 0];
			for (const shift of shifts) {
				let channel: int32 = channelOf(got, shift);
				let low: boolean = silhouette ? channel == 0 : isShadeOf(channel, 0.02);
				let high: boolean = silhouette ? isShadeOf(channel, DEPTH_SHADE) : channel == 255;
				if (low) { clear = clear + 1; }
				if (high) { shaded = shaded + 1; }
			}
			if (shaded + clear == 3 && shaded > 0 && clear > 0) { found = found + 1; }
		}
	}
	if (found == 0) {
		fail(silhouette ? "no texel is shaded where the cube meets the background" :
			"no crease between the cube's faces is lifted");
	}
}

// A lost context simulated on a live one, through beginFrame's own new-context branch.
function loseContext(): void {
	viewBefore = context.textures[texture.index].view;
	samplerBefore = context.textures[texture.index].sampler;
	for (let i = 0; i < (context.meshes.length as int32); i++) {
		if (context.meshData[i].vertexCount() > 0) { context.meshes[i].generation = 0; }
	}
	context.textures[texture.index].generation = 0;
	context.samplerGeneration = 0;
	forward.core.generation = 0;
	preset.core.generation = 0;
	outlinedPreset.core.generation = 0;
}

function checkRemade(): void {
	let remade: GpuTexture = context.textures[texture.index];
	if (remade.view == viewBefore || remade.view == 0 || remade.sampler == samplerBefore ||
		remade.sampler == 0 || remade.generation != contextGeneration()) {
		fail(`the new context kept view ${remade.view} or sampler ${remade.sampler}`);
	}
}

function presetFrame(ref renderer: PixelArtRenderer): int32 {
	let frame: Result<int32, PixelArtError> =
		renderPixelArt(renderer, context, items, cameraBlock, lights, SCREEN_MAPPING);
	if (frame.ok) { return frame.value; }
	fail(`the pixel-art preset refused the textured cube: ${frame.error.toString()}`);
	return 0;
}

function drawn(): int32 {
	if (outlined) { return presetFrame(outlinedPreset); }
	if (pixelArt) { return presetFrame(preset); }
	let frame: Result<int32, ForwardError> =
		prepareFrame(forward, context, items, cameraBlock, lights, WIDTH, HEIGHT);
	if (!frame.ok) {
		fail(`the forward preset refused the textured cube: ${frame.error.toString()}`);
		return 0;
	}
	beginScreenPass(BACKGROUND);
	drawToScreen(forward, context);
	endPass();
	commit();
	return frame.value;
}

export function frameTextured(frameIndex: int32): void {
	if (fbWidth() != WIDTH || fbHeight() != HEIGHT) { fail("the framebuffer size changed"); }
	if (frameIndex == rebuildAt) { loseContext(); }
	pose(frameIndex);
	if (refresh(scene, items) != 1) { fail("the scene does not draw exactly the cube"); }
	let collected: Result<int32, LightError> = collectLights(scene, lights);
	if (!collected.ok) { unreachable; }
	let view: CameraView = viewOf();
	view.writeCameraBlock(cameraBlock);
	if (drawn() != 1) { fail("the frame did not draw the cube"); }
	if (frameIndex == rebuildAt) { checkRemade(); }
	if (frameIndex == 1 || frameIndex == 6 || frameIndex == 11 || frameIndex == 16) {
		if (voidCaptureGrab(0) == 0 || voidCaptureGrab(1) == 0) { fail("D3D11 readback failed"); }
		if (voidCaptureSlotsDiffer() != 0) { fail("two readbacks of the same frame differ"); }
		let lit: boolean = stage(frameIndex) == 3;
		if (stage(frameIndex) == 0 || (lit && !pixelArt)) { checkQuadrants(view, lit); }
		if (lit && pixelArt) { checkStepped(view); }
		if (!lit && !outlined) { checkOnlyTexels(); }
		if (outlined && stage(frameIndex) == 0) { checkOutline(true); }
		if (outlined && stage(frameIndex) == 2) { checkOutline(false); }
		console.log(`textured frame: frame ${frameIndex} checked`);
	}
	if (frameIndex == 16) {
		console.log(
			"PASS textured frame: uv orientation, exact texels, texel times light, lifetime",
		);
	}
}
