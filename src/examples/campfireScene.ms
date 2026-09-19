// The campfire spike: a hand-built scene drawn by the M3 renderer. Its meshes, camera and
// lights are spike code until M4-M7 replace them; the spike is deleted with M6.

import { gfxSetup, fbWidth, fbHeight } from "../sokol/gpu";
import { sinf, cosf } from "../math/mat4";
import {
	Program,
	VertexLayout,
	Filter,
	Wrap,
	makeVertexBuffer,
	makeImage,
	makeTextureView,
} from "../void3d/gpu3d";
import { RenderState, Face, Compare } from "../void3d/pass";
import { Material, Phase } from "../void3d/material";
import { Sampler } from "../void3d/target";
import { DrawContext, DrawItem, addMesh, addMaterial } from "../void3d/draw";
import { LowResView, ViewError } from "../void3d/blit";
import { PaletteError } from "../void3d/palette";
import {
	PixelArtRenderer,
	PixelArtSettings,
	PixelArtError,
	PixelArtLook,
	PIXEL_ART_UNIFORM_LENGTH,
	setPalette,
	setSettings,
	renderFrame,
} from "../void3d/pixelArtRenderer";
import { identity, Vec3, vec3 } from "../math/math3d";
import { Rgba, Box, LIT_VERTEX_STRIDE, pushBox, pushGround } from "../void3d/mesh";
import {
	OrthoCamera,
	CameraView,
	CameraError,
	CAMERA_BLOCK_LENGTH,
} from "../void3d/camera";

const UNITS_ON_SHORT_SIDE: float32 = 20.0;
const CAMERA_YAW: float32 = 0.785398;
const CAMERA_PITCH: float32 = 0.6;

const GROUND_HALF_SIZE: float32 = 40.0;
const GRASS_RADIUS: float32 = 22.0;
const GRASS_SPACING: float32 = 0.42;
const FIRE_CLEARING_RADIUS: float32 = 0.75;
const SPROUT_CHANCE: float32 = 0.04;
const SPROUT_TINT: float32 = 2.3;

const FLICKER_FRAMES: int32 = 4;
const FLAME_FRAMES: int32 = 4;
const ATLAS_CELLS: int32 = 4;
const TUFT_CELL: int32 = 16;
const FLAME_CELL_WIDTH: int32 = 16;
const FLAME_CELL_HEIGHT: int32 = 20;
const BILLBOARD_STRIDE: int32 = 8;
const MAX_TEXTURE_PIXELS: int32 = 64 * 20;

const FIRE_HEIGHT: float32 = 0.55;
const FIRE_INTENSITY: float32 = 1.35;
const FIRE_RADIUS: float32 = 9.0;
const LIGHT_LEVELS: float32 = 4.0;
const LOG_RING_RADIUS: float32 = 0.42;

const RANDOM_MULTIPLIER: uint64 = 6364136223846793005;
const RANDOM_INCREMENT: uint64 = 1442695040888963407;
const RANDOM_RANGE: float32 = 16777216.0;

const STONE: Rgba = { red: 0.5, green: 0.44, blue: 0.48, alpha: 1.0 };
const LOG_WOOD: Rgba = { red: 0.3, green: 0.18, blue: 0.14, alpha: 1.0 };
const GROUND: Rgba = { red: 0.15, green: 0.17, blue: 0.3, alpha: 1.0 };

const sceneVertices: Vec<float32> = [];
const grassInstances: Vec<float32> = [];
const stones: Vec<Box> = [];
const flameBuffers: Vec<uint32> = [];
const texturePixels: Vec<uint32> = new Array(MAX_TEXTURE_PIXELS);
const lightParams: Vec<float32> = new Array(20);
const cameraParams: Vec<float32> = new Array(CAMERA_BLOCK_LENGTH);

// Billboard quad corners (x across, y up), two triangles; instances supply root and size.
const CORNERS: Vec<float32> = [
	-0.5, 0.0, 0.5, 0.0, 0.5, 1.0,
	-0.5, 0.0, 0.5, 1.0, -0.5, 1.0,
];

