import { decodePng, pngFailureReason } from "../../assets/png";

export const COLOUR_OK: int32 = 0;
export const COLOUR_NONE: int32 = 1;
export const COLOUR_BAD_TABLE: int32 = -1;
export const COLOUR_NO_MEMORY: int32 = -2;

export const COLOUR_ABSENT: int32 = 0;
export const COLOUR_PRESENT: int32 = 1;
export const COLOUR_REFUSED: int32 = -1;

export const COLOUR_MAX_LAYERS: int32 = 256;
export const COLOUR_MAX_TEXELS: int64 = 4096 * 4096;
export const COLOUR_MAX_SIZE_PX: float32 = 16384.0;

const MAX_TABLES: int32 = 256;
const MAX_STRIKES: int32 = 64;
const MAX_SIDE: int32 = 4096;
const REFUSED_SLOTS: int32 = 64;
const KIND_CBDT: int32 = 0;
const KIND_SBIX: int32 = 1;
const MAX_SBIX_DUPE: int32 = 8;
const MAX_REFUSED_TAGS: int32 = 8;
const MAX_REPORTED: int32 = 64;

struct Table {
	offset: int64;
	length: int64;
	found: boolean;
}

class Strike {
	kind: int32 = KIND_CBDT;
	arrayAt: int64 = 0;
	subtables: int64 = 0;
	ppemX: int32 = 0;
	ppemY: int32 = 0;
}

// A PNG inside the font file, located by its offset from the start of the file.
class Bitmap {
	pngAt: int64 = 0;
	pngLength: int64 = 0;
	width: int32 = 0;
	height: int32 = 0;
	bearingX: int32 = 0;
	bearingY: int32 = 0;
	ppem: int32 = 0;
}

export class ColourBox {
	width: int32 = 0;
	height: int32 = 0;
	bearingX: int32 = 0;
	bearingY: int32 = 0;
	ppem: int32 = 0;
}

export struct ColourLayer {
	glyph: int32;
	r: uint8;
	g: uint8;
	b: uint8;
	a: uint8;
}

export class ColourSfnt {
	head: int64 = 0;
	hhea: int64 = 0;
	hmtx: int64 = 0;
	hmtxLength: int64 = 0;
	numGlyphs: int32 = 0;
	outlines: boolean = false;
}

export class ColourFace {
	length: int64;
	cmap: Table = { offset: 0, length: 0, found: false };
	head: Table = { offset: 0, length: 0, found: false };
	hhea: Table = { offset: 0, length: 0, found: false };
	hmtx: Table = { offset: 0, length: 0, found: false };
	maxp: Table = { offset: 0, length: 0, found: false };
	glyf: Table = { offset: 0, length: 0, found: false };
	loca: Table = { offset: 0, length: 0, found: false };
	cff: Table = { offset: 0, length: 0, found: false };
	cblc: Table = { offset: 0, length: 0, found: false };
	cbdt: Table = { offset: 0, length: 0, found: false };
	sbix: Table = { offset: 0, length: 0, found: false };
	colr: Table = { offset: 0, length: 0, found: false };
	cpal: Table = { offset: 0, length: 0, found: false };
	numGlyphs: int32 = 0;
	index: int64 = 0;
	indexFormat: int32 = 0;
	strikes: Strike[] = [];
	refused: boolean[] = new Array<boolean>(REFUSED_SLOTS);
	refusedTags: int64[] = [];
	colrBases: int64 = 0;
	colrLayers: int64 = 0;
	paletteAt: int64 = 0;
	colrBaseCount: int64 = 0;
	colrLayerCount: int64 = 0;
	paletteEntries: int64 = 0;
	reported: int32[] = [];

	constructor(length: int64) {
		this.length = length;
		for (let i: int32 = 0; i < REFUSED_SLOTS; i++) { this.refused[i] = false; }
	}
}

export class ColourFaceOpened {
	status: int32 = COLOUR_NONE;
	face: ColourFace | null = null;
}

let lastReason: string = "";

export function colourFaceReason(): string {
	return lastReason;
}

function fail(text: string): int32 {
	lastReason = text;
	return COLOUR_BAD_TABLE;
}

// A bounds-checked window onto the font bytes; a read past the end sets `bad` and returns 0.
class Rd {
	readonly p: uint8[];
	base: int64;
	n: int64;
	bad: boolean = false;

	constructor(p: uint8[], base: int64, n: int64) {
		this.p = p;
		this.base = base;
		this.n = n;
	}
}

function rd8(s: Rd, at: int64): int32 {
	if (at < 0 || at >= s.n) { s.bad = true; return 0; }
	return s.p[(s.base + at) as int32] as int32;
}

function rd16(s: Rd, at: int64): int32 {
	if (at < 0 || at > s.n || s.n - at < 2) { s.bad = true; return 0; }
	const i = (s.base + at) as int32;
	return ((s.p[i] as int32) << 8) | (s.p[i + 1] as int32);
}

function rdI8(s: Rd, at: int64): int32 {
	const v = rd8(s, at);
	return v >= 128 ? v - 256 : v;
}

function rd32(s: Rd, at: int64): int64 {
	if (at < 0 || at > s.n || s.n - at < 4) { s.bad = true; return 0; }
	const i = (s.base + at) as int32;
	return (((s.p[i] as int64) << 24) | ((s.p[i + 1] as int64) << 16) |
		((s.p[i + 2] as int64) << 8) | (s.p[i + 3] as int64));
}

