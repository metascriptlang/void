import { gfxSetup, fbWidth, fbHeight } from "../../src/sokol/gpu";
import { Vec3, Vec4, vec3, eulerQuat } from "../../src/math/math3d";
import { RenderState, BlendMode, Face, FilterMode, Wrap } from "../../src/gpu/state";
import { Material, Phase, UniformBlock } from "../../src/void3d/material";
import { MeshData, MeshError, Rgba, addTexturedQuad } from "../../src/void3d/meshData";
import { TextureData, TextureId, TextureUploadError } from "../../src/void3d/texture";
import {
	Program, MATERIAL_UNIFORM_SLOT, UNLIT_MATERIAL_UNIFORM_LENGTH,
	VERTEX_UNIFORM_LENGTH, LIGHT_UNIFORM_LENGTH,
} from "../../src/void3d/gpu3d";
import {
	DrawContext, DrawItem, MeshId, MaterialId, MeshUploadError, MaterialError,
	addMeshData, addMaterial, addTexture, reserveUniforms, writeUniforms,
	releaseMesh, releaseMaterial, releaseTexture, closeContext,
} from "../../src/void3d/draw";
import { UniformError } from "../../src/void3d/uniformPool";
import {
	Scene3D, Transform3D, NodeId3D, SceneError, NO_NODE_ID,
	addGroup, addMeshNode, attach, insertBefore, setLocal, setVisible,
	refresh, collectLights, closeScene,
} from "../../src/void3d/scene";
import { Camera3D, CameraView, CameraError, ProjectionKind } from "../../src/void3d/camera";
import { LowResView } from "../../src/void3d/blit";
import {
	ForwardRenderer, ForwardError, FORWARD_UNIFORM_LENGTH,
	renderFrame as renderForward, closeForward,
} from "../../src/void3d/forwardRenderer";
import {
	PixelArtRenderer, PixelArtError, PixelArtSettings, PixelArtLook, PIXEL_ART_UNIFORM_LENGTH,
	renderFrame as renderPixelArt, closePixelArt,
} from "../../src/void3d/pixelArtRenderer";
import {
	voidCaptureBackend, voidCaptureGrab, voidCapturePixel, voidCaptureSlotsDiffer,
	voidCaptureEnvInt, voidCaptureExit,
} from "../capture/capture.h";

let WIDTH: int32 = 320;
let HEIGHT: int32 = 240;
let BACKGROUND: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };
let context: DrawContext = DrawContext.withUniformCapacity(
	FORWARD_UNIFORM_LENGTH + PIXEL_ART_UNIFORM_LENGTH + UNLIT_MATERIAL_UNIFORM_LENGTH,
);
let scene: Scene3D = Scene3D.create(context);
let reference: Scene3D = Scene3D.create(context);
let forward: ForwardRenderer = madeForward();
let preset: PixelArtRenderer = madePreset();
let items: Vec<DrawItem> = [];
let cameraValues: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let baseline: Vec<int64> = new Array(WIDTH * HEIGHT);
let SCREEN: LowResView = { width: 320, height: 240, scale: 1, offsetX: 0.0, offsetY: 0.0 };
let firstParent: NodeId3D = NO_NODE_ID;
let secondParent: NodeId3D = NO_NODE_ID;
let movedGroup: NodeId3D = NO_NODE_ID;
let redNode: NodeId3D = NO_NODE_ID;
let blueNode: NodeId3D = NO_NODE_ID;
let redMesh: MeshId;
let blueMesh: MeshId;
let material: MaterialId;
let normalReference: NodeId3D = NO_NODE_ID;
let reverseReference: NodeId3D = NO_NODE_ID;
let pixelArt: boolean = false;
let matched: int32 = 0;

function fail(message: string): void {
	console.log(`FAIL reparent frame: ${message}`);
	voidCaptureExit(1);
}

