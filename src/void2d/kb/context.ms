import { KbBreak, KbBreakState, kbBreakBegin, KB_JAPANESE_LINE_BREAK_STYLE_NORMAL } from "./break";
import { KbFeatureOverride, KbShapeConfig } from "./config";
import { KbFont, kbCodepointToGlyphId } from "./font";
import {
	KbGlyph,
	KbGlyphStorage,
	KB_GLYPH_SENTINEL,
	kbClearActiveGlyphs,
	kbPushGlyph,
	kbZeroGlyph,
} from "./glyph";
import { kbShapeDirect } from "./engine";
import { kbPlaceShapeScratch } from "./scratch";
import {
	kbGetVariationAxisInfo,
	kbGetVariationInfo,
	kbNormalizeVariationVector,
	kbPlaceGlyphConfig,
	kbPlaceShapeConfig,
} from "./shapeConfig";
import {
	KB_BREAK_FLAG_DIRECTION,
	KB_BREAK_FLAG_GRAPHEME,
	KB_BREAK_FLAG_LINE,
	KB_BREAK_FLAG_LINE_HARD,
	KB_BREAK_FLAG_MANUAL,
	KB_BREAK_FLAG_PARAGRAPH_DIRECTION,
	KB_BREAK_FLAG_SCRIPT,
	KB_DIRECTION_LTR,
	KB_DIRECTION_RTL,
	KB_SHAPER_ARABIC,
	KB_SHAPER_HEBREW,
} from "./shapeTables";
import { kbCombiningClass } from "./unicode";

const MAX_SIMULTANEOUS_FEATURES: int32 = 32;

const FLAG_MANUAL_SEGMENTATION: uint32 = 1;
const FLAG_START_OF_MANUAL_RUN: uint32 = 2;
const FLAG_USE_MANUAL_BREAK_INFO: uint32 = 4;
const FLAG_FEATURE_OVERRIDES_DIRTY: uint32 = 8;

export struct KbVariation {
	tag: uint32;
	value: float32;
}

struct KbInputCodepoint {
	fontPlusOne: int32;
	overrides: int32;
	overrideCount: int32;
	codepoint: int32;
	userId: int32;
	breakFlags: uint32;
	script: uint32;
	direction: uint32;
	paragraphDirection: uint32;
}

class KbContextFont {
	font: KbFont;
	serial: int32;
	variationVector: float32[] = [];
	normalized: int32[] | null = null;

	constructor(font: KbFont, serial: int32) {
		this.font = font;
		this.serial = serial;
	}
}

class KbExistingShapeConfig {
	serial: int32;
	vector: float32[];
	script: uint32;
	language: uint32;
	config: KbShapeConfig;

	constructor(serial: int32, vector: float32[], script: uint32, language: uint32, config: KbShapeConfig) {
		this.serial = serial;
		this.vector = vector;
		this.script = script;
		this.language = language;
		this.config = config;
	}
}

struct KbExistingGlyphConfig {
	uid: uint32;
	overrides: KbFeatureOverride[];
	configPlusOne: int32;
}

export class KbShapeCodepoint {
	font: KbFont | null = null;
	featureOverrideCount: int32 = 0;
	codepoint: int32 = 0;
	userId: int32 = 0;
	breakFlags: uint32 = 0;
	script: uint32 = 0;
	direction: uint32 = 0;
	paragraphDirection: uint32 = 0;
}

export class KbGlyphIterator {
	storage: KbGlyphStorage;
	current: int32;

	constructor(storage: KbGlyphStorage) {
		this.storage = storage;
		this.current = storage.glyphs[KB_GLYPH_SENTINEL].next;
	}
}

export class KbRun {
	font: KbFont;
	script: uint32 = 0;
	paragraphDirection: uint32 = 0;
	direction: uint32 = 0;
	flags: uint32 = 0;
	glyphs: KbGlyphIterator;
	config: KbShapeConfig | null = null;

	constructor(font: KbFont, glyphs: KbGlyphIterator) {
		this.font = font;
		this.glyphs = glyphs;
	}
}

