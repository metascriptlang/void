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
	colourBuilt,
	platformFacesBuilt,
	FaceBytesError,
	holdFaceBytes,
} from "./face";
import { graphemeProperty } from "./grapheme";
import { fontBytesFind } from "./fontBytes";

when (voidSprites) {
	import { spriteFace, spriteCell, SpriteCell } from "./face";
	import { SPRITE_FIRST_CODEPOINT, spriteIndex } from "./spriteGlyph";
}

when (emcc) {
	import { browserFace } from "./face";
}

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

export struct FaceQuery {
	codepoint: int32;
	presentation: Presentation;
	weight: int32;
	style: FontStyle;
}

export struct FaceCandidate {
	path: string;
	index: int32;
}

export type FaceResolver = (query: FaceQuery) => FaceCandidate[];

export type FontId = distinct int32;
@delegate export function `==`(this a: FontId, b: FontId): boolean;
export const DEFAULT_FONT: FontId = 0 as FontId;

export enum FontError {
	NoFamily,
	NoFallbackFamily,
	NeedsShaper,
	NotLoaded,
	BadFeatureTag,
	NameHeld,
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
const NO_DISCOVERY: int32 = -1;
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
	collectionIndex: int32;
	face: Result<int32, FaceError>;
}

struct PeekedPath {
	path: string;
	collectionIndex: int32;
	summary: Result<FaceSummary, SfntError>;
}

struct Synthetic {
	base: int32;
	bold: boolean;
	italic: boolean;
	face: int32;
}

when (voidSprites) {
	struct SpriteOf {
		base: int32;
		face: int32;
	}
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
	collectionIndex: int32;
	bold: boolean;
	italic: boolean;
	face: int32;
	scale: float32;
}

let registered: Vec<RegisteredFace> = [];
let loadedPaths: Vec<LoadedPath> = [];
let peekedPaths: Vec<PeekedPath> = [];
let heldNames: Vec<string> = [];
let synthetics: Vec<Synthetic> = [];
when (voidSprites) {
	let spriteFaces: Vec<SpriteOf> = [];
}
let fonts: Vec<FontEntry> = [];
let fallbacks: Vec<Fallback> = [];
when (emcc) {
	const BROWSER_SLOT: int32 = -2;
	const BROWSER_FAMILY: string = "sans-serif";

	struct BrowserFallback {
		font: FontId;
		face: int32;
		scale: float32;
	}

	let browserFallbacks: Vec<BrowserFallback> = [];
}
let resolved: Map<uint64, int32> = new Map<uint64, int32>();
let faceResolver: FaceResolver | null = null;
let discovered: Map<uint64, int32> = new Map<uint64, int32>();
let discoveries: Vec<FaceCandidate> = [];
let discoveryAsks: int32 = 0;
let fallbackLoads: int32 = 0;
let coverageProbes: int32 = 0;
let defaultLoads: int32 = 0;

function faceAtPath(path: string, collectionIndex: int32 = 0): Result<int32, FaceError> {
	for (let i: int32 = 0; i < (loadedPaths.length as int32); i++) {
		if (loadedPaths[i].path.equals(path) && loadedPaths[i].collectionIndex == collectionIndex) {
			return loadedPaths[i].face;
		}
	}
	const face = loadFace(path, collectionIndex);
	loadedPaths.push({ path: path, collectionIndex: collectionIndex, face: face });
	return face;
}

function summaryAtPath(path: string, collectionIndex: int32 = 0): Result<FaceSummary, SfntError> {
	for (let i: int32 = 0; i < (peekedPaths.length as int32); i++) {
		if (peekedPaths[i].path.equals(path) && peekedPaths[i].collectionIndex == collectionIndex) {
			return peekedPaths[i].summary;
		}
	}
	const summary = peekFace(path, collectionIndex);
	peekedPaths.push({ path: path, collectionIndex: collectionIndex, summary: summary });
	return summary;
}

