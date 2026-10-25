#pragma once
#include <stdint.h>

void dummyCopyBytes(void *destination, int64_t destinationOffset, void *source, int64_t bytes);
void dummyZeroBytes(void *destination, int64_t destinationOffset, int64_t bytes);
