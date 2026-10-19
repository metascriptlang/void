import { gfxSetup, fbWidth, fbHeight } from "../../src/sokol/gpu";
import { Vec3, Vec4, vec3, quatBetween, identity } from "../../src/math/math3d";
import {
	Material, MaterialKind, Phase, ShadowCasting, ShadowCulling, UniformBlock, movingDefaults,
	withShadowCulling,
} from "../../src/void3d/material";
import {
	MeshData, MeshError, Rgba, LIT_VERTEX_STRIDE, addQuad, addTexturedQuad,
	addSkinAttributes, vertexCount,
} from "../../src/void3d/meshData";
import {
	Program, ProgramKey, MATERIAL_UNIFORM_SLOT, MATERIAL_UNIFORM_LENGTH, VERTEX_UNIFORM_LENGTH,
	LIGHT_UNIFORM_LENGTH, MOVING_MATERIAL_UNIFORM_LENGTH, MOVING_DISSOLVE_THRESHOLD, movingBase,
	EMISSIVE_COLOR, EMISSIVE_STRENGTH, MATERIAL_ALPHA_KILL, emissiveBase, withSkin,
} from "../../src/void3d/gpu3d";
import {
	DrawContext, DrawItem, MeshId, MaterialId, MeshUploadError, MaterialError,
	addMeshData, addMaterial, addTexture, reserveUniforms, writeUniforms, rebuildMeshes,
} from "../../src/void3d/draw";
import { TextureId, TextureUploadError, NO_TEXTURE } from "../../src/void3d/texture";
import { FilterMode, Wrap, RenderState, BlendMode } from "../../src/gpu/state";
import { contextGeneration } from "../../src/gpu/door";
import { UniformError } from "../../src/void3d/uniformPool";
import { textureViewAt } from "../../src/test/drawHelpers";
import {
	Scene3D, Transform3D, NodeId3D, SceneError, LightKind, LightInstance, LightError,
	addMeshNode, addLightNode, addGroup, addSkinMeshNode, setLocal,
	setAmbient, refresh, collectLights,
} from "../../src/void3d/scene";
import { SkinPose, bind as bindSkinPose } from "../../src/void3d/skinPose";
import { SkinGeometry, bind as bindSkinGeometry } from "../../src/void3d/skinGeometry";
import { SkinPalette, create as createPalette } from "../../src/void3d/skinPalette";
import { SkinInfluences } from "../../src/void3d/skinInfluences";
import { Camera3D, CameraView, CameraError, ProjectionKind } from "../../src/void3d/camera";
import { LowResView } from "../../src/void3d/blit";
import { Renderer, attachShadow } from "../../src/void3d/renderer";
import {
	DirShadowMap, ShadowError, DIR_SHADOW_UNIFORM_LENGTH,
} from "../../src/void3d/dirShadowMap";
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

enum Case {
	Full,
	Detached,
	CastOff,
	ReceiveOff,
	ShadowOnly,
	HalfOpacity,
	// The caster dissolves its left half (M36); the control keeps the dissolve off.
	Dissolve,
	DissolveControl,
	// A caster that faces away from the sun, so the main culling (Back) removes it from the
	// shadow pass too (Heaps' rule); 9 draws it with the shadow pass's own culling off.
	BackFace,
	BackFaceBothSides,
	// A premultiplied unlit card whose left texel is transparent, cut at alpha 0.5 (a caster that
	// cuts as its colour does); 11 is the same card with no cutout, which casts its whole quad.
	CutCard,
	CutCardWhole,
	// The dissolving caster of 6, emissive: its block is longer than the caster's, which takes
	// the head (draw.ms applyBlockHead); 13 dissolves a premultiplied card.
	DissolveEmissive,
	DissolvePremultiplied,
	SkinNarrow,
	SkinWide,
}

