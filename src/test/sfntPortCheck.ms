import { sfntPeek, sfntPeekBytes, sfntCovers, sfntSequence, sfntFlags, SfntError } from "../void2d/sfnt";
import { FIXTURE_NAMES, FIXTURE_HEX } from "./sfntPortFixtures";

// BEGIN PEEK API
function errorCode(e: SfntError): int32 {
	return match (e) {
		SfntError.Unreadable => -1,
		SfntError.NotAnSfnt => -2,
		SfntError.OutOfMemory => -3,
	};
}

function peekBytesCode(bytes: uint8[], index: int32): int32 {
	const r = sfntPeekBytes(bytes, index);
	if (r.ok) { return r.value; }
	return errorCode(r.error);
}

function peekPathCode(path: string, index: int32): int32 {
	const r = sfntPeek(path, index);
	if (r.ok) { return r.value; }
	return errorCode(r.error);
}

function coversAt(id: int32, codepoint: int32): boolean {
	return sfntCovers(id, codepoint);
}

function sequenceAt(id: int32, codepoint: int32, selector: int32): int32 {
	return sfntSequence(id, codepoint, selector) as int32;
}

function flagsOf(id: int32): int32 {
	return sfntFlags(id);
}
// END PEEK API

// Pinned from the C peek (sfnt.c at 1ac6d6a8, removed with this port) over the same inputs.
const PINNED_BYTES: uint32 = 499806152;
const PINNED_FILES: uint32 = 488470174;

const PROBES: int32[] = [
	0x0, 0x20, 0x41, 0x42, 0x43, 0x61, 0xFF, 0x100, 0x2700, 0x2702, 0x2703, 0x3042, 0xFFFF,
	0x10000, 0x1F600, 0x1F601, 0x1F602, 0x10FFFF,
];
const SELECTORS: int32[] = [0xFE0E, 0xFE0F, 0xE0100, 0x41];

let digest: uint32 = 2166136261;

function mix(value: int32): void {
	digest = (digest ^ (value as uint32)) * 16777619;
}

function survey(id: int32, stride: int32): void {
	mix(flagsOf(id));
	for (const cp of PROBES) {
		mix(coversAt(id, cp) ? 1 : 0);
		for (const selector of SELECTORS) { mix(sequenceAt(id, cp, selector)); }
	}
	for (let cp: int32 = 0; cp <= 0x10FFFF; cp += stride) { mix(coversAt(id, cp) ? 1 : 0); }
}

function peekedBytes(bytes: uint8[], stride: int32): void {
	for (let index: int32 = 0; index < 3; index++) {
		const code = peekBytesCode(bytes, index);
		mix(code);
		if (code >= 0) { survey(code, stride); }
	}
}

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

function digestOfBytes(): uint32 {
	digest = 2166136261;
	for (let f: int32 = 0; f < (FIXTURE_HEX.length as int32); f++) {
		const bytes = decode(FIXTURE_HEX[f]);
		const length: int32 = bytes.length as int32;
		mix(length);
		peekedBytes(bytes, 1);
		const step: int32 = length <= 400 ? 1 : 31;
		for (let cut: int32 = 0; cut < length; cut += step) {
			peekedBytes(bytes.slice(0, cut), 509);
		}
		for (let at: int32 = 0; at < length; at += 5) {
			const was: uint8 = bytes[at];
			bytes[at] = was ^ 0xFF;
			peekedBytes(bytes, 509);
			bytes[at] = was;
		}
	}
	return digest;
}

test "the sfnt peek over byte fixtures, truncations and flips keeps its pinned digest" {
	assert FIXTURE_NAMES.length == FIXTURE_HEX.length;
	const result: uint32 = digestOfBytes();
	console.log(`sfnt bytes digest ${result}`);
	assert result == PINNED_BYTES;
}

// A font file is read only where the target has files: js holds faces as bytes.
when (js) {
} else {
	import { readDir } from "std/fs";

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
		files.push("tests/fonts/cmap/missing.ttf");
		return files;
	}

	function digestOfFiles(): uint32 {
		digest = 2166136261;
		for (const path of fontFiles()) {
			for (let index: int32 = -1; index < 4; index++) {
				const code = peekPathCode(path, index);
				mix(code);
				if (code >= 0) { survey(code, 17); }
			}
		}
		return digest;
	}

	test "the sfnt peek over the repo font files keeps its pinned digest" {
		const result: uint32 = digestOfFiles();
		console.log(`sfnt files digest ${result}`);
		assert result == PINNED_FILES;
	}
}
