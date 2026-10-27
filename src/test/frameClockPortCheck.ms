import { FrameClock } from "../void2d/frameClock";
import { PortModel, runScript, scriptDigest } from "./frameClockScript";

when (js) {
} else {
	import {
		COUNTER_DRAWS, COUNTER_UI_INSTANCES, COUNTER_SPRITE_INSTANCES, COUNTER_UPLOAD_BYTES,
		COUNTER_UPLOADS, COUNTER_COVERED_PIXELS, COUNTER_TARGET_PIXELS, COUNTER_OPAQUE_PIXELS,
		COUNTER_FRAME_PIXELS, VOID2D_COUNTER_SLOTS,
	} from "../void2d/frameClock";
	import {
		VOID_COUNTER_DRAWS, VOID_COUNTER_UI_INSTANCES, VOID_COUNTER_SPRITE_INSTANCES,
		VOID_COUNTER_UPLOAD_BYTES, VOID_COUNTER_UPLOADS, VOID_COUNTER_COVERED_PIXELS,
		VOID_COUNTER_TARGET_PIXELS, VOID_COUNTER_OPAQUE_PIXELS, VOID_COUNTER_FRAME_PIXELS,
	} from "../void2d/frameClock.h";

	test "the void2d counter slots agree with frameClock.h" {
		assert COUNTER_DRAWS == VOID_COUNTER_DRAWS;
		assert COUNTER_UI_INSTANCES == VOID_COUNTER_UI_INSTANCES;
		assert COUNTER_SPRITE_INSTANCES == VOID_COUNTER_SPRITE_INSTANCES;
		assert COUNTER_UPLOAD_BYTES == VOID_COUNTER_UPLOAD_BYTES;
		assert COUNTER_UPLOADS == VOID_COUNTER_UPLOADS;
		assert COUNTER_COVERED_PIXELS == VOID_COUNTER_COVERED_PIXELS;
		assert COUNTER_TARGET_PIXELS == VOID_COUNTER_TARGET_PIXELS;
		assert COUNTER_OPAQUE_PIXELS == VOID_COUNTER_OPAQUE_PIXELS;
		assert COUNTER_FRAME_PIXELS == VOID_COUNTER_FRAME_PIXELS;
		assert VOID2D_COUNTER_SLOTS == 9;
	}
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
