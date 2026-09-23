// The campfire, built as an Object3D tree and drawn from the draw list that tree produces.
// Nothing here positions geometry by hand any more: every piece is modelled in its own local
// space and placed by its node's transform, which is what finally exercises `DrawItem.world`.
// The hand-built scene this file used to be — one merged MeshData in world space and a draw
// list assembled by pushing items — is gone with M6.

import { gfxSetup, fbWidth, fbHeight } from "../sokol/gpu";
import { sinf, cosf } from "../math/mat4";
import {
	LIGHT_UNIFORM_LENGTH,
	TOON_UNIFORM_SLOT,
	TOON_UNIFORM_LENGTH,
	SPRITE_UNIFORM_SLOT,
	SPRITE_UNIFORM_LENGTH,
	Program,
	VertexLayout,
	Filter,
	Wrap,
	makeVertexBuffer,
	makeImage,
	makeTextureView,
	destroyBuffer,
	destroyImage,
	destroyView,
	destroySampler,
	originTopLeft,
} from "../void3d/gpu3d";
import { RenderState, Face, Compare } from "../void3d/pass";
import { Material, Phase, UniformBlock, NO_UNIFORMS } from "../void3d/material";
import { Sampler } from "../void3d/target";
import {
	EXTERNAL_GENERATION,
	DrawContext,
	DrawItem,
	GpuMesh,
	MeshUploadError,
	StreamError,
	addMesh,
	addMeshData,
	addMaterial,
	addStreamMesh,
	writeStream,
	rebuildMeshes,
	reserveUniforms,
	writeUniforms,
} from "../void3d/draw";
import { LowResView, ViewError } from "../void3d/blit";
import { Bounds } from "../void3d/bounds";
import { PaletteError } from "../void3d/palette";
import {
	PixelArtRenderer,
	PixelArtSettings,
	PixelArtError,
	PixelArtLook,
	PIXEL_ART_UNIFORM_LENGTH,
	setLook,
	setPalette,
	setSettings,
	renderFrame,
} from "../void3d/pixelArtRenderer";
import { Vec3, vec3, Mat4, eulerQuat, quatBetween, identity } from "../math/math3d";
import { MeshData, MeshError, Rgba, Box, addBox, addPlane } from "../void3d/meshData";
import {
	Scene,
	NodeId,
	Transform3D,
	SceneError,
	LightError,
	LightKind,
	NodeKind,
	identityTransform,
	transformAt,
	addGroup,
	addMeshNode,
	addLightNode,
	setLocal,
	setName,
	setLightPower,
	setAmbient,
	setPickable,
	collectLights,
	refresh,
	syncWorld,
} from "../void3d/scene";
import {
	AnimationClock,
	AnimationError,
	Interpolation,
	ObjectAnimation,
	MeshFrameAnimation,
	update,
	addTrack,
	bindTracks,
	syncPose,
	bindMeshFrames,
	syncMeshFrame,
	addBakedFrames,
} from "../void3d/animation";
import {
	OrthoCamera,
	CameraView,
	CameraError,
	CAMERA_BLOCK_LENGTH,
} from "../void3d/camera";
import { Ray } from "../void3d/ray";
import { PickHit, PickError, pickNearest } from "../void3d/pick";
import {
	EmitterState,
	ParticleEmitter,
	ParticleError,
	ShapeKind,
	ValueKind,
	Converge,
	PARTICLE_INSTANCE_STRIDE,
	constant,
	updateEmitter,
	writeInstances,
} from "../void3d/particles";

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
const SPIN_KEYS: int32 = 32;
const BAKED_STONE: int32 = 1;
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

// Each piece is its own geometry in its own local space, with `placements[i]` saying where
// that piece goes. The tree is what turns the two into draws.
const pieces: Vec<MeshData> = [];
const placements: Vec<Transform3D> = [];
const grassInstances: Vec<float32> = [];
const stones: Vec<Box> = [];
const flameBuffers: Vec<uint32> = [];
const texturePixels: Vec<uint32> = new Array(MAX_TEXTURE_PIXELS);
const lightParams: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
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

const WINTER_PALETTE: Vec<uint32> = [
	0x0B0E1A, 0x151C33, 0x22304F, 0x34486E, 0x4C6690, 0x6D88B0, 0x97AFCF, 0xC4D4EA,
	0xEEF4FC, 0x3A3F4F, 0x5C6272, 0x868C9C, 0x6E4A4A, 0xB0705A, 0xE0A070, 0xFFE0A8,
];

const PARTICLE_STEP: float64 = 1.0 / 30.0;
const PARTICLE_WARMUP_STEPS: int32 = 240;
const SNOW_SEED: uint32 = 12345;
const EMBER_SEED: uint32 = 777;
const SNOW_HEIGHT: float32 = 6.0;
const EMBER_HEIGHT: float32 = 0.35;
const LOOK_WINTER_AT: int32 = 5;
const LOOK_GREY_AT: int32 = 10;
const LOOK_RESTORED_AT: int32 = 15;

