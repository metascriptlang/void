// expect: gpu door: asTexture on a render target whose view
import { gfxSetup } from "../../src/sokol/gpu";
import { PixelFormat, LoadAction, destroyView } from "../../src/gpu/door";
import { RenderTarget, ColorAttachment, NO_DEPTH, beginPass } from "../../src/gpu/target";
import { Vec4 } from "../../src/math/math3d";
@include("../../src/sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

const RED: Vec4 = { x: 1.0, y: 0.0, z: 0.0, w: 1.0 };

function init(): void { gfxSetup(); }
function frame(): void {
	const target: RenderTarget = RenderTarget.allocate(8, 8, PixelFormat.Rgba8, true);
	destroyView(target.texture);
	console.log(`a target whose view was destroyed lent view ${target.asTexture()}`);
	process.exit(0);
}
voidRun(64, 64, init, frame);
