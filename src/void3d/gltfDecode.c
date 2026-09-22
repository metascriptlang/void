#include "gltfDecode.h"

float gltfDecodeFloat32At(const uint8_t *bytes, int64_t length, int32_t at) {
	if (at < 0 || (int64_t)at + 4 > length) return 0.0f;
	union { uint32_t u; float f; } pun;
	pun.u = (uint32_t)bytes[at]
		| ((uint32_t)bytes[at + 1] << 8)
		| ((uint32_t)bytes[at + 2] << 16)
		| ((uint32_t)bytes[at + 3] << 24);
	return pun.f;
}
