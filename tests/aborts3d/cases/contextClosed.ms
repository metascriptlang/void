// expect addMeshData: void3d: addMeshData on a draw context that was closed
// expect addStreamMesh: void3d: addStreamMesh on a draw context that was closed
// expect writeStream: void3d: writeStream on a draw context that was closed
// expect rebuildMeshes: void3d: rebuildMeshes on a draw context that was closed
// expect retainMesh: void3d: retainMesh on a draw context that was closed
// expect releaseMesh: void3d: releaseMesh on a draw context that was closed
// expect pinMesh: void3d: pinMesh on a draw context that was closed
// expect unpinMesh: void3d: unpinMesh on a draw context that was closed
// expect tallyMeshPin: void3d: tallyMeshPin on a draw context that was closed
// expect clearMeshTally: void3d: clearMeshTally on a draw context that was closed
// expect addMaterial: void3d: addMaterial on a draw context that was closed
// expect retainMaterial: void3d: retainMaterial on a draw context that was closed
// expect releaseMaterial: void3d: releaseMaterial on a draw context that was closed
// expect pinMaterial: void3d: pinMaterial on a draw context that was closed
// expect unpinMaterial: void3d: unpinMaterial on a draw context that was closed
// expect tallyMaterialPin: void3d: tallyMaterialPin on a draw context that was closed
// expect clearMaterialTally: void3d: clearMaterialTally on a draw context that was closed
// expect addTexture: void3d: addTexture on a draw context that was closed
// expect retainTexture: void3d: retainTexture on a draw context that was closed
// expect releaseTexture: void3d: releaseTexture on a draw context that was closed
// expect rebuildTextures: void3d: rebuildTextures on a draw context that was closed
// expect buryDoomed: void3d: buryDoomed on a draw context that was closed
// expect reserveUniforms: void3d: reserveUniforms on a draw context that was closed
// expect releaseUniforms: void3d: releaseUniforms on a draw context that was closed
// expect writeUniforms: void3d: writeUniforms on a draw context that was closed
// expect drawItem: void3d: drawItem on a draw context that was closed
// expect closeContext: void3d: closeContext on a draw context that was closed
// expect forMeshes: void3d: forMeshes on a draw context that was closed
// expect addGltfAssets: void3d: addGltfAssets on a draw context that was closed
// expect rendererCreate: void3d: Renderer.createDrawing on a draw context that was closed
// expect forwardCreate: void3d: ForwardRenderer.create on a draw context that was closed
// expect pixelArtCreate: void3d: PixelArtRenderer.create on a draw context that was closed
import { argv } from "std/process";
import { Vec4, identity } from "../../../src/math/math3d";
import { RenderState } from "../../../src/gpu/state";
import { SWAPCHAIN_LAYOUT } from "../../../src/gpu/target";
import { Program, ProgramKey, Preset } from "../../../src/void3d/gpu3d";
import { Material, Phase, NO_UNIFORMS, UniformBlock } from "../../../src/void3d/material";
import { MeshData } from "../../../src/void3d/meshData";
import {
	TextureData,
	TextureId,
	TextureUploadError,
	NO_TEXTURE,
} from "../../../src/void3d/texture";
import { UniformError } from "../../../src/void3d/uniformPool";
import {
	DrawContext,
	DrawItem,
	MeshId,
	MaterialId,
	MaterialError,
	MeshUploadError,
	StreamError,
	HandleError,
	NO_MESH,
	NO_MATERIAL,
	addMeshData,
	addStreamMesh,
	writeStream,
	rebuildMeshes,
	retainMesh,
	releaseMesh,
	pinMesh,
	unpinMesh,
	tallyMeshPin,
	clearMeshTally,
	addMaterial,
	retainMaterial,
	releaseMaterial,
	pinMaterial,
	unpinMaterial,
	tallyMaterialPin,
	clearMaterialTally,
	addTexture,
	retainTexture,
	releaseTexture,
	rebuildTextures,
	buryDoomed,
	reserveUniforms,
	releaseUniforms,
	writeUniforms,
	drawItem,
	closeContext,
} from "../../../src/void3d/draw";
import {
	AnimationClock,
	AnimationError,
	Interpolation,
	MeshFrameAnimation,
} from "../../../src/void3d/animation";
import { GltfData, GltfError, loadGltf } from "../../../src/void3d/gltf";
import { GltfAssets, GltfSceneError, addGltfAssets } from "../../../src/void3d/gltfScene";
import { Renderer, RendererError } from "../../../src/void3d/renderer";
import { ForwardRenderer, ForwardError } from "../../../src/void3d/forwardRenderer";
import {
	PixelArtRenderer,
	PixelArtSettings,
	PixelArtLook,
	PixelArtError,
} from "../../../src/void3d/pixelArtRenderer";

const BLACK: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };
const DOCUMENT: string = "{\"asset\":{\"version\":\"2.0\"},\"scenes\":[{\"nodes\":[0]}],"
	+ "\"nodes\":[{\"name\":\"only\"}],\"meshes\":[],\"accessors\":[],"
	+ "\"bufferViews\":[],\"buffers\":[]}";

function closedContext(): DrawContext {
	let context: DrawContext = DrawContext.withUniformCapacity(8);
	closeContext(context);
	return context;
}

function plainMaterial(): Material {
	return Material.plain(Program.Lit, RenderState.defaults(), Phase.Opaque);
}

function document(): GltfData {
	let bytes: Vec<uint8> = [];
	const loaded: Result<GltfData, GltfError> = loadGltf(DOCUMENT, bytes);
	if (!loaded.ok) { unreachable; }
	return loaded.value;
}