// kbts_shape_context with the input codepoints in one flat array instead of the C's power-of-two
// blocks, whose iterator stays valid past a text of exactly 128, 256, ... codepoints and so drops
// the terminating line-break run.
export class KbShapeContext {
	fonts: KbContextFont[] = [];
	input: KbInputCodepoint[] = [];
	inputCount: int32 = 0;
	lastGraphemeBreak: int32 = -1;
	lastGraphemeBreakIndex: int32 = 0;
	lastLineBreakIndex: int32 = 0;
	breakStartIndex: int32 = 0;
	storage: KbGlyphStorage = new KbGlyphStorage();
	flags: uint32 = 0;
	manualRunDirection: uint32 = 0;
	manualRunScript: uint32 = 0;
	hoisted: KbFeatureOverride[][] = [];
	currentFeatureOverrides: int32 = -1;
	currentFeatureOverrideCount: int32 = 0;
	paragraphDirection: uint32 = 0;
	language: uint32 = 0;
	runFont: int32 = 0;
	runScript: uint32 = 0;
	runParagraphDirection: uint32 = 0;
	runDirection: uint32 = 0;
	runStarted: boolean = false;
	runNext: int32 = 0;
	runEnd: int32 = 0;
	doneShapingRuns: boolean = false;
	shapeConfigs: KbExistingShapeConfig[] = [];
	glyphConfigs: KbExistingGlyphConfig[] = [];
	scratchFeatureOverrides: KbFeatureOverride[] = [];
	breakState: KbBreakState = kbBreakBegin(0, KB_JAPANESE_LINE_BREAK_STYLE_NORMAL, 0);
}

function zeroInput(): KbInputCodepoint {
	return {
		fontPlusOne: 0, overrides: -1, overrideCount: 0, codepoint: 0, userId: 0, breakFlags: 0,
		script: 0, direction: 0, paragraphDirection: 0,
	};
}

function ensureInput(ctx: KbShapeContext, index: int32): void {
	while ((ctx.input.length as int32) <= index) {
		ctx.input.push(zeroInput());
	}
}

export function kbShapePushFont(ctx: KbShapeContext, font: KbFont, variations: KbVariation[]): void {
	let serial = ctx.fonts.length as int32;
	for (const existing of ctx.fonts) {
		if (existing.font === font) {
			serial = existing.serial;
			break;
		}
	}
	const entry = new KbContextFont(font, serial);
	const axisCount = kbGetVariationInfo(font).axisCount;
	for (let axisIndex: int32 = 0; axisIndex < axisCount; axisIndex++) {
		const axis = kbGetVariationAxisInfo(font, axisIndex);
		let value = axis.defaultValue;
		for (const variation of variations) {
			if (variation.tag == axis.tag) {
				value = variation.value;
				break;
			}
		}
		entry.variationVector.push(value);
	}
	ctx.fonts.push(entry);
}

export function kbShapeBegin(ctx: KbShapeContext, paragraphDirection: uint32, language: uint32): void {
	ctx.hoisted = [];
	for (const entry of ctx.fonts) {
		entry.normalized = null;
	}
	kbClearActiveGlyphs(ctx.storage);
	ctx.breakStartIndex = 0;
	ctx.currentFeatureOverrides = -1;
	ctx.currentFeatureOverrideCount = 0;
	ctx.flags |= FLAG_FEATURE_OVERRIDES_DIRTY;
	ctx.paragraphDirection = paragraphDirection;
	ctx.language = language;
	ctx.inputCount = 0;
	ctx.lastGraphemeBreak = -1;
	ctx.lastLineBreakIndex = 0;
	ctx.runFont = 0;
	ctx.runScript = 0;
	ctx.runDirection = 0;
	ctx.breakState = kbBreakBegin(paragraphDirection, KB_JAPANESE_LINE_BREAK_STYLE_NORMAL, 0);
}

// kbts_FontCoverageTest*. The C's recomposition search runs over a parent count it has just zeroed,
// so no mark ever recomposes with its base: a mark the font lacks fails the test.
function fontCovers(font: KbFont, input: KbInputCodepoint[], start: int32, end: int32): boolean {
	let currentBaseError = false;
	let error = false;
	for (let i = start; i < end && !error; i++) {
		const codepoint = input[i].codepoint;
		if (kbCombiningClass(((codepoint as int64) & 0xFFFFFFFF) as uint32) == 0) {
			error = currentBaseError;
			currentBaseError = (kbCodepointToGlyphId(font, codepoint) & 0xFFFF) == 0;
		} else if ((kbCodepointToGlyphId(font, codepoint) & 0xFFFF) == 0) {
			error = true;
		}
	}
	return !(currentBaseError || error);
}

