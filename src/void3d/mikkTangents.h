#pragma once
#include <stdint.h>

int32_t void3dMikkTangents(const float *vertices, int64_t vertexFloats, int32_t stride,
	const uint16_t *indices, int64_t indexCount, float *corners, int64_t cornerFloats);
