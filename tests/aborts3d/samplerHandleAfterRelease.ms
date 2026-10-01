// expect: gpu door: asHandle on a sampler that was released
import { gfxSetup } from "../../src/sokol/gpu";
import { PixelFormat, LoadAction } from "../../src/gpu/door";
import { RenderTarget, Sampler } from "../../src/gpu/target";
import { FilterMode, Wrap } from "../../src/gpu/state";
@include("../../src/sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

function init(): void { gfxSetup(); }
function frame(): void {
	let sampler: Sampler = Sampler.create(FilterMode.Nearest, Wrap.Clamp);
	const copy: Sampler = sampler;
	sampler = sampler.released();
	console.log(`a released sampler copy lent handle ${copy.asHandle()}`);
	process.exit(0);
}
voidRun(64, 64, init, frame);
