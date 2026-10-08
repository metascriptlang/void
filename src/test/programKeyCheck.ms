import { approx } from "./helpers";
import { Mat4, Vec4, identity } from "../math/math3d";
import {
	Program,
	ProgramKey,
	Preset,
	ProgramError,
	VertexLayout,
	drawnIn,
	castIn,
	declares,
	textureSlotMask,
	samplerSlotMask,
	movingBase,
	FRAME_UNIFORM_SLOT,
	FRAME_UNIFORM_LENGTH,
	MOVING_UV_MATRIX,
	MOVING_BACK_UV_MATRIX,
	MOVING_MATERIAL_UNIFORM_LENGTH,
	MOVING_UNLIT_MATERIAL_UNIFORM_LENGTH,
	UNLIT_MATERIAL_UNIFORM_LENGTH,
	UNLIT_MATERIAL_COLOR,
	BACK_VIEW_SLOT,
	DISSOLVE_VIEW_SLOT,
	DISSOLVE_SAMPLER_SLOT,
	EMISSIVE_VIEW_SLOT,
	NORMAL_VIEW_SLOT,
	EMISSIVE_LENGTH,
	emissiveBase,
	MOVING_LENGTH,
	VERTEX_UNIFORM_SLOT,
	VERTEX_UNIFORM_LENGTH,
	LIGHT_UNIFORM_SLOT,
	LIGHT_UNIFORM_LENGTH,
	MATERIAL_UNIFORM_SLOT,
	MATERIAL_UNIFORM_LENGTH,
	BILLBOARD_UNIFORM_SLOT,
	BILLBOARD_UNIFORM_LENGTH,
	uniformBlockLength,
	vertexLayoutOf,
	MATERIAL_ALPHA_KILL,
} from "../void3d/gpu3d";
import { UNIFORM_SLOTS } from "../gpu/door";
import { RenderState, BlendMode } from "../gpu/state";
import { MeshData } from "../void3d/meshData";
import { Material, Phase, UniformBlock, NO_UNIFORMS, movingDefaults } from "../void3d/material";
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
	writeUniforms,
} from "../void3d/draw";
import { UniformError } from "../void3d/uniformPool";
import { added, litShape } from "./drawHelpers";
import {
	Renderer, RendererError, RENDERER_UNIFORM_LENGTH, beginFrame, setElapsedTime, setTimeWrap,
	setExposure,
	exposureMultiplier,
	frameTime,
} from "../void3d/renderer";
import {
	POST_UNIFORM_SLOT,
	POST_UNIFORM_LENGTH,
	BLIT_UNIFORM_SLOT,
	BLIT_UNIFORM_LENGTH,
} from "../void3d/pixelArtRenderer";
import {
	ForwardRenderer,
	ForwardError,
	FORWARD_UNIFORM_LENGTH,
	renderFrame,
} from "../void3d/forwardRenderer";

function pixelArt(program: Program): ProgramKey {
	return ProgramKey.of(program).withPreset(Preset.PixelArt);
}

function drawnAs(key: ProgramKey, preset: Preset): ProgramKey {
	const drawn: Result<ProgramKey, ProgramError> = drawnIn(key, preset, false);
	if (drawn.ok) { return drawn.value; }
	console.log(`${key.describe()} is not drawn in ${preset.toString()}`);
	unreachable;
}

function contextNaming(program: ProgramKey, capacity: int32): DrawContext {
	let context: DrawContext = DrawContext.withUniformCapacity(capacity);
	const plain: Material = Material.keyed(program, RenderState.defaults(), Phase.Opaque);
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
		...Material.keyed(cutBillboard(), RenderState.defaults(), Phase.Opaque),
		texture0: texture,
		sampler0: sampler,
		uniforms: block,
	});
	if (!added.ok) { unreachable; }
	return added.value;
}

const EVERY_PROGRAM: Vec<Program> = [
	Program.Lit, Program.Particle, Program.Billboard, Program.Copy, Program.Post, Program.Blit,
	Program.LitTextured, Program.UnlitTextured,
];

const SCENE_PROGRAMS: Vec<Program> = [
	Program.Lit, Program.Particle, Program.Billboard, Program.LitTextured, Program.UnlitTextured,
];

