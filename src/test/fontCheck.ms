import { loadFace, glyphIndex, glyphAdvance, faceMetrics } from "../void2d/face";
import {
	Font,
	FontStyle,
	FontFeature,
	SizeAdjust,
	FontId,
	FontError,
	addFont,
	addFallbackFont,
	registerFace,
	resolveFont,
	fontFace,
	faceForCodepoint,
	fallbackFacesLoaded,
	fallbackProbes,
} from "../void2d/font";
import { label } from "../void2d/node";
import { Align, TextLayout } from "../void2d/textLayout";
import { rgba } from "../void2d/types";
import { approx } from "./helpers";

const LATIN: string = "assets/font.ttf";
const CJK: string = "tests/fonts/NotoSansSC-subset.ttf";
const LIGHT: string = "tests/fonts/zeroThickness.ttf";
const HEAVY: string = "tests/fonts/zeroedDecorations.ttf";
const NO_LINE_HEIGHT: string = "tests/fonts/zeroLineHeight.ttf";

let registeredFamilies: boolean = false;

function registerFamilies(): void {
	if (registeredFamilies) { return; }
	registeredFamilies = true;
	registerFace(LATIN, "Test Sans", 400, FontStyle.Normal);
	registerFace(LIGHT, "Weights", 300, FontStyle.Normal);
	registerFace(LATIN, "Weights", 400, FontStyle.Normal);
	registerFace(HEAVY, "Weights", 700, FontStyle.Normal);
	registerFace(HEAVY, "Weights", 400, FontStyle.Italic);
	registerFace(CJK, "Test Hanzi", 400, FontStyle.Normal);
	registerFace(NO_LINE_HEIGHT, "No Line Height", 400, FontStyle.Normal);
}

function font(family: string, weight: int32, style: FontStyle): Font {
	registerFamilies();
	const features: FontFeature[] = [];
	const fallbacks: string[] = [];
	return {
		family: family, weight: weight, style: style, features: features, fallbacks: fallbacks,
		sizeAdjust: SizeAdjust.None,
	};
}

function added(path: string): FontId {
	const r = addFont(path);
	if (r.ok) { return r.value; }
	console.log(`fontCheck: ${path} did not load (${r.error.toString()})`);
	unreachable;
}

function resolved(f: Font): FontId {
	const r = resolveFont(f);
	if (r.ok) { return r.value; }
	console.log(`fontCheck: font "${f.family}" was refused (${r.error.toString()})`);
	unreachable;
}

function faceOfPath(path: string): int32 {
	return fontFace(added(path));
}

function layoutWith(fontId: FontId, text: string): TextLayout {
	return TextLayout.layout(text, {
		font: fontId,
		size: 13.0,
		letterSpacing: 0.0,
		lineSpacing: 0.0,
		maxWidth: 0.0,
		align: Align.Left,
	});
}

test "the primary face lacks a hanzi the fallback has" {
	const primary = try loadFace(LATIN) catch -1;
	assert glyphIndex(primary, 0x4F60) == 0;
	const cjk = try loadFace(CJK) catch -1;
	assert cjk >= 0;
	assert glyphIndex(cjk, 0x4F60) != 0;
}

test "a covered codepoint stays on the primary and a miss moves to the fallback" {
	const f = added(LATIN);
	addFallbackFont(f, CJK);
	assert faceForCodepoint(f, "A".code) == fontFace(f);
	const face = faceForCodepoint(f, 0x4F60);
	assert face != fontFace(f);
	assert glyphIndex(face, 0x4F60) != 0;
}

test "the fallback face loads on the first real miss, and only once" {
	const f = added(LATIN);
	addFallbackFont(f, CJK);
	const before = fallbackFacesLoaded();
	faceForCodepoint(f, "B".code);
	assert fallbackFacesLoaded() == before;
	faceForCodepoint(f, 0x597D);
	faceForCodepoint(f, 0x4E16);
	assert fallbackFacesLoaded() == before + 1;
}

test "a codepoint no face has is resolved once and then cached as a miss" {
	const f = added(LATIN);
	addFallbackFont(f, CJK);
	const thai: int32 = 0x0E01;
	assert faceForCodepoint(f, thai) == fontFace(f);
	const probes = fallbackProbes();
	assert faceForCodepoint(f, thai) == fontFace(f);
	assert fallbackProbes() == probes;
}

