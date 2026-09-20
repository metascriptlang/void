// The pixellight spike: the t3ssel8r nighttime-lighting demo (youtu.be/VEP4INri_1U) — a night
// camp scene. One quantized fire light wiggled at a low framerate, an additive pass that
// ignores the color ramp, on the PixelArtRenderer preset. Side quest of .wt/pixellight.md.

import { gfxSetup, fbWidth, fbHeight } from "../sokol/gpu";
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
import {
	DrawContext,
	DrawItem,
	GpuMesh,
	MeshUploadError,
	addMesh,
	addMeshData,
	addMaterial,
} from "../void3d/draw";
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
import { identity, vec3 } from "../math/math3d";
import { MeshData, MeshError, Rgba, Box, addBox, addPlane } from "../void3d/meshData";
import {
	OrthoCamera,
	CameraView,
	CameraError,
	CAMERA_BLOCK_LENGTH,
} from "../void3d/camera";

const UNITS_ON_SHORT_SIDE: float32 = 22.0;
const CAMERA_YAW: float32 = 0.55;
const CAMERA_PITCH: float32 = 0.5;
const CAMERA_NEAR: float32 = -60.0;
const CAMERA_FAR: float32 = 60.0;

const GROUND_HALF_SIZE: float32 = 34.0;

const FLICKER_FRAMES: int32 = 4;
const FLAME_FRAMES: int32 = 4;
const ATLAS_CELLS: int32 = 4;

const BACKDROP_CELL: int32 = 128;
const BACKDROP_H: int32 = 72;
const BACKDROP_ATLAS_W: int32 = BACKDROP_CELL * 4;
const TUFT_CELL: int32 = 16;
const FLAME_CELL_W: int32 = 16;
const FLAME_CELL_H: int32 = 20;
const MAX_TEXTURE_PIXELS: int32 = BACKDROP_ATLAS_W * BACKDROP_H;

const FIRE_X: float32 = 0.0;
const FIRE_Y: float32 = 0.55;
const FIRE_Z: float32 = -3.0;
const FIRE_INTENSITY: float32 = 1.35;
const FIRE_RADIUS: float32 = 8.5;
const LIGHT_LEVELS: float32 = 4.0;

const RING_STONES: int32 = 8;
const RING_RADIUS: float32 = 0.62;
const FIELD_STONES: int32 = 10;
const GRASS_RADIUS: float32 = 13.0;
const GRASS_SPACING: float32 = 0.42;
const FOREGROUND_STONES: int32 = 3;
const BILLBOARD_STRIDE: int32 = 8;

const RANDOM_MULTIPLIER: uint64 = 6364136223846793005;
const RANDOM_INCREMENT: uint64 = 1442695040888963407;
const RANDOM_RANGE: float32 = 16777216.0;

const GROUND: Rgba = { red: 0.075, green: 0.1, blue: 0.145, alpha: 1.0 };
const STONE: Rgba = { red: 0.32, green: 0.3, blue: 0.36, alpha: 1.0 };
const WOOD: Rgba = { red: 0.21, green: 0.13, blue: 0.1, alpha: 1.0 };

// A night palette (0xRRGGBB): deep blues of sky and shadow, cool stone, grass greens, wood
// browns, then the fire ramp pale gold to deep red.
const NIGHT_PALETTE: Vec<uint32> = [
	0x05070F, 0x0B101F, 0x14203D, 0x1E3055, 0x2C4473, 0x41598F, 0x6F8AD6, 0xAAB4FF,
	0x1A2418, 0x27381F, 0x39522B, 0x4F6B3C, 0x68874E,
	0x2A2634, 0x3E3A4A, 0x555060, 0x6E6784, 0x8E86A6,
	0x2E1A17, 0x4F2E24, 0xC8502A, 0xF08A36, 0xFFC857, 0xFFF1B0,
];

const CORNERS: Vec<float32> = [
	-0.5, 0.0, 0.5, 0.0, 0.5, 1.0,
	-0.5, 0.0, 0.5, 1.0, -0.5, 1.0,
];

