// Port of h3d.scene.Renderer: what every renderer does, and no look of its own.
//
// Heaps' base Renderer walks nothing and draws nothing (render() is abstract); it owns the
// named PassLists, sorts them and gives subclasses setTarget/copy. Here the same core owns the
// pass lists (Opaque, Alpha back to front, Additive), the scene's camera and light uniform
// blocks, the screen triangle every ScreenFx draws, and the GPU context bookkeeping. A preset
// (pixelArtRenderer.ms, as fwd.Renderer / pbr.Renderer are in Heaps) owns targets and passes
// and calls beginFrame, drawPassLists (or drawPhase, one list at a time, as Heaps'
// renderPass) and drawScreen in its own order, between openPrepare,
// closePrepare and openScreen, which hold its two halves to one sokol frame.
//
// It takes a Span<DrawItem> and the camera block, never a scene (docs/VOID3D.md, Porting
// rules); the items' meshes and materials live in the DrawContext it was made on. What it draws
// for each material's program is its ProgramMap: the core's own, or the one a preset gives it.

import {
	Program,
	VertexLayout,
	vertexLayoutOf,
	drawsQuads,
	VERTEX_UNIFORM_SLOT,
	VERTEX_UNIFORM_LENGTH,
	LIGHT_UNIFORM_SLOT,
	LIGHT_UNIFORM_LENGTH,
	uniformBlockLength,
	textureSlotMask,
	samplerSlotMask,
	destroyBuffer,
} from "./gpu3d";
import { Material, Phase, UniformBlock, NO_UNIFORMS } from "./material";
import { TargetLayout } from "../gpu/target";
import {
	PassState,
	passState,
	UNIFORM_SLOTS,
	contextGeneration,
	frameIndex,
} from "../gpu/door";
import {
	DrawContext,
	DrawItem,
	MeshId,
	MaterialId,
	MeshUploadError,
	addMesh,
	releaseMesh,
	HandleError,
	buryDoomed,
	rebuildMeshes,
	rebuildTextures,
	reserveUniforms,
	writeUniforms,
	drawItem,
	MODEL_SLOT,
} from "./draw";
import { UniformError, ownRange, disownRange } from "./uniformPool";
import { PassList, collect, filterFrustum, sortBackToFront, drawPassList } from "./passList";
import { ProgramMap, ProgramError } from "./programMap";
import { screenMesh, screenItem, makeScreenTriangle } from "./screenFx";
import { Mat4 } from "../math/math3d";
import { Frustum3D } from "./frustum";

// PENDING3D: store-serial-writable
export interface Renderer {
	context: DrawContext;
	opaque: PassList;
	alpha: PassList;
	additive: PassList;
	cameraBlock: UniformBlock;
	lightBlock: UniformBlock;
	sceneGlobals: Vec<UniformBlock>;
	programs: ProgramMap;
	// Per item of the frame, the program `programs` draws for its material's.
	drawn: Vec<Program>;
	screenMesh: MeshId;
	// The GPU context the handles in play belong to; 0 before the first frame.
	generation: int32;
	// Something changed since the last frame (V6: the host skips frames that would draw the
	// same image).
	changed: boolean;
	prepared: boolean;
	preparedFrame: uint32;
	culledCount: int32;
	closed: boolean;
}

export enum RendererError {
	UniformPoolFull,
	CameraBlockLength,
	LightBlockLength,
	ProgramNotDrawn,
	MaterialBlock,
	VertexLayout,
	MaterialTexture,
	QuadMesh,
	UniformsReplaced,
	TextureReplaced,
	StaleMesh,
	StaleMaterial,
	ForeignMesh,
	ForeignMaterial,
}

// Floats of the uniform pool the core reserves: camera and lights.
export const RENDERER_UNIFORM_LENGTH: int32 = VERTEX_UNIFORM_LENGTH + LIGHT_UNIFORM_LENGTH;

const NO_GLOBALS: Vec<UniformBlock> = [];

function meshError(context: DrawContext, id: MeshId): RendererError {
	return context.issuedMesh(id) ? RendererError.StaleMesh : RendererError.ForeignMesh;
}

