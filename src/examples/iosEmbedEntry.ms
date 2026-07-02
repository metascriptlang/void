// Void — iOS embed entry. No run-loop: registers lifecycle closures with the bridge;
// the host (React-Native VoidView driven by CADisplayLink) calls voidEmbedInit/voidEmbedFrame.

import { initIos, frameIos } from "./iosScene";
import { voidOnMessage } from "../void2d/message";

@include("bridge.h");
extern function voidEmbedRegister(init: () => void, frame: () => void): void;

// Host (React-Native) messages arrive here; game logic hooks in via voidOnMessage.
function onMsg(m: string): void {}

function main(): int32 {
	voidEmbedRegister(initIos, frameIos);
	voidOnMessage(onMsg);
	return 0;
}
