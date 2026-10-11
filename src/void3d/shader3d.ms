// void3d's programs written as MetaScript shader functions. tools/genShaders.ms writes their GLSL
// into shader3dGen.glsl, which shader3d.glsl includes; the native gate runs them on the CPU.

import {
	FragCoord,
	Sampler,
	Texture2D,
	Vec4,
	clamp,
	ivec2,
	sampler2D,
	texelFetch,
	textureSize,
	vec4,
} from "../shader/glsl";

// h3d.pass.Copy: the scene target onto the swapchain, one texel per pixel, opaque.
export function copyFs(
	fragCoord: FragCoord,
	sourceTexture: Texture2D,
	pointSampler: Sampler,
	out fragColor: Vec4,
): void {
	const size = textureSize(sampler2D(sourceTexture, pointSampler), 0);
	const p = clamp(ivec2(fragCoord.xy), ivec2(0, 0), size - ivec2(1, 1));
	const texel = texelFetch(sampler2D(sourceTexture, pointSampler), p, 0);
	fragColor = vec4(texel.rgb, 1.0);
}
