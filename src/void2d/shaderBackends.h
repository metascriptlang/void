#ifndef VOID2D_SHADER_BACKENDS_H
#define VOID2D_SHADER_BACKENDS_H

#include "../sokol/backend.h"

#if !defined(SOKOL_METAL) && !defined(SOKOL_D3D11) && !defined(SOKOL_GLES3) && \
	!defined(SOKOL_WGPU) && !defined(SOKOL_GLCORE)
#error "void2d: shader2d.glsl.h carries no shader text for this SOKOL_<backend>; add its language to LANGS in scripts/regen-shaders.sh"
#endif

#endif
