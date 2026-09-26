import { Mat4, Vec4, identity } from "../math/math3d";
import {
	Program,
	VERTEX_UNIFORM_SLOT,
	VERTEX_UNIFORM_LENGTH,
	LIGHT_UNIFORM_SLOT,
	LIGHT_UNIFORM_LENGTH,
	MATERIAL_UNIFORM_SLOT,
	MATERIAL_UNIFORM_LENGTH,
	VertexLayout,
	BILLBOARD_UNIFORM_SLOT,
	BILLBOARD_UNIFORM_LENGTH,
	UNIFORM_SLOTS,
	uniformBlockLength,
} from "../void3d/gpu3d";
import { RenderState } from "../void3d/pass";
import { Material, Phase, UniformBlock } from "../void3d/material";
import {
	DrawContext,
	DrawItem,
	GpuMesh,
	MODEL_SLOT,
	MODEL_LENGTH,
	UniformError,
	addMesh,
	addMaterial,
	reserveUniforms,
} from "../void3d/draw";
import { ProgramMap, ProgramError } from "../void3d/programMap";
import { Renderer, RendererError, RENDERER_UNIFORM_LENGTH, beginFrame } from "../void3d/renderer";
import {
	POST_UNIFORM_SLOT,
	POST_UNIFORM_LENGTH,
	BLIT_UNIFORM_SLOT,
	BLIT_UNIFORM_LENGTH,
	pixelArtPrograms,
} from "../void3d/pixelArtRenderer";
import {
	ForwardRenderer,
	ForwardError,
	FORWARD_UNIFORM_LENGTH,
	renderFrame,
} from "../void3d/forwardRenderer";

const EVERY_PROGRAM: Vec<Program> = [
	Program.Lit,
	Program.Particle,
	Program.Billboard,
	Program.Copy,
	Program.PixelArtLit,
	Program.PixelArtParticle,
	Program.PixelArtBillboard,
	Program.PixelArtPost,
	Program.PixelArtBlit,
];

function drawnAs(map: ProgramMap, named: Program): Program {
	const drawn: Result<Program, ProgramError> = map.drawnFor(named);
	if (drawn.ok) { return drawn.value; }
	console.log(`${named.toString()} is not drawn`);
	unreachable;
}

function namedCount(map: ProgramMap): int32 {
	let count: int32 = 0;
	for (const program of EVERY_PROGRAM) {
		if (map.draws(program)) { count = count + 1; }
	}
	return count;
}

function contextNaming(program: Program, capacity: int32): DrawContext {
	let context: DrawContext = DrawContext.withUniformCapacity(capacity);
	addMaterial(context, Material.plain(program, RenderState.defaults(), Phase.Opaque));
	return context;
}

function itemOf(material: int32): DrawItem {
	const world: Mat4 = identity();
	return { mesh: 0, material: material, world: world };
}

test "the core draws a material's Lit, Particle and Billboard as themselves, and nothing else" {
	const core: ProgramMap = ProgramMap.core();
	assert drawnAs(core, Program.Lit) == Program.Lit;
	assert drawnAs(core, Program.Particle) == Program.Particle;
	assert drawnAs(core, Program.Billboard) == Program.Billboard;
	assert namedCount(core) == 3;
	const preset: Result<Program, ProgramError> = core.drawnFor(Program.PixelArtBillboard);
	assert !preset.ok && preset.error == ProgramError.NotDrawn;
}

test "the pixel-art preset draws its own programs in place of the ones materials name" {
	const preset: ProgramMap = pixelArtPrograms();
	assert drawnAs(preset, Program.Lit) == Program.PixelArtLit;
	assert drawnAs(preset, Program.Particle) == Program.PixelArtParticle;
	assert drawnAs(preset, Program.Billboard) == Program.PixelArtBillboard;
	assert namedCount(preset) == 3;
	assert !preset.draws(Program.PixelArtLit) && !preset.draws(Program.Copy);
	assert !preset.draws(Program.PixelArtBillboard);
}

