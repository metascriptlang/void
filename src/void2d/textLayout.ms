import {
	glyphIndex,
	glyphAdvance,
	glyphKern,
	faceMetrics,
	FaceMetrics,
	decorationMetrics,
	DecorationMetrics,
} from "./face";
import { CodepointFace, FontId, codepointFace, fontFace, fontKerns } from "./font";
import { GraphemeCursor, startGraphemes, breaksBefore } from "./grapheme";
import { lineBreaks } from "./lineBreak";

const SPACE: int32 = 32;
const NEWLINE: int32 = 10;
const TAB: int32 = 9;
const DELETE: int32 = 127;
const TEXT_PRESENTATION: int32 = 0xFE0E;
const EMOJI_PRESENTATION: int32 = 0xFE0F;
const ZERO_WIDTH_JOINER: int32 = 0x200D;

export const NO_GLYPH: int32 = -1;
export const TAB_STOP_SPACES: int32 = 8;

export struct TextStyle {
	font: FontId;
	size: float32;
	letterSpacing: float32;
	lineSpacing: float32;
	maxWidth: float32;
	align: float32;
}

export struct LaidGlyph {
	face: int32;
	glyph: int32;
	size: float32;
	codepoint: int32;
	x: float32;
	advance: float32;
	line: int32;
	charIndex: int32;
	byteStart: int32;
	byteEnd: int32;
}

export struct LineBox {
	firstGlyph: int32;
	glyphCount: int32;
	x: float32;
	top: float32;
	baseline: float32;
	height: float32;
	width: float32;
	charStart: int32;
	charEnd: int32;
	byteStart: int32;
	byteEnd: int32;
}

export struct TextLayout {
	glyphs: Vec<LaidGlyph>;
	lines: Vec<LineBox>;
	ascent: float32;
	descent: float32;
	lineHeight: float32;
	width: float32;
	height: float32;
	decoration: DecorationMetrics;
}

struct Codepoint {
	value: int32;
	byteStart: int32;
	byteEnd: int32;
	face: int32;
	scale: float32;
	breakBefore: boolean;
}

enum GraphemeCoverage {
	NoFaceCoversAll,
}

function decodeUtf8(text: string): Vec<Codepoint> {
	const out: Vec<Codepoint> = new Array(0);
	const bytes: Span<char> = text;
	const total: int32 = bytes.length as int32;
	let i: int32 = 0;
	while (i < total) {
		const lead: int32 = (bytes[i] as uint8) as int32;
		let length: int32 = 1;
		let value: int32 = lead;
		if (lead >= 0xF0) {
			length = 4;
			value = lead & 0x07;
		} else if (lead >= 0xE0) {
			length = 3;
			value = lead & 0x0F;
		} else if (lead >= 0xC0) {
			length = 2;
			value = lead & 0x1F;
		}
		if (i + length > total) { length = total - i; }
		for (let k = 1; k < length; k++) {
			value = (value << 6) | (((bytes[i + k] as uint8) as int32) & 0x3F);
		}
		out.push({ value: value, byteStart: i, byteEnd: i + length, face: -1, scale: 1.0,
			breakBefore: false,
		});
		i = i + length;
	}
	return out;
}

struct Run {
	glyphs: Vec<LaidGlyph>;
	width: float32;
}

struct Step {
	face: int32;
	glyph: int32;
	size: float32;
	x: float32;
	advance: float32;
	next: float32;
}

function isControl(codepoint: int32): boolean {
	return codepoint < SPACE || codepoint == DELETE;
}

function tabStop(style: TextStyle): float32 {
	const primary: int32 = fontFace(style.font);
	const space: float32 = glyphAdvance(primary, glyphIndex(primary, SPACE), style.size);
	return (TAB_STOP_SPACES as float32) * space;
}

function faceOf(font: FontId, codepoint: int32): CodepointFace {
	if (isControl(codepoint)) { return { face: fontFace(font), scale: 1.0 }; }
	return codepointFace(font, codepoint);
}

function isJoiner(codepoint: int32): boolean {
	return codepoint == ZERO_WIDTH_JOINER || codepoint == TEXT_PRESENTATION ||
		codepoint == EMOJI_PRESENTATION;
}

function coversGrapheme(face: int32, cps: Span<Codepoint>, first: int32, end: int32): boolean {
	for (let k = first; k < end; k++) {
		if (!isJoiner(cps[k].value) && glyphIndex(face, cps[k].value) == 0) { return false; }
	}
	return true;
}

function graphemeFace(
	font: FontId,
	cps: Span<Codepoint>,
	first: int32,
	end: int32,
): Result<CodepointFace, GraphemeCoverage> {
	for (let k = first; k < end; k++) {
		if (k > first && isJoiner(cps[k].value)) { continue; }
		const candidate: CodepointFace = faceOf(font, cps[k].value);
		if (coversGrapheme(candidate.face, cps, first, end)) { return Result.ok(candidate); }
	}
	return Result.err(GraphemeCoverage.NoFaceCoversAll);
}

