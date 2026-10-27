import { exit } from "std/process";
import {
	DOOR_BUFFER_VERTEX, PixelFormat, PassState, doorValid, doorOriginTopLeft,
	doorContextGeneration, doorMakeBuffer, doorMakeBufferOf, doorDestroyBuffer, doorAppendBufferOf,
	doorUpdateBufferOf, doorMakeTexture, doorMakeTextureView, doorDestroyView, doorDestroyImage,
	doorUpdateTexture, doorUpdateTextureRect, doorMakeSampler, doorViewIsColorAttachment,
	doorApplyPipeline, doorApplyBindings, doorApplyUniformsOf, doorApplyScissor, doorDraw,
	doorBeginColorPass, doorEndPass, doorPassState,
} from "../gpu/doorGpu.ms";
import {
	DOOR_BINDING_LENGTH, DOOR_BINDING_SAMPLER, DOOR_BINDING_VIEW,
} from "../gpu/doorWords.h";
import {
	CMD_KIND, CMD_VERTEX_OFFSET, CMD_VERTEX_COUNT, CMD_BLEND, CMD_SAMPLER, commandViewOf,
	CMD_EFFECT, CMD_ARG0, CMD_ARG1, CMD_RT_MODE, CMD_CLEAR_R, CMD_PIPELINE, CMD_INSTANCE_OFFSET,
	CMD_INSTANCE_COUNT, CMD_CLIP_U_X, CMD_SCOPE, CMD_CLIP_ROUND_U, COMMAND_FLOATS, SAMPLER_COUNT,
	NO_SCOPE,
} from "./commandFields";
import {
	CommandKind, Pipeline, Program2D, PROGRAMS_2D, BLEND_MODES, EFFECT_FLOATS, VERTEX_FLOATS,
} from "./displayList";
import {
	INITIAL_BUFFER_BYTES, MAX_BUFFER_BYTES, ScissorRect, truncated, deviceScaleOf,
	scopeAt, scissorRectOf, growthTarget,
} from "./coverage";
import {
	UI_STRIDE, SPRITE_STRIDE, REC_UI_FLOATS, REC_SPRITE_FLOATS, REC_UI_COLOR_FILL,
	REC_UI_COLOR_BORDER, REC_UI_COLOR_EXTRA,
} from "./instanceLayout";
import { packChannel } from "./instance";
import { floatBits } from "./floatBits";
import {
	UB_void2d_params, UB_void2d_fx, UB_sprite_params, UB_ui_params, UB_ui_fx, UB_blur_params,
	VIEW_tex, VIEW_spriteTex, VIEW_uiTex, VIEW_srcTex, SMP_smp, SMP_spriteSmp, SMP_uiSmp, SMP_srcSmp,
	void2d_params_FLOATS, void2d_params_viewport, void2d_params_model0, void2d_params_model1,
	void2d_params_globalColor, void2d_params_clipU, void2d_params_clipV, void2d_params_clipRoundU,
	void2d_params_clipRoundV, void2d_params_clipRadii, void2d_params_shift,
	void2d_fx_FLOATS, void2d_fx_colorMatrix, void2d_fx_colorAdd, void2d_fx_colorKey,
	void2d_fx_gradientMeta, void2d_fx_gradientParams, void2d_fx_gradientColor0,
	void2d_fx_gradientColor1, void2d_fx_gradientColor2, void2d_fx_gammaRatios,
	void2d_fx_textParams, void2d_fx_sourceParams,
	sprite_params_FLOATS, sprite_params_viewport, sprite_params_clipU, sprite_params_clipV,
	sprite_params_clipRoundU, sprite_params_clipRoundV, sprite_params_clipRadii,
	sprite_params_shift,
	ui_params_FLOATS, ui_params_viewport, ui_params_clipU, ui_params_clipV, ui_params_clipRoundU,
	ui_params_clipRoundV, ui_params_clipRadii, ui_params_shift,
	ui_fx_FLOATS, ui_fx_gammaRatios, ui_fx_textParams, ui_fx_colorMatrix, ui_fx_colorAdd,
	ui_fx_colorKey, ui_fx_effectParams,
	blur_params_FLOATS, blur_params_dir,
} from "./shader2dSlots";
import {
	MAX_GLYPH_PAGES, PAGE_COVERAGE, PAGE_SDF, PAGE_RGBA, PAGE_MASK, state,
} from "./glyph/state";
import {
	void2dGlyphPageCount, void2dGlyphPageGeneration, void2dGlyphPageKind, void2dGlyphPageSize,
	void2dGlyphPageBytes, void2dGlyphPageTakeUpload, void2dGlyphPageUploadBox,
	void2dGlyphPagesFrameBegin, void2dGlyphPagesMarkDirty,
} from "./glyph";
when (voidProfiler) {
	import { scissorMax, clippedArea, quadClippedArea } from "./coverage";
	import { clockNow } from "../platform/clockNow";
	import {
		DOOR_STAT_DRAWS, DOOR_STAT_PIPELINES, DOOR_STAT_PASSES, DOOR_STAT_BUFFER_BYTES,
		DOOR_STAT_IMAGE_BYTES, doorFrameStat,
	} from "../gpu/doorGpu.ms";
	import {
		frameClock, profileBegin, VOID2D_COUNTER_SLOTS, COUNTER_DRAWS, COUNTER_UI_INSTANCES,
		COUNTER_SPRITE_INSTANCES, COUNTER_UPLOAD_BYTES, COUNTER_UPLOADS, COUNTER_COVERED_PIXELS,
		COUNTER_TARGET_PIXELS, COUNTER_OPAQUE_PIXELS, COUNTER_FRAME_PIXELS,
	} from "./frameClock";
}

const TARGET_PASS: int32 = PassState.Target as int32;
const RGBA8: int32 = PixelFormat.Rgba8 as int32;
const R8: int32 = PixelFormat.R8 as int32;
const KIND_DRAW: int32 = CommandKind.Draw as int32;
const KIND_SCISSOR: int32 = CommandKind.Scissor as int32;
const KIND_BLUR: int32 = CommandKind.Blur as int32;
const KIND_TARGET_BEGIN: int32 = CommandKind.TargetBegin as int32;
const KIND_TARGET_END: int32 = CommandKind.TargetEnd as int32;
const PIPELINE_SPRITE: int32 = Pipeline.Sprite as int32;
const PIPELINE_UI: int32 = Pipeline.Ui as int32;
const PROGRAM_VERTEX: int32 = Program2D.Vertex as int32;
const PROGRAM_SPRITE: int32 = Program2D.Sprite as int32;
const PROGRAM_UI: int32 = Program2D.Ui as int32;
const PROGRAM_BLUR: int32 = Program2D.Blur as int32;

const SAMPLER_NEAREST: int32 = 0;
const SAMPLER_LINEAR: int32 = 1;
const SAMPLER_CLAMP: int32 = 0;
const SAMPLER_REPEAT: int32 = 1;
const BRACKETS_BEFORE_COMPLAINT: int32 = 16;
const MAX_RETIRED_BUFFERS: int32 = 8;
const MAX_TARGET_DEPTH: int32 = 8;
const UI_WORDS: int32 = UI_STRIDE / 4;
const UI_FLOAT_WORDS: int32 = 24;
const ONE_BITS: uint32 = 0x3F800000;
const BLEND_NONE: int32 = 0;
const BLEND_ALPHA: int32 = 1;
const LIST_VERTEX: int32 = 0;
const LIST_SPRITE: int32 = 1;
const LIST_UI: int32 = 2;

const UNIT_QUAD: float32[] = [
	0.0, 0.0, 1.0, 0.0, 1.0, 1.0,
	0.0, 0.0, 1.0, 1.0, 0.0, 1.0,
];
const FULLSCREEN_QUAD: float32[] = [
	-1.0, -1.0, 0.0, 0.0, 1.0, -1.0, 1.0, 0.0, 1.0, 1.0, 1.0, 1.0,
	-1.0, -1.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0, -1.0, 1.0, 0.0, 1.0,
];
const WHITE_TEXEL: uint8[] = [255, 255, 255, 255];

