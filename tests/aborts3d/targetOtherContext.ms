// expect: gpu door: asColor on a render target of GPU context 2; the context is now 1
import { gfxSetup } from "../../src/sokol/gpu";
import { PixelFormat, LoadAction } from "../../src/gpu/door";
import { RenderTarget, Sampler } from "../../src/gpu/target";
import { FilterMode, Wrap } from "../../src/gpu/state";
@include("../../src/sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

function init(): void { gfxSetup(); }
function frame(): void {
	const target: RenderTarget = RenderTarget.allocate(8, 8, PixelFormat.Rgba8, false);
	const stale: RenderTarget = { ...target, generation: target.generation + 1 };
	const color = stale.asColor(LoadAction.Clear, { x: 0.0, y: 0.0, z: 0.0, w: 1.0 });
	console.log(`a target of another context lent view ${color.view}`);
	process.exit(0);
}
voidRun(64, 64, init, frame);
