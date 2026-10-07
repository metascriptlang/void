import { Vec3, vec3, identity } from "../math/math3d";
import {
	Program,
	ProgramKey,
	Preset,
	ProgramError,
	drawnIn,
	castIn,
	declares,
	vertexLayoutOf,
	uniformBlockLength,
	textureSlotMask,
	samplerSlotMask,
	VERTEX_UNIFORM_SLOT,
	VERTEX_UNIFORM_LENGTH,
	LIGHT_UNIFORM_LENGTH,
	MATERIAL_UNIFORM_SLOT,
	MATERIAL_UNIFORM_LENGTH,
	SHADOW_UNIFORM_SLOT,
	SHADOW_UNIFORM_LENGTH,
	SHADOW_VIEW_SLOT,
	SHADOW_SAMPLER_SLOT,
	BILLBOARD_UNIFORM_SLOT,
	BILLBOARD_UNIFORM_LENGTH,
} from "../void3d/gpu3d";
import { RenderState, Face } from "../gpu/state";
import {
	Material,
	MaterialKind,
	Phase,
	ShadowCasting,
	ShadowCulling,
	UniformBlock,
	withShadowCulling,
	shadowFace,
} from "../void3d/material";
import {
	DrawContext,
	DrawItem,
	GpuMesh,
	MeshId,
	MaterialId,
	MaterialError,
	MODEL_SLOT,
	MODEL_LENGTH,
	addMaterial,
	reserveUniforms,
	releaseUniforms,
} from "../void3d/draw";
import { UniformError } from "../void3d/uniformPool";
import { added } from "./drawHelpers";
import {
	Renderer,
	RendererError,
	RENDERER_UNIFORM_LENGTH,
	attachShadow,
	beginFrame,
} from "../void3d/renderer";
import {
	DirShadowMap,
	ShadowError,
	DIR_SHADOW_UNIFORM_LENGTH,
	lightBasis,
	shadowBounds,
} from "../void3d/dirShadowMap";
import { Bounds3D } from "../void3d/bounds";
import { CameraBasis } from "../void3d/camera";

const LIT_PROGRAMS: Vec<Program> = [Program.Lit, Program.LitTextured];

function drawnAs(key: ProgramKey, preset: Preset, shadowMap: boolean): ProgramKey {
	const drawn: Result<ProgramKey, ProgramError> = drawnIn(key, preset, shadowMap);
	if (drawn.ok) { return drawn.value; }
	console.log(`${key.describe()} is not drawn in ${preset.toString()}`);
	unreachable;
}

function castAs(key: ProgramKey): ProgramKey {
	const cast: Result<ProgramKey, ProgramError> = castIn(key);
	if (cast.ok) { return cast.value; }
	console.log(`${key.describe()} casts no shadow`);
	unreachable;
}

function bit(slot: int32): uint32 {
	return (1 as uint32) << (slot as uint32);
}

function near(a: float32, b: float32): boolean {
	const d: float32 = a - b;
	return d < 0.0001 && d > -0.0001;
}

test "a receiver draws shadowed only in a frame with a shadow map, in both presets" {
	for (const program of LIT_PROGRAMS) {
		for (const cut of [false, true]) {
			const whole: ProgramKey = ProgramKey.of(program);
			const plain: ProgramKey = cut ? whole.withCutout() : whole;
			const receiver: ProgramKey = plain.withShadowed();
			for (const preset of [Preset.Core, Preset.PixelArt]) {
				assert drawnAs(receiver, preset, false) == plain.withPreset(preset);
				assert drawnAs(receiver, preset, true) == receiver.withPreset(preset);
				assert drawnAs(plain, preset, true) == plain.withPreset(preset);
			}
		}
	}
	for (const program of [Program.Lit, Program.LitTextured, Program.UnlitTextured]) {
		const refused: Result<ProgramKey, ProgramError> =
			drawnIn(ProgramKey.of(program), Preset.Shadow, true);
		assert !refused.ok && refused.error == ProgramError.NotDrawn;
	}
}

