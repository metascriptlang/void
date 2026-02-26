// Void Math — Mat4 wrapper for C bridge

@include("./mat4.h")

import {
	void_math_set_perspective,
	void_math_set_look_at,
	void_math_set_rotate_y,
	void_math_multiply_mvp,
	void_math_get_mvp
} from "./mat4.h"

export function setPerspective(fovY: float32, aspect: float32, nearZ: float32, farZ: float32): void {
	void_math_set_perspective(fovY, aspect, nearZ, farZ);
}

export function setLookAt(
	eyeX: float32, eyeY: float32, eyeZ: float32,
	targetX: float32, targetY: float32, targetZ: float32,
	upX: float32, upY: float32, upZ: float32
): void {
	void_math_set_look_at(eyeX, eyeY, eyeZ, targetX, targetY, targetZ, upX, upY, upZ);
}

export function setRotateY(angle: float32): void {
	void_math_set_rotate_y(angle);
}

export function multiplyMVP(): void {
	void_math_multiply_mvp();
}

export function getMVP(): unknown {
	return void_math_get_mvp();
}
