import {
	FaceError,
	FaceSummary,
	SfntError,
	loadFace,
	peekFace,
	summaryCovers,
	syntheticFace,
	glyphIndex,
	faceHeights,
} from "./face";
import { graphemeProperty } from "./grapheme";

export enum FontStyle { Normal, Italic }

export enum SizeAdjust { None, IcWidth, ExHeight, CapHeight, LineHeight }

export struct FontFeature {
	tag: string;
	value: int32;
}

export struct Font {
	family: string;
	weight: int32;
	style: FontStyle;
	features: FontFeature[];
	fallbacks: string[];
	sizeAdjust: SizeAdjust;
}

export type FontId = distinct int32;
export const DEFAULT_FONT: FontId = 0 as FontId;

export enum FontError {
	NoFamily,
	NoFallbackFamily,
	NeedsShaper,
	NotLoaded,
	BadFeatureTag,
}

export enum Presentation {
	Default,
	Text,
	Emoji,
	Any,
}

export struct CodepointFace {
	face: int32;
	scale: float32;
}

const DEFAULT_PATH: string = "assets/font.ttf";
const DEFAULT_FAMILY: string = "Inter";
const NO_FACE: int32 = -1;
const NOT_LOADED: int32 = -1;
const LOAD_FAILED: int32 = -2;
const BOLD_WEIGHT: int32 = 600;
const PRIMARY_SLOT: int32 = -1;
const FONT_SHIFT: uint64 = 40;
const MODE_SHIFT: uint64 = 32;

struct RegisteredFace {
	path: string;
	family: string;
	weight: int32;
	style: FontStyle;
}

struct LoadedPath {
	path: string;
	face: Result<int32, FaceError>;
}

struct PeekedPath {
	path: string;
	summary: Result<FaceSummary, SfntError>;
}

struct Synthetic {
	base: int32;
	bold: boolean;
	italic: boolean;
	face: int32;
}

struct FontEntry {
	face: int32;
	path: string;
	kern: boolean;
	sizeAdjust: SizeAdjust;
	described: boolean;
	description: Font;
}

struct Fallback {
	font: FontId;
	path: string;
	bold: boolean;
	italic: boolean;
	face: int32;
	scale: float32;
}

let registered: Vec<RegisteredFace> = [];
let loadedPaths: Vec<LoadedPath> = [];
let peekedPaths: Vec<PeekedPath> = [];
let synthetics: Vec<Synthetic> = [];
let fonts: Vec<FontEntry> = [];
let fallbacks: Vec<Fallback> = [];
let resolved: Map<uint64, int32> = new Map<uint64, int32>();
let fallbackLoads: int32 = 0;
let coverageProbes: int32 = 0;

function faceAtPath(path: string): Result<int32, FaceError> {
	for (let i: int32 = 0; i < (loadedPaths.length as int32); i++) {
		if (loadedPaths[i].path.equals(path)) { return loadedPaths[i].face; }
	}
	const face = loadFace(path);
	loadedPaths.push({ path: path, face: face });
	return face;
}

function summaryAtPath(path: string): Result<FaceSummary, SfntError> {
	for (let i: int32 = 0; i < (peekedPaths.length as int32); i++) {
		if (peekedPaths[i].path.equals(path)) { return peekedPaths[i].summary; }
	}
	const summary = peekFace(path);
	peekedPaths.push({ path: path, summary: summary });
	return summary;
}

function coversAtPath(path: string, codepoint: int32): boolean {
	for (let i: int32 = 0; i < (loadedPaths.length as int32); i++) {
		if (loadedPaths[i].path.equals(path) && loadedPaths[i].face.ok) {
			return glyphIndex(loadedPaths[i].face.value, codepoint) != 0;
		}
	}
	const summary = summaryAtPath(path);
	return summary.ok && summaryCovers(summary.value, codepoint);
}

function styled(face: int32, bold: boolean, italic: boolean): Result<int32, FaceError> {
	if (!bold && !italic) { return Result.ok(face); }
	for (const s of synthetics) {
		if (s.base == face && s.bold == bold && s.italic == italic) { return Result.ok(s.face); }
	}
	const synthetic: int32 = try syntheticFace(face, bold, italic);
	synthetics.push({ base: face, bold: bold, italic: italic, face: synthetic });
	return Result.ok(synthetic);
}

function styledAt(path: string, bold: boolean, italic: boolean): Result<int32, FaceError> {
	const face: int32 = try faceAtPath(path);
	return styled(face, bold, italic);
}

function plainFont(face: int32, path: string): FontEntry {
	return {
		face: face,
		path: path,
		kern: true,
		sizeAdjust: SizeAdjust.None,
		described: false,
		description: {
			family: "",
			weight: 0,
			style: FontStyle.Normal,
			features: [],
			fallbacks: [],
			sizeAdjust: SizeAdjust.None,
		},
	};
}