function tableSpan(bytes: uint8[], t: Table): Rd {
	return new Rd(bytes, t.offset, t.length);
}

function int32Of(v: int64): int32 {
	return (((v & 0xFFFFFFFF) ^ 0x80000000) - 0x80000000) as int32;
}

function refusedBefore(face: ColourFace, slot: int32): boolean {
	if (face.refused[slot]) { return true; }
	face.refused[slot] = true;
	return false;
}

function tagRefusedBefore(face: ColourFace, tag: int64): boolean {
	for (let i: int32 = 0; i < face.refusedTags.length; i++) {
		if (face.refusedTags[i] == tag) { return true; }
	}
	if (face.refusedTags.length < MAX_REFUSED_TAGS) { face.refusedTags.push(tag); }
	return false;
}

function reportedBefore(face: ColourFace, glyph: int32): boolean {
	for (let i: int32 = 0; i < face.reported.length; i++) {
		if (face.reported[i] == glyph) { return true; }
	}
	if (face.reported.length == MAX_REPORTED) { return true; }
	face.reported.push(glyph);
	if (face.reported.length == MAX_REPORTED) {
		console.error(`void2d: ${MAX_REPORTED} colour glyphs refused, the rest are refused silently`);
	}
	return false;
}

function findTable(face: ColourFace, bytes: uint8[], directory: int64, tables: int32, tag: string): Table {
	const none: Table = { offset: 0, length: 0, found: false };
	for (let i: int32 = 0; i < tables; i++) {
		const at = (directory + 16 * (i as int64)) as int32;
		let same = true;
		for (let k: int32 = 0; k < 4; k++) {
			if ((bytes[at + k] as int32) != tag.charCodeAt(k)) { same = false; }
		}
		if (!same) { continue; }
		const r = new Rd(bytes, 0, face.length);
		const offset = rd32(r, (at + 8) as int64);
		const length = rd32(r, (at + 12) as int64);
		if (offset > face.length || length > face.length - offset) { continue; }
		return { offset: offset, length: length, found: true };
	}
	return none;
}

function openCblc(face: ColourFace, bytes: uint8[]): int32 {
	const s = tableSpan(bytes, face.cblc);
	const major = rd16(s, 0);
	const sizes = rd32(s, 4);
	if (s.bad || (major != 2 && major != 3)) {
		return fail(`CBLC version ${major} is not 2 or 3`);
	}
	if (sizes == 0 || sizes > MAX_STRIKES) {
		return fail(`CBLC holds ${sizes} strikes, expected 1 to ${MAX_STRIKES}`);
	}
	if (face.cbdt.length < 4) { return fail("CBDT is shorter than its header"); }
	const d = tableSpan(bytes, face.cbdt);
	const dataMajor = rd16(d, 0);
	if (dataMajor != 2 && dataMajor != 3) {
		return fail(`CBDT version ${dataMajor} is not 2 or 3`);
	}
	for (let i: int64 = 0; i < sizes; i++) {
		const at = 8 + 48 * i;
		const st = new Strike();
		st.kind = KIND_CBDT;
		st.arrayAt = rd32(s, at);
		st.subtables = rd32(s, at + 8);
		st.ppemX = rd8(s, at + 44);
		st.ppemY = rd8(s, at + 45);
		const depth = rd8(s, at + 46);
		if (s.bad) { return fail(`CBLC is cut off inside strike record ${i}`); }
		if (st.ppemY == 0 || st.ppemX == 0) {
			return fail(`CBLC strike ${i} has ppem 0`);
		}
		if (depth != 32) {
			console.error(
				`void2d: CBLC strike ${i} (ppem ${st.ppemY}) has bit depth ${depth}, only 32 (colour) is read; the strike is skipped`,
			);
			continue;
		}
		if (st.arrayAt > s.n || st.subtables > (s.n - st.arrayAt) / 8) {
			return fail(`CBLC strike ${i} index subtable array lies outside the table`);
		}
		if (face.strikes.length == MAX_STRIKES) { return fail(`more than ${MAX_STRIKES} strikes`); }
		face.strikes.push(st);
	}
	if (face.strikes.length == 0) {
		return fail("CBLC holds no strike with a 32-bit colour depth");
	}
	return COLOUR_OK;
}

function openSbix(face: ColourFace, bytes: uint8[]): int32 {
	const s = tableSpan(bytes, face.sbix);
	const version = rd16(s, 0);
	const count = rd32(s, 4);
	if (s.bad || version != 1) { return fail(`sbix version ${version} is not 1`); }
	if (count == 0 || count > MAX_STRIKES) {
		return fail(`sbix holds ${count} strikes, expected 1 to ${MAX_STRIKES}`);
	}
	const offsets: int64 = 4 * ((face.numGlyphs as int64) + 1);
	for (let i: int64 = 0; i < count; i++) {
		const st = new Strike();
		st.kind = KIND_SBIX;
		st.arrayAt = rd32(s, 8 + 4 * i);
		st.subtables = 0;
		st.ppemX = rd16(s, st.arrayAt);
		st.ppemY = st.ppemX;
		if (s.bad) { return fail(`sbix is cut off inside strike ${i}`); }
		if (st.ppemY == 0) { return fail(`sbix strike ${i} has ppem 0`); }
		if (st.arrayAt + 4 + offsets > s.n) {
			return fail(`sbix strike ${i} glyph offsets run past the table`);
		}
		if (face.strikes.length == MAX_STRIKES) { return fail(`more than ${MAX_STRIKES} strikes`); }
		face.strikes.push(st);
	}
	return COLOUR_OK;
}