// The night sky: deep blue falling to near-black space, single-pixel stars in three
// brightnesses, and a pale moon disc with craters high on the right.
const BACKDROP_INSTANCE: Vec<float32> = [2.0, -6.0, -46.0, 0.0, 52.0, 30.0, 1.0, 1.0];

function pushInstance(ref target: Vec<float32>, x: float32, y: float32, z: float32, variant: float32, sizeX: float32, sizeY: float32, tint: float32): void {
	target.push(x);
	target.push(y);
	target.push(z);
	target.push(variant);
	target.push(sizeX);
	target.push(sizeY);
	target.push(tint);
	target.push(1.0);
}

const FLAME_ROOT_0: Vec<float32> = [FIRE_X - 0.55, FIRE_Y - 0.5, FIRE_Z, 0.0, 1.1, 1.45, 1.0, 1.0];
const FLAME_ROOT_1: Vec<float32> = [FIRE_X - 0.55, FIRE_Y - 0.5, FIRE_Z, 1.0, 1.1, 1.45, 1.0, 1.0];
const FLAME_ROOT_2: Vec<float32> = [FIRE_X - 0.55, FIRE_Y - 0.5, FIRE_Z, 2.0, 1.1, 1.45, 1.0, 1.0];
const FLAME_ROOT_3: Vec<float32> = [FIRE_X - 0.55, FIRE_Y - 0.5, FIRE_Z, 3.0, 1.1, 1.45, 1.0, 1.0];

let sceneMesh: MeshData = MeshData.empty();
const texturePixels: Vec<uint32> = new Array(MAX_TEXTURE_PIXELS);
const lightParams: Vec<float32> = new Array(20);
const cameraParams: Vec<float32> = new Array(CAMERA_BLOCK_LENGTH);
const grassInstances: Vec<float32> = [];

let context: DrawContext = DrawContext.withUniformCapacity(PIXEL_ART_UNIFORM_LENGTH);
let renderer: PixelArtRenderer = createRenderer();
let pointSampler: Sampler = { filter: Filter.Nearest, wrap: Wrap.Clamp, handle: 0 };
const sceneItems: Vec<DrawItem> = [];
const FLAME_ITEM: int32 = 2;
let firstFlameMesh: int32 = 0;
let frameIndex: int32 = 0;
let randomState: uint64 = 88172645463325252;
let fireOffsetX: float32 = 0.0;
let fireOffsetY: float32 = 0.0;
let fireOffsetZ: float32 = 0.0;
let fireFlicker: float32 = 1.0;

function nightLook(): PixelArtLook {
	return {
		background: { x: 0.02, y: 0.027, z: 0.058, w: 0.0 },
		outline: {
			depthThreshold: 0.006,
			normalThreshold: 0.6,
			depthShade: 0.55,
			normalShade: 1.35,
		},
		fog: { start: 0.5, end: 0.85, strength: 0.85, color: { x: 0.02, y: 0.027, z: 0.058, w: 0.0 } },
	};
}

function createRenderer(): PixelArtRenderer {
	const created: Result<PixelArtRenderer, PixelArtError> = PixelArtRenderer.create(
		context,
		PixelArtSettings.full(),
		nightLook(),
	);
	if (created.ok) { return created.value; }
	unreachable;
}

function nextRandom(): float32 {
	randomState = randomState * RANDOM_MULTIPLIER + RANDOM_INCREMENT;
	const high: uint64 = randomState >> 40;
	return (high as float32) / RANDOM_RANGE;
}

