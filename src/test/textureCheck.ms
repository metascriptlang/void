import { Mat4, Vec4, identity } from "../math/math3d";
import { RenderState, FilterMode, Wrap } from "../gpu/state";
import { SWAPCHAIN_LAYOUT } from "../gpu/target";
import {
	Program,
	VertexLayout,
	MATERIAL_UNIFORM_SLOT,
	MATERIAL_UNIFORM_LENGTH,
	VERTEX_UNIFORM_LENGTH,
	LIGHT_UNIFORM_LENGTH,
} from "../void3d/gpu3d";
import { Material, Phase, UniformBlock } from "../void3d/material";
import { TextureData, TextureId, TextureUploadError, NO_TEXTURE } from "../void3d/texture";
import { UniformError } from "../void3d/uniformPool";
import {
	DrawContext,
	DrawItem,
	MeshId,
	MaterialId,
	MaterialError,
	HandleError,
	addMaterial,
	addTexture,
	retainTexture,
	releaseTexture,
	rebuildTextures,
	samplerSlot,
	reserveUniforms,
} from "../void3d/draw";
import {
	Renderer,
	RendererError,
	RENDERER_UNIFORM_LENGTH,
	beginFrame,
	drawScreen,
} from "../void3d/renderer";
import {
	ForwardRenderer,
	ForwardError,
	FORWARD_UNIFORM_LENGTH,
	renderFrame,
} from "../void3d/forwardRenderer";
import {
	PixelArtRenderer,
	PixelArtSettings,
	PixelArtLook,
	PixelArtError,
	PIXEL_ART_UNIFORM_LENGTH,
	renderFrame as renderPixelArt,
} from "../void3d/pixelArtRenderer";
import { LowResView } from "../void3d/blit";
import { added, litShape } from "./drawHelpers";

let FIRST_SLOT: TextureId = { index: 0, generation: 1 };

function sized(width: int32, height: int32, pixels: int32): TextureData {
	let words: Vec<uint32> = new Array(pixels);
	for (let i = 0; i < pixels; i++) { words[i] = 0xFFFFFFFF; }
	return {
		pixels: words,
		width: width,
		height: height,
		filter: FilterMode.Nearest,
		wrap: Wrap.Repeat,
	};
}

function texturedLit(ref context: DrawContext): Material {
	let block: Result<UniformBlock, UniformError> =
		reserveUniforms(context, MATERIAL_UNIFORM_SLOT, MATERIAL_UNIFORM_LENGTH);
	if (!block.ok) { unreachable; }
	let plain: Material =
		Material.plain(Program.LitTextured, RenderState.defaults(), Phase.Opaque);
	return { ...plain, uniforms: block.value };
}

function materialError(result: Result<MaterialId, MaterialError>): MaterialError {
	return result.ok ? MaterialError.ReleasedUniforms : result.error;
}

function texturedItem(ref context: DrawContext, material: MaterialId): DrawItem {
	let world: Mat4 = identity();
	let mesh: MeshId = added(context, { ...litShape(), layout: VertexLayout.LitTextured });
	return { mesh: mesh, material: material, world: world };
}

test "texture data is well formed only with a positive size and one word per pixel" {
	assert sized(2, 2, 4).isWellFormed();
	assert sized(3, 1, 3).isWellFormed();
	assert !sized(0, 2, 0).isWellFormed();
	assert !sized(-2, -2, 4).isWellFormed();
	assert !sized(2, 2, 3).isWellFormed() && !sized(2, 2, 5).isWellFormed();
	assert !TextureData.empty().isWellFormed();
}

test "a texture of the wrong size is refused before anything is made, and takes no slot" {
	let context: DrawContext = DrawContext.withUniformCapacity(0);
	let refused: Result<TextureId, TextureUploadError> = addTexture(context, sized(2, 2, 3));
	assert !refused.ok && refused.error == TextureUploadError.BadSize;
	assert context.liveTextures() == 0 && context.textures.length == 0;
	assert context.textureSlots.generations.length == 0 && rebuildTextures(context) == 0;
}

test "no texture has generation 0, so the empty id names none" {
	assert !NO_TEXTURE.isTexture() && FIRST_SLOT.isTexture();
	let plain: Material = Material.plain(Program.Lit, RenderState.defaults(), Phase.Opaque);
	assert !plain.namesTexture() && plain.texture == NO_TEXTURE;
}

