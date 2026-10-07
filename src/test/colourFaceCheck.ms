import { readFile } from "std/fs";
import {
	FaceError,
	ColourGlyph,
	loadFace,
	glyphIndex,
	glyphAdvance,
	glyphKern,
	glyphInkBox,
	faceMetrics,
	faceHeights,
	decorationMetrics,
	colourBuilt,
	hasColourTables,
	isColourOnly,
	colourTileBox,
	colourRasterize,
	colourSweep,
	colourLayerCount,
	colourLayerGlyph,
	colourLayerRgba,
	colourSweepRefused,
} from "../void2d/face";
import {
	GlyphAtlas,
	GlyphKey,
	PageKind,
	NO_GLYPH_PAGE_HANDLE,
} from "../void2d/glyphAtlas";
import { void2dGlyphPageTexelRgba } from "../void2d/glyph.h";
import { colourEmojiReason } from "../void2d/colourEmoji/colourEmoji";

const ORACLE_PATH: string = "tests/oracle/colour.json";
const PAGE_SIZE: int32 = 1024;
const FNV_OFFSET: uint64 = 0xCBF29CE484222325;
const FNV_PRIME: uint64 = 0x100000001B3;

function hex64(value: uint64): string {
	const digits: string = "0123456789abcdef";
	let out: string = "";
	for (let shift: int32 = 60; shift >= 0; shift = shift - 4) {
		out = out + digits[((value >> (shift as uint64)) & 15) as int32];
	}
	return out;
}

function tileHash(page: int32, x: int32, y: int32, width: int32, height: int32): string {
	let hash: uint64 = FNV_OFFSET;
	for (let row: int32 = 0; row < height; row++) {
		for (let col: int32 = 0; col < width; col++) {
			const texel: uint32 = void2dGlyphPageTexelRgba(page, x + col, y + row);
			for (let channel: int32 = 0; channel < 4; channel++) {
				const byte: uint64 = ((texel >> ((8 * channel) as uint32)) & 255) as uint64;
				hash = (hash ^ byte) * FNV_PRIME;
			}
		}
	}
	return hex64(hash);
}

test "the colour module is built and a CBDT-only face loads without an outline" {
	assert colourBuilt();
	const face = try loadFace("tests/fonts/NotoColorEmoji-subset.ttf") catch -1;
	assert face >= 0;
	assert isColourOnly(face);
	assert hasColourTables(face);
}

test "cmap, advance and vertical metrics of a colour-only face agree with fontTools" {
	const text = readFile(ORACLE_PATH);
	assert text.ok;
	const parsed = JSON.parseValue(text.value);
	assert parsed.ok;
	const fonts = parsed.value.getDynamicField("cbdt");
	for (let f: int32 = 0; f < (fonts.length() as int32); f++) {
		const row = fonts.at(f);
		const face = try loadFace(row.getDynamicField("path").asString()) catch -1;
		assert face >= 0;
		const em: float32 = row.getDynamicField("unitsPerEm").asNumber() as float32;
		const m = faceMetrics(face, em);
		assert m.ascent == row.getDynamicField("ascent").asNumber() as float32;
		assert m.descent == -(row.getDynamicField("descent").asNumber() as float32);
		const glyphs = row.getDynamicField("glyphs");
		for (let g: int32 = 0; g < (glyphs.length() as int32); g++) {
			const glyph = glyphs.at(g);
			const codepoint: int32 = glyph.getDynamicField("codepoint").asNumber() as int32;
			const id: int32 = glyphIndex(face, codepoint);
			assert id == glyph.getDynamicField("glyph").asNumber() as int32;
			const advance: float32 = glyph.getDynamicField("advance").asNumber() as float32;
			assert glyphAdvance(face, id, em) == advance;
		}
	}
}

test "every outline walk on a colour-only face answers empty instead of reading a missing glyf" {
	const face = try loadFace("tests/fonts/NotoColorEmoji-subset.ttf") catch -1;
	assert face >= 0;
	const id: int32 = glyphIndex(face, 0x1F600);
	assert id > 0;
	const ink = glyphInkBox(face, id, 32.0);
	assert ink[0] == 0.0 && ink[1] == 0.0 && ink[2] == 0.0 && ink[3] == 0.0;
	const heights = faceHeights(face);
	assert heights.lineHeight > 0.0;
	assert heights.capHeightEstimate > 0.0;
	const decoration = decorationMetrics(face, 32.0);
	assert decoration.underlineThickness > 0.0;
	assert glyphKern(face, id, id, 32.0) == 0.0;
	assert glyphAdvance(face, 60000, 32.0) == 0.0;
	assert glyphAdvance(face, -1, 32.0) == 0.0;
	assert glyphIndex(face, 0x10FFFF) == 0;
	assert glyphIndex(face, -1) == 0;
}