test "a shadowed program reads the shadow block, map and sampler past a material's" {
	for (const program of LIT_PROGRAMS) {
		for (const preset of [Preset.Core, Preset.PixelArt]) {
			const plain: ProgramKey = ProgramKey.of(program).withPreset(preset);
			const shadowed: ProgramKey = plain.withShadowed();
			assert declares(shadowed) && vertexLayoutOf(shadowed) == vertexLayoutOf(plain);
			assert uniformBlockLength(shadowed, SHADOW_UNIFORM_SLOT) == SHADOW_UNIFORM_LENGTH;
			assert uniformBlockLength(plain, SHADOW_UNIFORM_SLOT) == 0;
			assert uniformBlockLength(shadowed, MATERIAL_UNIFORM_SLOT) == MATERIAL_UNIFORM_LENGTH;
			assert textureSlotMask(shadowed) == (textureSlotMask(plain) | bit(SHADOW_VIEW_SLOT));
			assert samplerSlotMask(shadowed) ==
				(samplerSlotMask(plain) | bit(SHADOW_SAMPLER_SLOT));
		}
	}
}

test "the shadow pass casts a caster's depth on its layout, cut only where its material cuts" {
	for (const program of [Program.Lit, Program.LitTextured, Program.UnlitTextured]) {
		const whole: ProgramKey = castAs(ProgramKey.of(program));
		assert whole.preset == Preset.Shadow && !whole.cutout && !whole.shadowed;
		assert vertexLayoutOf(whole) == vertexLayoutOf(ProgramKey.of(program));
		assert uniformBlockLength(whole, VERTEX_UNIFORM_SLOT) == VERTEX_UNIFORM_LENGTH;
		assert uniformBlockLength(whole, MATERIAL_UNIFORM_SLOT) == 0;
		assert textureSlotMask(whole) == 0 && samplerSlotMask(whole) == 0;
		const cut: ProgramKey = castAs(ProgramKey.of(program).withCutout());
		assert cut.cutout;
		assert uniformBlockLength(cut, MATERIAL_UNIFORM_SLOT) ==
			uniformBlockLength(ProgramKey.of(program), MATERIAL_UNIFORM_SLOT);
		assert textureSlotMask(cut) == textureSlotMask(ProgramKey.of(program));
	}
	assert uniformBlockLength(castAs(ProgramKey.of(Program.Lit)), MODEL_SLOT) == MODEL_LENGTH;
	const premultiplied: ProgramKey =
		castAs(ProgramKey.of(Program.LitTextured).withPremultiplied());
	assert !premultiplied.premultiplied;
	const received: ProgramKey = castAs(ProgramKey.of(Program.Lit).withShadowed());
	assert !received.shadowed;
	for (const program of [Program.Billboard, Program.Particle]) {
		const refused: Result<ProgramKey, ProgramError> = castIn(ProgramKey.of(program));
		assert !refused.ok && refused.error == ProgramError.NotDrawn;
	}
}

test "a material kind casts and receives as Heaps' default props do, and the setters override" {
	const lit: Material = Material.ofKind(Program.LitTextured, MaterialKind.Alpha);
	assert lit.castShadows == ShadowCasting.On && lit.program.shadowed;
	const unlit: Material = Material.ofKind(Program.UnlitTextured, MaterialKind.Opaque);
	assert unlit.castShadows == ShadowCasting.On && !unlit.program.shadowed;
	const particle: Material = Material.ofKind(Program.Particle, MaterialKind.Add);
	assert particle.castShadows == ShadowCasting.Off && !particle.program.shadowed;
	const plain: Material = Material.plain(Program.Lit, RenderState.defaults(), Phase.Opaque);
	assert plain.castShadows == ShadowCasting.Off && !plain.program.shadowed;
	const only: Material = lit.withShadows(ShadowCasting.Only, false);
	assert only.castShadows == ShadowCasting.Only && !only.program.shadowed;
	assert plain.withShadows(ShadowCasting.Off, true).program == plain.program.withShadowed();
}

