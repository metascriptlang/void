// Void Math — Mat4 operations (column-major, right-handed)

#include "mat4.h"
#include <math.h>
#include <string.h>

// Internal scratch matrices (column-major, 16 floats each)
static float s_projection[16];
static float s_view[16];
static float s_model[16];
static float s_mvp[16];
static float s_temp[16]; // for intermediate multiply

static void mat4_identity(float *m) {
	memset(m, 0, 16 * sizeof(float));
	m[0] = 1.0f; m[5] = 1.0f; m[10] = 1.0f; m[15] = 1.0f;
}

// C = A * B (column-major 4x4)
static void mat4_multiply(float *out, const float *a, const float *b) {
	for (int col = 0; col < 4; col++) {
		for (int row = 0; row < 4; row++) {
			float sum = 0.0f;
			for (int k = 0; k < 4; k++) {
				sum += a[k * 4 + row] * b[col * 4 + k];
			}
			out[col * 4 + row] = sum;
		}
	}
}

void void_math_set_perspective(float fovY, float aspect, float nearZ, float farZ) {
	memset(s_projection, 0, sizeof(s_projection));
	float f = 1.0f / tanf(fovY * 0.5f);
	float range_inv = 1.0f / (nearZ - farZ);

	s_projection[0]  = f / aspect;
	s_projection[5]  = f;
	s_projection[10] = farZ * range_inv;
	s_projection[11] = -1.0f;
	s_projection[14] = nearZ * farZ * range_inv;
}

void void_math_set_look_at(
	float eyeX, float eyeY, float eyeZ,
	float targetX, float targetY, float targetZ,
	float upX, float upY, float upZ
) {
	// Forward = normalize(target - eye)
	float fx = targetX - eyeX;
	float fy = targetY - eyeY;
	float fz = targetZ - eyeZ;
	float flen = sqrtf(fx*fx + fy*fy + fz*fz);
	fx /= flen; fy /= flen; fz /= flen;

	// Right = normalize(forward x up)
	float rx = fy * upZ - fz * upY;
	float ry = fz * upX - fx * upZ;
	float rz = fx * upY - fy * upX;
	float rlen = sqrtf(rx*rx + ry*ry + rz*rz);
	rx /= rlen; ry /= rlen; rz /= rlen;

	// True up = right x forward
	float ux = ry * fz - rz * fy;
	float uy = rz * fx - rx * fz;
	float uz = rx * fy - ry * fx;

	// Column-major
	s_view[0]  = rx;  s_view[1]  = ux;  s_view[2]  = -fx; s_view[3]  = 0.0f;
	s_view[4]  = ry;  s_view[5]  = uy;  s_view[6]  = -fy; s_view[7]  = 0.0f;
	s_view[8]  = rz;  s_view[9]  = uz;  s_view[10] = -fz; s_view[11] = 0.0f;
	s_view[12] = -(rx*eyeX + ry*eyeY + rz*eyeZ);
	s_view[13] = -(ux*eyeX + uy*eyeY + uz*eyeZ);
	s_view[14] = -(-fx*eyeX + -fy*eyeY + -fz*eyeZ);
	s_view[15] = 1.0f;
}

void void_math_set_rotate_y(float angle) {
	mat4_identity(s_model);
	float c = cosf(angle);
	float s = sinf(angle);
	s_model[0]  =  c;
	s_model[2]  =  s;
	s_model[8]  = -s;
	s_model[10] =  c;
}

void void_math_multiply_mvp(void) {
	// temp = view * model
	mat4_multiply(s_temp, s_view, s_model);
	// mvp = projection * temp
	mat4_multiply(s_mvp, s_projection, s_temp);
}

const void *void_math_get_mvp(void) {
	return (const void *)s_mvp;
}

float void_math_sinf(float x) { return sinf(x); }
float void_math_cosf(float x) { return cosf(x); }
