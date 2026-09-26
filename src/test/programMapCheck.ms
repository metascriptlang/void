import { Mat4, Vec4, identity } from "../math/math3d";
import {
	Program,
	VERTEX_UNIFORM_LENGTH,
	LIGHT_UNIFORM_LENGTH,
} from "../void3d/gpu3d";
import { RenderState } from "../void3d/pass";
import { Material, Phase } from "../void3d/material";
import { DrawContext, DrawItem, addMaterial } from "../void3d/draw";
import { ProgramMap, ProgramError } from "../void3d/programMap";
import { Renderer, RendererError, RENDERER_UNIFORM_LENGTH, beginFrame } from "../void3d/renderer";
import { pixelArtPrograms } from "../void3d/pixelArtRenderer";
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

test "the core draws a material's Lit and Particle as themselves, and nothing else" {
	const core: ProgramMap = ProgramMap.core();
	assert drawnAs(core, Program.Lit) == Program.Lit;
	assert drawnAs(core, Program.Particle) == Program.Particle;
	assert namedCount(core) == 2;
	const billboard: Result<Program, ProgramError> = core.drawnFor(Program.Billboard);
	assert !billboard.ok && billboard.error == ProgramError.NotDrawn;
}

test "the pixel-art preset draws its own programs in place of the ones materials name" {
	const preset: ProgramMap = pixelArtPrograms();
	assert drawnAs(preset, Program.Lit) == Program.PixelArtLit;
	assert drawnAs(preset, Program.Particle) == Program.PixelArtParticle;
	assert drawnAs(preset, Program.Billboard) == Program.Billboard;
	assert namedCount(preset) == 3;
	assert !preset.draws(Program.PixelArtLit) && !preset.draws(Program.Copy);
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
	let context: DrawContext = contextNaming(Program.Billboard, RENDERER_UNIFORM_LENGTH);
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
	let context: DrawContext = contextNaming(Program.Billboard, FORWARD_UNIFORM_LENGTH);
	const created: Result<ForwardRenderer, ForwardError> =
		ForwardRenderer.create(context, background);
	assert created.ok;
	if (created.ok) {
		let forward: ForwardRenderer = created.value;
		assert context.uniformsUsed == FORWARD_UNIFORM_LENGTH;
		assert context.materials[forward.copyMaterial].program == Program.Copy;
		assert forward.core.programs.draws(Program.Lit);
		assert !forward.core.programs.draws(Program.Copy);
		const items: Vec<DrawItem> = [itemOf(0)];
		const camera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
		const lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
		const unsized: Result<int32, ForwardError> =
			renderFrame(forward, context, items, camera, lights, 0, 480);
		assert !unsized.ok && unsized.error == ForwardError.TargetSize;
		const billboard: Result<int32, ForwardError> =
			renderFrame(forward, context, items, camera, lights, 640, 480);
		assert !billboard.ok && billboard.error == ForwardError.ProgramNotDrawn;
		assert forward.core.generation == 0 && forward.colorTarget.image == 0;
	}
}
