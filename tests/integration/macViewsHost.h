#ifndef VOID_TEST_MAC_VIEWS_HOST_H
#define VOID_TEST_MAC_VIEWS_HOST_H

long long macHostOpen(int width, int height);
void macHostResize(int width, int height);
void macHostPump(void);
void macHostClose(void);
int macHostBackingWidth(void);
int macHostBackingHeight(void);
float macHostScale(void);
int macHostSublayerCount(void);
int macHostDrawableWidth(void);
int macHostDrawableHeight(void);
int macHostLayerDrawableWidth(long long layer);

#endif