function assignGrapheme(font: FontId, cps: Span<Codepoint>, first: int32, end: int32): void {
	if (end - first > 1) {
		const whole = graphemeFace(font, cps, first, end);
		if (whole.ok) {
			for (let k = first; k < end; k++) {
				cps[k].face = whole.value.face;
				cps[k].scale = whole.value.scale;
			}
			return;
		}
	}
	for (let k = first; k < end; k++) {
		const source: CodepointFace = faceOf(font, cps[k].value);
		cps[k].face = source.face;
		cps[k].scale = source.scale;
	}
}

function assignFaces(font: FontId, cps: Span<Codepoint>): void {
	let cursor: GraphemeCursor = startGraphemes();
	let first: int32 = 0;
	const count: int32 = cps.length as int32;
	for (let i = 0; i < count; i++) {
		if (breaksBefore(cursor, cps[i].value) && i > first) {
			assignGrapheme(font, cps, first, i);
			first = i;
		}
	}
	if (count > first) { assignGrapheme(font, cps, first, count); }
}

function assignBreaks(cps: Span<Codepoint>): void {
	const values: Vec<int32> = new Array(0);
	for (const cp of cps) { values.push(cp.value); }
	const breaks = lineBreaks(values);
	for (let i = 0; i < (cps.length as int32); i++) { cps[i].breakBefore = breaks[i]; }
}

function step(
	codepoint: Codepoint,
	pen: float32,
	previous: int32,
	previousFace: int32,
	style: TextStyle,
	kerns: boolean,
): Step {
	if (isControl(codepoint.value)) {
		let next: float32 = pen;
		if (codepoint.value == TAB) {
			const stop: float32 = tabStop(style);
			next = ((Math.floor(pen / stop) as float32) + 1.0) * stop;
		}
		return {
			face: codepoint.face, glyph: NO_GLYPH, size: style.size, x: pen, advance: next - pen,
			next: next,
		};
	}
	const face: int32 = codepoint.face;
	const size: float32 = style.size * codepoint.scale;
	const glyph: int32 = glyphIndex(face, codepoint.value);
	let x: float32 = pen;
	if (previous >= 0 && previousFace == face && kerns) {
		x = pen + glyphKern(face, previous, glyph, size);
	}
	const advance: float32 = glyphAdvance(face, glyph, size);
	return {
		face: face, glyph: glyph, size: size, x: x, advance: advance,
		next: x + advance + style.letterSpacing,
	};
}

function layRun(
	cps: Span<Codepoint>,
	from: int32,
	to: int32,
	style: TextStyle,
	line: int32,
): Run {
	const glyphs: Vec<LaidGlyph> = new Array(0);
	let pen: float32 = 0.0;
	let width: float32 = 0.0;
	let previous: int32 = NO_GLYPH;
	let previousFace: int32 = -1;
	const kerns: boolean = fontKerns(style.font);
	for (let i = from; i < to; i++) {
		const value: int32 = cps[i].value;
		const s = step(cps[i], pen, previous, previousFace, style, kerns);
		glyphs.push({
			face: s.face,
			glyph: s.glyph,
			size: s.size,
			codepoint: value,
			x: s.x,
			advance: s.advance,
			line: line,
			charIndex: i,
			byteStart: cps[i].byteStart,
			byteEnd: cps[i].byteEnd,
		});
		if (value != SPACE && s.glyph != NO_GLYPH) { width = s.x + s.advance; }
		pen = s.next;
		previous = s.glyph;
		previousFace = s.face;
	}
	return { glyphs: glyphs, width: width };
}

struct LineBreak {
	end: int32;
	next: int32;
}

function breakAt(cps: Span<Codepoint>, next: int32): LineBreak {
	const end: int32 = cps[next - 1].value == SPACE ? next - 1 : next;
	return { end: end, next: next };
}

function breakAfter(cps: Span<Codepoint>, from: int32, to: int32, style: TextStyle): LineBreak {
	const whole: LineBreak = { end: to, next: to };
	if (style.maxWidth <= 0.0) { return whole; }
	let candidate: int32 = -1;
	let inked: boolean = false;
	let pen: float32 = 0.0;
	let previous: int32 = NO_GLYPH;
	let previousFace: int32 = -1;
	const kerns: boolean = fontKerns(style.font);
	for (let i = from; i < to; i++) {
		const value: int32 = cps[i].value;
		if (i > from && inked && cps[i].breakBefore) { candidate = i; }
		const s = step(cps[i], pen, previous, previousFace, style, kerns);
		if (value != SPACE && candidate > from && s.x + s.advance > style.maxWidth) {
			return breakAt(cps, candidate);
		}
		if (value != SPACE) { inked = true; }
		pen = s.next;
		previous = s.glyph;
		previousFace = s.face;
	}
	return whole;
}

