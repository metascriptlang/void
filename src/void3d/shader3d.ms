// void3d's programs written as MetaScript shader functions. tools/genShaders.ms writes their GLSL
// into shader3dGen.glsl for scripts/regen-shaders.sh; the native gate runs them on the CPU.

import {
	Sampler,
	Texture2d,
	Vec4f,
	binding,
	builtin,
	clamp,
	textureDimensions,
	textureLoad,
	vec2i,
} from "../shader/std";

export struct CopyInput {
	@builtin(position) position: Vec4f;
}

export struct CopyBindings {
	@binding(0) sourceTexture: Texture2d;
	@binding(0) pointSampler: Sampler;
}

// h3d.pass.Copy: the scene target onto the swapchain, one texel per pixel.
export function copyFs(input: CopyInput, b: CopyBindings): Vec4f {
	const size = textureDimensions(b.sourceTexture, b.pointSampler, 0);
	const p = clamp(vec2i(input.position.xy), vec2i(0, 0), size - vec2i(1, 1));
	return textureLoad(b.sourceTexture, b.pointSampler, p, 0);
}
