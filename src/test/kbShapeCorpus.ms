import { KbFontBoundsError } from "../void2d/kb/blob";
import { KbBreak, KbBreakState, kbBreakBegin, KB_JAPANESE_LINE_BREAK_STYLE_NORMAL } from "../void2d/kb/break";
import {
	KbShapeContext,
	KbVariation,
	kbGlyphIteratorNext,
	kbShapeBegin,
	kbShapeBeginManualRuns,
	kbShapeCodepointWithUserId,
	kbShapeEnd,
	kbShapeEndManualRuns,
	kbShapeGetShapeCodepoint,
	kbShapeManualBreak,
	kbShapeNextManualRun,
	kbShapePopFeature,
	kbShapePushFeature,
	kbShapePushFont,
	kbShapeRun,
} from "../void2d/kb/context";
import { KbFont } from "../void2d/kb/font";
import { KbGlyph, kbZeroGlyph } from "../void2d/kb/glyph";
import { kbGetVariationAxisInfo } from "../void2d/kb/shapeConfig";
import { KB_BREAK_FLAG_SCRIPT, KB_DIRECTION_LTR, KB_DIRECTION_RTL } from "../void2d/kb/shapeTables";
import { kbConfigDigestStep } from "./kbConfigCorpus";
import { KbEngineCase, kbEngineFontCases, kbEngineVariedVector } from "./kbEngineCorpus";

// One context's life as ops, replayed alike by the C reference and the port: 1 begin dir lang,
// 2 push feature tag value, 3 pop feature tag, 4 codepoint cp userId, 5 manual break, 6 begin manual
// runs, 7 next manual run dir script, 8 end manual runs, 9 end and dump every run.
export struct KbShapeCase {
	varied: boolean;
	fallback: boolean;
	ops: int32[];
}

const LIGA: int32 = 0x6167696C;
const KERN: int32 = 0x6E72656B;
const SMCP: int32 = 0x70636D73;
const SS23: int32 = 0x33327373;
const SS24: int32 = 0x34327373;

function emit(ops: int32[], values: int32[]): void {
	for (const value of values) { ops.push(value); }
}

function pushText(ops: int32[], codepoints: int32[], userBase: int32): void {
	for (let i: int32 = 0; i < codepoints.length; i++) {
		ops.push(4);
		ops.push(codepoints[i]);
		ops.push(userBase + i * 3);
	}
}

// What shaper.c's forced path feeds: a manual run wherever the break pass starts a script, at the
// first codepoint and at breakAt.
function pushForced(ops: int32[], codepoints: int32[], direction: uint32, breakAt: int32): void {
	const count = codepoints.length as int32;
	let starts: boolean[] = [];
	let scripts: uint32[] = [];
	for (let i: int32 = 0; i < count; i++) {
		starts.push(false);
		scripts.push(0);
	}
	let state: KbBreakState = kbBreakBegin(direction, KB_JAPANESE_LINE_BREAK_STYLE_NORMAL, 0);
	let found: KbBreak = { position: 0, flags: 0, direction: 0, paragraphDirection: 0, script: 0 };
	for (let i: int32 = 0; i < count; i++) {
		state.kbBreakAddCodepoint(codepoints[i], 1, i == count - 1);
		while (state.kbBreakNext(out found)) {
			if ((found.flags & KB_BREAK_FLAG_SCRIPT) != 0 && found.position >= 0 && found.position < count) {
				starts[found.position] = true;
				scripts[found.position] = found.script;
			}
		}
	}
	ops.push(6);
	let current: uint32 = 0;
	for (let i: int32 = 0; i < count; i++) {
		if (starts[i]) { current = scripts[i]; }
		if (i == 0 || starts[i] || i == breakAt) {
			ops.push(7);
			ops.push(direction as int32);
			ops.push(current as int32);
		}
		ops.push(4);
		ops.push(codepoints[i]);
		ops.push(i);
	}
	ops.push(8);
}

function join(parts: int32[][], separators: int32[]): int32[] {
	let result: int32[] = [];
	for (let p: int32 = 0; p < parts.length; p++) {
		if (p > 0) { result.push(separators[(p - 1) % (separators.length as int32)]); }
		for (const codepoint of parts[p]) { result.push(codepoint); }
	}
	return result;
}

function longText(items: KbEngineCase[], atLeast: int32): int32[] {
	let parts: int32[][] = [];
	let length: int32 = 0;
	let k: int32 = 0;
	while (length < atLeast && k < items.length) {
		parts.push(items[k].codepoints);
		length += (items[k].codepoints.length as int32) + 1;
		k += 3;
	}
	let text = join(parts, [0x20, 0x0A, 0x20, 0x2029]);
	const count = text.length as int32;
	if ((count & (count - 1)) == 0) { text.push(0x20); }
	return text;
}

