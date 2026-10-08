import { ToneMode } from "../../src/void3d/renderer";
import { toneCurved } from "../../src/void3d/toneMap";

// The engine's own CPU curve (toneMap.ms toneCurved) on a grey: what the GPU stages hold the
// shader's toneCurve block to.
export function greyCurve(color: float32, mode: ToneMode): float32 {
	return toneCurved({ x: color, y: color, z: color, w: 1.0 }, mode).x;
}
