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
	addMesh,
	addMeshData,
	addMaterial,
	rebuildMeshes,
	reserveUniforms,
	writeUniforms,
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
import { Vec3, vec3, eulerQuat, quatBetween } from "../math/math3d";
import { MeshData, MeshError, Rgba, Box, addBox, addPlane } from "../void3d/meshData";
import {
	Scene,
	NodeId,
	Transform3D,
	SceneError,
	LightError,
	LightKind,
	identityTransform,
	transformAt,
	addGroup,
	addMeshNode,
	addLightNode,
	setLocal,
	setName,
	setLightPower,
	setAmbient,
	collectLights,
	refresh,
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
	return Result.ok(placed.value.index);
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
	renderFrame(renderer, context, sceneItems, cameraParams, lightParams, viewed.value);
	const flameMoved: Result<boolean, AnimationError> = update(flameFrames.clock, 1.0);
	const stoneMoved: Result<boolean, AnimationError> = update(stoneFrames.clock, 1.0);
	const logsMoved: Result<boolean, AnimationError> = update(logSpin.clock, 1.0);
	if (!flameMoved.ok || !stoneMoved.ok || !logsMoved.ok) { return; }
	frameIndex = frameIndex + 1;
	if (frameIndex == rebuildAtFrame) { forceRebuild(); }
}
