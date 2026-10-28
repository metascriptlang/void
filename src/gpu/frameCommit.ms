// The frame's end after the door's submit, the same on every target: the commit hook, the
// present hook's begin edge, the target's present, the present hook's end edge. The layers above
// the door register their hooks here, so the door imports none of them.

import { presentFrame } from "./framePresent";

function noCommit(): void {}
function noPresent(begin: int32): void {}

let commitHook: () => void = noCommit;
let presentHook: (begin: int32) => void = noPresent;

export function setCommitHook(hook: () => void): void { commitHook = hook; }
export function setPresentHook(hook: (begin: int32) => void): void { presentHook = hook; }

export function frameEndAround(present: () => void): void {
	commitHook();
	presentHook(1);
	present();
	presentHook(0);
}

export function frameEnd(): void { frameEndAround(presentFrame); }