// The pool holds the renderer's blocks plus this scene's material blocks: one toon ramp for
// the lit material, one sprite block shared by grass and flame.
const MATERIAL_UNIFORM_LENGTH: int32 = TOON_UNIFORM_LENGTH + SPRITE_UNIFORM_LENGTH;
let context: DrawContext = DrawContext.withUniformCapacity(
	PIXEL_ART_UNIFORM_LENGTH + MATERIAL_UNIFORM_LENGTH,
);
let renderer: PixelArtRenderer = createRenderer();
let pointSampler: Sampler = { filter: Filter.Nearest, wrap: Wrap.Clamp, handle: 0 };
// The draw list the tree writes into, owned here and reused every frame.
const sceneItems: Vec<DrawItem> = [];
let tree: Scene = Scene.create();
let flameNode: NodeId = { index: -1, generation: 0 };
// The logs hang under their own group rather than off the root, so the tree has a real nested
// transform to propagate through. The group sits at the identity unless a check turns it, and
// `local * identity` is exact, so the six standing configurations see the same pixels.
let logGroup: NodeId = { index: -1, generation: 0 };
let firstLogNode: NodeId = { index: -1, generation: 0 };
let bakedStoneNode: NodeId = { index: -1, generation: 0 };
let plainStoneNode: NodeId = { index: -1, generation: 0 };
let fireLight: NodeId = { index: -1, generation: 0 };
let firstLogPiece: int32 = 0;
let logSpinPerFrame: float32 = 0.0;
let flameFrames: MeshFrameAnimation = {
	clock: {
		frameCount: 0,
		sampling: 0.0,
		speed: 0.0,
		frame: 0.0,
		loop: false,
		pause: true,
		interpolation: Interpolation.Step,
	},
	name: "",
	target: { index: -1, generation: 0 },
	meshes: [],
	bound: false,
	shown: -1,
};
let logSpin: ObjectAnimation = ObjectAnimation.forClock(flameFrames.clock);
let stoneFrames: MeshFrameAnimation = flameFrames;
let firstStoneFrame: int32 = 0;
const NEVER_REBUILD: int32 = -1;
let firstFlameMesh: int32 = 0;
let settingsWanted: PixelArtSettings = PixelArtSettings.full();
let paletteWanted: boolean = false;
let cameraSnap: boolean = true;
let panTexelsPerFrame: float32 = 0.0;
let rebuildAtFrame: int32 = NEVER_REBUILD;
let particlesWanted: boolean = false;
let lookScheduleWanted: boolean = false;
let particleMaterial: int32 = 0;
let snow: ParticleEmitter = emitterOf(snowState(), SNOW_SEED);
let embers: ParticleEmitter = emitterOf(emberState(), EMBER_SEED);
let snowNode: NodeId = { index: -1, generation: 0 };
let emberNode: NodeId = { index: -1, generation: 0 };
let snowMesh: int32 = 0;
let emberMesh: int32 = 0;
const snowInstances: Vec<float32> = new Array(snowState().maxParts * PARTICLE_INSTANCE_STRIDE);
const emberInstances: Vec<float32> = new Array(emberState().maxParts * PARTICLE_INSTANCE_STRIDE);

let grassBuffer: uint32 = 0;
let grassCount: int32 = 0;
let grassTexture: uint32 = 0;
let flameTexture: uint32 = 0;
let grassImage: uint32 = 0;
let flameImage: uint32 = 0;
// The CPU copies a lost context rebuilds the billboards from: the pixels each texture was
// uploaded from (the shared scratch is overwritten by the second build) and the mesh and
// material slots the re-made handles go back into.
let tuftPixels: Vec<uint32> = [];
let flamePixels: Vec<uint32> = [];
let billboardCornerBuffer: uint32 = 0;
let grassMesh: int32 = 0;
let grassMaterial: int32 = 0;
let flameMaterial: int32 = 0;
let frameIndex: int32 = 0;
let randomState: uint64 = 88172645463325252;
let fireOffsetX: float32 = 0.0;
let fireOffsetY: float32 = 0.0;
let fireOffsetZ: float32 = 0.0;
let fireFlicker: float32 = 1.0;
let shownView: CameraView = {
	eye: vec3(0.0, 0.0, 0.0),
	basis: {
		right: vec3(0.0, 0.0, 0.0),
		up: vec3(0.0, 0.0, 0.0),
		forward: vec3(0.0, 0.0, 0.0),
	},
	viewProj: identity(),
	remainderX: 0.0,
	remainderY: 0.0,
	texelWidth: 0,
	texelHeight: 0,
	worldPerTexel: 0.0,
};
let shownBlit: LowResView = { width: 0, height: 0, scale: 0, offsetX: 0.0, offsetY: 0.0 };
let shownHeight: int32 = 0;

