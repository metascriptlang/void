// Void — browser host-view entry: each view clears to a colour whose last channel only init writes.
// The page starts and stops views itself: Module.voidStart(canvas) starts one and returns its stop
// (docs/EMBED.md "Web").

import { embedRegister, setViewSampleCount } from "../sokol/gpu";
import { beginScreenPassWith, endPass, commit } from "../gpu/door";

let clear: Vec<float32> = [0.1, 0.4];

function init(): void {
	if (clear.length == 2) clear.push(0.9);
}

function frame(): void {
	beginScreenPassWith(clear[0], clear[1], clear[2], 1.0);
	endPass();
	commit();
}

setViewSampleCount(4);
embedRegister(init, frame);