class PreparedContext {
	srcVertex: uint32 = 0;
	srcSprite: uint32 = 0;
	srcUi: uint32 = 0;
	srcVertexBase: int32 = 0;
	srcSpriteBase: int32 = 0;
	srcUiBase: int32 = 0;
	spriteInstanceCount: int32 = 0;
	uiInstanceCount: int32 = 0;
	frameUploaded: boolean = false;
	frameSerial: int32 = 0;
	prepared: boolean = false;
	live: boolean = false;
}

class DisplayList {
	buf: uint32[] = [0, 0, 0];
	cap: int32[] = [0, 0, 0];
	updatedFrame: int32 = -1;
	stale: boolean = false;
	stage: uint32[] = [];
}

function fail(message: string): never {
	console.error(message);
	exit(1);
}

function zeroFloats(count: int32): float32[] {
	const values: float32[] = [];
	for (let i: int32 = 0; i < count; i++) { values.push(0.0); }
	return values;
}

function zeroWords(count: int32): uint32[] {
	const values: uint32[] = [];
	for (let i: int32 = 0; i < count; i++) { values.push(0); }
	return values;
}

function clearWords(values: uint32[]): void {
	while ((values.length as int32) > 0) { values.pop(); }
}

let vbuf: uint32 = 0;
let vbufBytes: int32 = 0;
let frameBaseOffset: int32 = 0;
let frameUploaded: boolean = false;
let uiInstanceBase: int32 = 0;
let uiInstanceCount: int32 = 0;
let unitQuad: uint32 = 0;
let spriteInstanceBase: int32 = 0;
let spriteInstanceCount: int32 = 0;
let srcVertex: uint32 = 0;
let srcSprite: uint32 = 0;
let srcUi: uint32 = 0;
let srcVertexBase: int32 = 0;
let srcSpriteBase: int32 = 0;
let srcUiBase: int32 = 0;
let originTopLeft: boolean = false;
let dpiScale: float32 = 1.0;
let fsQuad: uint32 = 0;
let whiteView: uint32 = 0;
const samplers: uint32[] = zeroWords(SAMPLER_COUNT);
const pipelines: uint32[] = zeroWords(PROGRAMS_2D * 2 * BLEND_MODES);
const pageImg: uint32[] = zeroWords(MAX_GLYPH_PAGES);
const pageView: uint32[] = zeroWords(MAX_GLYPH_PAGES);
const pageGen: uint32[] = zeroWords(MAX_GLYPH_PAGES);
let atlasMade: int32 = 0;
let glyphUploads: int32 = 0;
const textGamma: float32[] = zeroFloats(4);
let textContrast: float32 = 1.0;
let glyphUploadBytes: int32 = 0;
let buffersMade: int32 = 0;
let buffersFreed: int32 = 0;
let frameOpen: boolean = false;
let bracketsThisFrame: int32 = 0;
let frameEndMissingReported: boolean = false;
let frameSerial: int32 = 0;
let frameVertexBytes: int32 = 0;
const retiredBuf: uint32[] = [];
const closedBuf: uint32[] = [];
let drawCallCount: int32 = 0;
let uploadCount: int32 = 0;
let uploadBytes: int32 = 0;
let droppedFrames: int32 = 0;
let generation: int32 = 0;
const contexts: PreparedContext[] = [];
const lists: DisplayList[] = [];
const uiStage: uint32[] = [];

let frameUiInstances: int32 = 0;
let frameSpriteInstances: int32 = 0;
let coveredSwapchain: float64 = 0.0;
let coveredTargets: float64 = 0.0;
let coveredOpaque: float64 = 0.0;
let swapchainPixels: int32 = 0;
let swapchainPass: boolean = false;

let lastPipeline: uint32 = 0;
let paramsValid: boolean = false;
let fxValid: boolean = false;
let scissorApplied: boolean = false;
const vertexParams: float32[] = zeroFloats(void2d_params_FLOATS);
const lastVertexParams: float32[] = zeroFloats(void2d_params_FLOATS);
const vertexFx: float32[] = zeroFloats(void2d_fx_FLOATS);
const lastVertexFx: float32[] = zeroFloats(void2d_fx_FLOATS);
const spriteParams: float32[] = zeroFloats(sprite_params_FLOATS);
const uiParams: float32[] = zeroFloats(ui_params_FLOATS);
const uiFx: float32[] = zeroFloats(ui_fx_FLOATS);
const blurParams: float32[] = zeroFloats(blur_params_FLOATS);
const bindWords: uint32[] = [];
const bindOffsets: int32[] = [0, 0];

export function void2dDrawCallCount(): int32 { return drawCallCount; }
export function void2dUploadCount(): int32 { return uploadCount; }
export function void2dUploadBytes(): int32 { return uploadBytes; }
export function void2dVertexBufferBytes(): int32 { return vbufBytes; }
export function void2dDroppedFrames(): int32 { return droppedFrames; }
export function void2dBuffersAlive(): int32 { return buffersMade - buffersFreed; }
export function void2dAtlasImagesAlive(): int32 { return atlasMade; }
export function void2dGlyphUploadCount(): int32 { return glyphUploads; }
export function void2dGlyphUploadBytes(): int32 { return glyphUploadBytes; }
export function void2dFrameSerial(): int32 { return frameSerial; }
export function void2dWhiteView(): uint32 { return whiteView; }

export function void2dFailPendingTargets(): never {
	fail("void2d: end2d with render-target commands pending; call flushTargets first");
}

export function void2dSetTextGamma(
	r0: float32, r1: float32, r2: float32, r3: float32, contrast: float32,
): void {
	textGamma[0] = r0;
	textGamma[1] = r1;
	textGamma[2] = r2;
	textGamma[3] = r3;
	textContrast = contrast;
}

export function void2dSetDpiScale(scale: float32): void {
	if (scale > 0.0) { dpiScale = scale; }
}

function field(cmd: Readonly<Span<float32>>, index: int32): int32 {
	return truncated(cmd[index] as float64);
}

function growWords(words: uint32[], count: int32): void {
	while ((words.length as int32) < count) { words.push(0); }
}

function packColor(records: Readonly<Span<float32>>, at: int32): uint32 {
	return (packChannel(records[at]) as uint32) |
		((packChannel(records[at + 1]) as uint32) << 8) |
		((packChannel(records[at + 2]) as uint32) << 16) |
		((packChannel(records[at + 3]) as uint32) << 24);
}

export function packUiInstance(
	stage: uint32[], instance: int32, records: Readonly<Span<float32>>,
): void {
	const to: int32 = instance * UI_WORDS;
	const from: int32 = instance * REC_UI_FLOATS;
	for (let i: int32 = 0; i < UI_FLOAT_WORDS; i++) { stage[to + i] = floatBits(records[from + i]); }
	stage[to + UI_FLOAT_WORDS] = packColor(records, from + REC_UI_COLOR_FILL);
	stage[to + UI_FLOAT_WORDS + 1] = packColor(records, from + REC_UI_COLOR_BORDER);
	stage[to + UI_FLOAT_WORDS + 2] = packColor(records, from + REC_UI_COLOR_EXTRA);
}

function releaseRetiredBuffers(): void {
	for (let i: int32 = 0; i < (retiredBuf.length as int32); i++) {
		doorDestroyBuffer(retiredBuf[i]);
		buffersFreed++;
	}
	clearWords(retiredBuf);
	for (let i: int32 = 0; i < (closedBuf.length as int32); i++) {
		doorDestroyBuffer(closedBuf[i]);
		buffersFreed++;
	}
	clearWords(closedBuf);
}

function makeBuffer(bytes: int32, what: string): uint32 {
	const id: uint32 = doorMakeBuffer(DOOR_BUFFER_VERTEX, [], bytes as int64);
	if (id == 0) { fail(`void2d: the door made no ${bytes}-byte ${what} buffer`); }
	return id;
}

