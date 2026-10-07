// A card table: the end-to-end consumer of void3d's M33 to M43, built only from Void's public
// API with procedural placeholder assets (docs/VOID3D.md, "M44 as built").
//
//   a board         a normal-mapped textured quad that receives the sun's shadow (M35, M37)
//   a hand          five cards, each a void2d render target on a quad (M27), overlapping and
//                   reordered every few frames with a per-node render order (M43)
//   a discard       one more card that dissolves with an emissive-looking edge (M36)
//   a sun           a directional light with a shadow map (M35)
//   two torches     particle emitters with Godot's turbulence and initial speed (M38), a point
//                   light each, and an emissive bowl (M37)
//   a highlight     drawn by a second camera on layer 1 into a transparent target, composited
//                   premultiplied over the first view (M40)
//   a label         text in the world, turned to face the camera (M41)
//
// `setupCardTable` makes everything, `frameCardTable` draws one frame and allocates nothing.
// The entry (mainCardTable.ms) and the readback test (tests/integration/cardTable.ms) share
// both. A featureless setup keeps every object and turns each feature off.

import { gfxSetup } from "../sokol/gpu";
import { Vec3, Vec4, Quat, Mat4, vec3, quatBetween } from "../math/math3d";
import { RenderState, BlendMode, Face, FilterMode, Wrap } from "../gpu/state";
import { PixelFormat, endPass, commit, originTopLeft } from "../gpu/door";
import { RenderTarget, beginScreenPass } from "../gpu/target";
import { Scene2D, NodeRef } from "../void2d/node";
import "../void2d/scene";
import { setup2d } from "../void2d/draw";
import { rgba, targetTile, whiteTile } from "../void2d/types";
import { BoxStyle, uniformRadii, uniformBorders } from "../void2d/boxStyle";
import {
	Program,
	ProgramKey,
	MATERIAL_UNIFORM_SLOT,
	UNLIT_MATERIAL_COLOR,
	VERTEX_UNIFORM_LENGTH,
	LIGHT_UNIFORM_LENGTH,
	MOVING_DISSOLVE_THRESHOLD,
	MOVING_DISSOLVE_EDGE_WIDTH,
	MOVING_DISSOLVE_EDGE_COLOR,
	EMISSIVE_COLOR,
	EMISSIVE_STRENGTH,
	EMISSIVE_LENGTH,
	movingBase,
	emissiveBase,
} from "../void3d/gpu3d";
import {
	Material, Phase, MaterialKind, ShadowCasting, UniformBlock, movingDefaults,
} from "../void3d/material";
import {
	MeshData, MeshError, Rgba, Uv, addTexturedVertex, addTriangle, addTangents, addTexturedCube,
} from "../void3d/meshData";
import { TextureData, TextureId, TextureUploadError, TextureAlpha } from "../void3d/texture";
import {
	DrawContext,
	DrawItem,
	MeshId,
	MaterialId,
	MaterialError,
	MeshUploadError,
	StreamError,
	addMeshData,
	addMaterial,
	addTexture,
	addTargetTexture,
	addStreamMesh,
	writeStream,
	reserveUniforms,
	writeUniforms,
} from "../void3d/draw";
import { UniformError } from "../void3d/uniformPool";
import {
	Scene3D,
	Transform3D,
	NodeId3D,
	SceneError,
	LightKind,
	LightInstance,
	LightError,
	NO_NODE_ID,
	addMeshNode,
	addLightNode,
	addCameraNode,
	setActiveCamera,
	setCameraLayers,
	cameraViewOf,
	setLayers,
	setVisible,
	setRenderOrder,
	setLightPower,
	setAmbient,
	refresh,
	refreshFor,
	syncWorld,
	collectLights,
	collectLightsFor,
} from "../void3d/scene";
import { layerBit } from "../void3d/layers";
import { Camera3D, CameraView, CameraError, ProjectionKind, basisOf } from "../void3d/camera";
import { ANCHOR_CENTER } from "../void3d/billboard";
import { attachShadow, openScreen } from "../void3d/renderer";
import { DirShadowMap, ShadowError, DIR_SHADOW_UNIFORM_LENGTH } from "../void3d/dirShadowMap";
import {
	ForwardRenderer,
	ForwardError,
	FORWARD_UNIFORM_LENGTH,
	prepareFrame as prepareForward,
	drawToScreen as drawForwardToScreen,
} from "../void3d/forwardRenderer";
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
import {
	WorldLabel,
	WorldLabelStyle,
	WorldLabelError,
	labelQuad,
	facingRotation,
	faceCamera,
	refreshLabel,
} from "../void3d/worldLabel";

export enum CardTableError {
	Camera,
	Lights,
	Forward,
	Overlay,
	Particles,
	Label,
}

