import { Mat4, translation } from "../math/math3d";
import { Program } from "../void3d/gpu3d";
import { RenderState } from "../void3d/pass";
import { Material, Phase } from "../void3d/material";
import { DrawContext, DrawItem, addMaterial } from "../void3d/draw";
import { PassList, collect, sortBackToFront } from "../void3d/passList";
import { PipelineKey } from "../void3d/pipelineCache";
import { LowResView, ViewError, lowResView } from "../void3d/blit";
import {
	PaletteLut,
	PaletteError,
	DEFAULT_PALETTE_LEVELS,
	cellIndex,
	nearestColor,
	textureColor,
	fill,
} from "../void3d/palette";
import {
	PixelArtRenderer,
	PixelArtSettings,
	PixelArtError,
	DepthSource,
	Stage,
	PixelArtLook,
	PIXEL_ART_UNIFORM_LENGTH,
	planStages,
	screenKey,
	setSettings,
	setPalette,
} from "../void3d/pixelArtRenderer";
import { Renderer, RendererError, RENDERER_UNIFORM_LENGTH, markChanged } from "../void3d/renderer";

function look(): PixelArtLook {
	return {
		background: { x: 0.0, y: 0.0, z: 0.0, w: 0.0 },
		outline: {
			depthThreshold: 0.006,
			normalThreshold: 0.6,
			depthShade: 0.55,
			normalShade: 1.35,
		},
		fog: { start: 0.5, end: 0.8, strength: 0.85, color: { x: 0.02, y: 0.02, z: 0.07, w: 0.0 } },
	};
}

function view(
	width: int32,
	height: int32,
	shortSide: int32,
	divisor: int32,
	margin: int32,
): LowResView {
	const empty: LowResView = { width: 0, height: 0, scale: 0, offsetX: 0.0, offsetY: 0.0 };
	return try lowResView(width, height, shortSide, divisor, margin) catch empty;
}

// Levels in range always make a table.
function table(levels: int32): PaletteLut {
	const made: Result<PaletteLut, PaletteError> = PaletteLut.withLevels(levels);
	if (made.ok) { return made.value; }
	unreachable;
}

function sameStages(stages: Span<Stage>, expected: Span<Stage>): boolean {
	if (stages.length != expected.length) { return false; }
	for (let i = 0; i < (stages.length as int32); i++) {
		if (stages[i] != expected[i]) { return false; }
	}
	return true;
}

// The low-res texel a framebuffer pixel samples (blitFs).
function texelOf(pixel: int32, scale: int32, offset: float32): int32 {
	const position: float32 = (pixel as float32) + 0.5 + offset;
	return (position / (scale as float32)) as int32;
}

function contextWith(phases: Span<Phase>): DrawContext {
	let context: DrawContext = DrawContext.withUniformCapacity(0);
	for (const phase of phases) {
		addMaterial(context, Material.plain(Program.Lit, RenderState.defaults(), phase));
	}
	return context;
}

function itemAt(material: int32, depth: float32): DrawItem {
	const world: Mat4 = translation(0.0, 0.0, depth);
	return { mesh: 0, material: material, world: world };
}

test "a frame runs scene, post, then blit; without the post pass it blits the scene" {
	const full: Vec<Stage> = [Stage.Scene, Stage.Post, Stage.Blit];
	assert sameStages(planStages(PixelArtSettings.full()), full);
	assert sameStages(planStages(PixelArtSettings.preview()), full);
	const direct: Vec<Stage> = [Stage.Scene, Stage.Blit];
	assert sameStages(planStages({ ...PixelArtSettings.full(), postPass: false }), direct);
}

test "preview halves the resolution and drops the outline, nothing else" {
	const full: PixelArtSettings = PixelArtSettings.full();
	const preview: PixelArtSettings = PixelArtSettings.preview();
	assert preview.resolutionDivisor == 2 && full.resolutionDivisor == 1;
	assert !preview.outline && full.outline;
	assert preview.postPass && preview.palette == full.palette;
	assert preview.lowResShortSide == full.lowResShortSide && preview.margin == full.margin;
	assert preview.depthSource == full.depthSource;
	const hibernal: LowResView = view(1080, 2400, preview.lowResShortSide, 2, 0);
	assert hibernal.width == 180 && hibernal.height == 400 && hibernal.scale == 6;
}

