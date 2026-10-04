// expect: void2d: beginTarget needs an allocated Rgba8 target and a positive scale, got Rgba8 16x16 view 2 at scale 0
import "../../src/sokol/gpu";
import { begin2d, beginTarget } from "../../src/void2d/draw";
import { rgba } from "../../src/void2d/types";
import { RenderTarget } from "../../src/gpu/target";
import { PixelFormat, contextGeneration } from "../../src/gpu/door";

const color: RenderTarget = {
	width: 16,
	height: 16,
	format: PixelFormat.Rgba8,
	sampled: true,
	image: 1,
	attachment: 2,
	texture: 3,
	generation: contextGeneration(),
	closed: false,
};
begin2d(16.0, 16.0, 1.0);
beginTarget(color, 16.0, 16.0, 0.0, 0.0, 0.0, rgba(0.0, 0.0, 0.0, 0.0));
console.log("a target with no scale opened a void2d target list");