function madeForward(): ForwardRenderer {
	const made: Result<ForwardRenderer, ForwardError> = ForwardRenderer.create(context, BACKGROUND);
	if (made.ok) { return made.value; }
	fail(`create forward renderer: ${made.error.toString()}`);
	unreachable;
}

function madePreset(): PixelArtRenderer {
	const settings: PixelArtSettings = {
		...PixelArtSettings.full(), lowResShortSide: HEIGHT, margin: 0, postPass: false,
	};
	const look: PixelArtLook = {
		background: BACKGROUND,
		outline: {
			depthThreshold: 0.006, normalThreshold: 0.6, depthShade: 0.55, normalShade: 1.35,
		},
		fog: { start: 1.0, end: 1.0, strength: 0.0, color: BACKGROUND }, saturation: 0.0,
	};
	const made: Result<PixelArtRenderer, PixelArtError> =
		PixelArtRenderer.create(context, settings, look);
	if (made.ok) { return made.value; }
	fail(`create pixel-art renderer: ${made.error.toString()}`);
	unreachable;
}

function pose(first: boolean): Transform3D {
	return {
		...Transform3D.identity(),
		position: first ? vec3(-0.4, 0.0, 0.0) : vec3(0.4, 0.2, 0.0),
		rotation: eulerQuat(0.0, 0.0, first ? 0.15 : 0.35),
	};
}

function meshOf(color: Rgba): MeshId {
	let data: MeshData = MeshData.withUvs();
	const added: Result<int32, MeshError> = addTexturedQuad(
		data, vec3(-0.6, -0.6, 0.0), vec3(0.6, -0.6, 0.0),
		vec3(0.6, 0.6, 0.0), vec3(-0.6, 0.6, 0.0), vec3(0.0, 0.0, 1.0), color,
	);
	if (!added.ok) { fail(`build quad: ${added.error.toString()}`); unreachable; }
	const uploaded: Result<MeshId, MeshUploadError> = addMeshData(context, data);
	if (!uploaded.ok) { fail(`upload quad: ${uploaded.error.toString()}`); unreachable; }
	return uploaded.value;
}

function materialOf(): MaterialId {
	const data: TextureData = {
		width: 1, height: 1, pixels: [0xFFFFFFFF], filter: FilterMode.Nearest, wrap: Wrap.Clamp,
	};
	const image: Result<TextureId, TextureUploadError> = addTexture(context, data);
	if (!image.ok) { fail(`upload texture: ${image.error.toString()}`); unreachable; }
	const reserved: Result<UniformBlock, UniformError> =
		reserveUniforms(context, MATERIAL_UNIFORM_SLOT, UNLIT_MATERIAL_UNIFORM_LENGTH);
	if (!reserved.ok) { fail(`reserve material range: ${reserved.error.toString()}`); unreachable; }
	const values: Vec<float32> = [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0];
	const written = writeUniforms(context, reserved.value, values);
	if (!written.ok) { fail(`write material range: ${written.error.toString()}`); unreachable; }
	const defaults: RenderState = RenderState.defaults();
	const pass: RenderState = defaults.withCulling(Face.None)
		.withDepth(false, defaults.depthTest).withBlendMode(BlendMode.Alpha);
	const added: Result<MaterialId, MaterialError> = addMaterial(context, {
		...Material.plain(Program.UnlitTextured, pass, Phase.Alpha),
		texture: image.value, uniforms: reserved.value,
	});
	if (!added.ok) { fail(`create material: ${added.error.toString()}`); unreachable; }
	const released = releaseTexture(context, image.value);
	if (!released.ok) {
		fail(`release texture caller hold: ${released.error.toString()}`);
		unreachable;
	}
	return added.value;
}

function nodeOf(owner: Scene3D, parent: NodeId3D, mesh: MeshId): NodeId3D {
	const added: Result<NodeId3D, SceneError> =
		addMeshNode(owner, parent, Transform3D.identity(), mesh, material);
	if (!added.ok) { fail(`create mesh node: ${added.error.toString()}`); unreachable; }
	return added.value;
}