function updateBreaks(ctx: KbShapeContext): void {
	if ((ctx.flags & FLAG_MANUAL_SEGMENTATION) != 0) {
		return;
	}
	let found: KbBreak = { position: 0, flags: 0, direction: 0, paragraphDirection: 0, script: 0 };
	while (ctx.breakState.kbBreakNext(out found)) {
		const position = found.position + ctx.breakStartIndex;
		ensureInput(ctx, position);

		if ((found.flags & KB_BREAK_FLAG_LINE_HARD) != 0) {
			ctx.lastLineBreakIndex = position;
		}

		if ((found.flags & KB_BREAK_FLAG_GRAPHEME) != 0) {
			let match: int32 = 0;
			for (let fontIndex = (ctx.fonts.length as int32) - 1; fontIndex >= 0; fontIndex--) {
				if (fontCovers(ctx.fonts[fontIndex].font, ctx.input, ctx.lastGraphemeBreakIndex, position)) {
					match = fontIndex + 1;
					break;
				}
			}
			if (ctx.lastGraphemeBreak >= 0) {
				ctx.input[ctx.lastGraphemeBreak].fontPlusOne = match;
			}
			ctx.lastGraphemeBreak = position;
			ctx.lastGraphemeBreakIndex = position;
		}

		ctx.input[position].breakFlags |= found.flags;
		if ((found.flags & KB_BREAK_FLAG_SCRIPT) != 0) {
			ctx.input[position].script = found.script;
		}
		if ((found.flags & KB_BREAK_FLAG_DIRECTION) != 0) {
			ctx.input[position].direction = found.direction;
		}
		if ((found.flags & KB_BREAK_FLAG_PARAGRAPH_DIRECTION) != 0) {
			ctx.input[position].paragraphDirection = found.paragraphDirection;
		}
	}
}

export function kbShapeBeginManualRuns(ctx: KbShapeContext): void {
	if (ctx.inputCount > 0) {
		ctx.breakState.kbBreakEnd();
		updateBreaks(ctx);
	}
	ctx.flags |= FLAG_MANUAL_SEGMENTATION;
}

export function kbShapeNextManualRun(ctx: KbShapeContext, direction: uint32, script: uint32): void {
	if ((ctx.flags & FLAG_MANUAL_SEGMENTATION) != 0) {
		ctx.flags |= FLAG_START_OF_MANUAL_RUN | FLAG_USE_MANUAL_BREAK_INFO;
		ctx.manualRunDirection = direction;
		ctx.manualRunScript = script;
	}
}

export function kbShapeEndManualRuns(ctx: KbShapeContext): void {
	if ((ctx.flags & FLAG_MANUAL_SEGMENTATION) != 0) {
		ctx.flags &= ~FLAG_MANUAL_SEGMENTATION;
		if (ctx.inputCount > 0) {
			ctx.breakState = kbBreakBegin(ctx.paragraphDirection, KB_JAPANESE_LINE_BREAK_STYLE_NORMAL, 0);
			ctx.breakStartIndex = ctx.inputCount;
		}
	}
}

export function kbShapeManualBreak(ctx: KbShapeContext): void {
	kbShapeBeginManualRuns(ctx);
	ctx.flags |= FLAG_START_OF_MANUAL_RUN;
	kbShapeEndManualRuns(ctx);
}

// The hoisted list copies the first UniqueCount pushed overrides, not the deduplicated ones, as the
// C does.
function hoistFeatureOverrides(ctx: KbShapeContext): void {
	const scratchCount = ctx.scratchFeatureOverrides.length as int32;
	let newCount = scratchCount;
	if (scratchCount > 0) {
		let uniqueTags: uint32[] = [];
		for (let i = scratchCount; i > 0; i--) {
			const tag = ctx.scratchFeatureOverrides[i - 1].tag;
			if (uniqueTags.indexOf(tag) < 0) {
				uniqueTags.push(tag);
			}
		}
		let hoisted: KbFeatureOverride[] = [];
		for (let i: int32 = 0; i < (uniqueTags.length as int32); i++) {
			hoisted.push(ctx.scratchFeatureOverrides[i]);
		}
		ctx.currentFeatureOverrides = ctx.hoisted.length as int32;
		ctx.hoisted.push(hoisted);
		newCount = uniqueTags.length as int32;
	}
	ctx.currentFeatureOverrideCount = newCount;
	ctx.flags &= ~FLAG_FEATURE_OVERRIDES_DIRTY;
}

