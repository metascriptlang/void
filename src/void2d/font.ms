import { FaceError, loadFace, syntheticFace, glyphIndex, faceHeights } from "./face";

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

enum FontError {
	NoFamily,
	NoFallbackFamily,
	NeedsShaper,
	NotLoaded,
}

export struct CodepointFace {
	face: int32;
	scale: float32;
}

export const NO_FONT: int32 = -1;
const DEFAULT_PATH: string = "assets/font.ttf";
const DEFAULT_FAMILY: string = "Inter";
const NO_FACE: int32 = -1;
const NOT_LOADED: int32 = -1;
const LOAD_FAILED: int32 = -2;
const BOLD_WEIGHT: int32 = 600;
const PRIMARY_SLOT: int32 = -1;

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

struct Synthetic {
	base: int32;
	bold: boolean;
	italic: boolean;
	face: int32;
}

struct FontEntry {
	face: int32;
	kern: boolean;
	sizeAdjust: SizeAdjust;
	described: boolean;
	description: Font;
}

struct Fallback {
	font: int32;
	path: string;
	bold: boolean;
	italic: boolean;
	face: int32;
	scale: float32;
}

const registered: Vec<RegisteredFace> = [];
const loadedPaths: Vec<LoadedPath> = [];
const synthetics: Vec<Synthetic> = [];
const fonts: Vec<FontEntry> = [];
const fallbacks: Vec<Fallback> = [];
let resolved: Map<uint64, int32> = new Map<uint64, int32>();
let fallbackLoads: int32 = 0;
let coverageProbes: int32 = 0;

function faceAtPath(path: string): Result<int32, FaceError> {
	for (const loaded of loadedPaths) {
		if (loaded.path.equals(path)) { return loaded.face; }
	}
	const face = loadFace(path);
	loadedPaths.push({ path: path, face: face });
	return face;
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

function plainFont(face: int32): FontEntry {
	return {
		face: face,
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
		fonts.push(plainFont(NO_FACE));
		return;
	}
	fonts.push(plainFont(loaded.value));
}

export function registerFace(path: string, family: string, weight: int32, style: FontStyle): void {
	ensureDefaultFont();
	registered.push({ path: path, family: family, weight: weight, style: style });
}

export function addFont(path: string): int32 {
	ensureDefaultFont();
	const face = faceAtPath(path);
	if (!face.ok) { return NO_FONT; }
	fonts.push(plainFont(face.value));
	return (fonts.length as int32) - 1;
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

function sameStrings(a: Span<string>, b: Span<string>): boolean {
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

export function resolveFont(font: Font): int32 {
	return try resolve(font) catch NO_FONT;
}

function resolve(font: Font): Result<int32, FontError> {
	ensureDefaultFont();
	for (let i = 0; i < (fonts.length as int32); i++) {
		if (fonts[i].described && fonts[i].description.sameAs(font)) { return Result.ok(i); }
	}
	let kern: boolean = true;
	for (const feature of font.features) {
		if (!feature.tag.equals("kern")) {
			console.log(
				`void2d: font feature "${feature.tag}" needs the shaper, which lands at P6; ` +
				`font "${font.family}" is refused`,
			);
			return Result.err(FontError.NeedsShaper);
		}
		kern = feature.value != 0;
	}
	const best = bestFace(font.family, font.weight, font.style);
	if (!best.ok) {
		console.log(
			`void2d: no face is registered for family "${font.family}"; the font is refused`,
		);
		return Result.err(best.error);
	}
	const primary: int32 = best.value;
	const fallbackMatches: Vec<int32> = new Array(0);
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
	const id: int32 = fonts.length as int32;
	const features: FontFeature[] = [];
	for (const feature of font.features) { features.push(feature); }
	const fallbackFamilies: string[] = [];
	for (const family of font.fallbacks) { fallbackFamilies.push(family); }
	fonts.push({
		face: face.value,
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

export function addFallbackFont(font: int32, path: string): void {
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

export function fontFace(font: int32): int32 {
	ensureDefaultFont();
	if (font < 0 || font >= (fonts.length as int32)) { return fonts[0].face; }
	return fonts[font].face;
}

export function fontKerns(font: int32): boolean {
	ensureDefaultFont();
	if (font < 0 || font >= (fonts.length as int32)) { return true; }
	return fonts[font].kern;
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
		const entry: Fallback = fallbacks[index];
		const face = styledAt(entry.path, entry.bold, entry.italic);
		fallbackLoads = fallbackLoads + 1;
		if (!face.ok) {
			console.log(
				`void2d: fallback font ${entry.path} did not load ` +
				`(${face.error.toString()}); it is skipped`,
			);
			fallbacks[index].face = LOAD_FAILED;
		} else {
			fallbacks[index].face = face.value;
			const primary: int32 = fontFace(entry.font);
			fallbacks[index].scale = adjustedScale(
				primary,
				face.value,
				fonts[entry.font].sizeAdjust,
			);
		}
	}
	return fallbacks[index].face;
}

function codepointSlot(font: int32, codepoint: int32): int32 {
	const key: uint64 = ((font as uint64) << 32) | (codepoint as uint64);
	const hit = resolved.get(key);
	if (hit.present) { return hit.value; }
	coverageProbes = coverageProbes + 1;
	let slot: int32 = PRIMARY_SLOT;
	if (glyphIndex(fontFace(font), codepoint) == 0) {
		for (let i = 0; i < (fallbacks.length as int32); i++) {
			if (fallbacks[i].font != font) { continue; }
			const candidate: int32 = fallbackFace(i);
			if (candidate >= 0 && glyphIndex(candidate, codepoint) != 0) {
				slot = i;
				break;
			}
		}
	}
	resolved.set(key, slot);
	return slot;
}

export function codepointFace(font: int32, codepoint: int32): CodepointFace {
	const slot: int32 = codepointSlot(font, codepoint);
	if (slot == PRIMARY_SLOT) { return { face: fontFace(font), scale: 1.0 }; }
	return { face: fallbacks[slot].face, scale: fallbacks[slot].scale };
}

export function faceForCodepoint(font: int32, codepoint: int32): int32 {
	return codepointFace(font, codepoint).face;
}
