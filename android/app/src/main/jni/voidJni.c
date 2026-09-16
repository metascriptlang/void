#include <jni.h>
#include <android/native_window_jni.h>

extern void MsMain(void);
extern void voidEmbedInit(const void *window, int w, int h);
extern void voidEmbedResize(int w, int h);
extern void voidEmbedFrame(void);
extern void voidEmbedDetach(void);

static int g_started = 0;
static ANativeWindow *g_window = NULL;

JNIEXPORT void JNICALL
Java_com_metascript_voidsample_VoidNative_attach(JNIEnv *env, jobject thiz, jobject surface, jint width, jint height) {
	(void)thiz;
	if (!g_started) { MsMain(); g_started = 1; }
	ANativeWindow *window = ANativeWindow_fromSurface(env, surface);
	voidEmbedInit((const void *)window, (int)width, (int)height);
	if (g_window) ANativeWindow_release(g_window);
	g_window = window;
}

JNIEXPORT void JNICALL
Java_com_metascript_voidsample_VoidNative_resize(JNIEnv *env, jobject thiz, jint width, jint height) {
	(void)env; (void)thiz;
	voidEmbedResize((int)width, (int)height);
}

JNIEXPORT void JNICALL
Java_com_metascript_voidsample_VoidNative_frame(JNIEnv *env, jobject thiz) {
	(void)env; (void)thiz;
	voidEmbedFrame();
}

JNIEXPORT void JNICALL
Java_com_metascript_voidsample_VoidNative_detach(JNIEnv *env, jobject thiz) {
	(void)env; (void)thiz;
	voidEmbedDetach();
	if (g_window) { ANativeWindow_release(g_window); g_window = NULL; }
}
