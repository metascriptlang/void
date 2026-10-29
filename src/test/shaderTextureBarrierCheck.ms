// textureBarrier(): the entry runs on the CPU, is pinned as GLSL and printed into
// out/<target>Probe/
// for scripts/validateWgsl.sh, scripts/validateHlsl.sh and spirv-val.

import { mkdir, writeFile } from "std/fs";
import { computeModule } from "../shader/descriptor";
import { glslCompute, glslComputeIr } from "../shader/emit";
import { ShaderModule, irErrors } from "../shader/ir";
import { ShaderTarget } from "../shader/layout";
import { printedProbe, printedSpirv } from "./shaderProbePrint";
import {
	StorageTexture2d,
	Vec3u,
	access,
	binding,
	builtin,
	format,
	textureBarrier,
	textureLoad,
	textureStore,
	vec2i,
	vec4f,
} from "../shader/std";

export struct Ids {
	@builtin(globalInvocationId) id: Vec3u;
}

export struct Pair {
	@binding(0) @format(r32float) @access(read_write) image: StorageTexture2d;
}

export function swapCs(input: Ids, b: Pair): void {
	const at = vec2i(input.id.xy);
	textureStore(b.image, at, vec4f(1.0 + (at.x as float32)));
	textureBarrier();
	const next = textureLoad(b.image, vec2i(at.x ^ 1, at.y));
	textureStore(b.image, at, vec4f(next.x * 10.0));
}

test "the barrier waits for no one on the CPU" {
	const b: Pair = { image: { width: 2, height: 1,
		texels: [0.0, 0.0, 0.0, 0.0, 3.0, 0.0, 0.0, 0.0] } };
	swapCs({ id: { x: 0, y: 0, z: 0 } }, b);
	assert b.image.texels[0] == 30.0;
}

function computeOf(): ShaderModule {
	const m = computeModule(glslComputeIr(swapCs, [2, 1, 1]), []);
	if (!m.ok) { throw new Error("computeOf: " + m.error); }
	return m.value;
}

test "GLSL 450 fences the images before the barrier" {
	const text = glslCompute(swapCs, [2, 1, 1]);
	const _out = mkdir("out");
	const _folder = mkdir("out/glslProbe");
	const _written = writeFile("out/glslProbe/textureBarrier.450.comp", "#version 450\n" + text);
	assert text ==
		"layout(local_size_x=2, local_size_y=1, local_size_z=1) in;\n" +
		"layout(binding=0, r32f) uniform image2D image;\n" +
		"void main() {\n" +
		"    ivec2 at = ivec2(gl_GlobalInvocationID.xy);\n" +
		"    imageStore(image, at, vec4((1.0 + float(at.x))));\n" +
		"    memoryBarrierImage(); barrier();\n" +
		"    vec4 next = imageLoad(image, ivec2((at.x ^ 1), at.y));\n" +
		"    imageStore(image, at, vec4((next.x * 10.0)));\n" +
		"}\n";
}

test "every target spells the barrier" {
	const m = computeOf();
	assert irErrors(m).length == 0;
	for (const t of [ShaderTarget.Wgsl, ShaderTarget.Hlsl5, ShaderTarget.Glsl430,
		ShaderTarget.Msl]) {
		const text = printedProbe(m, 0, t, "textureBarrier", "comp");
		assert text.length > 0 && !text.startsWith("print");
	}
	assert printedSpirv(m, 0, "textureBarrier") == "";
}
