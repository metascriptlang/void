import { gfxSetup, fbWidth, fbHeight } from "../../src/sokol/gpu";
import { Vec3, Vec4, vec3, srgbToLinear, linearToSrgb } from "../../src/math/math3d";
import { RenderState, BlendMode, FilterMode, Wrap } from "../../src/gpu/state";
import { PipelineCache, declaresBlock } from "../../src/gpu/pipeline";
import { Material, Phase, UniformBlock } from "../../src/void3d/material";
import { MeshData, MeshError, Rgba, addTexturedQuad } from "../../src/void3d/meshData";
import { TextureData, TextureId, TextureUploadError } from "../../src/void3d/texture";
import {
	Program, MATERIAL_UNIFORM_SLOT, MATERIAL_UNIFORM_LENGTH, UNLIT_MATERIAL_UNIFORM_LENGTH,
	UNLIT_MATERIAL_COLOR,
	VERTEX_UNIFORM_LENGTH, LIGHT_UNIFORM_LENGTH, LIGHT_UNIFORM_SLOT, doorProgram,
	ProgramKey,
	Preset,
} from "../../src/void3d/gpu3d";
import {
	DrawContext, DrawItem, MeshId, MaterialId, MeshUploadError, MaterialError,
	addMeshData, addMaterial, addTexture, reserveUniforms, writeUniforms,
} from "../../src/void3d/draw";
import { UniformError } from "../../src/void3d/uniformPool";
import {
	Scene3D, Transform3D, NodeId3D, SceneError, LightKind, LightInstance, LightError, NO_NODE_ID,
	addMeshNode, addLightNode, setAmbient, setLightPower, refresh, collectLights,
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
	voidCaptureBackend, voidCaptureGrab, voidCapturePixel, voidCaptureSlotsDiffer,
	voidCaptureEnvInt, voidCaptureExit,
} from "../capture/capture.h";

let WIDTH: int32 = 320;
let HEIGHT: int32 = 240;
let HALF: float32 = 0.6;
let WORLD_PER_TEXEL: float32 = 0.02;
let REGION_SIDE: int32 = 64;
let BACKGROUND: Vec4 = { x: 0.1, y: 0.15, z: 0.2, w: 1.0 };
let WHITE: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };
let VERTEX_TINT: Rgba = { red: 0.6, green: 0.8, blue: 0.4, alpha: 0.75 };
let MATERIAL_TINT: Vec4 = { x: 0.9, y: 0.7, z: 0.3, w: 0.5 };
let TEXELS: Vec<uint32> = [0xFF408080, 0xFF80C040, 0x80C040A0, 0xFF2080C0];
let SCREEN: LowResView = { width: 320, height: 240, scale: 1, offsetX: 0.0, offsetY: 0.0 };
let context: DrawContext = DrawContext.withUniformCapacity(
	FORWARD_UNIFORM_LENGTH + PIXEL_ART_UNIFORM_LENGTH + 2 * UNLIT_MATERIAL_UNIFORM_LENGTH +
	MATERIAL_UNIFORM_LENGTH,
);
let scene: Scene3D = Scene3D.create(context);
let forward: ForwardRenderer = makeForward();
let preset: PixelArtRenderer = makePreset();
let items: Vec<DrawItem> = [];
let cameraValues: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let baseline: Vec<int64> = new Array(2 * REGION_SIDE * REGION_SIDE);
let positions: Vec<float32> = [-2.0, 0.0, 2.0];
let TEXEL_SHIFTS: Vec<uint32> = [0, 8, 16];
let PIXEL_SHIFTS: Vec<int64> = [24, 16, 8];
let VERTEX_COMPONENTS: Vec<float32> = [VERTEX_TINT.red, VERTEX_TINT.green, VERTEX_TINT.blue];
let MATERIAL_COMPONENTS: Vec<float32> = [MATERIAL_TINT.x, MATERIAL_TINT.y, MATERIAL_TINT.z];
let BACKGROUND_COMPONENTS: Vec<float32> = [BACKGROUND.x, BACKGROUND.y, BACKGROUND.z];
let CORNERS: Vec<Vec3> = [
	vec3(-0.3, 0.3, 0.0), vec3(0.3, 0.3, 0.0),
	vec3(-0.3, -0.3, 0.0), vec3(0.3, -0.3, 0.0),
];
let expectedPlain: Vec<int32> = new Array(12);
let expectedTinted: Vec<int32> = new Array(12);
let pixelArt: boolean = false;
let sun: NodeId3D = NO_NODE_ID;

function fail(message: string): void {
	console.log(`FAIL unlit frame: ${message}`);
	voidCaptureExit(1);
}

