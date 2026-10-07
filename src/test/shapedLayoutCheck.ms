import { readFile } from "std/fs";
import { JsonValue } from "std/serialize/json/types";
import { glyphIndex, glyphAdvance } from "../void2d/face";
import {
	Font,
	FontFeature,
	FontId,
	FontStyle,
	SizeAdjust,
	registerFace,
	resolveFont,
	fontFace,
} from "../void2d/font";
import {
	Align,
	NO_GLYPH,
	TextLayout,
	TextStyle,
	setTextShaping,
} from "../void2d/textLayout";
import {
	allocateLabelText,
	releaseLabelText,
	shapeLabel,
	placeLabel,
	glyphAtlas,
	setSdfRegime,
	TextRegime,
} from "../void2d/labelText";
import { quantizeX, snapBaseline } from "../void2d/glyphAtlas";

when (voidSdfText) {
	import { SDF_EM } from "../void2d/textSdf";
}

import { Transform2D, trs2d } from "../void2d/types";
import { approx } from "./helpers";

const FIXTURE: string = "tests/fonts/shapeFixture.ttf";
const ORACLE_PATH: string = "tests/oracle/shapeFull.json";
const PENDING_PATH: string = "tests/PENDING.md";
const SIZE: float32 = 10.0;
const ORACLE_SIZE: float32 = 20.0;
const F: int32 = 0x66;
const I: int32 = 0x69;
const A: int32 = 0x61;
const B: int32 = 0x62;
const E_ACUTE: int32 = 0xE9;
const COMBINING_ACUTE: int32 = 0x301;

let familyCount: int32 = 0;

function fontWith(path: string, bold: boolean, features: FontFeature[]): FontId {
	familyCount = familyCount + 1;
	const family: string = `shaped layout ${familyCount}`;
	registerFace(path, family, 400, FontStyle.Normal);
	const fallbacks: string[] = [];
	const font: Font = {
		family: family, weight: bold ? 700 : 400, style: FontStyle.Normal, features: features,
		fallbacks: fallbacks, sizeAdjust: SizeAdjust.None,
	};
	const resolved = resolveFont(font);
	if (!resolved.ok) {
		console.log(`shaped layout check: ${path} did not resolve`);
		unreachable;
	}
	return resolved.value;
}

function fixture(features: FontFeature[]): FontId {
	return fontWith(FIXTURE, false, features);
}

function styleOf(font: FontId, size: float32, spacing: float32): TextStyle {
	return {
		font: font, size: size, letterSpacing: spacing, lineSpacing: 0.0, maxWidth: 0.0,
		align: Align.Left,
	};
}

function off(tag: string): FontFeature[] {
	const features: FontFeature[] = [];
	features.push({ tag: tag, value: 0 });
	return features;
}

function plain(): FontFeature[] {
	const features: FontFeature[] = [];
	return features;
}

function layoutOf(font: FontId, text: string, spacing: float32): TextLayout {
	return TextLayout.layout(text, styleOf(font, SIZE, spacing));
}

function gid(font: FontId, codepoint: int32): int32 {
	return glyphIndex(fontFace(font), codepoint);
}

test "two codepoints of a ligature are two slots, the first holding the glyph" {
	const font = fixture(plain());
	const l = layoutOf(font, "fi", 0.0);
	assert (l.glyphs.length as int32) == 2;
	assert l.glyphs[0].glyph != NO_GLYPH && l.glyphs[0].glyph != gid(font, F);
	assert l.glyphs[1].glyph == NO_GLYPH;
	assert l.glyphs[0].index == 0 && l.glyphs[1].index == 1;
	assert l.glyphs[0].byteEnd == 1 && l.glyphs[1].byteStart == 1;
	assert l.glyphs[0].clusterStart && l.glyphs[1].clusterStart;
	assert approx(l.width, 7.5);
}

test "a ligature's advance is shared evenly by the graphemes it covers" {
	const l = layoutOf(fixture(plain()), "fi", 0.0);
	assert approx(l.glyphs[0].advance, 3.75);
	assert approx(l.glyphs[1].advance, 3.75);
	assert approx(l.glyphs[0].x, 0.0);
	assert approx(l.glyphs[1].x, 3.75);
}

test "liga set to 0 gives each codepoint its own glyph and advance again" {
	const font = fixture(off("liga"));
	const l = layoutOf(font, "fi", 0.0);
	assert l.glyphs[0].glyph == gid(font, F) && l.glyphs[1].glyph == gid(font, I);
	assert approx(l.glyphs[0].advance, 5.0) && approx(l.glyphs[1].x, 5.0);
}