export const HAND_SIZE: int32 = 5;
// The hand's cards overlap, and these two swap their render orders every SWAP_PERIOD frames:
// one is on top for a period and the other for the next.
export const SWAP_LOW: int32 = 1;
export const SWAP_HIGH: int32 = 2;
export const SWAP_PERIOD: int32 = 12;
// The hand card the second camera highlights.
export const HIGHLIGHTED: int32 = 3;
// The dissolve reaches its hold at this frame and keeps it for DISSOLVE_HOLD_END - this frames.
export const DISSOLVE_HOLD_START: int32 = 20;
export const DISSOLVE_HOLD_END: int32 = 100;
export const DISSOLVE_THRESHOLD: float32 = 0.5;
export const CARD_WIDTH: float32 = 1.0;
export const CARD_HEIGHT: float32 = 1.4;
// The highlight is this many times the card, so its margin lies over the board.
export const HIGHLIGHT_SCALE: float32 = 1.5;
export const TO_LIGHT: Vec3 = { x: -0.6, y: 1.0, z: -1.0 };
export const LABEL_POSITION: Vec3 = { x: 0.0, y: 1.5, z: -2.4 };
export const LABEL_PIXELS_PER_UNIT: float32 = 100.0;
export const TORCH_X: float32 = 3.2;
export const TORCH_Z: float32 = -1.8;
export const FLAME_BASE: float32 = 1.05;

const CARD_TARGET_WIDTH: int32 = 160;
const CARD_TARGET_HEIGHT: int32 = 224;
const CARD_CORNER: float32 = 14.0;
const CARD_NORMAL: Vec3 = { x: 0.0, y: 0.6, z: 0.8 };
const HAND_CENTER_X: float32 = -0.6;
const HAND_SPACING: float32 = 0.66;
const HAND_Z: float32 = 1.8;
const DISCARD_X: float32 = 2.6;
const DISCARD_Z: float32 = 1.0;
const BOARD_HALF_X: float32 = 4.0;
const BOARD_HALF_Z: float32 = 3.0;
const BOARD_REPEAT_X: float32 = 4.0;
const BOARD_REPEAT_Z: float32 = 3.0;
const TILE: int32 = 32;
const SHADOW_SIZE: int32 = 1024;
const SHADOW_OPACITY: float32 = 0.8;
const PARTICLE_STEP: float64 = 1.0 / 60.0;
const PARTICLE_WARMUP: int32 = 90;
const FLICKER_FRAMES: int32 = 6;
const POOL_MARGIN: int32 = 1024;
const WHITE: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };
const CLEAR: Vec4 = { x: 0.04, y: 0.05, z: 0.10, w: 1.0 };
const TRANSPARENT: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 0.0 };
const SCREEN_CLEAR: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };

// The cards' faces, 0xRRGGBB through rgba() below: amber, red, blue, purple, ivory, and the
// discarded card's magenta.
const CARD_RED: Vec<float32> = [0.90, 0.85, 0.15, 0.60, 0.95];
const CARD_GREEN: Vec<float32> = [0.70, 0.15, 0.25, 0.25, 0.95];
const CARD_BLUE: Vec<float32> = [0.20, 0.12, 0.85, 0.75, 0.88];
const CARD_LETTERS: Vec<string> = ["A", "B", "C", "D", "E"];

let featureless: boolean = false;
let context: DrawContext = DrawContext.withUniformCapacity(
	2 * FORWARD_UNIFORM_LENGTH + DIR_SHADOW_UNIFORM_LENGTH + POOL_MARGIN,
);
let scene: Scene3D = Scene3D.create(context);
let forward: ForwardRenderer = makeForward(CLEAR);
let overlay: ForwardRenderer = makeForward(TRANSPARENT);
let shadow: DirShadowMap = makeShadow();
let items: Vec<DrawItem> = [];
let overlayItems: Vec<DrawItem> = [];
let cameraValues: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let overlayValues: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let overlayLights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let mainCamera: NodeId3D = NO_NODE_ID;
let overlayCamera: NodeId3D = NO_NODE_ID;
let handNodes: Vec<NodeId3D> = [];
let discardNode: NodeId3D = NO_NODE_ID;
let highlightNode: NodeId3D = NO_NODE_ID;
let torchLights: Vec<NodeId3D> = [];
let label: WorldLabel | null = null;
let cardScenes: Vec<Scene2D> = [];
let display: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 0.0));
let displaySprite: NodeRef = display.sprite(whiteTile(1.0, 1.0));
let displayImage: uint32 = 0;
let displayWidth: int32 = 0;
let torchA: ParticleEmitter = emitterOf(11);
let torchB: ParticleEmitter = emitterOf(23);
let torchANode: NodeId3D = NO_NODE_ID;
let torchBNode: NodeId3D = NO_NODE_ID;
let torchAMesh: MeshId = { store: 0, index: 0, generation: 0 };
let torchBMesh: MeshId = { store: 0, index: 0, generation: 0 };
let torchAInstances: Vec<float32> = new Array(flameState().maxParts * PARTICLE_INSTANCE_STRIDE);
let torchBInstances: Vec<float32> = new Array(flameState().maxParts * PARTICLE_INSTANCE_STRIDE);
let dissolveKey: ProgramKey = ProgramKey.of(Program.UnlitTextured).withDissolve();
let dissolveBlock: UniformBlock = { store: 0, slot: 0, offset: 0, length: 0, generation: 0 };
let dissolveValues: Vec<float32> = movingDefaults(dissolveKey);

