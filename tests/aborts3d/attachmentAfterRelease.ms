// expect: gpu door: beginPass on color attachment 0, whose view
import { gfxSetup } from "../../src/sokol/gpu";
import { PixelFormat, LoadAction, destroyView } from "../../src/gpu/door";
import { RenderTarget, ColorAttachment, NO_DEPTH, beginPass } from "../../src/gpu/target";
import { Vec4 } from "../../src/math/math3d";
@include("../../src/sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

const RED: Vec4 = { x: 1.0, y: 0.0, z: 0.0, w: 1.0 };

function init(): void { gfxSetup(); }
function frame(): void {
	let target: RenderTarget = RenderTarget.allocate(8, 8, PixelFormat.Rgba8, false);
	const kept: Vec<ColorAttachment> = [target.asColor(LoadAction.Clear, RED)];
	target.close();
	beginPass(kept, NO_DEPTH);
	console.log("a pass opened on the attachment of a released target");
	process.exit(0);
}
voidRun(64, 64, init, frame);
