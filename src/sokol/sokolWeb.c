// sokol implementation for web (emscripten). Plain C (no ObjC).
// Backend selected via -D on the emcc command line:
//   -DSOKOL_GLES3  → WebGL2
//   -DSOKOL_WGPU   → WebGPU (needs --use-port=emdawnwebgpu + -sASYNCIFY)
#define SOKOL_IMPL
#include "backend.h"
#define SOKOL_NO_ENTRY
#include "sokol_gfx.h"
#include "sokol_app.h"
#include "sokol_log.h"
#include "sokol_glue.h"