test "drawing a name again replaces what is drawn for it and leaves the others" {
	const map: ProgramMap = ProgramMap.empty()
		.drawing(Program.PixelArtBlit, Program.PixelArtBlit)
		.drawing(Program.Lit, Program.PixelArtBlit)
		.drawing(Program.Particle, Program.Copy)
		.drawing(Program.Lit, Program.PixelArtLit);
	assert drawnAs(map, Program.Lit) == Program.PixelArtLit;
	assert drawnAs(map, Program.Particle) == Program.Copy;
	assert drawnAs(map, Program.PixelArtBlit) == Program.PixelArtBlit;
	assert namedCount(map) == 3;
	assert namedCount(ProgramMap.empty()) == 0;
}

test "the core refuses a material it does not draw before it writes the camera" {
	let context: DrawContext = contextNaming(Program.PixelArtBillboard, RENDERER_UNIFORM_LENGTH);
	const created: Result<Renderer, RendererError> = Renderer.create(context);
	assert created.ok;
	if (created.ok) {
		let core: Renderer = created.value;
		const items: Vec<DrawItem> = [itemOf(0)];
		const camera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
		camera[0] = 7.0;
		const lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
		const began: Result<boolean, RendererError> =
			beginFrame(core, context, items, camera, lights);
		assert !began.ok && began.error == RendererError.ProgramNotDrawn;
		assert context.uniforms[core.cameraBlock.offset] == 0.0 && core.generation == 0;
	}
}

test "the forward preset takes the core's blocks and a copy material and draws core programs" {
	let small: DrawContext = DrawContext.withUniformCapacity(FORWARD_UNIFORM_LENGTH - 1);
	const background: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };
	const refused: Result<ForwardRenderer, ForwardError> =
		ForwardRenderer.create(small, background);
	assert !refused.ok && refused.error == ForwardError.UniformPoolFull;
	let context: DrawContext = contextNaming(Program.PixelArtBillboard, FORWARD_UNIFORM_LENGTH);
	const created: Result<ForwardRenderer, ForwardError> =
		ForwardRenderer.create(context, background);
	assert created.ok;
	if (created.ok) {
		let forward: ForwardRenderer = created.value;
		assert context.uniformsUsed == FORWARD_UNIFORM_LENGTH;
		assert context.materials[forward.copyMaterial].program == Program.Copy;
		assert forward.core.programs.draws(Program.Lit);
		assert forward.core.programs.draws(Program.Billboard);
		assert !forward.core.programs.draws(Program.Copy);
		const items: Vec<DrawItem> = [itemOf(0)];
		const camera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
		const lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
		const unsized: Result<int32, ForwardError> =
			renderFrame(forward, context, items, camera, lights, 0, 480);
		assert !unsized.ok && unsized.error == ForwardError.TargetSize;
		const preset: Result<int32, ForwardError> =
			renderFrame(forward, context, items, camera, lights, 640, 480);
		assert !preset.ok && preset.error == ForwardError.ProgramNotDrawn;
		assert forward.core.generation == 0 && forward.colorTarget.image == 0;
	}
}

function declaredSlots(program: Program): int32 {
	let count: int32 = 0;
	for (let slot = 0; slot < UNIFORM_SLOTS; slot++) {
		if (uniformBlockLength(program, slot) > 0) { count = count + 1; }
	}
	return count;
}