function tallestFaces(glyphs: Span<LaidGlyph>, primary: int32, style: TextStyle): FaceMetrics {
	const own: FaceMetrics = faceMetrics(primary, style.size);
	let ascent: float32 = own.ascent;
	let descent: float32 = own.descent;
	let measuredFace: int32 = primary;
	let measuredSize: float32 = style.size;
	for (let i = 0; i < (glyphs.length as int32); i++) {
		const face: int32 = glyphs[i].face;
		const size: float32 = glyphs[i].size;
		if (glyphs[i].glyph == NO_GLYPH || (face == measuredFace && size == measuredSize)) {
			continue;
		}
		const m: FaceMetrics = faceMetrics(face, size);
		if (m.ascent > ascent) { ascent = m.ascent; }
		if (m.descent > descent) { descent = m.descent; }
		measuredFace = face;
		measuredSize = size;
	}
	return { ascent: ascent, descent: descent, lineGap: own.lineGap };
}

export function layout(this typeof TextLayout, text: string, style: TextStyle): TextLayout {
	const primary: int32 = fontFace(style.font);
	const metrics = faceMetrics(primary, style.size);
	const lineHeight: float32 = metrics.ascent + metrics.descent + metrics.lineGap;
	const cps: Vec<Codepoint> = decodeUtf8(text);
	assignFaces(style.font, cps);
	if (style.maxWidth > 0.0) { assignBreaks(cps); }
	const count: int32 = cps.length as int32;
	const textBytes: int32 = count > 0 ? cps[count - 1].byteEnd : 0;
	const glyphs: Vec<LaidGlyph> = new Array(0);
	const lines: Vec<LineBox> = new Array(0);
	let width: float32 = 0.0;
	let top: float32 = 0.0;
	let start: int32 = 0;
	while (true) {
		let paragraphEnd: int32 = start;
		while (paragraphEnd < count && cps[paragraphEnd].value != NEWLINE) {
			paragraphEnd = paragraphEnd + 1;
		}
		const lineBreak: LineBreak = breakAfter(cps, start, paragraphEnd, style);
		const end: int32 = lineBreak.end;
		const lineIndex: int32 = lines.length as int32;
		const run = layRun(cps, start, end, style, lineIndex);
		const box: FaceMetrics = tallestFaces(run.glyphs, primary, style);
		const height: float32 = box.ascent + box.descent + box.lineGap;
		const x: float32 = -run.width * style.align;
		const firstGlyph: int32 = glyphs.length as int32;
		for (const g of run.glyphs) { glyphs.push({ ...g, x: g.x + x }); }
		const byteStart: int32 = start < count ? cps[start].byteStart : textBytes;
		const byteEnd: int32 = end > start ? cps[end - 1].byteEnd : byteStart;
		lines.push({
			firstGlyph: firstGlyph,
			glyphCount: run.glyphs.length as int32,
			x: x,
			top: top,
			baseline: top + box.ascent,
			height: height,
			width: run.width,
			charStart: start,
			charEnd: end,
			byteStart: byteStart,
			byteEnd: byteEnd,
		});
		if (run.width > width) { width = run.width; }
		top = top + height + style.lineSpacing;
		if (lineBreak.next < paragraphEnd) {
			start = lineBreak.next;
		} else if (paragraphEnd < count) {
			start = paragraphEnd + 1;
		} else {
			break;
		}
	}
	return {
		glyphs: glyphs,
		lines: lines,
		ascent: metrics.ascent,
		descent: metrics.descent,
		lineHeight: lineHeight,
		width: width,
		height: top - style.lineSpacing,
		decoration: decorationMetrics(primary, style.size),
	};
}

export function calcTextWidth(text: string, style: TextStyle): float32 {
	return TextLayout.layout(text, { ...style, maxWidth: 0.0 }).width;
}

export function splitText(this l: TextLayout, text: string): string {
	let out: string = "";
	for (let i = 0; i < (l.lines.length as int32); i++) {
		if (i > 0) { out += "\n"; }
		out += text.byteSlice(l.lines[i].byteStart, l.lines[i].byteEnd);
	}
	return out;
}

export function xForByte(this l: TextLayout, byteIndex: int32): float32 {
	for (const line of l.lines) {
		if (byteIndex < line.byteStart || byteIndex > line.byteEnd) { continue; }
		for (let i = line.firstGlyph; i < line.firstGlyph + line.glyphCount; i++) {
			if (l.glyphs[i].byteStart == byteIndex) { return l.glyphs[i].x; }
		}
		if (line.glyphCount == 0) { return line.x; }
		const last: LaidGlyph = l.glyphs[line.firstGlyph + line.glyphCount - 1];
		return last.x + last.advance;
	}
	return 0.0;
}

export function byteForX(this l: TextLayout, lineIndex: int32, x: float32): int32 {
	const line: LineBox = l.lines[lineIndex];
	for (let i = line.firstGlyph; i < line.firstGlyph + line.glyphCount; i++) {
		const g: LaidGlyph = l.glyphs[i];
		if (x < g.x + g.advance * 0.5) { return g.byteStart; }
	}
	return line.byteEnd;
}