function snowState(): EmitterState {
	return {
		...EmitterState.defaults(),
		emitRate: constant(45.0),
		maxParts: 400,
		shape: { kind: ShapeKind.Disc, radius: constant(13.0) },
		life: constant(7.0),
		size: constant(0.07),
		speed: constant(0.0),
		gravity: { kind: ValueKind.Random, start: 0.15, length: 0.15, converge: Converge.No },
		force: { x: constant(0.08), y: constant(0.0), z: constant(0.0) },
		colors: [{ time: 0.0, color: 0xE6ECFF }],
		alpha: { kind: ValueKind.Linear, start: 1.4, length: -1.0 },
	};
}

function emberState(): EmitterState {
	return {
		...EmitterState.defaults(),
		emitRate: constant(10.0),
		maxParts: 48,
		shape: { kind: ShapeKind.Cone, radius: constant(0.12), angle: constant(0.5) },
		life: { kind: ValueKind.Random, start: 1.0, length: 1.0, converge: Converge.No },
		size: constant(0.08),
		speed: { kind: ValueKind.Random, start: 0.5, length: 0.5, converge: Converge.No },
		gravity: constant(-0.4),
		force: { x: constant(0.1), y: constant(0.0), z: constant(0.0) },
		colors: [
			{ time: 0.0, color: 0xFFE070 },
			{ time: 0.4, color: 0xFF7A20 },
			{ time: 1.0, color: 0x9A2A10 },
		],
		alpha: { kind: ValueKind.Linear, start: 1.5, length: -1.2 },
	};
}

function emitterOf(state: EmitterState, seed: uint32): ParticleEmitter {
	const made: Result<ParticleEmitter, ParticleError> = ParticleEmitter.create(state, seed);
	if (made.ok) { return made.value; }
	unreachable;
}

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
		saturation: 0.0,
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

// A box's placement as a node transform. `toWorld` tilts about X first and then yaws about Y,
// so the node's rotation is `eulerQuat(tilt, yaw, 0)` — measured against the builder's own
// matrix in out/tmp/quatProbe, where the three other orderings are wrong by 0.78 to 1.5 and
// this one agrees to 1.19e-7, one float32 ulp at this magnitude.
function placementOf(block: Box): Transform3D {
	return {
		...identityTransform(),
		position: block.base,
		rotation: eulerQuat(block.tilt, block.yaw, 0.0),
	};
}

// The same box modelled at the origin, unturned: everything that used to be baked into the
// vertices now lives in the node instead. Size and colour stay, because they are the shape
// rather than the placement.
function unplaced(block: Box): Box {
	const origin: Vec3 = vec3(0.0, 0.0, 0.0);
	const flat: float32 = 0.0;
	return { ...block, base: origin, yaw: flat, tilt: flat };
}

function addPiece(geometry: MeshData, where: Transform3D): void {
	pieces.push(geometry);
	placements.push(where);
}

// The ground, the stones and three leaning logs, each its own piece of local-space geometry
// with its own place in the tree. Nothing here touches the GPU: the buffers are made when
// setupDraws hands each piece to the DrawContext, and remade from that same data after a
// context loss (draw.ms rebuildMeshes).
function buildScene(): void {
	layoutStones();
	let ground: MeshData = MeshData.empty();
	const plane: Result<int32, MeshError> = addPlane(ground, GROUND_HALF_SIZE, GROUND);
	if (!plane.ok) { return; }
	addPiece(ground, identityTransform());
	for (const block of stones) {
		let geometry: MeshData = MeshData.empty();
		const added: Result<int32, MeshError> = addBox(geometry, unplaced(block));
		if (!added.ok) { return; }
		addPiece(geometry, placementOf(block));
	}
	firstLogPiece = pieces.length as int32;
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
		let geometry: MeshData = MeshData.empty();
		const added: Result<int32, MeshError> = addBox(geometry, unplaced(log));
		if (!added.ok) { return; }
		addPiece(geometry, placementOf(log));
	}
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
				// The `as int32` is not decoration: Math.min/max answer float64 and the narrowing
				// is an error, so without it this file does not compile. It used to be applied
				// only by the gate's sed, which meant the example built in out/tmp and nowhere
				// else — the `entries` stage now builds what it blesses.
				const clamped: int32 = (Math.max(0, Math.min(TUFT_CELL - 1, offset)) as int32);
				const shade: int32 = 120 + (135 * step) / bladeHeight;
				setTexturePixel(width, cellLeft + clamped, height - 1 - step, shade, shade, shade);
			}
		}
	}
	return makeImage(texturePixels, width, height);
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
	return makeImage(texturePixels, width, height);
}

function deterministicFlameInstance(frame: int32): Vec<float32> {
	return [
		0.0, 0.05, 0.0, frame as float32,
		0.95, 1.2, 1.0, 1.0,
	];
}

function buildFlameBuffers(): void {
	for (let frame = 0; frame < FLAME_FRAMES; frame++) {
		flameBuffers.push(makeVertexBuffer(deterministicFlameInstance(frame)));
	}
}