const WIDTH: int32 = 320;
const HEIGHT: int32 = 240;
const WORLD_PER_TEXEL: float32 = 0.02;
const GREY: Vec4 = { x: 0.2, y: 0.2, z: 0.2, w: 1.0 };
const WHITE: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };
const RED: Rgba = { red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0 };
const SCREEN: LowResView = { width: 320, height: 240, scale: 1, offsetX: 0.0, offsetY: 0.0 };
const GROUND_HALF: float32 = 3.0;
const CASTER_HALF: float32 = 0.5;
const CASTER_HEIGHT: float32 = 1.0;
const TO_LIGHT: Vec3 = { x: 1.0, y: 2.0, z: 0.0 };
const SHADOW_SIZE: int32 = 512;
const FRAMES: int32 = 3;
const CARD_RED: uint32 = 0xFF0000FF;
let pixelArt: boolean = voidCaptureEnvInt("VOID_DIR_SHADOW_PIXEL_ART", 0) != 0;
let shadowCase: Case = voidCaptureEnvInt("VOID_DIR_SHADOW_CASE", 0) as Case;
let perspective: boolean = voidCaptureEnvInt("VOID_DIR_SHADOW_PERSPECTIVE", 0) != 0;
let context: DrawContext = DrawContext.withUniformCapacity(
	FORWARD_UNIFORM_LENGTH + PIXEL_ART_UNIFORM_LENGTH + DIR_SHADOW_UNIFORM_LENGTH +
	2 * MATERIAL_UNIFORM_LENGTH + MOVING_MATERIAL_UNIFORM_LENGTH,
);
let scene: Scene3D = Scene3D.create(context);
let forward: ForwardRenderer = makeForward();
let preset: PixelArtRenderer = makePreset();
let shadow: DirShadowMap = makeShadow();
let items: Vec<DrawItem> = [];
let cameraValues: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let stage: int32 = 0;
let skinControl: int32 = voidCaptureEnvInt("VOID_DIR_SHADOW_SKIN_CONTROL", 0);
let skinBones: Vec<NodeId3D> = [];
let skinMeshes: Vec<MeshId> = [];
let skinGeometries: Vec<SkinGeometry> = [];
const SKIN_HALF: float32 = 0.25;

function fail(message: string): void {
	const presetName: string = pixelArt ? "pixel-art" : "forward";
	const name: string = shadowCase.toString();
	console.log(`FAIL dir shadow: ${presetName} ${name} stage ${stage}: ${message}`);
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
		fog: { start: 0.0, end: 1.0, strength: 0.0, color: GREY },
		saturation: 0.0,
	};
	const made: Result<PixelArtRenderer, PixelArtError> =
		PixelArtRenderer.create(context, settings, look);
	if (made.ok) { return made.value; }
	unreachable;
}

function makeShadow(): DirShadowMap {
	const made: Result<DirShadowMap, ShadowError> = DirShadowMap.create(context, SHADOW_SIZE);
	if (made.ok) { return made.value; }
	unreachable;
}

function material(
	cast: ShadowCasting,
	receive: boolean,
	culling: ShadowCulling,
	skinned: boolean = false,
): MaterialId {
	const reserved: Result<UniformBlock, UniformError> =
		reserveUniforms(context, MATERIAL_UNIFORM_SLOT, MATERIAL_UNIFORM_LENGTH);
	if (!reserved.ok) { unreachable; }
	const values: Vec<float32> = [4.0, 0.0, 0.0, 0.0];
	if (!writeUniforms(context, reserved.value, values).ok) { unreachable; }
	const base = Material.ofKind(Program.Lit, MaterialKind.Opaque).withShadows(cast, receive)
		.withShadowCulling(culling);
	const added: Result<MaterialId, MaterialError> = addMaterial(context, {
		...base, program: skinned ? base.program.withSkin() : base.program,
		uniforms: reserved.value,
	});
	if (added.ok) { return added.value; }
	fail(`a material was refused: ${added.error.toString()}`);
	unreachable;
}

