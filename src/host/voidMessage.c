// MetaScript-facing FFI over void_relay: lets MetaScript game code receive host
// messages (voidRelayNext) and send messages back (voidRelayEmit), marshaling C
// strings ↔ msString. Kept separate from voidRelay.c so the queue stays runtime-free.
#include "voidMessage.h"
#include "voidRelay.h"

void voidRelayEmit(const char *msg) {
	voidRelayPushFromVoid(msg);
}

msString voidRelayNext(void) {
	char *m = voidRelayPopToVoid();
	if (!m) {
		msString empty;
		empty.len = 0;
		empty.p = NULL;
		return empty;
	}
	msString s = msStringFromCStr(m);
	voidRelayFreeString(m);
	return s;
}