function chooseIndex(face: ColourFace, bytes: uint8[]): int32 {
	const c = tableSpan(bytes, face.cmap);
	const records = rd16(c, 2);
	let chosen: int64 = 0;
	for (let i: int32 = 0; i < records; i++) {
		const record: int64 = 4 + 8 * (i as int64);
		const platform = rd16(c, record);
		const encoding = rd16(c, record + 2);
		const offset = rd32(c, record + 4);
		if (c.bad) { return fail("cmap is cut off inside its encoding records"); }
		if (platform == 3 && (encoding == 1 || encoding == 10)) { chosen = offset; }
		if (platform == 0 && encoding != 5) { chosen = offset; }
	}
	if (chosen == 0) { return fail("cmap has no Unicode subtable"); }
	const format = rd16(c, chosen);
	if (c.bad) { return fail("the cmap subtable lies outside the table"); }
	if (format == 4) {
		const segments: int64 = rd16(c, chosen + 6) / 2;
		if (c.bad || chosen + 16 + 8 * segments > c.n) {
			return fail("cmap format 4 segments run past the table");
		}
	} else if (format == 12) {
		const groups = rd32(c, chosen + 12);
		if (c.bad || chosen + 16 + 12 * groups > c.n) {
			return fail("cmap format 12 groups run past the table");
		}
	} else {
		return fail(`cmap format ${format} is not read for a colour font (4 and 12 are)`);
	}
	face.index = chosen;
	face.indexFormat = format;
	return COLOUR_OK;
}

export function colourFaceGlyphIndex(face: ColourFace | null, bytes: uint8[], codepoint: int32): int32 {
	if (face == null || codepoint < 0 || face.index == 0) { return 0; }
	const c = tableSpan(bytes, face.cmap);
	const at = face.index;
	let glyph: int64 = 0;
	if (face.indexFormat == 4) {
		if (codepoint > 0xFFFF) { return 0; }
		const count: int64 = rd16(c, at + 6) / 2;
		const ends = at + 14;
		const starts = ends + 2 * count + 2;
		const deltas = starts + 2 * count;
		const ranges = deltas + 2 * count;
		let lo: int64 = 0;
		let hi: int64 = count;
		while (lo < hi) {
			const mid = (lo + hi) / 2;
			if (rd16(c, ends + 2 * mid) < codepoint) { lo = mid + 1; } else { hi = mid; }
		}
		if (lo == count) { return 0; }
		const start = rd16(c, starts + 2 * lo);
		if (codepoint < start) { return 0; }
		const delta = rd16(c, deltas + 2 * lo);
		const range = rd16(c, ranges + 2 * lo);
		if (range == 0) {
			glyph = (codepoint + delta) & 0xFFFF;
		} else {
			const slot = ranges + 2 * lo + range + 2 * (codepoint - start);
			const raw = rd16(c, slot);
			glyph = raw != 0 ? (raw + delta) & 0xFFFF : 0;
		}
	} else {
		const groups = rd32(c, at + 12);
		let lo: int64 = 0;
		let hi: int64 = groups;
		while (lo < hi) {
			const mid = lo + (hi - lo) / 2;
			const group = at + 16 + 12 * mid;
			if (rd32(c, group + 4) < codepoint) { lo = mid + 1; } else { hi = mid; }
		}
		if (lo == groups) { return 0; }
		const group = at + 16 + 12 * lo;
		const start = rd32(c, group);
		if (codepoint < start) { return 0; }
		glyph = (rd32(c, group + 8) + (codepoint - start)) & 0xFFFFFFFF;
	}
	if (c.bad || glyph >= face.numGlyphs) { return 0; }
	return glyph as int32;
}

function openColr(face: ColourFace, bytes: uint8[]): int32 {
	if (!face.cpal.found) { return fail("COLR is present without CPAL"); }
	const c = tableSpan(bytes, face.colr);
	const version = rd16(c, 0);
	const bases = rd16(c, 2);
	const basesAt = rd32(c, 4);
	const layersAt = rd32(c, 8);
	const layers = rd16(c, 12);
	if (c.bad) { return fail("COLR is shorter than its header"); }
	if (version > 1) { return fail(`COLR version ${version} is not 0 or 1`); }
	if (bases == 0) {
		return version == 1
			? fail("COLR v1 holds a paint graph and no v0 layers, which is all that is read")
			: fail("COLR holds no base glyph records");
	}
	if (basesAt + 6 * (bases as int64) > c.n || layersAt + 4 * (layers as int64) > c.n) {
		return fail("COLR records run past the table");
	}
	const p = tableSpan(bytes, face.cpal);
	const cpalVersion = rd16(p, 0);
	const entries = rd16(p, 2);
	const palettes = rd16(p, 4);
	const records = rd16(p, 6);
	const recordsAt = rd32(p, 8);
	const first = rd16(p, 12);
	if (p.bad) { return fail("CPAL is shorter than its header"); }
	if (cpalVersion > 1) { return fail(`CPAL version ${cpalVersion} is not 0 or 1`); }
	if (palettes == 0 || entries == 0) { return fail("CPAL holds no palette"); }
	if (first + entries > records || recordsAt + 4 * (records as int64) > p.n) {
		return fail("CPAL palette 0 runs past its colour records");
	}
	face.colrBases = basesAt;
	face.colrBaseCount = bases;
	face.colrLayers = layersAt;
	face.colrLayerCount = layers;
	face.paletteAt = recordsAt + 4 * (first as int64);
	face.paletteEntries = entries;
	return COLOUR_OK;
}

