import { kbFontFromMemory, kbFontIsValid } from "../void2d/kb/font";
import { KB_CONFIG_FIXTURE_HEX } from "./kbConfigFixtures";
import { KB_LOOKUP_FIXTURE_HEX } from "./kbLookupFixtures";
import { kbEngineDigestOf } from "./kbEngineCorpus";
import { kbEnginePinned } from "./kbEnginePins";

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

function digestOfBytes(bytes: uint8[]): uint32 {
	const font = kbFontFromMemory(bytes[0..bytes.length], 0);
	if (!kbFontIsValid(font)) { return 0; }
	return kbEngineDigestOf(font, PER_POOL);
}

test "the kb engine port reproduces the digest recorded from the C over the config fixture" {
	assert `${digestOfBytes(decode(KB_CONFIG_FIXTURE_HEX))}` == kbEnginePinned("configFixture");
}

test "the kb engine port reproduces the digest recorded from the C over the lookup fixture" {
	assert `${digestOfBytes(decode(KB_LOOKUP_FIXTURE_HEX))}` == kbEnginePinned("lookupFixture");
}

when (js) {
} else {
	import { sfntSourceRead, sfntSourceSize } from "../void2d/sfntSource";
	import { KB_ENGINE_PINS } from "./kbEnginePins";

	function readBytes(path: string): uint8[] {
		const size = sfntSourceSize(path);
		if (size < 0) { throw new Error(`cannot read ${path}`); }
		const bytes: uint8[] = new Array<uint8>(size as int32);
		if (size > 0 && !sfntSourceRead(path, 0, bytes)) { throw new Error(`cannot read ${path}`); }
		return bytes;
	}

	test "the kb engine port reproduces the digests recorded from the C over the repo fonts" {
		let bad: int32 = 0;
		for (const pin of KB_ENGINE_PINS) {
			const path = pin.split(" ")[0];
			if (path == "configFixture" || path == "lookupFixture") { continue; }
			const got = digestOfBytes(readBytes(path));
			if (`${got}` != kbEnginePinned(path)) {
				bad++;
				console.log(`DIFFERS ${path}: ${got} vs ${kbEnginePinned(path)}`);
			}
		}
		assert bad == 0;
	}
}
