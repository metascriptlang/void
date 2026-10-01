// expect: gpu door: commit with a pass already open; endPass ends it
import { gfxSetup } from "../../src/sokol/gpu";
import { commit } from "../../src/gpu/door";
import { beginScreenPass } from "../../src/gpu/target";
@include("../../src/sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

function init(): void { gfxSetup(); }
function frame(): void {
	beginScreenPass({ x: 0.0, y: 0.0, z: 0.0, w: 1.0 });
	commit();
	console.log("commit with the screen pass open returned");
	process.exit(0);
}
voidRun(64, 64, init, frame);