export function colourFaceHasLayers(face: ColourFace): boolean {
	return face.colr.found;
}

function layersOf(face: ColourFace, bytes: uint8[], glyph: int32, out: ColourLayer[], capacity: int32): int32 {
	lastReason = "";
	if (!face.colr.found || glyph < 0 || glyph >= 0x10000) { return 0; }
	const c = tableSpan(bytes, face.colr);
	let lo: int64 = 0;
	let hi: int64 = face.colrBaseCount;
	while (lo < hi) {
		const mid = (lo + hi) / 2;
		if (rd16(c, face.colrBases + 6 * mid) < glyph) { lo = mid + 1; } else { hi = mid; }
	}
	if (lo == face.colrBaseCount) { return 0; }
	const record = face.colrBases + 6 * lo;
	if (rd16(c, record) != glyph) { return 0; }
	const first = rd16(c, record + 2);
	const count = rd16(c, record + 4);
	if (c.bad) { return fail("COLR is cut off inside its base glyph records"); }
	if (count == 0) { return 0; }
	if (count > COLOUR_MAX_LAYERS || count > capacity) {
		return fail(`COLR glyph ${glyph} has ${count} layers, at most ${COLOUR_MAX_LAYERS} are read`);
	}
	if (first + count > face.colrLayerCount) {
		return fail(`COLR glyph ${glyph} layers run past the layer records`);
	}
	const p = tableSpan(bytes, face.cpal);
	for (let i: int32 = 0; i < count; i++) {
		const layer = face.colrLayers + 4 * ((first as int64) + (i as int64));
		const layerGlyph = rd16(c, layer);
		const index = rd16(c, layer + 2);
		if (c.bad) { return fail("COLR is cut off inside its layer records"); }
		if (layerGlyph >= face.numGlyphs) {
			return fail(`COLR glyph ${glyph} layer ${i} names glyph ${layerGlyph} of ${face.numGlyphs}`);
		}
		if (index == 0xFFFF) {
			return fail(
				`COLR glyph ${glyph} layer ${i} uses the foreground colour (palette index 0xFFFF), which a colour tile cannot hold`,
			);
		}
		if (index >= face.paletteEntries) {
			return fail(`COLR glyph ${glyph} layer ${i} uses palette index ${index} of ${face.paletteEntries}`);
		}
		const at = face.paletteAt + 4 * (index as int64);
		const b = rd8(p, at);
		const g = rd8(p, at + 1);
		const r = rd8(p, at + 2);
		const a = rd8(p, at + 3);
		out[i] = { glyph: layerGlyph, r: r as uint8, g: g as uint8, b: b as uint8, a: a as uint8 };
		if (p.bad) { return fail("CPAL is cut off inside palette 0"); }
	}
	return count;
}

export function colourGlyphLayers(face: ColourFace, bytes: uint8[], glyph: int32, out: ColourLayer[], capacity: int32): int32 {
	const count = layersOf(face, bytes, glyph, out, capacity);
	if (count < 0 && !reportedBefore(face, glyph)) {
		console.error(`void2d: colour glyph ${glyph} refused: ${lastReason}`);
	}
	return count;
}

export function colourCompose(
	dst: uint32[], stride: int32, dw: int32, dh: int32,
	coverage: uint8[], coverageStride: int32, ox: int32, oy: int32,
	cw: int32, ch: int32, colour: ColourLayer,
): void {
	for (let y: int32 = 0; y < ch; y++) {
		for (let x: int32 = 0; x < cw; x++) {
			const tx = ox + x;
			const ty = oy + y;
			if (tx < 0 || ty < 0 || tx >= dw || ty >= dh) { continue; }
			const cov: uint32 = coverage[y * coverageStride + x] as uint32;
			if (cov == 0) { continue; }
			const sa: uint32 = (cov * (colour.a as uint32) + 127) / 255;
			const sr: uint32 = ((colour.r as uint32) * sa + 127) / 255;
			const sg: uint32 = ((colour.g as uint32) * sa + 127) / 255;
			const sb: uint32 = ((colour.b as uint32) * sa + 127) / 255;
			const at = ty * stride + tx;
			const old: uint32 = dst[at];
			const inv: uint32 = 255 - sa;
			const r: uint32 = sr + ((old & 255) * inv + 127) / 255;
			const g: uint32 = sg + (((old >> 8) & 255) * inv + 127) / 255;
			const b: uint32 = sb + (((old >> 16) & 255) * inv + 127) / 255;
			const a: uint32 = sa + (((old >> 24) & 255) * inv + 127) / 255;
			dst[at] = r | (g << 8) | (b << 16) | (a << 24);
		}
	}
}