function horizontal(
	half: float32,
	y: float32,
	color: Rgba,
	made: MaterialId,
	facingUp: boolean,
): void {
	let mesh: MeshData = MeshData.empty();
	const built: Result<int32, MeshError> = facingUp ?
		addQuad(
			mesh, vec3(-half, y, half), vec3(half, y, half), vec3(half, y, -half),
			vec3(-half, y, -half), vec3(0.0, 1.0, 0.0), color,
		) :
		addQuad(
			mesh, vec3(-half, y, -half), vec3(half, y, -half), vec3(half, y, half),
			vec3(-half, y, half), vec3(0.0, -1.0, 0.0), color,
		);
	if (!built.ok) { unreachable; }
	const uploaded: Result<MeshId, MeshUploadError> = addMeshData(context, mesh);
	if (!uploaded.ok) { unreachable; }
	const placed: Result<NodeId3D, SceneError> =
		addMeshNode(scene, scene.rootId(), Transform3D.identity(), uploaded.value, made);
	if (!placed.ok) { unreachable; }
}

// A LitTextured caster whose noise is low on its left half: a dissolve at 0.5 removes that half.
function dissolvingCaster(): void {
	const lit: ProgramKey = ProgramKey.of(Program.LitTextured);
	const key: ProgramKey = shadowCase == Case.DissolveEmissive ?
		lit.withDissolve().withEmissive() : shadowCase == Case.Dissolve ? lit.withDissolve() : lit;
	let values: Vec<float32> = [4.0, 0.0, 0.0, 0.0];
	if (key.dissolve) {
		values = movingDefaults(key);
		values[0] = 4.0;
		values[movingBase(key) + MOVING_DISSOLVE_THRESHOLD] = 0.5;
	}
	if (key.emissive) {
		values[emissiveBase(key) + EMISSIVE_COLOR + 2] = 1.0;
		values[emissiveBase(key) + EMISSIVE_STRENGTH] = 1.0;
	}
	const reserved: Result<UniformBlock, UniformError> =
		reserveUniforms(context, MATERIAL_UNIFORM_SLOT, values.length as int32);
	if (!reserved.ok) { unreachable; }
	if (!writeUniforms(context, reserved.value, values).ok) { unreachable; }
	const white: Result<TextureId, TextureUploadError> = addTexture(context, {
		pixels: [0xFFFFFFFF], width: 1, height: 1, filter: FilterMode.Nearest, wrap: Wrap.Clamp,
	});
	const noise: Result<TextureId, TextureUploadError> = addTexture(context, {
		pixels: [0xFF000033, 0xFF0000CC], width: 2, height: 1,
		filter: FilterMode.Nearest, wrap: Wrap.Clamp,
	});
	if (!white.ok || !noise.ok) { unreachable; }
	const base: Material = Material.ofKind(Program.LitTextured, MaterialKind.Opaque);
	const added: Result<MaterialId, MaterialError> = addMaterial(context, {
		...base,
		program: { ...key, shadowed: true },
		texture: white.value,
		dissolveTexture: key.dissolve ? noise.value : NO_TEXTURE,
		emissiveTexture: key.emissive ? white.value : NO_TEXTURE,
		uniforms: reserved.value,
	});
	if (!added.ok) { fail(`the caster was refused: ${added.error.toString()}`); }
	if (!added.ok) { return; }
	let mesh: MeshData = MeshData.withUvs();
	const half: float32 = CASTER_HALF;
	const y: float32 = CASTER_HEIGHT;
	const built: Result<int32, MeshError> = addTexturedQuad(
		mesh, vec3(-half, y, half), vec3(half, y, half), vec3(half, y, -half),
		vec3(-half, y, -half), vec3(0.0, 1.0, 0.0), RED,
	);
	if (!built.ok) { unreachable; }
	const uploaded: Result<MeshId, MeshUploadError> = addMeshData(context, mesh);
	if (!uploaded.ok) { unreachable; }
	const placed: Result<NodeId3D, SceneError> =
		addMeshNode(scene, scene.rootId(), Transform3D.identity(), uploaded.value, added.value);
	if (!placed.ok) { unreachable; }
}