function ensureDefaultFont(): void {
	if ((fonts.length as int32) > 0) { return; }
	registered.push({
		path: DEFAULT_PATH,
		family: DEFAULT_FAMILY,
		weight: 400,
		style: FontStyle.Normal,
	});
	const loaded = faceAtPath(DEFAULT_PATH);
	if (!loaded.ok) {
		console.log(
			`void2d: the default font ${DEFAULT_PATH} did not load ` +
			`(${loaded.error.toString()}); text in it draws nothing`,
		);
		fonts.push(plainFont(NO_FACE, DEFAULT_PATH));
		return;
	}
	fonts.push(plainFont(loaded.value, DEFAULT_PATH));
}

export function registerFace(path: string, family: string, weight: int32, style: FontStyle): void {
	ensureDefaultFont();
	registered.push({ path: path, family: family, weight: weight, style: style });
}

export function addFont(path: string): Result<FontId, FontError> {
	ensureDefaultFont();
	const face = faceAtPath(path);
	if (!face.ok) { return Result.err(FontError.NotLoaded); }
	fonts.push(plainFont(face.value, path));
	return Result.ok(((fonts.length as int32) - 1) as FontId);
}

function weightRank(desired: int32, weight: int32): int32 {
	if (desired >= 400 && desired <= 500) {
		if (weight >= desired && weight <= 500) { return weight - desired; }
		if (weight < desired) { return 1000 + desired - weight; }
		return 2000 + weight - 500;
	}
	if (desired < 400) {
		if (weight <= desired) { return desired - weight; }
		return 1000 + weight - desired;
	}
	if (weight >= desired) { return weight - desired; }
	return 1000 + desired - weight;
}

function bestFace(family: string, weight: int32, style: FontStyle): Result<int32, FontError> {
	let styleMatches: boolean = false;
	for (const r of registered) {
		if (r.family.equals(family) && r.style == style) { styleMatches = true; }
	}
	let best: int32 = -1;
	let bestRank: int32 = 0;
	for (let i = 0; i < (registered.length as int32); i++) {
		const r = registered[i];
		if (!r.family.equals(family) || (styleMatches && r.style != style)) { continue; }
		const rank: int32 = weightRank(weight, r.weight);
		if (best < 0 || rank < bestRank) {
			best = i;
			bestRank = rank;
		}
	}
	return best < 0 ? Result.err(FontError.NoFamily) : Result.ok(best);
}

function needsBold(this font: Font, match: int32): boolean {
	return font.weight >= BOLD_WEIGHT && registered[match].weight < BOLD_WEIGHT;
}

function needsItalic(this font: Font, match: int32): boolean {
	return font.style == FontStyle.Italic && registered[match].style != FontStyle.Italic;
}

function sameStrings(a: Readonly<Span<string>>, b: Readonly<Span<string>>): boolean {
	if (a.length != b.length) { return false; }
	for (let i = 0; i < (a.length as int32); i++) {
		if (!a[i].equals(b[i])) { return false; }
	}
	return true;
}

function sameAs(this a: Font, b: Font): boolean {
	if (!a.family.equals(b.family) || a.weight != b.weight || a.style != b.style) { return false; }
	if (a.sizeAdjust != b.sizeAdjust) { return false; }
	if (a.features.length != b.features.length) { return false; }
	if (!sameStrings(a.fallbacks, b.fallbacks)) { return false; }
	for (let i = 0; i < (a.features.length as int32); i++) {
		const left: FontFeature = a.features[i];
		const right: FontFeature = b.features[i];
		if (!left.tag.equals(right.tag) || left.value != right.value) { return false; }
	}
	return true;
}

function isFeatureTag(tag: string): boolean {
	if (tag.length != 4) { return false; }
	for (let i: int32 = 0; i < 4; i++) {
		const c: int32 = tag.charCodeAt(i) as int32;
		if (c < 0x20 || c > 0x7e) { return false; }
	}
	return true;
}

