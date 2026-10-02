import { Vec4 } from "../math/math3d";
import { contextGeneration } from "../gpu/door";
import { DrawContext } from "../void3d/draw";
import { UniformPool } from "../void3d/uniformPool";
import { PaletteLut, PaletteError, closePalette, releaseGpu } from "../void3d/palette";
import { Renderer, RendererError, RENDERER_UNIFORM_LENGTH, closeRenderer } from "../void3d/renderer";
import {
	ForwardRenderer,
	ForwardError,
	FORWARD_UNIFORM_LENGTH,
	closeForward,
} from "../void3d/forwardRenderer";
import {
	PixelArtRenderer,
	PixelArtSettings,
	PixelArtLook,
	PixelArtError,
	PIXEL_ART_UNIFORM_LENGTH,
	closePixelArt,
} from "../void3d/pixelArtRenderer";
import { LowResView } from "../void3d/blit";

const BLACK: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };

function forwardOn(context: DrawContext): ForwardRenderer {
	const made: Result<ForwardRenderer, ForwardError> = ForwardRenderer.create(context, BLACK);
	if (!made.ok) { unreachable; }
	return made.value;
}

function pixelArtOn(context: DrawContext): PixelArtRenderer {
	const look: PixelArtLook = {
		background: BLACK,
		outline: {
			depthThreshold: 0.006,
			normalThreshold: 0.6,
			depthShade: 0.55,
			normalShade: 1.35,
		},
		fog: { start: 0.5, end: 0.8, strength: 0.0, color: BLACK },
		saturation: 0.0,
	};
	const made: Result<PixelArtRenderer, PixelArtError> =
		PixelArtRenderer.create(context, PixelArtSettings.full(), look);
	if (!made.ok) { unreachable; }
	return made.value;
}

test "closing the core gives its screen mesh and both blocks back, once" {
	let context: DrawContext = DrawContext.withUniformCapacity(RENDERER_UNIFORM_LENGTH);
	const made: Result<Renderer, RendererError> = Renderer.create(context);
	assert made.ok;
	if (!made.ok) { return; }
	let core: Renderer = made.value;
	assert core.context.serial == context.serial && context.liveMeshes() == 1;
	assert context.uniforms.isOwned(core.cameraBlock) && context.uniforms.isOwned(core.lightBlock);
	let alias: Renderer = core;
	closeRenderer(alias);
	assert core.isClosed() && !core.needsFrame();
	assert context.liveMeshes() == 0;
	assert !context.uniforms.holds(core.cameraBlock) && !context.uniforms.holds(core.lightBlock);
}

test "closing a forward preset gives back its copy material and closes its core" {
	let context: DrawContext = DrawContext.withUniformCapacity(FORWARD_UNIFORM_LENGTH);
	let forward: ForwardRenderer = forwardOn(context);
	assert context.liveMeshes() == 1 && context.liveMaterials() == 1;
	let alias: ForwardRenderer = forward;
	closeForward(alias);
	assert forward.isClosed() && forward.core.isClosed();
	assert context.liveMeshes() == 0 && context.liveMaterials() == 0;
	assert !context.uniforms.holds(forward.core.cameraBlock);
	assert forward.colorTarget.image == 0 && forward.sampler.handle == 0;
}

test "a forward preset skips a core an alias already closed" {
	let context: DrawContext = DrawContext.withUniformCapacity(FORWARD_UNIFORM_LENGTH);
	let forward: ForwardRenderer = forwardOn(context);
	let core: Renderer = forward.core;
	closeRenderer(core);
	assert forward.core.isClosed() && !forward.isClosed();
	closeForward(forward);
	assert forward.isClosed() && context.liveMeshes() == 0 && context.liveMaterials() == 0;
}

test "closing a pixel-art preset gives back both screen materials and closes its table and core" {
	let context: DrawContext = DrawContext.withUniformCapacity(PIXEL_ART_UNIFORM_LENGTH);
	let pixelArt: PixelArtRenderer = pixelArtOn(context);
	assert context.liveMeshes() == 1 && context.liveMaterials() == 2;
	let palette: PaletteLut = pixelArt.palette;
	closePixelArt(pixelArt);
	assert pixelArt.isClosed() && pixelArt.core.isClosed() && palette.isClosed();
	assert context.liveMeshes() == 0 && context.liveMaterials() == 0;
	assert !context.uniforms.holds(pixelArt.postBlock) && !context.uniforms.holds(pixelArt.blitBlock);
	let view: LowResView = { width: 32, height: 24, scale: 1, offsetX: 0.0, offsetY: 0.0 };
	assert !pixelArt.needsFrame(view);
}

test "a pixel-art preset skips a table an alias already closed" {
	let context: DrawContext = DrawContext.withUniformCapacity(PIXEL_ART_UNIFORM_LENGTH);
	let pixelArt: PixelArtRenderer = pixelArtOn(context);
	closePalette(pixelArt.palette);
	closePixelArt(pixelArt);
	assert pixelArt.isClosed() && context.liveMaterials() == 0;
}

test "a palette table made under an older GPU context forgets its image instead of destroying it" {
	const made: Result<PaletteLut, PaletteError> = PaletteLut.withLevels(4);
	assert made.ok;
	if (!made.ok) { return; }
	let lut: PaletteLut = made.value;
	let alias: PaletteLut = lut;
	alias.image = 7;
	alias.texture = 9;
	alias.generation = contextGeneration() + 1;
	alias.dirty = false;
	releaseGpu(lut);
	assert alias.image == 0 && alias.texture == 0 && alias.generation == 0 && alias.dirty;
	alias.image = 7;
	alias.texture = 9;
	alias.generation = contextGeneration() + 1;
	closePalette(alias);
	assert lut.isClosed() && lut.image == 0 && lut.texture == 0;
}
