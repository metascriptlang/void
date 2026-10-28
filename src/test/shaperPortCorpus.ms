import { glyphFaceBytes } from "../void2d/glyph";
import { KbFont, kbFontFromMemory, kbFontIsValid } from "../void2d/kb/font";
import {
	ShapeDirection,
	ShapedGlyph,
	shaperBreak,
	shaperCodepoint,
	shaperEnd,
	shaperFeature,
	shaperGlyph,
	shaperTryBegin,
} from "../void2d/shaper";
import { kbConfigDigestStep } from "./kbConfigCorpus";
import { KbEngineCase, kbEngineFontCases } from "./kbEngineCorpus";

export const OP_BEGIN: int32 = 1;
export const OP_FEATURE: int32 = 2;
export const OP_CODEPOINT: int32 = 4;
export const OP_BREAK: int32 = 5;
export const OP_END: int32 = 9;

const LIGA: int32 = 0x6167696C;
const KERN: int32 = 0x6E72656B;
const SMCP: int32 = 0x70636D73;
const CALT: int32 = 0x746C6163;
const SS23: int32 = 0x33327373;
const SS24: int32 = 0x34327373;

export function shaperTagText(tag: int32): string {
	let text = "";
	for (let i: int32 = 0; i < 4; i++) {
		text += String.fromCharCode((tag >> (i * 8)) & 0xFF);
	}
	return text;
}

function emit(ops: int32[], values: int32[]): void {
	for (const value of values) { ops.push(value); }
}

function pushText(ops: int32[], codepoints: int32[], breakAt: int32): void {
	for (let i: int32 = 0; i < codepoints.length; i++) {
		if (i == breakAt) { ops.push(OP_BREAK); }
		ops.push(OP_CODEPOINT);
		ops.push(codepoints[i]);
	}
}

function pass(ops: int32[], direction: int32, codepoints: int32[], breakAt: int32): void {
	emit(ops, [OP_BEGIN, direction]);
	pushText(ops, codepoints, breakAt);
	ops.push(OP_END);
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
	return join(parts, [0x20, 0x0A, 0x20, 0x2029]);
}

function forcedOf(direction: uint32): int32 {
	return direction == 2 ? 2 : 1;
}

export function shaperPortCases(font: KbFont, perPool: int32): int32[][] {
	let cases: int32[][] = [];
	const bridge: int32[] = [0x41, 0x56];
	const arrow: int32[] = [0x2D, 0x3E];
	cases.push([OP_BEGIN, 0, OP_CODEPOINT, 0x41, OP_CODEPOINT, 0x56, OP_END]);
	let calt: int32[] = [OP_BEGIN, 0, OP_FEATURE, CALT, 0];
	pushText(calt, arrow, -1);
	calt.push(OP_END);
	cases.push(calt);
	let split: int32[] = [];
	pass(split, 0, arrow, 1);
	cases.push(split);
	let forcedBridge: int32[] = [];
	pass(forcedBridge, 1, bridge, -1);
	cases.push(forcedBridge);
	if (!kbFontIsValid(font)) { return cases; }
	const items = kbEngineFontCases(font, perPool);
	const n = items.length as int32;
	for (let c: int32 = 0; c < n; c++) {
		const item = items[c];
		const next = items[(c + 1) % n].codepoints;
		const other = items[(c + 7) % n].codepoints;
		const half = (item.codepoints.length as int32) / 2;
		let ops: int32[] = [];
		const mode = c % 4;
		if (mode == 0) {
			pass(ops, 0, item.codepoints, -1);
		} else if (mode == 1) {
			pass(ops, forcedOf(item.direction), item.codepoints, c % 8 == 3 ? half : -1);
		} else if (mode == 2) {
			emit(ops, [OP_BEGIN, c % 8 == 6 ? 0 : forcedOf(item.direction)]);
			emit(ops, [OP_FEATURE, LIGA, 0]);
			if (c % 8 == 6) { emit(ops, [OP_FEATURE, SMCP, 1]); }
			pushText(ops, item.codepoints, half);
			ops.push(OP_END);
			emit(ops, [OP_BEGIN, 0, OP_FEATURE, KERN, 0]);
			pushText(ops, next, -1);
			ops.push(OP_END);
		} else {
			pass(ops, 0, join([item.codepoints, other, next], [0x0A, 0x20]), -1);
			pass(ops, 2, other, -1);
		}
		cases.push(ops);
	}
	let jamo: int32[] = [];
	const jamoText: int32[] = [
		0xA960, 0x1161, 0xA97C, 0x1175, 0x11A8, 0x20, 0xA960, 0xD7B0, 0x1100, 0x1161, 0xA960, 0x1160,
	];
	pass(jamo, 0, jamoText, -1);
	cases.push(jamo);
	let verticalAttach: int32[] = [OP_BEGIN, 2, OP_FEATURE, SS23, 1, OP_FEATURE, SS24, 1];
	pushText(verticalAttach, [0x63, 0x301, 0x64, 0x301, 0x62, 0x301, 0x63, 0x303, 0x61, 0x301], -1);
	verticalAttach.push(OP_END);
	cases.push(verticalAttach);
	let longAuto: int32[] = [];
	pass(longAuto, 0, longText(items, 140), -1);
	cases.push(longAuto);
	let longForced: int32[] = [];
	pass(longForced, 1, longText(items, 300), 200);
	cases.push(longForced);
	return cases;
}

function directionOf(code: int32): ShapeDirection {
	return match (code) {
		1 => ShapeDirection.Ltr,
		2 => ShapeDirection.Rtl,
		_ => ShapeDirection.Unknown,
	};
}

export function shaperDumpGlyph(out: int32[], g: ShapedGlyph): void {
	emit(out, [g.glyph, g.advanceX, g.advanceY, g.offsetX, g.offsetY, g.index, g.codepoint]);
	out.push(g.direction as int32);
	out.push(g.run);
}

export function shaperPortReplay(face: int32, ops: int32[]): int32[] {
	let out: int32[] = [];
	let skipping = false;
	let i: int32 = 0;
	while (i < ops.length) {
		const op = ops[i];
		if (op == OP_BEGIN) {
			skipping = !shaperTryBegin(face, directionOf(ops[i + 1]));
			out.push(skipping ? 100 : 101);
			i += 2;
		} else if (op == OP_FEATURE) {
			if (!skipping) { shaperFeature(shaperTagText(ops[i + 1]), ops[i + 2]); }
			i += 3;
		} else if (op == OP_CODEPOINT) {
			if (!skipping) { shaperCodepoint(ops[i + 1]); }
			i += 2;
		} else if (op == OP_BREAK) {
			if (!skipping) { shaperBreak(); }
			i += 1;
		} else if (op == OP_END) {
			if (!skipping) {
				const count = shaperEnd();
				out.push(count);
				for (let g: int32 = 0; g < count; g++) { shaperDumpGlyph(out, shaperGlyph(g)); }
			}
			skipping = false;
			i += 1;
		} else {
			throw new Error(`shaper port corpus: unknown op ${op}`);
		}
	}
	return out;
}

export function shaperCaseFont(face: int32): KbFont {
	const bytes = glyphFaceBytes(face);
	if (bytes == null) { throw new Error(`shaper port corpus: face ${face} has no bytes`); }
	return kbFontFromMemory(bytes.data[0..bytes.data.length], 0);
}

export function shaperPortDigest(face: int32, perPool: int32): uint32 {
	let h: uint32 = 2166136261;
	for (const ops of shaperPortCases(shaperCaseFont(face), perPool)) {
		h = kbConfigDigestStep(h, shaperPortReplay(face, ops));
	}
	return h;
}