function makeStaticBuffer(data: Readonly<Span<float32>>, what: string): uint32 {
	const id: uint32 = doorMakeBufferOf(DOOR_BUFFER_VERTEX, data);
	if (id == 0) { fail(`void2d: the door made no ${data.length * 4}-byte ${what} buffer`); }
	return id;
}

function ensureVertexBuffer(bytes: int32): boolean {
	const want: int32 = growthTarget(vbufBytes, bytes);
	if (want <= vbufBytes) { return true; }
	if (vbuf != 0) {
		if ((retiredBuf.length as int32) >= MAX_RETIRED_BUFFERS) {
			console.error(
				`void2d: more than ${MAX_RETIRED_BUFFERS} vertex-buffer growths in one frame — frame dropped`,
			);
			return false;
		}
		retiredBuf.push(vbuf);
	}
	vbuf = makeBuffer(want, "frame vertex");
	buffersMade++;
	vbufBytes = want;
	return true;
}

export function void2dSetPipeline(
	program: int32, target: int32, blend: int32, pipeline: uint32,
): void {
	if (program < 0 || program >= PROGRAMS_2D || target < 0 || target > 1 || blend < 0 ||
		blend >= BLEND_MODES) {
		fail(`void2d: no pipeline slot for program ${program}, target ${target}, blend ${blend}`);
	}
	pipelines[(program * 2 + target) * BLEND_MODES + blend] = pipeline;
}

function pipelineAt(program: int32, target: int32, blend: int32): uint32 {
	const inRange: boolean = program >= 0 && program < PROGRAMS_2D && target >= 0 && target <= 1 &&
		blend >= 0 && blend < BLEND_MODES;
	const id: uint32 = inRange ? pipelines[(program * 2 + target) * BLEND_MODES + blend] : 0;
	if (id == 0) {
		fail(
			`void2d: replay reached program ${program}, ${target != 0 ? "offscreen" : "screen"} ` +
			`target, blend ${blend}, which flushTargets did not prepare`,
		);
	}
	return id;
}

function sourceOf(cmd: Readonly<Span<float32>>): int32 {
	const source: int32 = field(cmd, CMD_SAMPLER);
	if (source < 0 || source >= 2 * SAMPLER_COUNT) {
		fail(`void2d: a command's sampler field is ${source}, outside 0..${2 * SAMPLER_COUNT - 1}`);
	}
	return source;
}

function samplerOf(cmd: Readonly<Span<float32>>): int32 { return sourceOf(cmd) % SAMPLER_COUNT; }

function premultipliedSource(cmd: Readonly<Span<float32>>): boolean {
	return sourceOf(cmd) >= SAMPLER_COUNT;
}

function sampledTarget(view: uint32): boolean { return doorViewIsColorAttachment(view) != 0; }

function makeContextResources(): void {
	ensureVertexBuffer(INITIAL_BUFFER_BYTES);
	originTopLeft = doorOriginTopLeft() != 0;
	unitQuad = makeStaticBuffer(UNIT_QUAD, "unit quad");
	buffersMade++;
	fsQuad = makeStaticBuffer(FULLSCREEN_QUAD, "fullscreen quad");
	buffersMade++;
	whiteView = doorMakeTextureView(doorMakeTexture(1, 1, RGBA8, WHITE_TEXEL));
	for (let i: int32 = 0; i < SAMPLER_COUNT; i++) {
		const smooth: boolean = (i & 2) != 0;
		const wrap: boolean = (i & 1) != 0;
		samplers[i] = doorMakeSampler(
			smooth ? SAMPLER_LINEAR : SAMPLER_NEAREST, wrap ? SAMPLER_REPEAT : SAMPLER_CLAMP,
		);
	}
	generation = doorContextGeneration();
}

export function void2dSetup(): void { makeContextResources(); }

function dropReleasedPageImage(page: int32): void {
	if (pageImg[page] == 0 || pageGen[page] == void2dGlyphPageGeneration(page)) { return; }
	doorDestroyView(pageView[page]);
	doorDestroyImage(pageImg[page]);
	pageImg[page] = 0;
	pageView[page] = 0;
}

export function void2dGlyphPageView(page: int32): uint32 {
	if (page < 0 || page >= MAX_GLYPH_PAGES || doorValid() == 0) { return 0; }
	dropReleasedPageImage(page);
	if (pageImg[page] == 0) {
		const pageGeneration: uint32 = void2dGlyphPageGeneration(page);
		if (pageGeneration == 0) { return 0; }
		const size: int32 = void2dGlyphPageSize(page);
		if (size <= 0) { return 0; }
		const kind: int32 = void2dGlyphPageKind(page);
		if (kind != PAGE_COVERAGE && kind != PAGE_SDF && kind != PAGE_RGBA && kind != PAGE_MASK) {
			console.error(`void2d: no image format for glyph page ${page} of kind ${kind}`);
			return 0;
		}
		pageImg[page] = doorMakeTexture(size, size, kind == PAGE_RGBA ? RGBA8 : R8, []);
		pageView[page] = doorMakeTextureView(pageImg[page]);
		pageGen[page] = pageGeneration;
		atlasMade++;
	}
	return pageView[page];
}

function glyphPageViewKind(view: uint32): int32 {
	if (view == 0) { return -1; }
	for (let i: int32 = 0; i < MAX_GLYPH_PAGES; i++) {
		if (pageView[i] == view) {
			const kind: int32 = void2dGlyphPageKind(i);
			return kind < 0 ? -2 : kind;
		}
	}
	return -1;
}

function glyphPageViewMode(view: uint32): float32 {
	const kind: int32 = glyphPageViewKind(view);
	if (kind == -1) { return 0.0; }
	if (kind == PAGE_COVERAGE) { return 1.0; }
	if (kind == PAGE_SDF) { return 2.0; }
	if (kind == PAGE_MASK) { return 1.0; }
	if (kind == PAGE_RGBA) { return 0.0; }
	fail(`void2d: glyph page view ${view} of kind ${kind} has no shader mode`);
}

function applyScissor(
	cmd: Readonly<Span<float32>>, scopes: Readonly<Span<float32>>, scopeCount: int32,
	fbW: float32, fbH: float32,
): void {
	const rect: ScissorRect = scissorRectOf(
		cmd, scopes, scopeAt(cmd, scopeCount, scopes.length > 0), dpiScale, fbW, fbH,
	);
	doorApplyScissor(rect.x0, rect.y0, rect.x1 - rect.x0, rect.y1 - rect.y0);
}

