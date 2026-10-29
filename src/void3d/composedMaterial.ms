// A material's effect parameters held as the value of the block struct its program declares
// (shader3d.ms MovingMaterialParams and its siblings), so effects that read one block share one
// value and the write lands each field where the printers lay the block out.

import { Vec4f } from "../shader/std";
import { DrawContext, writeBlock } from "./draw";
import { TypedBlock, UniformBlock } from "./material";
import {
	MovingEmissiveMaterialParams,
	MovingMaterialParams,
	MovingUnlitMaterialParams,
} from "./shader3d";
import { UniformError } from "./uniformPool";

function zero(): Vec4f {
	return { x: 0, y: 0, z: 0, w: 0 };
}

function white(): Vec4f {
	return { x: 1, y: 1, z: 1, w: 1 };
}

function identityMatrix(): Vec4f {
	return { x: 1, y: 0, z: 0, w: 1 };
}

// Both UV transforms the identity, no scroll, no dissolve, the material colour white and every
// other lane 0: the values movingDefaults holds for a moving key.
export function movingParams(): MovingMaterialParams {
	return {
		material: zero(), materialColor: white(),
		uvMatrix: identityMatrix(), uvMotion: zero(),
		backUvMatrix: identityMatrix(), backUvOffset: zero(),
		dissolve: zero(), dissolveEdge: zero(),
		flipbookGrid: zero(), flipbookPlay: zero(),
		distanceFade: zero(), colorKey: zero(), sinusDeform: zero(),
	};
}

export function movingUnlitParams(): MovingUnlitMaterialParams {
	return {
		material: zero(), materialColor: white(),
		uvMatrix: identityMatrix(), uvMotion: zero(),
		backUvMatrix: identityMatrix(), backUvOffset: zero(),
		dissolve: zero(), dissolveEdge: zero(),
		flipbookGrid: zero(), flipbookPlay: zero(),
		distanceFade: zero(), colorKey: zero(), sinusDeform: zero(),
	};
}

export function movingEmissiveParams(): MovingEmissiveMaterialParams {
	return {
		material: zero(), materialColor: white(),
		uvMatrix: identityMatrix(), uvMotion: zero(),
		backUvMatrix: identityMatrix(), backUvOffset: zero(),
		dissolve: zero(), dissolveEdge: zero(),
		flipbookGrid: zero(), flipbookPlay: zero(),
		distanceFade: zero(), colorKey: zero(), sinusDeform: zero(),
		emissive: zero(),
	};
}

// Writes `value` over the material's block; a T that is not the block's struct is
// UniformError.WrongLength when the sizes differ.
export function writeMaterialParams<T>(
	context: DrawContext,
	block: UniformBlock,
	value: T,
): Result<int32, UniformError> {
	const typed: TypedBlock<T> = { block: block };
	return writeBlock<T>(context, typed, value);
}
