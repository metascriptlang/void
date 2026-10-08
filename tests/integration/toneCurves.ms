import { ToneMode } from "../../src/void3d/renderer";

// h3d.shader.pbr.ToneMapping's curves on a grey (r = g = b), from the Heaps source: for a grey,
// PBR Neutral's min and max are the channel itself and its final mix lands on the new peak.
export function greyCurve(color: float32, mode: ToneMode): float32 {
	return match (mode) {
		ToneMode.Linear => clampUnit(color),
		ToneMode.Reinhard => color / (color + 1.0),
		ToneMode.Filmic =>
			clampUnit((color * (2.51 * color + 0.03)) / (color * (2.43 * color + 0.59) + 0.14)),
		ToneMode.Neutral => neutral(color),
	};
}

function clampUnit(value: float32): float32 {
	if (value < 0.0) { return 0.0; }
	if (value > 1.0) { return 1.0; }
	return value;
}

function neutral(color: float32): float32 {
	const startCompression: float32 = 0.8 - 0.04;
	const offset: float32 = color < 0.08 ? color - 6.25 * color * color : 0.04;
	const shifted: float32 = color - offset;
	if (shifted < startCompression) { return shifted; }
	const d: float32 = 1.0 - startCompression;
	return 1.0 - d * d / (shifted + d - startCompression);
}
