import { Mat4, Vec4, identity } from "../math/math3d";
import { RenderState, FilterMode, Wrap } from "../gpu/state";
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
	reserveUniforms,
} from "../void3d/draw";
import {
	Renderer,
	RendererError,
	RENDERER_UNIFORM_LENGTH,
	beginFrame,
} from "../void3d/renderer";
import {
	ForwardRenderer,
	ForwardError,
	FORWARD_UNIFORM_LENGTH,
	renderFrame,
} from "../void3d/forwardRenderer";
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