function updateFlicker(): void {
	if (frameIndex % FLICKER_FRAMES != 0) { return; }
	fireOffsetX = (nextRandom() - 0.5) * 0.16;
	fireOffsetY = (nextRandom() - 0.5) * 0.12;
	fireOffsetZ = (nextRandom() - 0.5) * 0.16;
	fireFlicker = 1.0 + (nextRandom() - 0.5) * 0.14;
	const moved: Result<int32, SceneError> = setLocal(
		tree,
		fireLight,
		transformAt(vec3(fireOffsetX, FIRE_HEIGHT + fireOffsetY, fireOffsetZ)),
	);
	if (!moved.ok) { return; }
	const powered: Result<int32, SceneError> =
		setLightPower(tree, fireLight, FIRE_INTENSITY * fireFlicker);
	if (!powered.ok) { return; }
}


// Materials, meshes and items: lit geometry, grass and one flame, all opaque (the billboards
// discard their transparent texels). The spike draws unculled, depth-tested with LessEqual.
function setupDraws(): void {
	pointSampler = Sampler.create(Filter.Nearest, Wrap.Clamp);
	billboardCornerBuffer = makeVertexBuffer(CORNERS);
	const state: RenderState = RenderState.defaults()
		.withCulling(Face.None)
		.withDepth(true, Compare.LessEqual);
	const litToon: Vec<float32> = [LIGHT_LEVELS, 0.0, 0.0, 0.0];
	const spriteToon: Vec<float32> = [0.2, 0.26, 0.5, 0.0, LIGHT_LEVELS, 0.0, 0.0, 0.0];
	const litBlock: UniformBlock = try reserveUniforms(
		context,
		TOON_UNIFORM_SLOT,
		TOON_UNIFORM_LENGTH,
	) catch NO_UNIFORMS;
	const spriteBlock: UniformBlock = try reserveUniforms(
		context,
		SPRITE_UNIFORM_SLOT,
		SPRITE_UNIFORM_LENGTH,
	) catch NO_UNIFORMS;
	writeUniforms(context, litBlock, litToon);
	writeUniforms(context, spriteBlock, spriteToon);
	const litMaterial: int32 = addMaterial(context, {
		...Material.plain(Program.Lit, state, Phase.Opaque),
		uniforms: litBlock,
	});
	grassMaterial = addMaterial(context, {
		...Material.plain(Program.Billboard, state, Phase.Opaque),
		texture0: grassTexture,
		sampler0: pointSampler.handle,
		uniforms: spriteBlock,
	});
	flameMaterial = addMaterial(context, {
		...Material.plain(Program.Billboard, state, Phase.Opaque),
		texture0: flameTexture,
		sampler0: pointSampler.handle,
		uniforms: spriteBlock,
	});
	const root: NodeId = tree.rootId();
	const group: Result<NodeId, SceneError> = addGroup(tree, root, identityTransform());
	if (!group.ok) { console.log("campfire: setupDraws bailed at addGroup"); return; }
	const logsNamed: Result<int32, SceneError> = setName(tree, group.value, "logs");
	if (!logsNamed.ok) { console.log("campfire: setupDraws bailed at naming the logs"); return; }
	// The moon as h3d.scene.fwd.DirLight: its direction is the node's front vector, and the
	// shader wants the vector at the light, so the node faces away from it. Priority 100, the
	// value Heaps' DirLight sorts at.
	const moonToward: Vec3 = vec3(0.35, 0.9, 0.25).normalized();
	const moon: Result<NodeId, SceneError> = addLightNode(
		tree,
		root,
		{
			...identityTransform(),
			rotation: quatBetween(vec3(0.0, 0.0, 1.0), moonToward.scaled(-1.0)),
		},
		{
			kind: LightKind.Directional,
			color: vec3(1.0, 1.0, 1.0),
			radius: 0.0,
			power: 0.22,
			priority: 100,
		},
	);
	if (!moon.ok) { console.log("campfire: setupDraws bailed at the moon light"); return; }
	// The fire as h3d.scene.fwd.PointLight: its position is the node's world translation, and
	// the flicker below moves both that and its power.
	const fire: Result<NodeId, SceneError> = addLightNode(
		tree,
		root,
		transformAt(vec3(0.0, FIRE_HEIGHT, 0.0)),
		{
			kind: LightKind.Point,
			color: vec3(1.0, 0.45, 0.16),
			radius: FIRE_RADIUS,
			power: FIRE_INTENSITY,
			priority: 0,
		},
	);
	if (!fire.ok) { console.log("campfire: setupDraws bailed at the fire light"); return; }
	fireLight = fire.value;
	logGroup = group.value;
	const logsPickable: Result<int32, SceneError> = setPickable(tree, logGroup, true);
	if (!logsPickable.ok) { console.log("campfire: setupDraws bailed at the pickable logs"); return; }
	for (let i = 0; i < (pieces.length as int32); i++) {
		if (i == BAKED_STONE) {
			const placed: Result<int32, AnimationError> =
				placeBakedStone(pieces[i], placements[i], root, litMaterial);
			if (!placed.ok) { console.log("campfire: setupDraws bailed at the baked stone"); return; }
			continue;
		}
		const uploaded: Result<int32, MeshUploadError> = addMeshData(context, pieces[i]);
		if (!uploaded.ok) { console.log("campfire: setupDraws bailed at addMeshData"); return; }
		// The ground and the stones hang off the root; the logs hang off the group, so their
		// world matrix is the two-level product the flat pieces never exercise.
		const under: NodeId = i >= firstLogPiece ? logGroup : root;
		const placed: Result<NodeId, SceneError> =
			addMeshNode(tree, under, placements[i], uploaded.value, litMaterial);
		if (!placed.ok) { console.log("campfire: setupDraws bailed at placing a piece"); return; }
		if (i == firstLogPiece) { firstLogNode = placed.value; }
		if (i == BAKED_STONE + 1) { plainStoneNode = placed.value; }
	}
	grassMesh = addMesh(
		context,
		GpuMesh.external(VertexLayout.Billboard, billboardCornerBuffer, grassBuffer, 6, grassCount),
	);
	const grassNode: Result<NodeId, SceneError> =
		addMeshNode(tree, root, identityTransform(), grassMesh, grassMaterial);
	if (!grassNode.ok) { console.log("campfire: setupDraws bailed at the grass node"); return; }
	firstFlameMesh = context.meshes.length as int32;
	for (const flameBuffer of flameBuffers) {
		addMesh(
			context,
			GpuMesh.external(VertexLayout.Billboard, billboardCornerBuffer, flameBuffer, 6, 1),
		);
	}
	// The billboard programs ignore the model matrix — their roots are already world-space
	// instance data — so these two nodes sit at the identity and only carry draw order.
	const flame: Result<NodeId, SceneError> =
		addMeshNode(tree, root, identityTransform(), firstFlameMesh, flameMaterial);
	if (!flame.ok) { console.log("campfire: setupDraws bailed at the flame node"); return; }
	flameNode = flame.value;
	const flameNamed: Result<int32, SceneError> = setName(tree, flameNode, "flame");
	if (!flameNamed.ok) { console.log("campfire: setupDraws bailed at naming the flame"); return; }
	if (particlesWanted) {
		const particles: Result<int32, ParticleSetupError> = setupParticles(root, state);
		if (!particles.ok) { console.log("campfire: setupDraws bailed at the particles"); return; }
	}
	const animated: Result<int32, AnimationError> = setupAnimations();
	if (!animated.ok) { console.log("campfire: setupDraws bailed at the animations"); return; }
}