function materialError(context: DrawContext, id: MaterialId): RendererError {
	return context.issuedMaterial(id) ? RendererError.StaleMaterial : RendererError.ForeignMaterial;
}

// createDrawing checked that the pool fits the block, and the renderer owns it, so nothing but
// the renderer can release it.
function reserveOwned(context: DrawContext, slot: int32, length: int32): UniformBlock {
	const reserved: Result<UniformBlock, UniformError> = reserveUniforms(context, slot, length);
	if (!reserved.ok) { unreachable; }
	if (!ownRange(context.uniforms, reserved.value).ok) { unreachable; }
	return reserved.value;
}

// Reserves the camera and light blocks and adds the screen triangle's mesh to `context`. No
// GPU object is made here: the first beginFrame makes them. It draws the core's programs.
export function create(
	this typeof Renderer,
	context: DrawContext,
): Result<Renderer, RendererError> {
	return Renderer.createDrawing(context, ProgramMap.core());
}

// The same, drawing `programs` for the programs its materials name: a preset's.
export function createDrawing(
	this typeof Renderer,
	context: DrawContext,
	programs: ProgramMap,
): Result<Renderer, RendererError> {
	context.requireOpen("Renderer.createDrawing");
	const blocks: Vec<int32> = [VERTEX_UNIFORM_LENGTH, LIGHT_UNIFORM_LENGTH];
	if (!context.uniforms.fits(blocks).ok) {
		return Result.err(RendererError.UniformPoolFull);
	}
	const cameraBlock: UniformBlock =
		reserveOwned(context, VERTEX_UNIFORM_SLOT, VERTEX_UNIFORM_LENGTH);
	const lightBlock: UniformBlock =
		reserveOwned(context, LIGHT_UNIFORM_SLOT, LIGHT_UNIFORM_LENGTH);
	const screen: Result<MeshId, MeshUploadError> = addMesh(context, screenMesh(0));
	if (!screen.ok) { unreachable; }
	return Result.ok({
		context: context,
		opaque: PassList.forPhase(Phase.Opaque),
		alpha: PassList.forPhase(Phase.Alpha),
		additive: PassList.forPhase(Phase.Additive),
		cameraBlock: cameraBlock,
		lightBlock: lightBlock,
		sceneGlobals: [cameraBlock, lightBlock],
		programs: programs,
		drawn: [],
		screenMesh: screen.value,
		generation: 0,
		changed: true,
		prepared: false,
		preparedFrame: 0,
		culledCount: 0,
		closed: false,
	});
}

// For whatever the renderer cannot see: the items moved, a material or a light changed.
export function markChanged(renderer: Renderer): void {
	if (renderer.closed) { stopOnClosed("markChanged"); }
	renderer.changed = true;
}

// Whether the next frame could differ from the last one drawn: something was marked changed
// or the GPU context is new. A preset adds its own inputs (the view, its settings).
export function needsFrame(this renderer: Renderer): boolean {
	if (renderer.closed) { return false; }
	return renderer.changed || renderer.generation != contextGeneration();
}