test "a texture id that names nothing is refused by every hold" {
	let context: DrawContext = DrawContext.withUniformCapacity(0);
	let retained: Result<int32, HandleError> = retainTexture(context, FIRST_SLOT);
	assert !retained.ok && retained.error == HandleError.StaleTexture;
	let released: Result<int32, HandleError> = releaseTexture(context, FIRST_SLOT);
	assert !released.ok && released.error == HandleError.StaleTexture;
	assert !context.hasTexture(FIRST_SLOT) && context.texturePinned(FIRST_SLOT) == 0;
}

test "a material naming a texture refuses a view or sampler at slot 0 too, and a stale one" {
	let context: DrawContext = DrawContext.withUniformCapacity(MATERIAL_UNIFORM_LENGTH);
	let material: Material = { ...texturedLit(context), texture: FIRST_SLOT };
	let viewToo: Result<MaterialId, MaterialError> =
		addMaterial(context, { ...material, texture0: 7 });
	assert materialError(viewToo) == MaterialError.TextureNamedTwice;
	let samplerToo: Result<MaterialId, MaterialError> =
		addMaterial(context, { ...material, sampler0: 7 });
	assert materialError(samplerToo) == MaterialError.TextureNamedTwice;
	let stale: Result<MaterialId, MaterialError> = addMaterial(context, material);
	assert materialError(stale) == MaterialError.StaleTexture;
	assert context.liveMaterials() == 0;
	let withoutTexture: Result<MaterialId, MaterialError> =
		addMaterial(context, { ...material, texture: NO_TEXTURE });
	assert withoutTexture.ok;
}

test "the core refuses a textured material with nothing at slot 0, or whose texture changed" {
	let capacity: int32 = RENDERER_UNIFORM_LENGTH + 3 * MATERIAL_UNIFORM_LENGTH;
	let context: DrawContext = DrawContext.withUniformCapacity(capacity);
	let created: Result<Renderer, RendererError> = Renderer.create(context);
	assert created.ok;
	if (!created.ok) { return; }
	let core: Renderer = created.value;
	let camera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
	let shortCamera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH - 1);
	let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
	let bare: Result<MaterialId, MaterialError> = addMaterial(context, texturedLit(context));
	assert bare.ok;
	if (!bare.ok) { return; }
	let bareItems: Vec<DrawItem> = [texturedItem(context, bare.value)];
	let unbound: Result<boolean, RendererError> =
		beginFrame(core, context, bareItems, camera, lights);
	assert !unbound.ok && unbound.error == RendererError.MaterialTexture;
	let raw: Result<MaterialId, MaterialError> =
		addMaterial(context, { ...texturedLit(context), texture0: 1, sampler0: 1 });
	assert raw.ok;
	if (!raw.ok) { return; }
	let rawItems: Vec<DrawItem> = [texturedItem(context, raw.value)];
	let rawFrame: Result<boolean, RendererError> =
		beginFrame(core, context, rawItems, shortCamera, lights);
	assert !rawFrame.ok && rawFrame.error == RendererError.CameraBlockLength;
	context.materials[bare.value.index].texture = FIRST_SLOT;
	let swapped: Result<boolean, RendererError> =
		beginFrame(core, context, bareItems, camera, lights);
	assert !swapped.ok && swapped.error == RendererError.TextureReplaced;
	assert core.generation == 0 && core.drawn.length == 0;
}

test "the forward preset passes a replaced texture on by name" {
	let capacity: int32 = FORWARD_UNIFORM_LENGTH + MATERIAL_UNIFORM_LENGTH;
	let context: DrawContext = DrawContext.withUniformCapacity(capacity);
	let background: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };
	let created: Result<ForwardRenderer, ForwardError> =
		ForwardRenderer.create(context, background);
	assert created.ok;
	if (!created.ok) { return; }
	let forward: ForwardRenderer = created.value;
	let material: Result<MaterialId, MaterialError> = addMaterial(context, texturedLit(context));
	assert material.ok;
	if (!material.ok) { return; }
	context.materials[material.value.index].texture = FIRST_SLOT;
	let items: Vec<DrawItem> = [texturedItem(context, material.value)];
	let camera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
	let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
	let refused: Result<int32, ForwardError> =
		renderFrame(forward, context, items, camera, lights, 640, 480);
	assert !refused.ok && refused.error == ForwardError.TextureReplaced;
	assert forward.core.generation == 0 && forward.colorTarget.image == 0;
}