test "tile boxes and premultiplied area-average pixels agree with the oracle at every size" {
	const text = readFile(ORACLE_PATH);
	assert text.ok;
	const parsed = JSON.parseValue(text.value);
	assert parsed.ok;
	const fonts = parsed.value.getDynamicField("cbdt");
	let compared: int32 = 0;
	for (let f: int32 = 0; f < (fonts.length() as int32); f++) {
		const row = fonts.at(f);
		const face = try loadFace(row.getDynamicField("path").asString()) catch -1;
		assert face >= 0;
		const atlas = GlyphAtlas.create(PAGE_SIZE, 4);
		const glyphs = row.getDynamicField("glyphs");
		for (let g: int32 = 0; g < (glyphs.length() as int32); g++) {
			const glyph = glyphs.at(g);
			const id: int32 = glyph.getDynamicField("glyph").asNumber() as int32;
			const tiles = glyph.getDynamicField("tiles");
			for (let t: int32 = 0; t < (tiles.length() as int32); t++) {
				const want = tiles.at(t);
				const size: float32 = want.getDynamicField("size").asNumber() as float32;
				const box = colourTileBox(face, id, size);
				assert box.glyph == ColourGlyph.Present;
				assert box.left == want.getDynamicField("left").asNumber() as int32;
				assert box.top == want.getDynamicField("top").asNumber() as int32;
				assert box.right == want.getDynamicField("right").asNumber() as int32;
				assert box.bottom == want.getDynamicField("bottom").asNumber() as int32;
				assert box.ppem == want.getDynamicField("ppem").asNumber() as int32;
				const key: GlyphKey = {
					kind: PageKind.Rgba, face: face, glyph: id, sizePx: size, variant: 0,
				};
				const width: int32 = box.right - box.left;
				const height: int32 = box.bottom - box.top;
				const index = atlas.acquireBlank(key, width, height, box.left, box.top);
				assert index.ok;
				if (!index.ok) { return; }
				const tile = atlas.tile(index.value);
				const handle = atlas.pageHandle(tile.page);
				assert colourRasterize(face, id, size, handle, tile.x, tile.y, width, height) == 0;
				assert tileHash(handle as int32, tile.x, tile.y, width, height) ==
					want.getDynamicField("hash").asString();
				const samples = want.getDynamicField("samples");
				for (let s: int32 = 0; s < (samples.length() as int32); s++) {
					const sample = samples.at(s);
					const x: int32 = sample.at(0).asNumber() as int32;
					const y: int32 = sample.at(1).asNumber() as int32;
					const texel: uint32 = void2dGlyphPageTexelRgba(
						handle as int32, tile.x + x, tile.y + y);
					assert (texel as float64) == sample.at(2).asNumber();
				}
				compared = compared + 1;
			}
		}
	}
	assert compared == 6 * 8 + 2 * 6 + 3 * 8;
}