function referenceGroup(reverse: boolean): NodeId3D {
	const group: NodeId3D = addGroup(reference, reference.rootId(), Transform3D.identity());
	const _first: NodeId3D = nodeOf(reference, group, reverse ? blueMesh : redMesh);
	const _second: NodeId3D = nodeOf(reference, group, reverse ? redMesh : blueMesh);
	return group;
}

export function configureReparent(throughPixelArt: boolean): void { pixelArt = throughPixelArt; }

export function initReparent(): void {
	gfxSetup();
	if (voidCaptureBackend() != 1) {
		console.log("SKIP reparent frame: this consumer requires D3D11 readback");
		voidCaptureExit(3);
	}
	if (fbWidth() != WIDTH || fbHeight() != HEIGHT) { fail("unexpected framebuffer size"); }
	redMesh = meshOf({ red: 1.0, green: 0.0, blue: 0.0, alpha: 0.5 });
	blueMesh = meshOf({ red: 0.0, green: 0.0, blue: 1.0, alpha: 0.5 });
	material = materialOf();
	firstParent = addGroup(scene, scene.rootId(), pose(true));
	secondParent = addGroup(scene, scene.rootId(), pose(false));
	movedGroup = addGroup(scene, null, Transform3D.identity());
	redNode = nodeOf(scene, movedGroup, redMesh);
	blueNode = nodeOf(scene, movedGroup, blueMesh);
	normalReference = referenceGroup(false);
	reverseReference = referenceGroup(true);
	const redReleased = releaseMesh(context, redMesh);
	const blueReleased = releaseMesh(context, blueMesh);
	const materialReleased = releaseMaterial(context, material);
	if (!redReleased.ok) {
		fail(`release red caller hold: ${redReleased.error.toString()}`); unreachable;
	}
	if (!blueReleased.ok) {
		fail(`release blue caller hold: ${blueReleased.error.toString()}`); unreachable;
	}
	if (!materialReleased.ok) {
		fail(`release material caller hold: ${materialReleased.error.toString()}`); unreachable;
	}
}

function updatePair(pair: int32): void {
	if (pair == 1) { attach(scene, firstParent, movedGroup); }
	if (pair == 2 && voidCaptureEnvInt("VOID_REPARENT_SKIP_MOVE_CONTROL", 0) == 0) {
		attach(scene, secondParent, movedGroup);
	}
	if (pair == 3 && voidCaptureEnvInt("VOID_REPARENT_SKIP_ORDER_CONTROL", 0) == 0) {
		insertBefore(scene, movedGroup, blueNode, redNode);
	}
	if (pair == 4) { insertBefore(scene, movedGroup, redNode, blueNode); }
	if (pair == 5) { attach(scene, firstParent, movedGroup); }
	if (pair == 6) { attach(scene, movedGroup, redNode); }
	if (pair == 7) { insertBefore(scene, movedGroup, redNode, redNode); }
	const first: boolean = pair == 1 || pair >= 5;
	const reverse: boolean = pair == 3 || pair >= 6;
	setVisible(reference, normalReference, pair != 0 && !reverse);
	setVisible(reference, reverseReference, pair != 0 && reverse);
	setLocal(reference, normalReference, pose(first));
	setLocal(reference, reverseReference, pose(first));
}

function lifetimePin(): void {
	const before: int32 = context.meshPinned(redMesh);
	const owner: Scene3D = Scene3D.create(context);
	const group: NodeId3D = addGroup(owner, null, Transform3D.identity());
	const _node: NodeId3D = nodeOf(owner, group, redMesh);
	if (context.meshPinned(redMesh) != before + 1) {
		fail("detached node did not retain its mesh");
	}
	closeScene(owner);
	if (context.meshPinned(redMesh) != before) { fail("detached scene close leaked a mesh pin"); }
}

