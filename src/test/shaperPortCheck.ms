import { readDir } from "std/fs";
import { colourBuilt, holdFaceBytes, loadFace, syntheticFace } from "../void2d/face";
import { KB_CONFIG_FIXTURE_HEX } from "./kbConfigFixtures";
import { KB_LOOKUP_FIXTURE_HEX } from "./kbLookupFixtures";
import { shaperPortDigest } from "./shaperPortCorpus";
import { SHAPER_PORT_COLOUR_PINS, SHAPER_PORT_PINS } from "./shaperPortPins";

const PER_POOL: int32 = 4;

function pinnedIn(pins: string[], label: string): string {
	for (const pin of pins) {
		const parts = pin.split("|");
		if (parts[0] == label) { return parts[1]; }
	}
	return "unpinned";
}

function pinned(label: string): string {
	const found = pinnedIn(SHAPER_PORT_PINS, label);
	if (found != "unpinned" || !colourBuilt()) { return found; }
	return pinnedIn(SHAPER_PORT_COLOUR_PINS, label);
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

function fontFiles(dir: string): string[] {
	let files: string[] = [];
	let names: string[] = readDir(dir);
	names.sort();
	for (const name of names) {
		if (name.endsWith(".ttf") || name.endsWith(".otf") || name.endsWith(".ttc")) {
			files.push(dir + name);
		}
	}
	return files;
}

class Count {
	compared: int32 = 0;
	bad: int32 = 0;
}

function check(count: Count, label: string, face: int32): void {
	const got = `${shaperPortDigest(face, PER_POOL)}`;
	count.compared++;
	if (got != pinned(label)) {
		count.bad++;
		console.log(`DIFFERS ${label}: ${got} vs ${pinned(label)}`);
	}
}

test "shaper.ms reproduces the digests recorded from shaper.c over every face the repo loads" {
	const count = new Count();
	let files: string[] = ["assets/font.ttf"];
	for (const path of fontFiles("tests/fonts/")) { files.push(path); }
	for (const path of fontFiles("tests/fonts/cmap/")) { files.push(path); }
	for (const path of files) {
		for (let index: int32 = 0; index < (path.endsWith(".ttc") ? 3 : 1); index++) {
			const face: int32 = try loadFace(path, index) catch -1;
			if (face >= 0) { check(count, `${path}#${index}`, face); }
		}
	}
	const inter: int32 = try loadFace("assets/font.ttf") catch -1;
	check(count, "assets/font.ttf bold", try syntheticFace(inter, true, false) catch -1);
	const names: string[] = ["configFixture", "lookupFixture"];
	const hexes: string[] = [KB_CONFIG_FIXTURE_HEX, KB_LOOKUP_FIXTURE_HEX];
	for (let k: int32 = 0; k < 2; k++) {
		assert holdFaceBytes(names[k], decode(hexes[k])).ok;
		check(count, names[k], try loadFace(names[k]) catch -1);
	}
	assert count.bad == 0;
	const colourFaces = colourBuilt() ? (SHAPER_PORT_COLOUR_PINS.length as int32) : 0;
	assert count.compared == (SHAPER_PORT_PINS.length as int32) + colourFaces;
}