function stop(message: string): void {
	console.log(`card table: ${message}`);
}

function makeForward(background: Vec4): ForwardRenderer {
	const made: Result<ForwardRenderer, ForwardError> =
		ForwardRenderer.create(context, background);
	if (made.ok) { return made.value; }
	stop(`a forward preset was refused: ${made.error.toString()}`);
	unreachable;
}

function makeShadow(): DirShadowMap {
	const made: Result<DirShadowMap, ShadowError> = DirShadowMap.create(context, SHADOW_SIZE);
	if (made.ok) { return made.value; }
	stop(`the shadow map was refused: ${made.error.toString()}`);
	unreachable;
}

function flameState(): EmitterState {
	const base: EmitterState = EmitterState.defaults();
	return {
		...base,
		emitRate: constant(36.0),
		maxParts: 72,
		shape: { kind: ShapeKind.Cone, radius: constant(0.05), angle: constant(0.3) },
		life: { kind: ValueKind.Random, start: 0.7, length: 0.6, converge: Converge.No },
		size: constant(0.07),
		speed: constant(0.0),
		initialSpeed: { kind: ValueKind.Random, start: 0.7, length: 0.5, converge: Converge.No },
		gravity: constant(-0.35),
		damping: constant(0.4),
		turbulence: {
			...base.turbulence,
			enabled: true,
			noiseStrength: 1.5,
			noiseScale: 6.0,
			noiseSpeed: vec3(0.0, 0.8, 0.0),
			influence: constant(0.5),
		},
		colors: [
			{ time: 0.0, color: 0xFFE070 },
			{ time: 0.5, color: 0xFF7A20 },
			{ time: 1.0, color: 0x9A2A10 },
		],
		alpha: { kind: ValueKind.Linear, start: 1.5, length: -1.2 },
	};
}

function emitterOf(seed: uint32): ParticleEmitter {
	const made: Result<ParticleEmitter, ParticleError> =
		ParticleEmitter.create(flameState(), seed);
	if (made.ok) { return made.value; }
	unreachable;
}

// ---- Assets --------------------------------------------------------------------------------

function texture(
	pixels: Vec<uint32>,
	width: int32,
	height: int32,
	filter: FilterMode,
	wrap: Wrap,
): TextureId {
	const data: TextureData = {
		pixels: pixels, width: width, height: height, filter: filter, wrap: wrap,
	};
	const uploaded: Result<TextureId, TextureUploadError> = addTexture(context, data);
	if (uploaded.ok) { return uploaded.value; }
	stop(`a texture was refused: ${uploaded.error.toString()}`);
	unreachable;
}

function solid(texel: uint32): TextureId {
	return texture([texel], 1, 1, FilterMode.Nearest, Wrap.Clamp);
}

function texelOf(red: int32, green: int32, blue: int32): uint32 {
	return (0xFF000000 as uint32) | ((blue as uint32) << (16 as uint32)) |
		((green as uint32) << (8 as uint32)) | (red as uint32);
}

// A cheap repeatable hash in [0, 12], so the felt is not flat.
function grain(x: int32, y: int32): int32 {
	return (x * 73 + y * 151 + x * y * 13) % 13;
}

// The board's felt: green, with a darker stitch line along the tile's first row and column.
function feltTile(): TextureId {
	let pixels: Vec<uint32> = [];
	for (let y = 0; y < TILE; y++) {
		for (let x = 0; x < TILE; x++) {
			const noise: int32 = grain(x, y);
			if (x == 0 || y == 0) {
				pixels.push(texelOf(14, 60 + noise, 30));
			} else {
				pixels.push(texelOf(24 + noise / 2, 108 + noise, 54 + noise / 2));
			}
		}
	}
	return texture(pixels, TILE, TILE, FilterMode.Nearest, Wrap.Repeat);
}

// A tangent-space normal map: flat, with the stitch line tilted each side of its groove, so the
// light catches one edge of it. Bytes are (n * 0.5 + 0.5) * 255.
function stitchNormals(): TextureId {
	let pixels: Vec<uint32> = [];
	for (let y = 0; y < TILE; y++) {
		for (let x = 0; x < TILE; x++) {
			let red: int32 = 128;
			let green: int32 = 128;
			if (x == 0) { red = 204; }
			if (x == 1) { red = 51; }
			if (y == 0) { green = 204; }
			if (y == 1) { green = 51; }
			pixels.push(texelOf(red, green, 229));
		}
	}
	return texture(pixels, TILE, TILE, FilterMode.Nearest, Wrap.Repeat);
}