test "a material names a texture only on a program that samples one at slot 0" {
	let context: DrawContext = DrawContext.withUniformCapacity(MATERIAL_UNIFORM_LENGTH);
	let lit: Material = {
		...texturedLit(context),
		program: Program.Lit,
		texture: FIRST_SLOT,
	};
	assert materialError(addMaterial(context, lit)) == MaterialError.TextureNotSampled;
	let particle: Material = {
		...Material.plain(Program.Particle, RenderState.defaults(), Phase.Opaque),
		texture: FIRST_SLOT,
	};
	assert materialError(addMaterial(context, particle)) == MaterialError.TextureNotSampled;
	assert context.liveMaterials() == 0;
}

test "each filter and wrap has a sampler slot of its own" {
	let taken: Vec<int32> = [0, 0, 0, 0, 0, 0];
	let filters: Vec<FilterMode> = [FilterMode.Nearest, FilterMode.Linear];
	let wraps: Vec<Wrap> = [Wrap.Clamp, Wrap.Repeat, Wrap.Mirror];
	for (const filter of filters) {
		for (const wrap of wraps) {
			let slot: int32 = samplerSlot(filter, wrap);
			assert slot >= 0 && slot < 6;
			taken[slot] = taken[slot] + 1;
		}
	}
	for (const count of taken) { assert count == 1; }
}

test "a screen draw refuses a material whose texture changed" {
	let context: DrawContext = DrawContext.withUniformCapacity(RENDERER_UNIFORM_LENGTH);
	let created: Result<Renderer, RendererError> = Renderer.create(context);
	assert created.ok;
	if (!created.ok) { return; }
	let core: Renderer = created.value;
	let copy: Material = Material.plain(Program.Copy, RenderState.defaults(), Phase.Opaque);
	let added: Result<MaterialId, MaterialError> = addMaterial(context, copy);
	assert added.ok;
	if (!added.ok) { return; }
	context.materials[added.value.index].texture = FIRST_SLOT;
	let drawn: Result<int32, RendererError> =
		drawScreen(core, context, added.value, SWAPCHAIN_LAYOUT);
	assert !drawn.ok && drawn.error == RendererError.TextureReplaced;
}

test "both presets refuse a frame whose own screen material's texture changed" {
	let camera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
	let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
	let none: Vec<DrawItem> = [];
	let background: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };
	let forwardContext: DrawContext = DrawContext.withUniformCapacity(FORWARD_UNIFORM_LENGTH);
	let forward: Result<ForwardRenderer, ForwardError> =
		ForwardRenderer.create(forwardContext, background);
	assert forward.ok;
	if (!forward.ok) { return; }
	let copy: ForwardRenderer = forward.value;
	forwardContext.materials[copy.copyMaterial.index].texture = FIRST_SLOT;
	let copied: Result<int32, ForwardError> =
		renderFrame(copy, forwardContext, none, camera, lights, 640, 480);
	assert !copied.ok && copied.error == ForwardError.TextureReplaced;
	let look: PixelArtLook = {
		background: background,
		outline: {
			depthThreshold: 0.006,
			normalThreshold: 0.6,
			depthShade: 0.55,
			normalShade: 1.35,
		},
		fog: { start: 0.5, end: 0.8, strength: 0.0, color: background },
		saturation: 0.0,
	};
	let view: LowResView = { width: 320, height: 240, scale: 1, offsetX: 0.0, offsetY: 0.0 };
	for (const post of [true, false]) {
		let context: DrawContext = DrawContext.withUniformCapacity(PIXEL_ART_UNIFORM_LENGTH);
		let created: Result<PixelArtRenderer, PixelArtError> =
			PixelArtRenderer.create(context, PixelArtSettings.full(), look);
		assert created.ok;
		if (!created.ok) { return; }
		let preset: PixelArtRenderer = created.value;
		let screen: MaterialId = post ? preset.postMaterial : preset.blitMaterial;
		context.materials[screen.index].texture = FIRST_SLOT;
		let drawn: Result<int32, PixelArtError> =
			renderPixelArt(preset, context, none, camera, lights, view);
		assert !drawn.ok && drawn.error == PixelArtError.TextureReplaced;
		assert preset.core.generation == 0;
	}
}
