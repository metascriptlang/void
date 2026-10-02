import { Mat4, Vec4, identity } from "../math/math3d";
import {
	Program,
	VERTEX_UNIFORM_SLOT,
	VERTEX_UNIFORM_LENGTH,
	LIGHT_UNIFORM_SLOT,
	LIGHT_UNIFORM_LENGTH,
	MATERIAL_UNIFORM_SLOT,
	MATERIAL_UNIFORM_LENGTH,
	BILLBOARD_UNIFORM_SLOT,
	BILLBOARD_UNIFORM_LENGTH,
	uniformBlockLength,
} from "../void3d/gpu3d";
import { UNIFORM_SLOTS } from "../gpu/door";
import { RenderState } from "../gpu/state";
import { MeshData } from "../void3d/meshData";
import { Material, Phase, UniformBlock, NO_UNIFORMS } from "../void3d/material";
import {
	DrawContext,
	DrawItem,
	GpuMesh,
	MeshId,
	MaterialId,
	MaterialError,
	MODEL_SLOT,
	MODEL_LENGTH,
	addMesh,
	addMaterial,
	releaseMaterial,
	releaseMesh,
	releaseUniforms,
	reserveUniforms,
} from "../void3d/draw";
import { UniformError } from "../void3d/uniformPool";
import { added, litShape } from "./drawHelpers";
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
	Program.LitTextured,
	Program.PixelArtLitTextured,
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
	const plain: Material = Material.plain(program, RenderState.defaults(), Phase.Opaque);
	const _named: Result<MaterialId, MaterialError> = addMaterial(context, plain);
	return context;
}

function firstMaterial(context: DrawContext): MaterialId {
	return { store: context.serial, index: 0, generation: 1 };
}

// Drawn with the first mesh of its context, which a renderer adds when it is made (its screen
// triangle).
function itemOf(context: DrawContext, material: MaterialId): DrawItem {
	const world: Mat4 = identity();
	return {
		mesh: { store: context.serial, index: 0, generation: 1 },
		material: material,
		world: world,
	};
}

// A billboard material over a block of its own, from what `context` has left.
function billboardMaterial(context: DrawContext, texture: uint32, sampler: uint32): MaterialId {
	const block: UniformBlock =
		try reserveUniforms(
			context,
			BILLBOARD_UNIFORM_SLOT,
			BILLBOARD_UNIFORM_LENGTH,
		) catch NO_UNIFORMS;
	const added: Result<MaterialId, MaterialError> = addMaterial(context, {
		...Material.plain(Program.Billboard, RenderState.defaults(), Phase.Opaque),
		texture0: texture,
		sampler0: sampler,
		uniforms: block,
	});
	if (!added.ok) { unreachable; }
	return added.value;
}

test "the core draws a material's Lit, Particle, Billboard and LitTextured as themselves" {
	const core: ProgramMap = ProgramMap.core();
	assert drawnAs(core, Program.Lit) == Program.Lit;
	assert drawnAs(core, Program.Particle) == Program.Particle;
	assert drawnAs(core, Program.Billboard) == Program.Billboard;
	assert drawnAs(core, Program.LitTextured) == Program.LitTextured;
	assert namedCount(core) == 4;
	const preset: Result<Program, ProgramError> = core.drawnFor(Program.PixelArtBillboard);
	assert !preset.ok && preset.error == ProgramError.NotDrawn;
}

