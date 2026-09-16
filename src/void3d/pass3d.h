#ifndef VOID3D_PASS3D_H
#define VOID3D_PASS3D_H

#include <stdint.h>

void void3dSetup(void);
void void3dResize(int lowWidth, int lowHeight);
uint32_t void3dMakeBuffer(const float *data, int byteCount);
uint32_t void3dMakeTexture(const uint32_t *rgba, int width, int height);
void void3dBeginScene(float red, float green, float blue);
void void3dDrawLit(uint32_t buffer, int vertexCount, const float *vertexParams, const float *lightParams);
void void3dDrawBillboards(uint32_t instances, int instanceCount, uint32_t texture, const float *vertexParams, const float *lightParams);
void void3dEndScene(void);
void void3dPost(const float *postParams);
void void3dPresent(float pixelScale, float offsetX, float offsetY);

#endif