when (voidProfiler) {
	function addCoverage(area: float64, opaque: boolean): void {
		if (swapchainPass) {
			coveredSwapchain += area;
			if (opaque) { coveredOpaque += area; }
		} else {
			coveredTargets += area;
		}
	}

	function opaqueBlend(blend: int32): boolean { return blend == BLEND_NONE || blend == BLEND_ALPHA; }

	function coverAffineQuad(
		affine: Readonly<Span<float32>>, at: int32, ox: float64, oy: float64, lx0: float64,
		ly0: float64, lx1: float64, ly1: float64, cmd: Readonly<Span<float32>>,
		scopes: Readonly<Span<float32>>, scope: int32, rect: ScissorRect, opaque: boolean,
		blend: int32,
	): void {
		const shiftX: float64 = scope >= 0 ? scopes[scope] as float64 : 0.0;
		const shiftY: float64 = scope >= 0 ? scopes[scope + 1] as float64 : 0.0;
		const area: float64 = quadClippedArea(
			affine, at, ox + shiftX, oy + shiftY, lx0, ly0, lx1, ly1,
			deviceScaleOf(cmd, dpiScale) as float64, rect,
		);
		addCoverage(area, opaque && opaqueBlend(blend));
	}

	function coverUiRun(
		cmd: Readonly<Span<float32>>, count: int32, blend: int32, fbW: float32, fbH: float32,
		scopes: Readonly<Span<float32>>, scopeCount: int32, cpuUi: Readonly<Span<float32>>,
	): void {
		if (cpuUi.length == 0) { return; }
		const scope: int32 = scopeAt(cmd, scopeCount, scopes.length > 0);
		const rect: ScissorRect = scissorRectOf(cmd, scopes, scope, dpiScale, fbW, fbH);
		const scale: float64 = deviceScaleOf(cmd, dpiScale) as float64;
		const effected: boolean = field(cmd, CMD_EFFECT) >= 0;
		for (let i: int32 = 0; i < count; i++) {
			const at: int32 = (field(cmd, CMD_INSTANCE_OFFSET) + i) * REC_UI_FLOATS;
			const mode: int32 = truncated(cpuUi[at + 16] as float64);
			const sx: float64 = Math.hypot(cpuUi[at] as float64, cpuUi[at + 1] as float64) * scale;
			const sy: float64 = Math.hypot(cpuUi[at + 2] as float64, cpuUi[at + 3] as float64) * scale;
			const s: float64 = Math.sqrt(sx * sy);
			const aa: float64 = (mode == 2 || s <= 0.0) ? 0.0 : 1.0 / s;
			const ix: float64 = aa;
			const iy: float64 = mode == 5 ? 0.0 : aa;
			coverAffineQuad(
				cpuUi, at, cpuUi[at + 4] as float64, cpuUi[at + 5] as float64, -ix, -iy,
				(cpuUi[at + 6] as float64) + ix, (cpuUi[at + 7] as float64) + iy, cmd, scopes, scope,
				rect, mode == 0 && cpuUi[at + 27] >= 1.0 && !effected, blend,
			);
		}
	}

	function coverSpriteRun(
		cmd: Readonly<Span<float32>>, count: int32, blend: int32, fbW: float32, fbH: float32,
		scopes: Readonly<Span<float32>>, scopeCount: int32, cpuSprites: Readonly<Span<float32>>,
	): void {
		if (cpuSprites.length == 0) { return; }
		const scope: int32 = scopeAt(cmd, scopeCount, scopes.length > 0);
		const rect: ScissorRect = scissorRectOf(cmd, scopes, scope, dpiScale, fbW, fbH);
		for (let i: int32 = 0; i < count; i++) {
			const at: int32 = (field(cmd, CMD_INSTANCE_OFFSET) + i) * REC_SPRITE_FLOATS;
			coverAffineQuad(
				cpuSprites, at, cpuSprites[at + 4] as float64, cpuSprites[at + 5] as float64, 0.0, 0.0,
				cpuSprites[at + 6] as float64, cpuSprites[at + 7] as float64, cmd, scopes, scope, rect,
				false, blend,
			);
		}
	}

	function coverVertexRun(
		cmd: Readonly<Span<float32>>, count: int32, blend: int32, view: uint32, fbW: float32,
		fbH: float32, scopes: Readonly<Span<float32>>, scopeCount: int32,
		cpuVertices: Readonly<Span<float32>>,
	): void {
		if (cpuVertices.length == 0) { return; }
		const scope: int32 = scopeAt(cmd, scopeCount, scopes.length > 0);
		const rect: ScissorRect = scissorRectOf(cmd, scopes, scope, dpiScale, fbW, fbH);
		const scale: float64 = deviceScaleOf(cmd, dpiScale) as float64;
		const shiftX: float64 = scope >= 0 ? scopes[scope] as float64 : 0.0;
		const shiftY: float64 = scope >= 0 ? scopes[scope + 1] as float64 : 0.0;
		const first: int32 = field(cmd, CMD_VERTEX_OFFSET) * VERTEX_FLOATS;
		const plain: boolean = view == whiteView && field(cmd, CMD_EFFECT) < 0 && opaqueBlend(blend);
		let triangle: float64[6] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
		for (let i: int32 = 0; i + 2 < count; i += 3) {
			let opaque: boolean = plain;
			for (let k: int32 = 0; k < 3; k++) {
				const p: int32 = first + (i + k) * VERTEX_FLOATS;
				triangle[k * 2] = ((cpuVertices[p] as float64) + shiftX) * scale;
				triangle[k * 2 + 1] = ((cpuVertices[p + 1] as float64) + shiftY) * scale;
				if (cpuVertices[p + 7] < 1.0) { opaque = false; }
			}
			addCoverage(clippedArea(triangle[0..6], 3, rect), opaque);
		}
	}

	function coveredInt(pixels: float64): int32 {
		return pixels >= 2147483647.0 ? 2147483647 : truncated(pixels + 0.5);
	}
}

export function void2dFrameBegin(): void {
	bracketsThisFrame++;
	if (bracketsThisFrame > BRACKETS_BEFORE_COMPLAINT && !frameEndMissingReported) {
		frameEndMissingReported = true;
		console.error(
			`void2d: ${bracketsThisFrame} brackets since the last void2dFrameEnd - is it being called ` +
			"after the submit? until it is, the glyph atlas will not upload and retired resources " +
			"will not be freed",
		);
	}
	if (frameOpen) { return; }
	frameOpen = true;
	when (voidProfiler) {
		profileBegin();
		frameUiInstances = 0;
		frameSpriteInstances = 0;
		coveredSwapchain = 0.0;
		coveredTargets = 0.0;
		coveredOpaque = 0.0;
		swapchainPixels = 0;
	}
	adoptContext();
	void2dGlyphPagesFrameBegin();
	releaseRetiredBuffers();
	drawCallCount = 0;
	uploadCount = 0;
	uploadBytes = 0;
	glyphUploads = 0;
	glyphUploadBytes = 0;
	frameVertexBytes = 0;
}

export function void2dFrameEnd(): void {
	frameOpen = false;
	bracketsThisFrame = 0;
	frameSerial++;
	when (voidProfiler) {
		let counters: int32[9] = [0, 0, 0, 0, 0, 0, 0, 0, 0];
		counters[COUNTER_DRAWS] = drawCallCount;
		counters[COUNTER_UI_INSTANCES] = frameUiInstances;
		counters[COUNTER_SPRITE_INSTANCES] = frameSpriteInstances;
		counters[COUNTER_UPLOAD_BYTES] = uploadBytes;
		counters[COUNTER_UPLOADS] = uploadCount;
		counters[COUNTER_COVERED_PIXELS] = coveredInt(coveredSwapchain);
		counters[COUNTER_TARGET_PIXELS] = coveredInt(coveredTargets);
		counters[COUNTER_OPAQUE_PIXELS] = coveredInt(coveredOpaque);
		counters[COUNTER_FRAME_PIXELS] = swapchainPixels;
		const valid: boolean = doorValid() != 0;
		frameClock.commit(clockNow(), frameSerial, counters[0..VOID2D_COUNTER_SLOTS], {
			valid,
			draws: valid ? doorFrameStat(DOOR_STAT_DRAWS) : 0,
			pipelines: valid ? doorFrameStat(DOOR_STAT_PIPELINES) : 0,
			passes: valid ? doorFrameStat(DOOR_STAT_PASSES) : 0,
			bufferBytes: valid ? doorFrameStat(DOOR_STAT_BUFFER_BYTES) : 0,
			imageBytes: valid ? doorFrameStat(DOOR_STAT_IMAGE_BYTES) : 0,
		});
	}
}

function contextAt(id: int32): PreparedContext {
	while ((contexts.length as int32) <= id) { contexts.push(new PreparedContext()); }
	return contexts[id];
}

export function void2dRememberContext(id: int32, live: boolean): void {
	if (id < 0) { fail(`void2d: cannot remember context ${id} — invalid id`); }
	const c: PreparedContext = contextAt(id);
	c.srcVertex = srcVertex;
	c.srcSprite = srcSprite;
	c.srcUi = srcUi;
	c.srcVertexBase = srcVertexBase;
	c.srcSpriteBase = srcSpriteBase;
	c.srcUiBase = srcUiBase;
	c.spriteInstanceCount = spriteInstanceCount;
	c.uiInstanceCount = uiInstanceCount;
	c.frameUploaded = frameUploaded;
	c.frameSerial = frameSerial;
	c.prepared = true;
	c.live = live;
}