test "the pixel-art preset draws its own programs in place of the ones materials name" {
	const preset: ProgramMap = pixelArtPrograms();
	assert drawnAs(preset, Program.Lit) == Program.PixelArtLit;
	assert drawnAs(preset, Program.Particle) == Program.PixelArtParticle;
	assert drawnAs(preset, Program.Billboard) == Program.PixelArtBillboard;
	assert drawnAs(preset, Program.LitTextured) == Program.PixelArtLitTextured;
	assert namedCount(preset) == 4;
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
		const items: Vec<DrawItem> = [itemOf(context, firstMaterial(context))];
		let camera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
		camera[0] = 7.0;
		const lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
		const began: Result<boolean, RendererError> =
			beginFrame(core, items, camera, lights);
		assert !began.ok && began.error == RendererError.ProgramNotDrawn;
		assert context.uniforms.values[core.cameraBlock.offset] == 0.0 && core.generation == 0;
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
		assert context.uniforms.used == FORWARD_UNIFORM_LENGTH;
		assert context.materials[forward.copyMaterial.index].program == Program.Copy;
		assert forward.core.programs.draws(Program.Lit);
		assert forward.core.programs.draws(Program.Billboard);
		assert !forward.core.programs.draws(Program.Copy);
		const items: Vec<DrawItem> = [itemOf(context, firstMaterial(context))];
		const camera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
		const lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
		const unsized: Result<int32, ForwardError> =
			renderFrame(forward, items, camera, lights, 0, 480);
		assert !unsized.ok && unsized.error == ForwardError.TargetSize;
		const preset: Result<int32, ForwardError> =
			renderFrame(forward, items, camera, lights, 640, 480);
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
	for (const lit of [
		Program.Lit,
		Program.PixelArtLit,
		Program.LitTextured,
		Program.PixelArtLitTextured,
	]) {
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
	const items: Vec<DrawItem> = [itemOf(bare, firstMaterial(bare))];
	if (bareCore.ok) {
		let core: Renderer = bareCore.value;
		const began: Result<boolean, RendererError> = beginFrame(core, items, camera, lights);
		assert !began.ok && began.error == RendererError.MaterialBlock;
	}
	let held: DrawContext =
		DrawContext.withUniformCapacity(RENDERER_UNIFORM_LENGTH + MATERIAL_UNIFORM_LENGTH);
	const block: Result<UniformBlock, UniformError> =
		reserveUniforms(held, MATERIAL_UNIFORM_SLOT, MATERIAL_UNIFORM_LENGTH);
	assert block.ok;
	if (block.ok) {
		const _lit: Result<MaterialId, MaterialError> = addMaterial(held, {
			...Material.plain(Program.Lit, RenderState.defaults(), Phase.Opaque),
			uniforms: block.value,
		});
	}
	const heldCore: Result<Renderer, RendererError> = Renderer.create(held);
	assert heldCore.ok;
	const litMesh: MeshId = added(held, litShape());
	const heldItems: Vec<DrawItem> = [itemOf(held, firstMaterial(held))];
	const litItems: Vec<DrawItem> = [{ ...heldItems[0], mesh: litMesh }];
	if (heldCore.ok) {
		let core: Renderer = heldCore.value;
		const onScreen: Result<boolean, RendererError> =
			beginFrame(core, heldItems, shortCamera, lights);
		assert !onScreen.ok && onScreen.error == RendererError.VertexLayout;
		const began: Result<boolean, RendererError> =
			beginFrame(core, litItems, shortCamera, lights);
		assert !began.ok && began.error == RendererError.CameraBlockLength;
		assert core.drawn.length == 0 && held.uniforms.values[core.cameraBlock.offset] == 0.0;
	}
}

test "the core refuses a billboard without its texture and sampler, or off the quad's shape" {
	const capacity: int32 = RENDERER_UNIFORM_LENGTH + BILLBOARD_UNIFORM_LENGTH;
	let context: DrawContext = DrawContext.withUniformCapacity(capacity);
	const created: Result<Renderer, RendererError> = Renderer.create(context);
	assert created.ok;
	if (created.ok) {
		let core: Renderer = created.value;
		const quads: MeshId = added(context, GpuMesh.billboards(9, 1));
		const camera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
		const shortCamera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH - 1);
		const lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
		const textures: Vec<uint32> = [0, 5];
		for (const texture of textures) {
			const unsampled: MaterialId = billboardMaterial(context, texture, 0);
			const items: Vec<DrawItem> = [{ ...itemOf(context, unsampled), mesh: quads }];
			const began: Result<boolean, RendererError> =
				beginFrame(core, items, camera, lights);
			assert !began.ok && began.error == RendererError.MaterialTexture;
			assert releaseMaterial(context, unsampled).ok;
		}
		const cornered: GpuMesh = { ...GpuMesh.billboards(9, 1), vertexBuffer: 7 };
		const unbuffered: GpuMesh = GpuMesh.billboards(0, 1);
		const strip: GpuMesh = { ...GpuMesh.billboards(9, 1), vertexCount: 4 };
		const material: MaterialId = billboardMaterial(context, 5, 6);
		for (const offShape of [cornered, unbuffered, strip]) {
			const mesh: MeshId = added(context, offShape);
			const offItems: Vec<DrawItem> = [{ ...itemOf(context, material), mesh: mesh }];
			const refused: Result<boolean, RendererError> =
				beginFrame(core, offItems, camera, lights);
			assert !refused.ok && refused.error == RendererError.QuadMesh;
		}
		const unwritten: MeshId = added(context, GpuMesh.billboards(0, 0));
		const emptyItems: Vec<DrawItem> = [{ ...itemOf(context, material), mesh: unwritten }];
		const empty: Result<boolean, RendererError> =
			beginFrame(core, emptyItems, shortCamera, lights);
		assert !empty.ok && empty.error == RendererError.CameraBlockLength;
		const items: Vec<DrawItem> = [{ ...itemOf(context, material), mesh: quads }];
		const began: Result<boolean, RendererError> =
			beginFrame(core, items, shortCamera, lights);
		assert !began.ok && began.error == RendererError.CameraBlockLength;
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
		const items: Vec<DrawItem> = [itemOf(context, firstMaterial(context))];
		const camera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
		const lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
		const refused: Result<int32, ForwardError> =
			renderFrame(forward, items, camera, lights, 640, 480);
		assert !refused.ok && refused.error == ForwardError.MaterialBlock;
	}
}