// Sixteen columns whose red climbs with u, so a dissolve threshold takes the card from its left
// edge. Every column's grain stays under its 16-step, so a threshold between two columns cuts
// exactly the columns below it.
function noiseRamp(): TextureId {
	let pixels: Vec<uint32> = [];
	for (let y = 0; y < 16; y++) {
		for (let x = 0; x < 16; x++) {
			pixels.push(texelOf(x * 16 + 4 + grain(x, y) / 2, 0, 0));
		}
	}
	return texture(pixels, 16, 16, FilterMode.Nearest, Wrap.Clamp);
}

function block(values: Vec<float32>): UniformBlock {
	const reserved: Result<UniformBlock, UniformError> =
		reserveUniforms(context, MATERIAL_UNIFORM_SLOT, values.length as int32);
	if (!reserved.ok) {
		stop(`a uniform block was refused: ${reserved.error.toString()}`);
		unreachable;
	}
	if (!writeUniforms(context, reserved.value, values).ok) {
		stop("a uniform block was not written");
		unreachable;
	}
	return reserved.value;
}

function litBlock(): UniformBlock {
	return block([4.0, 0.0, 0.0, 0.0]);
}

function unlitBlock(): UniformBlock {
	return block([0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0]);
}

function material(made: Material): MaterialId {
	const added: Result<MaterialId, MaterialError> = addMaterial(context, made);
	if (added.ok) { return added.value; }
	stop(`a material was refused: ${added.error.toString()}`);
	unreachable;
}

function mesh(data: MeshData): MeshId {
	const uploaded: Result<MeshId, MeshUploadError> = addMeshData(context, data);
	if (uploaded.ok) { return uploaded.value; }
	stop(`a mesh was refused: ${uploaded.error.toString()}`);
	unreachable;
}

function place(parent: NodeId3D, at: Transform3D, shown: MeshId, made: MaterialId): NodeId3D {
	const placed: Result<NodeId3D, SceneError> = addMeshNode(scene, parent, at, shown, made);
	if (placed.ok) { return placed.value; }
	stop(`a node was refused: ${placed.error.toString()}`);
	unreachable;
}

// The board lies in the xz plane facing +y and repeats its tile; the tangents follow the uvs.
function boardMesh(): MeshId {
	let data: MeshData = MeshData.withUvs();
	const normal: Vec3 = vec3(0.0, 1.0, 0.0);
	const corners: Vec<Vec3> = [
		vec3(-BOARD_HALF_X, 0.0, BOARD_HALF_Z), vec3(BOARD_HALF_X, 0.0, BOARD_HALF_Z),
		vec3(BOARD_HALF_X, 0.0, -BOARD_HALF_Z), vec3(-BOARD_HALF_X, 0.0, -BOARD_HALF_Z),
	];
	const uvs: Vec<Uv> = [
		{ u: 0.0, v: BOARD_REPEAT_Z }, { u: BOARD_REPEAT_X, v: BOARD_REPEAT_Z },
		{ u: BOARD_REPEAT_X, v: 0.0 }, { u: 0.0, v: 0.0 },
	];
	for (let i = 0; i < 4; i++) {
		if (!addTexturedVertex(data, corners[i], normal, uvs[i], WHITE).ok) { unreachable; }
	}
	if (!addTriangle(data, 0, 1, 2).ok || !addTriangle(data, 0, 2, 3).ok) { unreachable; }
	if (!addTangents(data).ok) { unreachable; }
	return mesh(data);
}

// A unit quad facing +z, centred, with v flipped where a target's rows run bottom-up.
function cardQuad(): MeshId {
	const shape: Result<MeshData, MeshError> = labelQuad(ANCHOR_CENTER, !originTopLeft());
	if (!shape.ok) { unreachable; }
	return mesh(shape.value);
}

function cube(width: float32, height: float32, depth: float32): MeshId {
	let data: MeshData = MeshData.withUvs();
	if (!addTexturedCube(data, vec3(width, height, depth), true, WHITE).ok) { unreachable; }
	return mesh(data);
}

// A card is seen from the camera and lit from behind, so its shadow comes from its back face:
// the shadow pass takes the main pass's culling, and a back face culled there casts nothing.
function twoSided(): RenderState {
	return RenderState.defaults().withCulling(Face.None);
}

function premultipliedPass(): RenderState {
	const pass: RenderState = twoSided();
	return pass.withDepth(false, pass.depthTest).withBlendMode(BlendMode.AlphaAdd);
}

// ---- Cards ---------------------------------------------------------------------------------

