// expect: gpu door: beginPass on the depth attachment, which has no view
import { gfxSetup } from "../../src/sokol/gpu";
import { PixelFormat, LoadAction } from "../../src/gpu/door";
import { RenderTarget, Sampler, ColorAttachment, beginPass } from "../../src/gpu/target";
import { FilterMode, Wrap } from "../../src/gpu/state";
import { Vec4 } from "../../src/math/math3d";
@include("../../src/sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

const RED: Vec4 = { x: 1.0, y: 0.0, z: 0.0, w: 1.0 };

function init(): void { gfxSetup(); }
function frame(): void {
	const color: RenderTarget = RenderTarget.allocate(8, 8, PixelFormat.Rgba8, false);
	const depth: RenderTarget = RenderTarget.unallocated(PixelFormat.Depth, false);
	const colors: Vec<ColorAttachment> = [color.asColor(LoadAction.Clear, RED)];
	beginPass(colors, depth.asDepth(LoadAction.Clear, 1.0));
	console.log("a pass opened on an unallocated depth target");
	process.exit(0);
}
voidRun(64, 64, init, frame);
