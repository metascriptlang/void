// Void 2D colour effects — h2d.Drawable colorMatrix factories. A 4x4 RGBA transform
// packed column-major for GLSL `colorMatrix * rgba`; identity = no-op. Assign to
// Node2D.colorMatrix; colorAdd (Node2D.colorAdd) is just a Color added afterwards.

// Luminance grayscale (Rec.601). amount 0 = original .. 1 = fully gray.
export function colorMatrixGrayscale(amount: float32): float32[] {
	const lr: float32 = 0.299;
	const lg: float32 = 0.587;
	const lb: float32 = 0.114;
	const k: float32 = amount;
	const ik: float32 = 1.0 - amount;
	return [
		ik + k * lr, k * lr,      k * lr,      0.0,
		k * lg,      ik + k * lg, k * lg,      0.0,
		k * lb,      k * lb,      ik + k * lb, 0.0,
		0.0,         0.0,         0.0,         1.0,
	];
}

// Silhouette tint (h2d glow / drop-shadow): drops rgb, keeps alpha × gain. Pair with
// colorAdd = the tint colour (a=0) so a blurred render-target becomes a solid-coloured
// halo shaped only by its alpha — the colour of the source is discarded.
export function colorMatrixAlphaOnly(gain: float32): float32[] {
	return [
		0.0, 0.0, 0.0, 0.0,
		0.0, 0.0, 0.0, 0.0,
		0.0, 0.0, 0.0, 0.0,
		0.0, 0.0, 0.0, gain,
	];
}
