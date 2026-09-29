// expect: gpu door: beginPass with a pass already open; endPass ends it
import { gfxSetup } from "../../src/sokol/gpu";
import { PixelFormat, LoadAction } from "../../src/gpu/door";
import { RenderTarget, ColorAttachment, NO_DEPTH, beginPass } from "../../src/gpu/target";
@include("../../src/sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

function init(): void { gfxSetup(); }
function frame(): void {
	let target: RenderTarget = RenderTarget.allocate(16, 16, PixelFormat.Rgba8, false);
	let colors: Vec<ColorAttachment> = [target.asColor(
		LoadAction.Clear, { x: 0.0, y: 0.0, z: 0.0, w: 1.0 },
	)];
	beginPass(colors, NO_DEPTH);
	beginPass(colors, NO_DEPTH);
	console.log("nested target pass returned");
	process.exit(0);
}
voidRun(64, 64, init, frame);
