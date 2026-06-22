// sokol implementation unit — Objective-C (sokol Metal/app on macOS require ObjC).
// Precompiled to sokol.o and @link'd from gpu.ms (avoids per-file -x objc on the
// MetaScript-generated .c files).
#define SOKOL_IMPL
#define SOKOL_METAL
#define SOKOL_NO_ENTRY
#include "sokol_gfx.h"
#include "sokol_app.h"
#include "sokol_log.h"
#include "sokol_glue.h"