export function colourFaceOpen(bytes: uint8[], fontStart: int64): ColourFaceOpened {
	const result = new ColourFaceOpened();
	lastReason = "";
	const length = bytes.length as int64;
	if (fontStart > length || length - fontStart < 12) {
		result.status = fail("the file is shorter than an sfnt header");
		return result;
	}
	const start = fontStart as int32;
	const tables = ((bytes[start + 4] as int32) << 8) | (bytes[start + 5] as int32);
	if (tables == 0 || tables > MAX_TABLES) {
		result.status = fail(`the table directory counts ${tables} tables`);
		return result;
	}
	if (length - fontStart - 12 < 16 * (tables as int64)) {
		result.status = fail("the table directory runs past the end of the file");
		return result;
	}
	const face = new ColourFace(length);
	const dir = fontStart + 12;
	face.cmap = findTable(face, bytes, dir, tables, "cmap");
	face.head = findTable(face, bytes, dir, tables, "head");
	face.hhea = findTable(face, bytes, dir, tables, "hhea");
	face.hmtx = findTable(face, bytes, dir, tables, "hmtx");
	face.maxp = findTable(face, bytes, dir, tables, "maxp");
	face.glyf = findTable(face, bytes, dir, tables, "glyf");
	face.loca = findTable(face, bytes, dir, tables, "loca");
	face.cff = findTable(face, bytes, dir, tables, "CFF ");
	face.cblc = findTable(face, bytes, dir, tables, "CBLC");
	face.cbdt = findTable(face, bytes, dir, tables, "CBDT");
	face.sbix = findTable(face, bytes, dir, tables, "sbix");
	face.colr = findTable(face, bytes, dir, tables, "COLR");
	face.cpal = findTable(face, bytes, dir, tables, "CPAL");
	let status = COLOUR_NONE;
	if (face.cblc.found != face.cbdt.found) {
		status = fail(
			`${face.cblc.found ? "CBLC" : "CBDT"} is present without ${face.cblc.found ? "CBDT" : "CBLC"}`,
		);
	} else if (face.cblc.found || face.sbix.found || face.colr.found) {
		status = COLOUR_OK;
	}
	if (status == COLOUR_OK) {
		const m = tableSpan(bytes, face.maxp);
		face.numGlyphs = rd16(m, 4);
		if (!face.maxp.found || m.bad) {
			status = fail("a colour font needs a maxp with a glyph count");
		} else if (!face.cmap.found) {
			status = fail("a colour font without cmap");
		}
	}
	if (status == COLOUR_OK && face.cblc.found) { status = openCblc(face, bytes); }
	if (status == COLOUR_OK && face.sbix.found) { status = openSbix(face, bytes); }
	if (status == COLOUR_OK && face.colr.found) { status = openColr(face, bytes); }
	if (status == COLOUR_OK) { status = chooseIndex(face, bytes); }
	result.status = status;
	if (status == COLOUR_OK) { result.face = face; }
	return result;
}

export function colourFaceSfnt(face: ColourFace, bytes: uint8[], out: ColourSfnt): int32 {
	out.head = 0;
	out.hhea = 0;
	out.hmtx = 0;
	out.hmtxLength = 0;
	out.numGlyphs = 0;
	out.outlines = false;
	if (!face.head.found || !face.hhea.found || !face.hmtx.found) {
		return fail("a colour font needs head, hhea and hmtx");
	}
	if (face.head.length < 54) { return fail("head is shorter than 54 bytes"); }
	if (face.hhea.length < 36) { return fail("hhea is shorter than 36 bytes"); }
	const h = tableSpan(bytes, face.hhea);
	const longMetrics = rd16(h, 34);
	let need: int64 = 4 * (longMetrics as int64);
	if (longMetrics < face.numGlyphs) {
		need += 2 * ((face.numGlyphs as int64) - (longMetrics as int64));
	}
	if (longMetrics == 0 || face.hmtx.length < need) {
		return fail("hmtx holds fewer metrics than hhea and maxp promise");
	}
	const head = tableSpan(bytes, face.head);
	if (rd32(head, 12) != 0x5F0F3CF5) { return fail("head has a bad magic number"); }
	if (rd16(head, 18) == 0) { return fail("head has unitsPerEm 0"); }
	out.head = face.head.offset;
	out.hhea = face.hhea.offset;
	out.hmtx = face.hmtx.offset;
	out.hmtxLength = face.hmtx.length;
	out.numGlyphs = face.numGlyphs;
	out.outlines = face.glyf.found || face.cff.found;
	return COLOUR_OK;
}

const PNG_SIGNATURE: uint8[] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
const IHDR: uint8[] = [0x49, 0x48, 0x44, 0x52];

class PngSize {
	width: int32 = 0;
	height: int32 = 0;
}

function pngInfo(s: Rd, at: int64, length: int64, size: PngSize): boolean {
	if (length < 24 || at < 0 || at > s.n || s.n - at < length) { return false; }
	const i = (s.base + at) as int32;
	for (let k: int32 = 0; k < 8; k++) {
		if (s.p[i + k] != PNG_SIGNATURE[k]) { return false; }
	}
	for (let k: int32 = 0; k < 4; k++) {
		if (s.p[i + 12 + k] != IHDR[k]) { return false; }
	}
	size.width = int32Of(rd32(s, at + 16));
	size.height = int32Of(rd32(s, at + 20));
	return true;
}

