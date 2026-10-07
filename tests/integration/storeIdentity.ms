import { gfxSetup } from "../../src/sokol/gpu";
import {
	PassState,
	contextGeneration,
	passState,
	liveBuffers,
	liveImages,
	liveViews,
	liveSamplers,
} from "../../src/gpu/door";
import { FilterMode, Wrap, RenderState } from "../../src/gpu/state";
import { Vec4, vec3, identity } from "../../src/math/math3d";
import {
	Program,
	VERTEX_UNIFORM_LENGTH,
	LIGHT_UNIFORM_LENGTH,
	MATERIAL_UNIFORM_SLOT,
	MATERIAL_UNIFORM_LENGTH,
} from "../../src/void3d/gpu3d";
import { Material, Phase, UniformBlock } from "../../src/void3d/material";
import { MeshData, Rgba, addVertex, addTriangle } from "../../src/void3d/meshData";
import { TextureData, TextureId } from "../../src/void3d/texture";
import { UniformPool, UniformError } from "../../src/void3d/uniformPool";
import {
	DrawContext,
	DrawItem,
	MeshId,
	MaterialId,
	MaterialError,
	HandleError,
	addMeshData,
	addMaterial,
	addTexture,
	retainMesh,
	releaseMesh,
	pinMesh,
	retainMaterial,
	releaseMaterial,
	pinMaterial,
	retainTexture,
	releaseTexture,
	reserveUniforms,
	releaseUniforms,
	writeUniforms,
	buryDoomed,
} from "../../src/void3d/draw";
import { textureViewAt } from "../../src/test/drawHelpers";
import {
	Renderer,
	RendererError,
	RENDERER_UNIFORM_LENGTH,
	beginFrame,
} from "../../src/void3d/renderer";
import {
	ForwardRenderer,
	ForwardError,
	FORWARD_UNIFORM_LENGTH,
	renderFrame as renderForward,
} from "../../src/void3d/forwardRenderer";
import {
	PixelArtRenderer,
	PixelArtSettings,
	PixelArtLook,
	PixelArtError,
	PIXEL_ART_UNIFORM_LENGTH,
	renderFrame as renderPixelArt,
} from "../../src/void3d/pixelArtRenderer";
import { LowResView } from "../../src/void3d/blit";
import {
	voidCaptureBackend,
	voidCaptureExit,
	voidCaptureGrab,
	voidCapturePixel,
} from "../capture/capture.h";

@compile("./storeIdentity.c");
@include("./storeIdentity.h");
@include("../../src/sokol/bridge.h");
extern function storeViewLive(view: uint32): int32;
extern function storeBufferLive(buffer: uint32): int32;
extern function voidRunConfigured(
	w: int32, h: int32, sampleCount: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

const POOL: int32 = RENDERER_UNIFORM_LENGTH + 32;

let failures: int32 = 0;

function check(name: string, value: boolean): void {
	if (!value) {
		failures = failures + 1;
		console.log(`FAIL store identity: ${name}`);
	}
}

function handleRefused(result: Result<int32, HandleError>, expected: HandleError): boolean {
	return !result.ok && result.error == expected;
}

function uniformRefused(result: Result<int32, UniformError>, expected: UniformError): boolean {
	return !result.ok && result.error == expected;
}

function materialRefused(
	result: Result<MaterialId, MaterialError>,
	expected: MaterialError,
): boolean {
	return !result.ok && result.error == expected;
}

function triangle(): MeshData {
	let data: MeshData = MeshData.empty();
	const up = vec3(0.0, 0.0, 1.0);
	const white: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };
	const _a = addVertex(data, vec3(0.0, 0.0, 0.0), up, white);
	const _b = addVertex(data, vec3(1.0, 0.0, 0.0), up, white);
	const _c = addVertex(data, vec3(0.0, 1.0, 0.0), up, white);
	const _t = addTriangle(data, 0, 1, 2);
	return data;
}