// A card's face: a rectangle in its colour (rounded when it may be transparent at the corners)
// and its letter, drawn by void2d into a target once.
function cardTarget(
	red: float32,
	green: float32,
	blue: float32,
	letter: string,
	rounded: boolean,
): RenderTarget {
	const ui: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 0.0));
	const face: NodeRef = ui.rect(
		CARD_TARGET_WIDTH as float32, CARD_TARGET_HEIGHT as float32, rgba(red, green, blue, 1.0),
	);
	if (rounded) {
		face.setBoxStyle(BoxStyle.create(
			uniformRadii(CARD_CORNER), uniformBorders(0.0), rgba(0.0, 0.0, 0.0, 0.0),
		));
	}
	ui.add(face);
	ui.add(ui.label(letter, 72.0, rgba(1.0, 1.0, 1.0, 1.0)).at(14.0, 6.0));
	const target: RenderTarget =
		RenderTarget.allocate(CARD_TARGET_WIDTH, CARD_TARGET_HEIGHT, PixelFormat.Rgba8, true);
	ui.prepare(CARD_TARGET_WIDTH as float32, CARD_TARGET_HEIGHT as float32, 1.0);
	ui.drawTarget(target);
	cardScenes.push(ui);
	return target;
}

function targetTexture(target: RenderTarget, alpha: TextureAlpha): TextureId {
	const added: Result<TextureId, TextureUploadError> =
		addTargetTexture(context, target, FilterMode.Linear, Wrap.Clamp, alpha);
	if (added.ok) { return added.value; }
	stop(`a card's target texture was refused: ${added.error.toString()}`);
	unreachable;
}

function cardRotation(): Quat {
	return quatBetween(vec3(0.0, 0.0, 1.0), CARD_NORMAL.normalized());
}

// The card stands on the table with its lower edge just above it, leaning back.
function cardCenter(x: float32, z: float32): Vec3 {
	return vec3(x, 0.5 * CARD_HEIGHT * CARD_NORMAL.normalized().z + 0.03, z);
}

function cardAt(x: float32, z: float32): Transform3D {
	return {
		position: cardCenter(x, z), rotation: cardRotation(),
		scale: vec3(CARD_WIDTH, CARD_HEIGHT, 1.0),
	};
}

function handCard(index: int32, shown: MeshId): NodeId3D {
	const target: RenderTarget = cardTarget(
		CARD_RED[index], CARD_GREEN[index], CARD_BLUE[index], CARD_LETTERS[index], true,
	);
	const faceTexture: TextureId = targetTexture(target, TextureAlpha.Premultiplied);
	const base: Material = Material.keyed(
		ProgramKey.of(Program.UnlitTextured).withPremultiplied(), premultipliedPass(), Phase.Alpha,
	).withShadows(ShadowCasting.On, false);
	const made: MaterialId = material({ ...base, texture: faceTexture, uniforms: unlitBlock() });
	const x: float32 = HAND_CENTER_X + ((index - 2) as float32) * HAND_SPACING;
	return place(scene.rootId(), cardAt(x, HAND_Z), shown, made);
}

// The discarded card is opaque, so its target reads as straight alpha: a dissolve key has no
// premultiplied row (PENDING: dissolve-premultiplied, docs/VOID3D.md "M44 as built").
function discardCard(shown: MeshId): NodeId3D {
	const target: RenderTarget = cardTarget(0.80, 0.25, 0.70, "X", false);
	const faceTexture: TextureId = targetTexture(target, TextureAlpha.Straight);
	const base: Material = Material.keyed(dissolveKey, twoSided(), Phase.Opaque)
		.withShadows(ShadowCasting.On, false);
	const edge: int32 = movingBase(dissolveKey) + MOVING_DISSOLVE_EDGE_COLOR;
	for (let i = 0; i < 4; i++) { dissolveValues[UNLIT_MATERIAL_COLOR + i] = 1.0; }
	dissolveValues[movingBase(dissolveKey) + MOVING_DISSOLVE_EDGE_WIDTH] = 0.125;
	dissolveValues[edge] = 1.0;
	dissolveValues[edge + 1] = 0.45;
	dissolveValues[edge + 2] = 0.05;
	dissolveValues[edge + 3] = 1.0;
	dissolveBlock = block(dissolveValues);
	const made: MaterialId = material({
		...base, texture: faceTexture, dissolveTexture: noiseRamp(), uniforms: dissolveBlock,
	});
	return place(scene.rootId(), cardAt(DISCARD_X, DISCARD_Z), shown, made);
}

