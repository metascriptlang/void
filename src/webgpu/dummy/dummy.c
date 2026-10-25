#include <string.h>
#include "dummy.h"

void dummyCopyBytes(void *destination, int64_t destinationOffset, void *source, int64_t bytes) {
	memmove((uint8_t *)destination + destinationOffset, source, (size_t)bytes);
}

void dummyZeroBytes(void *destination, int64_t destinationOffset, int64_t bytes) {
	memset((uint8_t *)destination + destinationOffset, 0, (size_t)bytes);
}
