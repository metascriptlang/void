// expect: gpu door: asHandle on a sampler with no handle
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
	let sampler: Sampler = Sampler.create(FilterMode.Nearest, Wrap.Clamp);
	sampler = sampler.released();
	console.log(`a released sampler lent handle ${sampler.asHandle()}`);
	process.exit(0);
}
voidRun(64, 64, init, frame);