// Per engine case one context: automatic segmentation under each paragraph direction, shaper.c's
// forced path, features with a manual break and a second shape that inherits the unpopped
// overrides, mixed texts across paragraphs. Then a Hangul jamo text, a right-to-left text whose bases
// take a vertical advance under ss23 and ss24 in the lookup fixture, and two texts past the C's first
// input block.
export function kbShapeCases(font: KbFont, perPool: int32): KbShapeCase[] {
	const items = kbEngineFontCases(font, perPool);
	const n = items.length as int32;
	const paragraphs: uint32[] = [0, KB_DIRECTION_LTR, KB_DIRECTION_RTL];
	let cases: KbShapeCase[] = [];
	for (let c: int32 = 0; c < n; c++) {
		const item = items[c];
		const next = items[(c + 1) % n].codepoints;
		const other = items[(c + 7) % n].codepoints;
		const paragraph = paragraphs[c % 3] as int32;
		let ops: int32[] = [];
		const mode = c % 4;
		if (mode == 0) {
			emit(ops, [1, paragraph, 0]);
			pushText(ops, item.codepoints, 1);
			ops.push(9);
		} else if (mode == 1) {
			emit(ops, [1, item.direction as int32, 0]);
			pushForced(ops, item.codepoints, item.direction, c % 2 == 1 ? (item.codepoints.length as int32) / 2 : -1);
			ops.push(9);
		} else if (mode == 2) {
			const half = (item.codepoints.length as int32) / 2;
			emit(ops, [1, paragraph, 0]);
			emit(ops, [2, LIGA, 0]);
			if (c % 8 == 6) { emit(ops, [2, SMCP, 1]); }
			pushText(ops, item.codepoints.slice(0, half), 0);
			ops.push(5);
			emit(ops, [3, LIGA]);
			pushText(ops, item.codepoints.slice(half), 50);
			ops.push(9);
			emit(ops, [1, paragraphs[(c + 1) % 3] as int32, 0]);
			emit(ops, [2, KERN, 0]);
			pushText(ops, next, 7);
			ops.push(9);
			emit(ops, [3, KERN]);
			emit(ops, [3, SMCP]);
		} else {
			emit(ops, [1, 0, 0]);
			pushText(ops, join([item.codepoints, other, next], [0x0A, 0x20]), 2);
			ops.push(9);
			emit(ops, [1, KB_DIRECTION_RTL as int32, 0]);
			pushText(ops, other, 5);
			ops.push(9);
		}
		cases.push({ varied: item.varied, fallback: c % 5 == 3, ops });
	}
	let jamo: int32[] = [];
	emit(jamo, [1, 0, 0]);
	pushText(jamo, [0xA960, 0x1161, 0xA97C, 0x1175, 0x11A8, 0x20, 0xA960, 0xD7B0, 0x1100, 0x1161, 0xA960, 0x1160], 0);
	jamo.push(9);
	cases.push({ varied: false, fallback: false, ops: jamo });
	let verticalAttach: int32[] = [];
	emit(verticalAttach, [1, KB_DIRECTION_RTL as int32, 0]);
	emit(verticalAttach, [2, SS23, 1]);
	emit(verticalAttach, [2, SS24, 1]);
	pushForced(verticalAttach, [0x63, 0x301, 0x64, 0x301, 0x62, 0x301, 0x63, 0x303, 0x61, 0x301], KB_DIRECTION_RTL, -1);
	verticalAttach.push(9);
	cases.push({ varied: false, fallback: false, ops: verticalAttach });
	let longAuto: int32[] = [];
	emit(longAuto, [1, 0, 0]);
	pushText(longAuto, longText(items, 140), 0);
	longAuto.push(9);
	cases.push({ varied: false, fallback: true, ops: longAuto });
	let longForced: int32[] = [];
	emit(longForced, [1, KB_DIRECTION_LTR as int32, 0]);
	pushForced(longForced, longText(items, 300), KB_DIRECTION_LTR, 200);
	longForced.push(9);
	cases.push({ varied: true, fallback: false, ops: longForced });
	return cases;
}

function slotOf(font: KbFont | null, primary: KbFont, fallback: KbFont | null): int32 {
	if (font === null) { return -1; }
	if (font === primary) { return 0; }
	if (fallback !== null && font === fallback) { return 1; }
	return -2;
}