test "a contextual substitution keeps one slot per codepoint and changes only the glyph" {
	const on = fixture(plain());
	const gone = fixture(off("calt"));
	const l = layoutOf(on, "ab", 0.0);
	const bare = layoutOf(gone, "ab", 0.0);
	assert (l.glyphs.length as int32) == 2 && (bare.glyphs.length as int32) == 2;
	assert l.glyphs[0].glyph == bare.glyphs[0].glyph;
	assert l.glyphs[1].glyph != bare.glyphs[1].glyph;
	assert bare.glyphs[1].glyph == gid(gone, B);
	assert approx(l.glyphs[1].advance, 6.5) && approx(bare.glyphs[1].advance, 6.0);
	assert l.glyphs[1].index == bare.glyphs[1].index;
}

test "calt set to 0 lays text out as the module-off path does, glyph for glyph" {
	const font = fixture(off("calt"));
	const shaped = layoutOf(font, "ab AV", 0.0);
	setTextShaping(false);
	const unshaped = layoutOf(font, "ab AV", 0.0);
	setTextShaping(true);
	assert (shaped.glyphs.length as int32) == (unshaped.glyphs.length as int32);
	for (let k: int32 = 0; k < (shaped.glyphs.length as int32); k++) {
		assert shaped.glyphs[k].glyph == unshaped.glyphs[k].glyph;
		assert shaped.glyphs[k].index == unshaped.glyphs[k].index;
		assert approx(shaped.glyphs[k].x, unshaped.glyphs[k].x);
	}
}

test "a pair kerns through the shaper as it does through the module-off path" {
	const font = fixture(plain());
	const shaped = layoutOf(font, "AV", 0.0);
	setTextShaping(false);
	const unshaped = layoutOf(font, "AV", 0.0);
	setTextShaping(true);
	assert approx(shaped.glyphs[1].x, 6.0);
	assert approx(shaped.glyphs[1].x, unshaped.glyphs[1].x);
	assert approx(shaped.width, unshaped.width);
}

test "kern set to 0 turns the shaper's pair adjustment off" {
	const l = layoutOf(fixture(off("kern")), "AV", 0.0);
	assert approx(l.glyphs[1].x, 7.0);
}

test "a mark's GPOS offset rides on its slot while the pen does not move" {
	const l = layoutOf(fixture(plain()), "e\u{301}a", 0.0);
	assert (l.glyphs.length as int32) == 3;
	assert approx(l.glyphs[1].advance, 0.0);
	assert approx(l.glyphs[1].x, 6.0);
	assert approx(l.glyphs[1].offsetX, -3.0);
	assert approx(l.glyphs[1].offsetY, -2.0);
	assert approx(l.glyphs[2].x, 6.0);
	assert l.glyphs[0].offsetX == 0.0 && l.glyphs[0].offsetY == 0.0;
}

test "mark set to 0 leaves the mark with no offset" {
	const l = layoutOf(fixture(off("mark")), "e\u{301}", 0.0);
	assert l.glyphs[1].offsetX == 0.0 && l.glyphs[1].offsetY == 0.0;
}

test "one codepoint that shapes to two glyphs gets a slot for the second after it" {
	const font = fixture(plain());
	const l = layoutOf(font, "\u{E9}a", 0.0);
	assert (l.glyphs.length as int32) == 3;
	assert l.glyphs[0].glyph == gid(font, 0x65);
	assert l.glyphs[1].glyph == gid(font, COMBINING_ACUTE);
	assert l.glyphs[0].codepoint == E_ACUTE && l.glyphs[1].codepoint == E_ACUTE;
	assert l.glyphs[0].index == 0 && l.glyphs[1].index == 0;
	assert l.glyphs[0].byteEnd == 2 && l.glyphs[1].byteEnd == 2;
	assert l.glyphs[0].clusterStart && !l.glyphs[1].clusterStart;
	assert approx(l.glyphs[1].offsetX, -3.0) && approx(l.glyphs[1].offsetY, -2.0);
	assert approx(l.glyphs[2].x, 6.0);
	assert l.glyphs[2].index == 1;
}

test "ccmp set to 0 keeps the precomposed glyph in one slot" {
	const font = fixture(off("ccmp"));
	const l = layoutOf(font, "\u{E9}", 0.0);
	assert (l.glyphs.length as int32) == 1;
	assert l.glyphs[0].glyph == gid(font, E_ACUTE);
}

