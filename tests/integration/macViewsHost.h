#ifndef VOID_TEST_MAC_VIEWS_HOST_H
#define VOID_TEST_MAC_VIEWS_HOST_H

long long macHostOpen(int width, int height);
void macHostResize(int width, int height);
void macHostPump(void);
void macHostAwaitVsync(void);
double macHostNowMs(void);
void macHostClose(void);
int macHostBackingWidth(void);
int macHostBackingHeight(void);
float macHostScale(void);
void macHostHide(void);
void macHostShow(void);
int macHostSublayerCount(void);
int macHostDrawableWidth(void);
int macHostDrawableHeight(void);
int macHostLayerDrawableWidth(long long layer);

#endif