// A night palette for the palette-LUT check (0xRRGGBB): ground and grass blues, cool stone
// greys, the warm tones of firelit stone and grass, wood browns and the flame ramp.
const CAMPFIRE_PALETTE: Vec<uint32> = [
	0x07080F, 0x0E1224, 0x18203D, 0x243259, 0x33477F, 0x4A64A8, 0x6F8AD6,
	0x4F4A66, 0x6E6784, 0x8E86A6,
	0x5E3F4F, 0x8A5A64, 0xB5766E, 0xD99A7E, 0xF2C29A,
	0x2E1A17, 0x4F2E24,
	0xC8502A, 0xF08A36, 0xFFC857, 0xFFF1B0,
];

let context: DrawContext = DrawContext.withUniformCapacity(PIXEL_ART_UNIFORM_LENGTH);
let renderer: PixelArtRenderer = createRenderer();
let pointSampler: Sampler = { filter: Filter.Nearest, wrap: Wrap.Clamp, handle: 0 };
const sceneItems: Vec<DrawItem> = [];
const FLAME_ITEM: int32 = 2;
let firstFlameMesh: int32 = 0;
let settingsWanted: PixelArtSettings = PixelArtSettings.full();
let paletteWanted: boolean = false;
let cameraSnap: boolean = true;
let panTexelsPerFrame: float32 = 0.0;

let sceneBuffer: uint32 = 0;
let sceneVertexCount: int32 = 0;
let grassBuffer: uint32 = 0;
let grassCount: int32 = 0;
let grassTexture: uint32 = 0;
let flameTexture: uint32 = 0;
let frameIndex: int32 = 0;
let randomState: uint64 = 88172645463325252;
let fireOffsetX: float32 = 0.0;
let fireOffsetY: float32 = 0.0;
let fireOffsetZ: float32 = 0.0;
let fireFlicker: float32 = 1.0;

// The spike's look: outline and fog tuned on the campfire, palette off.
function campfireLook(): PixelArtLook {
	return {
		background: { x: 0.02, y: 0.02, z: 0.06, w: 0.0 },
		outline: {
			depthThreshold: 0.006,
			normalThreshold: 0.6,
			depthShade: 0.55,
			normalShade: 1.35,
		},
		fog: {
			start: 0.5,
			end: 0.8,
			strength: 0.85,
			color: { x: 0.02, y: 0.02, z: 0.07, w: 0.0 },
		},
	};
}

// The pool is sized for exactly the renderer's blocks, so create cannot fail.
function createRenderer(): PixelArtRenderer {
	const created: Result<PixelArtRenderer, PixelArtError> = PixelArtRenderer.create(
		context,
		PixelArtSettings.full(),
		campfireLook(),
	);
	if (created.ok) { return created.value; }
	unreachable;
}

function nextRandom(): float32 {
	randomState = randomState * RANDOM_MULTIPLIER + RANDOM_INCREMENT;
	const high: uint64 = randomState >> 40;
	const sample: float32 = high as float32;
	return sample / RANDOM_RANGE;
}

function absolute(value: float32): float32 {
	return value < 0.0 ? -value : value;
}

function stone(x: float32, z: float32, width: float32, depth: float32, height: float32, yaw: float32): Box {
	return {
		base: { x: x, y: 0.0, z: z },
		size: { x: width, y: height, z: depth },
		yaw: yaw,
		tilt: 0.0,
		color: STONE,
	};
}

