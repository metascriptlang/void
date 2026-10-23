#ifndef VOID3D_ENVIRONMENT_BAKE_H
#define VOID3D_ENVIRONMENT_BAKE_H

#include <stdint.h>

static const int32_t ENVIRONMENT_PARAMS_FLOATS = 20;
#define ENVIRONMENT_BAKE_PROGRAM_COUNT 4

// The door id of the first bake program; the rest follow in environment.ms's EnvironmentProgram order.
int32_t environmentBakeProgramBase(void);
int32_t environmentBakeLayout(void);

#endif