function look(): PixelArtLook {
	return {
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
}

function meshCase(name: string, context: DrawContext): boolean {
	let values: Vec<float32> = [0.0, 0.0, 0.0, 0.0];
	if (name == "addMeshData") {
		const _r: Result<MeshId, MeshUploadError> = addMeshData(context, MeshData.empty());
	} else if (name == "addStreamMesh") {
		const _r: Result<MeshId, StreamError> = addStreamMesh(context, 4);
	} else if (name == "writeStream") {
		const _r: Result<int32, StreamError> = writeStream(context, NO_MESH, values, 1);
	} else if (name == "rebuildMeshes") {
		const _r: int32 = rebuildMeshes(context);
	} else if (name == "retainMesh") {
		const _r: Result<int32, HandleError> = retainMesh(context, NO_MESH);
	} else if (name == "releaseMesh") {
		const _r: Result<int32, HandleError> = releaseMesh(context, NO_MESH);
	} else if (name == "pinMesh") {
		const _r: Result<int32, HandleError> = pinMesh(context, NO_MESH);
	} else if (name == "unpinMesh") {
		const _r: Result<int32, HandleError> = unpinMesh(context, NO_MESH);
	} else if (name == "tallyMeshPin") {
		const _r: boolean = tallyMeshPin(context, NO_MESH);
	} else if (name == "clearMeshTally") {
		clearMeshTally(context, NO_MESH);
	} else {
		return false;
	}
	return true;
}

function materialCase(name: string, context: DrawContext): boolean {
	if (name == "addMaterial") {
		const _r: Result<MaterialId, MaterialError> = addMaterial(context, plainMaterial());
	} else if (name == "retainMaterial") {
		const _r: Result<int32, HandleError> = retainMaterial(context, NO_MATERIAL);
	} else if (name == "releaseMaterial") {
		const _r: Result<int32, HandleError> = releaseMaterial(context, NO_MATERIAL);
	} else if (name == "pinMaterial") {
		const _r: Result<int32, HandleError> = pinMaterial(context, NO_MATERIAL);
	} else if (name == "unpinMaterial") {
		const _r: Result<int32, HandleError> = unpinMaterial(context, NO_MATERIAL);
	} else if (name == "tallyMaterialPin") {
		const _r: boolean = tallyMaterialPin(context, NO_MATERIAL);
	} else if (name == "clearMaterialTally") {
		clearMaterialTally(context, NO_MATERIAL);
	} else if (name == "addTexture") {
		const _r: Result<TextureId, TextureUploadError> = addTexture(context, TextureData.empty());
	} else if (name == "retainTexture") {
		const _r: Result<int32, HandleError> = retainTexture(context, NO_TEXTURE);
	} else if (name == "releaseTexture") {
		const _r: Result<int32, HandleError> = releaseTexture(context, NO_TEXTURE);
	} else if (name == "rebuildTextures") {
		const _r: int32 = rebuildTextures(context);
	} else {
		return false;
	}
	return true;
}

function drawCase(name: string, context: DrawContext): boolean {
	let values: Vec<float32> = [0.0, 0.0, 0.0, 0.0];
	let globals: Vec<UniformBlock> = [];
	if (name == "buryDoomed") {
		const _r: int32 = buryDoomed(context, 1);
	} else if (name == "reserveUniforms") {
		const _r: Result<UniformBlock, UniformError> = reserveUniforms(context, 2, 4);
	} else if (name == "releaseUniforms") {
		const _r: Result<int32, UniformError> = releaseUniforms(context, NO_UNIFORMS);
	} else if (name == "writeUniforms") {
		const _r: Result<int32, UniformError> = writeUniforms(context, NO_UNIFORMS, values);
	} else if (name == "drawItem") {
		const item: DrawItem = { mesh: NO_MESH, material: NO_MATERIAL, world: identity() };
		drawItem(context, item, ProgramKey.of(Program.Lit), SWAPCHAIN_LAYOUT, globals);
	} else if (name == "closeContext") {
		closeContext(context);
	} else {
		return false;
	}
	return true;
}

function ownerCase(name: string, context: DrawContext): boolean {
	let frames: Vec<MeshId> = [];
	if (name == "forMeshes") {
		const clock: Result<AnimationClock, AnimationError> =
			AnimationClock.forFrames(1, 12.0, Interpolation.Step);
		if (!clock.ok) { unreachable; }
		const _r: Result<MeshFrameAnimation, AnimationError> =
			MeshFrameAnimation.forMeshes(context, clock.value, "frames", frames);
	} else if (name == "addGltfAssets") {
		let block: Vec<float32> = [4.0, 0.0, 0.0, 0.0];
		const _r: Result<GltfAssets, GltfSceneError> =
			addGltfAssets(context, document(), { pass: RenderState.defaults(), block: block });
	} else if (name == "rendererCreate") {
		const _r: Result<Renderer, RendererError> =
			Renderer.createDrawing(context, Preset.Core);
	} else if (name == "forwardCreate") {
		const _r: Result<ForwardRenderer, ForwardError> = ForwardRenderer.create(context, BLACK);
	} else if (name == "pixelArtCreate") {
		const _r: Result<PixelArtRenderer, PixelArtError> =
			PixelArtRenderer.create(context, PixelArtSettings.full(), look());
	} else {
		return false;
	}
	return true;
}

function run(name: string): void {
	let context: DrawContext = closedContext();
	const known: boolean = meshCase(name, context) || materialCase(name, context) ||
		drawCase(name, context) || ownerCase(name, context);
	console.log(known ? `${name} returned on a closed context` : `no case named '${name}'`);
}

run((argv.length as int32) > 1 ? argv[1] : "");