export function void2dActivateContext(id: int32): boolean {
	if (id < 0 || id >= (contexts.length as int32) || !contexts[id].prepared) {
		fail(`void2d: cannot activate context ${id} — never prepared`);
	}
	const c: PreparedContext = contexts[id];
	if (c.frameSerial != frameSerial) {
		fail(
			`void2d: cannot activate context ${id} — prepared frame ${c.frameSerial} expired ` +
			`(current ${frameSerial})`,
		);
	}
	if (c.live && !c.frameUploaded) {
		fail(`void2d: cannot activate context ${id} — prepared draw has no uploaded sources`);
	}
	srcVertex = c.srcVertex;
	srcSprite = c.srcSprite;
	srcUi = c.srcUi;
	srcVertexBase = c.srcVertexBase;
	srcSpriteBase = c.srcSpriteBase;
	srcUiBase = c.srcUiBase;
	spriteInstanceCount = c.spriteInstanceCount;
	uiInstanceCount = c.uiInstanceCount;
	frameUploaded = c.live ? c.frameUploaded : false;
	return c.live;
}

function applyBindings(
	vertex0: uint32, vertex1: uint32, offset0: int32, offset1: int32, viewSlot: int32, view: uint32,
	samplerSlot: int32, sampler: uint32,
): void {
	while ((bindWords.length as int32) < DOOR_BINDING_LENGTH) { bindWords.push(0); }
	for (let i: int32 = 0; i < DOOR_BINDING_LENGTH; i++) { bindWords[i] = 0; }
	bindOffsets[0] = offset0;
	bindOffsets[1] = offset1;
	bindWords[0] = vertex0;
	bindWords[1] = vertex1;
	bindWords[DOOR_BINDING_VIEW + viewSlot] = view;
	bindWords[DOOR_BINDING_SAMPLER + samplerSlot] = sampler;
	doorApplyBindings(bindWords[0..DOOR_BINDING_LENGTH], bindOffsets[0..2]);
}

function clearFloats(values: float32[]): void {
	for (let i: int32 = 0; i < (values.length as int32); i++) { values[i] = 0.0; }
}

function void2dBlur(srcView: uint32, dirX: float32, dirY: float32, blend: int32): void {
	doorApplyPipeline(pipelineAt(PROGRAM_BLUR, 1, blend));
	applyBindings(fsQuad, 0, 0, 0, VIEW_srcTex, srcView, SMP_srcSmp, samplers[2]);
	clearFloats(blurParams);
	blurParams[blur_params_dir] = dirX;
	blurParams[blur_params_dir + 1] = dirY;
	doorApplyUniformsOf(UB_blur_params, blurParams[0..blur_params_FLOATS]);
	doorDraw(0, 6, 1);
}

function uploadGlyphPages(): void {
	const count: int32 = void2dGlyphPageCount();
	for (let page: int32 = 0; page < count && page < MAX_GLYPH_PAGES; page++) {
		dropReleasedPageImage(page);
		if (pageImg[page] == 0 || void2dGlyphPageTakeUpload(page) == 0) { continue; }
		let bytes: int32 = void2dGlyphPageBytes(page);
		const size: int32 = void2dGlyphPageSize(page);
		const box: Vec<int32> = void2dGlyphPageUploadBox(page);
		const w: int32 = box[2] - box[0];
		const h: int32 = box[3] - box[1];
		const texels: uint8[] = state.pages[page].texels;
		if (w >= size && h >= size) {
			doorUpdateTexture(pageImg[page], texels[0..bytes]);
		} else {
			const bytesPerPixel: int32 = bytes / (size * size);
			const stride: int32 = size * bytesPerPixel;
			const first: int32 = box[1] * stride + box[0] * bytesPerPixel;
			bytes = (h - 1) * stride + w * bytesPerPixel;
			doorUpdateTextureRect(pageImg[page], box[0], box[1], w, h, stride, texels[first..first + bytes]);
		}
		glyphUploads++;
		glyphUploadBytes += bytes;
	}
}

function appendFrame<T>(data: Readonly<Span<T>>): int64 {
	const at: int64 = doorAppendBufferOf(vbuf, data);
	if (at < 0) {
		droppedFrames++;
		console.error(
			`void2d: ${(data.length as int64) * (sizeof(T) as int64)} bytes did not fit the ` +
			`${vbufBytes}-byte vertex buffer after ${frameVertexBytes} this frame — frame dropped`,
		);
	}
	return at;
}

export function void2dReplayTargets(
	targetCommands: Readonly<Span<float32>>, targetCommandCount: int32,
	effects: Readonly<Span<float32>>, effectCount: int32,
	scopes: Readonly<Span<float32>>, scopeCount: int32,
	vertices: Readonly<Span<float32>>, vertexCount: int32,
	spriteInstances: Readonly<Span<float32>>, spriteCount: int32,
	uiInstances: Readonly<Span<float32>>, uiCount: int32,
): boolean {
	frameUploaded = false;
	frameBaseOffset = 0;
	spriteInstanceBase = 0;
	spriteInstanceCount = spriteCount;
	uiInstanceBase = 0;
	uiInstanceCount = uiCount;

	const vertexBytes: int64 = (vertexCount as int64) * VERTEX_FLOATS * 4;
	const spriteBytes: int64 = (spriteCount as int64) * SPRITE_STRIDE;
	const uiBytes: int64 = (uiCount as int64) * UI_STRIDE;
	const frameBytes: int64 = (frameVertexBytes as int64) + vertexBytes + spriteBytes + uiBytes;
	if (frameBytes > (MAX_BUFFER_BYTES as int64)) {
		droppedFrames++;
		console.error(
			`void2d: frame needs ${frameBytes} bytes of geometry, cap is ${MAX_BUFFER_BYTES} — ` +
			"frame dropped",
		);
		return false;
	}
	if (!ensureVertexBuffer(frameBytes as int32)) {
		droppedFrames++;
		return false;
	}
	uploadGlyphPages();

	if (vertexBytes > 0) {
		const at: int64 = appendFrame(vertices[0..vertexCount * VERTEX_FLOATS]);
		if (at < 0) { return false; }
		frameBaseOffset = at as int32;
		uploadCount++;
		uploadBytes += vertexBytes as int32;
	}
	if (spriteBytes > 0) {
		const at: int64 = appendFrame(spriteInstances[0..spriteCount * REC_SPRITE_FLOATS]);
		if (at < 0) { return false; }
		spriteInstanceBase = at as int32;
		uploadCount++;
		uploadBytes += spriteBytes as int32;
	}
	if (uiBytes > 0) {
		growWords(uiStage, uiCount * UI_WORDS);
		for (let i: int32 = 0; i < uiCount; i++) { packUiInstance(uiStage, i, uiInstances); }
		const at: int64 = appendFrame(uiStage[0..uiCount * UI_WORDS]);
		if (at < 0) { return false; }
		uiInstanceBase = at as int32;
		uploadCount++;
		uploadBytes += uiBytes as int32;
	}
	if (vertexBytes > 0 || spriteBytes > 0 || uiBytes > 0) { frameVertexBytes = frameBytes as int32; }
	srcVertex = vbuf;
	srcSprite = vbuf;
	srcUi = vbuf;
	srcVertexBase = frameBaseOffset;
	srcSpriteBase = spriteInstanceBase;
	srcUiBase = uiInstanceBase;
	frameUploaded = true;
	if (targetCommandCount > 0) {
		runCommands(
			targetCommands, targetCommandCount, effects, effectCount, scopes, scopeCount, vertices,
			spriteInstances, uiInstances, 0.0, 0.0,
		);
	}
	return true;
}

