import { env } from "std/process";
import { gfxSetup, fbWidth, fbHeight } from "../../src/sokol/gpu";
import { Vec3, Vec4, vec3 } from "../../src/math/math3d";
import { RenderState, BlendMode, FilterMode, Wrap } from "../../src/gpu/state";
import { RenderTarget } from "../../src/gpu/target";
import { setup2d } from "../../src/void2d/draw";
import { rgba } from "../../src/void2d/types";
import { Material, Phase, UniformBlock } from "../../src/void3d/material";
import { MeshData, MeshError, Rgba, addTexturedQuad } from "../../src/void3d/meshData";
import { TextureData, TextureId, TextureUploadError } from "../../src/void3d/texture";
import {
	Program, ProgramKey, MATERIAL_UNIFORM_SLOT, MATERIAL_UNIFORM_LENGTH,
	UNLIT_MATERIAL_UNIFORM_LENGTH, VERTEX_UNIFORM_LENGTH, LIGHT_UNIFORM_LENGTH,
} from "../../src/void3d/gpu3d";
import {
	DrawContext, DrawItem, MeshId, MaterialId, MeshUploadError, MaterialError, HandleError,
	addMeshData, addMaterial, addTexture, releaseMaterial, releaseMesh, releaseTexture,
	reserveUniforms, writeUniforms,
} from "../../src/void3d/draw";
import { UniformError } from "../../src/void3d/uniformPool";
import {
	Scene3D, Transform3D, NodeId3D, SceneError, LightError, addMeshNode, setLocal,
	refresh, collectLights, closeScene,
} from "../../src/void3d/scene";
import { ANCHOR_TOP_LEFT } from "../../src/void3d/billboard";
import {
	Camera3D, CameraBasis, CameraView, CameraError, ProjectionKind,
} from "../../src/void3d/camera";
import { LowResView } from "../../src/void3d/blit";
import {
	ForwardRenderer, ForwardError, FORWARD_UNIFORM_LENGTH, renderFrame as renderForward,
} from "../../src/void3d/forwardRenderer";
import {
	PixelArtRenderer, PixelArtError, PixelArtSettings, PixelArtLook, PIXEL_ART_UNIFORM_LENGTH,
	renderFrame as renderPixelArt,
} from "../../src/void3d/pixelArtRenderer";
import {
	WorldLabel, WorldLabelStyle, WorldLabelError, LABEL_PAD, facingRotation, faceCamera,
	setLabelText, setLabelTint, refreshLabel, closeLabel,
} from "../../src/void3d/worldLabel";
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
const WORLD_PER_TEXEL: float32 = 0.02;
const LEFT: int32 = 100;
const TOP: int32 = 80;
const LABEL_DISTANCE: float32 = 3.0;
const BACKDROP_DISTANCE: float32 = 6.0;
const BACKDROP_SIZE: float32 = 20.0;
const FONT_SIZE: float32 = 40.0;
const BACKDROP_TEXEL: uint32 = 0xFF20A040;
const BACKDROP_PIXEL: int64 = 0x40A020FF;
const BACKDROP_RED: int32 = 0x40;
const BACKDROP_GREEN: int32 = 0xA0;
const BACKDROP_BLUE: int32 = 0x20;
const SOLID: int32 = 253;
const MIN_SOLID: int32 = 30;
const SAME_SOLID: int32 = 3;
const STAGES: int32 = 4;
const BLACK: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };
const WHITE: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };
const SCREEN: LowResView = { width: 320, height: 240, scale: 1, offsetX: 0.0, offsetY: 0.0 };
const NO_NODE: NodeId3D = { scene: 0, index: 0, generation: 0 };

