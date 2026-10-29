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
// expect reserveBlock: void3d: reserveBlock on a draw context that was closed
// expect releaseBlock: void3d: releaseBlock on a draw context that was closed
// expect writeBlock: void3d: writeBlock on a draw context that was closed
// expect drawItem: void3d: drawItem on a draw context that was closed
// expect closeContext: void3d: closeContext on a draw context that was closed
// expect forMeshes: void3d: forMeshes on a draw context that was closed
// expect addGltfAssets: void3d: addGltfAssets on a draw context that was closed
// expect reserveRange: void3d: reserveRange on a uniform pool that was closed
// expect ownRange: void3d: ownRange on a uniform pool that was closed
// expect disownRange: void3d: disownRange on a uniform pool that was closed
// expect releaseRange: void3d: releaseRange on a uniform pool that was closed
// expect writeRange: void3d: writeRange on a uniform pool that was closed
// expect poolReserveBlock: void3d: reserveBlock on a uniform pool that was closed
// expect poolWriteBlock: void3d: writeBlock on a uniform pool that was closed
// expect closeUniformPool: void3d: closeUniformPool on a uniform pool that was closed
// expect closed.fill: void3d: fill on a palette table that was closed
// expect closed.releaseGpu: void3d: releaseGpu on a palette table that was closed
// expect closed.closePalette: void3d: closePalette on a palette table that was closed
// expect closed.upload: void3d: upload on a palette table that was closed
// expect context.liveHolds: void3d: closeContext with holds still live: meshes 1, materials 0, textures 0,
// expect context.usedAfterClose: void3d: addMesh on a draw context that was closed
// expect pool.liveRange: void3d: closeUniformPool with ranges still reserved: 1
// expect closedOwner.addTargetTexture: void3d: addTargetTexture on a render target that was closed
// expect tally.materialForeign: void3d: tallyMaterialPin through a context that did not issue the material
// expect tally.meshForeign: void3d: tallyMeshPin through a context that did not issue the mesh
// expect drawItem.foreignBlock: void3d: drawItem with a block at slot 0 its context does not hold
// expect drawItem.otherLiveBlock: void3d: drawItem with a material whose block is not the one it was added with
// expect drawItem.releasedBlock: void3d: drawItem with a material whose block is not the one it was added with
// expect blockHead.colour: so a block of 8 is not its own; only a shadow caster takes a head
// expect blockHead.short: reads 28 floats of slot 3 and its material's block holds 4
// expect key.emissiveUnlit: void3d: Core UnlitTextured has no emissive variant
// expect key.undeclared: void3d: no program declared for PixelArt Copy (src/void3d/programKeys.txt)
// expect key.withoutDissolve: void3d: Core Billboard has no dissolve variant
// expect key.withoutPremultiplied: void3d: Core Lit has no premultiplied variant
// expect key.movingWithPbr: void3d: Core LitTextured uv-transform has no pbr variant
// expect key.pbrWithUvTransform: void3d: Core LitTextured pbr has no uv transform variant
// expect key.normalMapUntextured: void3d: Core Lit has no normal map variant
// expect material.kindWithoutCutout: void3d: MaterialKind.AlphaKill for Copy, which has no cutout
// expect material.movingDefaultsStill: void3d: movingDefaults for Core LitTextured, which does not move
// expect camera.orthoBoundsPerspective: void3d: orthoBounds asked of a perspective camera
import { argv } from "std/process";
import { identity, vec3 } from "../../../src/math/math3d";
import { FilterMode, Wrap, RenderState } from "../../../src/gpu/state";
import { PixelFormat } from "../../../src/gpu/door";
import { RenderTarget, SWAPCHAIN_LAYOUT } from "../../../src/gpu/target";
import {
	Program,
	ProgramKey,
	Preset,
	MATERIAL_UNIFORM_SLOT,
	MATERIAL_UNIFORM_LENGTH,
	doorProgram,
} from "../../../src/void3d/gpu3d";
import {
	Material,
	MaterialKind,
	Phase,
	NO_UNIFORMS,
	TypedBlock,
	UniformBlock,
	movingDefaults,
} from "../../../src/void3d/material";
import { OutlineWidthParams } from "../../../src/void3d/post3d";
import { Camera3D, ProjectionKind } from "../../../src/void3d/camera";
import { MeshData } from "../../../src/void3d/meshData";
import {
	TextureData,
	TextureId,
	TextureAlpha,
	TextureUploadError,
	NO_TEXTURE,
} from "../../../src/void3d/texture";
import {
	UniformPool,
	UniformError,
	reserveRange,
	ownRange,
	disownRange,
	releaseRange,
	writeRange,
	reserveBlock as reserveBlockOn,
	writeBlock as writeBlockOn,
	closeUniformPool,
} from "../../../src/void3d/uniformPool";
import {
	PaletteLut,
	PaletteError,
	fill,
	upload,
	releaseGpu,
	closePalette,
} from "../../../src/void3d/palette";
import {
	DrawContext,
	DrawItem,
	GpuMesh,
	MeshId,
	MaterialId,
	MaterialError,
	MeshUploadError,
	StreamError,
	HandleError,
	NO_MESH,
	NO_MATERIAL,
	addMesh,
	addMeshData,
	addStreamMesh,
	addTargetTexture,
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
	reserveBlock,
	releaseBlock,
	writeBlock,
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

const DOCUMENT: string = "{\"asset\":{\"version\":\"2.0\"},\"scenes\":[{\"nodes\":[0]}],"
	+ "\"nodes\":[{\"name\":\"only\"}],\"meshes\":[],\"accessors\":[],"
	+ "\"bufferViews\":[],\"buffers\":[]}";
const NO_GLOBALS: Vec<UniformBlock> = [];


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
	} else if (name == "reserveBlock") {
		const _r: Result<TypedBlock<OutlineWidthParams>, UniformError> =
			reserveBlock<OutlineWidthParams>(context, 2);
	} else if (name == "releaseBlock") {
		const _r: Result<int32, UniformError> =
			releaseBlock<OutlineWidthParams>(context, { block: NO_UNIFORMS });
	} else if (name == "writeBlock") {
		const width: OutlineWidthParams = { outlineWidth: { x: 0.0, y: 0.0, z: 0.0, w: 0.0 } };
		const _r: Result<int32, UniformError> =
			writeBlock<OutlineWidthParams>(context, { block: NO_UNIFORMS }, width);
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
		let block: Vec<float32> = [4.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0];
		const _r: Result<GltfAssets, GltfSceneError> =
			addGltfAssets(context, document(), { pass: RenderState.defaults(), block: block });
	} else {
		return false;
	}
	return true;
}