test "Hibernal's framebuffer is 360x800 at 3x, centered with no offset" {
	const hibernal: LowResView = view(1080, 2400, 360, 1, 0);
	assert hibernal.width == 360 && hibernal.height == 800 && hibernal.scale == 3;
	assert hibernal.offsetX == 0.0 && hibernal.offsetY == 0.0;
	const landscape: LowResView = view(1280, 720, 360, 1, 0);
	assert landscape.width == 640 && landscape.height == 360 && landscape.scale == 2;
	const small: LowResView = view(320, 240, 360, 1, 0);
	assert small.scale == 1 && small.width == 320 && small.height == 240;
}

test "a framebuffer between whole texels is covered and centered" {
	// 1084 / 3 rounds up to 362 texels, 2 pixels too many: one hangs off each side.
	const odd: LowResView = view(1084, 2400, 360, 1, 0);
	assert odd.width == 362 && odd.offsetX == 1.0 && odd.offsetY == 0.0;
	assert texelOf(0, odd.scale, odd.offsetX) == 0;
	assert texelOf(1083, odd.scale, odd.offsetX) == odd.width - 1;
	for (let pixel = 0; pixel < 1084; pixel++) {
		const texel: int32 = texelOf(pixel, odd.scale, odd.offsetX);
		assert texel >= 0 && texel < odd.width;
	}
}

test "a margin adds texels on every side and the blit skips them" {
	const margin: LowResView = view(1080, 2400, 360, 1, 1);
	assert margin.width == 362 && margin.height == 802;
	assert margin.offsetX == 3.0 && margin.offsetY == 3.0;
	assert texelOf(0, margin.scale, margin.offsetX) == 1;
	assert texelOf(1079, margin.scale, margin.offsetX) == 360;
}

test "the sub-pixel remainder moves the sampling right and up" {
	const base: LowResView = view(1080, 2400, 360, 1, 1);
	const topLeft: LowResView = base.withRemainder(0.5, 0.25, true);
	assert topLeft.offsetX == 4.5 && topLeft.offsetY == 2.25;
	const bottomLeft: LowResView = base.withRemainder(0.5, 0.25, false);
	assert bottomLeft.offsetX == 4.5 && bottomLeft.offsetY == 3.75;
	// A remainder just under one texel never reaches past the margin.
	const most: LowResView = base.withRemainder(0.99, 0.0, true);
	assert texelOf(1079, most.scale, most.offsetX) == 361;
	assert !topLeft.sameAs(base) && base.withRemainder(0.0, 0.0, true).sameAs(base);
	const params: Vec<float32> = [0.0, 0.0, 0.0, 0.0];
	topLeft.writeBlitParams(params);
	assert params[0] == 3.0 && params[1] == 3.0 && params[2] == 4.5 && params[3] == 2.25;
}

test "a view is refused for an empty framebuffer or bad settings" {
	const empty: Result<LowResView, ViewError> = lowResView(0, 800, 360, 1, 0);
	assert !empty.ok;
	if (!empty.ok) { assert empty.error == ViewError.EmptyFramebuffer; }
	const divisor: Result<LowResView, ViewError> = lowResView(1080, 2400, 360, 0, 0);
	assert !divisor.ok;
	if (!divisor.ok) { assert divisor.error == ViewError.BadDivisor; }
	assert !lowResView(1080, 2400, 0, 1, 0).ok;
	assert !lowResView(1080, 2400, 360, 1, -1).ok;
}

test "the palette LUT lays cells out red + blue * levels across, green down" {
	assert cellIndex(16, 0, 0, 0) == 0;
	assert cellIndex(16, 1, 0, 0) == 1;
	assert cellIndex(16, 0, 0, 1) == 16;
	assert cellIndex(16, 0, 1, 0) == 256;
	assert cellIndex(16, 1, 2, 3) == 2 * 256 + 3 * 16 + 1;
	const lut: PaletteLut = table(16);
	assert lut.width() == 256 && lut.height() == 16;
	assert (lut.pixels.length as int32) == 16 * 16 * 16;
	assert textureColor(0x112233) == 0xFF332211;
}