function layoutFor(key: ProgramKey): VertexLayout {
	if (key.normalMap) { return VertexLayout.LitTexturedTangent; }
	return match (key.program) {
		Program.Lit => VertexLayout.Lit,
		Program.Particle => VertexLayout.Particle,
		Program.Billboard => VertexLayout.Billboard,
		Program.Copy => VertexLayout.Fullscreen,
		Program.Post => VertexLayout.Fullscreen,
		Program.Blit => VertexLayout.Fullscreen,
		Program.LitTextured => VertexLayout.LitTextured,
		Program.UnlitTextured => VertexLayout.LitTextured,
	};
}

function everyKey(): Vec<ProgramKey> {
	let keys: Vec<ProgramKey> = [];
	for (const program of EVERY_PROGRAM) {
		for (const preset of [Preset.Core, Preset.PixelArt, Preset.Shadow]) {
			for (const premultiplied of [false, true]) {
				for (const cutout of [false, true]) {
					for (const shadowed of [false, true]) {
						for (let features = 0; features < 32; features++) {
							keys.push({
								program: program, preset: preset,
								premultiplied: premultiplied, cutout: cutout, shadowed: shadowed,
								uvTransform: (features & 1) != 0, backTexture: (features & 2) != 0,
								dissolve: (features & 4) != 0, emissive: (features & 8) != 0,
								normalMap: (features & 16) != 0,
							});
						}
					}
				}
			}
		}
	}
	return keys;
}

test "every key packs to bits of its own, and each declared one reads its program's layout" {
	let seen: Vec<boolean> = [];
	for (let bits = 0; bits < 16384; bits++) { seen.push(false); }
	let declared: int32 = 0;
	for (const key of everyKey()) {
		const bits: int32 = key.bits();
		assert bits >= 0 && bits < 16384 && !seen[bits];
		seen[bits] = true;
		if (declares(key)) {
			declared = declared + 1;
			assert vertexLayoutOf(key) == layoutFor(key);
		}
	}
	assert declared == 88;
}

test "both presets draw every scene program's key in their own, and no screen program" {
	for (const program of SCENE_PROGRAMS) {
		const key: ProgramKey = ProgramKey.of(program);
		assert drawnAs(key, Preset.Core) == key;
		assert drawnAs(key, Preset.PixelArt) == pixelArt(program);
	}
	const screens: Vec<ProgramKey> =
		[ProgramKey.of(Program.Copy), pixelArt(Program.Post), pixelArt(Program.Blit)];
	for (const screen of screens) {
		assert declares(screen);
		for (const preset of [Preset.Core, Preset.PixelArt]) {
			const drawn: Result<ProgramKey, ProgramError> = drawnIn(screen, preset, false);
			assert !drawn.ok && drawn.error == ProgramError.NotDrawn;
		}
	}
	const named: Result<ProgramKey, ProgramError> =
		drawnIn(pixelArt(Program.Lit), Preset.PixelArt, false);
	assert !named.ok && named.error == ProgramError.NotDrawn;
}

test "a material whose key the build does not declare is refused when it is added" {
	let context: DrawContext = DrawContext.withUniformCapacity(0);
	const copy: Material = Material.keyed(pixelArt(Program.Copy), RenderState.defaults(),
		Phase.Opaque);
	const refused: Result<MaterialId, MaterialError> = addMaterial(context, copy);
	assert !refused.ok && refused.error == MaterialError.UndeclaredProgram;
	assert context.liveMaterials() == 0;
}

