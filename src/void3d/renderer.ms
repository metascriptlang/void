// Port of h3d.scene.Renderer: what every renderer does, and no look of its own.
//
// Heaps' base Renderer walks nothing and draws nothing (render() is abstract); it owns the
// named PassLists, sorts them and gives subclasses setTarget/copy. Here the same core owns the
// pass lists (Opaque, Alpha back to front, Additive), the scene's camera and light uniform
// blocks, the screen triangle every ScreenFx draws, and the GPU context bookkeeping. A preset
// (pixelArtRenderer.ms, as fwd.Renderer / pbr.Renderer are in Heaps) owns targets and passes
// and calls beginFrame, drawPassLists, drawScreen and endFrame in its own order.
//
// It takes a Span<DrawItem> and the camera block, never a scene (docs/VOID3D.md, Porting
// rules); the items' meshes and materials live in the caller's DrawContext. What it draws for
// each material's program is its ProgramMap: the core's own, or the one a preset gives it.

import {
	Program,
	VERTEX_UNIFORM_SLOT,
	VERTEX_UNIFORM_LENGTH,
	LIGHT_UNIFORM_SLOT,
	LIGHT_UNIFORM_LENGTH,
	UNIFORM_SLOTS,
	contextGeneration,
	uniformBlockLength,
} from "./gpu3d";
import { commit } from "../sokol/gpu";
import { Phase, UniformBlock, NO_UNIFORMS } from "./material";
import { TargetLayout } from "./target";
import {
	DrawContext,
	DrawItem,
	addMesh,
	rebuildMeshes,
	reserveUniforms,
	writeUniforms,
	drawItem,
	MODEL_SLOT,
} from "./draw";
import { forgetPipelines } from "./pipelineCache";
import { PassList, collect, sortBackToFront, drawPassList } from "./passList";
import { ProgramMap, ProgramError } from "./programMap";
import { screenMesh, screenItem, makeScreenTriangle } from "./screenFx";

export struct Renderer {
	opaque: PassList;
	alpha: PassList;
	additive: PassList;
	cameraBlock: UniformBlock;
	lightBlock: UniformBlock;
	sceneGlobals: Vec<UniformBlock>;
	programs: ProgramMap;
	// Per item of the frame, the program `programs` draws for its material's.
	drawn: Vec<Program>;
	screenMesh: int32;
	// The GPU context the handles in play belong to; 0 before the first frame.
	generation: int32;
	// Something changed since the last frame (V6: the host skips frames that would draw the
	// same image).
	changed: boolean;
}

export enum RendererError {
	UniformPoolFull,
	CameraBlockLength,
	LightBlockLength,
	ProgramNotDrawn,
	MaterialBlock,
}

// Floats of the uniform pool the core reserves: camera and lights.
export const RENDERER_UNIFORM_LENGTH: int32 = VERTEX_UNIFORM_LENGTH + LIGHT_UNIFORM_LENGTH;

const NO_GLOBALS: Vec<UniformBlock> = [];

function reserve(ref context: DrawContext, slot: int32, length: int32): UniformBlock {
	return try reserveUniforms(context, slot, length) catch NO_UNIFORMS;
}

// Reserves the camera and light blocks and adds the screen triangle's mesh to `context`. No
// GPU object is made here: the first beginFrame makes them. It draws the core's programs.
export function create(
	this typeof Renderer,
	ref context: DrawContext,
): Result<Renderer, RendererError> {
	return Renderer.createDrawing(context, ProgramMap.core());
}

// The same, drawing `programs` for the programs its materials name: a preset's.
export function createDrawing(
	this typeof Renderer,
	ref context: DrawContext,
	programs: ProgramMap,
): Result<Renderer, RendererError> {
	const free: int32 = (context.uniforms.length as int32) - context.uniformsUsed;
	if (free < RENDERER_UNIFORM_LENGTH) {
		return Result.err(RendererError.UniformPoolFull);
	}
	const cameraBlock: UniformBlock = reserve(context, VERTEX_UNIFORM_SLOT, VERTEX_UNIFORM_LENGTH);
	const lightBlock: UniformBlock = reserve(context, LIGHT_UNIFORM_SLOT, LIGHT_UNIFORM_LENGTH);
	return Result.ok({
		opaque: PassList.forPhase(Phase.Opaque),
		alpha: PassList.forPhase(Phase.Alpha),
		additive: PassList.forPhase(Phase.Additive),
		cameraBlock: cameraBlock,
		lightBlock: lightBlock,
		sceneGlobals: [cameraBlock, lightBlock],
		programs: programs,
		drawn: [],
		screenMesh: addMesh(context, screenMesh(0)),
		generation: 0,
		changed: true,
	});
}

