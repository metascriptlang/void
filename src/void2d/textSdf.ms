export const SDF_EM: float32 = 32.0;
export const SDF_PAD: int32 = 4;
export const SDF_RADIUS: float32 = 8.0;
export const SDF_EDGE: int32 = 191;

const BYTE_MAX: float32 = 255.0;

export function fieldByte(outwardTexels: float32): int32 {
	const edge: float32 = SDF_EDGE as float32;
	const perTexel: float32 = BYTE_MAX / SDF_RADIUS;
	const value: float32 = edge - outwardTexels * perTexel;
	if (value < 0.0) { return 0; }
	if (value > BYTE_MAX) { return 255; }
	return value as int32;
}

export function sdfCoverage(sample: float32, texelsPerPixel: float32): float32 {
	const half: float32 = 0.5;
	const edge: float32 = (SDF_EDGE as float32) / BYTE_MAX;
	const texels: float32 = (sample - edge) * SDF_RADIUS;
	const coverage: float32 = texels / texelsPerPixel + half;
	if (coverage < 0.0) { return 0.0; }
	if (coverage > 1.0) { return 1.0; }
	return coverage;
}

function texelAt(
	bytes: Readonly<Span<uint8>>,
	stride: int32,
	width: int32,
	height: int32,
	x: int32,
	y: int32,
): float32 {
	if (x < 0 || y < 0 || x >= width || y >= height) { return 0.0; }
	return (bytes[y * stride + x] as float32) / BYTE_MAX;
}

export function sampleField(
	bytes: Readonly<Span<uint8>>,
	stride: int32,
	width: int32,
	height: int32,
	x: float32,
	y: float32,
): float32 {
	const half: float32 = 0.5;
	const fx: float32 = x - half;
	const fy: float32 = y - half;
	const x0: int32 = Math.floor(fx) as int32;
	const y0: int32 = Math.floor(fy) as int32;
	const tx: float32 = fx - (x0 as float32);
	const ty: float32 = fy - (y0 as float32);
	const top: float32 = texelAt(bytes, stride, width, height, x0, y0) * (1.0 - tx) +
		texelAt(bytes, stride, width, height, x0 + 1, y0) * tx;
	const bottom: float32 = texelAt(bytes, stride, width, height, x0, y0 + 1) * (1.0 - tx) +
		texelAt(bytes, stride, width, height, x0 + 1, y0 + 1) * tx;
	return top * (1.0 - ty) + bottom * ty;
}