export function kbShapeCodepointWithUserId(ctx: KbShapeContext, codepoint: int32, userId: int32): void {
	if ((ctx.flags & FLAG_FEATURE_OVERRIDES_DIRTY) != 0) {
		hoistFeatureOverrides(ctx);
	}

	const flatIndex = ctx.inputCount;
	let entry = zeroInput();
	entry.codepoint = codepoint;
	entry.userId = userId;
	entry.overrides = ctx.currentFeatureOverrides;
	entry.overrideCount = ctx.currentFeatureOverrideCount;
	if (flatIndex != 0 && flatIndex == ctx.lastLineBreakIndex) {
		entry.breakFlags |= KB_BREAK_FLAG_LINE;
	}
	if ((ctx.flags & FLAG_START_OF_MANUAL_RUN) != 0) {
		entry.breakFlags |= KB_BREAK_FLAG_MANUAL;
		if ((ctx.flags & FLAG_USE_MANUAL_BREAK_INFO) != 0) {
			entry.direction = ctx.manualRunDirection;
			entry.script = ctx.manualRunScript;
		}
		ctx.flags &= ~FLAG_START_OF_MANUAL_RUN;
	}
	ensureInput(ctx, flatIndex);
	ctx.input[flatIndex] = entry;
	if (ctx.lastGraphemeBreak < 0) {
		ctx.lastGraphemeBreak = flatIndex;
	}
	ctx.inputCount += 1;

	if ((ctx.flags & FLAG_MANUAL_SEGMENTATION) == 0) {
		ctx.breakState.kbBreakAddCodepoint(codepoint, 1, false);
		updateBreaks(ctx);
	}
}

export function kbShapePushFeature(ctx: KbShapeContext, tag: uint32, value: int32): void {
	if ((ctx.scratchFeatureOverrides.length as int32) < MAX_SIMULTANEOUS_FEATURES) {
		ctx.scratchFeatureOverrides.push({ tag, value });
		ctx.flags |= FLAG_FEATURE_OVERRIDES_DIRTY;
	}
}

export function kbShapePopFeature(ctx: KbShapeContext, tag: uint32): boolean {
	for (let i = (ctx.scratchFeatureOverrides.length as int32) - 1; i >= 0; i--) {
		if (ctx.scratchFeatureOverrides[i].tag == tag) {
			ctx.scratchFeatureOverrides.splice(i, 1);
			ctx.flags |= FLAG_FEATURE_OVERRIDES_DIRTY;
			return true;
		}
	}
	return false;
}

function beginParagraph(ctx: KbShapeContext): void {
	let fontPlusOne: int32 = 0;
	if (ctx.fonts.length > 0) {
		fontPlusOne = (ctx.flags & FLAG_MANUAL_SEGMENTATION) == 0 ? (ctx.fonts.length as int32) : 1;
	}
	ctx.runFont = fontPlusOne;
	ctx.runScript = 0;
	ctx.runParagraphDirection = 0;
	ctx.runDirection = 0;
}

export function kbShapeEnd(ctx: KbShapeContext): void {
	ensureInput(ctx, ctx.inputCount);
	ctx.input[ctx.inputCount] = zeroInput();
	ctx.breakState.kbBreakEnd();
	updateBreaks(ctx);
	ctx.runStarted = false;
	ctx.doneShapingRuns = false;
	beginParagraph(ctx);
}

function sameVector(a: float32[], b: float32[]): boolean {
	if (a.length != b.length) {
		return false;
	}
	for (let i: int32 = 0; i < (a.length as int32); i++) {
		if (a[i] != b[i]) {
			return false;
		}
	}
	return true;
}

function runFontEntry(ctx: KbShapeContext, fontPlusOne: int32): KbContextFont {
	if (fontPlusOne == 0) {
		throw new Error("kb shape context: a run has no font; push one before shaping");
	}
	return ctx.fonts[fontPlusOne - 1];
}

