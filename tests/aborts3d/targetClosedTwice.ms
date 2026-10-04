// expect: gpu door: close on a render target that was closed
import { gfxSetup } from "../../src/sokol/gpu";
import { PixelFormat, LoadAction } from "../../src/gpu/door";
import { RenderTarget, Sampler } from "../../src/gpu/target";
import { FilterMode, Wrap } from "../../src/gpu/state";
@include("../../src/sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

function init(): void { gfxSetup(); }
function frame(): void {
	let target: RenderTarget = RenderTarget.allocate(8, 8, PixelFormat.Rgba8, true);
	const copy: RenderTarget = target;
	target.close();
	copy.close();
	console.log(`a closed alias was closed again: image ${copy.image}`);
	process.exit(0);
}
voidRun(64, 64, init, frame);
