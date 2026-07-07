// void2d text layout — fontstash-driven line layout, word wrap, glyph mesh expansion.
// Extracted from draw.ms; talks to batcher.h directly.

import { void2dTextBegin, void2dTextNext, void2dTextSyncAtlas, void2dTextWidth, void2dLineHeight, void2dTextSpacing, void2dSelectFont } from "./batcher.h";

function collectLine(line: string, size: float32, lh: float32, lineIdx: int32, align: float32, out: float32[]): void {
	const xoff: float32 = -void2dTextWidth(size, line) * align;
	const yoff: float32 = (lineIdx as float32) * lh;
	void2dTextBegin(xoff, yoff, size, line);
	let q: Ptr<float32> = void2dTextNext();
	while (q !== null) {
		out.push(q[0]); out.push(q[1]); out.push(q[2]); out.push(q[3]);
		out.push(q[4]); out.push(q[5]); out.push(q[6]); out.push(q[7]);
		q = void2dTextNext();
	}
}

function wrapCollect(para: string, size: float32, maxWidth: float32, lh: float32, startIdx: int32, align: float32, out: float32[]): int32 {
	const words: string[] = para.split(" ");
	const wc: int32 = words.length as int32;
	let cur: string = "";
	let hasCur: boolean = false;
	let idx: int32 = startIdx;
	let i: int32 = 0;
	while (i < wc) {
		const word = words[i];
		const candidate: string = hasCur ? cur + " " + word : word;
		if (hasCur && void2dTextWidth(size, candidate) > maxWidth) {
			collectLine(cur, size, lh, idx, align, out);
			idx = idx + 1;
			cur = word;
		} else {
			cur = candidate;
		}
		hasCur = true;
		i = i + 1;
	}
	if (hasCur) {
		collectLine(cur, size, lh, idx, align, out);
		idx = idx + 1;
	}
	return idx;
}

export function layoutText(size: float32, text: string, align: float32, letterSpacing: float32, lineSpacing: float32, maxWidth: float32, fontId: int32): float32[] {
	void2dSelectFont(fontId);
	const out: float32[] = [];
	void2dTextSpacing(letterSpacing);
	const lh: float32 = void2dLineHeight(size) * lineSpacing;
	const paras: string[] = text.split("\n");
	const pc: int32 = paras.length as int32;
	let li: int32 = 0;
	let pi: int32 = 0;
	while (pi < pc) {
		if (maxWidth > 0.0) {
			li = wrapCollect(paras[pi], size, maxWidth, lh, li, align, out);
		} else {
			collectLine(paras[pi], size, lh, li, align, out);
			li = li + 1;
		}
		pi = pi + 1;
	}
	void2dTextSpacing(0.0);
	void2dTextSyncAtlas();
	return out;
}

function glyphVert(out: float32[], x: float32, y: float32, u: float32, v: float32): void {
	const w: float32 = 1.0;
	out.push(x); out.push(y); out.push(u); out.push(v);
	out.push(w); out.push(w); out.push(w); out.push(w);
}

export function buildGlyphMesh(glyphs: float32[]): float32[] {
	const out: float32[] = [];
	const total: int32 = glyphs.length as int32;
	let i: int32 = 0;
	while (i + 8 <= total) {
		const x0: float32 = glyphs[i];     const y0: float32 = glyphs[i + 1];
		const s0: float32 = glyphs[i + 2]; const t0: float32 = glyphs[i + 3];
		const x1: float32 = glyphs[i + 4]; const y1: float32 = glyphs[i + 5];
		const s1: float32 = glyphs[i + 6]; const t1: float32 = glyphs[i + 7];
		glyphVert(out, x0, y0, s0, t0); glyphVert(out, x1, y0, s1, t0); glyphVert(out, x1, y1, s1, t1);
		glyphVert(out, x0, y0, s0, t0); glyphVert(out, x1, y1, s1, t1); glyphVert(out, x0, y1, s0, t1);
		i = i + 8;
	}
	return out;
}
