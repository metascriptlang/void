export enum ShapeDirection {
	Unknown,
	Ltr,
	Rtl,
}

export struct ShapedGlyph {
	glyph: int32;
	advanceX: int32;
	advanceY: int32;
	offsetX: int32;
	offsetY: int32;
	index: int32;
	codepoint: int32;
	direction: ShapeDirection;
	run: int32;
}

when (voidShaper) {
	import { FaceBytes, glyphFaceBytes } from "./glyph";
	import { KbFontBoundsError } from "./kb/blob";
	import { KbBreak, kbBreakBegin, KB_JAPANESE_LINE_BREAK_STYLE_NORMAL } from "./kb/break";
	import {
		KbShapeContext,
		kbGlyphIteratorNext,
		kbShapeBegin,
		kbShapeBeginManualRuns,
		kbShapeCodepointWithUserId,
		kbShapeEnd,
		kbShapeEndManualRuns,
		kbShapeGetShapeCodepoint,
		kbShapeManualBreak,
		kbShapeNextManualRun,
		kbShapePopFeature,
		kbShapePushFeature,
		kbShapePushFont,
		kbShapeRun,
	} from "./kb/context";
	import { KbFont, kbFontFromMemory, kbFontIsValid } from "./kb/font";
	import { kbZeroGlyph } from "./kb/glyph";
	import { KB_LANGUAGE_DONT_KNOW } from "./kb/languages";
	import { KB_BREAK_FLAG_SCRIPT } from "./kb/shapeTables";

	when (macos || ios) {
		import { void2dPlatformShape } from "./platformFace.h";
		import { platformInfo, platformOpen, postScriptName } from "./glyph/platform";
		import { getFontOffsetForIndex } from "./trueType";
		import { findTable } from "./trueType/fontInfo";
	}

	const NO_FACE: int32 = -1;
	const BAD_FONT: int32 = -2;
	const ENGINE_ERROR: int32 = -4;
	const NOT_OPEN: int32 = -5;
	const ALREADY_OPEN: int32 = -6;
	const BAD_TAG: int32 = -7;
	const TOO_MANY_FEATURES: int32 = -8;
	const CT_OVERFLOW: int32 = -9;
	const CT_SUBSTITUTED: int32 = -10;
	const CT_FAILED: int32 = -11;
	const MAX_FEATURES: int32 = 32;

	class ShapeFont {
		readonly bytes: FaceBytes;
		readonly font: KbFont;
		context: KbShapeContext;
		platform: Ptr<void> | null = null;

		constructor(bytes: FaceBytes, font: KbFont) {
			this.bytes = bytes;
			this.font = font;
			this.context = freshContext(font);
		}
	}

	function freshContext(font: KbFont): KbShapeContext {
		const context = new KbShapeContext();
		kbShapePushFont(context, font, []);
		return context;
	}

	let fonts: ShapeFont[] = [];
	let refusedBytes: FaceBytes[] = [];
	let currentFont: ShapeFont | null = null;
	let passOpen: boolean = false;
	let nextIndex: int32 = 0;
	let features: uint32[] = [];
	let shaped: ShapedGlyph[] = [];
	let forcedDirection: uint32 = 0;
	let input: int32[] = [];
	let inputBreak: boolean[] = [];
	let breakNext: boolean = false;

	function shapeStatus(code: int32, what: string): int32 {
		if (code >= 0) { return code; }
		const reason: string = match (code) {
			-1 => "the face is not loaded",
			-2 => "the shaper refused the font",
			-4 => "the shaper reported an error",
			-5 => "no shaping pass is open",
			-6 => "a shaping pass is already open",
			-7 => "a feature tag is four printable ASCII characters",
			-8 => "more than 32 feature overrides in one pass",
			-9 => "CoreText returned more glyphs than the run can hold",
			-10 => "CoreText substituted another font for the face",
			-11 => "CoreText did not shape the run",
			_ => "unknown status",
		};
		console.log(`void2d shaper: ${what}: ${reason} (${code})`);
		unreachable;
	}

	function morxPlatform(bytes: FaceBytes): Ptr<void> | null {
		when (macos || ios) {
			const data = bytes.data;
			const start: int32 = getFontOffsetForIndex(data, 0);
			if (start < 0 || findTable(data, start, "morx") == 0 || findTable(data, start, "GSUB") != 0) {
				return null;
			}
			const table = platformInfo(data, start);
			const name: string = postScriptName(data, start);
			if (table == null || name == "") { return null; }
			return platformOpen(null, data, name, table.glyphCount, table.unitsPerEm);
		} else {
			return null;
		}
	}

	function fontFor(bytes: FaceBytes): ShapeFont | null {
		for (const entry of fonts) {
			if (entry.bytes === bytes) { return entry; }
		}
		for (const refused of refusedBytes) {
			if (refused === bytes) { return null; }
		}
		const font = kbFontFromMemory(bytes.data[0..bytes.data.length], 0);
		if (!kbFontIsValid(font)) {
			refusedBytes.push(bytes);
			return null;
		}
		const entry = new ShapeFont(bytes, font);
		entry.platform = morxPlatform(bytes);
		fonts.push(entry);
		return entry;
	}

	function closeShape(font: ShapeFont): void {
		for (let i = (features.length as int32) - 1; i >= 0; i--) {
			kbShapePopFeature(font.context, features[i]);
		}
		features = [];
		passOpen = false;
		forcedDirection = 0;
	}

	function discardContext(font: ShapeFont): int32 {
		font.context = freshContext(font.font);
		features = [];
		passOpen = false;
		forcedDirection = 0;
		shaped = [];
		return ENGINE_ERROR;
	}

	function engineFailure(e: Error, font: ShapeFont): int32 {
		if (!(e instanceof KbFontBoundsError)) { throw e; }
		return discardContext(font);
	}

	function openShape(face: int32, direction: uint32, forced: boolean): int32 {
		if (passOpen) { return ALREADY_OPEN; }
		const bytes = glyphFaceBytes(face);
		if (bytes == null) { return NO_FACE; }
		let found: ShapeFont | null = null;
		try {
			found = fontFor(bytes);
		} catch (e) {
			if (!(e instanceof KbFontBoundsError)) { throw e; }
			return ENGINE_ERROR;
		}
		if (found == null) { return BAD_FONT; }
		currentFont = found;
		if (found.platform == null) {
			kbShapeBegin(found.context, direction, KB_LANGUAGE_DONT_KNOW);
		}
		shaped = [];
		nextIndex = 0;
		input = [];
		inputBreak = [];
		breakNext = false;
		forcedDirection = forced ? direction : 0;
		passOpen = true;
		return 0;
	}

	function beginPass(face: int32, direction: ShapeDirection): int32 {
		if (direction == ShapeDirection.Unknown) { return openShape(face, 0, false); }
		return openShape(face, (direction as int32) as uint32, true);
	}

	function featureTagFits(tag: string): boolean {
		if (tag.byteLength < 4) { return false; }
		for (let i: int32 = 0; i < 4; i++) {
			if (tag.byteAt(i) == 0) { return false; }
		}
		return tag.byteLength == 4 || tag.byteAt(4) == 0;
	}

	function featureCode(tag: string, value: int32): int32 {
		const font = currentFont;
		if (!passOpen || font == null) { return NOT_OPEN; }
		if (font.platform != null) { return 0; }
		if (!featureTagFits(tag)) { return BAD_TAG; }
		if ((features.length as int32) == MAX_FEATURES) { return TOO_MANY_FEATURES; }
		let id: uint32 = 0;
		for (let i: int32 = 3; i >= 0; i--) {
			const byte: int32 = tag.byteAt(i);
			if (byte > 0x7e) { return BAD_TAG; }
			id = (id << 8) | (byte as uint32);
		}
		kbShapePushFeature(font.context, id, value);
		features.push(id);
		return 0;
	}

	function codepointCode(codepoint: int32): int32 {
		const font = currentFont;
		if (!passOpen || font == null) { return NOT_OPEN; }
		if (forcedDirection != 0 || font.platform != null) {
			input.push(codepoint);
			inputBreak.push(breakNext);
			breakNext = false;
			return 0;
		}
		try {
			kbShapeCodepointWithUserId(font.context, codepoint, nextIndex);
		} catch (e) {
			return engineFailure(e, font);
		}
		nextIndex++;
		return 0;
	}

	function breakCode(): int32 {
		const font = currentFont;
		if (!passOpen || font == null) { return NOT_OPEN; }
		if (forcedDirection != 0 || font.platform != null) {
			breakNext = true;
			return 0;
		}
		try {
			kbShapeManualBreak(font.context);
		} catch (e) {
			return engineFailure(e, font);
		}
		return 0;
	}

	function feedForced(context: KbShapeContext): void {
		const count = input.length as int32;
		let starts: boolean[] = [];
		let scripts: uint32[] = [];
		for (let i: int32 = 0; i < count; i++) {
			starts.push(false);
			scripts.push(0);
		}
		let state = kbBreakBegin(forcedDirection, KB_JAPANESE_LINE_BREAK_STYLE_NORMAL, 0);
		let found: KbBreak = {
			position: 0,
			flags: 0,
			direction: 0,
			paragraphDirection: 0,
			script: 0,
		};
		for (let i: int32 = 0; i < count; i++) {
			state.kbBreakAddCodepoint(input[i], 1, i == count - 1);
			while (state.kbBreakNext(out found)) {
				if ((found.flags & KB_BREAK_FLAG_SCRIPT) != 0 && found.position >= 0 &&
					found.position < count) {
					starts[found.position] = true;
					scripts[found.position] = found.script;
				}
			}
		}
		kbShapeBeginManualRuns(context);
		let script: uint32 = 0;
		for (let i: int32 = 0; i < count; i++) {
			if (starts[i]) { script = scripts[i]; }
			if (i == 0 || starts[i] || inputBreak[i]) {
				kbShapeNextManualRun(context, forcedDirection, script);
			}
			kbShapeCodepointWithUserId(context, input[i], i);
		}
		kbShapeEndManualRuns(context);
	}

	function endCoreText(platform: Ptr<void>): int32 {
		when (macos || ios) {
			const count = input.length as int32;
			const direction: ShapeDirection =
				forcedDirection == 2 ? ShapeDirection.Rtl : ShapeDirection.Ltr;
			let from: int32 = 0;
			let segment: int32 = 0;
			while (from < count) {
				let to: int32 = from + 1;
				while (to < count && !inputBreak[to]) { to++; }
				const n: int32 = to - from;
				const capacity: int32 = 2 * n + 8;
				let cps: int32[] = new Array<int32>(n);
				for (let k: int32 = 0; k < n; k++) {
					const value: int32 = input[from + k];
					cps[k] = value;
				}
				let glyphs: int32[] = new Array<int32>(capacity);
				let advances: int32[] = new Array<int32>(capacity);
				let offsetsX: int32[] = new Array<int32>(capacity);
				let offsetsY: int32[] = new Array<int32>(capacity);
				let indices: int32[] = new Array<int32>(capacity);
				const total: int32 = void2dPlatformShape(
					platform, cps[0], n, capacity, (glyphs as Span<int32>) as Ptr<int32>,
					(advances as Span<int32>) as Ptr<int32>, (offsetsX as Span<int32>) as Ptr<int32>,
					(offsetsY as Span<int32>) as Ptr<int32>, (indices as Span<int32>) as Ptr<int32>,
				);
				if (total < 0) {
					return total == -1 ? CT_OVERFLOW : total == -2 ? CT_SUBSTITUTED : CT_FAILED;
				}
				for (let j: int32 = 0; j < total; j++) {
					const at: int32 = direction == ShapeDirection.Rtl ? total - 1 - j : j;
					const origin: int32 = from + indices[at];
					shaped.push({
						glyph: glyphs[at],
						advanceX: advances[at],
						advanceY: 0,
						offsetX: offsetsX[at],
						offsetY: offsetsY[at],
						index: origin,
						codepoint: input[origin],
						direction,
						run: segment,
					});
				}
				segment++;
				from = to;
			}
			return 0;
		} else {
			unreachable;
		}
	}

	function endCode(): int32 {
		const font = currentFont;
		if (!passOpen || font == null) { return NOT_OPEN; }
		const platform = font.platform;
		if (platform != null) {
			const status: int32 = endCoreText(platform);
			if (status < 0) {
				closeShape(font);
				return status;
			}
			closeShape(font);
			return shaped.length as int32;
		}
		try {
			if (forcedDirection != 0) { feedForced(font.context); }
			kbShapeEnd(font.context);
			let runIndex: int32 = 0;
			let glyph = kbZeroGlyph();
			let run = kbShapeRun(font.context);
			while (run !== null) {
				const direction = (run.direction as int32) as ShapeDirection;
				while (kbGlyphIteratorNext(run.glyphs, out glyph)) {
					const source = kbShapeGetShapeCodepoint(
						font.context,
						glyph.userIdOrCodepointIndex,
					);
					if (source === null) { return discardContext(font); }
					shaped.push({
						glyph: glyph.id as int32,
						advanceX: glyph.advanceX,
						advanceY: glyph.advanceY,
						offsetX: glyph.offsetX,
						offsetY: glyph.offsetY,
						index: source.userId,
						codepoint: glyph.codepoint as int32,
						direction,
						run: runIndex,
					});
				}
				runIndex++;
				run = kbShapeRun(font.context);
			}
		} catch (e) {
			return engineFailure(e, font);
		}
		closeShape(font);
		return shaped.length as int32;
	}

	export function shaperCompiled(): boolean { return true; }

	export function shaperBegin(face: int32, direction: ShapeDirection): void {
		shapeStatus(beginPass(face, direction), "begin");
	}

	let refusedFaces: Vec<int32> = new Array(0);

	export function shaperTryBegin(face: int32, direction: ShapeDirection): boolean {
		const status: int32 = beginPass(face, direction);
		if (status == NO_FACE) { return false; }
		if (status == BAD_FONT) {
			for (const seen of refusedFaces) {
				if (seen == face) { return false; }
			}
			refusedFaces.push(face);
			console.log(
				`void2d shaper: face ${face} is refused by the shaper, its text is laid out ` +
				`without ligatures, GPOS or cluster handling`,
			);
			return false;
		}
		shapeStatus(status, "begin");
		return true;
	}

	export function shaperFeature(tag: string, value: int32): void {
		shapeStatus(featureCode(tag, value), `feature ${tag}`);
	}

	export function shaperCodepoint(codepoint: int32): void {
		shapeStatus(codepointCode(codepoint), "codepoint");
	}

	export function shaperBreak(): void {
		shapeStatus(breakCode(), "break");
	}

	export function shaperEnd(): int32 {
		return shapeStatus(endCode(), "end");
	}

	export function shaperGlyph(index: int32): ShapedGlyph {
		const count = shaped.length as int32;
		if (index < 0 || index >= count) {
			console.log(`void2d shaper: glyph ${index} is outside the ${count} of the last pass`);
			unreachable;
		}
		return shaped[index];
	}
} else {
	function shaperOff(what: string): void {
		console.log(`void2d shaper: ${what} needs the shaper module; build with -d:voidShaper`);
		unreachable;
	}

	export function shaperCompiled(): boolean { return false; }

	export function shaperBegin(face: int32, direction: ShapeDirection): void {
		shaperOff("shaperBegin");
	}

	export function shaperTryBegin(face: int32, direction: ShapeDirection): boolean {
		shaperOff("shaperTryBegin");
		return false;
	}

	export function shaperFeature(tag: string, value: int32): void {
		shaperOff("shaperFeature");
	}

	export function shaperCodepoint(codepoint: int32): void {
		shaperOff("shaperCodepoint");
	}

	export function shaperBreak(): void {
		shaperOff("shaperBreak");
	}

	export function shaperEnd(): int32 {
		shaperOff("shaperEnd");
		return 0;
	}

	export function shaperGlyph(index: int32): ShapedGlyph {
		shaperOff("shaperGlyph");
		unreachable;
	}
}