test "a particle or a billboard material is unculled by default, as particles3D is, and the rest cull" {
	for (const program of [Program.Particle, Program.Billboard]) {
		const quads: Material = Material.ofKind(program, MaterialKind.Alpha);
		assert quads.pass.culling == Face.None && quads.castShadows == ShadowCasting.Off;
	}
	for (const program of [Program.Lit, Program.LitTextured, Program.UnlitTextured]) {
		assert Material.ofKind(program, MaterialKind.Opaque).pass.culling == Face.Back;
	}
}

test "the shadow pass culls as the main pass does unless the material says its own side" {
	const base: Material = Material.ofKind(Program.Lit, MaterialKind.Opaque);
	assert base.shadowCulling == ShadowCulling.Main && base.shadowFace() == Face.Back;
	const unculled: Material = { ...base, pass: base.pass.withCulling(Face.None) };
	assert unculled.shadowFace() == Face.None;
	assert base.withShadowCulling(ShadowCulling.None).shadowFace() == Face.None;
	assert unculled.withShadowCulling(ShadowCulling.Front).shadowFace() == Face.Front;
	assert unculled.withShadowCulling(ShadowCulling.Back).shadowFace() == Face.Back;
	assert base.withShadowCulling(ShadowCulling.None).pass.culling == Face.Back;
}

function lengthOf(v: Vec3): float32 {
	return v.length();
}

test "the light's axes are orthonormal and right-handed, straight down included" {
	const directions: Vec<Vec3> =
		[vec3(0.3, 1.0, 0.2), vec3(0.0, 1.0, 0.0), vec3(0.0, -1.0, 0.0), vec3(-1.0, 0.5, 0.0)];
	for (const toLight of directions) {
		const basis: CameraBasis = lightBasis(toLight);
		assert near(lengthOf(basis.right), 1.0) && near(lengthOf(basis.up), 1.0);
		assert near(lengthOf(basis.forward), 1.0);
		assert near(basis.right.dot(basis.up), 0.0) && near(basis.up.dot(basis.forward), 0.0);
		assert near(basis.forward.dot(toLight.normalized()), -1.0);
		assert near(basis.right.cross(basis.up).dot(basis.forward), -1.0);
	}
	const zero: CameraBasis = lightBasis(vec3(0.0, 0.0, 0.0));
	assert near(zero.forward.y, -1.0);
}

const DOWN: CameraBasis = {
	right: vec3(1.0, 0.0, 0.0),
	up: vec3(0.0, 0.0, -1.0),
	forward: vec3(0.0, -1.0, 0.0),
};

test "the shadow box is the casters' cut to the view across the light, keeping their near side" {
	const casters: Bounds3D = Bounds3D.fromPoints(vec3(-0.5, -0.5, -5.0), vec3(3.0, -0.2, 0.5));
	const box: Bounds3D = shadowBounds(DOWN, casters, identity());
	assert !box.isEmpty();
	assert near(box.min.x, 0.25 - 0.75 * 1.01) && near(box.max.x, 0.25 + 0.75 * 1.01);
	assert near(box.min.y, -0.35 - 0.15 * 1.01) && near(box.max.y, -0.35 + 0.15 * 1.01);
	assert near(box.min.z, -2.25 - 2.75 * 1.01) && near(box.max.z, -2.25 + 2.75 * 1.01);
	const beyond: Bounds3D = Bounds3D.fromPoints(vec3(-0.5, -0.5, -5.0), vec3(0.5, -0.2, 3.0));
	assert near(shadowBounds(DOWN, beyond, identity()).max.z, -2.0 + 3.0 * 1.01);
	const aside: Bounds3D = Bounds3D.fromPoints(vec3(2.0, -0.5, 0.0), vec3(3.0, -0.2, 0.5));
	assert shadowBounds(DOWN, aside, identity()).isEmpty();
	const behind: Bounds3D = Bounds3D.fromPoints(vec3(-0.5, -0.5, 2.0), vec3(0.5, -0.2, 3.0));
	assert shadowBounds(DOWN, behind, identity()).isEmpty();
	assert shadowBounds(DOWN, Bounds3D.empty(), identity()).isEmpty();
	const flat: Bounds3D = Bounds3D.fromPoints(vec3(-0.5, -0.5, 0.0), vec3(0.5, -0.2, 0.0));
	const thin: Bounds3D = shadowBounds(DOWN, flat, identity());
	assert thin.max.z - thin.min.z > 0.0009;
}