test "the forward preset refuses a frame once its own copy material or screen mesh is gone" {
	let context: DrawContext = contextNaming(Program.Lit, FORWARD_UNIFORM_LENGTH);
	const created: Result<ForwardRenderer, ForwardError> =
		ForwardRenderer.create(context, { x: 0.0, y: 0.0, z: 0.0, w: 1.0 });
	assert created.ok;
	if (!created.ok) { return; }
	let forward: ForwardRenderer = created.value;
	const camera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
	const lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
	const none: Vec<DrawItem> = [];
	assert releaseMesh(context, forward.core.screenMesh).ok;
	const noScreen: Result<int32, ForwardError> =
		renderFrame(forward, none, camera, lights, 64, 64);
	assert !noScreen.ok && noScreen.error == ForwardError.StaleMesh;
	assert releaseMaterial(context, forward.copyMaterial).ok;
	const noCopy: Result<int32, ForwardError> =
		renderFrame(forward, none, camera, lights, 64, 64);
	assert !noCopy.ok && noCopy.error == ForwardError.StaleMaterial;
	assert forward.core.generation == 0;
}

test "the core owns its camera and light blocks, so only it could give them back" {
	let context: DrawContext = DrawContext.withUniformCapacity(RENDERER_UNIFORM_LENGTH);
	const created: Result<Renderer, RendererError> = Renderer.create(context);
	assert created.ok;
	if (!created.ok) { return; }
	const camera: Result<int32, UniformError> = releaseUniforms(context, created.value.cameraBlock);
	assert !camera.ok && camera.error == UniformError.Owned;
	const lights: Result<int32, UniformError> = releaseUniforms(context, created.value.lightBlock);
	assert !lights.ok && lights.error == UniformError.Owned;
}
