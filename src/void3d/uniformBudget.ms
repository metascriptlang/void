// How many floats a uniform pool needs for what a caller will make on it: the sum of the blocks
// each renderer, preset, shadow map and material reserves (uniformPool.ms hands out exact ranges,
// with no alignment and no growth), so a short pool is sized here and not found at the second
// preset or the shadow map as UniformPoolFull.

import {
	ProgramKey,
	MATERIAL_UNIFORM_SLOT,
	BILLBOARD_UNIFORM_SLOT,
	uniformBlockLength,
} from "./gpu3d";
import { FORWARD_UNIFORM_LENGTH } from "./forwardRenderer";
import { PIXEL_ART_UNIFORM_LENGTH } from "./pixelArtRenderer";
import { DIR_SHADOW_UNIFORM_LENGTH } from "./dirShadowMap";

// The block a material of `key` reserves: the program's own, at the material slot or, for a
// billboard, the billboard slot (draw.ms reserveUniforms takes the slot and the length).
export function materialUniformFloats(key: ProgramKey): int32 {
	return uniformBlockLength(key, MATERIAL_UNIFORM_SLOT) +
		uniformBlockLength(key, BILLBOARD_UNIFORM_SLOT);
}

// `keys` holds one key per material that reserves a block of its own; a material that shares
// another's block adds nothing.
export function uniformFloatsFor(
	forwardPresets: int32,
	pixelArtPresets: int32,
	shadowMaps: int32,
	keys: Readonly<Span<ProgramKey>>,
): int32 {
	let floats: int32 = forwardPresets * FORWARD_UNIFORM_LENGTH +
		pixelArtPresets * PIXEL_ART_UNIFORM_LENGTH + shadowMaps * DIR_SHADOW_UNIFORM_LENGTH;
	for (const key of keys) { floats = floats + materialUniformFloats(key); }
	return floats;
}
