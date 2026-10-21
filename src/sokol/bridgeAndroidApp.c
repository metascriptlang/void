// Void sokol driver — Android app (GLES3). voidRun is an activity whose root view
// (android/app VoidAppView.java) renders through the views driver (bridgeAndroid.c, views.c) and
// feeds the window event surface (appWindow.c), as bridgeIosApp.m does on iOS. NativeApp.start runs
// MsMain, whose main_ calls voidRun, which records the closures and returns; start then adds the view.

#include <android/log.h>
#include <android/native_window_jni.h>
#include <jni.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#include "bridge.h"
#include "views.h"
#include "appWindow.h"
#include "androidApp.h"

extern void MsMain(void);

static JavaVM *s_vm;
static jobject s_loader, s_activity, s_view;
static jmethodID s_setRunning, s_setTextInput, s_detach;
static ANativeWindow *s_window;
static VoidViewId s_viewId;
static int s_running, s_started;
static int s_reqW, s_reqH;
static uint64_t s_frameCount;
static int s_fbW = 1, s_fbH = 1;
static float s_scale = 1.0f;
static uint32_t s_modifiers;
static int s_textInput;

uint64_t sapp_frame_count(void) { return s_frameCount; }
int sapp_width(void) { return s_fbW; }
int sapp_height(void) { return s_fbH; }
bool sapp_isvalid(void) { return s_running != 0; }
void sapp_set_window_title(const char *title) { (void)title; }

static void check(JNIEnv *e, const char *op) {
	if (!(*e)->ExceptionCheck(e)) return;
	(*e)->ExceptionDescribe(e);
	voidFail("Android app driver: %s threw", op);
}

static sapp_event makeEvent(sapp_event_type type) {
	sapp_event e;
	memset(&e, 0, sizeof e);
	e.type = type;
	e.frame_count = s_frameCount;
	e.modifiers = s_modifiers;
	e.framebuffer_width = s_fbW;
	e.framebuffer_height = s_fbH;
	e.window_width = (int)(s_fbW / s_scale);
	e.window_height = (int)(s_fbH / s_scale);
	return e;
}

static void send(sapp_event_type type) {
	sapp_event e = makeEvent(type);
	voidAppEventDeliver(&e);
}

static void sendKey(sapp_event_type type, sapp_keycode code, bool repeat) {
	sapp_event e = makeEvent(type);
	e.key_code = code;
	e.key_repeat = repeat;
	voidAppEventDeliver(&e);
}

static void sendTap(sapp_keycode code) {
	sendKey(SAPP_EVENTTYPE_KEY_DOWN, code, false);
	sendKey(SAPP_EVENTTYPE_KEY_UP, code, false);
}