test "letter spacing lands after the last slot of a grapheme, extra slots included" {
	const font = fixture(plain());
	const l = layoutOf(font, "\u{E9}a", 2.0);
	assert approx(l.glyphs[1].x, 6.0);
	assert approx(l.glyphs[2].x, 8.0);
	const fi = layoutOf(font, "fi", 1.0);
	assert fi.glyphs[0].glyph == gid(font, F) && fi.glyphs[1].glyph == gid(font, I);
	assert approx(fi.glyphs[1].x, 6.0);
}

test "an author's feature list wins over the optional ligatures letter spacing turns off" {
	const features: FontFeature[] = [];
	features.push({ tag: "liga", value: 1 });
	const font = fixture(features);
	const spaced = layoutOf(font, "fi", 1.0);
	assert spaced.glyphs[1].glyph == NO_GLYPH;
	assert approx(spaced.width, 8.5);
}

test "synthetic bold adds the emboldening to a shaped advance as the module-off path does" {
	const font = fontWith(FIXTURE, true, plain());
	const face = fontFace(font);
	const l = layoutOf(font, "ab", 0.0);
	assert approx(l.glyphs[0].advance, glyphAdvance(face, gid(font, A), SIZE));
	const regular = layoutOf(fixture(plain()), "ab", 0.0);
	assert l.glyphs[0].advance > regular.glyphs[0].advance;
}

test "a default-ignorable codepoint keeps its slot with no glyph and no advance" {
	const font = fixture(plain());
	const l = layoutOf(font, "a\u{200D}b", 0.0);
	assert (l.glyphs.length as int32) == 3;
	assert l.glyphs[1].glyph == NO_GLYPH && l.glyphs[1].advance == 0.0;
}

