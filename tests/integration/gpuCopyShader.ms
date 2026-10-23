// The foreign program gpuRegistrationFixture.ms registers: the scene copy with alpha forced to 1,
// over void3d's fullscreen vertex stage. tools/irPrograms.ms prints it into
// gpuCopyModules.ms.

import { CopyBindings, CopyInput } from "../../src/void3d/shader3d";
import {
	Vec4f,
	clamp,
	textureDimensions,
	textureLoad,
	vec2i,
	vec4f,
} from "../../src/shader/std";

export function gpuCopyFs(input: CopyInput, b: CopyBindings): Vec4f {
	const size = textureDimensions(b.sourceTexture, 0);
	const p = clamp(vec2i(input.position.xy), vec2i(0, 0), size - vec2i(1, 1));
	return vec4f(textureLoad(b.sourceTexture, p, 0).rgb, 1.0);
}