static sapp_keycode keyOfAndroid(int code) {
	if (code >= 29 && code <= 54) return (sapp_keycode)(SAPP_KEYCODE_A + (code - 29));
	if (code >= 7 && code <= 16) return (sapp_keycode)(SAPP_KEYCODE_0 + (code - 7));
	if (code >= 131 && code <= 142) return (sapp_keycode)(SAPP_KEYCODE_F1 + (code - 131));
	switch (code) {
		case 19: return SAPP_KEYCODE_UP;
		case 20: return SAPP_KEYCODE_DOWN;
		case 21: return SAPP_KEYCODE_LEFT;
		case 22: return SAPP_KEYCODE_RIGHT;
		case 55: return SAPP_KEYCODE_COMMA;
		case 56: return SAPP_KEYCODE_PERIOD;
		case 57: return SAPP_KEYCODE_LEFT_ALT;
		case 58: return SAPP_KEYCODE_RIGHT_ALT;
		case 59: return SAPP_KEYCODE_LEFT_SHIFT;
		case 60: return SAPP_KEYCODE_RIGHT_SHIFT;
		case 61: return SAPP_KEYCODE_TAB;
		case 62: return SAPP_KEYCODE_SPACE;
		case 66: return SAPP_KEYCODE_ENTER;
		case 67: return SAPP_KEYCODE_BACKSPACE;
		case 68: return SAPP_KEYCODE_GRAVE_ACCENT;
		case 69: return SAPP_KEYCODE_MINUS;
		case 70: return SAPP_KEYCODE_EQUAL;
		case 71: return SAPP_KEYCODE_LEFT_BRACKET;
		case 72: return SAPP_KEYCODE_RIGHT_BRACKET;
		case 73: return SAPP_KEYCODE_BACKSLASH;
		case 74: return SAPP_KEYCODE_SEMICOLON;
		case 75: return SAPP_KEYCODE_APOSTROPHE;
		case 76: return SAPP_KEYCODE_SLASH;
		case 92: return SAPP_KEYCODE_PAGE_UP;
		case 93: return SAPP_KEYCODE_PAGE_DOWN;
		case 111: return SAPP_KEYCODE_ESCAPE;
		case 112: return SAPP_KEYCODE_DELETE;
		case 113: return SAPP_KEYCODE_LEFT_CONTROL;
		case 114: return SAPP_KEYCODE_RIGHT_CONTROL;
		case 115: return SAPP_KEYCODE_CAPS_LOCK;
		case 117: return SAPP_KEYCODE_LEFT_SUPER;
		case 118: return SAPP_KEYCODE_RIGHT_SUPER;
		case 122: return SAPP_KEYCODE_HOME;
		case 123: return SAPP_KEYCODE_END;
		case 124: return SAPP_KEYCODE_INSERT;
		case 160: return SAPP_KEYCODE_KP_ENTER;
		default: return SAPP_KEYCODE_INVALID;
	}
}

// KeyEvent.META_SHIFT_ON, META_ALT_ON, META_CTRL_ON and META_META_ON.
static uint32_t modifiersOf(int meta) {
	uint32_t m = 0;
	if (meta & 0x1) m |= SAPP_MODIFIER_SHIFT;
	if (meta & 0x2) m |= SAPP_MODIFIER_ALT;
	if (meta & 0x1000) m |= SAPP_MODIFIER_CTRL;
	if (meta & 0x10000) m |= SAPP_MODIFIER_SUPER;
	return m;
}

static int chordHeld(void) { return (s_modifiers & (SAPP_MODIFIER_CTRL | SAPP_MODIFIER_SUPER)) != 0; }

static void sendChar(uint32_t codepoint) {
	if (codepoint < 0x20 || codepoint == 0x7F) return;
	sapp_event e = makeEvent(SAPP_EVENTTYPE_CHAR);
	e.char_code = codepoint;
	voidAppEventDeliver(&e);
}

static size_t putUtf8(char *out, uint32_t c) {
	if (c < 0x80) { out[0] = (char)c; return 1; }
	if (c < 0x800) { out[0] = (char)(0xC0 | (c >> 6)); out[1] = (char)(0x80 | (c & 0x3F)); return 2; }
	if (c < 0x10000) {
		out[0] = (char)(0xE0 | (c >> 12)); out[1] = (char)(0x80 | ((c >> 6) & 0x3F)); out[2] = (char)(0x80 | (c & 0x3F));
		return 3;
	}
	out[0] = (char)(0xF0 | (c >> 18)); out[1] = (char)(0x80 | ((c >> 12) & 0x3F));
	out[2] = (char)(0x80 | ((c >> 6) & 0x3F)); out[3] = (char)(0x80 | (c & 0x3F));
	return 4;
}

