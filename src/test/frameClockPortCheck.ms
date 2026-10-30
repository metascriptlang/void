import { FrameClock } from "../void2d/frameClock";
import { PortModel, runScript, scriptDigest } from "./frameClockScript";

import {
	COUNTER_DRAWS, COUNTER_UI_INSTANCES, COUNTER_SPRITE_INSTANCES, COUNTER_UPLOAD_BYTES,
	COUNTER_UPLOADS, COUNTER_COVERED_PIXELS, COUNTER_TARGET_PIXELS, COUNTER_OPAQUE_PIXELS,
	COUNTER_FRAME_PIXELS, VOID2D_COUNTER_SLOTS,
} from "../void2d/frameClock";

test "the void2d counter slots are the nine the batcher fills, in order" {
	assert COUNTER_DRAWS == 0;
	assert COUNTER_UI_INSTANCES == 1;
	assert COUNTER_SPRITE_INSTANCES == 2;
	assert COUNTER_UPLOAD_BYTES == 3;
	assert COUNTER_UPLOADS == 4;
	assert COUNTER_COVERED_PIXELS == 5;
	assert COUNTER_TARGET_PIXELS == 6;
	assert COUNTER_OPAQUE_PIXELS == 7;
	assert COUNTER_FRAME_PIXELS == 8;
	assert VOID2D_COUNTER_SLOTS == 9;
}

// Digests of the C frameClock.c, recorded before that file was deleted: seeds 1 to 4, 3000 random
// calls each (begin, input, commit, present, consume, the two takes, the door's reading) under a
// scripted clock, with every getter read after every call. Each FNV-1a is 32 bits over the low
// then the high word of each observed value.
const CLOCK_PINS: uint32[] = [3508803685, 2437395315, 2028296215, 2070791446];

test "the frame clock port reproduces the digests recorded from the C" {
	let bad: int32 = 0;
	for (let i: int32 = 0; i < (CLOCK_PINS.length as int32); i++) {
		const got: uint32 = scriptDigest(runScript(new PortModel(), (i + 1) as uint32, 3000));
		if (got != CLOCK_PINS[i]) {
			bad++;
			console.log(`DIFFERS seed ${i + 1} ${got} vs ${CLOCK_PINS[i]}`);
		}
	}
	assert bad == 0;
}

test "the last frame mark and counter are in range" {
	const clock = new FrameClock();
	assert clock.mark(3) == 0;
	assert clock.counter(14) == 0;
}