test "a control character and a newline keep the module-off slots" {
	const font = fixture(plain());
	const l = layoutOf(font, "a\tb\nA", 0.0);
	setTextShaping(false);
	const unshaped = layoutOf(font, "a	b
A", 0.0);
	setTextShaping(true);
	assert (l.glyphs.length as int32) == 4 && (unshaped.glyphs.length as int32) == 4;
	assert l.glyphs[1].glyph == NO_GLYPH && l.glyphs[1].advance == unshaped.glyphs[1].advance;
	assert approx(l.glyphs[2].x, unshaped.glyphs[2].x);
	assert (l.lines.length as int32) == 2;
}

test "a label places a mark at its GPOS offset" {
	const font = fixture(plain());
	const marked = allocateLabelText();
	shapeLabel(marked, "e\u{301}", styleOf(font, SIZE, 0.0));
	const bare = allocateLabelText();
	shapeLabel(bare, "e\u{301}", styleOf(fixture(off("mark")), SIZE, 0.0));
	const world: Transform2D = trs2d(0.0, 0.0, 0.0, 1.0, 1.0);
	const withOffset = placeLabel(marked, world, 1.0);
	const g = withOffset.layout.glyphs[1];
	const q = quantizeX((g.x + g.offsetX) * 1.0);
	const baseline = snapBaseline((withOffset.layout.lines[0].baseline + g.offsetY) * 1.0);
	const tile = glyphAtlas.tile(withOffset.placed[1].tile);
	assert withOffset.placed[1].x == ((q.whole + tile.left) as float32);
	assert withOffset.placed[1].y == ((baseline + tile.top) as float32);
	const without = placeLabel(bare, world, 1.0);
	assert withOffset.placed[1].x != without.placed[1].x;
	assert withOffset.placed[1].y != without.placed[1].y;
	assert withOffset.placed[0].x == without.placed[0].x;
	releaseLabelText(marked);
	releaseLabelText(bare);
}

function oracleRows(): JsonValue {
	const text = readFile(ORACLE_PATH);
	if (!text.ok) {
		console.log(`shaped layout check: ${ORACLE_PATH} cannot be read`);
		unreachable;
	}
	const parsed = JSON.parseValue(text.value);
	if (!parsed.ok) {
		console.log(`shaped layout check: ${ORACLE_PATH} is not JSON`);
		unreachable;
	}
	return parsed.value.getDynamicField("rows");
}

function rightToLeft(codepoint: int32): boolean {
	return (codepoint >= 0x590 && codepoint <= 0x8FF) ||
		(codepoint >= 0xFB1D && codepoint <= 0xFEFF);
}

function isJoinerCodepoint(codepoint: int32): boolean {
	return codepoint == 0x200C || codepoint == 0x200D || codepoint == 0xFE0E || codepoint == 0xFE0F;
}

function hasJoiner(codepoints: JsonValue): boolean {
	for (let c: int32 = 0; c < (codepoints.length() as int32); c++) {
		if (isJoinerCodepoint(codepoints.at(c).asNumber() as int32)) { return true; }
	}
	return false;
}

function oracleFont(row: JsonValue, path: string): FontId {
	const features: FontFeature[] = [];
	const listed = row.getDynamicField("features");
	for (let f: int32 = 0; f < (listed.length() as int32); f++) {
		features.push({
			tag: listed.at(f).at(0).asString(), value: listed.at(f).at(1).asNumber() as int32,
		});
	}
	return fontWith(path, false, features);
}

test "every left-to-right oracle row is laid out at the layout level as HarfBuzz shapes it" {
	const rows = oracleRows();
	const pendingText = readFile(PENDING_PATH);
	assert pendingText.ok;
	const pending: string = pendingText.ok ? pendingText.value : "";
	let compared: int32 = 0;
	let values: int32 = 0;
	for (let r: int32 = 0; r < (rows.length() as int32); r++) {
		const row = rows.at(r);
		const id: string = row.getDynamicField("id").asString();
		if (row.getDynamicField("direction").asNumber() != 0) { continue; }
		if (pending.includes(`| shape:${id} |`)) { continue; }
		const codepoints = row.getDynamicField("codepoints");
		const total: int32 = codepoints.length() as int32;
		if (total == 0) { continue; }
		let text: string = "";
		let skip: boolean = false;
		for (let c: int32 = 0; c < total; c++) {
			const cp: int32 = codepoints.at(c).asNumber() as int32;
			if (rightToLeft(cp)) { skip = true; }
			text += fromCodePoint(cp);
		}
		if (skip) { continue; }
		const font = oracleFont(row, row.getDynamicField("path").asString());
		const joiners: boolean = hasJoiner(codepoints);
		const l = TextLayout.layout(text, styleOf(font, ORACLE_SIZE, 0.0));
		const upem: float32 = row.getDynamicField("unitsPerEm").asNumber() as float32;
		const perUnit: float32 = ORACLE_SIZE / upem;
		const expected = row.getDynamicField("glyphs");
		let pen: float32 = 0.0;
		let at: int32 = 0;
		for (let g: int32 = 0; g < (expected.length() as int32); g++) {
			const want = expected.at(g);
			const advance: float32 = (want.at(2).asNumber() as float32) * perUnit;
			const blank: int32 = glyphIndex(fontFace(font), 0x20);
			const wantGlyph: int32 = want.at(0).asNumber() as int32;
			if (joiners && advance == 0.0 && wantGlyph == blank) { continue; }
			while (at < (l.glyphs.length as int32) && l.glyphs[at].glyph == NO_GLYPH) {
				at = at + 1;
			}
			if (at >= (l.glyphs.length as int32)) {
				console.log(`shaped layout check: ${id} has fewer glyphs than the oracle`);
				assert false;
			}
			const got = l.glyphs[at];
			if (got.glyph != wantGlyph) {
				console.log(
					`shaped layout check: ${id} glyph ${g} is ${got.glyph}, oracle ${wantGlyph}`,
				);
				assert false;
			}
			assert approx(got.x, pen);
			assert approx(got.offsetX, (want.at(4).asNumber() as float32) * perUnit);
			assert approx(got.offsetY, -(want.at(5).asNumber() as float32) * perUnit);
			values = values + 3;
			pen = pen + advance;
			at = at + 1;
		}
		while (at < (l.glyphs.length as int32)) {
			if (l.glyphs[at].glyph != NO_GLYPH) {
				console.log(`shaped layout check: ${id} has more glyphs than the oracle`);
				assert false;
			}
			at = at + 1;
		}
		compared = compared + 1;
	}
	console.log(
		`shaped layout: ${compared} oracle rows agree at the layout level, ${values} values`,
	);
	assert compared > 40;
}

when (voidSdfText) {
	test "an SDF label places a mark at its GPOS offset too" {
		setSdfRegime(true);
		defer setSdfRegime(false);
		const index = allocateLabelText();
		shapeLabel(index, "e\u{301}", styleOf(fixture(plain()), SIZE, 0.0));
		const text = placeLabel(index, trs2d(0.0, 0.0, 0.5, 2.0, 2.0), 1.0);
		assert text.regime == TextRegime.Sdf;
		assert (text.placed.length as int32) == 2;
		const g = text.layout.glyphs[1];
		const tile = glyphAtlas.tile(text.placed[1].tile);
		const k: float32 = SIZE / SDF_EM;
		assert approx(text.placed[1].x, g.x + g.offsetX + (tile.left as float32) * k);
		assert approx(
			text.placed[1].y,
			text.layout.lines[0].baseline + g.offsetY + (tile.top as float32) * k,
		);
		releaseLabelText(index);
	}
}
