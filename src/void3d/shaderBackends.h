#ifndef VOID3D_SHADER_BACKENDS_H
#define VOID3D_SHADER_BACKENDS_H

#include "../sokol/backend.h"

#if defined(SOKOL_GLCORE)
#error "void3d: shader3d.glsl.h, pixelArt3d.glsl.h and gpuCopy.glsl.h carry no glsl430 for SOKOL_GLCORE; add it to LANGS_IOS in scripts/regen-shaders.sh"
#endif

#if !defined(SOKOL_METAL) && !defined(SOKOL_D3D11) && !defined(SOKOL_GLES3) && !defined(SOKOL_WGPU)
#error "void3d: the shader headers carry no shader text for this SOKOL_<backend>; add its language to LANGS_IOS in scripts/regen-shaders.sh"
#endif

#endif