test "a mixed run takes each glyph from its own face and kerns only within one" {
	const f = added(LATIN);
	addFallbackFont(f, CJK);
	const primary = fontFace(f);
	const l = layoutWith(f, "A你V");
	const cjk = l.glyphs[1].face;
	assert l.glyphs[0].face == primary;
	assert cjk != primary;
	assert l.glyphs[2].face == primary;
	const aWidth = glyphAdvance(primary, l.glyphs[0].glyph, 13.0);
	assert approx(l.glyphs[1].x, aWidth);
	assert approx(l.glyphs[2].x, aWidth + glyphAdvance(cjk, l.glyphs[1].glyph, 13.0));
}

test "a font value resolves to its registered face and is interned" {
	const regular = resolved(font("Test Sans", 400, FontStyle.Normal));
	assert fontFace(regular) == faceOfPath(LATIN);
	assert resolved(font("Test Sans", 400, FontStyle.Normal)) == regular;
}

test "weights match in the CSS order: down from 400-500, up from above 500, down below 400" {
	assert fontFace(resolved(font("Weights", 500, FontStyle.Normal))) == faceOfPath(LATIN);
	assert fontFace(resolved(font("Weights", 600, FontStyle.Normal))) == faceOfPath(HEAVY);
	assert fontFace(resolved(font("Weights", 350, FontStyle.Normal))) == faceOfPath(LIGHT);
	assert fontFace(resolved(font("Weights", 900, FontStyle.Normal))) == faceOfPath(HEAVY);
}

test "a registered italic wins over a synthetic one" {
	assert fontFace(resolved(font("Weights", 400, FontStyle.Italic))) == faceOfPath(HEAVY);
}

test "a missing bold or italic is synthesized from the nearest face" {
	const regularFace = faceOfPath(LATIN);
	const bold = fontFace(resolved(font("Test Sans", 700, FontStyle.Normal)));
	const italic = fontFace(resolved(font("Test Sans", 400, FontStyle.Italic)));
	assert bold != regularFace;
	assert italic != regularFace;
	assert bold != italic;
	const h = glyphIndex(regularFace, "H".code);
	assert glyphAdvance(bold, h, 13.0) > glyphAdvance(regularFace, h, 13.0);
	assert glyphAdvance(italic, h, 13.0) == glyphAdvance(regularFace, h, 13.0);
	assert fontFace(resolved(font("Test Sans", 800, FontStyle.Normal))) == bold;
}

test "the kern feature set to 0 turns pair kerning off" {
	const kerned = resolved(font("Test Sans", 400, FontStyle.Normal));
	const plain = font("Test Sans", 400, FontStyle.Normal);
	plain.features.push({ tag: "kern", value: 0 });
	const unkerned = resolved(plain);
	assert unkerned != kerned;
	const face = fontFace(kerned);
	const aWidth = glyphAdvance(face, glyphIndex(face, "A".code), 13.0);
	assert approx(layoutWith(unkerned, "AV").glyphs[1].x, aWidth);
	assert layoutWith(kerned, "AV").glyphs[1].x < aWidth - 0.5;
}

test "a feature the shaper owns, or a family nobody registered, refuses the font" {
	const ligatures = font("Test Sans", 400, FontStyle.Normal);
	ligatures.features.push({ tag: "liga", value: 1 });
	const shaped = resolveFont(ligatures);
	assert !shaped.ok;
	if (!shaped.ok) { assert shaped.error == FontError.NeedsShaper; }
	const unknown = resolveFont(font("No Such Family", 400, FontStyle.Normal));
	assert !unknown.ok;
	if (!unknown.ok) { assert unknown.error == FontError.NoFamily; }
	const badFallback = font("Test Sans", 400, FontStyle.Normal);
	badFallback.fallbacks.push("No Such Family");
	const fallbackRefused = resolveFont(badFallback);
	assert !fallbackRefused.ok;
	if (!fallbackRefused.ok) { assert fallbackRefused.error == FontError.NoFallbackFamily; }
	const missing = addFont("tests/fonts/noSuchFont.ttf");
	assert !missing.ok;
	if (!missing.ok) { assert missing.error == FontError.NotLoaded; }
}

test "fallback families resolve in the font's weight, synthesized when they lack it" {
	const regular = font("Test Sans", 400, FontStyle.Normal);
	regular.fallbacks.push("Test Hanzi");
	const bold = font("Test Sans", 700, FontStyle.Normal);
	bold.fallbacks.push("Test Hanzi");
	const regularId = resolved(regular);
	const boldId = resolved(bold);
	const regularHanzi = faceForCodepoint(regularId, 0x4F60);
	const boldHanzi = faceForCodepoint(boldId, 0x4F60);
	assert regularHanzi == faceOfPath(CJK);
	assert boldHanzi != regularHanzi;
	const g = glyphIndex(regularHanzi, 0x4F60);
	assert glyphAdvance(boldHanzi, g, 13.0) > glyphAdvance(regularHanzi, g, 13.0);
}

