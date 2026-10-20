// Void — browser host-view entry: each view clears to its own colour. The page starts and stops
// views itself: Module.voidStart(canvas) starts one and returns its stop (docs/EMBED.md "Web").

import { embedRegister, currentView } from "../sokol/gpu";
import { beginScreenPassWith, endPass, commit } from "../gpu/door";

let clears: Vec<float32> = [0.9, 0.4, 0.1];

function init(): void {
	if (clears.length == 3) {
		clears.push(0.1);
		clears.push(0.4);
		clears.push(0.9);
	}
}

function frame(): void {
	const at: int32 = (currentView() & 1) == 1 ? 0 : 3;
	beginScreenPassWith(clears[at], clears[at + 1], clears[at + 2], 1.0);
	endPass();
	commit();
}

embedRegister(init, frame);
