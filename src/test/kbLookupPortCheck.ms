import { KB_LOOKUP_FIXTURE_HEX, KB_LOOKUP_WORDS } from "./kbLookupFixtures";
import { kbLookupDigestOfBytes } from "./kbLookupDigest";
import { kbLookupPinned } from "./kbLookupPins";

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

test "the kb lookup port reproduces the digest recorded from the C over the lookup fixture" {
	const got = kbLookupDigestOfBytes(decode(KB_LOOKUP_FIXTURE_HEX), 0, KB_LOOKUP_WORDS, 9, 16);
	assert `${got}` == kbLookupPinned("fixture");
}

when (js) {
} else {
	import { sfntSourceRead, sfntSourceSize } from "../void2d/sfntSource";
	import { KB_LOOKUP_PINS } from "./kbLookupPins";

	function readBytes(path: string): uint8[] {
		const size = sfntSourceSize(path);
		if (size < 0) { throw new Error(`cannot read ${path}`); }
		const bytes: uint8[] = new Array<uint8>(size as int32);
		if (size > 0 && !sfntSourceRead(path, 0, bytes)) { throw new Error(`cannot read ${path}`); }
		return bytes;
	}

	test "the kb lookup port reproduces the digests recorded from the C over the repo fonts" {
		let bad: int32 = 0;
		for (const pin of KB_LOOKUP_PINS) {
			const path = pin.split(" ")[0];
			if (path == "fixture") { continue; }
			const got = kbLookupDigestOfBytes(readBytes(path), 0, [], 3, 16);
			if (`${got}` != kbLookupPinned(path)) {
				bad++;
				console.log(`DIFFERS ${path}: ${got} vs ${kbLookupPinned(path)}`);
			}
		}
		assert bad == 0;
	}
}