// One stone goes through the vertex-baked path with two identical frames: the image cannot
// change, and upload, frame swap and the mid-run rebuild all run on it every capture.
function placeBakedStone(
	stone: MeshData,
	where: Transform3D,
	root: NodeId,
	material: int32,
): Result<int32, AnimationError> {
	const frames: Vec<MeshData> = [stone, stone];
	firstStoneFrame = try addBakedFrames(context, frames);
	const placed: Result<NodeId, SceneError> =
		addMeshNode(tree, root, where, firstStoneFrame, material);
	if (!placed.ok) { return Result.err(AnimationError.StaleTarget); }
	const named: Result<int32, SceneError> = setName(tree, placed.value, "bakedStone");
	if (!named.ok) { return Result.err(AnimationError.StaleTarget); }
	const marked: Result<int32, SceneError> = setPickable(tree, placed.value, true);
	if (!marked.ok) { return Result.err(AnimationError.StaleTarget); }
	bakedStoneNode = placed.value;
	return Result.ok(placed.value.index);
}

enum ParticleSetupError {
	StreamRefused,
	NodeRefused,
	EmitterRefused,
}

function setupParticles(root: NodeId, state: RenderState): Result<int32, ParticleSetupError> {
	particleMaterial = addMaterial(context, Material.plain(Program.Particle, state, Phase.Opaque));
	const snowStream: Result<int32, StreamError> = addStreamMesh(context, snow.capacity);
	const emberStream: Result<int32, StreamError> = addStreamMesh(context, embers.capacity);
	if (!snowStream.ok || !emberStream.ok) { return Result.err(ParticleSetupError.StreamRefused); }
	snowMesh = snowStream.value;
	emberMesh = emberStream.value;
	const snowPlaced: Result<NodeId, SceneError> = addMeshNode(
		tree,
		root,
		transformAt(vec3(0.0, SNOW_HEIGHT, 0.0)),
		snowMesh,
		particleMaterial,
	);
	const emberPlaced: Result<NodeId, SceneError> = addMeshNode(
		tree,
		root,
		transformAt(vec3(0.0, EMBER_HEIGHT, 0.0)),
		emberMesh,
		particleMaterial,
	);
	if (!snowPlaced.ok || !emberPlaced.ok) { return Result.err(ParticleSetupError.NodeRefused); }
	snowNode = snowPlaced.value;
	emberNode = emberPlaced.value;
	const _synced: int32 = syncWorld(tree);
	for (let i = 0; i < PARTICLE_WARMUP_STEPS; i++) {
		if (!advanceEmitter(snow, snowNode)) { return Result.err(ParticleSetupError.EmitterRefused); }
		if (!advanceEmitter(embers, emberNode)) { return Result.err(ParticleSetupError.EmitterRefused); }
	}
	return Result.ok(2);
}

