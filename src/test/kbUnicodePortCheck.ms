import { KB_UNICODE_NAMES, kbUnicodeDigest } from "./kbUnicodeDigest";
import { KB_UNICODE_PINS } from "./kbUnicodePins";

test "the kb unicode lookups reproduce the digests recorded from the C" {
	assert KB_UNICODE_PINS.length == KB_UNICODE_NAMES.length;
	let bad: int32 = 0;
	for (let family: int32 = 0; family < KB_UNICODE_NAMES.length; family++) {
		const parts = KB_UNICODE_PINS[family].split(" ");
		assert parts[0] == KB_UNICODE_NAMES[family];
		const got = kbUnicodeDigest(family);
		if (`${got}` != parts[1]) {
			bad++;
			console.log(`DIFFERS ${parts[0]}: ${got} vs ${parts[1]}`);
		}
	}
	assert bad == 0;
}