function layoutStones(): void {
	stones.push(stone(-2.2, 0.5, 1.1, 1.1, 4.6, 0.0));
	stones.push(stone(-1.3, 1.9, 1.2, 1.2, 1.5, 0.0));
	stones.push(stone(-2.6, -2.9, 1.0, 1.0, 3.0, 0.0));
	stones.push(stone(0.2, -3.6, 1.0, 1.0, 1.9, 0.0));
	stones.push(stone(2.0, -1.9, 1.3, 1.3, 1.7, 0.0));
	stones.push(stone(2.6, -3.1, 1.2, 1.2, 3.3, 0.0));
	stones.push(stone(2.3, 2.0, 1.6, 0.9, 0.35, 0.1));
	stones.push(stone(3.3, 2.8, 1.6, 0.9, 0.35, 0.05));
	stones.push(stone(4.3, 3.6, 1.6, 0.9, 0.35, 0.12));
	stones.push(stone(5.3, 4.4, 1.6, 0.9, 0.35, 0.02));
	stones.push(stone(-6.6, 3.6, 3.2, 2.6, 0.7, 0.0));
	stones.push(stone(-8.2, -1.8, 1.4, 1.4, 1.2, 0.0));
	stones.push(stone(-7.1, -3.1, 1.4, 1.4, 1.9, 0.0));
	stones.push(stone(-9.3, -0.6, 1.4, 1.4, 0.7, 0.0));
	stones.push(stone(-6.0, -4.3, 1.2, 1.2, 2.6, 0.0));
	stones.push(stone(4.2, -7.2, 1.3, 1.3, 2.4, 0.0));
	stones.push(stone(5.4, -6.2, 1.2, 1.2, 1.4, 0.0));
	stones.push(stone(6.2, -5.0, 1.2, 1.2, 0.8, 0.0));
	stones.push(stone(3.2, -8.4, 1.2, 1.2, 3.6, 0.0));
	stones.push(stone(7.2, 0.4, 1.3, 1.3, 0.9, 0.0));
	stones.push(stone(-3.8, 7.2, 1.4, 1.4, 1.1, 0.0));
	stones.push(stone(0.4, -10.5, 1.3, 1.3, 2.2, 0.0));
	stones.push(stone(9.0, 6.2, 1.2, 1.2, 0.6, 0.0));
	stones.push(stone(-11.0, -7.0, 1.5, 1.5, 3.0, 0.0));
	stones.push(stone(10.5, -3.5, 1.4, 1.4, 1.8, 0.0));
	stones.push(stone(-1.0, 11.0, 1.6, 1.2, 0.8, 0.0));
}

function buildScene(): void {
	layoutStones();
	pushGround(sceneVertices, GROUND_HALF_SIZE, GROUND);
	for (const block of stones) {
		pushBox(sceneVertices, block);
	}
	for (let i = 0; i < 3; i++) {
		const yaw: float32 = (i as float32) * 2.094 + 0.4;
		const logX: float32 = sinf(yaw) * LOG_RING_RADIUS;
		const logZ: float32 = cosf(yaw) * LOG_RING_RADIUS;
		const log: Box = {
			base: { x: logX, y: 0.0, z: logZ },
			size: { x: 0.16, y: 0.95, z: 0.16 },
			yaw: yaw,
			tilt: -0.85,
			color: LOG_WOOD,
		};
		pushBox(sceneVertices, log);
	}
	sceneVertexCount = (sceneVertices.length as int32) / LIT_VERTEX_STRIDE;
	sceneBuffer = makeVertexBuffer(sceneVertices);
}

function insideStone(x: float32, z: float32): boolean {
	for (const block of stones) {
		const halfX: float32 = block.size.x * 0.5 + 0.15;
		const halfZ: float32 = block.size.z * 0.5 + 0.15;
		if (absolute(x - block.base.x) < halfX && absolute(z - block.base.z) < halfZ) {
			return true;
		}
	}
	return false;
}

