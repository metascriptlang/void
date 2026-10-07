// expect: void3d: applyBindings descriptor holds 10 of 11 words
import { gfxSetup } from "../../src/sokol/gpu";
import { GPU3D_BINDING_LENGTH } from "../../src/void3d/gpu3d.h";
import { applyBindings } from "../../src/void3d/gpu3d";
@include("../../src/sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

let bindings: Vec<uint32> = new Array(GPU3D_BINDING_LENGTH - 1);

function init(): void { gfxSetup(); }
function frame(): void {
	applyBindings(bindings);
	console.log("a short bindings descriptor through gpu3d returned");
	process.exit(0);
}
voidRun(64, 64, init, frame);