function absolute(value: float32): float32 {
	return value < 0.0 ? -value : value;
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

function buildBackdropTexture(): uint32 {
	clearTexturePixels();
	for (let y = 0; y < BACKDROP_H; y++) {
		const rise: float32 = (y as float32) / ((BACKDROP_H - 1) as float32);
		const red: int32 = (5.0 + 20.0 * rise) as int32;
		const green: int32 = (7.0 + 24.0 * rise) as int32;
		const blue: int32 = (15.0 + 40.0 * rise) as int32;
		for (let cell = 0; cell < ATLAS_CELLS; cell++) {
			for (let x = 0; x < BACKDROP_CELL; x++) {
				setTexturePixel(BACKDROP_ATLAS_W, cell * BACKDROP_CELL + x, y, red, green, blue);
			}
		}
	}
	const placedX: Vec<int32> = [];
	const placedY: Vec<int32> = [];
	for (let star = 0; star < 150; star++) {
		const x: int32 = (nextRandom() * (BACKDROP_CELL as float32)) as int32;
		const y: int32 = (10.0 + nextRandom() * 60.0) as int32;
		let crowded: boolean = false;
		for (let n = 0; n < (placedX.length as int32); n++) {
			if (Math.abs(x - placedX[n]) < 2 && Math.abs(y - placedY[n]) < 2) {
				crowded = true;
				break;
			}
		}
		if (crowded) { continue; }
		placedX.push(x);
		placedY.push(y);
		const tier: int32 = (nextRandom() * 3.0) as int32;
		for (let cell = 0; cell < ATLAS_CELLS; cell++) {
			if (tier == 0) { setTexturePixel(BACKDROP_ATLAS_W, cell * BACKDROP_CELL + x, y, 255, 255, 255); }
			else if (tier == 1) { setTexturePixel(BACKDROP_ATLAS_W, cell * BACKDROP_CELL + x, y, 170, 180, 255); }
			else { setTexturePixel(BACKDROP_ATLAS_W, cell * BACKDROP_CELL + x, y, 140, 152, 210); }
		}
	}
	for (let cell = 0; cell < ATLAS_CELLS; cell++) {
		const moonX: int32 = cell * BACKDROP_CELL + 92;
		for (let y = 40; y < 60; y++) {
			for (let x = 0; x < 20; x++) {
				const dx: int32 = x - 10;
				const dy: int32 = y - 50;
				if (dx * dx + dy * dy < 81) {
					const crater: int32 = (dx + 3) * (dx + 3) + (dy - 2) * (dy - 2);
					if (crater < 5 || (dx - 4) * (dx - 4) + (dy + 3) * (dy + 3) < 3) {
						setTexturePixel(BACKDROP_ATLAS_W, moonX + x, y, 170, 180, 200);
					} else {
						setTexturePixel(BACKDROP_ATLAS_W, moonX + x, y, 214, 220, 234);
					}
				}
			}
		}
	}
	return makeTextureView(makeImage(texturePixels, BACKDROP_ATLAS_W, BACKDROP_H));
}

// Four grass tuft variants: grayscale blade masks the billboard shader tints with the light
// block's grassColor and lights with the fire, so the field flickers with the flames.
function buildTuftTexture(): uint32 {
	clearTexturePixels();
	const width: int32 = TUFT_CELL * ATLAS_CELLS;
	for (let variant = 0; variant < ATLAS_CELLS; variant++) {
		const cellLeft: int32 = variant * TUFT_CELL;
		const bladeCount: int32 = 5 + variant;
		for (let blade = 0; blade < bladeCount; blade++) {
			const rootX: float32 = 4.0 + nextRandom() * 8.0;
			const bladeHeight: int32 = 6 + ((nextRandom() * 9.0) as int32);
			const lean: float32 = (rootX - 8.0) * 0.14 + (nextRandom() - 0.5) * 0.4;
			for (let step = 0; step < bladeHeight; step++) {
				let clamped: int32 = (rootX + lean * (step as float32)) as int32;
				if (clamped < 0) { clamped = 0; }
				if (clamped > TUFT_CELL - 1) { clamped = TUFT_CELL - 1; }
				const shade: int32 = 120 + (135 * step) / bladeHeight;
				setTexturePixel(width, cellLeft + clamped, TUFT_CELL - 1 - step, shade, shade, shade);
			}
		}
	}
	return makeTextureView(makeImage(texturePixels, width, TUFT_CELL));
}

// The flame: a tapering S-curved body, pale gold core through orange to deep red edges, one
// cell per animation frame with its own sway so the fire wiggles at the demo's low framerate.
function buildFlameTexture(): uint32 {
	clearTexturePixels();
	const width: int32 = FLAME_CELL_W * FLAME_FRAMES;
	for (let frame = 0; frame < FLAME_FRAMES; frame++) {
		const cellLeft: int32 = frame * FLAME_CELL_W;
		const sway: float32 = (nextRandom() - 0.5) * 2.0;
		for (let y = 0; y < FLAME_CELL_H; y++) {
			const rise: float32 = ((FLAME_CELL_H - 1 - y) as float32) / ((FLAME_CELL_H - 1) as float32);
			const halfWidth: float32 = 5.5 * (1.0 - rise) * (1.1 - 0.3 * rise) + (nextRandom() - 0.5) * 1.2;
			if (halfWidth < 0.5) { continue; }
			const center: float32 = 8.0 + sway * rise * rise * 3.0;
			for (let x = 0; x < FLAME_CELL_W; x++) {
				const spread: float32 = absolute((x as float32) + 0.5 - center) / halfWidth;
				if (spread >= 1.0) { continue; }
				if (spread < 0.45 && rise < 0.6) {
					setTexturePixel(width, cellLeft + x, y, 255, 241, 176);
				} else if (spread < 0.75) {
					setTexturePixel(width, cellLeft + x, y, 240, 138, 54);
				} else {
					setTexturePixel(width, cellLeft + x, y, 200, 80, 42);
				}
			}
		}
	}
	return makeTextureView(makeImage(texturePixels, width, FLAME_CELL_H));
}

const placedBoxes: Vec<Box> = [];

function addBlock(b: Box): Result<int32, MeshError> {
	placedBoxes.push(b);
	return addBox(sceneMesh, b);
}

function box(x: float32, z: float32, width: float32, depth: float32, height: float32, yaw: float32, tilt: float32, color: Rgba): Box {
	return {
		base: { x: x, y: 0.0, z: z },
		size: { x: width, y: height, z: depth },
		yaw: yaw,
		tilt: tilt,
		color: color,
	};
}

// The stone ring and three leaning logs around the fire, a loose field of stones, then big
// dark framing stones close to the camera.
function buildScene(): void {
	const ground: Result<int32, MeshError> = addPlane(sceneMesh, GROUND_HALF_SIZE, GROUND);
	if (!ground.ok) { return; }
	for (let i = 0; i < RING_STONES; i++) {
		const angle: float32 = (i as float32) * 0.785 + nextRandom() * 0.2;
		const x: float32 = FIRE_X + Math.cos(angle) * (RING_RADIUS + nextRandom() * 0.1);
		const z: float32 = FIRE_Z + Math.sin(angle) * (RING_RADIUS + nextRandom() * 0.1);
		const size: float32 = 0.22 + nextRandom() * 0.12;
		const added: Result<int32, MeshError> = addBlock(
			box(x, z, size, size, size * (0.7 + nextRandom() * 0.5), nextRandom() * 3.14, (nextRandom() - 0.5) * 0.2, STONE),
		);
		if (!added.ok) { return; }
	}
	for (let i = 0; i < 3; i++) {
		const yaw: float32 = (i as float32) * 2.094 + 0.4;
		const x: float32 = FIRE_X + Math.sin(yaw) * 0.42;
		const z: float32 = FIRE_Z + Math.cos(yaw) * 0.42;
		const added: Result<int32, MeshError> = addBlock(
			box(x, z, 0.16, 0.16, 0.95, yaw, -0.85, WOOD),
		);
		if (!added.ok) { return; }
	}
	for (let i = 0; i < FIELD_STONES; i++) {
		const angle: float32 = nextRandom() * 6.28;
		const distance: float32 = 3.0 + nextRandom() * 9.0;
		const x: float32 = FIRE_X + Math.cos(angle) * distance;
		const z: float32 = FIRE_Z + Math.sin(angle) * distance * 0.7 - 2.0;
		const size: float32 = 0.5 + nextRandom() * 1.0;
		const added: Result<int32, MeshError> = addBlock(
			box(x, z, size, size, size * (0.6 + nextRandom() * 0.9), nextRandom() * 3.14, (nextRandom() - 0.5) * 0.3, STONE),
		);
		if (!added.ok) { return; }
	}
	const addedPillarA: Result<int32, MeshError> = addBlock(box(-3.2, -8.5, 0.9, 0.9, 4.5, 0.1, 0.03, STONE));
	if (!addedPillarA.ok) { return; }
	const addedPillarB: Result<int32, MeshError> = addBlock(box(2.8, -8.0, 0.9, 0.9, 3.8, -0.08, 0.0, STONE));
	if (!addedPillarB.ok) { return; }
	const addedCuboidA: Result<int32, MeshError> = addBlock(box(-5.5, -5.5, 1.3, 1.3, 1.6, 0.2, 0.0, STONE));
	if (!addedCuboidA.ok) { return; }
	const addedCuboidB: Result<int32, MeshError> = addBlock(box(4.6, -5.0, 1.1, 1.1, 1.3, -0.15, 0.05, STONE));
	if (!addedCuboidB.ok) { return; }
	const addedBenchA: Result<int32, MeshError> = addBlock(box(3.4, 0.5, 2.0, 0.9, 0.6, 0.05, 0.0, STONE));
	if (!addedBenchA.ok) { return; }
	const addedBenchB: Result<int32, MeshError> = addBlock(box(4.9, 0.2, 1.6, 0.8, 0.5, -0.1, 0.0, STONE));
	if (!addedBenchB.ok) { return; }
	const addedPlatform: Result<int32, MeshError> = addBlock(box(-4.6, 1.0, 2.8, 1.2, 0.7, 0.0, 0.0, STONE));
	if (!addedPlatform.ok) { return; }
	for (let i = 0; i < FOREGROUND_STONES; i++) {
		const x: float32 = -4.0 + (i as float32) * 4.0 + nextRandom() * 1.6;
		const z: float32 = 3.5 + nextRandom() * 2.0;
		const size: float32 = 1.3 + nextRandom() * 1.2;
		const added: Result<int32, MeshError> = addBlock(
			box(x, z, size, size, size * (0.7 + nextRandom() * 0.8), nextRandom() * 3.14, (nextRandom() - 0.5) * 0.35, STONE),
		);
		if (!added.ok) { return; }
	}
}

function insideStone(x: float32, z: float32): boolean {
	for (let i = 0; i < (placedBoxes.length as int32); i++) {
		const block: Box = placedBoxes[i];
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
			const distanceSquared: float32 = x * x + (z + 3.0) * (z + 3.0);
			if (distanceSquared > GRASS_RADIUS * GRASS_RADIUS) { continue; }
			if (distanceSquared < 0.8 * 0.8) { continue; }
			if (insideStone(x, z)) { continue; }
			const variant: float32 = ((nextRandom() * 4.0) as int32) as float32;
			const size: float32 = 0.9 * (0.8 + nextRandom() * 0.35);
			const tint: float32 = nextRandom() < 0.05 ? 2.3 : 0.8 + nextRandom() * 0.3;
			pushInstance(grassInstances, x, 0.0, z, variant, size, size, tint);
		}
	}
}