function buildGrass(): void {
	const steps: int32 = ((GRASS_RADIUS * 2.0) / GRASS_SPACING) as int32;
	for (let row = 0; row <= steps; row++) {
		for (let column = 0; column <= steps; column++) {
			const x: float32 = -GRASS_RADIUS + (column as float32) * GRASS_SPACING + (nextRandom() - 0.5) * GRASS_SPACING;
			const z: float32 = -GRASS_RADIUS + (row as float32) * GRASS_SPACING + (nextRandom() - 0.5) * GRASS_SPACING;
			const distanceSquared: float32 = x * x + z * z;
			if (distanceSquared > GRASS_RADIUS * GRASS_RADIUS) { continue; }
			if (distanceSquared < FIRE_CLEARING_RADIUS * FIRE_CLEARING_RADIUS) { continue; }
			if (insideStone(x, z)) { continue; }
			const variant: float32 = ((nextRandom() * 4.0) as int32) as float32;
			const size: float32 = 0.9 * (0.8 + nextRandom() * 0.35);
			const tint: float32 = nextRandom() < SPROUT_CHANCE ? SPROUT_TINT : 0.8 + nextRandom() * 0.3;
			grassInstances.push(x);
			grassInstances.push(0.0 as float32);
			grassInstances.push(z);
			grassInstances.push(variant);
			grassInstances.push(size);
			grassInstances.push(size);
			grassInstances.push(tint);
			grassInstances.push(0.0 as float32);
		}
	}
	grassCount = (grassInstances.length as int32) / BILLBOARD_STRIDE;
	grassBuffer = makeVertexBuffer(grassInstances);
}

function clearTexturePixels(): void {
	for (let i = 0; i < MAX_TEXTURE_PIXELS; i++) {
		texturePixels[i] = 0 as uint32;
	}
}

function setTexturePixel(width: int32, x: int32, y: int32, red: int32, green: int32, blue: int32): void {
	const index: int32 = y * width + x;
	if (x < 0 || y < 0 || x >= width || index >= MAX_TEXTURE_PIXELS) {
		return;
	}
	const packed: uint64 = (255 as uint64) * 16777216 + (blue as uint64) * 65536 + (green as uint64) * 256 + (red as uint64);
	texturePixels[index] = packed as uint32;
}

function buildTuftTexture(): uint32 {
	const width: int32 = TUFT_CELL * ATLAS_CELLS;
	const height: int32 = TUFT_CELL;
	clearTexturePixels();
	for (let variant = 0; variant < ATLAS_CELLS; variant++) {
		const cellLeft: int32 = variant * TUFT_CELL;
		const bladeCount: int32 = 5 + variant;
		for (let blade = 0; blade < bladeCount; blade++) {
			const rootX: float32 = 4.0 + nextRandom() * 8.0;
			const bladeHeight: int32 = 6 + ((nextRandom() * 9.0) as int32);
			const lean: float32 = (rootX - 8.0) * 0.14 + (nextRandom() - 0.5) * 0.4;
			for (let step = 0; step < bladeHeight; step++) {
				const offset: int32 = (rootX + lean * (step as float32)) as int32;
				const clamped: int32 = Math.max(0, Math.min(TUFT_CELL - 1, offset));
				const shade: int32 = 120 + (135 * step) / bladeHeight;
				setTexturePixel(width, cellLeft + clamped, height - 1 - step, shade, shade, shade);
			}
		}
	}
	return makeTextureView(makeImage(texturePixels, width, height));
}

function buildFlameTexture(): uint32 {
	const width: int32 = FLAME_CELL_WIDTH * FLAME_FRAMES;
	const height: int32 = FLAME_CELL_HEIGHT;
	clearTexturePixels();
	for (let frame = 0; frame < FLAME_FRAMES; frame++) {
		const cellLeft: int32 = frame * FLAME_CELL_WIDTH;
		const sway: float32 = (nextRandom() - 0.5) * 2.0;
		for (let y = 0; y < height; y++) {
			const rise: float32 = ((height - 1 - y) as float32) / ((height - 1) as float32);
			const halfWidth: float32 = 5.5 * (1.0 - rise) * (1.1 - 0.3 * rise) + (nextRandom() - 0.5) * 1.2;
			if (halfWidth < 0.5) { continue; }
			const center: float32 = 8.0 + sway * rise * rise * 3.0;
			for (let x = 0; x < FLAME_CELL_WIDTH; x++) {
				const spread: float32 = absolute((x as float32) + 0.5 - center) / halfWidth;
				if (spread >= 1.0) { continue; }
				if (spread < 0.45 && rise < 0.6) {
					setTexturePixel(width, cellLeft + x, y, 255, 236, 140);
				} else if (spread < 0.75) {
					setTexturePixel(width, cellLeft + x, y, 255, 150, 50);
				} else {
					setTexturePixel(width, cellLeft + x, y, 214, 70, 38);
				}
			}
		}
	}
	return makeTextureView(makeImage(texturePixels, width, height));
}

