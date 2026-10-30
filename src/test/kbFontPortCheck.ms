import { FIXTURE_NAMES, FIXTURE_HEX } from "./sfntPortFixtures";
import { COLOUR_FIXTURE_NAMES, COLOUR_FIXTURE_HEX } from "./colourFaceFixtures";
import { kbFontDigestOf } from "./kbFontDigest";
import { KB_FONT_PINS } from "./kbFontPins";

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

function pinOf(name: string): string[] {
	for (const pin of KB_FONT_PINS) {
		const parts = pin.split(" ");
		if (parts[0] == name) { return parts; }
	}
	return [name, "unpinned", "-"];
}

function pinned(name: string): string {
	return pinOf(name)[1];
}

function skipsOf(name: string): int32[] {
	let skips: int32[] = [];
	const list = pinOf(name)[2];
	if (list != "-") {
		for (const part of list.split(",")) { skips.push(parseInt(part) as int32); }
	}
	return skips;
}

function check(names: string[], hexes: string[]): int32 {
	let bad: int32 = 0;
	for (let f: int32 = 0; f < (hexes.length as int32); f++) {
		const got = kbFontDigestOf(decode(hexes[f]), skipsOf(names[f]));
		if (`${got}` != pinned(names[f])) {
			bad++;
			console.log(`DIFFERS ${names[f]}: ${got} vs ${pinned(names[f])}`);
		}
	}
	return bad;
}

test "the kb font port reproduces the digests recorded from the C over the byte fixtures" {
	assert FIXTURE_NAMES.length == FIXTURE_HEX.length;
	assert COLOUR_FIXTURE_NAMES.length == COLOUR_FIXTURE_HEX.length;
	assert KB_FONT_PINS.length >= FIXTURE_NAMES.length + COLOUR_FIXTURE_NAMES.length;
	const bad = check(FIXTURE_NAMES, FIXTURE_HEX) + check(COLOUR_FIXTURE_NAMES, COLOUR_FIXTURE_HEX);
	assert bad == 0;
}

when (js) {
} else {
	import { readDir } from "std/fs";
	import { sfntSourceRead, sfntSourceSize } from "../void2d/sfntSource";

	function fontFiles(): string[] {
		let files: string[] = ["assets/font.ttf"];
		for (const dir of ["tests/fonts/", "tests/fonts/cmap/"]) {
			let names: string[] = readDir(dir);
			names.sort();
			for (const name of names) {
				if (name.endsWith(".ttf") || name.endsWith(".otf") || name.endsWith(".ttc")) {
					files.push(dir + name);
				}
			}
		}
		return files;
	}

	function readBytes(path: string): uint8[] {
		const size = sfntSourceSize(path);
		if (size < 0) { throw new Error(`cannot read ${path}`); }
		const bytes: uint8[] = new Array<uint8>(size as int32);
		if (size > 0 && !sfntSourceRead(path, 0, bytes)) { throw new Error(`cannot read ${path}`); }
		return bytes;
	}

	test "the kb font port reproduces the digests recorded from the C over the repo font files" {
		let bad: int32 = 0;
		for (const path of fontFiles()) {
			const got = kbFontDigestOf(readBytes(path), skipsOf(path));
			if (`${got}` != pinned(path)) {
				bad++;
				console.log(`DIFFERS ${path}: ${got} vs ${pinned(path)}`);
			}
		}
		assert bad == 0;
	}
}
