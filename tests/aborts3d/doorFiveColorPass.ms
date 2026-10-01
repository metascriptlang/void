// expect: gpu door: beginPass takes at most 4 color attachments, given 5
import { gfxSetup } from "../../src/sokol/gpu";
import { PixelFormat, LoadAction } from "../../src/gpu/door";
import { RenderTarget, ColorAttachment, NO_DEPTH, beginPass } from "../../src/gpu/target";
@include("../../src/sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

function init(): void { gfxSetup(); }
function frame(): void {
	let colors: Vec<ColorAttachment> = [];
	for (let i = 0; i < 5; i++) {
		const target: RenderTarget = RenderTarget.allocate(8, 8, PixelFormat.Rgba8, false);
		colors.push(target.asColor(LoadAction.Clear, { x: 1.0, y: 0.0, z: 0.0, w: 1.0 }));
	}
	beginPass(colors, NO_DEPTH);
	console.log("a pass of five color attachments opened");
	process.exit(0);
}
voidRun(64, 64, init, frame);
