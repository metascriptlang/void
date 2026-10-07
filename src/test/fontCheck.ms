import {
	loadFace,
	glyphIndex,
	glyphAdvance,
	faceMetrics,
	faceSummariesRead,
	peekFace,
	summaryCovers,
	colourBuilt,
	isColourOnly,
	isSpriteFace,
} from "../void2d/face";
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
	Presentation,
	codepointFaceFor,
	faceSlotFor,
	spriteCellFor,
} from "../void2d/font";
import { Scene2D } from "../void2d/node";
import "../void2d/scene";
import { Align, TextLayout } from "../void2d/textLayout";
import { rgba } from "../void2d/types";
import { approx } from "./helpers";

const LATIN: string = "assets/font.ttf";
const CJK: string = "tests/fonts/NotoSansSC-subset.ttf";
const LIGHT: string = "tests/fonts/zeroThickness.ttf";
const HEAVY: string = "tests/fonts/zeroedDecorations.ttf";
const NO_LINE_HEIGHT: string = "tests/fonts/zeroLineHeight.ttf";
const TEXT_SYMBOL: string = "tests/fonts/textSymbol.ttf";
const COLOUR_ONLY: string = "tests/fonts/cbdtSynthetic.ttf";
const COLOUR_DRAWABLE: string = "tests/fonts/sbixSynthetic.ttf";
const COLLECTION: string = "tests/fonts/symbolCollection.ttc";
const JOINERS: string = "tests/fonts/cmap/joiners.ttf";
const UNLOADABLE: string = "tests/fonts/cmap/coversButUnloadable.otf";

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

function covered(f: FontId, codepoint: int32): boolean {
	return glyphIndex(fontFace(f), codepoint) != 0 ||
		faceSlotFor(f, codepoint, Presentation.Any) >= 0;
}

function peekedCovers(path: string, codepoint: int32): boolean {
	const peeked = peekFace(path);
	return peeked.ok && summaryCovers(peeked.value, codepoint);
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
	const loads = fallbackFacesLoaded();
	assert faceForCodepoint(f, thai) == fontFace(f);
	assert fallbackFacesLoaded() == loads;
	const probes = fallbackProbes();
	assert faceForCodepoint(f, thai) == fontFace(f);
	assert fallbackProbes() == probes;
}

test "coverage of a fallback is answered from its summary, with no face loaded" {
	const f = added(LATIN);
	addFallbackFont(f, TEXT_SYMBOL);
	const loads = fallbackFacesLoaded();
	assert covered(f, 0x1F600);
	const summaries = faceSummariesRead();
	assert covered(f, 0x2764);
	assert !covered(f, 0x0E01);
	assert faceSummariesRead() == summaries;
	assert fallbackFacesLoaded() == loads;
	const face = faceForCodepoint(f, 0x1F600);
	assert face != fontFace(f);
	assert glyphIndex(face, 0x1F600) != 0;
	assert fallbackFacesLoaded() == loads + 1;
	assert faceSummariesRead() == summaries;
}

test "with the colour module off a colour-only fallback is skipped without a load" {
	if (colourBuilt()) { return; }
	const f = added(LATIN);
	addFallbackFont(f, COLOUR_ONLY);
	const loads = fallbackFacesLoaded();
	assert peekedCovers(COLOUR_ONLY, 0x1F600);
	assert faceForCodepoint(f, 0x1F600) == fontFace(f);
	assert faceForCodepoint(f, 0x2764) == fontFace(f);
	assert codepointFaceFor(f, 0x1F600, Presentation.Emoji).face == fontFace(f);
	assert fallbackFacesLoaded() == loads;
	assert peekedCovers(COLOUR_ONLY, 0x1F600);
}

test "with the colour module on a colour-only fallback is drawable and loads once" {
	if (!colourBuilt()) { return; }
	const f = added(LATIN);
	addFallbackFont(f, COLOUR_ONLY);
	const loads = fallbackFacesLoaded();
	assert peekedCovers(COLOUR_ONLY, 0x1F600);
	const face = faceForCodepoint(f, 0x1F600);
	assert face != fontFace(f);
	assert isColourOnly(face);
	assert glyphIndex(face, 0x1F600) != 0;
	assert fallbackFacesLoaded() == loads + 1;
}

function symbolFont(colourFirst: boolean): FontId {
	const f = added(NO_LINE_HEIGHT);
	if (colourFirst) {
		addFallbackFont(f, COLOUR_DRAWABLE);
		addFallbackFont(f, TEXT_SYMBOL);
	} else {
		addFallbackFont(f, TEXT_SYMBOL);
		addFallbackFont(f, COLOUR_DRAWABLE);
	}
	return f;
}

test "with no selector the default presentation picks the matching fallback in either order" {
	const text = faceOfPath(TEXT_SYMBOL);
	const colour = faceOfPath(COLOUR_DRAWABLE);
	for (const colourFirst of [false, true]) {
		const f = symbolFont(colourFirst);
		assert codepointFaceFor(f, 0x1F600, Presentation.Default).face == colour;
		assert codepointFaceFor(f, 0x2764, Presentation.Default).face == text;
	}
}