function buildFlameBuffers(): void {
	for (let frame = 0; frame < FLAME_FRAMES; frame++) {
		const instance: Vec<float32> = [
			0.0, 0.05, 0.0, frame as float32,
			0.95, 1.2, 1.0, 1.0,
		];
		flameBuffers.push(makeVertexBuffer(instance));
	}
}

function updateFlicker(): void {
	if (frameIndex % FLICKER_FRAMES != 0) { return; }
	fireOffsetX = (nextRandom() - 0.5) * 0.16;
	fireOffsetY = (nextRandom() - 0.5) * 0.12;
	fireOffsetZ = (nextRandom() - 0.5) * 0.16;
	fireFlicker = 1.0 + (nextRandom() - 0.5) * 0.14;
}

function writeLightParams(): void {
	lightParams[0] = fireOffsetX;
	lightParams[1] = FIRE_HEIGHT + fireOffsetY;
	lightParams[2] = fireOffsetZ;
	lightParams[3] = FIRE_INTENSITY * fireFlicker;
	lightParams[4] = 1.0;
	lightParams[5] = 0.45;
	lightParams[6] = 0.16;
	lightParams[7] = FIRE_RADIUS;
	lightParams[8] = 0.33;
	lightParams[9] = 0.36;
	lightParams[10] = 0.6;
	lightParams[11] = LIGHT_LEVELS;
	lightParams[12] = 0.35;
	lightParams[13] = 0.9;
	lightParams[14] = 0.25;
	lightParams[15] = 0.22;
	lightParams[16] = 0.2;
	lightParams[17] = 0.26;
	lightParams[18] = 0.5;
	lightParams[19] = 0.0;
}

function item(mesh: int32, material: int32): DrawItem {
	return { mesh: mesh, material: material, world: identity() };
}

// Materials, meshes and items: lit geometry, grass and one flame, all opaque (the billboards
// discard their transparent texels). The spike draws unculled, depth-tested with LessEqual.
function setupDraws(): void {
	pointSampler = Sampler.create(Filter.Nearest, Wrap.Clamp);
	const cornerBuffer: uint32 = makeVertexBuffer(CORNERS);
	const scene: RenderState = RenderState.defaults()
		.withCulling(Face.None)
		.withDepth(true, Compare.LessEqual);
	const litMaterial: int32 = addMaterial(
		context,
		Material.plain(Program.Lit, scene, Phase.Opaque),
	);
	const grassMaterial: int32 = addMaterial(context, {
		...Material.plain(Program.Billboard, scene, Phase.Opaque),
		texture0: grassTexture,
		sampler0: pointSampler.handle,
	});
	const flameMaterial: int32 = addMaterial(context, {
		...Material.plain(Program.Billboard, scene, Phase.Opaque),
		texture0: flameTexture,
		sampler0: pointSampler.handle,
	});
	const litMesh: int32 = addMesh(context, {
		layout: VertexLayout.Lit,
		vertexBuffer: sceneBuffer,
		instanceBuffer: 0,
		vertexCount: sceneVertexCount,
		instanceCount: 1,
	});
	const grassMesh: int32 = addMesh(context, {
		layout: VertexLayout.Billboard,
		vertexBuffer: cornerBuffer,
		instanceBuffer: grassBuffer,
		vertexCount: 6,
		instanceCount: grassCount,
	});
	firstFlameMesh = context.meshes.length as int32;
	for (const flameBuffer of flameBuffers) {
		addMesh(context, {
			layout: VertexLayout.Billboard,
			vertexBuffer: cornerBuffer,
			instanceBuffer: flameBuffer,
			vertexCount: 6,
			instanceCount: 1,
		});
	}
	sceneItems.push(item(litMesh, litMaterial));
	sceneItems.push(item(grassMesh, grassMaterial));
	sceneItems.push(item(firstFlameMesh, flameMaterial));
}

