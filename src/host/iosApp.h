#ifndef VOID_SOKOL_IOS_APP_H
#define VOID_SOKOL_IOS_APP_H

#include <stdbool.h>
#include <stdint.h>

// The iOS app driver (bridgeIosApp.m) as appWindow.c reads it; the asset dir is bridgeIos.m's.
bool voidIosValid(void);
int voidIosWidth(void);
int voidIosHeight(void);
float voidIosScale(void);
uint32_t voidIosModifiers(void);
const char *voidIosAssetDir(void);
uint64_t voidIosFrameCount(void);
// The display link's frame interval, as sokol_app reports it on iOS.
double voidIosFrameDuration(void);

#endif
