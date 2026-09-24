import {
	glyphIndex,
	glyphAdvance,
	glyphKern,
	faceMetrics,
	decorationMetrics,
	DecorationMetrics,
} from "./face";
import { codepointFace, fontFace, fontKerns } from "./font";

const SPACE: int32 = 32;
const NEWLINE: int32 = 10;

export struct TextStyle {
	font: int32;
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
		out.push({ value: value, byteStart: i, byteEnd: i + length });
		i = i + length;
	}
	return out;
}

struct Run {
	glyphs: Vec<LaidGlyph>;
	width: float32;
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
	let previous: int32 = -1;
	let previousFace: int32 = -1;
	const kerns: boolean = fontKerns(style.font);
	for (let i = from; i < to; i++) {
		const source = codepointFace(style.font, cps[i].value);
		const face: int32 = source.face;
		const size: float32 = style.size * source.scale;
		const glyph: int32 = glyphIndex(face, cps[i].value);
		if (previous >= 0 && previousFace == face && kerns) {
			pen = pen + glyphKern(face, previous, glyph, size);
		}
		const advance: float32 = glyphAdvance(face, glyph, size);
		glyphs.push({
			face: face,
			glyph: glyph,
			size: size,
			codepoint: cps[i].value,
			x: pen,
			advance: advance,
			line: line,
			charIndex: i,
			byteStart: cps[i].byteStart,
			byteEnd: cps[i].byteEnd,
		});
		if (cps[i].value != SPACE) { width = pen + advance; }
		pen = pen + advance + style.letterSpacing;
		previous = glyph;
		previousFace = face;
	}
	return { glyphs: glyphs, width: width };
}

function breakAfter(cps: Span<Codepoint>, from: int32, to: int32, style: TextStyle): int32 {
	if (style.maxWidth <= 0.0) { return to; }
	let lastSpace: int32 = -1;
	let pen: float32 = 0.0;
	let previous: int32 = -1;
	let previousFace: int32 = -1;
	const kerns: boolean = fontKerns(style.font);
	for (let i = from; i < to; i++) {
		const source = codepointFace(style.font, cps[i].value);
		const face: int32 = source.face;
		const size: float32 = style.size * source.scale;
		const glyph: int32 = glyphIndex(face, cps[i].value);
		if (previous >= 0 && previousFace == face && kerns) {
			pen = pen + glyphKern(face, previous, glyph, size);
		}
		const advance: float32 = glyphAdvance(face, glyph, size);
		if (cps[i].value == SPACE) {
			lastSpace = i;
		} else if (lastSpace >= from && pen + advance > style.maxWidth) {
			return lastSpace;
		}
		pen = pen + advance + style.letterSpacing;
		previous = glyph;
		previousFace = face;
	}
	return to;
}

export function layout(this typeof TextLayout, text: string, style: TextStyle): TextLayout {
	const primary: int32 = fontFace(style.font);
	const metrics = faceMetrics(primary, style.size);
	const lineHeight: float32 = metrics.ascent + metrics.descent + metrics.lineGap;
	const cps: Vec<Codepoint> = decodeUtf8(text);
	const count: int32 = cps.length as int32;
	const textBytes: int32 = count > 0 ? cps[count - 1].byteEnd : 0;
	const glyphs: Vec<LaidGlyph> = new Array(0);
	const lines: Vec<LineBox> = new Array(0);
	let width: float32 = 0.0;
	let start: int32 = 0;
	while (true) {
		let paragraphEnd: int32 = start;
		while (paragraphEnd < count && cps[paragraphEnd].value != NEWLINE) {
			paragraphEnd = paragraphEnd + 1;
		}
		const end: int32 = breakAfter(cps, start, paragraphEnd, style);
		const lineIndex: int32 = lines.length as int32;
		const run = layRun(cps, start, end, style, lineIndex);
		const top: float32 = (lineIndex as float32) * (lineHeight + style.lineSpacing);
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
			baseline: top + metrics.ascent,
			width: run.width,
			charStart: start,
			charEnd: end,
			byteStart: byteStart,
			byteEnd: byteEnd,
		});
		if (run.width > width) { width = run.width; }
		if (end < paragraphEnd) {
			start = end + 1;
		} else if (paragraphEnd < count) {
			start = paragraphEnd + 1;
		} else {
			break;
		}
	}
	const lineCount: float32 = lines.length as float32;
	const gaps: float32 = lineCount - (1 as float32);
	return {
		glyphs: glyphs,
		lines: lines,
		ascent: metrics.ascent,
		descent: metrics.descent,
		lineHeight: lineHeight,
		width: width,
		height: lineCount * lineHeight + gaps * style.lineSpacing,
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
		out += text.slice(l.lines[i].charStart, l.lines[i].charEnd);
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