test "an unfilled LUT keeps every color at its level" {
	const lut: Result<PaletteLut, PaletteError> = PaletteLut.withLevels(16);
	assert lut.ok;
	if (lut.ok) {
		const table: PaletteLut = lut.value;
		assert table.pixels[cellIndex(16, 0, 0, 0)] == 0xFF000000;
		assert table.pixels[cellIndex(16, 15, 0, 0)] == 0xFF0000FF;
		assert table.pixels[cellIndex(16, 0, 15, 0)] == 0xFF00FF00;
		assert table.pixels[cellIndex(16, 15, 15, 15)] == 0xFFFFFFFF;
		// Level 1 of 15 is 17 in a byte.
		assert table.pixels[cellIndex(16, 1, 0, 0)] == 0xFF000011;
		assert table.dirty;
	}
}

test "a filled LUT maps each cell to its nearest palette color" {
	let lut: PaletteLut = table(DEFAULT_PALETTE_LEVELS);
	lut.dirty = false;
	const palette: Vec<uint32> = [0x000000, 0xFFFFFF, 0xFF0000];
	const written: Result<int32, PaletteError> = fill(lut, palette);
	assert written.ok;
	if (written.ok) { assert written.value == 4096; }
	assert lut.dirty;
	assert lut.pixels[cellIndex(16, 0, 0, 0)] == textureColor(0x000000);
	assert lut.pixels[cellIndex(16, 15, 15, 15)] == textureColor(0xFFFFFF);
	assert lut.pixels[cellIndex(16, 15, 1, 1)] == textureColor(0xFF0000);
	assert lut.pixels[cellIndex(16, 2, 2, 2)] == textureColor(0x000000);
	// Green weighs most: dark green is nearer to black than a dark red of the same level.
	assert nearestColor(palette, 0.0, 0.3, 0.0) == 0;
	// A tie goes to the first color.
	const twins: Vec<uint32> = [0x808080, 0x808080];
	assert nearestColor(twins, 0.5, 0.5, 0.5) == 0;
}

test "a LUT refuses an empty palette and levels it cannot address" {
	assert !PaletteLut.withLevels(1).ok;
	assert !PaletteLut.withLevels(33).ok;
	assert PaletteLut.withLevels(32).ok;
	let lut: PaletteLut = table(4);
	const none: Vec<uint32> = [];
	const refused: Result<int32, PaletteError> = fill(lut, none);
	assert !refused.ok;
	if (!refused.ok) { assert refused.error == PaletteError.EmptyPalette; }
}

test "pass lists keep item order per phase and sort alpha back to front" {
	const phases: Vec<Phase> = [Phase.Opaque, Phase.Alpha, Phase.Additive];
	const context: DrawContext = contextWith(phases);
	const items: Vec<DrawItem> = [
		itemAt(0, 0.1),
		itemAt(1, 0.2),
		itemAt(0, 0.3),
		itemAt(2, 0.4),
		itemAt(1, 0.7),
		itemAt(1, 0.2),
	];
	let opaque: PassList = PassList.forPhase(Phase.Opaque);
	let alpha: PassList = PassList.forPhase(Phase.Alpha);
	let additive: PassList = PassList.forPhase(Phase.Additive);
	collect(opaque, items, context.materials);
	collect(alpha, items, context.materials);
	collect(additive, items, context.materials);
	assert opaque.count == 2 && opaque.indices[0] == 0 && opaque.indices[1] == 2;
	assert additive.count == 1 && additive.indices[0] == 3;
	assert alpha.count == 3 && alpha.indices[0] == 1 && alpha.indices[1] == 4;
	// Clip z = world z: the camera block's third column is (0, 0, 1, 0).
	const camera: Vec<float32> = new Array(24);
	for (let i = 0; i < 24; i++) {
		camera[i] = 0.0;
	}
	camera[10] = 1.0;
	sortBackToFront(alpha, items, camera);
	assert alpha.indices[0] == 4;
	// Items 1 and 5 share a depth and keep their order.
	assert alpha.indices[1] == 1 && alpha.indices[2] == 5;
	// Collecting the same items again reuses the storage.
	const capacity: int32 = alpha.indices.length as int32;
	collect(alpha, items, context.materials);
	assert (alpha.indices.length as int32) == capacity && alpha.count == 3;
}

test "screen passes have one pipeline each, whatever the settings or palette" {
	const post: string = "program=Post layout=Fullscreen indexType=None" +
		" colors=Rgba8 depth=None sampleCount=1" +
		" culling=None depthWrite=false depthTest=Always blend=One,Zero alphaBlend=One,Zero" +
		" operation=Add,Add colorMask=15";
	const postKey: PipelineKey = screenKey(Stage.Post);
	assert postKey.toString() == post;
	const blit: string = screenKey(Stage.Blit).toString();
	assert blit.indexOf("program=Blit layout=Fullscreen indexType=None colors=Default depth=Default") == 0;
	assert screenKey(Stage.Post).bits != screenKey(Stage.Blit).bits;
}