// The codepoints of a Java string, which JNI's own UTF-8 would give as separate surrogate halves.
static size_t codepointsOf(JNIEnv *e, jstring s, uint32_t *out, size_t cap) {
	const jsize n = (*e)->GetStringLength(e, s);
	const jchar *units = (*e)->GetStringChars(e, s, NULL);
	size_t count = 0;
	for (jsize i = 0; i < n && count < cap; i++) {
		uint32_t c = units[i];
		if (c >= 0xD800 && c < 0xDC00 && i + 1 < n && units[i + 1] >= 0xDC00 && units[i + 1] < 0xE000) {
			c = 0x10000 + ((c - 0xD800) << 10) + (units[i + 1] - 0xDC00);
			i++;
		}
		out[count++] = c;
	}
	(*e)->ReleaseStringChars(e, s, units);
	return count;
}

#define TEXT_CAP 256

static void textOf(JNIEnv *e, jstring s, char *utf8, uint32_t *codepoints, size_t *count) {
	*count = codepointsOf(e, s, codepoints, TEXT_CAP);
	size_t at = 0;
	for (size_t i = 0; i < *count; i++) at += putUtf8(utf8 + at, codepoints[i]);
	utf8[at] = '\0';
}

static void commit(const char *utf8, const uint32_t *codepoints, size_t count) {
	if (s_textInput) {
		int printable = 0;
		for (size_t i = 0; i < count; i++) printable |= codepoints[i] >= 0x20 && codepoints[i] != 0x7F;
		if (printable) voidAppTextDeliver(VOID_EVENT_TEXT_INPUT, utf8, 0);
	} else {
		for (size_t i = 0; i < count; i++) sendChar(codepoints[i]);
	}
}

JNIEXPORT void JNICALL Java_dev_metascript_voidapp_VoidAppView_nativeCommit(JNIEnv *e, jobject self, jstring text) {
	(void)self;
	if (chordHeld()) return;
	char utf8[TEXT_CAP * 4 + 1];
	uint32_t codepoints[TEXT_CAP];
	size_t count;
	textOf(e, text, utf8, codepoints, &count);
	if (count == 1 && (codepoints[0] == '\n' || codepoints[0] == '\r')) {
		sendTap(SAPP_KEYCODE_ENTER);
		return;
	}
	if (count == 1 && codepoints[0] == '\t') {
		sendTap(SAPP_KEYCODE_TAB);
		return;
	}
	commit(utf8, codepoints, count);
}

JNIEXPORT void JNICALL Java_dev_metascript_voidapp_VoidAppView_nativePreedit(JNIEnv *e, jobject self, jstring text, jint cursor) {
	(void)self;
	if (!s_textInput) return;
	char utf8[TEXT_CAP * 4 + 1];
	uint32_t codepoints[TEXT_CAP];
	size_t count;
	textOf(e, text, utf8, codepoints, &count);
	voidAppTextDeliver(VOID_EVENT_PREEDIT, utf8, cursor);
}

JNIEXPORT jboolean JNICALL Java_dev_metascript_voidapp_VoidAppView_nativeKey(JNIEnv *e, jobject self,
	jboolean down, jint keyCode, jint metaState, jint repeat, jint unicode) {
	(void)e; (void)self;
	s_modifiers = modifiersOf(metaState);
	const sapp_keycode code = keyOfAndroid(keyCode);
	if (code != SAPP_KEYCODE_INVALID) sendKey(down ? SAPP_EVENTTYPE_KEY_DOWN : SAPP_EVENTTYPE_KEY_UP, code, repeat > 0);
	const int typed = down && unicode >= 0x20 && unicode != 0x7F && !chordHeld();
	if (typed) {
		char utf8[5];
		const uint32_t c = (uint32_t)unicode;
		utf8[putUtf8(utf8, c)] = '\0';
		commit(utf8, &c, 1);
	}
	return code != SAPP_KEYCODE_INVALID || typed;
}

