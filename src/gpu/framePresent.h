#ifndef VOID_GPU_FRAME_PRESENT_H
#define VOID_GPU_FRAME_PRESENT_H

// The platform bridge's present (src/sokol/bridgeWin.c and the other bridges). It stays out of
// bridge.h and door.h so that doorCommit is the one way a consumer ends a frame.
void voidDriverPresent(void);

#endif