// The highlight lives on layer 1 only, so the first camera never draws it; it is a translucent
// yellow slab around one card, larger than the card.
function highlight(shown: MeshId): NodeId3D {
	const base: Material = Material.ofKind(Program.UnlitTextured, MaterialKind.Alpha)
		.withShadows(ShadowCasting.Off, false);
	const made: MaterialId = material({
		...base, texture: solid(0x8026D9FF), uniforms: unlitBlock(),
	});
	const x: float32 = HAND_CENTER_X + ((HIGHLIGHTED - 2) as float32) * HAND_SPACING;
	const at: Transform3D = cardAt(x, HAND_Z);
	const node: NodeId3D = place(scene.rootId(), {
		...at,
		position: at.position + CARD_NORMAL.normalized().scaled(0.02),
		scale: vec3(CARD_WIDTH * HIGHLIGHT_SCALE, CARD_HEIGHT * HIGHLIGHT_SCALE, 1.0),
	}, shown, made);
	setLayers(scene, node, layerBit(1));
	return node;
}

// ---- Board and torches ---------------------------------------------------------------------

function board(): void {
	const base: Material = Material.keyed(
		ProgramKey.of(Program.LitTextured).withNormalMap(), RenderState.defaults(), Phase.Opaque,
	).withShadows(ShadowCasting.Off, true);
	const made: MaterialId = material({
		...base, texture: feltTile(), normalTexture: stitchNormals(), uniforms: litBlock(),
	});
	const _board: NodeId3D = place(scene.rootId(), Transform3D.identity(), boardMesh(), made);
}

function torch(x: float32, which: int32): NodeId3D {
	const wood: TextureId = solid(texelOf(70, 46, 28));
	const pole: Material = Material.ofKind(Program.LitTextured, MaterialKind.Opaque);
	const poleMaterial: MaterialId = material({ ...pole, texture: wood, uniforms: litBlock() });
	const poleAt: Transform3D = Transform3D.fromTranslation(vec3(x, 0.45, TORCH_Z));
	const _pole: NodeId3D = place(scene.rootId(), poleAt, cube(0.14, 0.9, 0.14), poleMaterial);

	const key: ProgramKey = ProgramKey.of(Program.LitTextured).withEmissive();
	let bowlValues: Vec<float32> = [4.0, 0.0, 0.0, 0.0];
	for (let i = 0; i < EMISSIVE_LENGTH; i++) { bowlValues.push(1.0); }
	const emitted: int32 = emissiveBase(key);
	bowlValues[emitted + EMISSIVE_COLOR] = 1.0;
	bowlValues[emitted + EMISSIVE_COLOR + 1] = 0.5;
	bowlValues[emitted + EMISSIVE_COLOR + 2] = 0.1;
	bowlValues[emitted + EMISSIVE_STRENGTH] = 1.5;
	const bowl: Material = Material.keyed(key, RenderState.defaults(), Phase.Opaque)
		.withShadows(ShadowCasting.Off, true);
	const bowlMaterial: MaterialId = material({
		...bowl, texture: wood, emissiveTexture: solid(0xFFFFFFFF), uniforms: block(bowlValues),
	});
	const bowlAt: Transform3D = Transform3D.fromTranslation(vec3(x, 0.96, TORCH_Z));
	const _bowl: NodeId3D = place(scene.rootId(), bowlAt, cube(0.32, 0.12, 0.32), bowlMaterial);

	const flame: LightInstance = {
		kind: LightKind.Point, color: vec3(1.0, 0.55, 0.2), radius: 3.6, power: 1.2, priority: 0,
	};
	const lightAt: Transform3D = Transform3D.fromTranslation(vec3(x, 1.3, TORCH_Z));
	torchLights.push(addLightNode(scene, scene.rootId(), lightAt, flame));

	const stream: Result<MeshId, StreamError> =
		addStreamMesh(context, flameState().maxParts);
	if (!stream.ok) { stop("a flame stream was refused"); unreachable; }
	const particles: MaterialId =
		material(Material.plain(Program.Particle, twoSided(), Phase.Opaque));
	const emitterAt: Transform3D = Transform3D.fromTranslation(vec3(x, FLAME_BASE, TORCH_Z));
	const emitter: NodeId3D = place(scene.rootId(), emitterAt, stream.value, particles);
	if (which == 0) { torchAMesh = stream.value; } else { torchBMesh = stream.value; }
	return emitter;
}

function advance(ref emitter: ParticleEmitter, node: NodeId3D): boolean {
	const world: Result<Mat4, SceneError> = scene.worldOf(node);
	if (!world.ok) { return false; }
	return updateEmitter(emitter, PARTICLE_STEP, world.value).ok;
}

function draw(
	ref emitter: ParticleEmitter,
	node: NodeId3D,
	stream: MeshId,
	instances: Span<float32>,
): boolean {
	const world: Result<Mat4, SceneError> = scene.worldOf(node);
	if (!world.ok) { return false; }
	const written: Result<int32, ParticleError> = writeInstances(emitter, world.value, instances);
	if (!written.ok) { return false; }
	return writeStream(context, stream, instances, written.value).ok;
}