test "post parameters carry the look, the switches and the depth unpack" {
	const values: Vec<float32> = new Array(20);
	look().writePostParams(PixelArtSettings.full(), 16, true, values);
	const style: PixelArtLook = look();
	assert values[0] == style.outline.depthThreshold && values[3] == style.outline.normalShade;
	assert values[4] == style.fog.start && values[6] == style.fog.strength;
	assert values[10] == style.fog.color.z;
	assert values[12] == 1.0 && values[13] == 0.0 && values[14] == 0.0 && values[15] == 16.0;
	assert values[16] == 1.0 && values[17] == 0.0;
	const every: PixelArtSettings = {
		...PixelArtSettings.preview(),
		palette: true,
		depthSource: DepthSource.DepthTexture,
	};
	look().writePostParams(every, 32, false, values);
	assert values[12] == 0.0 && values[13] == 1.0 && values[14] == 1.0 && values[15] == 32.0;
	// GL keeps (z + 1) / 2 in its depth buffer.
	assert values[16] == 2.0 && values[17] == -1.0;
}

test "a renderer needs a frame until one is drawn, then only when something changed" {
	let small: DrawContext = DrawContext.withUniformCapacity(PIXEL_ART_UNIFORM_LENGTH - 1);
	const refused: Result<PixelArtRenderer, PixelArtError> = PixelArtRenderer.create(
		small,
		PixelArtSettings.full(),
		look(),
	);
	assert !refused.ok;
	let context: DrawContext = DrawContext.withUniformCapacity(PIXEL_ART_UNIFORM_LENGTH);
	const created: Result<PixelArtRenderer, PixelArtError> = PixelArtRenderer.create(
		context,
		PixelArtSettings.full(),
		look(),
	);
	assert created.ok;
	if (created.ok) {
		let renderer: PixelArtRenderer = created.value;
		assert (context.materials.length as int32) == 2 && (context.meshes.length as int32) == 1;
		assert context.uniformsUsed == PIXEL_ART_UNIFORM_LENGTH;
		const drawn: LowResView = view(1080, 2400, 360, 1, 0);
		assert renderer.needsFrame(drawn);
		// What renderFrame records once it has drawn `drawn`.
		renderer.view = drawn;
		renderer.core.changed = false;
		renderer.core.generation = 1;
		assert !renderer.needsFrame(drawn);
		assert renderer.needsFrame(drawn.withRemainder(0.5, 0.0, true));
		markChanged(renderer.core);
		assert renderer.needsFrame(drawn);
		renderer.core.changed = false;
		setSettings(renderer, { ...PixelArtSettings.full(), postPass: false });
		assert renderer.needsFrame(drawn);
		const direct: Vec<Stage> = [Stage.Scene, Stage.Blit];
		assert sameStages(renderer.stages, direct);
		renderer.core.changed = false;
		const palette: Vec<uint32> = [0x101010];
		assert setPalette(renderer, palette).ok;
		assert renderer.needsFrame(drawn) && renderer.palette.dirty;
	}
}

test "the core reserves the camera and light blocks and one screen mesh, nothing else" {
	let small: DrawContext = DrawContext.withUniformCapacity(RENDERER_UNIFORM_LENGTH - 1);
	const refused: Result<Renderer, RendererError> = Renderer.create(small);
	assert !refused.ok;
	let context: DrawContext = DrawContext.withUniformCapacity(RENDERER_UNIFORM_LENGTH);
	const created: Result<Renderer, RendererError> = Renderer.create(context);
	assert created.ok;
	if (created.ok) {
		let core: Renderer = created.value;
		assert context.uniformsUsed == RENDERER_UNIFORM_LENGTH;
		assert (context.meshes.length as int32) == 1 && (context.materials.length as int32) == 0;
		assert core.cameraBlock.offset == 0 && core.lightBlock.offset == core.cameraBlock.length;
		assert core.sceneGlobals.length == 2;
		assert core.needsFrame();
		core.changed = false;
		core.generation = 1;
		assert !core.needsFrame();
		markChanged(core);
		assert core.needsFrame();
	}
}
