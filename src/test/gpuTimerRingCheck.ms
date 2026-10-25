import { timerWriteSlot, timerReadSlot, timerReadFrame } from "../gpu/gpuTimer.ms";

function ringHolds(ring: int32): boolean {
	for (let frame: int64 = 0; frame < 40; frame++) {
		const written = timerWriteSlot(frame, ring);
		const read = timerReadSlot(frame, ring);
		if (written < 0 || written >= ring) { return false; }
		if (timerReadFrame(frame, ring) != frame - ((ring - 1) as int64)) { return false; }
		if (timerReadFrame(frame, ring) >= 0 && timerWriteSlot(timerReadFrame(frame, ring), ring) != read) { return false; }
		if (read == written || read != timerWriteSlot(frame + 1, ring)) { return false; }
	}
	return true;
}

test "the slot read at frame F is the one frame F - N + 1 wrote, and the next frame overwrites it, for a ring of 3" {
	assert ringHolds(3);
	assert timerReadSlot(5, 3) == 0 && timerReadFrame(5, 3) == 3 && timerWriteSlot(3, 3) == 0;
}

test "the same holds for rings of 2 and 4, and the lag is N - 1 frames" {
	assert ringHolds(2);
	assert ringHolds(4);
	assert timerReadFrame(9, 2) == 8 && timerReadSlot(9, 2) == 0;
	assert timerReadFrame(9, 4) == 6 && timerReadSlot(9, 4) == 2 && timerWriteSlot(6, 4) == 2;
}