// An unlit premultiplied card, whose base texture is a raw view because a context texture is
// straight and a premultiplied key refuses it (draw.ms drawItemWith); only a render target is
// registered premultiplied (M27), which this test has no void2d scene to make.
function premultipliedCard(): void {
	const premultiplied: ProgramKey = ProgramKey.of(Program.UnlitTextured).withPremultiplied();
	const key: ProgramKey = shadowCase == Case.CutCard ? premultiplied.withCutout() :
		shadowCase == Case.DissolvePremultiplied ? premultiplied.withDissolve() : premultiplied;
	const melting: boolean = key.dissolve;
	let values: Vec<float32> = new Array(MATERIAL_UNIFORM_LENGTH);
	if (melting) {
		values = movingDefaults(key);
		values[movingBase(key) + MOVING_DISSOLVE_THRESHOLD] = 0.5;
	} else {
		values = [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0];
		values[MATERIAL_ALPHA_KILL] = key.cutout ? 0.5 : 0.0;
	}
	const reserved: Result<UniformBlock, UniformError> =
		reserveUniforms(context, MATERIAL_UNIFORM_SLOT, values.length as int32);
	if (!reserved.ok) { unreachable; }
	if (!writeUniforms(context, reserved.value, values).ok) { unreachable; }
	const base: Result<TextureId, TextureUploadError> = addTexture(context, melting ? {
		pixels: [CARD_RED], width: 1, height: 1, filter: FilterMode.Nearest, wrap: Wrap.Clamp,
	} : {
		pixels: [0x00000000, CARD_RED], width: 2, height: 1,
		filter: FilterMode.Nearest, wrap: Wrap.Clamp,
	});
	const noise: Result<TextureId, TextureUploadError> = addTexture(context, {
		pixels: [0xFF000033, 0xFF0000CC], width: 2, height: 1,
		filter: FilterMode.Nearest, wrap: Wrap.Clamp,
	});
	if (!base.ok || !noise.ok) { unreachable; }
	const added: Result<MaterialId, MaterialError> = addMaterial(context, {
		...Material.keyed(
			key, RenderState.defaults().withBlendMode(BlendMode.AlphaAdd), Phase.Alpha,
		).withShadows(ShadowCasting.On, false),
		texture0: textureViewAt(context, base.value.index),
		sampler0: context.textures[base.value.index].sampler,
		dissolveTexture: melting ? noise.value : NO_TEXTURE,
		uniforms: reserved.value,
	});
	if (!added.ok) { fail(`the card was refused: ${added.error.toString()}`); }
	if (!added.ok) { return; }
	let mesh: MeshData = MeshData.withUvs();
	const half: float32 = CASTER_HALF;
	const y: float32 = CASTER_HEIGHT;
	const built: Result<int32, MeshError> = addTexturedQuad(
		mesh, vec3(-half, y, half), vec3(half, y, half), vec3(half, y, -half),
		vec3(-half, y, -half), vec3(0.0, 1.0, 0.0), WHITE,
	);
	if (!built.ok) { unreachable; }
	const uploaded: Result<MeshId, MeshUploadError> = addMeshData(context, mesh);
	if (!uploaded.ok) { unreachable; }
	const placed: Result<NodeId3D, SceneError> =
		addMeshNode(scene, scene.rootId(), Transform3D.identity(), uploaded.value, added.value);
	if (!placed.ok) { unreachable; }
}

function isSkin(): boolean {
	return shadowCase == Case.SkinNarrow || shadowCase == Case.SkinWide;
}

