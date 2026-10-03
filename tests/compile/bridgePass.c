#include "bridge.h"

#if defined(PROBE_BEGIN)
void (*bridgeBegin)(float, float, float, float) = voidBeginPass;
#elif defined(PROBE_COMMIT)
void (*bridgeCommit)(void) = voidCommit;
#elif defined(PROBE_DOOR)
#include "door.h"
int probeDoor(void) {
	doorBeginScreenPass(0.0f, 0.0f, 0.0f, 0.0f);
	doorEndPass();
	doorCommit();
	return doorPassState();
}
#else
#error Select a consumer probe
#endif
