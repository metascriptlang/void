// C prototypes for the MetaScript message FFI. @include'd from message.ms so the emitted
// C sees the msString return type (without this, voidRelayNext defaults to an int return).
#pragma once

#include "runtime/core/string.h"

#ifdef __cplusplus
extern "C" {
#endif

void     voidRelayEmit(const char *msg);
msString voidRelayNext(void);

#ifdef __cplusplus
}
#endif
