// With no app event handler set, Escape quits the macOS window, as on the other window drivers; the
// key is a real NSEvent through the window, and the process must end by itself (exit 0).

@include("macWindowHost.h");
@compile("./macWindowHost.m", "-fobjc-arc");
extern function macHostKey(down: int32, keyCode: int32, chars: cstring, flags: uint32): void;

import { gfxSetup } from "../../src/sokol/gpu";
import { beginScreenPassWith, endPass, commit } from "../../src/gpu/door";
import { exit } from "std/process";

@include("../../src/sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;
extern function voidKeyDown(keycode: int32): int32;

const keyEscape: int32 = 256;
const giveUpFrames: int32 = 300;
let frames: int32 = 0;
let heldSeen: boolean = false;

function init(): void { gfxSetup(); }

function frame(): void {
	frames = frames + 1;
	beginScreenPassWith(0.1, 0.1, 0.15, 1.0);
	endPass();
	commit();
	if (frames === 30) {
		if (voidKeyDown(keyEscape) !== 0) { console.log("FAIL macOS escape: Escape reads as down before it is pressed"); exit(1); }
		macHostKey(1, 53, "\u001b", 0);
		heldSeen = voidKeyDown(keyEscape) !== 0;
		macHostKey(0, 53, "\u001b", 0);
		if (!heldSeen) { console.log("FAIL macOS escape: voidKeyDown never saw Escape"); exit(1); }
		console.log("PASS macOS escape: voidKeyDown saw Escape; the process must now end by itself (exit 0)");
	}
	if (frames > giveUpFrames) {
		console.log("FAIL macOS escape: the window is still open after Escape");
		exit(1);
	}
}

voidRun(320, 200, init, frame);
