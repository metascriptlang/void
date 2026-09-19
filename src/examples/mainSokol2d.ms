// Void — sokol native entry for the 2D batcher demo. Window/loop only.

import { init2d, frame2d } from "./renderer2d";

@include("../sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

// Ends with a top-level call, not a bare `function main()`: nothing calls main() on the
// installed msc (0.2.53) on Windows or under --os=emcc, so this entry used to build into a
// binary that exited at once and a wasm module with the renderer linked out — 48 KB for
// WebGPU against the 511 KB a working build produces. CODE-STYLE.md section 9 has the rule.
// voidRun does not return until the window closes, so the call is the whole entry.
function main(): int32 {
	voidRun(800, 600, init2d, frame2d);
	return 0;
}

main();
