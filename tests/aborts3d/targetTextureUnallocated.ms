// expect: gpu door: asTexture on a render target with no GPU objects
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
	const target: RenderTarget = RenderTarget.unallocated(PixelFormat.Rgba8, true);
	console.log(`an unallocated target lent texture view ${target.asTexture()}`);
	process.exit(0);
}
voidRun(64, 64, init, frame);