function texel(): TextureData {
	const pixels: Vec<uint32> = [0xff0000ff as uint32];
	return { pixels: pixels, width: 1, height: 1, filter: FilterMode.Nearest, wrap: Wrap.Clamp };
}

function meshOf(context: DrawContext): MeshId {
	const made = addMeshData(context, triangle());
	if (!made.ok) { console.log("UNEXPECTED store identity: mesh setup refused"); unreachable; }
	return made.value;
}

function materialOf(context: DrawContext): MaterialId {
	const block = reserveUniforms(context, MATERIAL_UNIFORM_SLOT, MATERIAL_UNIFORM_LENGTH);
	if (!block.ok) {
		console.log("UNEXPECTED store identity: material block refused");
		unreachable;
	}
	const lit: Material = {
		...Material.plain(Program.Lit, RenderState.defaults(), Phase.Opaque),
		uniforms: block.value,
	};
	const made = addMaterial(context, lit);
	if (!made.ok) { console.log("UNEXPECTED store identity: material setup refused"); unreachable; }
	return made.value;
}

function textureOf(context: DrawContext): TextureId {
	const made = addTexture(context, texel());
	if (!made.ok) { console.log("UNEXPECTED store identity: texture setup refused"); unreachable; }
	return made.value;
}

function blockOf(context: DrawContext): UniformBlock {
	const made = reserveUniforms(context, 2, 4);
	if (!made.ok) { console.log("UNEXPECTED store identity: uniform setup refused"); unreachable; }
	return made.value;
}

function rendererOf(context: DrawContext): Renderer {
	const made = Renderer.create(context);
	if (!made.ok) { console.log("UNEXPECTED store identity: renderer setup refused"); unreachable; }
	return made.value;
}

