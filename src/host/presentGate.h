#ifndef VOID_SOKOL_PRESENT_GATE_H
#define VOID_SOKOL_PRESENT_GATE_H

void *voidPresentGateCreate(void *metalLayer);
void voidPresentGateRelease(void *gate);
int voidPresentGateAdmits(void *gate);
void voidPresentGateTrack(void *gate, void *drawable);

#endif
