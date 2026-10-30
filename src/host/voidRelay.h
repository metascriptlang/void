// void_relay — bidirectional in-memory JSON message queue between the React-Native
// host and the embedded Void engine. Mirrors the urg_relay surface used for Godot so
// VoidLauncher can drop into the same JS integration (sendMessage / addMessageListener).
#pragma once

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// host → void: native sendMessage() pushes; the engine drains via PopToVoid each frame.
void  voidRelayPushToVoid(const char *json);
char *voidRelayPopToVoid(void);     // NULL if empty; free with voidRelayFreeString
bool  voidRelayHasToVoid(void);

// void → host: the engine pushes; the native poll loop drains via PopFromVoid → JS event.
void  voidRelayPushFromVoid(const char *json);
char *voidRelayPopFromVoid(void);   // NULL if empty; free with voidRelayFreeString
bool  voidRelayHasFromVoid(void);

void  voidRelayFreeString(char *s);

#ifdef __cplusplus
}
#endif