function findCbdt(face: ColourFace, bytes: uint8[], strike: Strike, glyph: int32, out: Bitmap): int32 {
	const index = tableSpan(bytes, face.cblc);
	const data = tableSpan(bytes, face.cbdt);
	for (let i: int64 = 0; i < strike.subtables; i++) {
		const entry = strike.arrayAt + 8 * i;
		const first = rd16(index, entry);
		const last = rd16(index, entry + 2);
		const additional = rd32(index, entry + 4);
		if (index.bad) { return fail("CBLC is cut off inside an index subtable array"); }
		if (glyph < first || glyph > last) { continue; }
		const sub = strike.arrayAt + additional;
		const indexFormat = rd16(index, sub);
		const imageFormat = rd16(index, sub + 2);
		const imageBase = rd32(index, sub + 4);
		if (index.bad) { return fail("CBLC is cut off inside an index subtable header"); }
		const slot: int64 = (glyph as int64) - (first as int64);
		let start: int64 = 0;
		let size: int64 = 0;
		let hasMetrics = false;
		let bigWidth: int32 = 0;
		let bigHeight: int32 = 0;
		let bigBx: int32 = 0;
		let bigBy: int32 = 0;
		if (indexFormat == 1 || indexFormat == 3) {
			const width: int64 = indexFormat == 1 ? 4 : 2;
			const cells: int64 = (last as int64) - (first as int64) + 2;
			if (sub + 8 > index.n || cells > (index.n - sub - 8) / width) {
				return fail(`CBLC index format ${indexFormat} offsets run past the table`);
			}
			const at = sub + 8 + width * slot;
			const a = indexFormat == 1 ? rd32(index, at) : (rd16(index, at) as int64);
			const b = indexFormat == 1 ? rd32(index, at + width) : (rd16(index, at + width) as int64);
			if (b < a) { return fail(`CBLC glyph ${glyph} has a negative image length`); }
			start = imageBase + a;
			size = b - a;
		} else if (indexFormat == 2) {
			const each = rd32(index, sub + 8);
			bigHeight = rd8(index, sub + 12);
			bigWidth = rd8(index, sub + 13);
			bigBx = rdI8(index, sub + 14);
			bigBy = rdI8(index, sub + 15);
			hasMetrics = true;
			if (index.bad) { return fail("CBLC index format 2 is cut off"); }
			start = imageBase + each * slot;
			size = each;
		} else {
			if (!refusedBefore(face, indexFormat & 31)) {
				console.error(`void2d: CBLC index format ${indexFormat} is not read (1, 2 and 3 are)`);
			}
			return COLOUR_REFUSED;
		}
		if (size == 0) { return COLOUR_ABSENT; }
		if (imageFormat != 17 && imageFormat != 18 && imageFormat != 19) {
			if (!refusedBefore(face, 32 + (imageFormat & 31))) {
				console.error(
					`void2d: CBDT image format ${imageFormat} is not a PNG format (17, 18 and 19 are)`,
				);
			}
			return COLOUR_REFUSED;
		}
		if (start > data.n || size > data.n - start) {
			return fail(`CBDT glyph ${glyph} image lies outside the table`);
		}
		const header: int64 = imageFormat == 17 ? 5 : imageFormat == 18 ? 8 : 0;
		let width = bigWidth;
		let height = bigHeight;
		let bx = bigBx;
		let by = bigBy;
		if (imageFormat == 17 || imageFormat == 18) {
			height = rd8(data, start);
			width = rd8(data, start + 1);
			bx = rdI8(data, start + 2);
			by = rdI8(data, start + 3);
		} else if (!hasMetrics) {
			return fail("CBDT image format 19 needs the shared metrics of index format 2");
		}
		const pngLength = rd32(data, start + header);
		if (data.bad || size < header + 4 || pngLength > size - header - 4) {
			return fail(`CBDT glyph ${glyph} image is cut off`);
		}
		const png = new PngSize();
		const pngAt = start + header + 4;
		if (!pngInfo(data, pngAt, pngLength, png)) {
			return fail(`CBDT glyph ${glyph} is not a PNG`);
		}
		if (png.width != width || png.height != height || width <= 0 || height <= 0) {
			return fail(
				`CBDT glyph ${glyph} metrics say ${width}x${height} but its PNG is ${png.width}x${png.height}`,
			);
		}
		out.pngAt = face.cbdt.offset + pngAt;
		out.pngLength = pngLength;
		out.width = width;
		out.height = height;
		out.bearingX = bx;
		out.bearingY = by;
		out.ppem = strike.ppemY;
		return COLOUR_PRESENT;
	}
	return COLOUR_ABSENT;
}

function tagName(tag: int64): string {
	let name = "";
	for (let i: int32 = 0; i < 4; i++) {
		const c = ((tag >> ((24 - 8 * i) as int64)) & 255) as int32;
		name += String.fromCharCode(c >= 32 && c < 127 ? c : 63);
	}
	return name;
}