function listAt(id: int32): DisplayList {
	while ((lists.length as int32) <= id) { lists.push(new DisplayList()); }
	return lists[id];
}

export function void2dReleaseList(id: int32): void {
	if (id < 0) { fail(`void2d: cannot release list ${id} — invalid id`); }
	if (id < (contexts.length as int32)) { contexts[id] = new PreparedContext(); }
	if (id >= (lists.length as int32)) { return; }
	const l: DisplayList = lists[id];
	for (let i: int32 = 0; i < 3; i++) {
		if (l.buf[i] == 0) { continue; }
		if (frameOpen) {
			closedBuf.push(l.buf[i]);
		} else {
			doorDestroyBuffer(l.buf[i]);
			buffersFreed++;
		}
	}
	lists[id] = new DisplayList();
}

function forgetContextResources(): void {
	vbuf = 0;
	vbufBytes = 0;
	for (let i: int32 = 0; i < (pipelines.length as int32); i++) { pipelines[i] = 0; }
	for (let i: int32 = 0; i < MAX_GLYPH_PAGES; i++) {
		pageImg[i] = 0;
		pageView[i] = 0;
	}
	clearWords(retiredBuf);
	clearWords(closedBuf);
	for (let i: int32 = 0; i < (lists.length as int32); i++) {
		for (let which: int32 = 0; which < 3; which++) {
			lists[i].buf[which] = 0;
			lists[i].cap[which] = 0;
		}
		lists[i].stale = true;
	}
	for (let i: int32 = 0; i < (contexts.length as int32); i++) {
		contexts[i].srcVertex = 0;
		contexts[i].srcSprite = 0;
		contexts[i].srcUi = 0;
		contexts[i].prepared = false;
	}
	buffersMade = 0;
	buffersFreed = 0;
	atlasMade = 0;
	void2dGlyphPagesMarkDirty();
}

function adoptContext(): void {
	if (generation == 0 || doorContextGeneration() == generation) { return; }
	forgetContextResources();
	makeContextResources();
}

function ensureListBuffer(l: DisplayList, which: int32, bytes: int32): boolean {
	if (l.buf[which] != 0 && bytes <= l.cap[which]) { return true; }
	const want: int32 = growthTarget(l.cap[which], bytes);
	if (want == 0) { return false; }
	if (l.buf[which] != 0) {
		if ((retiredBuf.length as int32) >= MAX_RETIRED_BUFFERS) { return false; }
		retiredBuf.push(l.buf[which]);
	}
	l.buf[which] = makeBuffer(want, "display list");
	buffersMade++;
	l.cap[which] = want;
	return true;
}

function writeListBuffer<T>(l: DisplayList, which: int32, data: Readonly<Span<T>>): boolean {
	const bytes: int64 = (data.length as int64) * (sizeof(T) as int64);
	if (bytes == 0) { return true; }
	if (!ensureListBuffer(l, which, bytes as int32)) { return false; }
	if (doorUpdateBufferOf(l.buf[which], data) == 0) { return false; }
	uploadCount++;
	uploadBytes += bytes as int32;
	return true;
}

export function void2dReplayList(
	list: int32,
	targetCommands: Readonly<Span<float32>>, targetCommandCount: int32,
	effects: Readonly<Span<float32>>, effectCount: int32,
	scopes: Readonly<Span<float32>>, scopeCount: int32,
	vertices: Readonly<Span<float32>>, vertexCount: int32, vertexDirtyNow: boolean,
	spriteInstances: Readonly<Span<float32>>, spriteCount: int32, spriteDirtyNow: boolean,
	uiInstances: Readonly<Span<float32>>, uiCount: int32,
	uiRanges: Readonly<Span<int32>>, uiRangeCountNow: int32,
): boolean {
	const l: DisplayList = listAt(list);
	let vertexDirty: boolean = vertexDirtyNow;
	let spriteDirty: boolean = spriteDirtyNow;
	let uiRangeCount: int32 = uiRangeCountNow;
	if (l.stale) {
		vertexDirty = true;
		spriteDirty = true;
		uiRangeCount = -1;
	}
	const dirty: boolean = vertexDirty || spriteDirty || uiRangeCount != 0;
	if (dirty && l.updatedFrame == frameSerial) {
		l.stale = true;
		return void2dReplayTargets(
			targetCommands, targetCommandCount, effects, effectCount, scopes, scopeCount, vertices,
			vertexCount, spriteInstances, spriteCount, uiInstances, uiCount,
		);
	}
	frameUploaded = false;
	spriteInstanceCount = spriteCount;
	uiInstanceCount = uiCount;
	uploadGlyphPages();
	if (vertexDirty && !writeListBuffer(l, LIST_VERTEX, vertices[0..vertexCount * VERTEX_FLOATS])) {
		l.stale = true;
		droppedFrames++;
		return false;
	}
	if (spriteDirty &&
		!writeListBuffer(l, LIST_SPRITE, spriteInstances[0..spriteCount * REC_SPRITE_FLOATS])) {
		l.stale = true;
		droppedFrames++;
		return false;
	}
	if (uiRangeCount != 0 && uiCount > 0) {
		growWords(l.stage, uiCount * UI_WORDS);
		const ranges: int32 = uiRangeCount < 0 ? 1 : uiRangeCount;
		for (let r: int32 = 0; r < ranges; r++) {
			const from: int32 = uiRangeCount < 0 ? 0 : uiRanges[r * 2];
			const to: int32 = uiRangeCount < 0 ? uiCount : uiRanges[r * 2 + 1];
			for (let i: int32 = from; i < to && i < uiCount; i++) {
				packUiInstance(l.stage, i, uiInstances);
			}
		}
		if (!writeListBuffer(l, LIST_UI, l.stage[0..uiCount * UI_WORDS])) {
			l.stale = true;
			droppedFrames++;
			return false;
		}
	}
	if (dirty) { l.updatedFrame = frameSerial; }
	l.stale = false;
	srcVertex = l.buf[LIST_VERTEX];
	srcSprite = l.buf[LIST_SPRITE];
	srcUi = l.buf[LIST_UI];
	srcVertexBase = 0;
	srcSpriteBase = 0;
	srcUiBase = 0;
	frameUploaded = true;
	if (targetCommandCount > 0) {
		runCommands(
			targetCommands, targetCommandCount, effects, effectCount, scopes, scopeCount, vertices,
			spriteInstances, uiInstances, 0.0, 0.0,
		);
	}
	return true;
}

export function void2dReplay(
	commands: Readonly<Span<float32>>, commandCount: int32,
	effects: Readonly<Span<float32>>, effectCount: int32,
	scopes: Readonly<Span<float32>>, scopeCount: int32,
	vertices: Readonly<Span<float32>>,
	spriteInstances: Readonly<Span<float32>>,
	uiInstances: Readonly<Span<float32>>,
	fbW: float32, fbH: float32,
): void {
	if (commandCount <= 0 || !frameUploaded) { return; }
	runCommands(
		commands, commandCount, effects, effectCount, scopes, scopeCount, vertices, spriteInstances,
		uiInstances, fbW, fbH,
	);
}

function copyClipParams(
	block: float32[], clipU: int32, clipV: int32, roundU: int32, roundV: int32, radii: int32,
	cmd: Readonly<Span<float32>>,
): void {
	for (let i: int32 = 0; i < 4; i++) {
		block[clipU + i] = cmd[CMD_CLIP_U_X + i];
		block[clipV + i] = cmd[CMD_CLIP_U_X + 4 + i];
	}
	const scale: float32 = deviceScaleOf(cmd, dpiScale);
	for (let i: int32 = 0; i < 4; i++) {
		block[roundU + i] = cmd[CMD_CLIP_ROUND_U + i] * scale;
		block[roundV + i] = cmd[CMD_CLIP_ROUND_U + 4 + i] * scale;
		block[radii + i] = cmd[CMD_CLIP_ROUND_U + 8 + i] * scale;
	}
}

