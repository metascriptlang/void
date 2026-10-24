import { gfxSetup, fbWidth, fbHeight } from "../../src/sokol/gpu";
import { Vec4, vec3, translation } from "../../src/math/math3d";
import { RenderState } from "../../src/gpu/state";
import { Texture, TextureError } from "../../src/gpu/texture";
import { MeshData, MeshError, Rgba, addQuad } from "../../src/void3d/meshData";
import { Material, Phase, UniformBlock, pbrBlock } from "../../src/void3d/material";
import { PbrResponseError } from "../../src/void3d/pbrResponse";
import {
	Program, ProgramKey, MATERIAL_UNIFORM_SLOT, PBR_MATERIAL_UNIFORM_LENGTH, VERTEX_UNIFORM_LENGTH,
	LIGHT_UNIFORM_LENGTH,
} from "../../src/void3d/gpu3d";
import {
	DrawContext, DrawItem, MeshId, MaterialId, MaterialError, MeshUploadError,
	addMeshData, addMaterial, reserveUniforms, writeUniforms,
} from "../../src/void3d/draw";
import { UniformError } from "../../src/void3d/uniformPool";
import { Camera3D, CameraView, CameraError, ProjectionKind } from "../../src/void3d/camera";
import { attachEnvironment, setCameraPosition } from "../../src/void3d/renderer";
import { Environment, EnvironmentError } from "../../src/void3d/environment";
import {
	ForwardRenderer, ForwardError, FORWARD_UNIFORM_LENGTH, renderFrame,
} from "../../src/void3d/forwardRenderer";
import { LitBindings, linearToSrgb, pbrEnvironmentLight, srgbToLinear } from "../../src/void3d/shader3d";
import { TextureCube, vec3f, vec4f } from "../../src/shader/std";
import {
	voidCaptureBackend, voidCaptureGrab, voidCapturePixel, voidCaptureExit,
} from "../capture/capture.h";

@include("../../src/sokol/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, sampleCount: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

const WIDTH: int32 = 160;
const HEIGHT: int32 = 120;
// The bake reads the panorama through fp16 cubes and the shader writes 8 bits.
const TOLERANCE: float32 = 3.0;
const PANORAMA_BYTE: int32 = 128;
const METALNESS: float32 = 0.0;
const ROUGHNESS: float32 = 0.5;
const GREY: Vec4 = { x: 0.5, y: 0.5, z: 0.5, w: 1.0 };
const WHITE: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };
let context: DrawContext =
	DrawContext.withUniformCapacity(FORWARD_UNIFORM_LENGTH + PBR_MATERIAL_UNIFORM_LENGTH);
let forward: ForwardRenderer = makeForward();
let items: Vec<DrawItem> = [];
let cameraValues: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let environment: Environment | null = null;
let stage: int32 = 0;

function fail(message: string): void {
	console.log(`FAIL environmentLight: stage ${stage}: ${message}`);
	voidCaptureExit(1);
}

function makeForward(): ForwardRenderer {
	const made: Result<ForwardRenderer, ForwardError> = ForwardRenderer.create(context, GREY);
	if (made.ok) { return made.value; }
	unreachable;
}

function facingQuad(): MeshId {
	let data: MeshData = MeshData.empty();
	const built: Result<int32, MeshError> = addQuad(
		data, vec3(-1.0, -1.0, 0.0), vec3(1.0, -1.0, 0.0), vec3(1.0, 1.0, 0.0),
		vec3(-1.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), WHITE,
	);
	if (!built.ok) { unreachable; }
	const uploaded: Result<MeshId, MeshUploadError> = addMeshData(context, data);
	if (uploaded.ok) { return uploaded.value; }
	unreachable;
}

function pbrMaterial(): MaterialId {
	const key: ProgramKey = ProgramKey.of(Program.Lit).withPbr();
	const values: Result<Vec<float32>, PbrResponseError> =
		pbrBlock(key, { metalness: METALNESS, roughness: ROUGHNESS, occlusion: 1.0 });
	if (!values.ok) { unreachable; }
	const reserved: Result<UniformBlock, UniformError> =
		reserveUniforms(context, MATERIAL_UNIFORM_SLOT, PBR_MATERIAL_UNIFORM_LENGTH);
	if (!reserved.ok) { unreachable; }
	if (!writeUniforms(context, reserved.value, values.value).ok) { unreachable; }
	const added: Result<MaterialId, MaterialError> = addMaterial(context, {
		...Material.keyed(key, RenderState.defaults(), Phase.Opaque),
		uniforms: reserved.value,
	});
	if (added.ok) { return added.value; }
	fail(`the pbr material was refused: ${added.error.toString()}`);
	unreachable;
}

function greyPanorama(): Texture {
	const byte: uint32 = PANORAMA_BYTE as uint32;
	const pixel: uint32 = 0xFF000000 | (byte << 16) | (byte << 8) | byte;
	let pixels: Vec<uint32> = [];
	for (let i = 0; i < 64 * 32; i++) { pixels.push(pixel); }
	const made: Result<Texture, TextureError> = Texture.fromPixels(pixels, 64, 32, true);
	if (made.ok) { return made.value; }
	fail(`the panorama was refused: ${made.error.toString()}`);
	unreachable;
}