test "VS15 asks for the text face and VS16 for the colour face, in either order" {
	const text = faceOfPath(TEXT_SYMBOL);
	const colour = faceOfPath(COLOUR_DRAWABLE);
	for (const colourFirst of [false, true]) {
		const f = symbolFont(colourFirst);
		assert codepointFaceFor(f, 0x1F600, Presentation.Text).face == text;
		assert codepointFaceFor(f, 0x2764, Presentation.Text).face == text;
		assert codepointFaceFor(f, 0x1F600, Presentation.Emoji).face == colour;
		assert codepointFaceFor(f, 0x2764, Presentation.Emoji).face == colour;
	}
}

test "the any mode takes the first covering face whatever its presentation" {
	const text = faceOfPath(TEXT_SYMBOL);
	const colour = faceOfPath(COLOUR_DRAWABLE);
	assert codepointFaceFor(symbolFont(false), 0x1F600, Presentation.Any).face == text;
	assert codepointFaceFor(symbolFont(true), 0x2764, Presentation.Any).face == colour;
}

test "the primary face is explicit: it takes any presentation until a selector asks" {
	const text = faceOfPath(TEXT_SYMBOL);
	const colour = faceOfPath(COLOUR_DRAWABLE);
	const f = added(TEXT_SYMBOL);
	addFallbackFont(f, COLOUR_DRAWABLE);
	assert codepointFaceFor(f, 0x1F600, Presentation.Default).face == text;
	assert codepointFaceFor(f, 0x1F600, Presentation.Text).face == text;
	assert codepointFaceFor(f, 0x1F600, Presentation.Emoji).face == colour;
}

test "a fallback of the other presentation is the last resort when nothing matches" {
	const text = faceOfPath(TEXT_SYMBOL);
	const colour = faceOfPath(COLOUR_DRAWABLE);
	const onlyText = added(NO_LINE_HEIGHT);
	addFallbackFont(onlyText, TEXT_SYMBOL);
	assert codepointFaceFor(onlyText, 0x1F600, Presentation.Emoji).face == text;
	const onlyColour = added(NO_LINE_HEIGHT);
	addFallbackFont(onlyColour, COLOUR_DRAWABLE);
	assert codepointFaceFor(onlyColour, 0x2764, Presentation.Text).face == colour;
	assert codepointFaceFor(onlyColour, 0x2764, Presentation.Default).face == colour;
}

test "the resolver answers a presentation without loading a face it does not pick" {
	const f = symbolFont(false);
	const loads = fallbackFacesLoaded();
	assert faceSlotFor(f, 0x1F600, Presentation.Emoji) >= 0;
	assert faceSlotFor(f, 0x2764, Presentation.Text) >= 0;
	assert fallbackFacesLoaded() == loads;
	const probes = fallbackProbes();
	assert faceSlotFor(f, 0x1F600, Presentation.Emoji) >= 0;
	assert fallbackProbes() == probes;
	const asText: int32 = faceSlotFor(f, 0x1F600, Presentation.Text);
	assert asText != faceSlotFor(f, 0x1F600, Presentation.Emoji);
}

test "an unreadable fallback path is refused by the peek and never loaded" {
	const f = added(LATIN);
	addFallbackFont(f, "tests/fonts/doesNotExist.ttf");
	const loads = fallbackFacesLoaded();
	assert !covered(f, 0x4F60);
	assert faceForCodepoint(f, 0x4F60) == fontFace(f);
	assert fallbackFacesLoaded() == loads;
}

test "a fallback that covers a codepoint but will not load is skipped, and only its font forgets" {
	const keeper = added(LATIN);
	addFallbackFont(keeper, TEXT_SYMBOL);
	const broken = added(LATIN);
	addFallbackFont(broken, UNLOADABLE);
	assert faceSlotFor(keeper, 0x1F600, Presentation.Default) >= 0;
	assert faceSlotFor(broken, 0x1F600, Presentation.Default) >= 0;
	assert codepointFaceFor(broken, 0x1F600, Presentation.Default).face == fontFace(broken);
	const probes = fallbackProbes();
	assert faceSlotFor(keeper, 0x1F600, Presentation.Default) >= 0;
	assert codepointFaceFor(broken, 0x1F600, Presentation.Default).face == fontFace(broken);
	assert fallbackProbes() == probes;
}

test "a selector or joiner takes the face before it and loads no face of its own" {
	const f = added(LATIN);
	addFallbackFont(f, TEXT_SYMBOL);
	addFallbackFont(f, JOINERS);
	const loads = fallbackFacesLoaded();
	const split = layoutWith(f, "\u{1F600}\u{301}\u{FE0F}");
	assert split.glyphs[0].face == faceOfPath(TEXT_SYMBOL);
	assert split.glyphs[1].face == fontFace(f);
	assert fallbackFacesLoaded() == loads + 1;
	const alone = added(LATIN);
	addFallbackFont(alone, JOINERS);
	const before = fallbackFacesLoaded();
	layoutWith(alone, "\u{200D}");
	layoutWith(alone, "\u{FE0F}");
	assert fallbackFacesLoaded() == before;
}