export function resolveFont(font: Font): Result<FontId, FontError> {
	ensureDefaultFont();
	for (let i = 0; i < (fonts.length as int32); i++) {
		if (fonts[i].described && fonts[i].description.sameAs(font)) {
			return Result.ok(i as FontId);
		}
	}
	let kern: boolean = true;
	for (const feature of font.features) {
		if (feature.tag.equals("kern")) {
			kern = feature.value != 0;
			continue;
		}
		when (voidShaper) {
			if (!isFeatureTag(feature.tag)) {
				console.log(
					`void2d: font feature "${feature.tag}" is not four printable ASCII ` +
					`characters; font "${font.family}" is refused`,
				);
				return Result.err(FontError.BadFeatureTag);
			}
		} else {
			console.log(
				`void2d: font feature "${feature.tag}" needs the shaper module, built with ` +
				`-d:voidShaper; font "${font.family}" is refused`,
			);
			return Result.err(FontError.NeedsShaper);
		}
	}
	const best = bestFace(font.family, font.weight, font.style);
	if (!best.ok) {
		console.log(
			`void2d: no face is registered for family "${font.family}"; the font is refused`,
		);
		return Result.err(best.error);
	}
	const primary: int32 = best.value;
	let fallbackMatches: Vec<int32> = new Array(0);
	for (const family of font.fallbacks) {
		const matched = bestFace(family, font.weight, font.style);
		if (!matched.ok) {
			console.log(
				`void2d: no face is registered for fallback family "${family}"; ` +
				`font "${font.family}" is refused`,
			);
			return Result.err(FontError.NoFallbackFamily);
		}
		fallbackMatches.push(matched.value);
	}
	const face = styledAt(
		registered[primary].path,
		font.needsBold(primary),
		font.needsItalic(primary),
	);
	if (!face.ok) {
		console.log(
			`void2d: ${registered[primary].path} did not load (${face.error.toString()}); ` +
			`font "${font.family}" is refused`,
		);
		return Result.err(FontError.NotLoaded);
	}
	const id: FontId = (fonts.length as int32) as FontId;
	const features: FontFeature[] = [];
	for (const feature of font.features) { features.push(feature); }
	const fallbackFamilies: string[] = [];
	for (const family of font.fallbacks) { fallbackFamilies.push(family); }
	fonts.push({
		face: face.value,
		path: registered[primary].path,
		kern: kern,
		sizeAdjust: font.sizeAdjust,
		described: true,
		description: { ...font, features: features, fallbacks: fallbackFamilies },
	});
	for (const m of fallbackMatches) {
		fallbacks.push({
			font: id,
			path: registered[m].path,
			bold: font.needsBold(m),
			italic: font.needsItalic(m),
			face: NOT_LOADED,
			scale: 1.0,
		});
	}
	resolved = new Map<uint64, int32>();
	return Result.ok(id);
}

export function addFallbackFont(font: FontId, path: string): void {
	fallbacks.push({
		font: font,
		path: path,
		bold: false,
		italic: false,
		face: NOT_LOADED,
		scale: 1.0,
	});
	resolved = new Map<uint64, int32>();
}

function fontIndex(font: FontId): int32 {
	ensureDefaultFont();
	const index: int32 = font as int32;
	if (index < 0 || index >= (fonts.length as int32)) {
		console.log(`void2d: font id ${index} was not made by addFont or resolveFont`);
		unreachable;
	}
	return index;
}

export function fontFace(font: FontId): int32 {
	return fonts[fontIndex(font)].face;
}

export function fontFeatures(font: FontId): FontFeature[] {
	return fonts[fontIndex(font)].description.features;
}

export function fontKerns(font: FontId): boolean {
	return fonts[fontIndex(font)].kern;
}

export function fallbackFacesLoaded(): int32 {
	return fallbackLoads;
}

export function fallbackProbes(): int32 {
	return coverageProbes;
}

function adjustedScale(primary: int32, fallback: int32, adjust: SizeAdjust): float32 {
	if (adjust == SizeAdjust.None) { return 1.0; }
	const p = faceHeights(primary);
	const f = faceHeights(fallback);
	if (adjust == SizeAdjust.IcWidth && f.icWidth > 0.0) { return p.icWidthEstimate / f.icWidth; }
	if ((adjust == SizeAdjust.IcWidth || adjust == SizeAdjust.ExHeight) && f.exHeight > 0.0) {
		return p.exHeightEstimate / f.exHeight;
	}
	if (adjust != SizeAdjust.LineHeight && f.capHeight > 0.0) {
		return p.capHeightEstimate / f.capHeight;
	}
	if (f.lineHeight <= 0.0 || p.lineHeight <= 0.0) {
		console.log(
			`void2d: face ${fallback} or ${primary} has no line height, so the fallback ` +
			`cannot be size-adjusted; it keeps the primary size`,
		);
		return 1.0;
	}
	return p.lineHeight / f.lineHeight;
}