function twoStores(): void {
	let a: DrawContext = DrawContext.withUniformCapacity(POOL);
	let b: DrawContext = DrawContext.withUniformCapacity(POOL);
	let rendererB: Renderer = rendererOf(b);
	const _rendererA: Renderer = rendererOf(a);
	const meshA: MeshId = meshOf(a);
	const meshB: MeshId = meshOf(b);
	const materialA: MaterialId = materialOf(a);
	const materialB: MaterialId = materialOf(b);
	const textureA: TextureId = textureOf(a);
	const textureB: TextureId = textureOf(b);
	const blockA: UniformBlock = blockOf(a);
	const blockB: UniformBlock = blockOf(b);
	check("the two contexts name the same slots, so only identity tells them apart",
		meshA.index == meshB.index && materialA.index == materialB.index &&
		textureA.index == textureB.index && blockA.offset == blockB.offset);
	const bufferB: uint32 = b.meshes[meshB.index].vertexBuffer;
	const viewB: uint32 = textureViewAt(b, textureB.index);
	const viewA: uint32 = textureViewAt(a, textureA.index);

	check("a mesh of A is not one of B's", !b.hasMesh(meshA));
	check("a material of A is not one of B's", !b.hasMaterial(materialA));
	check("a texture of A is not one of B's", !b.hasTexture(textureA));
	check("a block of A is not held by B's pool", !b.uniforms.holds(blockA));

	check("B refuses to retain A's mesh",
		handleRefused(retainMesh(b, meshA), HandleError.ForeignMesh));
	check("B refuses to pin A's mesh", handleRefused(pinMesh(b, meshA), HandleError.ForeignMesh));
	check("B refuses to release A's mesh",
		handleRefused(releaseMesh(b, meshA), HandleError.ForeignMesh));
	check("B refuses to retain A's material",
		handleRefused(retainMaterial(b, materialA), HandleError.ForeignMaterial));
	check("B refuses to pin A's material",
		handleRefused(pinMaterial(b, materialA), HandleError.ForeignMaterial));
	check("B refuses to release A's material",
		handleRefused(releaseMaterial(b, materialA), HandleError.ForeignMaterial));
	check("B refuses to retain A's texture",
		handleRefused(retainTexture(b, textureA), HandleError.ForeignTexture));
	check("B refuses to release A's texture",
		handleRefused(releaseTexture(b, textureA), HandleError.ForeignTexture));
	const values: Vec<float32> = [1.0, 2.0, 3.0, 4.0];
	check("B refuses to write A's block",
		uniformRefused(writeUniforms(b, blockA, values), UniformError.Foreign));
	check("B refuses to release A's block",
		uniformRefused(releaseUniforms(b, blockA), UniformError.Foreign));
	const textured: Material = {
		...Material.plain(Program.LitTextured, RenderState.defaults(), Phase.Opaque),
		texture: textureA,
	};
	check("B refuses a material naming A's texture",
		materialRefused(addMaterial(b, textured), MaterialError.ForeignTexture));
	const blocked: Material = {
		...Material.plain(Program.Lit, RenderState.defaults(), Phase.Opaque),
		uniforms: blockA,
	};
	check("B refuses a material taking A's block",
		materialRefused(addMaterial(b, blocked), MaterialError.ForeignUniforms));

	check("B's own resources are untouched", b.hasMesh(meshB) && b.hasMaterial(materialB) &&
		b.hasTexture(textureB) && b.uniforms.holds(blockB));
	check("A's resources are untouched", a.hasMesh(meshA) && a.hasMaterial(materialA) &&
		a.hasTexture(textureA) && a.uniforms.holds(blockA));
	check("B buries nothing", buryDoomed(b, contextGeneration()) == 0);
	check("B's buffer and view are live",
		storeBufferLive(bufferB) == 1 && storeViewLive(viewB) == 1);
	check("A's view is live", storeViewLive(viewA) == 1);

	let camera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
	for (let i = 0; i < VERTEX_UNIFORM_LENGTH; i++) { camera[i] = 0.0; }
	let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
	for (let i = 0; i < LIGHT_UNIFORM_LENGTH; i++) { lights[i] = 0.0; }
	const own: Vec<DrawItem> = [{ mesh: meshB, material: materialB, world: identity() }];
	const ownFrame: Result<boolean, RendererError> =
		beginFrame(rendererB, own, camera, lights);
	if (!ownFrame.ok) { console.log(`store identity: own frame ${ownFrame.error.toString()}`); }
	check("B draws its own item", ownFrame.ok);
	const foreign: Vec<DrawItem> = [{ mesh: meshA, material: materialA, world: identity() }];
	const foreignFrame: Result<boolean, RendererError> =
		beginFrame(rendererB, foreign, camera, lights);
	check("B refuses to draw A's item by name",
		!foreignFrame.ok && foreignFrame.error == RendererError.ForeignMesh);
	const crossed: Vec<DrawItem> = [{ mesh: meshB, material: materialA, world: identity() }];
	const crossedFrame: Result<boolean, RendererError> =
		beginFrame(rendererB, crossed, camera, lights);
	check("B refuses A's material on its own mesh by name",
		!crossedFrame.ok && crossedFrame.error == RendererError.ForeignMaterial);
}