test "every block the CPU writes is the length its shader declares, read off the shader desc" {
	for (const lit of [Program.Lit, Program.PixelArtLit]) {
		assert uniformBlockLength(lit, VERTEX_UNIFORM_SLOT) == VERTEX_UNIFORM_LENGTH;
		assert uniformBlockLength(lit, LIGHT_UNIFORM_SLOT) == LIGHT_UNIFORM_LENGTH;
		assert uniformBlockLength(lit, MATERIAL_UNIFORM_SLOT) == MATERIAL_UNIFORM_LENGTH;
		assert uniformBlockLength(lit, MODEL_SLOT) == MODEL_LENGTH;
		assert declaredSlots(lit) == 4;
	}
	for (const billboard of [Program.Billboard, Program.PixelArtBillboard]) {
		assert uniformBlockLength(billboard, VERTEX_UNIFORM_SLOT) == VERTEX_UNIFORM_LENGTH;
		assert uniformBlockLength(billboard, LIGHT_UNIFORM_SLOT) == LIGHT_UNIFORM_LENGTH;
		assert uniformBlockLength(billboard, BILLBOARD_UNIFORM_SLOT) == BILLBOARD_UNIFORM_LENGTH;
		assert declaredSlots(billboard) == 3;
	}
	assert declaredSlots(Program.Particle) == 1 && declaredSlots(Program.PixelArtParticle) == 1;
	assert uniformBlockLength(Program.PixelArtPost, POST_UNIFORM_SLOT) == POST_UNIFORM_LENGTH;
	assert uniformBlockLength(Program.PixelArtBlit, BLIT_UNIFORM_SLOT) == BLIT_UNIFORM_LENGTH;
	assert declaredSlots(Program.Copy) == 0;
	assert uniformBlockLength(Program.Lit, UNIFORM_SLOTS) == 0;
}

test "the core refuses a lit material without its block, or on a mesh of another layout" {
	let bare: DrawContext = contextNaming(Program.Lit, RENDERER_UNIFORM_LENGTH);
	const bareCore: Result<Renderer, RendererError> = Renderer.create(bare);
	assert bareCore.ok;
	const camera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
	const shortCamera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH - 1);
	const lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
	const items: Vec<DrawItem> = [itemOf(0)];
	if (bareCore.ok) {
		let core: Renderer = bareCore.value;
		const began: Result<boolean, RendererError> = beginFrame(core, bare, items, camera, lights);
		assert !began.ok && began.error == RendererError.MaterialBlock;
	}
	let held: DrawContext =
		DrawContext.withUniformCapacity(RENDERER_UNIFORM_LENGTH + MATERIAL_UNIFORM_LENGTH);
	const block: Result<UniformBlock, UniformError> =
		reserveUniforms(held, MATERIAL_UNIFORM_SLOT, MATERIAL_UNIFORM_LENGTH);
	assert block.ok;
	if (block.ok) {
		addMaterial(held, {
			...Material.plain(Program.Lit, RenderState.defaults(), Phase.Opaque),
			uniforms: block.value,
		});
	}
	const heldCore: Result<Renderer, RendererError> = Renderer.create(held);
	assert heldCore.ok;
	const litMesh: int32 = addMesh(held, GpuMesh.external(VertexLayout.Lit, 0, 0, 6, 1));
	const litItems: Vec<DrawItem> = [{ ...itemOf(0), mesh: litMesh }];
	if (heldCore.ok) {
		let core: Renderer = heldCore.value;
		const onScreen: Result<boolean, RendererError> =
			beginFrame(core, held, items, shortCamera, lights);
		assert !onScreen.ok && onScreen.error == RendererError.VertexLayout;
		const began: Result<boolean, RendererError> =
			beginFrame(core, held, litItems, shortCamera, lights);
		assert !began.ok && began.error == RendererError.CameraBlockLength;
		assert core.drawn.length == 0 && held.uniforms[core.cameraBlock.offset] == 0.0;
	}
}

test "the forward preset refuses a lit material without its block" {
	let context: DrawContext = contextNaming(Program.Lit, FORWARD_UNIFORM_LENGTH);
	const background: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };
	const created: Result<ForwardRenderer, ForwardError> =
		ForwardRenderer.create(context, background);
	assert created.ok;
	if (created.ok) {
		let forward: ForwardRenderer = created.value;
		const items: Vec<DrawItem> = [itemOf(0)];
		const camera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
		const lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
		const refused: Result<int32, ForwardError> =
			renderFrame(forward, context, items, camera, lights, 640, 480);
		assert !refused.ok && refused.error == ForwardError.MaterialBlock;
	}
}