test "sbix tiles, dupe chains and refused graphic types agree with the oracle at every size" {
	const text = readFile(ORACLE_PATH);
	assert text.ok;
	const parsed = JSON.parseValue(text.value);
	assert parsed.ok;
	const fonts = parsed.value.getDynamicField("sbix");
	let compared: int32 = 0;
	let refused: int32 = 0;
	for (let f: int32 = 0; f < (fonts.length() as int32); f++) {
		const row = fonts.at(f);
		const face = try loadFace(row.getDynamicField("path").asString()) catch -1;
		assert face >= 0;
		assert hasColourTables(face);
		assert !isColourOnly(face);
		const atlas = GlyphAtlas.create(PAGE_SIZE, 4);
		const glyphs = row.getDynamicField("glyphs");
		for (let g: int32 = 0; g < (glyphs.length() as int32); g++) {
			const glyph = glyphs.at(g);
			const codepoint: int32 = glyph.getDynamicField("codepoint").asNumber() as int32;
			const id: int32 = glyphIndex(face, codepoint);
			assert id == glyph.getDynamicField("glyph").asNumber() as int32;
			const tiles = glyph.getDynamicField("tiles");
			for (let t: int32 = 0; t < (tiles.length() as int32); t++) {
				const want = tiles.at(t);
				const size: float32 = want.getDynamicField("size").asNumber() as float32;
				const status: string = want.getDynamicField("status").asString();
				const box = colourTileBox(face, id, size);
				if (status == "refused") {
					assert box.glyph == ColourGlyph.Refused;
					refused = refused + 1;
					continue;
				}
				assert status == "present";
				assert box.glyph == ColourGlyph.Present;
				assert box.ppem == want.getDynamicField("ppem").asNumber() as int32;
				assert box.left == want.getDynamicField("left").asNumber() as int32;
				assert box.top == want.getDynamicField("top").asNumber() as int32;
				assert box.right == want.getDynamicField("right").asNumber() as int32;
				assert box.bottom == want.getDynamicField("bottom").asNumber() as int32;
				const key: GlyphKey = {
					kind: PageKind.Rgba, face: face, glyph: id, sizePx: size, variant: 0,
				};
				const width: int32 = box.right - box.left;
				const height: int32 = box.bottom - box.top;
				const index = atlas.acquireBlank(key, width, height, box.left, box.top);
				assert index.ok;
				if (!index.ok) { return; }
				const tile = atlas.tile(index.value);
				const handle = atlas.pageHandle(tile.page);
				assert colourRasterize(face, id, size, handle, tile.x, tile.y, width, height) == 0;
				assert tileHash(handle as int32, tile.x, tile.y, width, height) ==
					want.getDynamicField("hash").asString();
				compared = compared + 1;
			}
		}
	}
	assert compared == 15;
	assert refused == 5;
}

test "an sbix face keeps its outlines and a dupe glyph resolves to its target" {
	const face = try loadFace("tests/fonts/sbixSynthetic.ttf") catch -1;
	assert face >= 0;
	const heart = colourTileBox(face, glyphIndex(face, 0x2665), 12.0);
	const target = colourTileBox(face, glyphIndex(face, 0x2764), 12.0);
	assert heart.glyph == ColourGlyph.Present;
	assert heart.left == target.left && heart.top == target.top;
	assert heart.right == target.right && heart.bottom == target.bottom;
	assert glyphInkBox(face, glyphIndex(face, 0x2764), 32.0)[2] > 0.0;
	assert colourTileBox(face, 0, 12.0).glyph == ColourGlyph.Absent;
}

test "COLR v0 layers, palette 0 and the composited tile agree with the oracle" {
	const text = readFile(ORACLE_PATH);
	assert text.ok;
	const parsed = JSON.parseValue(text.value);
	assert parsed.ok;
	const fonts = parsed.value.getDynamicField("colr");
	let compared: int32 = 0;
	for (let f: int32 = 0; f < (fonts.length() as int32); f++) {
		const row = fonts.at(f);
		const face = try loadFace(row.getDynamicField("path").asString()) catch -1;
		assert face >= 0;
		assert hasColourTables(face);
		assert !isColourOnly(face);
		const atlas = GlyphAtlas.create(PAGE_SIZE, 4);
		const glyphs = row.getDynamicField("glyphs");
		for (let g: int32 = 0; g < (glyphs.length() as int32); g++) {
			const glyph = glyphs.at(g);
			const codepoint: int32 = glyph.getDynamicField("codepoint").asNumber() as int32;
			const id: int32 = glyphIndex(face, codepoint);
			assert id == glyph.getDynamicField("glyph").asNumber() as int32;
			const layers = glyph.getDynamicField("layers");
			assert colourLayerCount(face, id) == (layers.length() as int32);
			for (let l: int32 = 0; l < (layers.length() as int32); l++) {
				const layer = layers.at(l);
				const layerGlyph: int32 = layer.getDynamicField("glyph").asNumber() as int32;
				assert colourLayerGlyph(face, id, l) == layerGlyph;
				const rgba = layer.getDynamicField("rgba");
				const packed: uint32 = (rgba.at(0).asNumber() as uint32) |
					((rgba.at(1).asNumber() as uint32) << 8) |
					((rgba.at(2).asNumber() as uint32) << 16) |
					((rgba.at(3).asNumber() as uint32) << 24);
				assert colourLayerRgba(face, id, l) == packed;
			}
			const tiles = glyph.getDynamicField("tiles");
			for (let t: int32 = 0; t < (tiles.length() as int32); t++) {
				const want = tiles.at(t);
				const size: float32 = want.getDynamicField("size").asNumber() as float32;
				const box = colourTileBox(face, id, size);
				assert box.glyph == ColourGlyph.Present;
				assert box.left == want.getDynamicField("left").asNumber() as int32;
				assert box.top == want.getDynamicField("top").asNumber() as int32;
				assert box.right == want.getDynamicField("right").asNumber() as int32;
				assert box.bottom == want.getDynamicField("bottom").asNumber() as int32;
				const key: GlyphKey = {
					kind: PageKind.Rgba, face: face, glyph: id, sizePx: size, variant: 0,
				};
				const width: int32 = box.right - box.left;
				const height: int32 = box.bottom - box.top;
				const index = atlas.acquireBlank(key, width, height, box.left, box.top);
				assert index.ok;
				if (!index.ok) { return; }
				const tile = atlas.tile(index.value);
				const handle = atlas.pageHandle(tile.page);
				assert colourRasterize(face, id, size, handle, tile.x, tile.y, width, height) == 0;
				assert tileHash(handle as int32, tile.x, tile.y, width, height) ==
					want.getDynamicField("hash").asString();
				compared = compared + 1;
			}
		}
	}
	assert compared == 3 + 2;
}

