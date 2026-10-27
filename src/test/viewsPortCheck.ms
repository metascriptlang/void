import { viewsScriptChurnOps, viewsScriptDigest, viewsScriptOps, viewsScriptRun } from "./viewsPortScript";

// FNV-1a digests of the transcripts of seeds 1 to 8 (odd seeds plain, even seeds churn), 500 ops
// each, with the generation limit at 3, recorded from the C views.c before the port replaced it.
const VIEWS_PINS: string[] = [
	"3301042456",
	"2243240927",
	"909664956",
	"2118374890",
	"264483876",
	"3967493600",
	"1793616059",
	"644053808",
];

test "the host views reproduce the transcripts recorded from the C" {
	let bad: int32 = 0;
	for (let i: int32 = 0; i < VIEWS_PINS.length; i++) {
		const seed = i + 1;
		const ops = seed % 2 == 0 ? viewsScriptChurnOps(seed, 500) : viewsScriptOps(seed, 500);
		const got = viewsScriptDigest(viewsScriptRun(ops, 3));
		if (got != VIEWS_PINS[i]) {
			bad++;
			console.log(`DIFFERS seed ${seed}: ${got} vs ${VIEWS_PINS[i]}`);
		}
	}
	assert bad == 0;
}

test "a view id is refused after its view is destroyed, and a full table says so" {
	const lines = viewsScriptRun(viewsScriptChurnOps(2, 500), 3);
	let destroyed = 0;
	let full = 0;
	for (const line of lines) {
		if (line.includes("was destroyed; a view id names one view only")) { destroyed++; }
		if (line.includes("all 16 views are in use or retired")) { full++; }
	}
	assert destroyed > 0;
	assert full > 0;
}