function sun(): void {
	const light: LightInstance = {
		kind: LightKind.Directional, color: vec3(1.0, 0.95, 0.85), radius: 0.0, power: 1.0,
		priority: 0,
	};
	const front: Vec3 = vec3(0.0, 0.0, 0.0) - TO_LIGHT.normalized();
	const _sun: NodeId3D = addLightNode(scene, scene.rootId(), {
		...Transform3D.identity(), rotation: quatBetween(vec3(0.0, 0.0, 1.0), front),
	}, light);
	setAmbient(scene, vec3(0.3, 0.3, 0.3));
}

// ---- Cameras -------------------------------------------------------------------------------

function cameraRequest(): Camera3D {
	return {
		position: vec3(0.0, 5.0, 6.0), yaw: 0.0, pitch: 0.77, orientation: null,
		nearPlane: 0.1, farPlane: 30.0,
		projection: { kind: ProjectionKind.Perspective, fovY: 0.95 },
	};
}

// Both cameras stand at one pose, so the overlay lines up with the first view; they differ in
// the layers they draw.
function cameraNode(): NodeId3D {
	const request: Camera3D = cameraRequest();
	const at: Transform3D = {
		position: request.position, rotation: facingRotation(basisOf(request)),
		scale: vec3(1.0, 1.0, 1.0),
	};
	return addCameraNode(scene, scene.rootId(), at, request);
}

// ---- Setup ---------------------------------------------------------------------------------

export function setupCardTable(withoutFeatures: boolean): void {
	featureless = withoutFeatures;
	gfxSetup();
	setup2d();
	mainCamera = cameraNode();
	overlayCamera = cameraNode();
	setActiveCamera(scene, mainCamera);
	setCameraLayers(scene, overlayCamera, layerBit(1));
	board();
	sun();
	const shown: MeshId = cardQuad();
	for (let i = 0; i < HAND_SIZE; i++) { handNodes.push(handCard(i, shown)); }
	discardNode = discardCard(shown);
	highlightNode = highlight(shown);
	torchANode = torch(-TORCH_X, 0);
	torchBNode = torch(TORCH_X, 1);
	const style: WorldLabelStyle = {
		...WorldLabelStyle.plainStyle(LABEL_PIXELS_PER_UNIT),
		fontSize: 64.0, color: rgba(1.0, 1.0, 1.0, 1.0), anchor: ANCHOR_CENTER,
	};
	const made: Result<WorldLabel, WorldLabelError> =
		WorldLabel.create(scene, scene.rootId(), "TURN 2", style);
	if (!made.ok) { stop(`the label was refused: ${made.error.toString()}`); unreachable; }
	label = made.value;
	display.add(displaySprite);
	const _synced: int32 = syncWorld(scene);
	if (featureless) {
		setVisible(scene, made.value.node, false);
		return;
	}
	attachShadow(forward.core, shadow);
	shadow.opacity = SHADOW_OPACITY;
	for (let i = 0; i < PARTICLE_WARMUP; i++) {
		if (!advance(torchA, torchANode) || !advance(torchB, torchBNode)) {
			stop("a flame emitter refused a warm-up step");
			unreachable;
		}
	}
}

// ---- Frame ---------------------------------------------------------------------------------

// One of two orders for the swapped pair, by period: low then high, high then low.
function swapped(frame: int32): boolean {
	return (frame / SWAP_PERIOD) % 2 == 1;
}

function writeOrders(frame: int32): void {
	for (let i = 0; i < HAND_SIZE; i++) { setRenderOrder(scene, handNodes[i], i); }
	if (swapped(frame)) {
		setRenderOrder(scene, handNodes[SWAP_LOW], SWAP_HIGH);
		setRenderOrder(scene, handNodes[SWAP_HIGH], SWAP_LOW);
	}
}

// Rises to the threshold, holds, and falls back; the period is 160 frames.
export function dissolveAt(frame: int32): float32 {
	const t: int32 = frame % 160;
	if (t < DISSOLVE_HOLD_START) {
		return DISSOLVE_THRESHOLD * (t as float32) / (DISSOLVE_HOLD_START as float32);
	}
	if (t < DISSOLVE_HOLD_END) { return DISSOLVE_THRESHOLD; }
	return DISSOLVE_THRESHOLD * ((160 - t) as float32) / ((160 - DISSOLVE_HOLD_END) as float32);
}

function writeDissolve(frame: int32): boolean {
	dissolveValues[movingBase(dissolveKey) + MOVING_DISSOLVE_THRESHOLD] = dissolveAt(frame);
	return writeUniforms(context, dissolveBlock, dissolveValues).ok;
}

// The torches' light steps at ten frames a second, as a campfire's does.
function flicker(frame: int32): void {
	const step: int32 = frame / FLICKER_FRAMES;
	setLightPower(scene, torchLights[0], 1.0 + 0.1 * (((step * 7) % 5) as float32));
	setLightPower(scene, torchLights[1], 1.0 + 0.1 * (((step * 3 + 2) % 5) as float32));
}

