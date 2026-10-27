#ifndef VOID_BATCHER_HOOK_H
#define VOID_BATCHER_HOOK_H

#include "../sokol/bridge.h"

void void2dFrameEndHook(void);

static inline void void2dRegisterFrameEnd(void) { voidSetCommitHook(void2dFrameEndHook); }

#endif
