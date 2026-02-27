// Void Math — Mat4 operations for GPU uniform buffers
// All functions operate on a C-side scratch buffer, then
// the result can be uploaded to a GPU uniform buffer via queue.writeBuffer.

#ifndef VOID_MATH_MAT4_H
#define VOID_MATH_MAT4_H

#include <stdint.h>

// Set the projection matrix (perspective)
void void_math_set_perspective(float fovY, float aspect, float nearZ, float farZ);

// Set the view matrix (look-at)
void void_math_set_look_at(
    float eyeX, float eyeY, float eyeZ,
    float targetX, float targetY, float targetZ,
    float upX, float upY, float upZ);

// Set the model matrix to rotation around Y axis
void void_math_set_rotate_y(float angle);

// Compute MVP = projection * view * model → internal 64-byte buffer
void void_math_multiply_mvp(void);

// Get pointer to the 64-byte MVP result (16 floats, column-major)
const void *void_math_get_mvp(void);

// Trig helpers (expose C math to MetaScript)
float void_math_sinf(float x);
float void_math_cosf(float x);

#endif