test "a COLR v1 paint graph is refused when the face loads and the outline face still draws text" {
	const face = try loadFace("tests/fonts/colrV1Only.ttf") catch -1;
	assert face >= 0;
	assert colourEmojiReason().includes("paint graph");
	assert !hasColourTables(face);
	assert !isColourOnly(face);
	assert glyphIndex(face, 0x1F600) != 0;
	assert colourTileBox(face, glyphIndex(face, 0x1F600), 16.0).glyph == ColourGlyph.Absent;
}

test "a COLR glyph with a foreground-colour layer is refused by name, not drawn" {
	const face = try loadFace("tests/fonts/colrForeground.ttf") catch -1;
	assert face >= 0;
	assert hasColourTables(face);
	const id: int32 = glyphIndex(face, 0x1F600);
	assert colourLayerCount(face, id) == -1;
	assert colourEmojiReason().includes("foreground colour");
	assert colourTileBox(face, id, 20.0).glyph == ColourGlyph.Refused;
	assert colourRasterize(face, id, 20.0, NO_GLYPH_PAGE_HANDLE, 0, 0, 12, 14) == 1;
}

test "an sbix dupe that points at itself is refused and its neighbours still draw" {
	const face = try loadFace("tests/fonts/sbixLoop.ttf") catch -1;
	assert face >= 0;
	assert colourTileBox(face, glyphIndex(face, 0x2665), 12.0).glyph == ColourGlyph.Refused;
	assert colourTileBox(face, glyphIndex(face, 0x2764), 12.0).glyph == ColourGlyph.Present;
}

test "a glyph with no bitmap is absent, not refused, and its tile is never drawn" {
	const face = try loadFace("tests/fonts/NotoColorEmoji-subset.ttf") catch -1;
	assert face >= 0;
	assert colourTileBox(face, 0, 16.0).glyph == ColourGlyph.Absent;
	assert colourTileBox(face, glyphIndex(face, 0x200D), 16.0).glyph == ColourGlyph.Absent;
	assert colourTileBox(face, 60000, 16.0).glyph == ColourGlyph.Absent;
	assert colourTileBox(face, glyphIndex(face, 0x1F600), 0.0).glyph == ColourGlyph.Absent;
	assert colourTileBox(face, glyphIndex(face, 0x1F600), -4.0).glyph == ColourGlyph.Absent;
}

test "strike selection takes the smallest ppem at or above the size, else the largest" {
	const face = try loadFace("tests/fonts/cbdtSynthetic.ttf") catch -1;
	assert face >= 0;
	const id: int32 = glyphIndex(face, 0x1F600);
	assert id > 0;
	const small = colourTileBox(face, id, 6.0);
	assert small.right - small.left == 6;
	const eight = colourTileBox(face, id, 8.0);
	assert eight.right - eight.left == 8;
	const twelve = colourTileBox(face, id, 12.0);
	assert twelve.right - twelve.left == 12;
	const sixteen = colourTileBox(face, id, 16.0);
	assert sixteen.right - sixteen.left == 16;
	const huge = colourTileBox(face, id, 40.0);
	assert huge.right - huge.left == 40;
}