function findOrCreateShapeConfig(
	ctx: KbShapeContext,
	fontPlusOne: int32,
	script: uint32,
	language: uint32,
): KbShapeConfig {
	const entry = runFontEntry(ctx, fontPlusOne);
	for (const existing of ctx.shapeConfigs) {
		if (existing.serial == entry.serial && existing.script == script && existing.language == language &&
			sameVector(existing.vector, entry.variationVector)) {
			return existing.config;
		}
	}
	const config = kbPlaceShapeConfig(entry.font, script, language, entry.variationVector, entry.serial as int64);
	ctx.shapeConfigs.push(new KbExistingShapeConfig(entry.serial, entry.variationVector, script, language, config));
	return config;
}

function findOrCreateGlyphConfig(ctx: KbShapeContext, config: KbShapeConfig, overrides: int32, count: int32): int32 {
	if (count <= 0) {
		return 0;
	}
	const list = ctx.hoisted[overrides];
	const uid = config.uid[0] ^ config.uid[1] ^ config.uid[2] ^ config.uid[3];
	for (const existing of ctx.glyphConfigs) {
		if (existing.uid != uid || (existing.overrides.length as int32) != count) {
			continue;
		}
		let same = true;
		for (let i: int32 = 0; i < count; i++) {
			if (existing.overrides[i].tag != list[i].tag || existing.overrides[i].value != list[i].value) {
				same = false;
				break;
			}
		}
		if (same) {
			return existing.configPlusOne;
		}
	}
	let used: KbFeatureOverride[] = [];
	for (let i: int32 = 0; i < count; i++) {
		used.push(list[i]);
	}
	ctx.storage.configs.push(kbPlaceGlyphConfig(config, used));
	const configPlusOne = ctx.storage.configs.length as int32;
	ctx.glyphConfigs.push({ uid, overrides: used, configPlusOne });
	return configPlusOne;
}

function pushRunGlyph(ctx: KbShapeContext, fontPlusOne: int32, config: KbShapeConfig, index: int32): void {
	const item = ctx.input[index];
	const glyphConfig = findOrCreateGlyphConfig(ctx, config, item.overrides, item.overrideCount);
	kbPushGlyph(ctx.storage, runFontEntry(ctx, fontPlusOne).font, item.codepoint, glyphConfig, index);
}

function shapeGlyphs(
	m: Span<uint8>,
	config: KbShapeConfig,
	storage: KbGlyphStorage,
	direction: uint32,
	normalized: int32[],
): void {
	kbShapeDirect(kbPlaceShapeScratch(config, storage), m, direction, normalized);
}

