// expect: gpu door: beginTarget on a render target of GPU context 7; the context is now 1
import "../../src/sokol/gpu";
import { begin2d, beginTarget } from "../../src/void2d/draw";
import { rgba } from "../../src/void2d/types";
import { RenderTarget } from "../../src/gpu/target";
import { PixelFormat } from "../../src/gpu/door";

const stale: RenderTarget = {
	width: 16,
	height: 16,
	format: PixelFormat.Rgba8,
	sampled: true,
	image: 1,
	attachment: 2,
	texture: 3,
	generation: 7,
	closed: false,
};
begin2d(16.0, 16.0, 1.0);
beginTarget(stale, 16.0, 16.0, 1.0, 0.0, 0.0, rgba(0.0, 0.0, 0.0, 0.0));
console.log("a target of another GPU context opened a void2d target list");
