#include <jni.h>
#include <stdint.h>
#include <android/native_window_jni.h>

extern void MsMain(void);
extern int voidViewCreate(long long window, int w, int h, float scale);
extern void voidViewResize(int view, int w, int h, float scale);
extern int voidViewFrame(int view);
extern void voidViewDestroy(int view);
extern void voidEmbedDetach(void);

static int g_started = 0;
static ANativeWindow *g_window = NULL;
static int g_view = 0;

JNIEXPORT void JNICALL
Java_com_metascript_voidsample_VoidNative_attach(JNIEnv *env, jobject thiz, jobject surface, jint width, jint height) {
	(void)thiz;
	if (!g_started) { MsMain(); g_started = 1; }
	ANativeWindow *window = ANativeWindow_fromSurface(env, surface);
	if (g_view) voidViewDestroy(g_view);
	g_view = voidViewCreate((long long)(intptr_t)window, (int)width, (int)height, 1.0f);
	if (g_window) ANativeWindow_release(g_window);
	g_window = window;
}

JNIEXPORT void JNICALL
Java_com_metascript_voidsample_VoidNative_resize(JNIEnv *env, jobject thiz, jint width, jint height) {
	(void)env; (void)thiz;
	if (g_view) voidViewResize(g_view, (int)width, (int)height, 1.0f);
}

JNIEXPORT void JNICALL
Java_com_metascript_voidsample_VoidNative_frame(JNIEnv *env, jobject thiz) {
	(void)env; (void)thiz;
	if (g_view) voidViewFrame(g_view);
}

JNIEXPORT void JNICALL
Java_com_metascript_voidsample_VoidNative_detach(JNIEnv *env, jobject thiz) {
	(void)env; (void)thiz;
	voidEmbedDetach();
	if (g_window) { ANativeWindow_release(g_window); g_window = NULL; }
}