// Starts a frame: uploads the camera and lights, adopts a new GPU context if there is one and fills
// the pass lists from `items`. A camera or light span that is not its block's length, an item whose
// material names a program this renderer does not draw, a material whose block is not the one that
// program reads or has been released, or that lacks a texture or sampler it samples, names a
// texture it does not sample or another than it was added with, or a mesh whose vertex layout it
// does not read, or a quad-layout mesh with a vertex buffer or with instances and no instance
// buffer, is refused before anything changes. Answers true when the context is new: every handle
// the caller made before is stale then (it may name an object of the new context), so the caller
// drops its own without destroying them and makes them again before drawing. The core has already
// dropped the pipelines, remade the screen triangle, and remade every mesh and texture that
// carries its CPU data (draw.ms rebuildMeshes, rebuildTextures); what is left is whatever the
// caller uploaded from buffers only it keeps.
export function beginFrame(
	renderer: Renderer,
	items: Readonly<Span<DrawItem>>,
	camera: Readonly<Span<float32>>,
	lights: Readonly<Span<float32>>,
): Result<boolean, RendererError> {
	if (renderer.closed) { stopOnClosed("beginFrame"); }
	const context: DrawContext = renderer.context;
	if (!context.hasMesh(renderer.screenMesh)) {
		return Result.err(meshError(context, renderer.screenMesh));
	}
	for (const item of items) {
		if (!context.hasMesh(item.mesh)) { return Result.err(meshError(context, item.mesh)); }
		if (!context.hasMaterial(item.material)) {
			return Result.err(materialError(context, item.material));
		}
		const material: int32 = item.material.index;
		const drawn: Result<Program, ProgramError> =
			renderer.programs.drawnFor(context.materials[material].program);
		if (!drawn.ok) { return Result.err(RendererError.ProgramNotDrawn); }
		if (!context.keepsItsUniforms(item.material)) {
			return Result.err(RendererError.UniformsReplaced);
		}
		if (!context.keepsItsTexture(item.material)) {
			return Result.err(RendererError.TextureReplaced);
		}
		if (!blockFits(drawn.value, context.materials[material].uniforms)) {
			return Result.err(RendererError.MaterialBlock);
		}
		const layout: VertexLayout = context.meshes[item.mesh.index].layout;
		if (layout != vertexLayoutOf(drawn.value)) {
			return Result.err(RendererError.VertexLayout);
		}
		if (drawsQuads(layout) && !context.meshes[item.mesh.index].isQuadShaped()) {
			return Result.err(RendererError.QuadMesh);
		}
		if (!texturesFit(drawn.value, context.materials[material])) {
			return Result.err(RendererError.MaterialTexture);
		}
	}
	if ((camera.length as int32) != renderer.cameraBlock.length) {
		return Result.err(RendererError.CameraBlockLength);
	}
	if ((lights.length as int32) != renderer.lightBlock.length) {
		return Result.err(RendererError.LightBlockLength);
	}
	const cameraWritten: Result<int32, UniformError> =
		writeUniforms(context, renderer.cameraBlock, camera);
	if (!cameraWritten.ok) { return Result.err(RendererError.CameraBlockLength); }
	const lightsWritten: Result<int32, UniformError> =
		writeUniforms(context, renderer.lightBlock, lights);
	if (!lightsWritten.ok) { return Result.err(RendererError.LightBlockLength); }
	while ((renderer.drawn.length as int32) < (items.length as int32)) {
		renderer.drawn.push(Program.Lit);
	}
	for (let i = 0; i < (items.length as int32); i++) {
		const resolved: Result<Program, ProgramError> =
			renderer.programs.drawnFor(context.materials[items[i].material.index].program);
		if (!resolved.ok) { unreachable; }
		renderer.drawn[i] = resolved.value;
	}
	const generation: int32 = contextGeneration();
	const _buried: int32 = buryDoomed(context, generation);
	const fresh: boolean = generation != renderer.generation;
	if (fresh) {
		rebuildMeshes(context);
		rebuildTextures(context);
		context.meshes[renderer.screenMesh.index].vertexBuffer = makeScreenTriangle();
		renderer.generation = generation;
		renderer.changed = true;
	}
	collect(renderer.opaque, items, context.materials);
	collect(renderer.alpha, items, context.materials);
	collect(renderer.additive, items, context.materials);
	let viewProj: Mat4 = {
		m11: camera[0], m12: camera[1], m13: camera[2], m14: camera[3],
		m21: camera[4], m22: camera[5], m23: camera[6], m24: camera[7],
		m31: camera[8], m32: camera[9], m33: camera[10], m34: camera[11],
		m41: camera[12], m42: camera[13], m43: camera[14], m44: camera[15],
	};
	let frustum: Frustum3D = Frustum3D.fromMatrix(viewProj);
	renderer.culledCount =
		filterFrustum(renderer.opaque, items, context.meshData, frustum) +
		filterFrustum(renderer.alpha, items, context.meshData, frustum) +
		filterFrustum(renderer.additive, items, context.meshData, frustum);
	sortBackToFront(renderer.alpha, items, camera);
	return Result.ok(fresh);
}