function setupDraws(): void {
	pointSampler = Sampler.create(Filter.Nearest, Wrap.Clamp);
	const cornerBuffer: uint32 = makeVertexBuffer(CORNERS);
	const state: RenderState = RenderState.defaults()
		.withCulling(Face.None)
		.withDepth(true, Compare.LessEqual);
	const litMaterial: int32 = addMaterial(
		context,
		Material.plain(Program.Lit, state, Phase.Opaque),
	);
	const backdropMaterial: int32 = addMaterial(context, {
		...Material.plain(Program.Billboard, state, Phase.Opaque),
		texture0: buildBackdropTexture(),
		sampler0: pointSampler.handle,
	});
	const grassMaterial: int32 = addMaterial(context, {
		...Material.plain(Program.Billboard, state, Phase.Opaque),
		texture0: buildTuftTexture(),
		sampler0: pointSampler.handle,
	});
	const flameMaterial: int32 = addMaterial(context, {
		...Material.plain(Program.Billboard, state, Phase.Opaque),
		texture0: buildFlameTexture(),
		sampler0: pointSampler.handle,
	});

	const uploaded: Result<int32, MeshUploadError> = addMeshData(context, sceneMesh);
	if (!uploaded.ok) { return; }
	const litMesh: int32 = uploaded.value;
	const backdropMesh: int32 = addMesh(
		context,
		GpuMesh.external(
			VertexLayout.Billboard,
			cornerBuffer,
			makeVertexBuffer(BACKDROP_INSTANCE),
			6,
			1,
		),
	);
	const grassCount: int32 = (grassInstances.length as int32) / BILLBOARD_STRIDE;
	const grassMesh: int32 = addMesh(
		context,
		GpuMesh.external(
			VertexLayout.Billboard,
			cornerBuffer,
			makeVertexBuffer(grassInstances),
			6,
			grassCount,
		),
	);
	firstFlameMesh = context.meshes.length as int32;
	addMesh(context, GpuMesh.external(VertexLayout.Billboard, cornerBuffer, makeVertexBuffer(FLAME_ROOT_0), 6, 1));
	addMesh(context, GpuMesh.external(VertexLayout.Billboard, cornerBuffer, makeVertexBuffer(FLAME_ROOT_1), 6, 1));
	addMesh(context, GpuMesh.external(VertexLayout.Billboard, cornerBuffer, makeVertexBuffer(FLAME_ROOT_2), 6, 1));
	addMesh(context, GpuMesh.external(VertexLayout.Billboard, cornerBuffer, makeVertexBuffer(FLAME_ROOT_3), 6, 1));
	sceneItems.push({ mesh: litMesh, material: litMaterial, world: identity() });
	sceneItems.push({ mesh: backdropMesh, material: backdropMaterial, world: identity() });
	sceneItems.push({ mesh: firstFlameMesh, material: flameMaterial, world: identity() });
	sceneItems.push({ mesh: grassMesh, material: grassMaterial, world: identity() });
}

