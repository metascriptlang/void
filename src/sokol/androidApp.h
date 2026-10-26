#ifndef VOID_SOKOL_ANDROID_APP_H
#define VOID_SOKOL_ANDROID_APP_H

#include <jni.h>
#include <stdbool.h>
#include <stdint.h>

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

// The app driver as appWindow.c reads it; the asset dir is bridgeAndroid.c's.
bool voidAndroidValid(void);
int voidAndroidWidth(void);
int voidAndroidHeight(void);
float voidAndroidScale(void);
uint32_t voidAndroidModifiers(void);
const char *voidAndroidAssetDir(void);
uint64_t voidAndroidFrameCount(void);
double voidAndroidFrameDuration(void);
// Finishes the activity, which the shell then destroys.
void voidAndroidRequestQuit(void);

#endif