test "the summary of a collection is the summary of its first font" {
	const f = added(LATIN);
	addFallbackFont(f, COLLECTION);
	assert covered(f, 0x1F600);
	assert covered(f, 0x2764);
	const face = faceForCodepoint(f, 0x1F600);
	assert face != fontFace(f);
	assert glyphIndex(face, 0x1F600) != 0;
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
	when (voidShaper) {
		assert shaped.ok;
		const tagged = font("Test Sans", 400, FontStyle.Normal);
		tagged.features.push({ tag: "lig", value: 1 });
		const short = resolveFont(tagged);
		assert !short.ok;
		if (!short.ok) { assert short.error == FontError.BadFeatureTag; }
	} else {
		assert !shaped.ok;
		if (!shaped.ok) { assert shaped.error == FontError.NeedsShaper; }
	}
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
	const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	const n = s.label("void2d", 13.0, rgba(1.0, 1.0, 1.0, 1.0));
	const bold: FontId = resolved(font("Test Sans", 700, FontStyle.Normal));
	n.setFont(bold);
	assert n.textStyle().font == bold;
}

struct AdjustCase {
	adjust: SizeAdjust;
	ratio: float64;
}

function withFallback(family: string, fallback: string, adjust: SizeAdjust): FontId {
	let f = font(family, 400, FontStyle.Normal);
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
	const noto: float32 = (1.0 / 1000.0) as float32;
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

test "a sprite codepoint resolves to a sprite face before any font and probes no coverage" {
	const f = added(LATIN);
	addFallbackFont(f, CJK);
	const modes: Presentation[] = [
		Presentation.Default, Presentation.Text, Presentation.Emoji, Presentation.Any,
	];
	const probes = fallbackProbes();
	const loads = fallbackFacesLoaded();
	const samples: int32[] = [0x2500, 0x2588, 0x2593, 0x257F, 0x2800, 0x28FF];
	for (const mode of modes) {
		for (const codepoint of samples) {
			const resolvedFace = codepointFaceFor(f, codepoint, mode);
			assert isSpriteFace(resolvedFace.face);
			assert resolvedFace.scale == 1.0;
			assert glyphIndex(resolvedFace.face, codepoint) != 0;
		}
	}
	assert fallbackProbes() == probes;
	assert fallbackFacesLoaded() == loads;
	assert !isSpriteFace(codepointFaceFor(f, "A".code, Presentation.Default).face);
	assert !isSpriteFace(codepointFaceFor(f, 0x24FF, Presentation.Default).face);
	assert !isSpriteFace(codepointFaceFor(f, 0x4F60, Presentation.Default).face);
}

test "one sprite face serves every codepoint of a font and each font's base has its own" {
	const a = added(LATIN);
	const b = added(CJK);
	const first = codepointFaceFor(a, 0x2588, Presentation.Default).face;
	assert codepointFaceFor(a, 0x2800, Presentation.Default).face == first;
	assert codepointFaceFor(a, 0x2588, Presentation.Text).face == first;
	const other = codepointFaceFor(b, 0x2588, Presentation.Default).face;
	assert isSpriteFace(other);
	assert other != first;
}

test "a laid out line puts the sprite face on the box and braille glyphs and the font on the rest" {
	const f = added(LATIN);
	const l = layoutWith(f, "a\u{2588}b\u{2800}");
	assert l.glyphs[0].face == fontFace(f) && l.glyphs[2].face == fontFace(f);
	assert isSpriteFace(l.glyphs[1].face) && isSpriteFace(l.glyphs[3].face);
	assert l.glyphs[1].size == 13.0;
	assert l.glyphs[1].glyph == glyphIndex(l.glyphs[1].face, 0x2588);
	assert approx(l.glyphs[1].advance, glyphAdvance(l.glyphs[1].face, l.glyphs[1].glyph, 13.0));
	assert l.glyphs[1].advance > 0.0;
}

test "a cell is whole device pixels at every size and DPI, and forceWidth reproduces its width" {
	const f = added(LATIN);
	const face = fontFace(f);
	const sizes: float32[] = [13.0, 14.0, 16.0];
	const scales: float32[] = [1.0, 1.25, 1.5];
	for (const size of sizes) {
		for (const dpl of scales) {
			const cell = spriteCellFor(f, size * dpl);
			assert cell.width >= 1 && cell.height >= 1 && cell.lineThickness >= 1;
			assert cell.topToBaseline >= 1 && cell.topToBaseline <= cell.height;
			const forceWidth: float32 = (cell.width as float32) / dpl;
			assert Math.abs(forceWidth * dpl - (cell.width as float32)) < 0.001;
			const advance = glyphAdvance(face, glyphIndex(face, "W".code), size * dpl);
			assert Math.abs((cell.width as float32) - advance) <= 1.5;
		}
	}
	assert spriteCellFor(f, 14.0 * 1.25).width == 17;
	assert spriteCellFor(f, 14.0 * 1.25).height == 21;
}
