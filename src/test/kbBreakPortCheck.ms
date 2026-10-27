import { KB_BREAK_NAMES, kbBreakDigest, kbRepresentatives } from "./kbBreakDigest";
import { KB_BREAK_PINS } from "./kbBreakPins";

test "the kb break port reproduces the digests recorded from the C" {
	assert KB_BREAK_PINS.length == KB_BREAK_NAMES.length;
	const representatives = kbRepresentatives();
	let bad: int32 = 0;
	for (let family: int32 = 0; family < KB_BREAK_NAMES.length; family++) {
		const parts = KB_BREAK_PINS[family].split(" ");
		assert parts[0] == KB_BREAK_NAMES[family];
		const got = kbBreakDigest(family, representatives);
		if (`${got}` != parts[1]) {
			bad++;
			console.log(`DIFFERS ${parts[0]}: ${got} vs ${parts[1]}`);
		}
	}
	assert bad == 0;
}
