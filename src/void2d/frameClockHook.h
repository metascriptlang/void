// The bridge's present hook, set to the profiler's present edge (frameClockExports.cms).
#ifndef VOID_FRAME_CLOCK_HOOK_H
#define VOID_FRAME_CLOCK_HOOK_H

#include "../sokol/bridge.h"

void voidProfilePresent(int begin);

static inline void voidProfileSetup(void) { voidSetPresentHook(voidProfilePresent); }

#endif