function aliases(): void {
	let a: DrawContext = DrawContext.withUniformCapacity(POOL);
	const texture: TextureId = textureOf(a);
	const material: MaterialId = materialOf(a);
	const view: uint32 = textureViewAt(a, texture.index);
	let alias: DrawContext = a;
	check("the alias releases the texture", releaseTexture(alias, texture).ok);
	check("the context sees the alias's release", !a.hasTexture(texture));
	check("the release is buried once", buryDoomed(a, contextGeneration()) == 1 &&
		buryDoomed(alias, contextGeneration()) == 0);
	check("the texture's view is destroyed", storeViewLive(view) == 0);
	const mesh: MeshId = meshOf(a);
	const buffer: uint32 = a.meshes[mesh.index].vertexBuffer;
	check("the alias releases the mesh", releaseMesh(alias, mesh).ok && !a.hasMesh(mesh));
	check("the mesh's two buffers are buried once", buryDoomed(a, contextGeneration()) == 2 &&
		buryDoomed(alias, contextGeneration()) == 0 && storeBufferLive(buffer) == 0);
	check("a second release through the context is refused",
		handleRefused(releaseTexture(a, texture), HandleError.StaleTexture));
	check("the alias releases the material", releaseMaterial(alias, material).ok);
	check("the context sees the material gone", !a.hasMaterial(material));
	let pool: UniformPool = a.uniforms;
	const block = reserveUniforms(a, 3, 8);
	check("a block reserved by the context", block.ok);
	if (block.ok) {
		check("the pool's alias holds it", pool.holds(block.value));
	}
}

function reuse(): void {
	let a: DrawContext = DrawContext.withUniformCapacity(POOL);
	const first: MaterialId = materialOf(a);
	check("the first material goes", releaseMaterial(a, first).ok);
	const second: MaterialId = materialOf(a);
	check("the slot is reused", second.index == first.index);
	check("the old id names nothing", !a.hasMaterial(first) && a.hasMaterial(second));
	check("the old id is refused",
		handleRefused(releaseMaterial(a, first), HandleError.StaleMaterial) &&
		a.hasMaterial(second));
}

const SIDE: int32 = 32;
const BLACK: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };
const GREEN: Vec4 = { x: 0.0, y: 1.0, z: 0.0, w: 1.0 };
const VIEW: LowResView = { width: SIDE, height: SIDE, scale: 1, offsetX: 0.0, offsetY: 0.0 };
const NO_ITEMS: Vec<DrawItem> = [];

let presetCamera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let presetLights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let forwardContext: DrawContext =
	DrawContext.withUniformCapacity(FORWARD_UNIFORM_LENGTH + MATERIAL_UNIFORM_LENGTH);
let pixelContext: DrawContext =
	DrawContext.withUniformCapacity(PIXEL_ART_UNIFORM_LENGTH + MATERIAL_UNIFORM_LENGTH);
let survivorContext: DrawContext = DrawContext.withUniformCapacity(FORWARD_UNIFORM_LENGTH);
let forward: ForwardRenderer = forwardOf(forwardContext, BLACK);
let survivor: ForwardRenderer = forwardOf(survivorContext, GREEN);
let pixelArt: PixelArtRenderer = pixelArtOf(pixelContext);
let frames: int32 = 0;

function forwardOf(context: DrawContext, background: Vec4): ForwardRenderer {
	const made = ForwardRenderer.create(context, background);
	if (!made.ok) { console.log("UNEXPECTED store identity: forward preset refused"); unreachable; }
	return made.value;
}

function pixelArtOf(context: DrawContext): PixelArtRenderer {
	const look: PixelArtLook = {
		background: BLACK,
		outline: {
			depthThreshold: 0.006,
			normalThreshold: 0.6,
			depthShade: 0.55,
			normalShade: 1.35,
		},
		fog: { start: 0.5, end: 0.8, strength: 0.0, color: BLACK },
		saturation: 0.0,
	};
	const made = PixelArtRenderer.create(context, PixelArtSettings.full(), look);
	if (!made.ok) {
		console.log("UNEXPECTED store identity: pixel-art preset refused");
		unreachable;
	}
	return made.value;
}

function spareOf(context: DrawContext): UniformBlock {
	const made = reserveUniforms(context, MATERIAL_UNIFORM_SLOT, MATERIAL_UNIFORM_LENGTH);
	if (!made.ok) { console.log("UNEXPECTED store identity: spare block refused"); unreachable; }
	return made.value;
}

function gpuObjects(context: DrawContext): int32 {
	return liveBuffers() + liveImages() + liveViews() + liveSamplers() +
		(context.pipelines.entries.length as int32);
}