JNIEXPORT void JNICALL Java_dev_metascript_voidapp_VoidAppView_nativeTouch(JNIEnv *e, jobject self,
	jint phase, jlongArray ids, jfloatArray xs, jfloatArray ys, jint changed) {
	(void)self;
	static const sapp_event_type types[] = {
		SAPP_EVENTTYPE_TOUCHES_BEGAN, SAPP_EVENTTYPE_TOUCHES_MOVED, SAPP_EVENTTYPE_TOUCHES_ENDED, SAPP_EVENTTYPE_TOUCHES_CANCELLED,
	};
	if (phase < 0 || phase > 3) voidFail("Android app driver: touch phase %d is not one of VoidAppView's four", phase);
	sapp_event ev = makeEvent(types[phase]);
	jsize n = (*e)->GetArrayLength(e, ids);
	if (n > SAPP_MAX_TOUCHPOINTS) n = SAPP_MAX_TOUCHPOINTS;
	jlong *id = (*e)->GetLongArrayElements(e, ids, NULL);
	jfloat *x = (*e)->GetFloatArrayElements(e, xs, NULL);
	jfloat *y = (*e)->GetFloatArrayElements(e, ys, NULL);
	for (jsize i = 0; i < n; i++) {
		sapp_touchpoint *p = &ev.touches[i];
		p->identifier = (uintptr_t)id[i];
		p->pos_x = x[i];
		p->pos_y = y[i];
		p->changed = changed < 0 || changed == i;
	}
	ev.num_touches = n;
	(*e)->ReleaseLongArrayElements(e, ids, id, JNI_ABORT);
	(*e)->ReleaseFloatArrayElements(e, xs, x, JNI_ABORT);
	(*e)->ReleaseFloatArrayElements(e, ys, y, JNI_ABORT);
	voidAppEventDeliver(&ev);
}

JNIEXPORT void JNICALL Java_dev_metascript_voidapp_VoidAppView_nativeInsets(JNIEnv *e, jobject self,
	jint top, jint left, jint bottom, jint right, jint keyboard) {
	(void)e; (void)self;
	const int changed = top != voidSafeAreaTop() || left != voidSafeAreaLeft() || bottom != voidSafeAreaBottom() ||
		right != voidSafeAreaRight() || keyboard != voidKeyboardHeight();
	voidAppSetSafeArea((float)top, (float)left, (float)bottom, (float)right);
	voidAppSetKeyboard((float)keyboard);
	if (changed && s_viewId != 0) send(SAPP_EVENTTYPE_RESIZED);
}

JNIEXPORT void JNICALL Java_dev_metascript_voidapp_VoidAppView_nativeFocus(JNIEnv *e, jobject self, jboolean focused) {
	(void)e; (void)self;
	if (!focused) s_modifiers = 0;
	if (s_viewId != 0) send(focused ? SAPP_EVENTTYPE_FOCUSED : SAPP_EVENTTYPE_UNFOCUSED);
}

JNIEXPORT void JNICALL Java_dev_metascript_voidapp_VoidAppView_nativeSurface(JNIEnv *e, jobject self, jobject surface, jint width, jint height) {
	(void)self;
	s_fbW = width > 0 ? width : 1;
	s_fbH = height > 0 ? height : 1;
	if (s_viewId == 0) {
		s_window = ANativeWindow_fromSurface(e, surface);
		if (!s_window) voidFail("Android app driver: the view's surface has no native window");
		s_viewId = voidViewCreate((long long)(intptr_t)s_window, s_fbW, s_fbH, s_scale);
	} else {
		voidViewResize(s_viewId, s_fbW, s_fbH, s_scale);
	}
	send(SAPP_EVENTTYPE_RESIZED);
}

static void dropView(void) {
	if (s_viewId != 0) voidViewDestroy(s_viewId);
	s_viewId = 0;
	if (s_window) ANativeWindow_release(s_window);
	s_window = NULL;
}

JNIEXPORT void JNICALL Java_dev_metascript_voidapp_VoidAppView_nativeSurfaceGone(JNIEnv *e, jobject self) {
	(void)e; (void)self;
	dropView();
}