let context: DrawContext = DrawContext.withUniformCapacity(
	FORWARD_UNIFORM_LENGTH + PIXEL_ART_UNIFORM_LENGTH + 4 * UNLIT_MATERIAL_UNIFORM_LENGTH +
	4 * MATERIAL_UNIFORM_LENGTH,
);
let scene: Scene3D = Scene3D.create(context);
let forward: ForwardRenderer = makeForward();
let preset: PixelArtRenderer = makePreset();
let label: WorldLabel | null = null;
let backdropNode: NodeId3D = NO_NODE;
let backdropMesh: MeshId = { store: 0, index: 0, generation: 0 };
let backdropMaterial: MaterialId = { store: 0, index: 0, generation: 0 };
let backdrop: TextureId = { store: 0, index: 0, generation: 0 };
let items: Vec<DrawItem> = [];
let cameraValues: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let pixelArt: boolean = false;
let control: string = "";
let heldBasis: CameraBasis = cameraOf(0).basisOf();
let firstSolid: int32 = 0;
let firstTarget: int32 = 0;
let stage: int32 = 0;

function fail(message: string): void {
	console.log(`FAIL world label: stage ${stage}: ${message}`);
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

function cameraOf(stageNumber: int32): Camera3D {
	const turned: boolean = stageNumber >= 1;
	return {
		position: vec3(0.0, 0.0, 4.0), yaw: turned ? 0.7 : 0.0, pitch: turned ? 0.3 : 0.0,
		orientation: null, nearPlane: 0.1, farPlane: 10.0,
		projection: {
			kind: ProjectionKind.Orthographic, worldPerTexel: WORLD_PER_TEXEL, snap: false,
		},
	};
}

function viewOf(): CameraView {
	const view: Result<CameraView, CameraError> = cameraOf(stage).resolve(WIDTH, HEIGHT);
	if (view.ok) { return view.value; }
	unreachable;
}

function unlitBlock(): UniformBlock {
	const reserved: Result<UniformBlock, UniformError> =
		reserveUniforms(context, MATERIAL_UNIFORM_SLOT, UNLIT_MATERIAL_UNIFORM_LENGTH);
	if (!reserved.ok) { unreachable; }
	const values: Vec<float32> = [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0];
	if (!writeUniforms(context, reserved.value, values).ok) { unreachable; }
	return reserved.value;
}

function unitQuad(): MeshId {
	let data: MeshData = MeshData.withUvs();
	const built: Result<int32, MeshError> = addTexturedQuad(
		data, vec3(-0.5, -0.5, 0.0), vec3(0.5, -0.5, 0.0), vec3(0.5, 0.5, 0.0),
		vec3(-0.5, 0.5, 0.0), vec3(0.0, 0.0, 1.0), WHITE,
	);
	if (!built.ok) { unreachable; }
	const uploaded: Result<MeshId, MeshUploadError> = addMeshData(context, data);
	if (uploaded.ok) { return uploaded.value; }
	unreachable;
}

function theLabel(): WorldLabel {
	const own: WorldLabel | null = label;
	if (own !== null) { return own; }
	fail("the label was not made");
	unreachable;
}

function init(): void {
	if (voidCaptureBackend() == 0) { voidCaptureExit(3); }
	gfxSetup();
	setup2d();
	pixelArt = env.get("VOID_WORLD_LABEL_PRESET").equals("pixelArt");
	control = env.get("VOID_WORLD_LABEL_CONTROL");
	const data: TextureData = {
		pixels: [BACKDROP_TEXEL], width: 1, height: 1, filter: FilterMode.Nearest, wrap: Wrap.Clamp,
	};
	const uploaded: Result<TextureId, TextureUploadError> = addTexture(context, data);
	if (!uploaded.ok) { unreachable; }
	backdrop = uploaded.value;
	const wall: Result<MaterialId, MaterialError> = addMaterial(context, {
		...Material.plain(Program.UnlitTextured, RenderState.defaults(), Phase.Opaque),
		texture: backdrop, uniforms: unlitBlock(),
	});
	if (!wall.ok) { unreachable; }
	backdropMaterial = wall.value;
	backdropMesh = unitQuad();
	const placed: Result<NodeId3D, SceneError> = addMeshNode(
		scene, scene.rootId(), Transform3D.identity(), backdropMesh, backdropMaterial,
	);
	if (!placed.ok) { unreachable; }
	backdropNode = placed.value;
	const style: WorldLabelStyle = {
		...WorldLabelStyle.plainStyle(1.0 / WORLD_PER_TEXEL),
		fontSize: FONT_SIZE, color: rgba(1.0, 1.0, 1.0, 1.0),
		anchor: ANCHOR_TOP_LEFT, filter: FilterMode.Nearest,
	};
	const refused: Result<WorldLabel, WorldLabelError> = WorldLabel.create(
		scene, scene.rootId(), "T", { ...style, pixelsPerUnit: 0.0 },
	);
	if (refused.ok || refused.error != WorldLabelError.NotPositive) {
		fail("a label of no texels per unit was accepted");
	}
	const made: Result<WorldLabel, WorldLabelError> =
		WorldLabel.create(scene, scene.rootId(), "T", style);
	if (!made.ok) { fail(`the label was refused: ${made.error.toString()}`); }
	if (made.ok) { label = made.value; }
	if (control.equals("straight")) { readAsStraight(); }
}

function readAsStraight(): void {
	const own: WorldLabel = theLabel();
	const row: int32 = scene.liveRow(own.node, "control");
	const material: MaterialId = scene.meshes[scene.nodes[row].payload].material;
	const pass: RenderState = RenderState.defaults();
	const read: Material = context.materials[material.index];
	context.materials[material.index] = {
		...read,
		program: ProgramKey.of(Program.UnlitTextured),
		pass: pass.withDepth(false, pass.depthTest).withBlendMode(BlendMode.Alpha),
		texture: { store: 0, index: 0, generation: 0 },
		texture0: own.target.asTexture(),
		sampler0: context.textures[own.texture.index].sampler,
	};
}

function place(view: CameraView): void {
	const own: WorldLabel = theLabel();
	const basis: CameraBasis = control.equals("facing") ? heldBasis : view.basis;
	const right: Vec3 = view.basis.right.scaled(
		((LEFT - WIDTH / 2) as float32) * WORLD_PER_TEXEL,
	);
	const up: Vec3 = view.basis.up.scaled(((HEIGHT / 2 - TOP) as float32) * WORLD_PER_TEXEL);
	faceCamera(own, view.eye + right + up + view.basis.forward.scaled(LABEL_DISTANCE), basis);
	setLocal(scene, backdropNode, {
		position: view.eye + view.basis.forward.scaled(BACKDROP_DISTANCE),
		rotation: facingRotation(view.basis),
		scale: vec3(BACKDROP_SIZE, BACKDROP_SIZE, 1.0),
	});
}

function channel(pixel: int64, shift: int64): int32 {
	return ((pixel >> shift) & 255) as int32;
}

function render(view: CameraView): void {
	if (refresh(scene, items) != 2) { fail("the scene does not draw the backdrop and the label"); }
	const collected: Result<int32, LightError> = collectLights(scene, lights);
	if (!collected.ok) { unreachable; }
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

function checkOutside(width: int32, height: int32): void {
	const gap: int32 = LABEL_PAD + 1;
	for (let k = 0; k < 4; k++) {
		const x: int32 = k % 2 == 0 ? LEFT - gap : LEFT + width + gap;
		const y: int32 = k < 2 ? TOP - gap : TOP + height + gap;
		const pixel: int64 = voidCapturePixel(0, x, y);
		if (pixel != BACKDROP_PIXEL) {
			fail(`outside the label at ${x},${y} the backdrop became ${pixel}`);
		}
	}
	const corner: int64 = voidCapturePixel(0, LEFT + 1, TOP + 1);
	if (corner != BACKDROP_PIXEL) {
		fail(`the transparent margin changed the backdrop to ${corner}`);
	}
}

function checkInside(width: int32, height: int32, tinted: boolean): int32 {
	let solid: int32 = 0;
	let backdropOnly: int32 = 0;
	let upper: int32 = 0;
	let lower: int32 = 0;
	let brightestGreen: int32 = 0;
	const bottom: int32 = TOP + height - LABEL_PAD;
	const right: int32 = LEFT + width - LABEL_PAD;
	for (let y = TOP + LABEL_PAD; y < bottom; y++) {
		for (let x = LEFT + LABEL_PAD; x < right; x++) {
			const pixel: int64 = voidCapturePixel(0, x, y);
			const red: int32 = channel(pixel, 24);
			const green: int32 = channel(pixel, 16);
			const blue: int32 = channel(pixel, 8);
			if (red < BACKDROP_RED - 1 || green < BACKDROP_GREEN - 1 || blue < BACKDROP_BLUE - 1) {
				fail(`a dark fringe at ${x},${y}: ${pixel} under the backdrop ${BACKDROP_PIXEL}`);
				return 0;
			}
			if (pixel == BACKDROP_PIXEL) { backdropOnly = backdropOnly + 1; }
			if (green > brightestGreen) { brightestGreen = green; }
			if (red >= SOLID && green >= SOLID && blue >= SOLID) {
				solid = solid + 1;
				if (y < TOP + height / 2) { upper = upper + 1; } else { lower = lower + 1; }
			}
		}
	}
	if (tinted) {
		const expected: int32 = (255 + BACKDROP_GREEN) / 2;
		if (Math.abs(brightestGreen - expected) as int32 > 2) {
			fail(`half alpha text reached green ${brightestGreen}, expected ${expected}`);
		}
		return solid;
	}
	if (solid < MIN_SOLID) { fail(`only ${solid} text pixels, expected at least ${MIN_SOLID}`); }
	if (backdropOnly * 10 < (right - LEFT - LABEL_PAD) * (bottom - TOP - LABEL_PAD) * 3) {
		fail(`only ${backdropOnly} pixels show the backdrop between the glyphs`);
	}
	if (stage == 0 && upper * 10 < lower * 13) {
		fail(`the T is upside down: ${upper} text pixels above, ${lower} below`);
	}
	return solid;
}

function frame(): void {
	if (fbWidth() != WIDTH || fbHeight() != HEIGHT) { fail("the framebuffer size changed"); }
	const own: WorldLabel = theLabel();
	const view: CameraView = viewOf();
	if (stage == 0) { heldBasis = view.basis; }
	if (stage == 2) { setLabelText(own, "TT"); }
	if (stage == 3) { setLabelTint(own, { red: 1.0, green: 1.0, blue: 1.0, alpha: 0.5 }); }
	const redrew: boolean = refreshLabel(own);
	if (redrew != (stage == 2)) { fail(`refreshLabel answered ${redrew}`); }
	if (refreshLabel(own)) { fail("a label redrew with nothing changed"); }
	if (!context.hasTexture(own.texture)) { fail("a resize invalidated the texture"); }
	place(view);
	render(view);
	if (voidCaptureGrab(0) == 0) { fail("readback failed"); }
	const width: int32 = own.target.width;
	const height: int32 = own.target.height;
	checkOutside(width, height);
	const solid: int32 = checkInside(width, height, stage == 3);
	if (stage == 0) {
		firstSolid = solid;
		firstTarget = width;
	}
	if (stage == 1 && Math.abs(solid - firstSolid) as int32 > SAME_SOLID) {
		fail(`turning the camera changed the text from ${firstSolid} to ${solid} pixels`);
	}
	if (stage == 2 && (width <= firstTarget || solid * 10 < firstSolid * 16)) {
		fail(`a longer text drew ${solid} pixels over ${width} texels, after ${firstSolid}`);
	}
	console.log(`world label: stage ${stage} checked, ${solid} text pixels`);
	stage = stage + 1;
	if (stage < STAGES) { return; }
	closeScene(scene);
	closeLabel(own);
	if (context.hasTexture(own.texture)) { fail("closing the label kept its texture"); }
	const meshHeld: Result<int32, HandleError> = releaseMesh(context, backdropMesh);
	const wallHeld: Result<int32, HandleError> = releaseMaterial(context, backdropMaterial);
	if (!meshHeld.ok || !wallHeld.ok) { fail("the backdrop's holds were not the caller's"); }
	const _texture: Result<int32, HandleError> = releaseTexture(context, backdrop);
	console.log("PASS world label: checked text pixels, margin, orientation, premultiplied " +
		"edges, facing, redraw on text only, tint, holds");
	voidCaptureExit(0);
}

voidRunConfigured(WIDTH, HEIGHT, 1, 0, init, frame);