function forwardReplaced(): void {
	const spare: UniformBlock = spareOf(forwardContext);
	const copy: int32 = forward.copyMaterial.index;
	const own: UniformBlock = forwardContext.materials[copy].uniforms;
	const objects: int32 = gpuObjects(forwardContext);
	const generation: int32 = forward.core.generation;
	forwardContext.materials[copy].uniforms = spare;
	const refused: Result<int32, ForwardError> = renderForward(
		forward, NO_ITEMS, presetCamera, presetLights, SIDE, SIDE,
	);
	check("the forward preset refuses its replaced copy block before any pass",
		!refused.ok && refused.error == ForwardError.UniformsReplaced);
	check("no pass is open after the forward refusal", passState() == PassState.None);
	check("the forward refusal made no GPU object", gpuObjects(forwardContext) == objects);
	check("the forward core is untouched",
		forward.core.generation == generation && !forward.core.prepared);
	forwardContext.materials[copy].uniforms = own;
}

function pixelArtReplaced(post: boolean): void {
	const spare: UniformBlock = spareOf(pixelContext);
	const screen: int32 = post ? pixelArt.postMaterial.index : pixelArt.blitMaterial.index;
	const own: UniformBlock = pixelContext.materials[screen].uniforms;
	const objects: int32 = gpuObjects(pixelContext);
	const generation: int32 = pixelArt.core.generation;
	pixelContext.materials[screen].uniforms = spare;
	const refused: Result<int32, PixelArtError> = renderPixelArt(
		pixelArt, NO_ITEMS, presetCamera, presetLights, VIEW,
	);
	const which: string = post ? "post" : "blit";
	check(`the pixel-art preset refuses its replaced ${which} block before any pass`,
		!refused.ok && refused.error == PixelArtError.UniformsReplaced);
	check(`no pass is open after the ${which} refusal`, passState() == PassState.None);
	check(`the ${which} refusal made no GPU object`, gpuObjects(pixelContext) == objects);
	check(`the pixel-art core is untouched after the ${which} refusal`,
		pixelArt.core.generation == generation && !pixelArt.core.prepared);
	pixelContext.materials[screen].uniforms = own;
	if (!releaseUniforms(pixelContext, spare).ok) { unreachable; }
}

function init(): void {
	gfxSetup();
	twoStores();
	aliases();
	reuse();
}

function frame(): void {
	if (frames == 0) {
		const drawn = renderForward(
			forward, NO_ITEMS, presetCamera, presetLights, SIDE, SIDE,
		);
		check("the forward preset draws a good frame first", drawn.ok);
	} else if (frames == 1) {
		const drawn = renderPixelArt(
			pixelArt, NO_ITEMS, presetCamera, presetLights, VIEW,
		);
		check("the pixel-art preset draws a good frame first", drawn.ok);
	} else if (frames == 2) {
		forwardReplaced();
		pixelArtReplaced(true);
		pixelArtReplaced(false);
		const drawn = renderForward(
			survivor, NO_ITEMS, presetCamera, presetLights, SIDE, SIDE,
		);
		check("a surviving context draws in the same frame", drawn.ok);
		check("the survivor's frame reads back", voidCaptureGrab(0) == 1);
		const pixel: int64 = voidCapturePixel(0, SIDE / 2, SIDE / 2);
		check("the survivor's frame is its own background", ((pixel >> 8) & 0xFFFFFF) == 0x00FF00);
		if (failures == 0) {
			console.log(
				"PASS store identity: two contexts, an alias, reuse; " +
				"meshes, materials, textures, blocks; replaced screen blocks refused before a pass",
			);
			voidCaptureExit(0);
		}
		voidCaptureExit(1);
	}
	frames = frames + 1;
}

if (voidCaptureBackend() == 0) { voidCaptureExit(3); }
voidRunConfigured(128, 96, 1, 0, init, frame);
