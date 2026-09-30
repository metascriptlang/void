// Void Math — C float32 math for MetaScript

import {
	void_math_sinf,
	void_math_cosf,
	void_math_sqrtf
} from "./mat4.h";

export function sinf(x: float32): float32 {
	return void_math_sinf(x);
}

export function cosf(x: float32): float32 {
	return void_math_cosf(x);
}

export function sqrtf(x: float32): float32 {
	return void_math_sqrtf(x);
}
