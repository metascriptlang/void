import { SVG_PINS } from "./svgMaskPins";
import { corpusEdgeCount, corpusFixtureCount } from "./svgCorpus";
import { corpusTotal, digestRange } from "./svgMaskDigest";
import { hex64 } from "./colourFaceDigest";

const GENERATED_CHUNK: int32 = 500;

test "the svg mask port reproduces the digests recorded from the C" {
	assert SVG_PINS.length == 9;
	const base = corpusFixtureCount() + corpusEdgeCount();
	let bad: int32 = 0;
	for (const row of SVG_PINS) {
		const parts = row.split(" ");
		const name = parts[0];
		let got: string = "";
		if (name == "fixtures") {
			got = hex64(digestRange(0, corpusFixtureCount(), false));
		} else if (name == "edges") {
			got = hex64(digestRange(corpusFixtureCount(), base, false));
		} else if (name == "skew") {
			got = hex64(digestRange(0, corpusTotal(), true));
		} else {
			const chunk = name.charCodeAt(3) - 48;
			const from = base + chunk * GENERATED_CHUNK;
			got = hex64(digestRange(from, from + GENERATED_CHUNK, false));
		}
		if (got != parts[1]) {
			bad++;
			console.log(`DIFFERS ${name}: ${got} vs ${parts[1]}`);
		}
	}
	assert bad == 0;
}
