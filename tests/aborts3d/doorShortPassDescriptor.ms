// expect: gpu door: beginPass descriptor holds 10 of 11 words and 17 of 17 clear values
import { gfxSetup } from "../../src/sokol/gpu";
import { DOOR_PASS_LENGTH, DOOR_PASS_CLEAR_LENGTH } from "../../src/gpu/door.h";
@include("../../src/sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;
extern function doorBeginPass(descriptor: Span<uint32>, clear: Span<float32>): void;

let descriptor: Vec<uint32> = new Array(DOOR_PASS_LENGTH - 1);
let clear: Vec<float32> = new Array(DOOR_PASS_CLEAR_LENGTH);

function init(): void { gfxSetup(); }
function frame(): void {
	doorBeginPass(descriptor, clear);
	console.log("a short pass descriptor through the C door returned");
	process.exit(0);
}
voidRun(64, 64, init, frame);