function makeForward(): ForwardRenderer {
	const made: Result<ForwardRenderer, ForwardError> = ForwardRenderer.create(context, BACKGROUND);
	if (made.ok) { return made.value; }
	unreachable;
}

function makePreset(): PixelArtRenderer {
	const settings: PixelArtSettings = {
		...PixelArtSettings.full(), lowResShortSide: HEIGHT, postPass: false,
	};
	const look: PixelArtLook = {
		background: BACKGROUND,
		outline: { depthThreshold: 0.006, normalThreshold: 0.6, depthShade: 0.55, normalShade: 1.35 },
		fog: { start: 1.0, end: 1.0, strength: 0.0, color: BACKGROUND },
		saturation: 0.0,
	};
	const made: Result<PixelArtRenderer, PixelArtError> =
		PixelArtRenderer.create(context, settings, look);
	if (made.ok) { return made.value; }
	unreachable;
}

export function configureUnlit(throughPixelArt: boolean): void {
	pixelArt = throughPixelArt;
}

function madeMaterial(image: TextureId, lit: boolean, tinted: boolean): MaterialId {
	const program: Program = lit ? Program.LitTextured : Program.UnlitTextured;
	const length: int32 = lit ? MATERIAL_UNIFORM_LENGTH : UNLIT_MATERIAL_UNIFORM_LENGTH;
	const reserved: Result<UniformBlock, UniformError> =
		reserveUniforms(context, MATERIAL_UNIFORM_SLOT, length);
	if (!reserved.ok) { unreachable; }
	let values: Vec<float32> = [4.0, 0.0, 0.0, 0.0];
	if (!lit) {
		values = [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0];
		if (tinted) {
			values[UNLIT_MATERIAL_COLOR] = MATERIAL_TINT.x;
			values[UNLIT_MATERIAL_COLOR + 1] = MATERIAL_TINT.y;
			values[UNLIT_MATERIAL_COLOR + 2] = MATERIAL_TINT.z;
			values[UNLIT_MATERIAL_COLOR + 3] = MATERIAL_TINT.w;
		}
	}
	if (!writeUniforms(context, reserved.value, values).ok) { unreachable; }
	let pass: RenderState = RenderState.defaults();
	if (tinted) {
		pass = pass.withDepth(false, pass.depthTest).withBlendMode(BlendMode.Alpha);
	}
	const added: Result<MaterialId, MaterialError> = addMaterial(context, {
		...Material.plain(program, pass, tinted ? Phase.Alpha : Phase.Opaque),
		texture: image, uniforms: reserved.value,
	});
	if (added.ok) { return added.value; }
	unreachable;
}