// fwd.Renderer's default, alpha and additive passes, into the current pass (`targets` is
// its attachment layout), with the camera and lights applied to every item and each drawn with
// the program beginFrame resolved for it: `items` must be the span that beginFrame accepted.
export function drawPassLists(
	renderer: Renderer,
	items: Readonly<Span<DrawItem>>,
	targets: TargetLayout,
): void {
	if (renderer.closed) { stopOnClosed("drawPassLists"); }
	drawPhase(renderer, Phase.Opaque, items, targets);
	drawPhase(renderer, Phase.Alpha, items, targets);
	drawPhase(renderer, Phase.Additive, items, targets);
}

// fwd.Renderer's renderPass(output, get(name)): one of the lists into the current pass, for a
// preset that sends its lists to different targets.
export function drawPhase(
	renderer: Renderer,
	phase: Phase,
	items: Readonly<Span<DrawItem>>,
	targets: TargetLayout,
): void {
	if (renderer.closed) { stopOnClosed("drawPhase"); }
	const context: DrawContext = renderer.context;
	match (phase) {
		Phase.Opaque => {
			drawPassList(
				context, renderer.opaque, items, renderer.drawn, targets, renderer.sceneGlobals,
			);
		},
		Phase.Alpha => {
			drawPassList(
				context, renderer.alpha, items, renderer.drawn, targets, renderer.sceneGlobals,
			);
		},
		Phase.Additive => {
			drawPassList(
				context, renderer.additive, items, renderer.drawn, targets, renderer.sceneGlobals,
			);
		},
	};
}

// How many items of `phase` the frame beginFrame accepted draws, after culling.
export function phaseCount(this renderer: Renderer, phase: Phase): int32 {
	if (renderer.closed) { stopOnClosed("phaseCount"); }
	return match (phase) {
		Phase.Opaque => renderer.opaque.count,
		Phase.Alpha => renderer.alpha.count,
		Phase.Additive => renderer.additive.count,
	};
}

// ScreenFx.render: `material` (a Fullscreen-layout material of the renderer's context, drawn
// with its own program) over the whole current pass.
export function drawScreen(
	renderer: Renderer,
	material: MaterialId,
	targets: TargetLayout,
): Result<int32, RendererError> {
	if (renderer.closed) { stopOnClosed("drawScreen"); }
	const context: DrawContext = renderer.context;
	if (!context.hasMesh(renderer.screenMesh)) {
		return Result.err(meshError(context, renderer.screenMesh));
	}
	if (!context.hasMaterial(material)) { return Result.err(materialError(context, material)); }
	if (!context.keepsItsUniforms(material)) {
		return Result.err(RendererError.UniformsReplaced);
	}
	if (!context.keepsItsTexture(material)) { return Result.err(RendererError.TextureReplaced); }
	const program: Program = context.materials[material.index].program;
	drawItem(context, screenItem(renderer.screenMesh, material), program, targets, NO_GLOBALS);
	return Result.ok(1);
}

// The one block a material brings for `program`: the slot it declares that is neither pass-wide
// nor the model matrix, at the length its shader declares; none when it declares no such slot.
function blockFits(program: Program, block: UniformBlock): boolean {
	let own: int32 = -1;
	for (let slot = 0; slot < UNIFORM_SLOTS; slot++) {
		const passWide: boolean = slot == VERTEX_UNIFORM_SLOT || slot == LIGHT_UNIFORM_SLOT;
		if (passWide || slot == MODEL_SLOT || uniformBlockLength(program, slot) == 0) {
			continue;
		}
		if (own >= 0) { return false; }
		own = slot;
	}
	if (own < 0) { return block.length == 0; }
	return block.slot == own && block.length == uniformBlockLength(program, own);
}

function slotBound(mask: uint32, slot: uint32, bound: boolean): boolean {
	return (mask & ((1 as uint32) << slot)) == 0 || bound;
}