function pipelineChanged(pip: uint32): void {
	if (pip != lastPipeline) {
		doorApplyPipeline(pip);
		lastPipeline = pip;
		scissorApplied = false;
		paramsValid = false;
		fxValid = false;
	}
}

function drawSpriteRun(
	cmd: Readonly<Span<float32>>, blend: int32, rt: boolean, view: uint32, fbW: float32,
	fbH: float32, scopes: Readonly<Span<float32>>, scopeCount: int32,
	cpuSprites: Readonly<Span<float32>>,
): void {
	const count: int32 = field(cmd, CMD_INSTANCE_COUNT);
	if (count <= 0) { return; }
	pipelineChanged(pipelineAt(PROGRAM_SPRITE, rt ? 1 : 0, blend));
	applyBindings(
		unitQuad, srcSprite, 0, srcSpriteBase + field(cmd, CMD_INSTANCE_OFFSET) * SPRITE_STRIDE,
		VIEW_spriteTex, view, SMP_spriteSmp, samplers[samplerOf(cmd)],
	);
	if (!scissorApplied) {
		applyScissor(cmd, scopes, scopeCount, fbW, fbH);
		scissorApplied = true;
	}
	clearFloats(spriteParams);
	spriteParams[sprite_params_viewport] = fbW;
	spriteParams[sprite_params_viewport + 1] = fbH;
	spriteParams[sprite_params_viewport + 2] = (sampledTarget(view) && !originTopLeft) ? 1.0 : 0.0;
	spriteParams[sprite_params_viewport + 3] = premultipliedSource(cmd) ? 1.0 : 0.0;
	const scope: int32 = scopeAt(cmd, scopeCount, scopes.length > 0);
	if (scope >= 0) {
		spriteParams[sprite_params_shift] = scopes[scope];
		spriteParams[sprite_params_shift + 1] = scopes[scope + 1];
	}
	copyClipParams(
		spriteParams, sprite_params_clipU, sprite_params_clipV, sprite_params_clipRoundU,
		sprite_params_clipRoundV, sprite_params_clipRadii, cmd,
	);
	doorApplyUniformsOf(UB_sprite_params, spriteParams[0..sprite_params_FLOATS]);
	doorDraw(0, 6, count);
	drawCallCount++;
	when (voidProfiler) {
		frameSpriteInstances += count;
		coverSpriteRun(cmd, count, blend, fbW, fbH, scopes, scopeCount, cpuSprites);
	}
}

function drawUiRun(
	cmd: Readonly<Span<float32>>, blend: int32, rt: boolean, view: uint32, fbW: float32,
	fbH: float32, scopes: Readonly<Span<float32>>, scopeCount: int32,
	effects: Readonly<Span<float32>>, effectCount: int32, cpuUi: Readonly<Span<float32>>,
): void {
	const count: int32 = field(cmd, CMD_INSTANCE_COUNT);
	if (count <= 0) { return; }
	pipelineChanged(pipelineAt(PROGRAM_UI, rt ? 1 : 0, blend));
	applyBindings(
		unitQuad, srcUi, 0, srcUiBase + field(cmd, CMD_INSTANCE_OFFSET) * UI_STRIDE,
		VIEW_uiTex, view, SMP_uiSmp, samplers[samplerOf(cmd)],
	);
	if (!scissorApplied) {
		applyScissor(cmd, scopes, scopeCount, fbW, fbH);
		scissorApplied = true;
	}
	clearFloats(uiParams);
	uiParams[ui_params_viewport] = fbW;
	uiParams[ui_params_viewport + 1] = fbH;
	uiParams[ui_params_viewport + 2] = (sampledTarget(view) && !originTopLeft) ? 1.0 : 0.0;
	uiParams[ui_params_viewport + 3] = deviceScaleOf(cmd, dpiScale);
	const scope: int32 = scopeAt(cmd, scopeCount, scopes.length > 0);
	if (scope >= 0) {
		uiParams[ui_params_shift] = scopes[scope];
		uiParams[ui_params_shift + 1] = scopes[scope + 1];
	}
	copyClipParams(
		uiParams, ui_params_clipU, ui_params_clipV, ui_params_clipRoundU, ui_params_clipRoundV,
		ui_params_clipRadii, cmd,
	);
	doorApplyUniformsOf(UB_ui_params, uiParams[0..ui_params_FLOATS]);
	clearFloats(uiFx);
	for (let i: int32 = 0; i < 4; i++) { uiFx[ui_fx_gammaRatios + i] = textGamma[i]; }
	uiFx[ui_fx_textParams] = textContrast;
	const effectIndex: int32 = field(cmd, CMD_EFFECT);
	if (effectIndex >= 0 && effectIndex < effectCount) {
		const at: int32 = effectIndex * EFFECT_FLOATS;
		for (let i: int32 = 0; i < 16; i++) { uiFx[ui_fx_colorMatrix + i] = effects[at + i]; }
		for (let i: int32 = 0; i < 4; i++) {
			uiFx[ui_fx_colorAdd + i] = effects[at + 16 + i];
			uiFx[ui_fx_colorKey + i] = effects[at + 20 + i];
		}
		uiFx[ui_fx_effectParams] = 1.0;
	}
	doorApplyUniformsOf(UB_ui_fx, uiFx[0..ui_fx_FLOATS]);
	doorDraw(0, 6, count);
	drawCallCount++;
	when (voidProfiler) {
		frameUiInstances += count;
		coverUiRun(cmd, count, blend, fbW, fbH, scopes, scopeCount, cpuUi);
	}
}

function sameBits(a: float32, b: float32): boolean {
	return floatBits(a) == floatBits(b);
}

function sameFloats(a: float32[], b: float32[]): boolean {
	for (let i: int32 = 0; i < (a.length as int32); i++) {
		if (!sameBits(a[i], b[i])) { return false; }
	}
	return true;
}

function copyFloats(to: float32[], from: float32[]): void {
	for (let i: int32 = 0; i < (from.length as int32); i++) { to[i] = from[i]; }
}

function identityMatrix(effects: Readonly<Span<float32>>, at: int32): boolean {
	for (let i: int32 = 0; i < 16; i++) {
		const expected: uint32 = i % 5 == 0 ? ONE_BITS : 0;
		if (floatBits(effects[at + i]) != expected) { return false; }
	}
	return true;
}

