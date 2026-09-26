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
import { Color } from "./types";
import { GraphemeCursor, startGraphemes, breaksBefore } from "./grapheme";
import { lineBreaks } from "./lineBreak";

const SPACE: int32 = 32;
const NEWLINE: int32 = 10;
const TAB: int32 = 9;
const DELETE: int32 = 127;
const TEXT_PRESENTATION: int32 = 0xFE0E;
const EMOJI_PRESENTATION: int32 = 0xFE0F;
const ZERO_WIDTH_JOINER: int32 = 0x200D;

const ELLIPSIS: int32 = 0x2026;

export const NO_GLYPH: int32 = -1;
export const TAB_STOP_SPACES: int32 = 8;

export enum Truncate {
	None,
	Start,
	Middle,
	End,
}

export struct LineOptions {
	truncate: Truncate;
	hangingIndent: float32;
	forceWidth: float32;
}

export const PLAIN_LINES: LineOptions = {
	truncate: Truncate.None,
	hangingIndent: 0.0,
	forceWidth: 0.0,
};

export enum Align {
	Left,
	Right,
	Center,
	MultilineRight,
	MultilineCenter,
}

export struct TextStyle {
	font: FontId;
	size: float32;
	letterSpacing: float32;
	lineSpacing: float32;
	maxWidth: float32;
	align: Align;
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
	index: int32;
	byteStart: int32;
	byteEnd: int32;
	run: int32;
	clusterStart: boolean;
}

export const NO_RUN: int32 = -1;

