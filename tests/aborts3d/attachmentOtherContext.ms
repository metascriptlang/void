// expect: gpu door: beginPass on color attachment 0 of GPU context 2; the context is now 1
import { gfxSetup } from "../../src/sokol/gpu";
import { PixelFormat, LoadAction, destroyView } from "../../src/gpu/door";
import { RenderTarget, ColorAttachment, NO_DEPTH, beginPass } from "../../src/gpu/target";
import { Vec4 } from "../../src/math/math3d";
@include("../../src/sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

const RED: Vec4 = { x: 1.0, y: 0.0, z: 0.0, w: 1.0 };

function init(): void { gfxSetup(); }
function frame(): void {
	const target: RenderTarget = RenderTarget.allocate(8, 8, PixelFormat.Rgba8, false);
	const color: ColorAttachment = target.asColor(LoadAction.Clear, RED);
	const stale: Vec<ColorAttachment> = [{ ...color, generation: color.generation + 1 }];
	beginPass(stale, NO_DEPTH);
	console.log("a pass opened on an attachment of another context");
	process.exit(0);
}
voidRun(64, 64, init, frame);
