// Void Math — float32 sin, cos, sqrt

@inline export function sinf(x: float32): float32 {
	return Math.sin(x as float64) as float32;
}

@inline export function cosf(x: float32): float32 {
	return Math.cos(x as float64) as float32;
}

@inline export function sqrtf(x: float32): float32 {
	return Math.sqrt(x as float64) as float32;
}
