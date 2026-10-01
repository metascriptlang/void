// expect: gpu door: endPass with no pass open
import { gfxSetup } from "../../src/sokol/gpu";
import { doorEndPass } from "../../src/gpu/door.h";
@include("../../src/sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

function init(): void { gfxSetup(); }
function frame(): void {
	doorEndPass();
	console.log("endPass through the C door with no pass open returned");
	process.exit(0);
}
voidRun(64, 64, init, frame);