// Every texture view and sampler `program` declares is bound on `material`; a slot the
// material has no field for (views past 3, samplers past 1) never is.
function texturesFit(program: Program, material: Material): boolean {
	const views: uint32 = textureSlotMask(program);
	const samplers: uint32 = samplerSlotMask(program);
	if ((views >> 4) != 0 || (samplers >> 2) != 0) { return false; }
	let texture: boolean = material.namesTexture();
	if (texture && (material.texture0 != 0 || material.sampler0 != 0)) { return false; }
	if (texture && ((views & 1) == 0 || (samplers & 1) == 0)) { return false; }
	return slotBound(views, 0, texture || material.texture0 != 0)
		&& slotBound(views, 1, material.texture1 != 0)
		&& slotBound(views, 2, material.texture2 != 0)
		&& slotBound(views, 3, material.texture3 != 0)
		&& slotBound(samplers, 0, texture || material.sampler0 != 0)
		&& slotBound(samplers, 1, material.sampler1 != 0);
}

export function openPrepare(this renderer: Renderer): void {
	if (renderer.closed) { stopOnClosed("prepareFrame"); }
	if (renderer.prepared) {
		console.log("void3d: prepareFrame again before drawToScreen drew the frame it prepared");
		unreachable;
	}
	// sokol cannot nest passes, and the prepare opens its own (the door tracks which pass is
	// open, M18's screen-pass-unchecked).
	if (passState() != PassState.None) {
		console.log("void3d: prepareFrame with a pass already open; it would nest inside it");
		unreachable;
	}
}

// The frame's inputs are taken here, so a change made before the screen half is kept.
export function closePrepare(renderer: Renderer): void {
	renderer.prepared = true;
	renderer.preparedFrame = frameIndex();
	renderer.changed = false;
}

export function openScreen(renderer: Renderer): void {
	if (renderer.closed) { stopOnClosed("drawToScreen"); }
	if (!renderer.prepared) {
		console.log("void3d: drawToScreen with no prepared frame; call prepareFrame first");
		unreachable;
	}
	if (passState() != PassState.Screen) {
		console.log("void3d: drawToScreen outside a screen pass; open one with beginScreenPass");
		unreachable;
	}
	// frameIndex counts sokol frames, so it is read only once a screen pass proves one is
	// being recorded; a headless caller stops above before touching it.
	if (renderer.preparedFrame != frameIndex()) {
		console.log("void3d: drawToScreen in a later sokol frame than the prepareFrame it draws");
		unreachable;
	}
	renderer.prepared = false;
}

export function closeRenderer(renderer: Renderer): void {
	if (renderer.closed) { stopOnClosed("closeRenderer"); }
	if (passState() != PassState.None) {
		console.log("void3d: closeRenderer with a pass open; endPass ends it");
		unreachable;
	}
	const context: DrawContext = renderer.context;
	if (!context.hasMesh(renderer.screenMesh)) { stopOnLostScreenMesh(context, renderer); }
	const screen: int32 = renderer.screenMesh.index;
	const buffer: uint32 = context.meshes[screen].vertexBuffer;
	if (buffer != 0 && renderer.generation == contextGeneration()) { destroyBuffer(buffer); }
	context.meshes[screen].vertexBuffer = 0;
	const released: Result<int32, HandleError> = releaseMesh(context, renderer.screenMesh);
	if (!released.ok) { stopOnLostScreenMesh(context, renderer); }
	const camera: Result<int32, UniformError> = disownRange(context.uniforms, renderer.cameraBlock);
	const light: Result<int32, UniformError> = disownRange(context.uniforms, renderer.lightBlock);
	if (!camera.ok || !light.ok) {
		console.log("void3d: closeRenderer found its camera or light block already given back");
		unreachable;
	}
	renderer.closed = true;
}

export function isClosed(this renderer: Renderer): boolean {
	return renderer.closed;
}

function stopOnClosed(call: string): void {
	console.log(`void3d: ${call} on a renderer that was closed`);
	unreachable;
}

function stopOnLostScreenMesh(context: DrawContext, renderer: Renderer): void {
	const holders: int32 = context.meshHolders[renderer.screenMesh.index];
	console.log(`void3d: closeRenderer found its screen mesh released (${holders} holders)`);
	unreachable;
}
