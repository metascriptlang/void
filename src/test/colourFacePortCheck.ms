import { COLOUR_FIXTURE_HEX, COLOUR_FIXTURE_NAMES } from "./colourFaceFixtures";
import { COLOUR_PINS } from "./colourFacePins";
import { Digest, digestCase, digestCompose, hex64, hexBytes } from "./colourFaceDigest";

function fixtureBytes(name: string): uint8[] {
	const parts = name.split(":");
	for (let i: int32 = 0; i < COLOUR_FIXTURE_NAMES.length; i++) {
		if (COLOUR_FIXTURE_NAMES[i] == parts[1]) { return hexBytes(COLOUR_FIXTURE_HEX[i]); }
	}
	throw new Error(`no colour fixture for pin ${name}`);
}

test "the colour face port reproduces the digests recorded from the C" {
	assert COLOUR_FIXTURE_NAMES.length == COLOUR_FIXTURE_HEX.length;
	assert COLOUR_PINS.length == 23;
	let bad: int32 = 0;
	for (const row of COLOUR_PINS) {
		const parts = row.split(" ");
		let got: string = "";
		if (parts[0] == "compose") {
			const d = new Digest();
			digestCompose(d);
			got = hex64(d.h);
		} else {
			got = hex64(digestCase(parts[0], fixtureBytes(parts[0])));
		}
		if (got != parts[1]) {
			bad++;
			console.log(`DIFFERS ${parts[0]}: ${got} vs ${parts[1]}`);
		}
	}
	assert bad == 0;
}
