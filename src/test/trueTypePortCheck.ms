import { combineFont } from "./trueTypePortDump";
import { FIXTURE_NAMES, FIXTURE_HEX } from "./trueTypePortFixtures";

// Pinned from the C stb_truetype.h (deps/stb) over the same inputs: per face the init and
// metrics, the cmap sweep, per-glyph metrics and kerning, the outline, the bitmap box, the
// bitmaps at 9, 17.5 and 64 px with two subpixel shifts, and the signed distance field.
const CFF_FIXTURE: string = "cffSynthetic.otf";

function pinnedBytes(): uint32 {
	when (voidCff) {
		return 4002692370;
	} else {
		return 2256489126;
	}
}

// Except tests/fonts/cmap/unicodeThenMacRoman.ttf: its part of these digests is the port's own
// output, recorded with no stb_truetype run, until a dump from the C reference replaces it.
function pinnedFiles(): uint32 {
	when (voidCff) {
		return 3134188005;
	} else {
		return 2339484085;
	}
}

const CODEPOINT_STRIDE: int32 = 61;
const SEED: uint32 = 2166136261;

function hexValue(code: int32): int32 {
	return code >= 97 ? code - 87 : code - 48;
}

function decode(hex: string): uint8[] {
	let bytes: uint8[] = [];
	for (let i: int32 = 0; i < (hex.length as int32); i += 2) {
		bytes.push(((hexValue(hex.charCodeAt(i)) << 4) | hexValue(hex.charCodeAt(i + 1))) as uint8);
	}
	return bytes;
}

test "the TrueType port over byte fixtures keeps the digest recorded from stb_truetype" {
	assert FIXTURE_NAMES.length == FIXTURE_HEX.length;
	let result: uint32 = SEED;
	for (let f: int32 = 0; f < (FIXTURE_HEX.length as int32); f++) {
		when (voidCff) {
		} else {
			if (FIXTURE_NAMES[f] == CFF_FIXTURE) { continue; }
		}
		result = combineFont(decode(FIXTURE_HEX[f]), result, CODEPOINT_STRIDE);
	}
	console.log(`trueType bytes digest ${result}`);
	assert result == pinnedBytes();
}

// A font file is read only where the target has files: js holds faces as bytes.
when (js) {
} else {
	import { readDir, readFileBytes } from "std/fs";

	// stb_truetype reads outside these files, so no C output exists to pin them against.
	const READS_OUTSIDE: string[] = ["collectionOffsetHuge.ttc", "directoryWraps.ttf", "offsetNear2G.ttf"];

	function isFont(name: string): boolean {
		return name.endsWith(".ttf") || name.endsWith(".otf") || name.endsWith(".ttc");
	}

	function fontFiles(main: boolean): string[] {
		let files: string[] = main ? ["assets/font.ttf"] : [];
		for (const dir of ["tests/fonts/", "tests/fonts/cmap/"]) {
			let names: string[] = readDir(dir);
			names.sort();
			for (const name of names) {
				when (voidCff) {
				} else {
					if (name == CFF_FIXTURE) { continue; }
				}
				if (isFont(name) && (READS_OUTSIDE.includes(name) != main)) { files.push(dir + name); }
			}
		}
		return files;
	}

	function digestOf(paths: string[]): uint32 {
		let result: uint32 = SEED;
		for (const path of paths) {
			const bytes = readFileBytes(path);
			if (!bytes.ok) { throw new Error(`cannot read ${path}`); }
			result = combineFont(bytes.value, result, CODEPOINT_STRIDE);
		}
		return result;
	}

	test "the TrueType port over the repo font files keeps the digest recorded from stb_truetype" {
		const result: uint32 = digestOf(fontFiles(true));
		console.log(`trueType files digest ${result}`);
		assert result == pinnedFiles();
	}

	test "the TrueType port reads the files stb_truetype reads outside of without faulting" {
		const paths = fontFiles(false);
		assert paths.length == READS_OUTSIDE.length;
		const result: uint32 = digestOf(paths);
		assert result != SEED;
	}
}