function coversAtPath(path: string, collectionIndex: int32, codepoint: int32): boolean {
	for (let i: int32 = 0; i < (loadedPaths.length as int32); i++) {
		if (loadedPaths[i].path.equals(path) && loadedPaths[i].collectionIndex == collectionIndex &&
			loadedPaths[i].face.ok) {
			return glyphIndex(loadedPaths[i].face.value, codepoint) != 0;
		}
	}
	const summary = summaryAtPath(path, collectionIndex);
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

when (voidSprites) {
	function spriteFaceOf(base: int32): int32 {
		for (const s of spriteFaces) {
			if (s.base == base) { return s.face; }
		}
		const made = spriteFace(base);
		if (!made.ok) {
			console.log(
				`void2d: face ${base} cannot back the sprite glyphs (${made.error.toString()}); ` +
				`its box drawing and block characters come from the font`,
			);
			spriteFaces.push({ base: base, face: NO_FACE });
			return NO_FACE;
		}
		spriteFaces.push({ base: base, face: made.value });
		return made.value;
	}

	export function spriteCellFor(font: FontId, sizePx: float32): SpriteCell {
		const base: int32 = fontFace(font);
		const sprite: int32 = base < 0 ? NO_FACE : spriteFaceOf(base);
		if (sprite < 0) {
			console.log(`void2d: font ${font as int32} has no face to measure a sprite cell from`);
			unreachable;
		}
		return spriteCell(sprite, sizePx);
	}
}

function styledAt(
	path: string, collectionIndex: int32, bold: boolean, italic: boolean,
): Result<int32, FaceError> {
	const face: int32 = try faceAtPath(path, collectionIndex);
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
	fonts.push(plainFont(NOT_LOADED, DEFAULT_PATH));
}

function defaultFace(): int32 {
	when (js) {
		if (fontBytesFind(DEFAULT_PATH) < 0) {
			defaultLoads = defaultLoads + 1;
			console.log(
				`void2d: js has no font file for the default font ${DEFAULT_PATH}; ` +
				`supply its bytes with defaultFontBytes before any text reads it`,
			);
			return LOAD_FAILED;
		}
	}
	const loaded = faceAtPath(DEFAULT_PATH);
	defaultLoads = defaultLoads + 1;
	if (!loaded.ok) {
		console.log(
			`void2d: the default font ${DEFAULT_PATH} did not load ` +
			`(${loaded.error.toString()}); text in it draws nothing`,
		);
		return LOAD_FAILED;
	}
	return loaded.value;
}

export function registerFace(path: string, family: string, weight: int32, style: FontStyle): void {
	ensureDefaultFont();
	registered.push({ path: path, family: family, weight: weight, style: style });
}

function pathRead(path: string): boolean {
	for (const loaded of loadedPaths) { if (loaded.path.equals(path)) { return true; } }
	for (const peeked of peekedPaths) { if (peeked.path.equals(path)) { return true; } }
	return false;
}

function holdBytes(name: string, bytes: uint8[]): Result<void, FontError> {
	let known: boolean = false;
	for (const held of heldNames) { known = known || held.equals(name); }
	if (!known && pathRead(name)) { return Result.err(FontError.NameHeld); }
	const held = holdFaceBytes(name, bytes);
	if (held.ok) {
		if (!known) { heldNames.push(name); }
		return Result.ok(null);
	}
	if (held.error == FaceBytesError.NameHeld) { return Result.err(FontError.NameHeld); }
	return Result.err(FontError.NotLoaded);
}

// registerFace for a face given as bytes (an asset read from an APK); `name` stands for its path.
export function registerFaceBytes(
	name: string, bytes: uint8[], family: string, weight: int32, style: FontStyle,
): Result<void, FontError> {
	try holdBytes(name, bytes);
	registerFace(name, family, weight, style);
	return Result.ok(null);
}

// The default font's bytes, for an app whose assets have no file path; before any text reads it.
export function defaultFontBytes(bytes: uint8[]): Result<void, FontError> {
	return holdBytes(DEFAULT_PATH, bytes);
}

// addFont for a face given as bytes; `name` stands for its path.
export function addFontBytes(name: string, bytes: uint8[]): Result<FontId, FontError> {
	try holdBytes(name, bytes);
	return addFont(name);
}

export function addFont(path: string): Result<FontId, FontError> {
	ensureDefaultFont();
	const face = faceAtPath(path);
	if (!face.ok) {
		return Result.err(FontError.NotLoaded);
	}
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
		0,
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
			collectionIndex: 0,
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
		collectionIndex: 0,
		bold: false,
		italic: false,
		face: NOT_LOADED,
		scale: 1.0,
	});
	resolved = new Map<uint64, int32>();
}