// For whatever the renderer cannot see: the items moved, a material or a light changed.
export function markChanged(ref renderer: Renderer): void {
	renderer.changed = true;
}

// Whether the next frame could differ from the last one drawn: something was marked changed
// or the GPU context is new. A preset adds its own inputs (the view, its settings).
export function needsFrame(this renderer: Renderer): boolean {
	return renderer.changed || renderer.generation != contextGeneration();
}

// Starts a frame: uploads the camera and lights, adopts a new GPU context if there is one and
// fills the pass lists from `items`. A camera or light span that is not its block's length, an
// item whose material names a program this renderer does not draw, or a material whose block is
// not the one that program reads, is refused before anything changes. Answers true when the
// context is new: every handle the caller made before is stale then (it may name an object of
// the new context), so the caller drops its own without destroying them and makes them again
// before drawing. The core has already dropped the pipelines, remade the screen triangle, and
// re-uploaded every mesh that carries its CPU data (draw.ms rebuildMeshes); what is left is
// whatever the caller uploaded from buffers only it keeps.
export function beginFrame(
	ref renderer: Renderer,
	ref context: DrawContext,
	items: Span<DrawItem>,
	camera: Span<float32>,
	lights: Span<float32>,
): Result<boolean, RendererError> {
	while ((renderer.drawn.length as int32) < (items.length as int32)) {
		renderer.drawn.push(Program.Lit);
	}
	for (let i = 0; i < (items.length as int32); i++) {
		const material: int32 = items[i].material;
		const drawn: Result<Program, ProgramError> =
			renderer.programs.drawnFor(context.materials[material].program);
		if (!drawn.ok) { return Result.err(RendererError.ProgramNotDrawn); }
		if (!blockFits(drawn.value, context.materials[material].uniforms)) {
			return Result.err(RendererError.MaterialBlock);
		}
		renderer.drawn[i] = drawn.value;
	}
	if (!writeUniforms(context, renderer.cameraBlock, camera).ok) {
		return Result.err(RendererError.CameraBlockLength);
	}
	if (!writeUniforms(context, renderer.lightBlock, lights).ok) {
		return Result.err(RendererError.LightBlockLength);
	}
	const generation: int32 = contextGeneration();
	const fresh: boolean = generation != renderer.generation;
	if (fresh) {
		forgetPipelines(context.pipelines);
		rebuildMeshes(context);
		context.meshes[renderer.screenMesh].vertexBuffer = makeScreenTriangle();
		renderer.generation = generation;
		renderer.changed = true;
	}
	collect(renderer.opaque, items, context.materials);
	collect(renderer.alpha, items, context.materials);
	collect(renderer.additive, items, context.materials);
	sortBackToFront(renderer.alpha, items, camera);
	return Result.ok(fresh);
}

// fwd.Renderer's default, alpha and additive passes, into the current pass (`targets` is
// its attachment layout), with the camera and lights applied to every item and each drawn with
// the program beginFrame resolved for it.
export function drawPassLists(
	ref renderer: Renderer,
	ref context: DrawContext,
	items: Span<DrawItem>,
	targets: TargetLayout,
): void {
	drawPassList(context, renderer.opaque, items, renderer.drawn, targets, renderer.sceneGlobals);
	drawPassList(context, renderer.alpha, items, renderer.drawn, targets, renderer.sceneGlobals);
	drawPassList(context, renderer.additive, items, renderer.drawn, targets, renderer.sceneGlobals);
}

// ScreenFx.render: `material` (a Fullscreen-layout material in `context`, drawn with its own
// program) over the whole current pass.
export function drawScreen(
	ref renderer: Renderer,
	ref context: DrawContext,
	material: int32,
	targets: TargetLayout,
): void {
	const program: Program = context.materials[material].program;
	drawItem(context, screenItem(renderer.screenMesh, material), program, targets, NO_GLOBALS);
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

export function endFrame(ref renderer: Renderer): void {
	commit();
	renderer.changed = false;
}
