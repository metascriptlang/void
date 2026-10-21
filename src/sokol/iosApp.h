#ifndef VOID_SOKOL_IOS_APP_H
#define VOID_SOKOL_IOS_APP_H

// The framebuffer of the iOS app driver (bridgeIosApp.m) outside a frame; inside one, and
// in the embed driver, the current view's (views.c).
int voidIosAppFbWidth(void);
int voidIosAppFbHeight(void);
float voidIosAppDpiScale(void);

#endif