function skinnedCasters(): void {
	let data = MeshData.empty();
	if (shadowCase == Case.SkinWide) {
		data.vertices = new Array(65536 * LIT_VERTEX_STRIDE);
	}
	if (!addQuad(data, vec3(-SKIN_HALF, 1, SKIN_HALF), vec3(SKIN_HALF, 1, SKIN_HALF),
		vec3(SKIN_HALF, 1, -SKIN_HALF), vec3(-SKIN_HALF, 1, -SKIN_HALF),
		vec3(0, 1, 0), RED).ok) { unreachable; }
	let influences: SkinInfluences = {
		joints: new Array(data.vertexCount() * 4), weights: new Array(data.vertexCount() * 4),
	};
	for (let vertex = 0; vertex < data.vertexCount(); vertex++) {
		influences.weights[vertex * 4] = 1.0;
	}
	if (!addSkinAttributes(data, influences.joints, influences.weights).ok) { unreachable; }
	const uploaded = addMeshData(context, data);
	if (!uploaded.ok) { fail("skin mesh upload refused"); unreachable; }
	skinMeshes.push(uploaded.value);
	const made = material(ShadowCasting.On, true, ShadowCulling.Main, true);
	const palette = SkinPalette.createPalette([0]);
	if (!palette.ok) { unreachable; }
	for (const x of [-1.0, 1.0]) {
		const root = addGroup(scene, scene.rootId(), {
			...Transform3D.identity(), position: vec3(x as float32, 0, 0),
		});
		const bone = addGroup(scene, root, Transform3D.identity());
		const pose = SkinPose.bindSkinPose(scene, [0], [bone], [identity()], [palette.value]);
		if (!pose.ok) { fail("skin pose refused"); unreachable; }
		const geometry = SkinGeometry.bindSkinGeometry(data, influences, pose.value);
		if (!geometry.ok) { fail("skin geometry refused"); unreachable; }
		const added = addSkinMeshNode(scene, root, {
			...Transform3D.identity(), position: vec3(0, 100, 0),
		}, uploaded.value, made, geometry.value, 0, null);
		if (!added.ok) { fail("skin node refused"); unreachable; }
		skinBones.push(bone);
		skinGeometries.push(geometry.value);
	}
}

function reuploadSkin(): void {
	const mesh = skinMeshes[0];
	const old = context.meshes[mesh.index];
	const generation = contextGeneration();
	context.doomed.push({ buffer: old.vertexBuffer, generation: generation });
	context.doomed.push({ buffer: old.indexBuffer, generation: generation });
	context.meshes[mesh.index] = { ...old, vertexBuffer: 0, indexBuffer: 0, generation: 0 };
	if (rebuildMeshes(context) != 1) { fail("skin reupload did not rebuild one shared mesh"); }
	if (context.meshes[mesh.index].vertexBuffer == old.vertexBuffer ||
		context.meshes[mesh.index].indexBuffer == old.indexBuffer ||
		context.meshes[mesh.index].index32 != (shadowCase == Case.SkinWide)) {
		fail("skin reupload lost buffers or index width");
	}
}

function isCard(): boolean {
	return shadowCase == Case.CutCard || shadowCase == Case.CutCardWhole ||
		shadowCase == Case.DissolvePremultiplied;
}