test "setFont gives a label the font a FontId names" {
	const n = label("void2d", 13.0, rgba(1.0, 1.0, 1.0, 1.0));
	const bold: FontId = resolved(font("Test Sans", 700, FontStyle.Normal));
	n.setFont(bold);
	assert n.fontId == bold;
}

struct AdjustCase {
	adjust: SizeAdjust;
	ratio: float64;
}

function withFallback(family: string, fallback: string, adjust: SizeAdjust): FontId {
	const f = font(family, 400, FontStyle.Normal);
	f.fallbacks.push(fallback);
	f.sizeAdjust = adjust;
	return resolved(f);
}

function laidSize(fontId: FontId, text: string, index: int32): float32 {
	return layoutWith(fontId, text).glyphs[index].size;
}

test "without sizeAdjust a fallback glyph keeps the label's size" {
	assert laidSize(withFallback("Test Sans", "Test Hanzi", SizeAdjust.None), "A你", 1) == 13.0;
}

test "sizeAdjust scales a fallback face to the primary's metric, in em" {
	const inter: float32 = 1.0 / 2048.0;
	const noto: float32 = 1.0 / 1000.0;
	const cases: AdjustCase[] = [
		{ adjust: SizeAdjust.IcWidth, ratio: 2450.0 * inter / (1000.0 * noto) },
		{ adjust: SizeAdjust.ExHeight, ratio: 1118.0 * inter / (543.0 * noto) },
		{ adjust: SizeAdjust.CapHeight, ratio: 1490.0 * inter / (733.0 * noto) },
		{ adjust: SizeAdjust.LineHeight, ratio: 2478.0 * inter / (1448.0 * noto) },
	];
	for (const c of cases) {
		const id = withFallback("Test Sans", "Test Hanzi", c.adjust);
		const l = layoutWith(id, "A你");
		assert l.glyphs[0].size == 13.0;
		assert Math.abs(l.glyphs[1].size - ((13.0 * c.ratio) as float32)) < 0.01;
		const g = l.glyphs[1];
		assert approx(g.advance, glyphAdvance(g.face, g.glyph, g.size));
	}
}

test "an ic width the fallback lacks falls through to the ex height" {
	const id = withFallback("Test Hanzi", "Test Sans", SizeAdjust.IcWidth);
	const l = layoutWith(id, "你é");
	assert l.glyphs[1].face != l.glyphs[0].face;
	assert Math.abs(l.glyphs[1].size - 13.0 * (543.0 / 1000.0) / (1118.0 / 2048.0)) < 0.01;
}

test "a primary face with no line height leaves a line-height fallback at the label's size" {
	const id = withFallback("No Line Height", "Test Sans", SizeAdjust.LineHeight);
	const l = layoutWith(id, "Hx");
	assert l.glyphs[1].face != l.glyphs[0].face;
	assert l.glyphs[1].size == 13.0;
}

test "a grapheme takes the first face that covers all of it, and a lone codepoint its own" {
	const id = withFallback("Test Sans", "Test Hanzi", SizeAdjust.None);
	const l = layoutWith(id, "A〪 B");
	const hanzi: int32 = faceForCodepoint(id, 0x4F60);
	assert l.glyphs[0].face == hanzi && l.glyphs[1].face == hanzi;
	assert l.glyphs[3].face == fontFace(id);
}

test "a grapheme no one face covers keeps a face per codepoint" {
	const id = withFallback("Test Sans", "Test Hanzi", SizeAdjust.None);
	const l = layoutWith(id, "你́");
	assert l.glyphs[0].face == faceForCodepoint(id, 0x4F60);
	assert l.glyphs[1].face == fontFace(id);
}

test "a line box is as tall as the tallest face on it, and a Latin line keeps the font's" {
	const id = withFallback("Test Sans", "Test Hanzi", SizeAdjust.None);
	const inter = faceMetrics(fontFace(id), 13.0);
	const noto = faceMetrics(faceForCodepoint(id, 0x4F60), 13.0);
	assert noto.ascent > inter.ascent;
	const l = layoutWith(id, "A\n你A\nA");
	const latin: float32 = inter.ascent + inter.descent + inter.lineGap;
	const mixed: float32 = noto.ascent + Math.max(noto.descent, inter.descent) + inter.lineGap;
	assert approx(l.lines[0].height, latin) && approx(l.lines[2].height, latin);
	assert approx(l.lines[1].height, mixed);
	assert approx(l.lines[1].top, latin);
	assert approx(l.lines[1].baseline, latin + noto.ascent);
	assert approx(l.lines[2].top, latin + mixed);
	assert approx(l.height, latin + mixed + latin);
}
