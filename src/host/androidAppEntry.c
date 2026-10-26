// The JNI entry points of Ion's NativeApp for a voidRun app. An app compiles this file itself, as
// an iOS app compiles its own main, because a Neon widget app defines the same symbols.

#include "androidApp.h"

JNIEXPORT void JNICALL Java_dev_metascript_app_NativeApp_start(JNIEnv *e, jclass cls, jobject root) {
	(void)cls;
	voidAndroidAppStart(e, root);
}

JNIEXPORT void JNICALL Java_dev_metascript_app_NativeApp_resize(JNIEnv *e, jclass cls, jint width, jint height) {
	(void)e; (void)cls; (void)width; (void)height;
}

JNIEXPORT void JNICALL Java_dev_metascript_app_NativeApp_pause(JNIEnv *e, jclass cls) {
	(void)cls;
	voidAndroidAppPause(e);
}

JNIEXPORT void JNICALL Java_dev_metascript_app_NativeApp_resume(JNIEnv *e, jclass cls) {
	(void)cls;
	voidAndroidAppResume(e);
}

JNIEXPORT void JNICALL Java_dev_metascript_app_NativeApp_destroy(JNIEnv *e, jclass cls) {
	(void)cls;
	voidAndroidAppDestroy(e);
}

JNIEXPORT void JNICALL Java_dev_metascript_app_NativeApp_newIntent(JNIEnv *e, jclass cls, jobject intent) {
	(void)e; (void)cls; (void)intent;
}