function closedPool(): UniformPool {
	let context: DrawContext = DrawContext.withUniformCapacity(8);
	let pool: UniformPool = context.uniforms;
	closeContext(context);
	return pool;
}

function poolCase(name: string): boolean {
	let pool: UniformPool = closedPool();
	let values: Vec<float32> = [0.0, 0.0, 0.0, 0.0];
	if (name == "reserveRange") {
		const _r: Result<UniformBlock, UniformError> = reserveRange(pool, 2, 4);
	} else if (name == "ownRange") {
		const _r: Result<int32, UniformError> = ownRange(pool, NO_UNIFORMS);
	} else if (name == "disownRange") {
		const _r: Result<int32, UniformError> = disownRange(pool, NO_UNIFORMS);
	} else if (name == "releaseRange") {
		const _r: Result<int32, UniformError> = releaseRange(pool, NO_UNIFORMS);
	} else if (name == "writeRange") {
		const _r: Result<int32, UniformError> = writeRange(pool, NO_UNIFORMS, values);
	} else if (name == "poolReserveBlock") {
		const _r: Result<TypedBlock<OutlineWidthParams>, UniformError> =
			reserveBlockOn<OutlineWidthParams>(pool, 2);
	} else if (name == "poolWriteBlock") {
		const width: OutlineWidthParams = { outlineWidth: { x: 0.0, y: 0.0, z: 0.0, w: 0.0 } };
		const _r: Result<int32, UniformError> =
			writeBlockOn<OutlineWidthParams>(pool, { block: NO_UNIFORMS }, width);
	} else if (name == "closeUniformPool") {
		closeUniformPool(pool);
	} else {
		return false;
	}
	return true;
}