JNIEXPORT void JNICALL Java_dev_metascript_voidapp_VoidAppView_nativeFrame(JNIEnv *e, jobject self) {
	(void)e; (void)self;
	if (s_viewId == 0) return;
	s_frameCount++;
	voidViewFrame(s_viewId);
}

static int s_logPipe[2];

static void *pumpLog(void *arg) {
	(void)arg;
	char line[1024];
	FILE *in = fdopen(s_logPipe[0], "r");
	while (in && fgets(line, sizeof line, in)) {
		const size_t n = strlen(line);
		if (n > 0 && line[n - 1] == '\n') line[n - 1] = '\0';
		__android_log_write(ANDROID_LOG_INFO, "MetaScript", line);
	}
	return NULL;
}

// An app process has no reader on stdout and stderr; console.log and voidFail go to logcat instead.
static void logToLogcat(void) {
	if (pipe(s_logPipe) != 0) return;
	setvbuf(stdout, NULL, _IOLBF, 0);
	setvbuf(stderr, NULL, _IONBF, 0);
	dup2(s_logPipe[1], STDOUT_FILENO);
	dup2(s_logPipe[1], STDERR_FILENO);
	pthread_t reader;
	if (pthread_create(&reader, NULL, pumpLog, NULL) == 0) pthread_detach(reader);
}

static jobject callObject(JNIEnv *e, jobject target, const char *name, const char *sig) {
	jclass cls = (*e)->GetObjectClass(e, target);
	jobject out = (*e)->CallObjectMethod(e, target, (*e)->GetMethodID(e, cls, name, sig));
	check(e, name);
	return out;
}

static void enterFilesDir(JNIEnv *e) {
	jobject dir = callObject(e, s_activity, "getFilesDir", "()Ljava/io/File;");
	jstring path = (jstring)callObject(e, dir, "getAbsolutePath", "()Ljava/lang/String;");
	const char *p = (*e)->GetStringUTFChars(e, path, NULL);
	if (chdir(p) != 0) voidFail("Android app driver: cannot enter the files dir %s", p);
	(*e)->ReleaseStringUTFChars(e, path, p);
}

static jclass appClass(JNIEnv *e, const char *dotted) {
	jclass loaderClass = (*e)->GetObjectClass(e, s_loader);
	jmethodID loadClass = (*e)->GetMethodID(e, loaderClass, "loadClass", "(Ljava/lang/String;)Ljava/lang/Class;");
	jstring name = (*e)->NewStringUTF(e, dotted);
	jclass cls = (jclass)(*e)->CallObjectMethod(e, s_loader, loadClass, name);
	check(e, dotted);
	return cls;
}

void voidAndroidAppStart(JNIEnv *e, jobject root) {
	if (s_started) voidFail("NativeApp.start: the Android app driver started already");
	s_started = 1;
	(*e)->GetJavaVM(e, &s_vm);
	logToLogcat();
	(*e)->PushLocalFrame(e, 32);
	jobject context = callObject(e, root, "getContext", "()Landroid/content/Context;");
	s_activity = (*e)->NewGlobalRef(e, context);
	s_loader = (*e)->NewGlobalRef(e, callObject(e, context, "getClassLoader", "()Ljava/lang/ClassLoader;"));
	jobject resources = callObject(e, context, "getResources", "()Landroid/content/res/Resources;");
	jobject metrics = callObject(e, resources, "getDisplayMetrics", "()Landroid/util/DisplayMetrics;");
	s_scale = (*e)->GetFloatField(e, metrics, (*e)->GetFieldID(e, (*e)->GetObjectClass(e, metrics), "density", "F"));
	check(e, "DisplayMetrics.density");
	enterFilesDir(e);

	MsMain();
	if (!s_running) voidFail("NativeApp.start: the program returned without calling voidRun");

	jclass viewClass = appClass(e, "dev.metascript.voidapp.VoidAppView");
	jobject view = (*e)->NewObject(e, viewClass, (*e)->GetMethodID(e, viewClass, "<init>", "(Landroid/content/Context;)V"), context);
	check(e, "new VoidAppView");
	s_view = (*e)->NewGlobalRef(e, view);
	s_setRunning = (*e)->GetMethodID(e, viewClass, "setRunning", "(Z)V");
	s_setTextInput = (*e)->GetMethodID(e, viewClass, "setTextInput", "(Z)V");
	s_detach = (*e)->GetMethodID(e, viewClass, "detach", "()V");
	(*e)->CallVoidMethod(e, view, (*e)->GetMethodID(e, viewClass, "attach", "(Landroid/widget/FrameLayout;)V"), root);
	check(e, "VoidAppView.attach");
	(*e)->PopLocalFrame(e, NULL);
}