export function setFaceResolver(resolver: FaceResolver | null): void {
	faceResolver = resolver;
	discovered = new Map<uint64, int32>();
	discoveries = [];
	resolved = new Map<uint64, int32>();
}

export function faceDiscoveryAsks(): int32 {
	return discoveryAsks;
}

function discoveredFace(font: FontId, codepoint: int32, want: Presentation): int32 {
	const resolver = faceResolver;
	if (resolver === null) { return NO_DISCOVERY; }
	const index: int32 = fontIndex(font);
	const described: boolean = fonts[index].described;
	const weight: int32 = described ? fonts[index].description.weight : 400;
	const style: FontStyle = described ? fonts[index].description.style : FontStyle.Normal;
	const key: uint64 = ((weight as uint64) << 32) | (((style as int32) as uint64) << 28) |
		(((want as int32) as uint64) << 24) | (codepoint as uint64);
	const hit = discovered.get(key);
	if (hit.present) { return hit.value; }
	discoveryAsks = discoveryAsks + 1;
	const answers = resolver({ codepoint: codepoint, presentation: want, weight: weight, style: style });
	let chosen: int32 = NO_DISCOVERY;
	for (let k: int32 = 0; k < (answers.length as int32); k++) {
		const path: string = answers[k].path;
		const collectionIndex: int32 = answers[k].index;
		if (drawableAt(path, collectionIndex) && coversAtPath(path, collectionIndex, codepoint) &&
			presentationOfPath(path, collectionIndex) == want && osOpens(path, collectionIndex)) {
			discoveries.push({ path: path, index: collectionIndex });
			chosen = (discoveries.length as int32) - 1;
			break;
		}
	}
	discovered.set(key, chosen);
	return chosen;
}

