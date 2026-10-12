#ifndef VOID_TEST_FORWARD_OUTLINE_REFERENCE_H
#define VOID_TEST_FORWARD_OUTLINE_REFERENCE_H
#include <stdint.h>
int32_t outlineReferenceProgram(void);
int32_t outlineReferenceLayout(void);
void outlineReferenceDraw(uint32_t pipeline, uint32_t view, uint32_t sampler,
    float sizeX, float sizeY, float complement);
void outlineReferenceClose(void);
#endif