function closedTable(): PaletteLut {
	const made: Result<PaletteLut, PaletteError> = PaletteLut.withLevels(4);
	if (!made.ok) { unreachable; }
	let lut: PaletteLut = made.value;
	closePalette(lut);
	return lut;
}

function paletteCase(name: string): boolean {
	let colors: Vec<uint32> = [0xFF000000, 0xFFFFFFFF];
	if (name == "closed.fill") {
		const _r: Result<int32, PaletteError> = fill(closedTable(), colors);
	} else if (name == "closed.releaseGpu") {
		releaseGpu(closedTable());
	} else if (name == "closed.closePalette") {
		closePalette(closedTable());
	} else if (name == "closed.upload") {
		upload(closedTable());
	} else {
		return false;
	}
	return true;
}

function meshOf(context: DrawContext): MeshId {
	const added: Result<MeshId, MeshUploadError> = addMesh(context, GpuMesh.fullscreen(0, 3));
	if (!added.ok) { unreachable; }
	return added.value;
}

function blockOf(context: DrawContext): UniformBlock {
	const made: Result<UniformBlock, UniformError> =
		reserveUniforms(context, MATERIAL_UNIFORM_SLOT, MATERIAL_UNIFORM_LENGTH);
	if (!made.ok) { unreachable; }
	return made.value;
}

function drawItemBlockCase(name: string): boolean {
	let drawing: DrawContext = DrawContext.withUniformCapacity(3 * MATERIAL_UNIFORM_LENGTH);
	const lit: Material = {
		...Material.plain(Program.Lit, RenderState.defaults(), Phase.Opaque),
		uniforms: blockOf(drawing),
	};
	const mesh: MeshId = meshOf(drawing);
	const material: Result<MaterialId, MaterialError> = addMaterial(drawing, lit);
	if (!material.ok) { unreachable; }
	let globals: Vec<UniformBlock> = NO_GLOBALS;
	if (name == "drawItem.foreignBlock") {
		let other: DrawContext = DrawContext.withUniformCapacity(64);
		const padding: Result<UniformBlock, UniformError> = reserveUniforms(other, 0, 32);
		const block: Result<UniformBlock, UniformError> = reserveUniforms(other, 0, 24);
		if (!padding.ok || !block.ok) { unreachable; }
		globals = [block.value];
	} else if (name == "drawItem.otherLiveBlock") {
		drawing.materials[material.value.index].uniforms = blockOf(drawing);
	} else if (name == "drawItem.releasedBlock") {
		const gone: UniformBlock = blockOf(drawing);
		if (!releaseUniforms(drawing, gone).ok) { unreachable; }
		drawing.materials[material.value.index].uniforms = gone;
	} else {
		return false;
	}
	const item: DrawItem = { mesh: mesh, material: material.value, world: identity() };
	drawItem(drawing, item, ProgramKey.of(Program.Lit), SWAPCHAIN_LAYOUT, globals);
	return true;
}

function blockHeadCase(name: string): boolean {
	let context: DrawContext = DrawContext.withUniformCapacity(64);
	if (name == "blockHead.colour") {
		const long: UniformBlock = {
			store: context.uniforms.serial, slot: MATERIAL_UNIFORM_SLOT, offset: 0,
			length: 8, generation: 1,
		};
		context.applyBlockHead(long, ProgramKey.of(Program.Lit), 4);
	} else if (name == "blockHead.short") {
		const short: UniformBlock = {
			store: context.uniforms.serial, slot: MATERIAL_UNIFORM_SLOT, offset: 0,
			length: 4, generation: 1,
		};
		const caster: ProgramKey =
			ProgramKey.of(Program.LitTextured).withDissolve().withPreset(Preset.Shadow);
		context.applyBlockHead(short, caster, 28);
	} else {
		return false;
	}
	return true;
}