test "a shadow map reserves and owns its two blocks, and refuses no room or no size" {
	let small: DrawContext = DrawContext.withUniformCapacity(DIR_SHADOW_UNIFORM_LENGTH - 1);
	const full: Result<DirShadowMap, ShadowError> = DirShadowMap.create(small, 1024);
	assert !full.ok && full.error == ShadowError.UniformPoolFull;
	let context: DrawContext = DrawContext.withUniformCapacity(DIR_SHADOW_UNIFORM_LENGTH);
	const unsized: Result<DirShadowMap, ShadowError> = DirShadowMap.create(context, 0);
	assert !unsized.ok && unsized.error == ShadowError.Size;
	const made: Result<DirShadowMap, ShadowError> = DirShadowMap.create(context, 1024);
	assert made.ok;
	if (!made.ok) { return; }
	assert context.uniforms.used == DIR_SHADOW_UNIFORM_LENGTH;
	assert made.value.shadowBlock.slot == SHADOW_UNIFORM_SLOT;
	assert made.value.shadowBlock.length == SHADOW_UNIFORM_LENGTH;
	const given: Result<int32, UniformError> = releaseUniforms(context, made.value.shadowBlock);
	assert !given.ok && given.error == UniformError.Owned;
}

function itemOf(context: DrawContext, material: MaterialId): DrawItem {
	return {
		mesh: { store: context.serial, index: 0, generation: 1 },
		material: material,
		world: identity(),
	};
}

test "a frame with a shadow map refuses a caster with no shadow output before it writes" {
	let context: DrawContext = DrawContext.withUniformCapacity(
		RENDERER_UNIFORM_LENGTH + DIR_SHADOW_UNIFORM_LENGTH + BILLBOARD_UNIFORM_LENGTH,
	);
	const created: Result<Renderer, RendererError> = Renderer.create(context);
	const map: Result<DirShadowMap, ShadowError> = DirShadowMap.create(context, 256);
	assert created.ok && map.ok;
	if (!created.ok || !map.ok) { return; }
	let core: Renderer = created.value;
	assert core.sceneGlobals.length == 3 && core.sceneGlobals[2] == core.frameBlock;
	attachShadow(core, map.value);
	assert core.sceneGlobals.length == 4 && core.sceneGlobals[3] == map.value.shadowBlock;
	const block: Result<UniformBlock, UniformError> =
		reserveUniforms(context, BILLBOARD_UNIFORM_SLOT, BILLBOARD_UNIFORM_LENGTH);
	if (!block.ok) { unreachable; }
	const caster: Material = {
		...Material.plain(Program.Billboard, RenderState.defaults(), Phase.Opaque),
		texture0: 5,
		sampler0: 6,
		uniforms: block.value,
		castShadows: ShadowCasting.On,
	};
	const material: Result<MaterialId, MaterialError> = addMaterial(context, caster);
	assert material.ok;
	if (!material.ok) { return; }
	const quads: MeshId = added(context, GpuMesh.billboards(9, 1));
	const items: Vec<DrawItem> = [{ ...itemOf(context, material.value), mesh: quads }];
	let camera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
	camera[0] = 7.0;
	const lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
	const began: Result<boolean, RendererError> = beginFrame(core, items, camera, lights);
	assert !began.ok && began.error == RendererError.ProgramNotCast;
	assert context.uniforms.values[core.cameraBlock.offset] == 0.0 && core.generation == 0;
	attachShadow(core, null);
	assert core.sceneGlobals.length == 3;
}