function fallbackFace(index: int32): int32 {
	if (fallbacks[index].face == NOT_LOADED) {
		const face = styledAt(
			fallbacks[index].path, fallbacks[index].bold, fallbacks[index].italic,
		);
		fallbackLoads = fallbackLoads + 1;
		if (!face.ok) {
			console.log(
				`void2d: fallback font ${fallbacks[index].path} did not load ` +
				`(${face.error.toString()}); it is skipped`,
			);
			fallbacks[index].face = LOAD_FAILED;
		} else {
			fallbacks[index].face = face.value;
			const primary: int32 = fontFace(fallbacks[index].font);
			fallbacks[index].scale = adjustedScale(
				primary,
				face.value,
				fonts[fontIndex(fallbacks[index].font)].sizeAdjust,
			);
		}
	}
	return fallbacks[index].face;
}

function presentationOfPath(path: string): Presentation {
	const summary = summaryAtPath(path);
	if (summary.ok && (summary.value.colourBitmap || summary.value.colourLayers)) {
		return Presentation.Emoji;
	}
	return Presentation.Text;
}

function wantedPresentation(mode: Presentation, codepoint: int32): Presentation {
	if (mode != Presentation.Default) { return mode; }
	return graphemeProperty(codepoint).emojiPresentation ? Presentation.Emoji : Presentation.Text;
}

function fallbackUsable(index: int32): boolean {
	if (fallbacks[index].face == LOAD_FAILED) { return false; }
	const summary = summaryAtPath(fallbacks[index].path);
	if (!summary.ok || summary.value.drawable) { return true; }
	console.log(
		`void2d: fallback font ${fallbacks[index].path} holds colour glyphs but no outlines, ` +
		`and the colour emoji module (-d:voidColourEmoji) is not built; it is skipped`,
	);
	fallbacks[index].face = LOAD_FAILED;
	return false;
}

function fallbackAnswers(
	font: FontId, index: int32, codepoint: int32, exact: boolean, want: Presentation,
): boolean {
	if (fallbacks[index].font != font || !fallbackUsable(index)) { return false; }
	if (!coversAtPath(fallbacks[index].path, codepoint)) { return false; }
	return !exact || presentationOfPath(fallbacks[index].path) == want;
}

function primaryAnswers(
	font: FontId, codepoint: int32, mode: Presentation, want: Presentation,
): boolean {
	if (glyphIndex(fontFace(font), codepoint) == 0) { return false; }
	if (mode == Presentation.Default) { return true; }
	return presentationOfPath(fonts[fontIndex(font)].path) == want;
}

export function faceSlotFor(font: FontId, codepoint: int32, mode: Presentation): int32 {
	const key: uint64 = (((font as int32) as uint64) << FONT_SHIFT) |
		(((mode as int32) as uint64) << MODE_SHIFT) | (codepoint as uint64);
	const hit = resolved.get(key);
	if (hit.present) { return hit.value; }
	coverageProbes = coverageProbes + 1;
	const want: Presentation = wantedPresentation(mode, codepoint);
	let slot: int32 = PRIMARY_SLOT;
	let found: boolean = false;
	if (mode != Presentation.Any) {
		found = primaryAnswers(font, codepoint, mode, want);
		for (let i = 0; !found && i < (fallbacks.length as int32); i++) {
			if (fallbackAnswers(font, i, codepoint, true, want)) {
				slot = i;
				found = true;
			}
		}
	}
	if (!found && glyphIndex(fontFace(font), codepoint) != 0) { found = true; }
	for (let i = 0; !found && i < (fallbacks.length as int32); i++) {
		if (fallbackAnswers(font, i, codepoint, false, want)) {
			slot = i;
			found = true;
		}
	}
	resolved.set(key, slot);
	return slot;
}

function forgetResolved(font: FontId): void {
	const owner: uint64 = (font as int32) as uint64;
	for (const key of resolved.keys()) {
		if ((key >> FONT_SHIFT) == owner) { resolved.delete(key); }
	}
}

export function codepointFaceFor(
	font: FontId, codepoint: int32, mode: Presentation,
): CodepointFace {
	while (true) {
		const slot: int32 = faceSlotFor(font, codepoint, mode);
		if (slot == PRIMARY_SLOT) { return { face: fontFace(font), scale: 1.0 }; }
		const face: int32 = fallbackFace(slot);
		if (face < 0) {
			forgetResolved(font);
			continue;
		}
		if (glyphIndex(face, codepoint) == 0) {
			console.log(
				`void2d: the summary of ${fallbacks[slot].path} covers ` +
				`U+${codepoint.toString(16)} but its loaded face ${face} has no glyph, ` +
				`though both choose the cmap subtable as stb_truetype does`,
			);
			unreachable;
		}
		return { face: face, scale: fallbacks[slot].scale };
	}
}

export function codepointFace(font: FontId, codepoint: int32): CodepointFace {
	return codepointFaceFor(font, codepoint, Presentation.Default);
}

export function faceForCodepoint(font: FontId, codepoint: int32): int32 {
	return codepointFace(font, codepoint).face;
}
