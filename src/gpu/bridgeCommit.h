#ifndef VOID_GPU_BRIDGE_COMMIT_H
#define VOID_GPU_BRIDGE_COMMIT_H

// The platform bridge's frame end (src/host/bridge.c), which doorCommit calls. It stays out of
// bridge.h and door.h so that doorCommit is the one way a consumer ends a frame.
void voidCommit(void);

#endif