export struct TextRun {
	len: int32;
	font: FontId;
	color: Color;
	background: Color;
	underline: Color;
	wavy: boolean;
	strikethrough: Color;
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
	indexStart: int32;
	indexEnd: int32;
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

export interface ShapedText {
	glyphs: Vec<LaidGlyph>;
	values: Vec<int32>;
	breaks: Vec<boolean>;
	ellipsis: Vec<LaidGlyph>;
	units: int32;
	bytes: int32;
	style: TextStyle;
	tabStop: float32;
}

struct Codepoint {
	value: int32;
	index: int32;
	byteStart: int32;
	byteEnd: int32;
	font: FontId;
	run: int32;
	face: int32;
	scale: float32;
	clusterStart: boolean;
	shapingBreak: boolean;
}

enum GraphemeCoverage {
	NoFaceCoversAll,
}

function decodeUtf8(text: string, font: FontId): Vec<Codepoint> {
	const out: Vec<Codepoint> = new Array(0);
	let index: int32 = 0;
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
		out.push({
			value: value, index: index, byteStart: i, byteEnd: i + length, font: font,
			run: NO_RUN, face: -1, scale: 1.0, clusterStart: false, shapingBreak: false,
		});
		index = index + (value >= 0x10000 ? 2 : 1);
		i = i + length;
	}
	return out;
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

function tabStop(this style: TextStyle): float32 {
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

function assignGrapheme(cps: Span<Codepoint>, first: int32, end: int32): void {
	const font: FontId = cps[first].font;
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
		const source: CodepointFace = faceOf(cps[k].font, cps[k].value);
		cps[k].face = source.face;
		cps[k].scale = source.scale;
	}
}

function assignFaces(cps: Span<Codepoint>): void {
	let cursor: GraphemeCursor = startGraphemes();
	let first: int32 = 0;
	const count: int32 = cps.length as int32;
	for (let i = 0; i < count; i++) {
		const boundary: boolean = breaksBefore(cursor, cps[i].value);
		cps[i].clusterStart = boundary;
		if (boundary && i > first) {
			assignGrapheme(cps, first, i);
			first = i;
		}
	}
	if (count > first) { assignGrapheme(cps, first, count); }
}

function step(
	this codepoint: Codepoint,
	pen: float32,
	previous: int32,
	previousFace: int32,
	previousRun: int32,
	style: TextStyle,
	stop: float32,
	spaced: boolean,
): Step {
	if (isControl(codepoint.value)) {
		let next: float32 = pen;
		if (codepoint.value == TAB && stop > 0.0) {
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
	const sameRun: boolean = previousFace == face && previousRun == codepoint.run &&
		!codepoint.shapingBreak;
	if (previous >= 0 && sameRun && fontKerns(codepoint.font)) {
		x = pen + glyphKern(face, previous, glyph, size);
	}
	const advance: float32 = glyphAdvance(face, glyph, size);
	const spacing: float32 = spaced ? style.letterSpacing : 0.0;
	return {
		face: face, glyph: glyph, size: size, x: x, advance: advance, next: x + advance + spacing,
	};
}

struct LineBreak {
	end: int32;
	next: int32;
}

function breakAt(glyphs: Span<LaidGlyph>, next: int32): LineBreak {
	const end: int32 = glyphs[next - 1].codepoint == SPACE ? next - 1 : next;
	return { end: end, next: next };
}

function breakAfter(shaped: ShapedText, from: int32, to: int32, room: float32): LineBreak {
	const whole: LineBreak = { end: to, next: to };
	if (from >= to) { return whole; }
	let delta: float32 = -shaped.glyphs[from].x;
	let candidate: int32 = -1;
	let inked: boolean = false;
	for (let k = from; k < to; k++) {
		const g: LaidGlyph = shaped.glyphs[k];
		const value: int32 = g.codepoint;
		if (k > from && inked && shaped.breaks[k]) { candidate = k; }
		const x: float32 = g.x + delta;
		const advance: float32 = g.rowAdvance(x, shaped.tabStop);
		delta = delta + advance - g.advance;
		const right: float32 = x + advance;
		if (value != SPACE && candidate > from && right > room) {
			return breakAt(shaped.glyphs, candidate);
		}
		if (value != SPACE) { inked = true; }
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

function alignShare(align: Align): float32 {
	return match (align) {
		Align.Left => 0.0,
		Align.Center | Align.MultilineCenter => 0.5,
		Align.Right | Align.MultilineRight => 1.0,
	};
}

function alignLines(
	glyphs: Span<LaidGlyph>,
	lines: Span<LineBox>,
	style: TextStyle,
	widest: float32,
): void {
	const multiline: boolean = style.align == Align.MultilineCenter ||
		style.align == Align.MultilineRight;
	const span: float32 = multiline ? widest : (style.maxWidth > 0.0 ? style.maxWidth : 0.0);
	const share: float32 = alignShare(style.align);
	if (share == 0.0) { return; }
	for (let i = 0; i < (lines.length as int32); i++) {
		const indent: float32 = lines[i].x;
		const x: float32 = (span - indent - lines[i].width) * share;
		lines[i].x = indent + x;
		const first: int32 = lines[i].firstGlyph;
		for (let k = first; k < first + lines[i].glyphCount; k++) {
			glyphs[k].x = glyphs[k].x + x;
		}
	}
}

function unitEnd(this cp: Codepoint): int32 {
	return cp.index + (cp.value >= 0x10000 ? 2 : 1);
}

function assignRuns(cps: Span<Codepoint>, runs: Span<TextRun>, units: int32): void {
	let total: int32 = 0;
	for (const run of runs) { total = total + run.len; }
	if (total != units) {
		console.log(`void2d: text runs cover ${total} UTF-16 units of a text of ${units}`);
		unreachable;
	}
	let run: int32 = 0;
	let runEnd: int32 = runs.length > 0 ? runs[0].len : 0;
	for (let i = 0; i < (cps.length as int32); i++) {
		while (cps[i].index >= runEnd) {
			run = run + 1;
			runEnd = runEnd + runs[run].len;
		}
		if (runEnd < cps[i].unitEnd()) {
			console.log(
				`void2d: text run ${run + 1} starts inside the surrogate pair at ${cps[i].index}`,
			);
			unreachable;
		}
		cps[i].run = run;
		cps[i].font = runs[run].font;
	}
}

function markShapingBreaks(cps: Span<Codepoint>, breaks: Span<int32>): void {
	const count: int32 = cps.length as int32;
	for (const at of breaks) {
		let lo: int32 = 0;
		let hi: int32 = count;
		while (lo < hi) {
			const mid: int32 = (lo + hi) >> 1;
			if (cps[mid].index < at) { lo = mid + 1; } else { hi = mid; }
		}
		if (lo < count && cps[lo].index == at) {
			cps[lo].shapingBreak = true;
		} else if (lo > 0 && cps[lo - 1].unitEnd() > at) {
			console.log(
				`void2d: shaping break ${at} falls inside the surrogate pair at ${cps[lo - 1].index}`,
			);
			unreachable;
		}
	}
}

function hasTab(cps: Span<Codepoint>): boolean {
	for (let i = 0; i < (cps.length as int32); i++) {
		if (cps[i].value == TAB) { return true; }
	}
	return false;
}

// Shapes once: one glyph per codepoint, x measured from the start of its paragraph. A width,
// alignment or truncation change wraps these again without a glyph lookup (GPUI.md:49).
export function shapeText(
	text: string,
	style: TextStyle,
	runs: Span<TextRun>,
	shapingBreaks: Span<int32>,
): ShapedText {
	const cps: Vec<Codepoint> = decodeUtf8(text, style.font);
	const count: int32 = cps.length as int32;
	const units: int32 = count > 0 ? cps[count - 1].unitEnd() : 0;
	if (runs.length > 0) { assignRuns(cps, runs, units); }
	markShapingBreaks(cps, shapingBreaks);
	assignFaces(cps);
	const stop: float32 = hasTab(cps) ? style.tabStop() : 0.0;
	const glyphs: Vec<LaidGlyph> = new Array(0);
	const values: Vec<int32> = new Array(0);
	let pen: float32 = 0.0;
	let previous: int32 = NO_GLYPH;
	let previousFace: int32 = -1;
	let previousRun: int32 = NO_RUN;
	let paragraph: int32 = 0;
	for (let i = 0; i < count; i++) {
		const cp: Codepoint = cps[i];
		values.push(cp.value);
		let s: Step = {
			face: cp.face, glyph: NO_GLYPH, size: style.size, x: pen, advance: 0.0, next: pen,
		};
		if (cp.value != NEWLINE) {
			const spaced: boolean = i + 1 >= count || cps[i + 1].clusterStart;
			s = cp.step(pen, previous, previousFace, previousRun, style, stop, spaced);
		}
		glyphs.push({
			face: s.face,
			glyph: s.glyph,
			size: s.size,
			codepoint: cp.value,
			x: s.x,
			advance: s.advance,
			line: paragraph,
			charIndex: i,
			index: cp.index,
			byteStart: cp.byteStart,
			byteEnd: cp.byteEnd,
			run: cp.run,
			clusterStart: cp.clusterStart,
		});
		if (cp.value == NEWLINE) {
			pen = 0.0;
			previous = NO_GLYPH;
			previousFace = -1;
			previousRun = NO_RUN;
			paragraph = paragraph + 1;
			continue;
		}
		pen = s.next;
		previous = s.glyph;
		previousFace = s.face;
		previousRun = cp.run;
	}
	return {
		glyphs: glyphs,
		values: values,
		breaks: new Array(0),
		ellipsis: new Array(0),
		units: units,
		bytes: count > 0 ? cps[count - 1].byteEnd : 0,
		style: style,
		tabStop: stop,
	};
}

function lineWidthOf(glyphs: Span<LaidGlyph>, first: int32): float32 {
	let width: float32 = 0.0;
	for (let k = first; k < (glyphs.length as int32); k++) {
		const g: LaidGlyph = glyphs[k];
		if (g.codepoint != SPACE && g.glyph != NO_GLYPH) { width = g.x + g.advance; }
	}
	return width;
}

// GPUI's force_width (line_layout.rs:898-921): a base moves onto the grid unless it is within a
// pixel of it, a combining mark keeps its offset. A base is a grapheme's first glyph: GPUI finds
// it by x, which holds only once a shaper has put the marks over their base.
function forceCells(glyphs: Span<LaidGlyph>, first: int32, cell: float32): float32 {
	let cells: int32 = 0;
	let lastShaped: float32 = 0.0;
	let lastActual: float32 = 0.0;
	for (let k = first; k < (glyphs.length as int32); k++) {
		const shaped: float32 = glyphs[k].x;
		if (glyphs[k].clusterStart || k == first) {
			const forced: float32 = (cells as float32) * cell;
			if (Math.abs(shaped - forced) > 1.0) { glyphs[k].x = forced; }
			glyphs[k].advance = cell;
			lastShaped = shaped;
			lastActual = glyphs[k].x;
			cells = cells + 1;
		} else {
			glyphs[k].x = lastActual + (shaped - lastShaped);
		}
	}
	return (cells as float32) * cell;
}

function pushLine(
	shaped: ShapedText,
	from: int32,
	end: int32,
	lineIndex: int32,
	ref out: Vec<LaidGlyph>,
): void {
	let delta: float32 = from < end ? -shaped.glyphs[from].x : 0.0;
	for (let k = from; k < end; k++) {
		const g: LaidGlyph = shaped.glyphs[k];
		const x: float32 = g.x + delta;
		const advance: float32 = g.rowAdvance(x, shaped.tabStop);
		delta = delta + advance - g.advance;
		out.push({ ...g, x: x, advance: advance, line: lineIndex });
	}
}

function rowAdvance(this g: LaidGlyph, x: float32, stop: float32): float32 {
	if (g.codepoint != TAB || stop <= 0.0) { return g.advance; }
	const next: float32 = ((Math.floor(x / stop) as float32) + 1.0) * stop;
	return next - x;
}

function ellipsisGlyph(shaped: ShapedText): LaidGlyph {
	if ((shaped.ellipsis.length as int32) == 0) {
		const style: TextStyle = shaped.style;
		const source: CodepointFace = codepointFace(style.font, ELLIPSIS);
		const size: float32 = style.size * source.scale;
		const glyph: int32 = glyphIndex(source.face, ELLIPSIS);
		shaped.ellipsis.push({
			face: source.face, glyph: glyph, size: size, codepoint: ELLIPSIS, x: 0.0,
			advance: glyphAdvance(source.face, glyph, size), line: 0, charIndex: 0, index: 0,
			byteStart: 0, byteEnd: 0, run: NO_RUN, clusterStart: true,
		});
	}
	return shaped.ellipsis[0];
}

function elided(
	shaped: ShapedText,
	at: int32,
	x: float32,
	lineIndex: int32,
	run: int32,
): LaidGlyph {
	const g: LaidGlyph = shaped.glyphs[at];
	return {
		...ellipsisGlyph(shaped), x: x, line: lineIndex, charIndex: g.charIndex, index: g.index,
		byteStart: g.byteStart, byteEnd: g.byteStart, run: run,
	};
}

// GPUI's truncation (line_wrapper.rs:141-446): the line keeps what fits beside an ellipsis,
// cut only where a grapheme starts.
function trimsBeforeEllipsis(codepoint: int32): boolean {
	if (codepoint < 0x80) {
		return (codepoint >= 0x09 && codepoint <= 0x0D) || codepoint == SPACE ||
			(codepoint >= 0x21 && codepoint <= 0x2F) || (codepoint >= 0x3A && codepoint <= 0x40) ||
			(codepoint >= 0x5B && codepoint <= 0x60) || (codepoint >= 0x7B && codepoint <= 0x7E);
	}
	return codepoint == 0x85 || codepoint == 0xA0 || codepoint == 0x1680 ||
		(codepoint >= 0x2000 && codepoint <= 0x200A) || codepoint == 0x2028 ||
		codepoint == 0x2029 || codepoint == 0x202F || codepoint == 0x205F || codepoint == 0x3000;
}

function pushTruncated(
	shaped: ShapedText,
	from: int32,
	to: int32,
	lineIndex: int32,
	ref out: Vec<LaidGlyph>,
	room: float32,
	truncate: Truncate,
): void {
	const first: int32 = out.length as int32;
	pushLine(shaped, from, to, lineIndex, out);
	const full: float32 = lineWidthOf(out, first);
	if (full <= room || to <= from) { return; }
	const line: Vec<LaidGlyph> = new Array(0);
	for (let k = first; k < (out.length as int32); k++) { line.push(out[k]); }
	while ((out.length as int32) > first) { out.pop(); }
	const dots: float32 = ellipsisGlyph(shaped).advance;
	const count: int32 = line.length as int32;
	const content: float32 = room - dots;
	const headBudget: float32 = truncate == Truncate.Middle ? content * (2.0 / 3.0) : content;
	const tailBudget: float32 = truncate == Truncate.Middle ? content - headBudget : content;
	let head: int32 = 0;
	if (truncate != Truncate.Start) {
		while (head < count) {
			let next: int32 = head + 1;
			let right: float32 = line[head].x + line[head].advance;
			while (next < count && !line[next].clusterStart) {
				const markRight: float32 = line[next].x + line[next].advance;
				if (markRight > right) { right = markRight; }
				next = next + 1;
			}
			if (right > headBudget) { break; }
			head = next;
		}
	}
	if (truncate == Truncate.End) {
		while (head > 0 && trimsBeforeEllipsis(line[head - 1].codepoint)) { head = head - 1; }
	}
	let tail: int32 = count;
	if (truncate != Truncate.End) {
		const end: float32 = line[count - 1].x + line[count - 1].advance;
		for (let at: int32 = count - 1; at >= head; at--) {
			if (end - line[at].x > tailBudget) { break; }
			if (line[at].clusterStart) { tail = at; }
		}
	}
	for (let k = 0; k < head; k++) { out.push(line[k]); }
	const cut: int32 = head < count ? head : count - 1;
	const dotsX: float32 = head > 0 ? line[head - 1].x + line[head - 1].advance : 0.0;
	const run: int32 = head > 0 ? line[head - 1].run : line[tail < count ? tail : count - 1].run;
	out.push(elided(shaped, from + cut, dotsX, lineIndex, run));
	if (tail < count) {
		const shift: float32 = dotsX + dots - line[tail].x;
		for (let k = tail; k < count; k++) { out.push({ ...line[k], x: line[k].x + shift }); }
	}
}

export function wrapText(shaped: ShapedText, style: TextStyle, options: LineOptions): TextLayout {
	const primary: int32 = fontFace(style.font);
	const metrics = faceMetrics(primary, style.size);
	const lineHeight: float32 = metrics.ascent + metrics.descent + metrics.lineGap;
	const truncating: boolean = style.maxWidth > 0.0 && options.truncate != Truncate.None;
	const wrapping: boolean = style.maxWidth > 0.0 && !truncating;
	const count: int32 = shaped.glyphs.length as int32;
	if (wrapping && count > 0 && (shaped.breaks.length as int32) == 0) {
		shaped.breaks = lineBreaks(shaped.values);
	}
	const glyphs: Vec<LaidGlyph> = new Array(0);
	const lines: Vec<LineBox> = new Array(0);
	let width: float32 = 0.0;
	let top: float32 = 0.0;
	let start: int32 = 0;
	while (true) {
		let paragraphEnd: int32 = start;
		while (paragraphEnd < count && shaped.glyphs[paragraphEnd].codepoint != NEWLINE) {
			paragraphEnd = paragraphEnd + 1;
		}
		let lineStart: int32 = start;
		let continuation: boolean = false;
		while (true) {
			const indent: float32 = continuation ? options.hangingIndent : 0.0;
			const lineBreak: LineBreak = wrapping
				? breakAfter(shaped, lineStart, paragraphEnd, style.maxWidth - indent)
				: { end: paragraphEnd, next: paragraphEnd };
			const end: int32 = lineBreak.end;
			const lineIndex: int32 = lines.length as int32;
			const firstGlyph: int32 = glyphs.length as int32;
			if (truncating) {
				pushTruncated(
					shaped, lineStart, end, lineIndex, glyphs, style.maxWidth, options.truncate,
				);
			} else {
				pushLine(shaped, lineStart, end, lineIndex, glyphs);
			}
			let lineWidth: float32 = options.forceWidth > 0.0
				? forceCells(glyphs, firstGlyph, options.forceWidth)
				: lineWidthOf(glyphs, firstGlyph);
			for (let k = firstGlyph; k < (glyphs.length as int32); k++) {
				glyphs[k].x = glyphs[k].x + indent;
			}
			const lineGlyphs: Span<LaidGlyph> = glyphs[firstGlyph..(glyphs.length as int32)];
			const box: FaceMetrics = tallestFaces(lineGlyphs, primary, style);
			const height: float32 = box.ascent + box.descent + box.lineGap;
			const atEnd: boolean = lineStart >= count;
			const indexStart: int32 = atEnd ? shaped.units : shaped.glyphs[lineStart].index;
			const byteStart: int32 = atEnd ? shaped.bytes : shaped.glyphs[lineStart].byteStart;
			const indexEnd: int32 = end > lineStart ? unitsTo(shaped, end) : indexStart;
			const byteEnd: int32 = end > lineStart ? shaped.glyphs[end - 1].byteEnd : byteStart;
			lines.push({
				firstGlyph: firstGlyph,
				glyphCount: (glyphs.length as int32) - firstGlyph,
				x: indent,
				top: top,
				baseline: top + box.ascent,
				height: height,
				width: lineWidth,
				charStart: lineStart,
				charEnd: end,
				indexStart: indexStart,
				indexEnd: indexEnd,
				byteStart: byteStart,
				byteEnd: byteEnd,
			});
			if (indent + lineWidth > width) { width = indent + lineWidth; }
			top = top + height + style.lineSpacing;
			if (lineBreak.next >= paragraphEnd) { break; }
			lineStart = lineBreak.next;
			continuation = true;
		}
		if (paragraphEnd >= count) { break; }
		start = paragraphEnd + 1;
	}
	alignLines(glyphs, lines, style, width);
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

function unitsTo(shaped: ShapedText, end: int32): int32 {
	const last: LaidGlyph = shaped.glyphs[end - 1];
	return last.index + (last.codepoint >= 0x10000 ? 2 : 1);
}

export function layout(this typeof TextLayout, text: string, style: TextStyle): TextLayout {
	const plain: Vec<TextRun> = new Array(0);
	return layoutRuns(text, style, plain);
}

export function layoutRuns(text: string, style: TextStyle, runs: Span<TextRun>): TextLayout {
	const noBreaks: Vec<int32> = new Array(0);
	return wrapText(shapeText(text, style, runs, noBreaks), style, PLAIN_LINES);
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

function lineOfIndex(this l: TextLayout, index: int32): int32 {
	const last: int32 = (l.lines.length as int32) - 1;
	for (let i = 0; i < last; i++) {
		if (index <= l.lines[i].indexEnd || index < l.lines[i + 1].indexStart) { return i; }
	}
	return last;
}

// GPUI's x_for_index (line_layout.rs:61-129), over every line: the x of the caret before
// `index`, a UTF-16 unit; past a line's last glyph it is the line's end.
export function xForIndex(this l: TextLayout, index: int32): float32 {
	if ((l.lines.length as int32) == 0) { return 0.0; }
	const line: LineBox = l.lines[l.lineOfIndex(index)];
	const end: int32 = line.firstGlyph + line.glyphCount;
	for (let k = line.firstGlyph; k < end; k++) {
		if (l.glyphs[k].index >= index) { return l.glyphs[k].x; }
	}
	return l.clusterEnd(line);
}

function clusterEnd(this l: TextLayout, line: LineBox): float32 {
	if (line.glyphCount == 0) { return line.x; }
	let right: float32 = line.x;
	for (let k = line.firstGlyph + line.glyphCount - 1; k >= line.firstGlyph; k--) {
		const edge: float32 = l.glyphs[k].x + l.glyphs[k].advance;
		if (edge > right) { right = edge; }
		if (l.glyphs[k].clusterStart) { break; }
	}
	return right;
}

export function lineBoxAt(this l: TextLayout, index: int32): LineBox {
	return l.lines[l.lineOfIndex(index)];
}

// GPUI's closest_index_for_x on the line under `y`: the grapheme boundary nearest to `x`.
export function indexAt(this l: TextLayout, x: float32, y: float32): int32 {
	const count: int32 = l.lines.length as int32;
	if (count == 0) { return 0; }
	let li: int32 = 0;
	while (li + 1 < count && y >= l.lines[li + 1].top) { li = li + 1; }
	const line: LineBox = l.lines[li];
	const end: int32 = line.firstGlyph + line.glyphCount;
	for (let k = line.firstGlyph; k < end; k++) {
		if (!l.glyphs[k].clusterStart) { continue; }
		let right: float32 = l.glyphs[k].x + l.glyphs[k].advance;
		let next: int32 = k + 1;
		while (next < end && !l.glyphs[next].clusterStart) {
			right = l.glyphs[next].x + l.glyphs[next].advance;
			next = next + 1;
		}
		if (x < (l.glyphs[k].x + right) * 0.5) { return l.glyphs[k].index; }
	}
	return line.indexEnd;
}

// GPUI's ShapedLine::split_at (line.rs:193-380): one line cut in two at `index` without being
// shaped again; the right half starts at x 0.
export function splitAt(this l: TextLayout, index: int32): [TextLayout, TextLayout] {
	if ((l.lines.length as int32) != 1) {
		console.log(`void2d: splitAt cuts one line, and this layout has ${l.lines.length}`);
		unreachable;
	}
	const line: LineBox = l.lines[0];
	let cut: int32 = line.firstGlyph + line.glyphCount;
	for (let k = line.firstGlyph; k < line.firstGlyph + line.glyphCount; k++) {
		if (l.glyphs[k].index >= index) {
			cut = k;
			break;
		}
	}
	const left: Vec<LaidGlyph> = new Array(0);
	const right: Vec<LaidGlyph> = new Array(0);
	const origin: float32 = cut < line.firstGlyph + line.glyphCount ? l.glyphs[cut].x : 0.0;
	for (let k = line.firstGlyph; k < line.firstGlyph + line.glyphCount; k++) {
		if (k < cut) {
			left.push(l.glyphs[k]);
		} else {
			right.push({ ...l.glyphs[k], x: l.glyphs[k].x - origin });
		}
	}
	const leftWidth: float32 = lineWidthOf(left, 0);
	const rightWidth: float32 = lineWidthOf(right, 0);
	const whole: boolean = cut >= line.firstGlyph + line.glyphCount;
	const leftEnd: int32 = whole ? line.indexEnd : l.glyphs[cut].index;
	const leftByteEnd: int32 = whole ? line.byteEnd : l.glyphs[cut].byteStart;
	const leftLine: LineBox = {
		...line, firstGlyph: 0, glyphCount: left.length as int32, width: leftWidth,
		charEnd: line.charStart + (left.length as int32), indexEnd: leftEnd,
		byteEnd: leftByteEnd,
	};
	const rightLine: LineBox = {
		...line, firstGlyph: 0, glyphCount: right.length as int32, x: 0.0, width: rightWidth,
		charStart: line.charStart + (left.length as int32), indexStart: leftEnd,
		byteStart: leftByteEnd,
	};
	const leftLines: Vec<LineBox> = new Array(0);
	leftLines.push(leftLine);
	const rightLines: Vec<LineBox> = new Array(0);
	rightLines.push(rightLine);
	return [
		{ ...l, glyphs: left, lines: leftLines, width: leftWidth },
		{ ...l, glyphs: right, lines: rightLines, width: rightWidth },
	];
}
