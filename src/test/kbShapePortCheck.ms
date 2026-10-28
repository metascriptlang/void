import { KbFont, kbFontFromMemory, kbFontIsValid } from "../void2d/kb/font";
import { KB_CONFIG_FIXTURE_HEX } from "./kbConfigFixtures";
import { KB_LOOKUP_FIXTURE_HEX } from "./kbLookupFixtures";
import { kbShapeDigestOf } from "./kbShapeCorpus";
import { kbShapePinned } from "./kbShapePins";

const PER_POOL: int32 = 4;

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

function digestOfBytes(bytes: uint8[], fallback: KbFont): uint32 {
	const font = kbFontFromMemory(bytes[0..bytes.length], 0);
	if (!kbFontIsValid(font)) { return 0; }
	return kbShapeDigestOf(font, fallback, PER_POOL);
}

test "the kb shape context port reproduces the digest recorded from the C over the config fixture" {
	const lookup = decode(KB_LOOKUP_FIXTURE_HEX);
	const got = digestOfBytes(decode(KB_CONFIG_FIXTURE_HEX), kbFontFromMemory(lookup[0..lookup.length], 0));
	assert `${got}` == kbShapePinned("configFixture");
}

test "the kb shape context port reproduces the digest recorded from the C over the lookup fixture" {
	const config = decode(KB_CONFIG_FIXTURE_HEX);
	const got = digestOfBytes(decode(KB_LOOKUP_FIXTURE_HEX), kbFontFromMemory(config[0..config.length], 0));
	assert `${got}` == kbShapePinned("lookupFixture");
}

when (js) {
} else {
	import { sfntSourceRead, sfntSourceSize } from "../void2d/sfntSource";
	import { KB_SHAPE_PINS } from "./kbShapePins";

	function readBytes(path: string): uint8[] {
		const size = sfntSourceSize(path);
		if (size < 0) { throw new Error(`cannot read ${path}`); }
		const bytes: uint8[] = new Array<uint8>(size as int32);
		if (size > 0 && !sfntSourceRead(path, 0, bytes)) { throw new Error(`cannot read ${path}`); }
		return bytes;
	}

	test "the kb shape context port reproduces the digests recorded from the C over the repo fonts" {
		const asset = readBytes("assets/font.ttf");
		const fallback = kbFontFromMemory(asset[0..asset.length], 0);
		let bad: int32 = 0;
		for (const pin of KB_SHAPE_PINS) {
			const path = pin.split(" ")[0];
			if (path == "configFixture" || path == "lookupFixture") { continue; }
			const got = digestOfBytes(readBytes(path), fallback);
			if (`${got}` != kbShapePinned(path)) {
				bad++;
				console.log(`DIFFERS ${path}: ${got} vs ${kbShapePinned(path)}`);
			}
		}
		assert bad == 0;
	}
}