function keyCase(name: string): boolean {
	if (name == "key.emissiveUnlit") {
		const _made: ProgramKey = ProgramKey.of(Program.UnlitTextured).withEmissive();
	} else if (name == "key.undeclared") {
		const id: int32 = doorProgram(ProgramKey.of(Program.Copy).withPreset(Preset.PixelArt));
		console.log(`an undeclared key reached the door as ${id}`);
	} else if (name == "key.withoutDissolve") {
		const _made: ProgramKey = ProgramKey.of(Program.Billboard).withDissolve();
	} else if (name == "key.withoutPremultiplied") {
		const _made: ProgramKey = ProgramKey.of(Program.Lit).withPremultiplied();
	} else if (name == "key.movingWithPbr") {
		const _made: ProgramKey = ProgramKey.of(Program.LitTextured).withUvTransform().withPbr();
	} else if (name == "key.pbrWithUvTransform") {
		const _made: ProgramKey = ProgramKey.of(Program.LitTextured).withPbr().withUvTransform();
	} else if (name == "key.normalMapUntextured") {
		const _made: ProgramKey = ProgramKey.of(Program.Lit).withNormalMap();
	} else if (name == "material.kindWithoutCutout") {
		const made: Material = Material.ofKind(Program.Copy, MaterialKind.AlphaKill);
		console.log(`a cutout of a program without one was made: ${made.program.toString()}`);
	} else if (name == "material.movingDefaultsStill") {
		const values: Vec<float32> = movingDefaults(ProgramKey.of(Program.LitTextured));
		console.log(`a still key got a moving block of ${values.length} floats`);
	} else if (name == "camera.orthoBoundsPerspective") {
		let camera: Camera3D = {
			position: vec3(0.0, 0.0, 0.0),
			yaw: 0.0,
			pitch: 0.0,
			nearPlane: 0.1,
			farPlane: 100.0,
			projection: { kind: ProjectionKind.Perspective, fovY: 1.0 },
		};
		let bounds = camera.orthoBounds(320, 240);
		console.log(bounds.minX);
	} else {
		return false;
	}
	return true;
}

function wiringCase(name: string): boolean {
	if (name == "context.liveHolds") {
		let context: DrawContext = DrawContext.withUniformCapacity(4);
		const mesh: Result<MeshId, MeshUploadError> = addMesh(context, GpuMesh.fullscreen(0, 3));
		const range: Result<UniformBlock, UniformError> = reserveUniforms(context, 2, 4);
		if (!mesh.ok || !range.ok) { unreachable; }
		closeContext(context);
	} else if (name == "context.usedAfterClose") {
		let context: DrawContext = DrawContext.withUniformCapacity(0);
		let alias: DrawContext = context;
		closeContext(context);
		const _mesh: Result<MeshId, MeshUploadError> = addMesh(alias, GpuMesh.fullscreen(0, 3));
	} else if (name == "pool.liveRange") {
		let pool: UniformPool = UniformPool.withCapacity(8);
		const range: Result<UniformBlock, UniformError> = reserveRange(pool, 2, 4);
		if (!range.ok) { unreachable; }
		closeUniformPool(pool);
	} else if (name == "closedOwner.addTargetTexture") {
		const context: DrawContext = DrawContext.withUniformCapacity(0);
		const target: RenderTarget = RenderTarget.unallocated(PixelFormat.Rgba8, true);
		target.close();
		const _added = addTargetTexture(
			context, target, FilterMode.Nearest, Wrap.Clamp, TextureAlpha.Premultiplied,
		);
	} else if (name == "tally.materialForeign") {
		let made: DrawContext = DrawContext.withUniformCapacity(0);
		let other: DrawContext = DrawContext.withUniformCapacity(0);
		const material: Result<MaterialId, MaterialError> = addMaterial(made, plainMaterial());
		if (!material.ok) { unreachable; }
		const _covered: boolean = tallyMaterialPin(other, material.value);
	} else if (name == "tally.meshForeign") {
		let made: DrawContext = DrawContext.withUniformCapacity(0);
		let other: DrawContext = DrawContext.withUniformCapacity(0);
		const _covered: boolean = tallyMeshPin(other, meshOf(made));
	} else {
		return false;
	}
	return true;
}

function run(name: string): void {
	let context: DrawContext = closedContext();
	const known: boolean = meshCase(name, context) || materialCase(name, context) ||
		drawCase(name, context) || ownerCase(name, context) || poolCase(name) ||
		paletteCase(name) || drawItemBlockCase(name) || blockHeadCase(name) ||
		keyCase(name) || wiringCase(name);
	if (!known) {
		console.log(`no case named '${name}'`);
		process.exit(2);
	}
	console.log(`${name} returned`);
}

run((argv.length as int32) > 1 ? argv[1] : "");