function discoveredSlot(font: FontId, codepoint: int32, want: Presentation): int32 {
	const found: int32 = discoveredFace(font, codepoint, want);
	if (found == NO_DISCOVERY) { return PRIMARY_SLOT; }
	const path: string = discoveries[found].path;
	const collectionIndex: int32 = discoveries[found].index;
	for (let i: int32 = 0; i < (fallbacks.length as int32); i++) {
		if (fallbacks[i].font == font && fallbacks[i].path.equals(path) &&
			fallbacks[i].collectionIndex == collectionIndex) {
			return fallbackUsable(i) ? i : PRIMARY_SLOT;
		}
	}
	fallbacks.push({
		font: font, path: path, collectionIndex: collectionIndex,
		bold: false, italic: false, face: NOT_LOADED, scale: 1.0,
	});
	const slot: int32 = (fallbacks.length as int32) - 1;
	return fallbackUsable(slot) ? slot : PRIMARY_SLOT;
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

export function isFontFace(face: int32): boolean {
	for (let i = 0; i < (fonts.length as int32); i++) {
		if (fonts[i].face == face) { return true; }
	}
	return false;
}

export function fontFace(font: FontId): int32 {
	const index: int32 = fontIndex(font);
	if (fonts[index].face == NOT_LOADED) { fonts[index].face = defaultFace(); }
	return fonts[index].face;
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

export function defaultFaceLoads(): int32 {
	return defaultLoads;
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
			fallbacks[index].path, fallbacks[index].collectionIndex,
			fallbacks[index].bold, fallbacks[index].italic,
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

function presentationOfPath(path: string, collectionIndex: int32 = 0): Presentation {
	const summary = summaryAtPath(path, collectionIndex);
	if (summary.ok && (summary.value.colourBitmap || summary.value.colourLayers)) {
		return Presentation.Emoji;
	}
	return Presentation.Text;
}

function wantedPresentation(mode: Presentation, codepoint: int32): Presentation {
	if (mode != Presentation.Default) { return mode; }
	return graphemeProperty(codepoint).emojiPresentation ? Presentation.Emoji : Presentation.Text;
}

function drawableAt(path: string, collectionIndex: int32): boolean {
	const summary = summaryAtPath(path, collectionIndex);
	if (!summary.ok) { return false; }
	const colour: boolean = summary.value.colourBitmap || summary.value.colourLayers;
	return summary.value.drawable || (colour && colourBuilt()) ||
		(summary.value.osOutlines && platformFacesBuilt());
}

function osOpens(path: string, collectionIndex: int32): boolean {
	const summary = summaryAtPath(path, collectionIndex);
	if (!summary.ok || !summary.value.osOutlines || summary.value.drawable) { return true; }
	return faceAtPath(path, collectionIndex).ok;
}

function fallbackUsable(index: int32): boolean {
	if (fallbacks[index].face == LOAD_FAILED) { return false; }
	const path: string = fallbacks[index].path;
	const collectionIndex: int32 = fallbacks[index].collectionIndex;
	const summary = summaryAtPath(path, collectionIndex);
	if (!summary.ok || (drawableAt(path, collectionIndex) && osOpens(path, collectionIndex))) {
		return true;
	}
	const colour: boolean = summary.value.colourBitmap || summary.value.colourLayers;
	console.log(
		summary.value.osOutlines && platformFacesBuilt()
			? `void2d: fallback font ${path} has outlines only the OS draws, and the OS did not ` +
				`open it; it is skipped`
			: colour
			? `void2d: fallback font ${path} holds colour glyphs but no outlines, ` +
				`and the colour emoji module (-d:voidColourEmoji) is not built; it is skipped`
			: `void2d: fallback font ${path} has no outlines or colour glyphs Void can draw; ` +
				`it is skipped`,
	);
	fallbacks[index].face = LOAD_FAILED;
	return false;
}

when (emcc) {
	function browserFallback(font: FontId): int32 {
		for (let i: int32 = 0; i < (browserFallbacks.length as int32); i++) {
			if (browserFallbacks[i].font == font) { return i; }
		}
		const entry: FontEntry = fonts[fontIndex(font)];
		const weight: int32 = entry.described ? entry.description.weight : 400;
		const italic: boolean = entry.described && entry.description.style == FontStyle.Italic;
		const face = browserFace(`${italic ? "italic " : ""}${weight}`, BROWSER_FAMILY);
		if (!face.ok) {
			console.log(
				`void2d: the browser's ${BROWSER_FAMILY} face did not open ` +
				`(${face.error.toString()}); codepoints no loaded face covers stay undrawn`,
			);
			browserFallbacks.push({ font: font, face: LOAD_FAILED, scale: 1.0 });
		} else {
			browserFallbacks.push({
				font: font,
				face: face.value,
				scale: adjustedScale(fontFace(font), face.value, entry.sizeAdjust),
			});
		}
		return (browserFallbacks.length as int32) - 1;
	}

	function browserAnswers(font: FontId, codepoint: int32): boolean {
		const face: int32 = browserFallbacks[browserFallback(font)].face;
		return face >= 0 && glyphIndex(face, codepoint) != 0;
	}
}

function fallbackAnswers(
	font: FontId, index: int32, codepoint: int32, exact: boolean, want: Presentation,
): boolean {
	if (fallbacks[index].font != font || !fallbackUsable(index)) { return false; }
	const path: string = fallbacks[index].path;
	const collectionIndex: int32 = fallbacks[index].collectionIndex;
	if (!coversAtPath(path, collectionIndex, codepoint)) { return false; }
	return !exact || presentationOfPath(path, collectionIndex) == want;
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
		if (!found) {
			slot = discoveredSlot(font, codepoint, want);
			found = slot != PRIMARY_SLOT;
		}
		when (emcc) {
			if (!found && want == Presentation.Text && browserAnswers(font, codepoint)) {
				slot = BROWSER_SLOT;
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
	when (emcc) {
		if (!found && browserAnswers(font, codepoint)) {
			slot = BROWSER_SLOT;
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
	when (voidSprites) {
		if (codepoint >= SPRITE_FIRST_CODEPOINT && spriteIndex(codepoint) != 0) {
			const base: int32 = fontFace(font);
			const sprite: int32 = base < 0 ? NO_FACE : spriteFaceOf(base);
			if (sprite >= 0) { return { face: sprite, scale: 1.0 }; }
		}
	}
	while (true) {
		const slot: int32 = faceSlotFor(font, codepoint, mode);
		if (slot == PRIMARY_SLOT) { return { face: fontFace(font), scale: 1.0 }; }
		when (emcc) {
			if (slot == BROWSER_SLOT) {
				const browser: BrowserFallback = browserFallbacks[browserFallback(font)];
				return { face: browser.face, scale: browser.scale };
			}
		}
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
