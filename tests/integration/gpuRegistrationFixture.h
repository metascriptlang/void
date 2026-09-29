#ifndef VOID_TEST_GPU_REGISTRATION_H
#define VOID_TEST_GPU_REGISTRATION_H

#include <stdint.h>

int32_t fixturePreload(void);
int32_t fixtureProgram(void);
int32_t fixtureLayout(void);
void fixtureDraw(uint32_t pipeline, uint32_t texture, uint32_t sampler);
int32_t fixtureInvalidLayoutCount(int32_t count);
int32_t fixtureInvalidProgramCount(int32_t count);

#endif
