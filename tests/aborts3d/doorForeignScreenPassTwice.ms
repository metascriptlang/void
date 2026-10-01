// expect: gpu door: beginScreenPass with a pass already open; endPass ends it
import { gfxSetup } from "../../src/sokol/gpu";
import { doorBeginScreenPass } from "../../src/gpu/door.h";
@include("../../src/sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

function init(): void { gfxSetup(); }
function frame(): void {
	doorBeginScreenPass(0.0, 0.0, 0.0, 1.0);
	doorBeginScreenPass(0.0, 0.0, 0.0, 1.0);
	console.log("nested screen pass through the C door returned");
	process.exit(0);
}
voidRun(64, 64, init, frame);