// kbts_ShapeRun: the next run of the text given since kbShapeBegin, shaped, or null when every run
// has been returned. Its glyphs stay valid until the next call.
export function kbShapeRun(ctx: KbShapeContext): KbRun | null {
	if (ctx.doneShapingRuns) {
		return null;
	}
	let runFont = ctx.runFont;
	let runScript = ctx.runScript;
	let runParagraphDirection = ctx.runParagraphDirection;
	let runDirection = ctx.runDirection;
	const language = ctx.language;
	let config: KbShapeConfig | null = null;
	let flags: uint32 = 0;
	let result = false;

	kbClearActiveGlyphs(ctx.storage);

	let initialized = true;
	if (!ctx.runStarted) {
		ctx.runStarted = ctx.inputCount > 0;
		ctx.runNext = 0;
		ctx.runEnd = ctx.inputCount;
		initialized = false;
	}

	if (ctx.runStarted && ctx.runNext < ctx.runEnd) {
		while (ctx.runNext < ctx.runEnd) {
			const index = ctx.runNext;
			ctx.runNext += 1;

			if ((ctx.input[index].breakFlags & KB_BREAK_FLAG_DIRECTION) != 0 && ctx.input[index].direction == 0) {
				ctx.input[index].direction = runParagraphDirection;
			}

			const first = !result;
			result = true;

			const item = ctx.input[index];
			const newLine = !first && (item.breakFlags & (KB_BREAK_FLAG_LINE_HARD | KB_BREAK_FLAG_MANUAL)) != 0;

			if (first) {
				flags = item.breakFlags;
				if ((item.breakFlags & KB_BREAK_FLAG_LINE_HARD) != 0) {
					beginParagraph(ctx);
					runFont = ctx.runFont;
					runScript = 0;
					runDirection = 0;
					initialized = false;
				}
			}

			if ((item.fontPlusOne != 0 && item.fontPlusOne != runFont) ||
				(item.script != 0 && item.script != runScript) ||
				(item.direction != 0 && item.direction != runDirection) ||
				(item.paragraphDirection != 0 && item.paragraphDirection != runParagraphDirection) ||
				newLine) {
				if (item.fontPlusOne != 0) { ctx.runFont = item.fontPlusOne; }
				if (item.script != 0) { ctx.runScript = item.script; }
				if (item.direction != 0) { ctx.runDirection = item.direction; }
				if (item.paragraphDirection != 0) { ctx.runParagraphDirection = item.paragraphDirection; }

				if (initialized || newLine) {
					ctx.runNext -= 1;
					break;
				}
				runFont = ctx.runFont;
				runScript = ctx.runScript;
				runDirection = ctx.runDirection;
				runParagraphDirection = ctx.runParagraphDirection;
				const created = findOrCreateShapeConfig(ctx, runFont, runScript, language);
				config = created;
				pushRunGlyph(ctx, runFont, created, index);
				initialized = true;
			} else {
				const existing = config ?? findOrCreateShapeConfig(ctx, runFont, runScript, language);
				config = existing;
				pushRunGlyph(ctx, runFont, existing, index);
			}
		}

		if (result) {
			const runConfig = config;
			if (runConfig == null) {
				throw new Error("kb shape context: a run broke before its first glyph");
			}
			if (runDirection == 0) {
				runDirection = KB_DIRECTION_LTR;
				if (runConfig.shaper == KB_SHAPER_ARABIC || runConfig.shaper == KB_SHAPER_HEBREW) {
					runDirection = KB_DIRECTION_RTL;
				}
			}
			const entry = runFontEntry(ctx, runFont);
			let normalized = entry.normalized;
			if (normalized == null) {
				let fresh: int32[] = [];
				for (let i: int32 = 0; i < (entry.variationVector.length as int32); i++) {
					fresh.push(0);
				}
				kbNormalizeVariationVector(entry.font, entry.variationVector, fresh);
				entry.normalized = fresh;
				normalized = fresh;
			}
			const m: Span<uint8> = entry.font.blob[0..entry.font.blob.length];
			shapeGlyphs(m, runConfig, ctx.storage, runDirection, normalized);
		}
	} else {
		ensureInput(ctx, ctx.inputCount);
		if ((ctx.input[ctx.inputCount].breakFlags & KB_BREAK_FLAG_LINE_HARD) != 0) {
			flags = ctx.input[ctx.inputCount].breakFlags;
			result = true;
		}
		ctx.doneShapingRuns = true;
	}

	if (!result) {
		return null;
	}
	const run = new KbRun(runFontEntry(ctx, runFont).font, new KbGlyphIterator(ctx.storage));
	run.script = runScript;
	run.paragraphDirection = runParagraphDirection;
	run.direction = runDirection;
	run.flags = flags;
	run.config = config;
	return run;
}

export function kbGlyphIteratorNext(it: KbGlyphIterator, out glyph: KbGlyph): boolean {
	if (it.current == KB_GLYPH_SENTINEL) {
		glyph = kbZeroGlyph();
		return false;
	}
	glyph = it.storage.glyphs[it.current];
	it.current = it.storage.glyphs[it.current].next;
	return true;
}

// kbts_ShapeGetShapeCodepoint, ParagraphDirection included: the C fills it from Direction.
export function kbShapeGetShapeCodepoint(ctx: KbShapeContext, index: int32): KbShapeCodepoint | null {
	if (index < 0 || index >= ctx.inputCount) {
		return null;
	}
	const item = ctx.input[index];
	const result = new KbShapeCodepoint();
	result.font = item.fontPlusOne != 0 ? ctx.fonts[item.fontPlusOne - 1].font : null;
	result.featureOverrideCount = item.overrideCount;
	result.codepoint = item.codepoint;
	result.userId = item.userId;
	result.breakFlags = item.breakFlags;
	result.script = item.script;
	result.direction = item.direction;
	result.paragraphDirection = item.direction;
	return result;
}