function drawVertexRun(
	cmd: Readonly<Span<float32>>, blend: int32, rt: boolean, view: uint32, fbW: float32,
	fbH: float32, scopes: Readonly<Span<float32>>, scopeCount: int32,
	effects: Readonly<Span<float32>>, effectCount: int32, cpuVertices: Readonly<Span<float32>>,
): void {
	const count: int32 = field(cmd, CMD_VERTEX_COUNT);
	if (count <= 0) { return; }
	pipelineChanged(pipelineAt(PROGRAM_VERTEX, rt ? 1 : 0, blend));
	applyBindings(
		srcVertex, 0, srcVertexBase + field(cmd, CMD_VERTEX_OFFSET) * VERTEX_FLOATS * 4, 0,
		VIEW_tex, view, SMP_smp, samplers[samplerOf(cmd)],
	);
	if (!scissorApplied) {
		applyScissor(cmd, scopes, scopeCount, fbW, fbH);
		scissorApplied = true;
	}
	const effectIndex: int32 = field(cmd, CMD_EFFECT);
	const hasFx: boolean = effectIndex >= 0 && effectIndex < effectCount;
	const fx: int32 = effectIndex * EFFECT_FLOATS;
	const addR: float32 = hasFx ? effects[fx + 16] : 0.0;
	const addG: float32 = hasFx ? effects[fx + 17] : 0.0;
	const addB: float32 = hasFx ? effects[fx + 18] : 0.0;
	const addA: float32 = hasFx ? effects[fx + 19] : 0.0;

	clearFloats(vertexParams);
	vertexParams[void2d_params_viewport] = fbW;
	vertexParams[void2d_params_viewport + 1] = fbH;
	const isRT: boolean = sampledTarget(view);
	const noEffect: boolean = (!hasFx || identityMatrix(effects, fx)) && addR == 0.0 && addG == 0.0 &&
		addB == 0.0 && addA == 0.0 && (!hasFx || effects[fx + 23] <= 0.5);
	const premultiplied: boolean = premultipliedSource(cmd);
	vertexParams[void2d_params_viewport + 2] = (isRT && !originTopLeft) ? 1.0 : 0.0;
	vertexParams[void2d_params_viewport + 3] = (premultiplied && noEffect) ? 1.0 : 0.0;
	vertexParams[void2d_params_model0] = 1.0;
	vertexParams[void2d_params_model0 + 3] = 1.0;
	vertexParams[void2d_params_model1 + 2] = glyphPageViewMode(view);
	vertexParams[void2d_params_model1 + 3] = deviceScaleOf(cmd, dpiScale);
	for (let i: int32 = 0; i < 4; i++) { vertexParams[void2d_params_globalColor + i] = 1.0; }
	const scope: int32 = scopeAt(cmd, scopeCount, scopes.length > 0);
	if (scope >= 0) {
		vertexParams[void2d_params_shift] = scopes[scope];
		vertexParams[void2d_params_shift + 1] = scopes[scope + 1];
	}
	copyClipParams(
		vertexParams, void2d_params_clipU, void2d_params_clipV, void2d_params_clipRoundU,
		void2d_params_clipRoundV, void2d_params_clipRadii, cmd,
	);
	if (!paramsValid || !sameFloats(vertexParams, lastVertexParams)) {
		doorApplyUniformsOf(UB_void2d_params, vertexParams[0..void2d_params_FLOATS]);
		copyFloats(lastVertexParams, vertexParams);
		paramsValid = true;
	}

	clearFloats(vertexFx);
	for (let i: int32 = 0; i < 16; i++) {
		vertexFx[void2d_fx_colorMatrix + i] = hasFx ? effects[fx + i] : (i % 5 == 0 ? 1.0 : 0.0);
	}
	vertexFx[void2d_fx_colorAdd] = addR;
	vertexFx[void2d_fx_colorAdd + 1] = addG;
	vertexFx[void2d_fx_colorAdd + 2] = addB;
	vertexFx[void2d_fx_colorAdd + 3] = addA;
	if (hasFx) {
		for (let i: int32 = 0; i < 4; i++) {
			vertexFx[void2d_fx_colorKey + i] = effects[fx + 20 + i];
			vertexFx[void2d_fx_gradientMeta + i] = effects[fx + 24 + i];
			vertexFx[void2d_fx_gradientParams + i] = effects[fx + 28 + i];
			vertexFx[void2d_fx_gradientColor0 + i] = effects[fx + 32 + i];
			vertexFx[void2d_fx_gradientColor1 + i] = effects[fx + 36 + i];
			vertexFx[void2d_fx_gradientColor2 + i] = effects[fx + 40 + i];
		}
	}
	for (let i: int32 = 0; i < 4; i++) { vertexFx[void2d_fx_gammaRatios + i] = textGamma[i]; }
	vertexFx[void2d_fx_textParams] = textContrast;
	vertexFx[void2d_fx_sourceParams] = (premultiplied && !noEffect) ? 1.0 : 0.0;
	if (!fxValid || !sameFloats(vertexFx, lastVertexFx)) {
		doorApplyUniformsOf(UB_void2d_fx, vertexFx[0..void2d_fx_FLOATS]);
		copyFloats(lastVertexFx, vertexFx);
		fxValid = true;
	}

	doorDraw(0, count, 1);
	drawCallCount++;
	when (voidProfiler) {
		coverVertexRun(cmd, count, blend, view, fbW, fbH, scopes, scopeCount, cpuVertices);
	}
}

function resetBound(): void {
	lastPipeline = 0;
	paramsValid = false;
	fxValid = false;
	scissorApplied = false;
}

function runCommands(
	commands: Readonly<Span<float32>>, commandCount: int32,
	effects: Readonly<Span<float32>>, effectCount: int32,
	scopes: Readonly<Span<float32>>, scopeCount: int32,
	cpuVertices: Readonly<Span<float32>>,
	cpuSprites: Readonly<Span<float32>>,
	cpuUi: Readonly<Span<float32>>,
	startW: float32, startH: float32,
): void {
	let fbW: float32 = startW;
	let fbH: float32 = startH;
	let sizeStack: float32[16] = [
		0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
	];
	let sizeDepth: int32 = 0;
	const baseTarget: boolean = doorPassState() == TARGET_PASS;
	when (voidProfiler) {
		swapchainPass = !baseTarget;
		if (swapchainPass && fbW > 0.0 && fbH > 0.0) {
			swapchainPixels = scissorMax(fbW, dpiScale) * scissorMax(fbH, dpiScale);
		}
	}
	resetBound();
	let lastScope: int32 = NO_SCOPE;
	for (let i: int32 = 0; i < commandCount; i++) {
		const cmd: Readonly<Span<float32>> = commands[i * COMMAND_FLOATS..(i + 1) * COMMAND_FLOATS];
		const kind: int32 = field(cmd, CMD_KIND);
		const scope: int32 = field(cmd, CMD_SCOPE);
		if (scope != lastScope) {
			lastScope = scope;
			scissorApplied = false;
		}
		if (kind == KIND_SCISSOR) {
			applyScissor(cmd, scopes, scopeCount, fbW, fbH);
			scissorApplied = true;
			continue;
		}
		if (kind == KIND_BLUR) {
			void2dBlur(commandViewOf(cmd), cmd[CMD_ARG0], cmd[CMD_ARG1], field(cmd, CMD_BLEND));
			resetBound();
			continue;
		}
		if (kind == KIND_TARGET_BEGIN) {
			if (sizeDepth >= MAX_TARGET_DEPTH) {
				fail(
					`void2d: a target list nested ${sizeDepth + 1} deep at replay, where its blocks ` +
					"are flat",
				);
			}
			sizeStack[sizeDepth * 2] = fbW;
			sizeStack[sizeDepth * 2 + 1] = fbH;
			sizeDepth++;
			fbW = cmd[CMD_ARG0];
			fbH = cmd[CMD_ARG1];
			when (voidProfiler) { swapchainPass = false; }
			doorBeginColorPass(
				commandViewOf(cmd), cmd[CMD_CLEAR_R], cmd[CMD_CLEAR_R + 1], cmd[CMD_CLEAR_R + 2],
				cmd[CMD_CLEAR_R + 3],
			);
			resetBound();
			continue;
		}
		if (kind == KIND_TARGET_END) {
			doorEndPass();
			if (sizeDepth > 0) {
				sizeDepth--;
				fbW = sizeStack[sizeDepth * 2];
				fbH = sizeStack[sizeDepth * 2 + 1];
			}
			when (voidProfiler) { swapchainPass = sizeDepth == 0 && !baseTarget; }
			resetBound();
			continue;
		}
		if (kind != KIND_DRAW) { continue; }

		const blend: int32 = field(cmd, CMD_BLEND);
		let view: uint32 = commandViewOf(cmd);
		if (view == 0) { view = whiteView; }
		const rt: boolean = baseTarget || cmd[CMD_RT_MODE] != 0.0;
		const pipeline: int32 = field(cmd, CMD_PIPELINE);
		if (pipeline == PIPELINE_SPRITE) {
			drawSpriteRun(cmd, blend, rt, view, fbW, fbH, scopes, scopeCount, cpuSprites);
			continue;
		}
		if (pipeline == PIPELINE_UI) {
			drawUiRun(cmd, blend, rt, view, fbW, fbH, scopes, scopeCount, effects, effectCount, cpuUi);
			continue;
		}
		drawVertexRun(
			cmd, blend, rt, view, fbW, fbH, scopes, scopeCount, effects, effectCount, cpuVertices,
		);
	}
}