function advanceEmitter(ref emitter: ParticleEmitter, node: NodeId): boolean {
	const world: Result<Mat4, SceneError> = tree.worldOf(node);
	if (!world.ok) { return false; }
	return updateEmitter(emitter, PARTICLE_STEP, world.value).ok;
}

function drawEmitter(
	ref emitter: ParticleEmitter,
	node: NodeId,
	mesh: int32,
	instances: Span<float32>,
): boolean {
	const world: Result<Mat4, SceneError> = tree.worldOf(node);
	if (!world.ok) { return false; }
	const written: Result<int32, ParticleError> = writeInstances(emitter, world.value, instances);
	if (!written.ok) { return false; }
	return writeStream(context, mesh, instances, written.value).ok;
}

function applyLookSchedule(): void {
	if (!lookScheduleWanted) { return; }
	if (frameIndex == LOOK_WINTER_AT) {
		const swapped: Result<int32, PaletteError> = setPalette(renderer, WINTER_PALETTE);
		if (!swapped.ok) { console.log("campfire: the winter palette was refused"); }
	}
	if (frameIndex == LOOK_GREY_AT) {
		setLook(renderer, { ...campfireLook(), saturation: -1.0 });
	}
	if (frameIndex == LOOK_RESTORED_AT) {
		const restored: Result<int32, PaletteError> = setPalette(renderer, CAMPFIRE_PALETTE);
		if (!restored.ok) { console.log("campfire: the night palette was refused"); }
		setLook(renderer, campfireLook());
	}
}

