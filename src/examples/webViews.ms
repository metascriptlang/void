// Void — browser host-view entry: each view clears to its own colour. The page starts and stops
// views itself: Module.voidStart(canvas) starts one and returns its stop (docs/EMBED.md "Web").

import { embedRegister, currentView } from "../sokol/gpu";
import { beginScreenPassWith, endPass, commit } from "../gpu/door";

function init(): void {}

function frame(): void {
	const odd = (currentView() & 1) == 1;
	beginScreenPassWith(odd ? 0.9 : 0.1, 0.4, odd ? 0.1 : 0.9, 1.0);
	endPass();
	commit();
}

embedRegister(init, frame);