export function initUnlit(): void {
	if (voidCaptureBackend() != 1) {
		console.log("SKIP unlit frame: this consumer requires D3D11 readback");
		voidCaptureExit(3);
	}
	gfxSetup();
	for (let texel = 0; texel < 4; texel++) {
		for (let component = 0; component < 3; component++) {
			const offset: int32 = texel * 3 + component;
			expectedPlain[offset] = expectedChannel(TEXELS[texel], component, false);
			expectedTinted[offset] = expectedChannel(TEXELS[texel], component, true);
		}
	}
	const data: TextureData = {
		pixels: TEXELS, width: 2, height: 2, filter: FilterMode.Nearest, wrap: Wrap.Clamp,
	};
	const uploaded: Result<TextureId, TextureUploadError> = addTexture(context, data);
	if (!uploaded.ok) { unreachable; }
	for (let i = 0; i < 3; i++) {
		const tinted: boolean = i == 1;
		let mesh: MeshData = MeshData.withUvs();
		const built: Result<int32, MeshError> = addTexturedQuad(
			mesh, vec3(-HALF, -HALF, 0.0), vec3(HALF, -HALF, 0.0),
			vec3(HALF, HALF, 0.0), vec3(-HALF, HALF, 0.0), vec3(0.0, 0.0, 1.0),
			tinted ? VERTEX_TINT : WHITE,
		);
		if (!built.ok) { unreachable; }
		const uploadedMesh: Result<MeshId, MeshUploadError> = addMeshData(context, mesh);
		if (!uploadedMesh.ok) { unreachable; }
		const lit: boolean = i == 2 ||
			(i == 0 && voidCaptureEnvInt("VOID_UNLIT_LIT_CONTROL", 0) != 0);
		const material: MaterialId = madeMaterial(uploaded.value, lit, tinted);
		const placed: Result<NodeId3D, SceneError> = addMeshNode(
			scene, scene.rootId(), Transform3D.fromTranslation(vec3(positions[i], 0.0, 0.0)),
			uploadedMesh.value, material,
		);
		if (!placed.ok) { unreachable; }
	}
	const light: LightInstance = {
		kind: LightKind.Directional, color: vec3(1.0, 1.0, 1.0),
		radius: 0.0, power: 0.0, priority: 0,
	};
	sun = addLightNode(scene, scene.rootId(), {
		...Transform3D.identity(), rotation: { x: 0.0, y: 1.0, z: 0.0, w: 0.0 },
	}, light);
	setAmbient(scene, vec3(0.0, 0.0, 0.0));
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

function channel(pixel: int64, shift: int64): int32 {
	return ((pixel >> shift) & 255) as int32;
}

function expectedChannel(texel: uint32, channelIndex: int32, tinted: boolean): int32 {
	const raw: float32 = (((texel >> TEXEL_SHIFTS[channelIndex]) & 255) as float32) / 255.0;
	if (!tinted) { return Math.round(raw * 255.0) as int32; }
	const source: float32 = linearToSrgb(
		srgbToLinear(raw) * srgbToLinear(VERTEX_COMPONENTS[channelIndex]) *
		srgbToLinear(MATERIAL_COMPONENTS[channelIndex]),
	);
	const alpha: float32 = (((texel >> 24) & 255) as float32) / 255.0 *
		VERTEX_TINT.alpha * MATERIAL_TINT.w;
	const destination: float32 = Math.round(BACKGROUND_COMPONENTS[channelIndex] * 255.0) as float32;
	return Math.round(source * 255.0 * alpha + destination * (1.0 - alpha)) as int32;
}

function checkPixels(view: CameraView, lit: boolean): void {
	for (let quad = 0; quad < 3; quad++) {
		for (let corner = 0; corner < 4; corner++) {
			const point: Vec3 = CORNERS[corner] + vec3(positions[quad], 0.0, 0.0);
			const at: Vec3 = view.project(point, SCREEN, true);
			const pixel: int64 = voidCapturePixel(0, at.x as int32, at.y as int32);
			for (let component = 0; component < 3; component++) {
				const offset: int32 = corner * 3 + component;
				const expected: int32 = quad == 2 && !lit
					? 0 : quad == 1 ? expectedTinted[offset] : expectedPlain[offset];
				if (Math.abs(channel(pixel, PIXEL_SHIFTS[component]) - expected) > 1) {
					fail(`quad ${quad} texel ${corner} channel ${component} is not ${expected}`);
				}
			}
		}
	}
}

function holdRegions(view: CameraView, frameIndex: int32): void {
	for (let quad = 0; quad < 2; quad++) {
		const at: Vec3 = view.project(vec3(positions[quad] - HALF, HALF, 0.0), SCREEN, true);
		const left: int32 = (Math.floor(at.x) as int32) - 2;
		const top: int32 = (Math.floor(at.y) as int32) - 2;
		for (let y = 0; y < REGION_SIDE; y++) {
			for (let x = 0; x < REGION_SIDE; x++) {
				const pixel: int64 = voidCapturePixel(0, left + x, top + y);
				const offset: int32 = quad * REGION_SIDE * REGION_SIDE + y * REGION_SIDE + x;
				if (frameIndex == 1) { baseline[offset] = pixel; }
				else if (baseline[offset] != pixel) { fail("an unlit region changed with the lights"); }
			}
		}
	}
}

export function frameUnlit(frameIndex: int32): void {
	if (fbWidth() != WIDTH || fbHeight() != HEIGHT) { fail("the framebuffer size changed"); }
	const lit: boolean = (frameIndex >= 6 && frameIndex < 11) || frameIndex >= 16;
	setLightPower(scene, sun, lit ? 1.0 : 0.0);
	if (refresh(scene, items) != 3) { fail("the scene lost a quad"); }
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
	if (frameIndex == 1 || frameIndex == 6 || frameIndex == 11 || frameIndex == 16) {
		if (voidCaptureGrab(0) == 0 || voidCaptureGrab(1) == 0) { fail("readback failed"); }
		if (voidCaptureSlotsDiffer() != 0) { fail("two readbacks of one frame differ"); }
		checkPixels(view, lit);
		holdRegions(view, frameIndex);
		const drawnIn: Preset = pixelArt ? Preset.PixelArt : Preset.Core;
		const program: ProgramKey = ProgramKey.of(Program.UnlitTextured).withPreset(drawnIn);
		const cache: PipelineCache =
			pixelArt ? preset.core.context.pipelines : forward.core.context.pipelines;
		if (cache.declaresBlock(doorProgram(program), LIGHT_UNIFORM_SLOT)) {
			fail("the unlit pipeline declares a light slot");
		}
		console.log(`unlit frame: frame ${frameIndex} checked`);
	}
	if (frameIndex == 16) {
		console.log(
			"PASS unlit frame: light-independent RGBA, material/vertex/texel product, lit control",
		);
	}
}