// The example's clock runs in frames, not seconds: every animation is updated by 1.0 per
// frame, so a sampling rate is keys per frame. The flame steps one atlas cell every
// FLICKER_FRAMES frames; the log spin is one key per frame.
function setupAnimations(): Result<int32, AnimationError> {
	const perFlicker: float64 = 1.0 / (FLICKER_FRAMES as float64);
	const flameClock: AnimationClock =
		try AnimationClock.forFrames(FLAME_FRAMES, perFlicker, Interpolation.Step);
	const cells: Vec<int32> = [];
	for (let i = 0; i < FLAME_FRAMES; i++) { cells.push(firstFlameMesh + i); }
	flameFrames = try MeshFrameAnimation.forMeshes(flameClock, "flame", cells);
	const _flame: int32 = try bindMeshFrames(flameFrames, tree, tree.rootId());
	const stoneClock: AnimationClock =
		try AnimationClock.forFrames(2, perFlicker, Interpolation.Step);
	const stoneMeshes: Vec<int32> = [firstStoneFrame, firstStoneFrame + 1];
	stoneFrames = try MeshFrameAnimation.forMeshes(stoneClock, "bakedStone", stoneMeshes);
	const _stone: int32 = try bindMeshFrames(stoneFrames, tree, tree.rootId());
	if (logSpinPerFrame == 0.0) { return Result.ok(0); }
	let spinClock: AnimationClock =
		try AnimationClock.forFrames(SPIN_KEYS, 1.0, Interpolation.Step);
	spinClock.loop = false;
	logSpin = ObjectAnimation.forClock(spinClock);
	const turns: Vec<Transform3D> = [];
	for (let i = 0; i < SPIN_KEYS; i++) {
		const angle: float32 = logSpinPerFrame * (i as float32);
		turns.push({ ...identityTransform(), rotation: eulerQuat(0.0, angle, 0.0) });
	}
	const _track: int32 = try addTrack(logSpin, "logs", turns);
	return bindTracks(logSpin, tree, tree.rootId());
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

// For the M5 check: at this frame, tell the renderer that every mesh's handles came from a GPU
// context that is gone, so its rebuild path re-uploads the ones that carry CPU data. Off
// Android `contextGeneration()` never moves, so nothing else here ever exercises that branch.
// The frames captured after it say whether the rebuilt buffers draw the same pixels. The
// default never does it.
export function configureCampfireRebuildAt(frame: int32): void {
	rebuildAtFrame = frame;
}

// For the seventh capture configuration: turn the log group a little every frame, as a stepped
// keyframe animation of SPIN_KEYS keys that then holds its last one. It is the one thing the
// standing campfire does not exercise — a node that moves after setup, and a child whose world
// matrix is its parent's times its own. Zero leaves the group at the identity.
export function configureCampfireLogSpin(radiansPerFrame: float32): void {
	logSpinPerFrame = radiansPerFrame;
}

// Snow and embers on the particle path. Off by default, so the configurations that predate them
// still draw what they drew.
export function configureCampfireParticles(on: boolean): void {
	particlesWanted = on;
}

// Swaps to WINTER_PALETTE at frame 5, greys the look at frame 10 and puts both back at frame 15.
// Needs the palette on.
export function configureCampfireLookSchedule(on: boolean): void {
	lookScheduleWanted = on;
}

function copyTexturePixels(): Vec<uint32> {
	const kept: Vec<uint32> = new Array(texturePixels.length as int32);
	for (let i = 0; i < (texturePixels.length as int32); i++) { kept[i] = texturePixels[i]; }
	return kept;
}

// Everything this file owns is re-made from its CPU copies — corners and grass instances back
// into buffers, the kept pixels back into textures, the sampler afresh — and the re-made
// handles are written back into the external meshes and materials that hold them. Nothing
// re-rolls the RNG: the grass and the textures were generated once, and a rebuild replays
// data, not chance.
function forceRebuild(): void {
	destroyBuffer(billboardCornerBuffer);
	destroyBuffer(grassBuffer);
	for (let i = 0; i < (flameBuffers.length as int32); i++) {
		destroyBuffer(flameBuffers[i]);
	}
	destroyView(grassTexture);
	destroyImage(grassImage);
	destroyView(flameTexture);
	destroyImage(flameImage);
	destroySampler(pointSampler.handle);
	billboardCornerBuffer = makeVertexBuffer(CORNERS);
	grassBuffer = makeVertexBuffer(grassInstances);
	for (let i = 0; i < (flameBuffers.length as int32); i++) {
		flameBuffers[i] = makeVertexBuffer(deterministicFlameInstance(i));
	}
	grassImage = makeImage(tuftPixels, TUFT_CELL * ATLAS_CELLS, TUFT_CELL);
	flameImage = makeImage(flamePixels, FLAME_CELL_WIDTH * FLAME_FRAMES, FLAME_CELL_HEIGHT);
	grassTexture = makeTextureView(grassImage);
	flameTexture = makeTextureView(flameImage);
	pointSampler = Sampler.create(Filter.Nearest, Wrap.Clamp);
	context.materials[grassMaterial].texture0 = grassTexture;
	context.materials[grassMaterial].sampler0 = pointSampler.handle;
	context.materials[flameMaterial].texture0 = flameTexture;
	context.materials[flameMaterial].sampler0 = pointSampler.handle;
	context.meshes[grassMesh].vertexBuffer = billboardCornerBuffer;
	context.meshes[grassMesh].instanceBuffer = grassBuffer;
	for (let i = 0; i < (flameBuffers.length as int32); i++) {
		context.meshes[firstFlameMesh + i].vertexBuffer = billboardCornerBuffer;
		context.meshes[firstFlameMesh + i].instanceBuffer = flameBuffers[i];
	}
	for (let i = 0; i < (context.meshes.length as int32); i++) {
		if (context.meshes[i].generation != EXTERNAL_GENERATION) {
			if (context.meshes[i].vertexBuffer != 0) { destroyBuffer(context.meshes[i].vertexBuffer); }
			if (context.meshes[i].indexBuffer != 0) { destroyBuffer(context.meshes[i].indexBuffer); }
			if (context.meshes[i].isStream() && context.meshes[i].instanceBuffer != 0) {
				destroyBuffer(context.meshes[i].instanceBuffer);
			}
			context.meshes[i].generation = 0;
		}
	}
	rebuildMeshes(context);
}

// What the bench stage reads. Every field is a length that a steady frame must not move: the
// draw list, the tree's node table and its descent stack, the uniform pool, the mesh table and
// the pipeline cache. "Frame state is preallocated... nothing in `frame` allocates"
// (docs/VOID3D.md, Data types) is a claim about exactly these, and a growth of zero across a
// long run is what makes it a measurement instead of an intention.
//
// The DRC ledger (`-DMS_DRC_LEDGER`) is deliberately not what this uses. It was tried: it
// counts typed ref objects and reports alloc=0 for a `Vec` and for a string, so on a renderer
// built from structs and `Vec` it would pass while measuring nothing. A gate that cannot fail
// is worse than no gate.
export struct CampfireStats {
	drawItems: int32;
	nodes: int32;
	meshes: int32;
	rebuildable: int32;
	pipelines: int32;
	uniforms: int32;
	stack: int32;
}

export function campfireStats(): CampfireStats {
	let rebuildable: int32 = 0;
	for (let i = 0; i < (context.meshData.length as int32); i++) {
		if (context.meshData[i].vertexCount() > 0) { rebuildable = rebuildable + 1; }
	}
	return {
		drawItems: sceneItems.length as int32,
		nodes: tree.nodeCount(),
		meshes: context.meshes.length as int32,
		rebuildable: rebuildable,
		pipelines: context.pipelines.entries.length as int32,
		uniforms: context.uniforms.length as int32,
		stack: tree.stack.length as int32,
	};
}

export struct CampfireTargets {
	logs: NodeId;
	firstLog: NodeId;
	bakedStone: NodeId;
	plainStone: NodeId;
}

export function campfireTargets(): CampfireTargets {
	return {
		logs: logGroup,
		firstLog: firstLogNode,
		bakedStone: bakedStoneNode,
		plainStone: plainStoneNode,
	};
}

// Host pixels count rows from the top (sokol_app events, Android MotionEvent); the blit's
// framebuffer pixels count them from the bottom on GL.
function flipRowIfGl(row: float32): float32 {
	if (originTopLeft()) { return row; }
	return (shownHeight as float32) - row;
}

// The host pixel under the centre of a mesh node's bounds in the last frame drawn.
export function campfirePixelOf(id: NodeId): Result<Vec3, SceneError> {
	if (!tree.isLive(id)) { return Result.err(SceneError.StaleNode); }
	if (tree.nodes[id.index].kind != NodeKind.Mesh) {
		return Result.err(SceneError.NotAMeshNode);
	}
	const mesh: int32 = tree.meshes[tree.nodes[id.index].payload].mesh;
	if (mesh < 0 || mesh >= (context.meshData.length as int32)) {
		return Result.err(SceneError.NodeNotFound);
	}
	const box: Bounds = context.meshData[mesh].bounds;
	const centre: Vec3 = box.center() * tree.nodes[id.index].world;
	const pixel: Vec3 = shownView.project(centre, shownBlit, originTopLeft());
	return Result.ok(vec3(pixel.x, flipRowIfGl(pixel.y), pixel.z));
}

export function campfireTap(hostX: float32, hostY: float32): Result<PickHit, PickError> {
	const ray: Ray =
		shownView.rayFromScreen(hostX, flipRowIfGl(hostY), shownBlit, originTopLeft());
	return pickNearest(tree, context.meshData, context.materials, ray);
}

export function initCampfire(): void {
	gfxSetup();
	buildScene();
	buildGrass();
	buildFlameBuffers();
	grassImage = buildTuftTexture();
	tuftPixels = copyTexturePixels();
	grassTexture = makeTextureView(grassImage);
	flameImage = buildFlameTexture();
	flamePixels = copyTexturePixels();
	flameTexture = makeTextureView(flameImage);
	setupDraws();
	setAmbient(tree, vec3(0.33, 0.36, 0.6));
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
	const framebufferHeight: int32 = fbHeight();
	const sized: Result<LowResView, ViewError> = renderer.viewFor(
		fbWidth(),
		framebufferHeight,
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

	if (logSpinPerFrame != 0.0) {
		const spun: Result<int32, AnimationError> = syncPose(logSpin, tree);
		if (!spun.ok) { return; }
	}
	const swapped: Result<int32, AnimationError> = syncMeshFrame(flameFrames, tree);
	if (!swapped.ok) { return; }
	const stoneSwapped: Result<int32, AnimationError> = syncMeshFrame(stoneFrames, tree);
	if (!stoneSwapped.ok) { return; }
	// Sync the world matrices and rewrite the list in place. The structure only changes once,
	// at setup, so every later frame takes the rewrite path and allocates nothing.
	const drawn: int32 = refresh(tree, sceneItems);
	if (drawn == 0) { return; }
	// Lights are read out of the synced tree: a light's position and direction are its world
	// matrix, so collecting before `refresh` would read the previous frame's.
	const lit: Result<int32, LightError> = collectLights(tree, lightParams);
	if (!lit.ok) { return; }
	if (particlesWanted) {
		const stepped: boolean = advanceEmitter(snow, snowNode) && advanceEmitter(embers, emberNode);
		const drawn: boolean = stepped &&
			drawEmitter(snow, snowNode, snowMesh, snowInstances) &&
			drawEmitter(embers, emberNode, emberMesh, emberInstances);
		if (!drawn) { console.log("campfire: a particle emitter failed to step or draw"); return; }
	}
	applyLookSchedule();
	renderFrame(renderer, context, sceneItems, cameraParams, lightParams, viewed.value);
	shownView = cameraView;
	shownBlit = viewed.value;
	shownHeight = framebufferHeight;
	const flameMoved: Result<boolean, AnimationError> = update(flameFrames.clock, 1.0);
	const stoneMoved: Result<boolean, AnimationError> = update(stoneFrames.clock, 1.0);
	const logsMoved: Result<boolean, AnimationError> = update(logSpin.clock, 1.0);
	if (!flameMoved.ok || !stoneMoved.ok || !logsMoved.ok) { return; }
	frameIndex = frameIndex + 1;
	if (frameIndex == rebuildAtFrame) { forceRebuild(); }
}
