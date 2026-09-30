// expect: void2d: beginTarget needs an allocated Rgba8 target and a positive scale, got Depth 16x16 view 2 at scale 1
import "../../src/sokol/gpu";
import { begin2d, beginTarget } from "../../src/void2d/draw";
import { rgba } from "../../src/void2d/types";
import { RenderTarget } from "../../src/gpu/target";
import { PixelFormat } from "../../src/gpu/door";

const depth: RenderTarget = {
	width: 16,
	height: 16,
	format: PixelFormat.Depth,
	sampled: false,
	image: 1,
	attachment: 2,
	texture: 0,
};
begin2d(16.0, 16.0, 1.0);
beginTarget(depth, 16.0, 16.0, 1.0, 0.0, 0.0, rgba(0.0, 0.0, 0.0, 0.0));
console.log("a depth target opened a void2d target list");