function resolved(): CameraView {
	const camera: Camera3D = {
		position: vec3(0.0, 0.0, 5.0), yaw: 0.0, pitch: 0.0,
		projection: { kind: ProjectionKind.Orthographic, worldPerTexel: 0.02, snap: false },
		nearPlane: -20.0, farPlane: 20.0,
	};
	const view: Result<CameraView, CameraError> = camera.resolve(WIDTH, HEIGHT);
	if (view.ok) { return view.value; }
	fail(`resolve reparent camera: ${view.error.toString()}`);
	unreachable;
}

function orderPixel(pair: int32, view: CameraView): void {
	if (pair == 0) { return; }
	const first: boolean = pair == 1 || pair >= 5;
	const reverse: boolean = pair == 3 || pair >= 6;
	const at: Vec3 = view.project(pose(first).position, SCREEN, true);
	const pixel: int64 = voidCapturePixel(0, at.x as int32, at.y as int32);
	const red: int32 = ((pixel >> 24) & 255) as int32;
	const green: int32 = ((pixel >> 16) & 255) as int32;
	const blue: int32 = ((pixel >> 8) & 255) as int32;
	const expectedRed: int32 = reverse ? 128 : 64;
	const expectedBlue: int32 = reverse ? 64 : 128;
	if (Math.abs(red - expectedRed) > 1 || green != 0 || Math.abs(blue - expectedBlue) > 1) {
		fail(`order pixel at pair ${pair}: expected ${expectedRed},0,${expectedBlue}`);
	}
}

export function frameReparent(frameIndex: int32): void {
	if (fbWidth() != WIDTH || fbHeight() != HEIGHT) { fail("framebuffer size changed"); }
	const pair: int32 = frameIndex / 2;
	if (frameIndex < 16 && frameIndex % 2 == 0) { updatePair(pair); }
	const owner: Scene3D = frameIndex % 2 == 0 ? scene : reference;
	const drawCount: int32 = refresh(owner, items);
	if (drawCount != (frameIndex < 2 ? 0 : 2)) { fail("detached/mounted draw count is wrong"); }
	const gathered = collectLights(owner, lights);
	if (!gathered.ok) {
		fail(`collect reparent lights: ${gathered.error.toString()}`); unreachable;
	}
	const view: CameraView = resolved();
	view.writeCameraBlock(cameraValues);
	if (pixelArt) {
		if (!renderPixelArt(preset, items, cameraValues, lights, SCREEN).ok) {
			fail("pixel-art reparent frame refused");
		}
	} else if (!renderForward(forward, items, cameraValues, lights, WIDTH, HEIGHT).ok) {
		fail("forward reparent frame refused");
	}
	if (voidCaptureGrab(0) == 0 || voidCaptureGrab(1) == 0) { fail("readback failed"); }
	if (voidCaptureSlotsDiffer() != 0) { fail("two readbacks of one frame differ"); }
	if (frameIndex < 16) {
		orderPixel(pair, view);
		for (let y = 0; y < HEIGHT; y++) {
			for (let x = 0; x < WIDTH; x++) {
				const at: int32 = y * WIDTH + x;
				const pixel: int64 = voidCapturePixel(0, x, y);
				if (frameIndex % 2 == 0) { baseline[at] = pixel; }
				else if (baseline[at] != pixel) {
					fail(`moved/in-place RGBA differs at frame ${frameIndex}`);
				}
			}
		}
		if (frameIndex % 2 != 0) { matched = matched + 1; }
		lifetimePin();
	} else {
		if (matched != 8) { fail("not all eight moved/in-place pairs matched"); }
		closeScene(scene);
		closeScene(reference);
		closeForward(forward);
		closePixelArt(preset);
		closeContext(context);
		console.log(
			"PASS reparent: 8 RGBA pairs, stable equal-depth order, sole holds, detached cleanup",
		);
	}
}