function findSbix(face: ColourFace, bytes: uint8[], strike: Strike, glyph: int32, depth: int32, out: Bitmap): int32 {
	const s = tableSpan(bytes, face.sbix);
	if (glyph < 0 || glyph >= face.numGlyphs) { return COLOUR_ABSENT; }
	const base = strike.arrayAt;
	const from = rd32(s, base + 4 + 4 * (glyph as int64));
	const to = rd32(s, base + 4 + 4 * ((glyph as int64) + 1));
	if (s.bad) { return fail("sbix is cut off inside the glyph offsets"); }
	if (to < from) { return fail(`sbix glyph ${glyph} has a negative data length`); }
	if (to == from || to - from == 8) { return COLOUR_ABSENT; }
	if (to - from < 8 || base + to > s.n) {
		return fail(`sbix glyph ${glyph} data lies outside the table`);
	}
	const at = base + from;
	const rawX = rd16(s, at);
	const rawY = rd16(s, at + 2);
	const originX = rawX >= 32768 ? rawX - 65536 : rawX;
	const originY = rawY >= 32768 ? rawY - 65536 : rawY;
	const tag = rd32(s, at + 4);
	if (tag == 0x64757065) {
		if (to - from < 10) { return fail(`sbix glyph ${glyph} is a dupe without a target`); }
		if (depth >= MAX_SBIX_DUPE) {
			return fail(`sbix glyph ${glyph} starts a dupe chain deeper than ${MAX_SBIX_DUPE}`);
		}
		return findSbix(face, bytes, strike, rd16(s, at + 8), depth + 1, out);
	}
	if (tag != 0x706E6720) {
		if (!tagRefusedBefore(face, tag)) {
			console.error(`void2d: sbix graphic type '${tagName(tag)}' is not read ('png ' and 'dupe' are)`);
		}
		return COLOUR_REFUSED;
	}
	const png = new PngSize();
	if (!pngInfo(s, at + 8, to - from - 8, png)) {
		return fail(`sbix glyph ${glyph} is not a PNG`);
	}
	if (png.width <= 0 || png.height <= 0 || png.width > MAX_SIDE || png.height > MAX_SIDE) {
		return fail(`sbix glyph ${glyph} is ${png.width}x${png.height}, expected 1 to ${MAX_SIDE} a side`);
	}
	out.pngAt = face.sbix.offset + at + 8;
	out.pngLength = to - from - 8;
	out.width = png.width;
	out.height = png.height;
	out.bearingX = originX;
	out.bearingY = originY + png.height;
	out.ppem = strike.ppemY;
	return COLOUR_PRESENT;
}

function findBitmap(face: ColourFace, bytes: uint8[], strike: Strike, glyph: int32, out: Bitmap): int32 {
	lastReason = "";
	if (strike.kind == KIND_SBIX) { return findSbix(face, bytes, strike, glyph, 0, out); }
	return findCbdt(face, bytes, strike, glyph, out);
}

class Choice {
	status: int32 = COLOUR_ABSENT;
	bitmap: Bitmap = new Bitmap();
}

// The smallest strike whose ppem reaches sizePx, else the largest strike that has the glyph.
function chooseStrike(face: ColourFace, bytes: uint8[], glyph: int32, sizePx: float32): Choice {
	const choice = new Choice();
	let hasBest = false;
	let bestPpem: int32 = 0;
	let refusal = COLOUR_ABSENT;
	for (let i: int32 = 0; i < face.strikes.length; i++) {
		const st = face.strikes[i];
		const found = new Bitmap();
		const code = findBitmap(face, bytes, st, glyph, found);
		if (code == COLOUR_PRESENT) {
			const bigger = (st.ppemY as float32) >= sizePx;
			const bestBigger = hasBest && (bestPpem as float32) >= sizePx;
			const better = !hasBest
				|| (bigger && (!bestBigger || st.ppemY < bestPpem))
				|| (!bigger && !bestBigger && st.ppemY > bestPpem);
			if (better) {
				hasBest = true;
				bestPpem = st.ppemY;
				choice.bitmap = found;
			}
		} else if (code != COLOUR_ABSENT) {
			refusal = code;
		}
	}
	choice.status = hasBest ? COLOUR_PRESENT : refusal;
	return choice;
}

function scaled(value: int32, sizePx: float32, ppem: int32): int32 {
	return Math.floor((value as float64) * (sizePx as float64) / (ppem as float64) + 0.5) as int32;
}

function boxOf(b: Bitmap, sizePx: float32, box: ColourBox): void {
	const w = scaled(b.width, sizePx, b.ppem);
	const h = scaled(b.height, sizePx, b.ppem);
	box.width = w < 1 ? 1 : w;
	box.height = h < 1 ? 1 : h;
	box.bearingX = scaled(b.bearingX, sizePx, b.ppem);
	box.bearingY = scaled(b.bearingY, sizePx, b.ppem);
	box.ppem = b.ppem;
}

// C's %g for the two values a size message prints: whole numbers print without a point.
function gText(v: float64): string {
	return v == Math.floor(v) && Math.abs(v) < 1e15 ? `${v as int64}` : `${v}`;
}

function fixed1(v: float32): string {
	const tenths = Math.floor((v as float64) * 10 + 0.5) as int64;
	return `${tenths / 10}.${tenths % 10}`;
}

export function colourGlyphBox(face: ColourFace, bytes: uint8[], glyph: int32, sizePx: float32, box: ColourBox): int32 {
	box.width = 0;
	box.height = 0;
	box.bearingX = 0;
	box.bearingY = 0;
	box.ppem = 0;
	if (glyph <= 0 || glyph >= 0x10000 || !(sizePx > 0.0)) { return COLOUR_ABSENT; }
	lastReason = "";
	let status = COLOUR_ABSENT;
	let bitmap = new Bitmap();
	if (!(sizePx <= COLOUR_MAX_SIZE_PX)) {
		fail(`a size of ${gText(sizePx as float64)} px is over the ${gText(COLOUR_MAX_SIZE_PX as float64)} px limit`);
		status = COLOUR_REFUSED;
	} else {
		const choice = chooseStrike(face, bytes, glyph, sizePx);
		status = choice.status;
		bitmap = choice.bitmap;
	}
	if (status == COLOUR_PRESENT) {
		boxOf(bitmap, sizePx, box);
		if ((box.width as int64) * (box.height as int64) > COLOUR_MAX_TEXELS) {
			fail(
				`colour glyph ${glyph} is ${box.width}x${box.height} at ${fixed1(sizePx)} px, over the ${COLOUR_MAX_TEXELS} texel limit`,
			);
			box.width = 0;
			box.height = 0;
			box.bearingX = 0;
			box.bearingY = 0;
			box.ppem = 0;
			status = COLOUR_REFUSED;
		}
	}
	if (status != COLOUR_PRESENT && status != COLOUR_ABSENT) {
		if (lastReason != "" && !reportedBefore(face, glyph)) {
			console.error(`void2d: colour glyph ${glyph} refused: ${lastReason}`);
		}
		return COLOUR_REFUSED;
	}
	return status;
}