function stepTorches(): boolean {
	return advance(torchA, torchANode) && advance(torchB, torchBNode) &&
		draw(torchA, torchANode, torchAMesh, torchAInstances) &&
		draw(torchB, torchBNode, torchBMesh, torchBInstances);
}

export function tableView(width: int32, height: int32): Result<CameraView, CameraError> {
	const request: Result<Camera3D, CameraError> = cameraViewOf(scene, mainCamera);
	if (!request.ok) { return Result.err(request.error); }
	return request.value.resolve(width, height);
}

function overlayView(width: int32, height: int32): Result<CameraView, CameraError> {
	const request: Result<Camera3D, CameraError> = cameraViewOf(scene, overlayCamera);
	if (!request.ok) { return Result.err(request.error); }
	return request.value.resolve(width, height);
}

// The overlay's target is made by the second preset's first prepare and made again when the
// window resizes; the sprite that composites it holds the target's view, so it is renewed
// whenever the target is not the one it shows.
function showOverlay(width: int32, height: int32): void {
	if (overlay.colorTarget.image != displayImage || width != displayWidth) {
		displaySprite.setTile(
			targetTile(overlay.colorTarget, width as float32, height as float32).premultiplied(),
		);
		displaySprite.setSize(width as float32, height as float32);
		displayImage = overlay.colorTarget.image;
		displayWidth = width;
	}
	display.prepare(width as float32, height as float32, 1.0);
}

export function frameCardTable(
	frame: int32,
	width: int32,
	height: int32,
): Result<int32, CardTableError> {
	if (!featureless) {
		writeOrders(frame);
		if (!writeDissolve(frame)) { return Result.err(CardTableError.Camera); }
		flicker(frame);
		if (!stepTorches()) { return Result.err(CardTableError.Particles); }
	}
	const first: Result<CameraView, CameraError> = tableView(width, height);
	if (!first.ok) { return Result.err(CardTableError.Camera); }
	const own: WorldLabel | null = label;
	if (own === null) { return Result.err(CardTableError.Label); }
	faceCamera(own, LABEL_POSITION, first.value.basis);
	const _redrawn: boolean = refreshLabel(own);
	const drawn: int32 = refresh(scene, items);
	const lit: Result<int32, LightError> = collectLights(scene, lights);
	if (!lit.ok) { return Result.err(CardTableError.Lights); }
	first.value.writeCameraBlock(cameraValues);
	const prepared: Result<int32, ForwardError> =
		prepareForward(forward, items, cameraValues, lights, width, height);
	if (!prepared.ok) { return Result.err(CardTableError.Forward); }
	if (!featureless) {
		const second: Result<CameraView, CameraError> = overlayView(width, height);
		if (!second.ok) { return Result.err(CardTableError.Camera); }
		const _overlaid: int32 = refreshFor(scene, overlayCamera, overlayItems);
		const overlit: Result<int32, LightError> =
			collectLightsFor(scene, layerBit(1), overlayLights);
		if (!overlit.ok) { return Result.err(CardTableError.Lights); }
		second.value.writeCameraBlock(overlayValues);
		const prepared2: Result<int32, ForwardError> =
			prepareForward(overlay, overlayItems, overlayValues, overlayLights, width, height);
		if (!prepared2.ok) { return Result.err(CardTableError.Overlay); }
		showOverlay(width, height);
	}
	beginScreenPass(SCREEN_CLEAR);
	drawForwardToScreen(forward);
	if (!featureless) {
		// The second preset's prepared frame is consumed here: only openScreen clears it, and
		// the composite is void2d's sprite, not the preset's own opaque copy.
		openScreen(overlay.core);
		display.drawScreen();
	}
	endPass();
	commit();
	return Result.ok(drawn);
}

// ---- Probes for the readback test ----------------------------------------------------------

export function handNode(index: int32): NodeId3D { return handNodes[index]; }
export function discardCardNode(): NodeId3D { return discardNode; }
export function ownLabel(): WorldLabel | null { return label; }
export function mainScene(): Scene3D { return scene; }

// A point on a card, in the card's own unit coordinates: x across (-0.5 left, 0.5 right) and y up
// (-0.5 at the lower edge, 0.5 at the upper one), in the world the last frame drew.
export function cardPoint(node: NodeId3D, across: float32, up: float32): Vec3 {
	const world: Result<Mat4, SceneError> = scene.worldOf(node);
	if (!world.ok) { unreachable; }
	return vec3(across, up, 0.0) * world.value;
}

// The point on the table the sun's ray from `point` reaches.
export function shadowOf(point: Vec3): Vec3 {
	const toLight: Vec3 = TO_LIGHT.normalized();
	return point - toLight.scaled(point.y / toLight.y);
}