function init(): void {
	if (voidCaptureBackend() == 0) { voidCaptureExit(3); }
	gfxSetup();
	items.push({
		mesh: facingQuad(), material: pbrMaterial(), world: translation(0.0, 0.0, 0.0), order: 0,
	});
	const made: Result<Environment, EnvironmentError> =
		Environment.fromPanorama(greyPanorama(), 16, 32);
	if (!made.ok) { fail(`fromPanorama refused: ${made.error.toString()}`); }
	if (made.ok) { environment = made.value; }
}

function viewOf(): CameraView {
	const camera: Camera3D = {
		position: vec3(0.0, 0.0, 4.0), yaw: 0.0, pitch: 0.0,
		nearPlane: 0.1, farPlane: 10.0,
		projection: { kind: ProjectionKind.Orthographic, worldPerTexel: 0.02, snap: false },
	};
	const view: Result<CameraView, CameraError> = camera.resolve(WIDTH, HEIGHT);
	if (view.ok) { return view.value; }
	unreachable;
}

function constantCube(value: float32): TextureCube {
	let texels: float32[] = [];
	for (let face = 0; face < 6; face++) {
		texels.push(value);
		texels.push(value);
		texels.push(value);
		texels.push(1.0);
	}
	return { size: 1, texels };
}

// The centre pixel as the CPU runs pbrEnvironmentLight: a constant panorama bakes to constant
// cubes, so the irradiance and every specular mip hold its linear value.
function expectedByte(power: float32): float32 {
	const value: float32 = srgbToLinear(vec3f((PANORAMA_BYTE as float32) / 255.0)).x;
	const empty: TextureCube = { size: 0, texels: [] };
	const b: LitBindings = {
		frameParams: { envParams: vec4f(power * power, 5.0, 1.0, 0.0) },
		envDiffuse: constantCube(value),
		envSpecular: constantCube(value),
		shadowMap: { width: 0, height: 0, texels: [] },
		spotShadowMap: { width: 0, height: 0, texels: [] },
		baseTexture: { width: 0, height: 0, texels: [] },
		backTexture: { width: 0, height: 0, texels: [] },
		dissolveTexture: { width: 0, height: 0, texels: [] },
		emissiveTexture: { width: 0, height: 0, texels: [] },
		normalTexture: { width: 0, height: 0, texels: [] },
		metalRoughTexture: { width: 0, height: 0, texels: [] },
		occlusionTexture: { width: 0, height: 0, texels: [] },
	};
	const light = pbrEnvironmentLight(vec3f(1.0), METALNESS, ROUGHNESS, vec3f(0.0, 0.0, 1.0),
		vec3f(0.0, 0.0, 4.0), 1.0, b);
	return linearToSrgb(light).x * 255.0;
}

function red(x: int32, y: int32): int32 {
	return (voidCapturePixel(0, x, y) & 255) as int32;
}

function frame(): void {
	if (fbWidth() != WIDTH || fbHeight() != HEIGHT) { fail("the framebuffer size changed"); }
	const env: Environment | null = environment;
	if (env === null) { unreachable; }
	const power: float32 = stage == 2 ? 2.0 : 1.0;
	env.power = power;
	attachEnvironment(forward.core, stage == 0 ? null : env);
	setCameraPosition(forward.core, vec3(0.0, 0.0, 4.0));
	viewOf().writeCameraBlock(cameraValues);
	const drawn: Result<int32, ForwardError> =
		renderFrame(forward, items, cameraValues, lights, WIDTH, HEIGHT);
	if (!drawn.ok) { fail(`forward refused: ${drawn.error.toString()}`); }
	if (voidCaptureGrab(0) == 0) { fail("readback failed"); }
	const got: int32 = red(WIDTH / 2, HEIGHT / 2);
	const want: float32 = stage == 0 ? 0.0 : expectedByte(power);
	const centre: uint32 = voidCapturePixel(0, WIDTH / 2, HEIGHT / 2) as uint32;
	const corner: uint32 = voidCapturePixel(0, 0, 0) as uint32;
	console.log(`environmentLight: stage ${stage} power ${power} centre ${got} (want ${want}) ` +
		`rgba ${centre.toString(16)}, corner ${corner.toString(16)}`);
	if (Math.abs((got as float32) - want) > TOLERANCE) {
		fail(`the centre drew ${got}, not ${want}`);
	}
	stage = stage + 1;
	if (stage < 3) { return; }
	console.log("PASS environmentLight: a pbr key is black with no environment and lit by the " +
		"baked panorama as the CPU shader predicts, scaled by the power squared");
	voidCaptureExit(0);
}

voidRunConfigured(WIDTH, HEIGHT, 1, 0, init, frame);
