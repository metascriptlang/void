// void3d's programs written as MetaScript shader functions. tools/genShaders.ms writes their GLSL
// into shader3dGen.glsl for scripts/regen-shaders.sh; the native gate runs them on the CPU.

import {
	Sampler,
	Texture2d,
	Vec4f,
	builtin,
	clamp,
	textureDimensions,
	textureLoad,
	vec2i,
	vec4f,
} from "../shader/std";

export struct CopyInput {
	@builtin(position) position: Vec4f;
}

// h3d.pass.Copy: the scene target onto the swapchain, one texel per pixel, opaque.
export function copyFs(input: CopyInput, sourceTexture: Texture2d, pointSampler: Sampler): Vec4f {
	const size = vec2i(textureDimensions(sourceTexture, pointSampler, 0));
	const p = clamp(vec2i(input.position.xy), vec2i(0, 0), size - vec2i(1, 1));
	const texel = textureLoad(sourceTexture, pointSampler, p, 0);
	return vec4f(texel.rgb, 1.0);
}
