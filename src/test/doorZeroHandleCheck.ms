import {
	doorBufferSize,
	doorDestroyBuffer,
	doorDestroyImage,
	doorDestroyPipeline,
	doorDestroySampler,
	doorDestroyView,
	doorSetup,
	doorShutdown,
	doorTextureHeight,
	doorTextureWidth,
} from "../gpu/doorGpu.ms";
import { warpDevice, warpContext } from "./d3d11Warp.h";

@passL("-ld3d11");

const RGBA8 = 2;
const NO_DEPTH = 0;

test "destroying or querying handle 0, which an exhausted make returns, does nothing" {
	doorSetup(warpDevice(), warpContext(), RGBA8, NO_DEPTH, 1);
	doorDestroyImage(0);
	doorDestroyView(0);
	doorDestroySampler(0);
	doorDestroyBuffer(0);
	doorDestroyPipeline(0);
	assert doorBufferSize(0) == 0 && doorTextureWidth(0) == 0 && doorTextureHeight(0) == 0;
	doorShutdown();
}
