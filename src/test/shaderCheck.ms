// The MetaScript shader functions run on the CPU, as the oracle for what their emitted GLSL draws
// (src/shader/CLAUDE.md, "CPU oracle within a tolerance").

import { Sampler, Texture2d, Vec4f } from "../shader/std";
import { CopyInput, copyFs } from "../void3d/shader3d";

function source(): Texture2d {
	return {
		width: 2,
		height: 2,
		texels: [
			0.1, 0.2, 0.3, 0.0, 0.4, 0.5, 0.6, 0.25,
			0.7, 0.8, 0.9, 0.5, 1.0, 0.0, 0.5, 0.75,
		],
	};
}

function copyAt(x: float32, y: float32): Vec4f {
	const input: CopyInput = { position: { x, y, z: 0.5, w: 1.0 } };
	const point: Sampler = { nearest: true };
	return copyFs(input, source(), point);
}

test "copy reads the texel under the pixel centre and makes it opaque" {
	const c = copyAt(1.5, 0.5);
	assert c.x == 0.4 && c.y == 0.5 && c.z == 0.6 && c.w == 1.0;
	const d = copyAt(0.5, 1.5);
	assert d.x == 0.7 && d.y == 0.8 && d.z == 0.9 && d.w == 1.0;
}

test "copy clamps a pixel beyond the source to its last texel" {
	const c = copyAt(5.5, 7.5);
	assert c.x == 1.0 && c.y == 0.0 && c.z == 0.5 && c.w == 1.0;
}