function init(): void {
	if (voidCaptureBackend() == 0) { voidCaptureExit(3); }
	gfxSetup();
	const casting: ShadowCasting = match (shadowCase) {
		Case.Full => ShadowCasting.On,
		Case.Detached => ShadowCasting.On,
		Case.CastOff => ShadowCasting.Off,
		Case.ReceiveOff => ShadowCasting.On,
		Case.ShadowOnly => ShadowCasting.Only,
		Case.HalfOpacity => ShadowCasting.On,
		Case.Dissolve => ShadowCasting.On,
		Case.DissolveControl => ShadowCasting.On,
		Case.BackFace => ShadowCasting.On,
		Case.BackFaceBothSides => ShadowCasting.On,
		Case.CutCard => ShadowCasting.On,
		Case.CutCardWhole => ShadowCasting.On,
		Case.DissolveEmissive => ShadowCasting.On,
		Case.DissolvePremultiplied => ShadowCasting.On,
		Case.SkinNarrow => ShadowCasting.On,
		Case.SkinWide => ShadowCasting.On,
	};
	if (skinControl < 0 || skinControl > 2 || (!isSkin() && skinControl != 0)) {
		fail("unknown skin control");
	}
	const ground: MaterialId = material(isSkin() ? ShadowCasting.Off : ShadowCasting.On,
		shadowCase != Case.ReceiveOff, ShadowCulling.Main);
	horizontal(GROUND_HALF, 0.0, WHITE, ground, true);
	if (isSkin()) {
		skinnedCasters();
	} else if (shadowCase == Case.Dissolve || shadowCase == Case.DissolveControl ||
		shadowCase == Case.DissolveEmissive) {
		dissolvingCaster();
	} else if (isCard()) {
		premultipliedCard();
	} else {
		const culling: ShadowCulling =
			shadowCase == Case.BackFaceBothSides ? ShadowCulling.None : ShadowCulling.Main;
		const facingUp: boolean =
			shadowCase != Case.BackFace && shadowCase != Case.BackFaceBothSides;
		horizontal(CASTER_HALF, CASTER_HEIGHT, RED, material(casting, true, culling), facingUp);
	}
	const sun: LightInstance = {
		kind: LightKind.Directional, color: vec3(1.0, 1.0, 1.0),
		radius: 0.0, power: 1.0, priority: 0,
	};
	const front: Vec3 = vec3(0.0, 0.0, 0.0) - TO_LIGHT.normalized();
	const _sun: NodeId3D = addLightNode(scene, scene.rootId(), {
		...Transform3D.identity(), rotation: quatBetween(vec3(0.0, 0.0, 1.0), front),
	}, sun);
	setAmbient(scene, vec3(0.3, 0.3, 0.3));
	if (shadowCase == Case.HalfOpacity) { shadow.opacity = 0.5; }
	if (isSkin() && skinControl == 2) { shadow.opacity = 0.0; }
	if (shadowCase != Case.Detached) {
		const core: Renderer = pixelArt ? preset.core : forward.core;
		attachShadow(core, shadow);
	}
}

function viewOf(): CameraView {
	const camera: Camera3D = {
		position: vec3(0.0, 4.0, 4.0), yaw: 0.0, pitch: 0.785398,
		nearPlane: 0.1, farPlane: 20.0,
		projection: perspective ? { kind: ProjectionKind.Perspective, fovY: 0.6 } : {
			kind: ProjectionKind.Orthographic, worldPerTexel: WORLD_PER_TEXEL, snap: false,
		},
	};
	const view: Result<CameraView, CameraError> = camera.resolve(WIDTH, HEIGHT);
	if (view.ok) { return view.value; }
	unreachable;
}

function rgbAt(view: CameraView, point: Vec3): int64 {
	const at: Vec3 = view.project(point, SCREEN, true);
	return voidCapturePixel(0, at.x as int32, at.y as int32) >> 8;
}

function green(rgb: int64): int64 {
	return (rgb >> 8) & 0xFF;
}

// The sun moves a shadow 0.5 toward -x per unit of height: the caster's left half shades the
// ground over x in [-1, -0.5], its right half over [-0.5, 0].
function checkDissolve(view: CameraView): void {
	const gone: int64 = rgbAt(view, vec3(-0.75, 0.0, 0.0));
	const kept: int64 = rgbAt(view, vec3(-0.25, 0.0, 0.0));
	const keptTop: int64 = rgbAt(view, vec3(0.25, CASTER_HEIGHT, 0.0));
	const goneTop: int64 = rgbAt(view, vec3(-0.25, CASTER_HEIGHT, 0.0));
	console.log(`dir shadow: dissolved ${gone}, kept ${kept}, tops ${goneTop} ${keptTop}`);
	if (green(gone) < 240) { fail(`the dissolved half still cast a shadow: ${gone}`); }
	if (green(kept) > 100) { fail(`the kept half cast no shadow: ${kept}`); }
	if ((keptTop >> 16) < 200 || green(keptTop) > 60) { fail(`the kept half drew ${keptTop}`); }
	if ((goneTop >> 16) > 200 && green(goneTop) < 60) { fail("the dissolved half drew red"); }
}