function pngReason(): string {
	const reason = pngFailureReason();
	if (reason == null) { return "the decoded size changed"; }
	let text = "";
	for (let i: int32 = 0; i < reason.length && i < 63; i++) {
		const c = reason.charCodeAt(i);
		text += String.fromCharCode(c >= 32 && c < 127 ? c : 63);
	}
	return text;
}

function premultiplied(c: uint32, a: uint32): uint32 {
	return (c * a + 127) / 255;
}

function areaAverage(
	src: uint32[], sw: int32, sh: int32, dst: uint32[], stride: int32, dw: int32, dh: int32,
): void {
	const total: int64 = (sw as int64) * (sh as int64);
	for (let oy: int32 = 0; oy < dh; oy++) {
		const y0: int64 = (oy as int64) * sh;
		const y1: int64 = y0 + sh;
		const iy0 = (y0 / dh) as int32;
		const iy1 = ((y1 - 1) / dh) as int32;
		for (let ox: int32 = 0; ox < dw; ox++) {
			const x0: int64 = (ox as int64) * sw;
			const x1: int64 = x0 + sw;
			const ix0 = (x0 / dw) as int32;
			const ix1 = ((x1 - 1) / dw) as int32;
			let s0: int64 = 0;
			let s1: int64 = 0;
			let s2: int64 = 0;
			let s3: int64 = 0;
			for (let iy: int32 = iy0; iy <= iy1; iy++) {
				const lowY: int64 = (iy as int64) * dh;
				const highY: int64 = ((iy as int64) + 1) * dh;
				const ya = lowY > y0 ? lowY : y0;
				const yb = highY < y1 ? highY : y1;
				for (let ix: int32 = ix0; ix <= ix1; ix++) {
					const lowX: int64 = (ix as int64) * dw;
					const highX: int64 = ((ix as int64) + 1) * dw;
					const xa = lowX > x0 ? lowX : x0;
					const xb = highX < x1 ? highX : x1;
					const weight = (xb - xa) * (yb - ya);
					const texel: uint32 = src[iy * sw + ix];
					s0 += weight * ((texel & 255) as int64);
					s1 += weight * (((texel >> 8) & 255) as int64);
					s2 += weight * (((texel >> 16) & 255) as int64);
					s3 += weight * (((texel >> 24) & 255) as int64);
				}
			}
			const half = total / 2;
			const r = ((s0 + half) / total) as uint32;
			const g = ((s1 + half) / total) as uint32;
			const b = ((s2 + half) / total) as uint32;
			const a = ((s3 + half) / total) as uint32;
			dst[oy * stride + ox] = r | (g << 8) | (b << 16) | (a << 24);
		}
	}
}

export function colourGlyphRender(
	face: ColourFace, bytes: uint8[], glyph: int32, sizePx: float32, dst: uint32[], strideTexels: int32,
	width: int32, height: int32,
): int32 {
	const box = new ColourBox();
	let status = colourGlyphBox(face, bytes, glyph, sizePx, box);
	if (status != COLOUR_PRESENT) { return status; }
	if (box.width != width || box.height != height || strideTexels < width) {
		console.error(
			`void2d: colour tile ${width}x${height} does not match the glyph's ${box.width}x${box.height} box`,
		);
		return COLOUR_REFUSED;
	}
	const choice = chooseStrike(face, bytes, glyph, sizePx);
	if (choice.status != COLOUR_PRESENT) { return COLOUR_REFUSED; }
	const bitmap = choice.bitmap;
	const from = bitmap.pngAt as int32;
	const decoded = decodePng(bytes[from..(from + (bitmap.pngLength as int32))], 4, MAX_SIDE);
	if (!decoded.ok || decoded.value.width != bitmap.width || decoded.value.height != bitmap.height) {
		console.error(`void2d: colour glyph ${glyph}: the PNG does not decode: ${pngReason()}`);
		return !decoded.ok && decoded.error == "outofmem" ? COLOUR_NO_MEMORY : COLOUR_REFUSED;
	}
	const w = decoded.value.width;
	const h = decoded.value.height;
	const pixels = decoded.value.pixels;
	const source: uint32[] = new Array<uint32>(w * h);
	for (let i: int32 = 0; i < w * h; i++) {
		const a: uint32 = pixels[4 * i + 3] as uint32;
		source[i] = premultiplied(pixels[4 * i] as uint32, a) |
			(premultiplied(pixels[4 * i + 1] as uint32, a) << 8) |
			(premultiplied(pixels[4 * i + 2] as uint32, a) << 16) | (a << 24);
	}
	areaAverage(source, w, h, dst, strideTexels, width, height);
	return COLOUR_PRESENT;
}