function endAndDump(
	ctx: KbShapeContext,
	primary: KbFont,
	fallback: KbFont | null,
	out: int32[],
	shaperRuns: int32[],
): void {
	kbShapeEnd(ctx);
	let run = kbShapeRun(ctx);
	while (run !== null) {
		out.push(1000);
		out.push(run.flags as int32);
		out.push(run.script as int32);
		out.push(run.paragraphDirection as int32);
		out.push(run.direction as int32);
		out.push(slotOf(run.font, primary, fallback));
		const countAt = out.length as int32;
		out.push(0);
		let glyphs: int32 = 0;
		let glyph: KbGlyph = kbZeroGlyph();
		while (kbGlyphIteratorNext(run.glyphs, out glyph)) {
			const source = kbShapeGetShapeCodepoint(ctx, glyph.userIdOrCodepointIndex);
			out.push(glyph.id as int32);
			out.push(glyph.codepoint as int32);
			out.push(glyph.userIdOrCodepointIndex);
			out.push(source !== null ? 1 : 0);
			out.push(source !== null ? source.userId : 0);
			out.push(glyph.offsetX);
			out.push(glyph.offsetY);
			out.push(glyph.advanceX);
			out.push(glyph.advanceY);
			glyphs++;
		}
		out[countAt] = glyphs;
		const config = run.config;
		if (config !== null) { shaperRuns[config.shaper as int32]++; }
		run = kbShapeRun(ctx);
	}
	out.push(2000);
	out.push(ctx.inputCount);
	for (let i: int32 = 0; i < ctx.inputCount; i++) {
		const cp = kbShapeGetShapeCodepoint(ctx, i);
		if (cp === null) { throw new Error(`kb shape corpus: codepoint ${i} missing`); }
		out.push(1);
		out.push(cp.codepoint);
		out.push(cp.userId);
		out.push(cp.breakFlags as int32);
		out.push(cp.script as int32);
		out.push(cp.direction as int32);
		out.push(cp.paragraphDirection as int32);
		out.push(cp.featureOverrideCount);
		out.push(slotOf(cp.font, primary, fallback));
	}
	out.push(0);
}

function replay(
	primary: KbFont,
	fallback: KbFont | null,
	vector: float32[] | null,
	ops: int32[],
	shaperRuns: int32[],
): int32[] {
	const ctx = new KbShapeContext();
	if (fallback !== null) { kbShapePushFont(ctx, fallback, []); }
	let variations: KbVariation[] = [];
	if (vector !== null) {
		for (let i: int32 = 0; i < vector.length; i++) {
			const axis = kbGetVariationAxisInfo(primary, i);
			if (axis.valid) { variations.push({ tag: axis.tag, value: vector[i] }); }
		}
	}
	kbShapePushFont(ctx, primary, variations);
	let out: int32[] = [];
	let i: int32 = 0;
	while (i < ops.length) {
		const op = ops[i];
		if (op == 1) {
			kbShapeBegin(ctx, ops[i + 1] as uint32, ops[i + 2] as uint32);
			i += 3;
		} else if (op == 2) {
			kbShapePushFeature(ctx, ops[i + 1] as uint32, ops[i + 2]);
			i += 3;
		} else if (op == 3) {
			out.push(kbShapePopFeature(ctx, ops[i + 1] as uint32) ? 3001 : 3000);
			i += 2;
		} else if (op == 4) {
			kbShapeCodepointWithUserId(ctx, ops[i + 1], ops[i + 2]);
			i += 3;
		} else if (op == 5) {
			kbShapeManualBreak(ctx);
			i += 1;
		} else if (op == 6) {
			kbShapeBeginManualRuns(ctx);
			i += 1;
		} else if (op == 7) {
			kbShapeNextManualRun(ctx, ops[i + 1] as uint32, ops[i + 2] as uint32);
			i += 3;
		} else if (op == 8) {
			kbShapeEndManualRuns(ctx);
			i += 1;
		} else if (op == 9) {
			endAndDump(ctx, primary, fallback, out, shaperRuns);
			i += 1;
		} else {
			throw new Error(`kb shape corpus: unknown op ${op}`);
		}
	}
	return out;
}

// The port's dump of one case, or [-1] where it refuses an out-of-bounds read the C would make.
export function kbShapePortRun(
	primary: KbFont,
	fallback: KbFont | null,
	vector: float32[] | null,
	ops: int32[],
	shaperRuns: int32[],
): int32[] {
	try {
		return replay(primary, fallback, vector, ops, shaperRuns);
	} catch (e) {
		if (e instanceof KbFontBoundsError) { return [-1]; }
		throw e;
	}
}

export function kbShapeDigestOf(font: KbFont, fallback: KbFont | null, perPool: int32): uint32 {
	const vector = kbEngineVariedVector(font);
	let shaperRuns: int32[] = [0, 0, 0, 0, 0, 0, 0, 0, 0];
	let h: uint32 = 2166136261;
	for (const item of kbShapeCases(font, perPool)) {
		h = kbConfigDigestStep(h, kbShapePortRun(font, item.fallback ? fallback : null, item.varied ? vector : null,
			item.ops, shaperRuns));
	}
	return h;
}
