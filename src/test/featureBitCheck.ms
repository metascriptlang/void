import { GPUFeatureName, featureBit } from "../webgpu/types";

const FEATURE_NAMES: GPUFeatureName[] = [
	"timestamp-query",
	"texture-compression-bc",
	"texture-compression-etc2",
	"texture-compression-astc",
	"depth32float-stencil8",
	"depth-clip-control",
	"float32-filterable",
	"float32-blendable",
	"rg11b10ufloat-renderable",
	"bgra8unorm-storage",
	"indirect-first-instance",
	"shader-f16",
	"dual-source-blending",
];

test "every feature name maps to its own single bit" {
	let seen: uint32 = 0;
	for (const name of FEATURE_NAMES) {
		const bit = featureBit(name);
		assert bit != 0 && (bit & (bit - 1)) == 0;
		assert (seen & bit) == 0;
		seen |= bit;
	}
}
