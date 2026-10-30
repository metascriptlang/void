#ifndef VOID_TEST_MAC_WINDOW_HOST_H
#define VOID_TEST_MAC_WINDOW_HOST_H

#include "runtime/core/string.h"

int macHostWindowCount(void);
msString macHostTitle(void);
msString macHostPasteboard(void);
void macHostClearPasteboard(void);
int macHostCursorIs(int cursor);
void macHostKey(int down, int keyCode, const char *chars, unsigned flags);
void macHostFlags(unsigned flags);
void macHostMouse(int type, double x, double y, unsigned flags);
void macHostScroll(int lines);
void macHostEnter(int enter, double x, double y);
void macHostMark(const char *text, int caret);
void macHostInsert(const char *text);
void macHostUnmark(void);
int macHostImeRectFits(double x, double y, double w, double h);
void macHostResignKey(void);
void macHostBecomeKey(void);
void macHostMiniaturize(int on);
int macHostMiniaturized(void);
void macHostRaise(void);
int macHostWindowVisible(void);
int macHostFullscreenStyle(void);
void macHostSetContentSize(int w, int h);
int macHostContentWidth(void);
int macHostLayerDrawableWidth(void);
int macHostLayerDrawableHeight(void);
int macHostDrop(const char *path);
float macHostScale(void);
int macHostMaxFps(void);
double macHostNowMs(void);

#endif