test "a CBLC face whose every strike has a non-colour bit depth is refused by name when it loads" {
	const r = loadFace("tests/fonts/cbdtBroken.ttf");
	assert !r.ok;
	if (!r.ok) { assert r.error == FaceError.BadColourTable; }
}

test "a CBLC strike with a non-colour bit depth is skipped and the other strikes still draw" {
	const face = try loadFace("tests/fonts/cbdtMixedDepth.ttf") catch -1;
	assert face >= 0;
	assert hasColourTables(face);
	const id: int32 = glyphIndex(face, 0x1F600);
	const small = colourTileBox(face, id, 8.0);
	assert small.glyph == ColourGlyph.Present;
	assert small.ppem == 16;
	assert small.right - small.left == 8;
}

test "a colour font whose last Unicode cmap record is the variation-selector one still loads" {
	const face = try loadFace("tests/fonts/cbdtUvsLast.ttf") catch -1;
	assert face >= 0;
	assert hasColourTables(face);
	const id: int32 = glyphIndex(face, 0x1F600);
	assert id > 0;
	assert glyphIndex(face, 0x2764) > 0;
	assert colourTileBox(face, id, 16.0).glyph == ColourGlyph.Present;
}

test "CBLC index formats 1 to 3 and CBDT image formats 17 to 19 are each read from a face that uses them" {
	const face = try loadFace("tests/fonts/cbdtFormats.ttf") catch -1;
	assert face >= 0;
	const heart: int32 = glyphIndex(face, 0x2764);
	const thumb: int32 = glyphIndex(face, 0x1F44D);
	const index2 = colourTileBox(face, thumb, 8.0);
	assert index2.ppem == 8;
	assert index2.left == 1 && index2.top == -7;
	const index3 = colourTileBox(face, heart, 16.0);
	assert index3.ppem == 16;
	assert index3.right - index3.left == 12 && index3.bottom - index3.top == 16;
	assert index3.left == -1;
	const plain3 = colourTileBox(face, thumb, 24.0);
	assert plain3.ppem == 24 && plain3.right - plain3.left == 24;
	const index1 = colourTileBox(face, heart, 32.0);
	assert index1.ppem == 32;
	assert index1.right - index1.left == 32 && index1.bottom - index1.top == 26;
}

test "a tile aimed at the wrong place or with the wrong size is refused" {
	const face = try loadFace("tests/fonts/cbdtSynthetic.ttf") catch -1;
	assert face >= 0;
	const id: int32 = glyphIndex(face, 0x1F600);
	const atlas = GlyphAtlas.create(64, 2);
	const key: GlyphKey = { kind: PageKind.Rgba, face: face, glyph: id, sizePx: 16.0, variant: 0 };
	const index = atlas.acquireBlank(key, 16, 16, 0, -16);
	assert index.ok;
	if (!index.ok) { return; }
	const tile = atlas.tile(index.value);
	const handle = atlas.pageHandle(tile.page);
	assert colourRasterize(face, id, 16.0, handle, tile.x, tile.y, 15, 16) == 4;
	assert colourRasterize(face, id, 16.0, handle, 60, 0, 16, 16) == 3;
	assert colourRasterize(face, id, 16.0, handle, tile.x, tile.y, 16, 16) == 0;
	assert colourRasterize(face, 60000, 16.0, handle, tile.x, tile.y, 16, 16) == 4;
	assert colourRasterize(face, id, 16.0, NO_GLYPH_PAGE_HANDLE, 0, 0, 16, 16) == 1;
}

test "truncating a colour font and stamping 0xFFFFFFFF into it never crashes" {
	const synthetic = try loadFace("tests/fonts/cbdtSynthetic.ttf") catch -1;
	assert synthetic >= 0;
	assert colourSweep(synthetic, 4) > 600;
	assert colourSweepRefused() > 0;
	const noto = try loadFace("tests/fonts/NotoColorEmoji-subset.ttf") catch -1;
	assert noto >= 0;
	assert colourSweep(noto, 16) > 2000;
	assert colourSweepRefused() > 0;
	const colr = try loadFace("tests/fonts/colrSynthetic.ttf") catch -1;
	assert colr >= 0;
	assert colourSweep(colr, 4) > 300;
	const sbix = try loadFace("tests/fonts/sbixSynthetic.ttf") catch -1;
	assert sbix >= 0;
	assert colourSweep(sbix, 4) > 600;
	assert colourSweepRefused() > 0;
}