function checkSkins(view: CameraView): void {
	for (let actor = 0; actor < 2; actor++) {
		const x: float32 = actor == 0 ? -1.0 : (stage == 0 ? 1.0 : 1.75);
		const under = rgbAt(view, vec3(x - 0.5, 0, 0));
		if (green(under) > 100) { fail(`no skinned shadow at actor ${actor}: ${under}`); }
		const top = rgbAt(view, vec3(x, 1, 0));
		if ((top >> 16) < 200 || green(top) > 60) {
			fail(`skinned colour did not match actor ${actor}: ${top}`);
		}
		const bounds = skinGeometries[actor].mesh.bounds;
		if (Math.abs(bounds.max.x - x - SKIN_HALF) > 0.0001 || bounds.max.y != 1.0) {
			fail(`skinned bounds did not match actor ${actor}`);
		}
	}
	if (stage > 0 && green(rgbAt(view, vec3(0.5, 0, 0))) < 240) {
		fail("stale skinned shadow remained at the old pose");
	}
	if (shadow.casterCount != 2) { fail("skin shadow lost an independent actor"); }
}

function check(view: CameraView): void {
	if (isSkin()) { checkSkins(view); return; }
	if (shadowCase == Case.Dissolve || shadowCase == Case.DissolveControl ||
		shadowCase == Case.DissolveEmissive || isCard()) {
		checkDissolve(view);
		return;
	}
	const under: int64 = rgbAt(view, vec3(-0.5, 0.0, 0.0));
	const open: int64 = rgbAt(view, vec3(1.8, 0.0, 0.0));
	const top: int64 = rgbAt(view, vec3(0.0, CASTER_HEIGHT, 0.0));
	console.log(`dir shadow: under ${under}, open ${open}, caster top ${top}`);
	if (green(open) < 240) { fail(`the open ground drew ${open}, darker than full light`); }
	const shadowed: boolean = shadowCase == Case.Full || shadowCase == Case.ShadowOnly ||
		shadowCase == Case.HalfOpacity || shadowCase == Case.Detached ||
		shadowCase == Case.BackFaceBothSides;
	if (shadowed && shadowCase != Case.HalfOpacity && green(under) > 100) {
		fail(`no shadow under the caster: ${under} against the open ground's ${open}`);
	}
	if (shadowCase == Case.HalfOpacity && (green(under) < 140 || green(under) > 230)) {
		fail(`half opacity drew ${under} under the caster, not between shadow and light`);
	}
	if (!shadowed && under != open) {
		fail(`the ground under a caster that should not shade it drew ${under}, not ${open}`);
	}
	const drawn: boolean = (top >> 16) > 200 && green(top) < 60;
	if (shadowCase == Case.BackFace || shadowCase == Case.BackFaceBothSides) { return; }
	if (shadowCase == Case.ShadowOnly && drawn) { fail("the shadow-only caster drew its colour"); }
	if (shadowCase != Case.ShadowOnly && !drawn) { fail(`the caster drew ${top}, not red`); }
}

function frame(): void {
	if (fbWidth() != WIDTH || fbHeight() != HEIGHT) { fail("the framebuffer size changed"); }
	if (isSkin() && stage == 1 && skinControl != 1) {
		setLocal(scene, skinBones[1], Transform3D.fromTranslation(vec3(0.75, 0, 0)));
	}
	if (isSkin() && stage == 2) { reuploadSkin(); }
	if (refresh(scene, items) != (isSkin() ? 3 : 2)) {
		fail("the scene lost its expected meshes");
	}
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
	console.log(`PASS dir shadow: ${shadowCase.toString()}`);
	voidCaptureExit(0);
}

voidRunConfigured(WIDTH, HEIGHT, 1, 0, init, frame);
