import { appWindowScriptDigest, appWindowScriptOps, appWindowScriptRun } from "./appWindowPortScript";

// FNV-1a digests of the transcripts of seeds 1 to 8, 400 ops each, recorded from the C
// appWindow.c before the port replaced it: its shell build (the iOS and Android stand-ins and
// voidMobile*) and its window-driver build. Mobile seed 8 prints the default title, re-pinned
// when appWindow.c's default became "Void" (73eddd80); one line differs from the C transcript.
const MOBILE_PINS: string[] = [
	"3598159361",
	"3144506974",
	"570629940",
	"1092669951",
	"2360007723",
	"1656989209",
	"1092655958",
	"2941399967",
];
const DESKTOP_PINS: string[] = [
	"883842619",
	"927674001",
	"1606448609",
	"3613943196",
	"3871716161",
	"2411256681",
	"2908228779",
	"1974093507",
];

function differing(pins: string[], mobile: boolean): int32 {
	let bad: int32 = 0;
	for (let i: int32 = 0; i < pins.length; i++) {
		const got = appWindowScriptDigest(appWindowScriptRun(appWindowScriptOps(i + 1, 400, mobile), mobile));
		if (got != pins[i]) {
			bad++;
			console.log(`DIFFERS ${mobile ? "mobile" : "desktop"} seed ${i + 1}: ${got} vs ${pins[i]}`);
		}
	}
	return bad;
}

test "the shells' window half reproduces the transcripts recorded from the C" {
	assert differing(MOBILE_PINS, true) == 0;
}

test "a window driver's window half reproduces the transcripts recorded from the C" {
	assert differing(DESKTOP_PINS, false) == 0;
}

function count(lines: string[], part: string): int32 {
	let found: int32 = 0;
	for (const line of lines) {
		if (line.includes(part)) { found++; }
	}
	return found;
}

test "an event read outside the handler and an over-long title are refused by name" {
	const lines = appWindowScriptRun(appWindowScriptOps(1, 400, false), false);
	assert count(lines, "FAIL voidEventType: read outside the event handler voidSetEventHandler registered") > 0;
	assert count(lines, "FAIL voidSetWindowTitle: the title is 256 bytes; at most 255 fit") > 0;
	assert count(lines, "FAIL voidIsFullscreen: the window does not exist yet; call it from the event handler or after init") > 0;
}

test "a quit request is recorded and a touch past the end is refused by name" {
	const lines = appWindowScriptRun(appWindowScriptOps(2, 400, false), false);
	assert count(lines, "quit 1") > 0;
	assert count(lines, "H touch past the end FAIL voidEventTouchX(") > 0;
}