void voidAndroidAppPause(JNIEnv *e) {
	if (!s_view) return;
	(*e)->CallVoidMethod(e, s_view, s_setRunning, JNI_FALSE);
	check(e, "VoidAppView.setRunning");
	if (s_frameCount > 0) send(SAPP_EVENTTYPE_SUSPENDED);
}

void voidAndroidAppResume(JNIEnv *e) {
	if (!s_view) return;
	(*e)->CallVoidMethod(e, s_view, s_setRunning, JNI_TRUE);
	check(e, "VoidAppView.setRunning");
	if (s_frameCount > 0) send(SAPP_EVENTTYPE_RESUMED);
}

void voidAndroidAppDestroy(JNIEnv *e) {
	if (!s_view) return;
	(*e)->CallVoidMethod(e, s_view, s_detach);
	check(e, "VoidAppView.detach");
	dropView();
	(*e)->DeleteGlobalRef(e, s_view);
	s_view = NULL;
}

JNIEnv *voidAndroidEnv(void) {
	JNIEnv *e = NULL;
	if (!s_vm || (*s_vm)->GetEnv(s_vm, (void **)&e, JNI_VERSION_1_6) != JNI_OK) {
		voidFail("voidAndroidEnv: called before NativeApp.start or off a Java thread");
	}
	return e;
}

jobject voidAndroidClassLoader(void) { return s_loader; }
jobject voidAndroidActivity(void) { return s_activity; }

void voidRequestedSize(int *w, int *h) { *w = s_reqW; *h = s_reqH; }

void voidRunConfigured(int w, int h, int sampleCount, int highDpi, msClosure init, msClosure frame) {
	if (s_running) voidFail("voidRun: the Android app is already running");
	if (!s_started) voidFail("voidRun: an Android app runs from NativeApp.start; this process has no app shell");
	if (!highDpi) voidFail("voidRunConfigured: highDpi 0 is not supported by the Android app driver");
	s_running = 1;
	s_reqW = w;
	s_reqH = h;
	voidEmbedRegister(init, frame);
	voidViewsSetSampleCount(sampleCount);
}

void voidRun(int w, int h, msClosure init, msClosure frame) {
	voidRunConfigured(w, h, 1, 1, init, frame);
}

void voidSetTextInput(int on) {
	const int was = s_textInput;
	s_textInput = on ? 1 : 0;
	if (!s_view || was == s_textInput) return;
	JNIEnv *e = voidAndroidEnv();
	(*e)->CallVoidMethod(e, s_view, s_setTextInput, s_textInput ? JNI_TRUE : JNI_FALSE);
	check(e, "VoidAppView.setTextInput");
}

void voidSetImeRect(int x, int y, int w, int h) { (void)x; (void)y; (void)w; (void)h; }

int voidAndroidAppFbWidth(void) { return s_running && voidCurrentView() == 0 ? s_fbW : voidViewsFbWidth(); }
int voidAndroidAppFbHeight(void) { return s_running && voidCurrentView() == 0 ? s_fbH : voidViewsFbHeight(); }
float voidAndroidAppDpiScale(void) { return s_running && voidCurrentView() == 0 ? s_scale : voidViewsDpiScale(); }
