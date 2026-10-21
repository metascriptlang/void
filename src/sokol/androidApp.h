#ifndef VOID_SOKOL_ANDROID_APP_H
#define VOID_SOKOL_ANDROID_APP_H

#include <jni.h>

// The Android app driver (bridgeAndroidApp.c), driven by the shell's NativeApp calls on the main
// thread; androidAppEntry.c forwards them. start runs MsMain, whose main_ must call voidRun.
void voidAndroidAppStart(JNIEnv *env, jobject root);
void voidAndroidAppPause(JNIEnv *env);
void voidAndroidAppResume(JNIEnv *env);
void voidAndroidAppDestroy(JNIEnv *env);

// For code that reaches Java from the main thread after start: the env, the app's class loader
// (FindClass sees only system classes from a native callback) and the activity.
JNIEnv *voidAndroidEnv(void);
jobject voidAndroidClassLoader(void);
jobject voidAndroidActivity(void);

// The framebuffer of the app driver outside a frame; inside one, and in the embed driver, the
// current view's (views.c).
int voidAndroidAppFbWidth(void);
int voidAndroidAppFbHeight(void);
float voidAndroidAppDpiScale(void);

#endif