// For the checks in out/tmp: the renderer settings and whether CAMPFIRE_PALETTE is on. Call
// before voidRun.
export function configureCampfire(settings: PixelArtSettings, palette: boolean): void {
	settingsWanted = settings;
	paletteWanted = palette;
}

// For the M4 checks: whether the camera snaps to the texel grid, and how far it slides along its
// right axis each frame, in low-res texels. The default is the pixel-perfect camera; the M2/M3
// baseline captures turn the snap off, because the spike's camera did not have one
// (docs/VOID3D.md, M4 as built).
export function configureCampfireCamera(snap: boolean, panPerFrame: float32): void {
	cameraSnap = snap;
	panTexelsPerFrame = panPerFrame;
}

export function initCampfire(): void {
	gfxSetup();
	buildScene();
	buildGrass();
	buildFlameBuffers();
	grassTexture = buildTuftTexture();
	flameTexture = buildFlameTexture();
	setupDraws();
	setSettings(renderer, settingsWanted);
	if (paletteWanted) {
		const filled: Result<int32, PaletteError> = setPalette(renderer, CAMPFIRE_PALETTE);
		if (filled.ok) {
			setSettings(renderer, { ...renderer.settings, palette: true });
		}
	}
}

export function frameCampfire(): void {
	// The low-res target's size does not depend on the camera, so the view is made twice: once
	// to learn the texel grid the camera snaps to, and once with the remainder that snap left.
	const noRemainder: float32 = 0.0;
	const sized: Result<LowResView, ViewError> = renderer.viewFor(
		fbWidth(),
		fbHeight(),
		noRemainder,
		noRemainder,
	);
	if (!sized.ok) { return; }
	const grid: LowResView = sized.value;

	const shortSide: float32 = Math.min(grid.width, grid.height) as float32;
	const worldPerTexel: float32 = UNITS_ON_SHORT_SIDE / shortSide;
	const centred: OrthoCamera = {
		target: vec3(0.0, 0.0, 0.0),
		yaw: CAMERA_YAW,
		pitch: CAMERA_PITCH,
		worldPerTexel: worldPerTexel,
		nearPlane: -50.0,
		farPlane: 50.0,
		snap: cameraSnap,
	};
	const slide: float32 = panTexelsPerFrame * (frameIndex as float32) * worldPerTexel;
	const target: Vec3 = centred.basisOf().right.scaled(slide);
	const camera: OrthoCamera = { ...centred, target: target };
	const resolved: Result<CameraView, CameraError> = camera.resolve(grid.width, grid.height);
	if (!resolved.ok) { return; }
	const cameraView: CameraView = resolved.value;

	const viewed: Result<LowResView, ViewError> = renderer.viewFor(
		fbWidth(),
		fbHeight(),
		cameraView.remainderX,
		cameraView.remainderY,
	);
	if (!viewed.ok) { return; }

	cameraView.writeCameraBlock(cameraParams);
	updateFlicker();
	writeLightParams();

	const flameFrame: int32 = (frameIndex / FLICKER_FRAMES) % FLAME_FRAMES;
	sceneItems[FLAME_ITEM].mesh = firstFlameMesh + flameFrame;
	renderFrame(renderer, context, sceneItems, cameraParams, lightParams, viewed.value);
	frameIndex = frameIndex + 1;
}