test "the core refuses a material it does not draw before it writes the camera" {
	let context: DrawContext = contextNaming(pixelArt(Program.Billboard), RENDERER_UNIFORM_LENGTH);
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
	let context: DrawContext = contextNaming(pixelArt(Program.Billboard), FORWARD_UNIFORM_LENGTH);
	const created: Result<ForwardRenderer, ForwardError> =
		ForwardRenderer.create(context, background);
	assert created.ok;
	if (created.ok) {
		let forward: ForwardRenderer = created.value;
		assert context.uniforms.used == FORWARD_UNIFORM_LENGTH;
		assert context.materials[forward.copyMaterial.index].program ==
			ProgramKey.of(Program.Copy);
		assert forward.core.preset == Preset.Core;
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

function declaredSlots(program: ProgramKey): int32 {
	let count: int32 = 0;
	for (let slot = 0; slot < UNIFORM_SLOTS; slot++) {
		if (uniformBlockLength(program, slot) > 0) { count = count + 1; }
	}
	return count;
}

test "every block the CPU writes is the length its shader declares, read off the shader desc" {
	for (const lit of [
		ProgramKey.of(Program.Lit),
		pixelArt(Program.Lit),
		ProgramKey.of(Program.LitTextured),
		pixelArt(Program.LitTextured),
	]) {
		assert uniformBlockLength(lit, VERTEX_UNIFORM_SLOT) == VERTEX_UNIFORM_LENGTH;
		assert uniformBlockLength(lit, LIGHT_UNIFORM_SLOT) == LIGHT_UNIFORM_LENGTH;
		assert uniformBlockLength(lit, MATERIAL_UNIFORM_SLOT) == MATERIAL_UNIFORM_LENGTH;
		assert uniformBlockLength(lit, MODEL_SLOT) == MODEL_LENGTH;
		assert uniformBlockLength(lit, FRAME_UNIFORM_SLOT) == FRAME_UNIFORM_LENGTH;
		assert declaredSlots(lit) == 5;
	}
	for (const billboard of [ProgramKey.of(Program.Billboard), pixelArt(Program.Billboard)]) {
		assert uniformBlockLength(billboard, VERTEX_UNIFORM_SLOT) == VERTEX_UNIFORM_LENGTH;
		assert uniformBlockLength(billboard, LIGHT_UNIFORM_SLOT) == LIGHT_UNIFORM_LENGTH;
		assert uniformBlockLength(billboard, BILLBOARD_UNIFORM_SLOT) == BILLBOARD_UNIFORM_LENGTH;
		assert uniformBlockLength(billboard, FRAME_UNIFORM_SLOT) == FRAME_UNIFORM_LENGTH;
		assert declaredSlots(billboard) == 4;
	}
	for (const particle of [ProgramKey.of(Program.Particle), pixelArt(Program.Particle)]) {
		assert uniformBlockLength(particle, FRAME_UNIFORM_SLOT) == FRAME_UNIFORM_LENGTH;
		assert declaredSlots(particle) == 2;
	}
	assert uniformBlockLength(pixelArt(Program.Post), POST_UNIFORM_SLOT) == POST_UNIFORM_LENGTH;
	assert uniformBlockLength(pixelArt(Program.Blit), BLIT_UNIFORM_SLOT) == BLIT_UNIFORM_LENGTH;
	assert declaredSlots(ProgramKey.of(Program.Copy)) == 0;
	assert uniformBlockLength(ProgramKey.of(Program.Lit), UNIFORM_SLOTS) == 0;
}

test "the core refuses a lit material without its block, or on a mesh of another layout" {
	let bare: DrawContext = contextNaming(ProgramKey.of(Program.Lit), RENDERER_UNIFORM_LENGTH);
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
	let context: DrawContext = contextNaming(ProgramKey.of(Program.Lit), FORWARD_UNIFORM_LENGTH);
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
	let context: DrawContext = contextNaming(ProgramKey.of(Program.Lit), FORWARD_UNIFORM_LENGTH);
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

const UNIFORM_SLOTS_OF_LIT: Vec<int32> =
	[VERTEX_UNIFORM_SLOT, LIGHT_UNIFORM_SLOT, MATERIAL_UNIFORM_SLOT, MODEL_SLOT];

test "each cutout key keeps the uncut key's layout and blocks, in both presets" {
	for (const program of [Program.Lit, Program.LitTextured, Program.UnlitTextured]) {
		for (const preset of [Preset.Core, Preset.PixelArt]) {
			const whole: ProgramKey = drawnAs(ProgramKey.of(program), preset);
			const cut: ProgramKey = drawnAs(ProgramKey.of(program).withCutout(), preset);
			assert cut.cutout && !cut.premultiplied && !whole.cutout;
			assert vertexLayoutOf(cut) == vertexLayoutOf(whole);
			for (const slot of UNIFORM_SLOTS_OF_LIT) {
				assert uniformBlockLength(cut, slot) == uniformBlockLength(whole, slot);
			}
		}
	}
}

test "a cutout program refuses a block without a positive alpha-kill threshold" {
	let context: DrawContext = DrawContext.withUniformCapacity(3 * MATERIAL_UNIFORM_LENGTH);
	const cut: ProgramKey = ProgramKey.of(Program.Lit).withCutout();
	const bare: Result<MaterialId, MaterialError> = addMaterial(context, Material.keyed(
		cut, RenderState.defaults(), Phase.Opaque,
	));
	assert !bare.ok && bare.error == MaterialError.NoAlphaKill;
	const thresholds: Vec<float32> = [0.0, -0.5, 0.5];
	for (const threshold of thresholds) {
		const reserved: Result<UniformBlock, UniformError> =
			reserveUniforms(context, MATERIAL_UNIFORM_SLOT, MATERIAL_UNIFORM_LENGTH);
		if (!reserved.ok) { unreachable; }
		let values: Vec<float32> = [0.0, 0.0, 0.0, 0.0];
		values[MATERIAL_ALPHA_KILL] = threshold;
		if (!writeUniforms(context, reserved.value, values).ok) { unreachable; }
		const made: Result<MaterialId, MaterialError> = addMaterial(context, {
			...Material.keyed(cut, RenderState.defaults(), Phase.Opaque),
			uniforms: reserved.value,
		});
		assert made.ok == (threshold > 0.0);
		if (!made.ok) { assert made.error == MaterialError.NoAlphaKill; }
	}
}

test "each premultiplied key keeps the straight key's blocks, in both presets" {
	for (const program of [Program.LitTextured, Program.UnlitTextured]) {
		for (const preset of [Preset.Core, Preset.PixelArt]) {
			const straight: ProgramKey = drawnAs(ProgramKey.of(program), preset);
			const premultiplied: ProgramKey =
				drawnAs(ProgramKey.of(program).withPremultiplied(), preset);
			assert premultiplied.premultiplied && !premultiplied.cutout && !straight.premultiplied;
			for (const slot of UNIFORM_SLOTS_OF_LIT) {
				assert uniformBlockLength(premultiplied, slot) ==
					uniformBlockLength(straight, slot);
			}
		}
	}
}

test "a premultiplied program refuses any blend but ONE, ONE_MINUS_SRC_ALPHA" {
	let context: DrawContext = DrawContext.withUniformCapacity(0);
	for (const mode of [BlendMode.None, BlendMode.Alpha, BlendMode.Add, BlendMode.Max]) {
		const refused: Result<MaterialId, MaterialError> = addMaterial(context, Material.keyed(
			ProgramKey.of(Program.UnlitTextured).withPremultiplied(),
			RenderState.defaults().withBlendMode(mode),
			Phase.Alpha,
		));
		assert !refused.ok && refused.error == MaterialError.StraightBlend;
	}
	assert context.liveMaterials() == 0;
	const kept: Result<MaterialId, MaterialError> = addMaterial(context, Material.keyed(
		ProgramKey.of(Program.LitTextured).withPremultiplied(),
		RenderState.defaults().withBlendMode(BlendMode.AlphaAdd),
		Phase.Alpha,
	));
	assert kept.ok;
}

test "a premultiplied billboard keeps the billboard's blocks and samplers, in both presets" {
	for (const preset of [Preset.Core, Preset.PixelArt]) {
		const straight: ProgramKey = drawnAs(ProgramKey.of(Program.Billboard), preset);
		const premultiplied: ProgramKey =
			drawnAs(ProgramKey.of(Program.Billboard).withPremultiplied(), preset);
		assert premultiplied.premultiplied && !premultiplied.cutout && !straight.premultiplied;
		assert premultiplied.bits() != straight.bits();
		assert vertexLayoutOf(premultiplied) == VertexLayout.Billboard;
		assert textureSlotMask(premultiplied) == textureSlotMask(straight);
		assert samplerSlotMask(premultiplied) == samplerSlotMask(straight);
		for (let slot = 0; slot < UNIFORM_SLOTS; slot++) {
			assert uniformBlockLength(premultiplied, slot) == uniformBlockLength(straight, slot);
		}
		assert uniformBlockLength(premultiplied, BILLBOARD_UNIFORM_SLOT) ==
			BILLBOARD_UNIFORM_LENGTH;
	}
}

test "a premultiplied billboard blends ONE, ONE_MINUS_SRC_ALPHA and only that" {
	let context: DrawContext = DrawContext.withUniformCapacity(0);
	const key: ProgramKey = ProgramKey.of(Program.Billboard).withPremultiplied();
	for (const mode of [BlendMode.None, BlendMode.Alpha, BlendMode.Add]) {
		const refused: Result<MaterialId, MaterialError> = addMaterial(
			context,
			Material.keyed(key, RenderState.defaults().withBlendMode(mode), Phase.Alpha),
		);
		assert !refused.ok && refused.error == MaterialError.StraightBlend;
	}
	const kept: Result<MaterialId, MaterialError> = addMaterial(context, Material.keyed(
		key, RenderState.defaults().withBlendMode(BlendMode.AlphaAdd), Phase.Alpha,
	));
	assert kept.ok;
}

test "unlit textured programs require colour data and no light uniform block" {
	for (const program of [ProgramKey.of(Program.UnlitTextured), pixelArt(Program.UnlitTextured)]) {
		assert uniformBlockLength(program, LIGHT_UNIFORM_SLOT) == 0;
		assert uniformBlockLength(program, VERTEX_UNIFORM_SLOT) == VERTEX_UNIFORM_LENGTH;
		assert uniformBlockLength(program, MATERIAL_UNIFORM_SLOT) == 8;
	}
	assert uniformBlockLength(ProgramKey.of(Program.UnlitTextured), MODEL_SLOT) == 16;
	assert uniformBlockLength(pixelArt(Program.UnlitTextured), MODEL_SLOT) == MODEL_LENGTH;
}

test "an unlit material refuses a missing colour block or the old lit block size" {
	for (const length of [0, MATERIAL_UNIFORM_LENGTH]) {
		const context: DrawContext =
			DrawContext.withUniformCapacity(RENDERER_UNIFORM_LENGTH + length);
		let block: UniformBlock = NO_UNIFORMS;
		if (length > 0) {
			const reserved: Result<UniformBlock, UniformError> =
				reserveUniforms(context, MATERIAL_UNIFORM_SLOT, length);
			assert reserved.ok;
			if (!reserved.ok) { return; }
			block = reserved.value;
		}
		const material: Result<MaterialId, MaterialError> = addMaterial(context, {
			...Material.plain(Program.UnlitTextured, RenderState.defaults(), Phase.Opaque),
			uniforms: block,
		});
		assert material.ok;
		if (!material.ok) { return; }
		const created: Result<Renderer, RendererError> = Renderer.create(context);
		assert created.ok;
		if (!created.ok) { return; }
		const items: Vec<DrawItem> = [itemOf(context, material.value)];
		const camera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
		const lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
		const began: Result<boolean, RendererError> =
			beginFrame(created.value, items, camera, lights);
		assert !began.ok && began.error == RendererError.MaterialBlock;
	}
}

function featureKeys(program: Program): Vec<ProgramKey> {
	const plain: ProgramKey = ProgramKey.of(program);
	return [
		plain.withUvTransform(), plain.withBackTexture(), plain.withDissolve(),
		plain.withUvTransform().withBackTexture().withDissolve(),
	];
}

function bit(mask: uint32, slot: int32): boolean {
	return (mask & ((1 as uint32) << (slot as uint32))) != 0;
}

test "a moving key reads its program's block and the moving floats, and what its features sample" {
	for (const program of [Program.LitTextured, Program.UnlitTextured]) {
		const unlit: boolean = program == Program.UnlitTextured;
		const length: int32 =
			unlit ? MOVING_UNLIT_MATERIAL_UNIFORM_LENGTH : MOVING_MATERIAL_UNIFORM_LENGTH;
		assert movingBase(ProgramKey.of(program)) ==
			(unlit ? UNLIT_MATERIAL_UNIFORM_LENGTH : MATERIAL_UNIFORM_LENGTH);
		for (const preset of [Preset.Core, Preset.PixelArt]) {
			const plain: ProgramKey = drawnAs(ProgramKey.of(program), preset);
			for (const feature of featureKeys(program)) {
				const key: ProgramKey = drawnAs(feature, preset);
				assert key.moves() && vertexLayoutOf(key) == vertexLayoutOf(plain);
				assert uniformBlockLength(key, MATERIAL_UNIFORM_SLOT) == length;
				assert uniformBlockLength(key, FRAME_UNIFORM_SLOT) == FRAME_UNIFORM_LENGTH;
				assert uniformBlockLength(key, VERTEX_UNIFORM_SLOT) ==
					uniformBlockLength(plain, VERTEX_UNIFORM_SLOT);
				assert uniformBlockLength(key, LIGHT_UNIFORM_SLOT) ==
					uniformBlockLength(plain, LIGHT_UNIFORM_SLOT);
				const views: uint32 = textureSlotMask(key);
				const samplers: uint32 = samplerSlotMask(key);
				assert bit(views, 0) && bit(samplers, 0);
				assert bit(views, BACK_VIEW_SLOT) == key.backTexture;
				assert bit(views, DISSOLVE_VIEW_SLOT) == key.dissolve;
				assert bit(samplers, DISSOLVE_SAMPLER_SLOT) == key.dissolve;
				if (!unlit) {
					const shadowed: Result<ProgramKey, ProgramError> = drawnIn(
						{ ...feature, shadowed: true }, preset, true,
					);
					assert shadowed.ok;
				}
			}
		}
	}
}

test "a caster keeps a dissolve and leaves the UV features to a cut" {
	for (const program of [Program.LitTextured, Program.UnlitTextured]) {
		const dissolve: Result<ProgramKey, ProgramError> =
			castIn(ProgramKey.of(program).withDissolve().withUvTransform());
		assert dissolve.ok;
		if (dissolve.ok) {
			assert dissolve.value.dissolve && !dissolve.value.uvTransform;
			assert uniformBlockLength(dissolve.value, MATERIAL_UNIFORM_SLOT) ==
				uniformBlockLength(ProgramKey.of(program).withDissolve(), MATERIAL_UNIFORM_SLOT);
			assert bit(textureSlotMask(dissolve.value), DISSOLVE_VIEW_SLOT);
		}
		const moved: Result<ProgramKey, ProgramError> =
			castIn(ProgramKey.of(program).withUvTransform().withBackTexture());
		assert moved.ok;
		if (moved.ok) { assert !moved.value.moves(); }
		const cut: Result<ProgramKey, ProgramError> =
			castIn(ProgramKey.of(program).withCutout().withUvTransform());
		assert !cut.ok && cut.error == ProgramError.NotDrawn;
	}
}

test "movingDefaults makes both UV transforms and an unlit colour the identity, the rest 0" {
	for (const program of [Program.LitTextured, Program.UnlitTextured]) {
		const key: ProgramKey = ProgramKey.of(program).withDissolve();
		const values: Vec<float32> = movingDefaults(key);
		assert (values.length as int32) == uniformBlockLength(key, MATERIAL_UNIFORM_SLOT);
		const base: int32 = movingBase(key);
		let ones: int32 = 0;
		for (let i = 0; i < (values.length as int32); i++) {
			if (values[i] == 1.0) { ones = ones + 1; } else { assert values[i] == 0.0; }
		}
		if (program == Program.UnlitTextured) {
			for (let i = 0; i < 4; i++) { assert values[UNLIT_MATERIAL_COLOR + i] == 1.0; }
		}
		const colour: int32 = program == Program.UnlitTextured ? 4 : 0;
		assert ones == 4 + colour;
		for (const matrix of [base + MOVING_UV_MATRIX, base + MOVING_BACK_UV_MATRIX]) {
			assert values[matrix] == 1.0 && values[matrix + 1] == 0.0;
			assert values[matrix + 2] == 0.0 && values[matrix + 3] == 1.0;
		}
	}
}

test "the core owns a frame block and asks for frames while time passes under a key reading it" {
	let context: DrawContext = DrawContext.withUniformCapacity(RENDERER_UNIFORM_LENGTH);
	const created: Result<Renderer, RendererError> = Renderer.create(context);
	assert created.ok;
	if (!created.ok) { return; }
	let core: Renderer = created.value;
	assert core.frameBlock.slot == FRAME_UNIFORM_SLOT;
	assert core.frameBlock.length == FRAME_UNIFORM_LENGTH;
	assert context.uniforms.used == RENDERER_UNIFORM_LENGTH;
	const released: Result<int32, UniformError> = releaseUniforms(context, core.frameBlock);
	assert !released.ok && released.error == UniformError.Owned;
	assert core.time == 0.0 && core.elapsedTime == 0.0;
	core.changed = false;
	core.generation = 1;
	assert !core.needsFrame();
	setElapsedTime(core, 0.25);
	assert core.elapsedTime == 0.25 && !core.needsFrame();
	core.readsTime = true;
	assert core.needsFrame();
	setElapsedTime(core, 0.0);
	assert !core.needsFrame();
}

test "the frame's time is Heaps' unless the renderer wraps it, as Bevy's hour, in 64-bit first" {
	assert frameTime(5400.25, 0.0) == 5400.25;
	assert frameTime(5400.25, 3600.0) == 1800.25;
	assert frameTime(3599.5, 3600.0) == 3599.5;
	assert frameTime(7200.0, 3600.0) == 0.0;
	const day: float64 = 86400.0 + 0.125;
	assert frameTime(day, 3600.0) == 0.125;
	assert frameTime(day, 0.0) == day as float32;
	let context: DrawContext = DrawContext.withUniformCapacity(RENDERER_UNIFORM_LENGTH);
	const created: Result<Renderer, RendererError> = Renderer.create(context);
	assert created.ok;
	if (!created.ok) { return; }
	let core: Renderer = created.value;
	assert core.timeWrap == 0.0;
	setTimeWrap(core, 3600.0);
	assert core.timeWrap == 3600.0;
	setTimeWrap(core, 0.0);
	assert core.timeWrap == 0.0;
}

function mapKeys(): Vec<ProgramKey> {
	const plain: ProgramKey = ProgramKey.of(Program.LitTextured);
	return [plain.withEmissive(), plain.withNormalMap(), plain.withEmissive().withNormalMap()];
}

test "an emissive or normal-mapped key ends its block in the emissive floats and samples its maps" {
	for (const preset of [Preset.Core, Preset.PixelArt]) {
		const plain: ProgramKey = drawnAs(ProgramKey.of(Program.LitTextured), preset);
		for (const mapped of mapKeys()) {
			for (const shadowed of [false, true]) {
				const drawn: Result<ProgramKey, ProgramError> =
					drawnIn({ ...mapped, shadowed: shadowed }, preset, shadowed);
				assert drawn.ok;
				if (!drawn.ok) { return; }
				const key: ProgramKey = drawn.value;
				assert !key.moves() && emissiveBase(key) == MATERIAL_UNIFORM_LENGTH;
				const length: int32 =
					MATERIAL_UNIFORM_LENGTH + (key.emissive ? EMISSIVE_LENGTH : 0);
				assert uniformBlockLength(key, MATERIAL_UNIFORM_SLOT) == length;
				assert vertexLayoutOf(key) == (key.normalMap ?
					VertexLayout.LitTexturedTangent : VertexLayout.LitTextured);
				const views: uint32 = textureSlotMask(key);
				assert bit(views, 0) && bit(samplerSlotMask(key), 0);
				assert bit(views, EMISSIVE_VIEW_SLOT) == key.emissive;
				assert bit(views, NORMAL_VIEW_SLOT) == key.normalMap;
				assert samplerSlotMask(key) == samplerSlotMask({ ...plain, shadowed: shadowed });
			}
		}
	}
}

test "an emissive key after a moving one reads its floats after the moving ones" {
	const moving: ProgramKey = ProgramKey.of(Program.LitTextured).withDissolve().withEmissive();
	assert emissiveBase(moving) == MATERIAL_UNIFORM_LENGTH + MOVING_LENGTH;
	assert declares(moving) && declares(moving.withShadowed());
	const length: int32 = MOVING_MATERIAL_UNIFORM_LENGTH + EMISSIVE_LENGTH;
	assert uniformBlockLength(moving, MATERIAL_UNIFORM_SLOT) == length;
	assert uniformBlockLength(moving.withShadowed(), MATERIAL_UNIFORM_SLOT) == length;
	assert !declares(moving.withUvTransform()) && !declares(moving.withPreset(Preset.PixelArt));
	const cast: Result<ProgramKey, ProgramError> = castIn(moving.withShadowed());
	assert cast.ok;
	if (!cast.ok) { return; }
	assert cast.value.dissolve && !cast.value.emissive;
	assert uniformBlockLength(cast.value, MATERIAL_UNIFORM_SLOT) == MOVING_MATERIAL_UNIFORM_LENGTH;
	assert bit(textureSlotMask(moving), EMISSIVE_VIEW_SLOT);
	assert !bit(textureSlotMask(cast.value), EMISSIVE_VIEW_SLOT);
}

test "a premultiplied card can cut and dissolve, and its caster cuts and dissolves as it does" {
	for (const program of [Program.LitTextured, Program.UnlitTextured]) {
		const premultiplied: ProgramKey = ProgramKey.of(program).withPremultiplied();
		const cut: ProgramKey = premultiplied.withCutout();
		const melting: ProgramKey = premultiplied.withDissolve();
		assert declares(cut) && declares(melting);
		assert !declares(cut.withPreset(Preset.PixelArt));
		assert uniformBlockLength(cut, MATERIAL_UNIFORM_SLOT) ==
			uniformBlockLength(ProgramKey.of(program), MATERIAL_UNIFORM_SLOT);
		assert uniformBlockLength(melting, MATERIAL_UNIFORM_SLOT) ==
			uniformBlockLength(ProgramKey.of(program).withDissolve(), MATERIAL_UNIFORM_SLOT);
		assert vertexLayoutOf(cut) == vertexLayoutOf(ProgramKey.of(program));
		const castCut: Result<ProgramKey, ProgramError> = castIn(cut);
		assert castCut.ok;
		if (castCut.ok) {
			assert castCut.value.cutout && !castCut.value.premultiplied;
			assert uniformBlockLength(castCut.value, MATERIAL_UNIFORM_SLOT) ==
				uniformBlockLength(cut, MATERIAL_UNIFORM_SLOT);
			assert textureSlotMask(castCut.value) == textureSlotMask(cut);
		}
		const castMelting: Result<ProgramKey, ProgramError> = castIn(melting);
		assert castMelting.ok;
		if (castMelting.ok) {
			assert castMelting.value.dissolve && !castMelting.value.premultiplied;
			assert uniformBlockLength(castMelting.value, MATERIAL_UNIFORM_SLOT) ==
				uniformBlockLength(melting, MATERIAL_UNIFORM_SLOT);
		}
	}
}

test "a caster leaves the emissive map and keeps the normal map's layout" {
	for (const mapped of mapKeys()) {
		const cast: Result<ProgramKey, ProgramError> = castIn(mapped);
		assert cast.ok;
		if (!cast.ok) { return; }
		assert !cast.value.emissive && cast.value.normalMap == mapped.normalMap;
		assert vertexLayoutOf(cast.value) == vertexLayoutOf(mapped.withPreset(Preset.Core));
		assert !bit(textureSlotMask(cast.value), NORMAL_VIEW_SLOT);
		assert !bit(textureSlotMask(cast.value), EMISSIVE_VIEW_SLOT);
	}
}

function cutBillboard(): ProgramKey {
	return ProgramKey.of(Program.Billboard).withCutout();
}

test "the frame block carries Heaps' exposure as its multiplier, exactly 1 at stop 0" {
	assert exposureMultiplier(0.0) == 1.0;
	assert approx(exposureMultiplier(Math.log(1.5) as float32), 1.5);
	assert approx(exposureMultiplier(-1.0), Math.exp(-1.0) as float32);
	let context: DrawContext = DrawContext.withUniformCapacity(RENDERER_UNIFORM_LENGTH);
	const created: Result<Renderer, RendererError> = Renderer.create(context);
	assert created.ok;
	if (!created.ok) { return; }
	let core: Renderer = created.value;
	assert core.exposure == 0.0;
	setExposure(core, 0.5);
	assert core.exposure == 0.5;
	setExposure(core, 0.0);
	assert core.exposure == 0.0;
}