function updateFlicker(): void {
	if (frameIndex % FLICKER_FRAMES != 0) { return; }
	fireOffsetX = (nextRandom() - 0.5) * 0.16;
	fireOffsetY = (nextRandom() - 0.5) * 0.12;
	fireOffsetZ = (nextRandom() - 0.5) * 0.16;
	fireFlicker = 1.0 + (nextRandom() - 0.5) * 0.14;
}

function writeLightParams(): void {
	lightParams[0] = FIRE_X + fireOffsetX;
	lightParams[1] = FIRE_Y + fireOffsetY;
	lightParams[2] = FIRE_Z + fireOffsetZ;
	lightParams[3] = FIRE_INTENSITY * fireFlicker;
	lightParams[4] = 1.0;
	lightParams[5] = 0.45;
	lightParams[6] = 0.16;
	lightParams[7] = FIRE_RADIUS;
	lightParams[8] = 0.05;
	lightParams[9] = 0.058;
	lightParams[10] = 0.095;
	lightParams[11] = LIGHT_LEVELS;
	lightParams[12] = 0.5;
	lightParams[13] = 0.75;
	lightParams[14] = 0.35;
	lightParams[15] = 0.18;
	lightParams[16] = 0.14;
	lightParams[17] = 0.22;
	lightParams[18] = 0.14;
	lightParams[19] = 0.0;
}

export function initPixellight(): void {
	gfxSetup();
	buildScene();
	buildGrass();
	setupDraws();
	const filled: Result<int32, PaletteError> = setPalette(renderer, NIGHT_PALETTE);
	if (filled.ok) {
		setSettings(renderer, { ...renderer.settings, palette: true });
	}
}

export function framePixellight(): void {
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
	const camera: OrthoCamera = {
		target: vec3(0.0, 0.0, -2.0),
		yaw: CAMERA_YAW,
		pitch: CAMERA_PITCH,
		worldPerTexel: worldPerTexel,
		nearPlane: CAMERA_NEAR,
		farPlane: CAMERA_FAR,
		snap: true,
	};
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
