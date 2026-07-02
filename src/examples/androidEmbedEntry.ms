// Void — Android RN embed entry. Registers renderer2d's init2d/frame2d; the host (Kotlin
// SurfaceView via JNI) owns the window surface + Choreographer render loop. No driver, no
// main: MsMain (called once from JNI) runs this top-level to register, then the host drives
// voidEmbedInit(ANativeWindow) + voidEmbedFrame.

import { init2d, frame2d } from "./renderer2d";
import { voidOnMessage } from "../void2d/message";

@include("bridge.h");
extern function voidEmbedRegister(init: () => void, frame: () => void): void;

// Host (React-Native) messages arrive here; game logic hooks in via voidOnMessage.
function onMsg(m: string): void {}

function registerVoid(): void {
	voidEmbedRegister(init2d, frame2d);
	voidOnMessage(onMsg);
}

registerVoid();
