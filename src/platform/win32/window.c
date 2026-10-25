#include "window.h"

#include <windowsx.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <shellapi.h>

#include "../frameTiming.h"

#define CLASS_NAME L"VOIDWINDOW"
#define TITLE_UNITS 256

static const int16_t keyTable[VOID_KEY_COUNT] = {
	[0x00B] = VOID_KEY_0,
	[0x002] = VOID_KEY_1,
	[0x003] = VOID_KEY_2,
	[0x004] = VOID_KEY_3,
	[0x005] = VOID_KEY_4,
	[0x006] = VOID_KEY_5,
	[0x007] = VOID_KEY_6,
	[0x008] = VOID_KEY_7,
	[0x009] = VOID_KEY_8,
	[0x00A] = VOID_KEY_9,
	[0x01E] = VOID_KEY_A,
	[0x030] = VOID_KEY_B,
	[0x02E] = VOID_KEY_C,
	[0x020] = VOID_KEY_D,
	[0x012] = VOID_KEY_E,
	[0x021] = VOID_KEY_F,
	[0x022] = VOID_KEY_G,
	[0x023] = VOID_KEY_H,
	[0x017] = VOID_KEY_I,
	[0x024] = VOID_KEY_J,
	[0x025] = VOID_KEY_K,
	[0x026] = VOID_KEY_L,
	[0x032] = VOID_KEY_M,
	[0x031] = VOID_KEY_N,
	[0x018] = VOID_KEY_O,
	[0x019] = VOID_KEY_P,
	[0x010] = VOID_KEY_Q,
	[0x013] = VOID_KEY_R,
	[0x01F] = VOID_KEY_S,
	[0x014] = VOID_KEY_T,
	[0x016] = VOID_KEY_U,
	[0x02F] = VOID_KEY_V,
	[0x011] = VOID_KEY_W,
	[0x02D] = VOID_KEY_X,
	[0x015] = VOID_KEY_Y,
	[0x02C] = VOID_KEY_Z,
	[0x028] = VOID_KEY_APOSTROPHE,
	[0x02B] = VOID_KEY_BACKSLASH,
	[0x033] = VOID_KEY_COMMA,
	[0x00D] = VOID_KEY_EQUAL,
	[0x029] = VOID_KEY_GRAVE_ACCENT,
	[0x01A] = VOID_KEY_LEFT_BRACKET,
	[0x00C] = VOID_KEY_MINUS,
	[0x034] = VOID_KEY_PERIOD,
	[0x01B] = VOID_KEY_RIGHT_BRACKET,
	[0x027] = VOID_KEY_SEMICOLON,
	[0x035] = VOID_KEY_SLASH,
	[0x056] = VOID_KEY_WORLD_2,
	[0x00E] = VOID_KEY_BACKSPACE,
	[0x153] = VOID_KEY_DELETE,
	[0x14F] = VOID_KEY_END,
	[0x01C] = VOID_KEY_ENTER,
	[0x001] = VOID_KEY_ESCAPE,
	[0x147] = VOID_KEY_HOME,
	[0x152] = VOID_KEY_INSERT,
	[0x15D] = VOID_KEY_MENU,
	[0x151] = VOID_KEY_PAGE_DOWN,
	[0x149] = VOID_KEY_PAGE_UP,
	[0x045] = VOID_KEY_PAUSE,
	[0x146] = VOID_KEY_PAUSE,
	[0x039] = VOID_KEY_SPACE,
	[0x00F] = VOID_KEY_TAB,
	[0x03A] = VOID_KEY_CAPS_LOCK,
	[0x145] = VOID_KEY_NUM_LOCK,
	[0x046] = VOID_KEY_SCROLL_LOCK,
	[0x03B] = VOID_KEY_F1,
	[0x03C] = VOID_KEY_F2,
	[0x03D] = VOID_KEY_F3,
	[0x03E] = VOID_KEY_F4,
	[0x03F] = VOID_KEY_F5,
	[0x040] = VOID_KEY_F6,
	[0x041] = VOID_KEY_F7,
	[0x042] = VOID_KEY_F8,
	[0x043] = VOID_KEY_F9,
	[0x044] = VOID_KEY_F10,
	[0x057] = VOID_KEY_F11,
	[0x058] = VOID_KEY_F12,
	[0x064] = VOID_KEY_F13,
	[0x065] = VOID_KEY_F14,
	[0x066] = VOID_KEY_F15,
	[0x067] = VOID_KEY_F16,
	[0x068] = VOID_KEY_F17,
	[0x069] = VOID_KEY_F18,
	[0x06A] = VOID_KEY_F19,
	[0x06B] = VOID_KEY_F20,
	[0x06C] = VOID_KEY_F21,
	[0x06D] = VOID_KEY_F22,
	[0x06E] = VOID_KEY_F23,
	[0x076] = VOID_KEY_F24,
	[0x038] = VOID_KEY_LEFT_ALT,
	[0x01D] = VOID_KEY_LEFT_CONTROL,
	[0x02A] = VOID_KEY_LEFT_SHIFT,
	[0x15B] = VOID_KEY_LEFT_SUPER,
	[0x137] = VOID_KEY_PRINT_SCREEN,
	[0x138] = VOID_KEY_RIGHT_ALT,
	[0x11D] = VOID_KEY_RIGHT_CONTROL,
	[0x036] = VOID_KEY_RIGHT_SHIFT,
	[0x136] = VOID_KEY_RIGHT_SHIFT,
	[0x15C] = VOID_KEY_RIGHT_SUPER,
	[0x150] = VOID_KEY_DOWN,
	[0x14B] = VOID_KEY_LEFT,
	[0x14D] = VOID_KEY_RIGHT,
	[0x148] = VOID_KEY_UP,
	[0x052] = VOID_KEY_KP_0,
	[0x04F] = VOID_KEY_KP_1,
	[0x050] = VOID_KEY_KP_2,
	[0x051] = VOID_KEY_KP_3,
	[0x04B] = VOID_KEY_KP_4,
	[0x04C] = VOID_KEY_KP_5,
	[0x04D] = VOID_KEY_KP_6,
	[0x047] = VOID_KEY_KP_7,
	[0x048] = VOID_KEY_KP_8,
	[0x049] = VOID_KEY_KP_9,
	[0x04E] = VOID_KEY_KP_ADD,
	[0x053] = VOID_KEY_KP_DECIMAL,
	[0x135] = VOID_KEY_KP_DIVIDE,
	[0x11C] = VOID_KEY_KP_ENTER,
	[0x037] = VOID_KEY_KP_MULTIPLY,
	[0x04A] = VOID_KEY_KP_SUBTRACT,
};

typedef struct {
	bool aware;
	float contentScale;
	float windowScale;
	float mouseScale;
} Dpi;

static struct {
	VoidWin32Desc desc;
	HWND hwnd;
	Dpi dpi;
	bool valid;
	bool inCreateWindow;
	bool initCalled;
	bool cleanupCalled;
	bool quitRequested;
	bool quitOrdered;
	bool iconified;
	WCHAR surrogate;
	uint64_t frameCount;
	int windowWidth;
	int windowHeight;
	int framebufferWidth;
	int framebufferHeight;
	struct {
		float x, y, dx, dy;
		bool posValid;
		bool tracked;
		uint8_t captureMask;
		bool shown;
		bool locked;
		bool requestedLock;
		int cursor;
		bool lockPosValid;
		POINT lockPos;
		bool rawPosValid;
		LONG rawX, rawY;
	} mouse;
	HCURSOR standardCursors[VOID_CURSOR_COUNT];
	VoidFrameTiming timing;
	bool fullscreen;
	RECT storedWindowRect;
	int droppedCount;
	char **droppedPaths;
	char *clipboard;
	VoidKeysHeld keysHeld;
	VoidAppEvent event;
} s;

__attribute__((noreturn)) static void fail(const char *what) {
	fprintf(stderr, "void: %s failed: %lu\n", what, GetLastError());
	abort();
}

static int roundAtLeastOne(float f) {
	int v = (int)roundf(f);
	return v <= 0 ? 1 : v;
}

static bool eventsEnabled(void) { return s.desc.event != NULL && s.initCalled; }

static void initEvent(VoidAppEventType type) {
	memset(&s.event, 0, sizeof s.event);
	s.event.type = type;
	s.event.frameCount = s.frameCount;
	s.event.mouseButton = VOID_MOUSE_INVALID;
	s.event.windowWidth = s.windowWidth;
	s.event.windowHeight = s.windowHeight;
	s.event.framebufferWidth = s.framebufferWidth;
	s.event.framebufferHeight = s.framebufferHeight;
	s.event.mouseX = s.mouse.x;
	s.event.mouseY = s.mouse.y;
	s.event.mouseDx = s.mouse.dx;
	s.event.mouseDy = s.mouse.dy;
}

static void callEvent(void) {
	if (!s.cleanupCalled) s.desc.event(&s.event);
}

static void appEvent(VoidAppEventType type) {
	if (!eventsEnabled()) return;
	initEvent(type);
	callEvent();
}

static uint32_t mods(void) {
	uint32_t m = 0;
	if (GetKeyState(VK_SHIFT) & (1 << 15)) m |= VOID_MODIFIER_SHIFT;
	if (GetKeyState(VK_CONTROL) & (1 << 15)) m |= VOID_MODIFIER_CTRL;
	if (GetKeyState(VK_MENU) & (1 << 15)) m |= VOID_MODIFIER_ALT;
	if ((GetKeyState(VK_LWIN) | GetKeyState(VK_RWIN)) & (1 << 15)) m |= VOID_MODIFIER_SUPER;
	const bool swapped = GetSystemMetrics(SM_SWAPBUTTON) == TRUE;
	if (GetAsyncKeyState(VK_LBUTTON)) m |= swapped ? VOID_MODIFIER_RMB : VOID_MODIFIER_LMB;
	if (GetAsyncKeyState(VK_RBUTTON)) m |= swapped ? VOID_MODIFIER_LMB : VOID_MODIFIER_RMB;
	if (GetAsyncKeyState(VK_MBUTTON)) m |= VOID_MODIFIER_MMB;
	return m;
}

static bool updateDimensions(void) {
	RECT rect;
	if (!GetClientRect(s.hwnd, &rect)) {
		s.windowWidth = s.windowHeight = 1;
		s.framebufferWidth = s.framebufferHeight = 1;
		return false;
	}
	const float w = (float)(rect.right - rect.left) / s.dpi.windowScale;
	const float h = (float)(rect.bottom - rect.top) / s.dpi.windowScale;
	if (w == 0.0f && h == 0.0f) return false;
	s.windowWidth = roundAtLeastOne(w);
	s.windowHeight = roundAtLeastOne(h);
	const int fbWidth = roundAtLeastOne(w * s.dpi.contentScale);
	const int fbHeight = roundAtLeastOne(h * s.dpi.contentScale);
	if (fbWidth == s.framebufferWidth && fbHeight == s.framebufferHeight) return false;
	s.framebufferWidth = fbWidth;
	s.framebufferHeight = fbHeight;
	return true;
}

static void captureMouse(uint8_t mask) {
	if (s.mouse.captureMask == 0) SetCapture(s.hwnd);
	s.mouse.captureMask |= mask;
}

static void releaseMouse(uint8_t mask) {
	if (s.mouse.captureMask == 0) return;
	s.mouse.captureMask &= (uint8_t)~mask;
	if (s.mouse.captureMask == 0) ReleaseCapture();
}

static void mouseUpdate(LPARAM lParam) {
	if (s.mouse.locked) return;
	const float x = (float)GET_X_LPARAM(lParam) * s.dpi.mouseScale;
	const float y = (float)GET_Y_LPARAM(lParam) * s.dpi.mouseScale;
	if (s.mouse.posValid) {
		s.mouse.dx = x - s.mouse.x;
		s.mouse.dy = y - s.mouse.y;
	}
	s.mouse.x = x;
	s.mouse.y = y;
	s.mouse.posValid = true;
}

static void mouseEvent(VoidAppEventType type, VoidMouseButton button) {
	if (!eventsEnabled()) return;
	initEvent(type);
	s.event.modifiers = mods();
	s.event.mouseButton = button;
	callEvent();
}

static void mouseButtonEvent(LPARAM lParam, VoidAppEventType type, VoidMouseButton button) {
	mouseUpdate(lParam);
	mouseEvent(type, button);
	if (type == VOID_EVENT_MOUSE_DOWN) captureMouse((uint8_t)(1 << button));
	else releaseMouse((uint8_t)(1 << button));
}

static void scrollEvent(float x, float y) {
	if (!eventsEnabled()) return;
	initEvent(VOID_EVENT_MOUSE_SCROLL);
	s.event.modifiers = mods();
	s.event.scrollX = x;
	s.event.scrollY = y;
	callEvent();
}

static void keyEvent(VoidAppEventType type, int scanCode, bool repeat) {
	if (!eventsEnabled() || scanCode >= VOID_KEY_COUNT) return;
	initEvent(type);
	s.event.modifiers = mods();
	s.event.keyCode = (VoidKeyCode)keyTable[scanCode];
	s.event.keyRepeat = repeat;
	voidKeysHeldTrack(&s.keysHeld, type, s.event.keyCode);
	callEvent();
	if (type == VOID_EVENT_KEY_DOWN && s.event.modifiers == VOID_MODIFIER_CTRL && s.event.keyCode == VOID_KEY_V) {
		initEvent(VOID_EVENT_CLIPBOARD_PASTED);
		callEvent();
	}
}

static void releaseKey(VoidKeyCode key) {
	if (!eventsEnabled()) return;
	initEvent(VOID_EVENT_KEY_UP);
	s.event.keyCode = key;
	callEvent();
}

static void charEvent(uint32_t c, bool repeat) {
	if (!eventsEnabled() || c < 32) return;
	if (c >= 0xD800 && c <= 0xDBFF) {
		s.surrogate = (WCHAR)(c - 0xD800);
		return;
	}
	if (c > 0xDC00 && c <= 0xDFFF) {
		c = ((uint32_t)s.surrogate << 10 | (c - 0xDC00)) + 0x10000;
		s.surrogate = 0;
	}
	initEvent(VOID_EVENT_CHAR);
	s.event.modifiers = mods();
	s.event.charCode = c;
	s.event.keyRepeat = repeat;
	callEvent();
}

static char *wideToUtf8(const WCHAR *wide) {
	const int bytes = WideCharToMultiByte(CP_UTF8, 0, wide, -1, NULL, 0, NULL, NULL);
	if (bytes <= 0) fail("WideCharToMultiByte");
	char *utf8 = (char *)malloc((size_t)bytes);
	if (utf8 == NULL) fail("malloc for a UTF-8 string");
	if (WideCharToMultiByte(CP_UTF8, 0, wide, -1, utf8, bytes, NULL, NULL) == 0) fail("WideCharToMultiByte");
	return utf8;
}

static WCHAR *utf8ToWide(const char *utf8) {
	const int units = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, NULL, 0);
	if (units <= 0) fail("MultiByteToWideChar");
	WCHAR *wide = (WCHAR *)malloc((size_t)units * sizeof(WCHAR));
	if (wide == NULL) fail("malloc for a UTF-16 string");
	if (MultiByteToWideChar(CP_UTF8, 0, utf8, -1, wide, units) == 0) fail("MultiByteToWideChar");
	return wide;
}

static void setScales(float windowScale) {
	s.dpi.windowScale = windowScale;
	s.dpi.contentScale = s.desc.highDpi ? windowScale : 1.0f;
	s.dpi.mouseScale = s.desc.highDpi ? 1.0f : 1.0f / windowScale;
}

static void dpiChanged(HWND hwnd, const RECT *proposed) {
	if (!s.dpi.aware) return;
	setScales((float)GetDpiForWindow(hwnd) / 96.0f);
	SetWindowPos(hwnd, NULL, proposed->left, proposed->top, proposed->right - proposed->left,
		proposed->bottom - proposed->top, SWP_NOZORDER | SWP_NOACTIVATE);
}

static void setFullscreen(bool fullscreen, UINT swpFlags) {
	HMONITOR monitor = MonitorFromWindow(s.hwnd, MONITOR_DEFAULTTONEAREST);
	MONITORINFO minfo;
	ZeroMemory(&minfo, sizeof minfo);
	minfo.cbSize = sizeof minfo;
	GetMonitorInfoW(monitor, &minfo);
	const DWORD exStyle = WS_EX_APPWINDOW | WS_EX_WINDOWEDGE;
	DWORD style;
	RECT rect;
	s.fullscreen = fullscreen;
	if (!s.fullscreen) {
		style = WS_CLIPSIBLINGS | WS_CLIPCHILDREN | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_SIZEBOX;
		rect = s.storedWindowRect;
	} else {
		GetWindowRect(s.hwnd, &s.storedWindowRect);
		style = WS_POPUP | WS_SYSMENU | WS_VISIBLE;
		rect = minfo.rcMonitor;
		AdjustWindowRectEx(&rect, style, FALSE, exStyle);
	}
	SetWindowLongPtrW(s.hwnd, GWL_STYLE, (LONG_PTR)style);
	SetWindowPos(s.hwnd, HWND_TOP, rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top, swpFlags | SWP_FRAMECHANGED);
}

static void initCursors(void) {
	static const int ids[VOID_CURSOR_COUNT] = {
		[VOID_CURSOR_ARROW] = 32512,
		[VOID_CURSOR_IBEAM] = 32513,
		[VOID_CURSOR_CROSSHAIR] = 32515,
		[VOID_CURSOR_POINTING_HAND] = 32649,
		[VOID_CURSOR_RESIZE_EW] = 32644,
		[VOID_CURSOR_RESIZE_NS] = 32645,
		[VOID_CURSOR_RESIZE_NWSE] = 32642,
		[VOID_CURSOR_RESIZE_NESW] = 32643,
		[VOID_CURSOR_RESIZE_ALL] = 32646,
		[VOID_CURSOR_NOT_ALLOWED] = 32648,
	};
	for (int i = 0; i < VOID_CURSOR_COUNT; i++) {
		if (ids[i] != 0) s.standardCursors[i] = (HCURSOR)LoadImageW(NULL, MAKEINTRESOURCEW(ids[i]), IMAGE_CURSOR, 0, 0, LR_DEFAULTSIZE | LR_SHARED);
		if (s.standardCursors[i] == NULL) s.standardCursors[i] = LoadCursorW(NULL, MAKEINTRESOURCEW(32512));
	}
}

static bool cursorInContentArea(void) {
	POINT pos;
	if (!GetCursorPos(&pos)) return false;
	if (WindowFromPoint(pos) != s.hwnd) return false;
	RECT area;
	GetClientRect(s.hwnd, &area);
	ClientToScreen(s.hwnd, (POINT *)&area.left);
	ClientToScreen(s.hwnd, (POINT *)&area.right);
	return PtInRect(&area, pos) == TRUE;
}

static void updateCursor(bool skipAreaTest) {
	if (!skipAreaTest && !cursorInContentArea()) return;
	SetCursor(s.mouse.shown ? s.standardCursors[s.mouse.cursor] : NULL);
}

static void doLockMouse(void) {
	s.mouse.locked = true;
	ShowCursor(FALSE);
	s.mouse.dx = 0.0f;
	s.mouse.dy = 0.0f;
	releaseMouse(0xFF);
	s.mouse.lockPosValid = GetCursorPos(&s.mouse.lockPos) != 0;
	RECT client;
	GetClientRect(s.hwnd, &client);
	POINT mid = { (client.right - client.left) / 2, (client.bottom - client.top) / 2 };
	ClientToScreen(s.hwnd, &mid);
	RECT clip = { mid.x, mid.y, mid.x, mid.y };
	ClipCursor(&clip);
	const RAWINPUTDEVICE rid = { 0x01, 0x02, 0, s.hwnd };
	if (!RegisterRawInputDevices(&rid, 1, sizeof rid)) fail("RegisterRawInputDevices for the mouse lock");
	s.mouse.rawPosValid = false;
}

static void doUnlockMouse(void) {
	s.mouse.locked = false;
	ShowCursor(TRUE);
	s.mouse.dx = 0.0f;
	s.mouse.dy = 0.0f;
	releaseMouse(0xFF);
	const RAWINPUTDEVICE rid = { 0x01, 0x02, RIDEV_REMOVE, NULL };
	if (!RegisterRawInputDevices(&rid, 1, sizeof rid)) fail("RegisterRawInputDevices to end the mouse lock");
	ClipCursor(NULL);
	if (s.mouse.lockPosValid) {
		SetCursorPos(s.mouse.lockPos.x, s.mouse.lockPos.y);
		s.mouse.lockPosValid = false;
	}
}

static void updateMouseLock(void) {
	if (s.hwnd != GetForegroundWindow()) {
		if (s.mouse.locked) doUnlockMouse();
		return;
	}
	if (s.mouse.requestedLock == s.mouse.locked) return;
	if (s.mouse.requestedLock) doLockMouse();
	else doUnlockMouse();
}

static void rawMouseInput(LPARAM lParam) {
	RAWINPUT raw;
	UINT size = sizeof raw;
	if (GetRawInputData((HRAWINPUT)lParam, RID_INPUT, &raw, &size, sizeof(RAWINPUTHEADER)) == (UINT)-1) fail("GetRawInputData");
	if (raw.data.mouse.usFlags & MOUSE_MOVE_ABSOLUTE) {
		const LONG x = raw.data.mouse.lLastX;
		const LONG y = raw.data.mouse.lLastY;
		if (s.mouse.rawPosValid) {
			s.mouse.dx = (float)(x - s.mouse.rawX);
			s.mouse.dy = (float)(y - s.mouse.rawY);
		}
		s.mouse.rawX = x;
		s.mouse.rawY = y;
		s.mouse.rawPosValid = true;
	} else {
		s.mouse.dx = (float)raw.data.mouse.lLastX;
		s.mouse.dy = (float)raw.data.mouse.lLastY;
	}
	mouseEvent(VOID_EVENT_MOUSE_MOVE, VOID_MOUSE_INVALID);
}

static void clearDropped(void) {
	for (int i = 0; i < s.droppedCount; i++) free(s.droppedPaths[i]);
	free(s.droppedPaths);
	s.droppedPaths = NULL;
	s.droppedCount = 0;
}

static void filesDropped(HDROP hdrop) {
	clearDropped();
	const int count = (int)DragQueryFileW(hdrop, 0xffffffff, NULL, 0);
	s.droppedPaths = (char **)calloc((size_t)(count > 0 ? count : 1), sizeof(char *));
	if (s.droppedPaths == NULL) fail("calloc for the dropped file paths");
	for (int i = 0; i < count; i++) {
		const UINT units = DragQueryFileW(hdrop, (UINT)i, NULL, 0) + 1;
		WCHAR *wide = (WCHAR *)calloc(units, sizeof(WCHAR));
		if (wide == NULL) fail("calloc for a dropped file path");
		DragQueryFileW(hdrop, (UINT)i, wide, units);
		s.droppedPaths[i] = wideToUtf8(wide);
		free(wide);
	}
	s.droppedCount = count;
	DragFinish(hdrop);
	if (eventsEnabled()) {
		initEvent(VOID_EVENT_FILES_DROPPED);
		s.event.modifiers = mods();
		callEvent();
	}
}

static void frame(bool fromWndProc) {
	if (!s.initCalled) {
		if (s.desc.init) s.desc.init();
		s.initCalled = true;
	}
	if (!s.cleanupCalled && s.desc.frame) s.desc.frame();
	s.frameCount++;
	if (!fromWndProc && IsIconic(s.hwnd)) Sleep(16);
}

static LRESULT CALLBACK wndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
	if (s.inCreateWindow) return DefWindowProcW(hwnd, msg, wParam, lParam);
	switch (msg) {
		case WM_CLOSE:
			if (!s.quitOrdered) {
				s.quitRequested = true;
				appEvent(VOID_EVENT_QUIT_REQUESTED);
				if (s.quitRequested) s.quitOrdered = true;
			}
			if (s.quitOrdered) PostQuitMessage(0);
			return 0;
		case WM_SYSCOMMAND:
			if ((wParam & 0xFFF0) == SC_KEYMENU) return 0;
			break;
		case WM_ERASEBKGND:
			return 1;
		case WM_SIZE: {
			const bool iconified = wParam == SIZE_MINIMIZED;
			if (iconified != s.iconified) {
				s.iconified = iconified;
				appEvent(iconified ? VOID_EVENT_ICONIFIED : VOID_EVENT_RESTORED);
			}
			break;
		}
		case WM_SETCURSOR:
			if (LOWORD(lParam) == HTCLIENT) {
				updateCursor(true);
				return TRUE;
			}
			break;
		case WM_DROPFILES: filesDropped((HDROP)wParam); break;
		case WM_INPUT:
			if (s.mouse.locked) rawMouseInput(lParam);
			break;
		case WM_SETFOCUS: appEvent(VOID_EVENT_FOCUSED); break;
		case WM_KILLFOCUS:
			voidKeysHeldRelease(&s.keysHeld, releaseKey);
			appEvent(VOID_EVENT_UNFOCUSED);
			break;
		case WM_DPICHANGED: dpiChanged(hwnd, (const RECT *)lParam); break;
		case WM_LBUTTONDOWN: mouseButtonEvent(lParam, VOID_EVENT_MOUSE_DOWN, VOID_MOUSE_LEFT); break;
		case WM_RBUTTONDOWN: mouseButtonEvent(lParam, VOID_EVENT_MOUSE_DOWN, VOID_MOUSE_RIGHT); break;
		case WM_MBUTTONDOWN: mouseButtonEvent(lParam, VOID_EVENT_MOUSE_DOWN, VOID_MOUSE_MIDDLE); break;
		case WM_LBUTTONUP: mouseButtonEvent(lParam, VOID_EVENT_MOUSE_UP, VOID_MOUSE_LEFT); break;
		case WM_RBUTTONUP: mouseButtonEvent(lParam, VOID_EVENT_MOUSE_UP, VOID_MOUSE_RIGHT); break;
		case WM_MBUTTONUP: mouseButtonEvent(lParam, VOID_EVENT_MOUSE_UP, VOID_MOUSE_MIDDLE); break;
		case WM_MOUSEMOVE:
			if (s.mouse.locked) break;
			mouseUpdate(lParam);
			if (!s.mouse.tracked) {
				s.mouse.tracked = true;
				TRACKMOUSEEVENT tme;
				ZeroMemory(&tme, sizeof tme);
				tme.cbSize = sizeof tme;
				tme.dwFlags = TME_LEAVE;
				tme.hwndTrack = s.hwnd;
				TrackMouseEvent(&tme);
				s.mouse.dx = 0.0f;
				s.mouse.dy = 0.0f;
				mouseEvent(VOID_EVENT_MOUSE_ENTER, VOID_MOUSE_INVALID);
			}
			mouseEvent(VOID_EVENT_MOUSE_MOVE, VOID_MOUSE_INVALID);
			break;
		case WM_MOUSELEAVE:
			if (s.mouse.locked) break;
			s.mouse.dx = 0.0f;
			s.mouse.dy = 0.0f;
			s.mouse.tracked = false;
			mouseEvent(VOID_EVENT_MOUSE_LEAVE, VOID_MOUSE_INVALID);
			break;
		case WM_MOUSEWHEEL:
			scrollEvent(0.0f, (float)GET_WHEEL_DELTA_WPARAM(wParam) / (float)WHEEL_DELTA);
			break;
		case WM_MOUSEHWHEEL:
			scrollEvent(-(float)GET_WHEEL_DELTA_WPARAM(wParam) / (float)WHEEL_DELTA, 0.0f);
			break;
		case WM_CHAR: charEvent((uint32_t)wParam, (lParam & 0x40000000) != 0); break;
		case WM_KEYDOWN:
		case WM_SYSKEYDOWN:
			keyEvent(VOID_EVENT_KEY_DOWN, (int)(HIWORD(lParam) & 0x1FF), (lParam & 0x40000000) != 0);
			break;
		case WM_KEYUP:
		case WM_SYSKEYUP:
			keyEvent(VOID_EVENT_KEY_UP, (int)(HIWORD(lParam) & 0x1FF), false);
			break;
		case WM_ENTERSIZEMOVE: SetTimer(s.hwnd, 1, USER_TIMER_MINIMUM, NULL); break;
		case WM_EXITSIZEMOVE: KillTimer(s.hwnd, 1); break;
		case WM_TIMER:
			voidFrameTimingUpdate(&s.timing, 0.0);
			frame(true);
			break;
		case WM_NCLBUTTONDOWN:
			if (SendMessageW(s.hwnd, WM_NCHITTEST, wParam, lParam) == HTCAPTION) {
				POINT point = { 0, 0 };
				if (GetCursorPos(&point)) {
					ScreenToClient(s.hwnd, &point);
					PostMessageW(s.hwnd, WM_MOUSEMOVE, 0, (LPARAM)(((uint32_t)point.x) | (((uint32_t)point.y) << 16)));
				}
			}
			break;
		default: break;
	}
	return DefWindowProcW(hwnd, msg, wParam, lParam);
}

typedef BOOL(WINAPI *SetProcessDpiAwareFn)(void);
typedef BOOL(WINAPI *SetProcessDpiAwarenessContextFn)(HANDLE);
typedef HRESULT(WINAPI *SetProcessDpiAwarenessFn)(int);
typedef HRESULT(WINAPI *GetDpiForMonitorFn)(HMONITOR, int, UINT *, UINT *);

static void initDpi(void) {
	enum { processDpiUnaware = 0, processSystemDpiAware = 1, monitorEffectiveDpi = 0 };
	HMODULE user32 = LoadLibraryA("user32.dll");
	HMODULE shcore = LoadLibraryA("shcore.dll");
	SetProcessDpiAwareFn setAware = user32 ? (SetProcessDpiAwareFn)(void *)GetProcAddress(user32, "SetProcessDPIAware") : NULL;
	SetProcessDpiAwarenessContextFn setContext = user32 ? (SetProcessDpiAwarenessContextFn)(void *)GetProcAddress(user32, "SetProcessDpiAwarenessContext") : NULL;
	SetProcessDpiAwarenessFn setAwareness = shcore ? (SetProcessDpiAwarenessFn)(void *)GetProcAddress(shcore, "SetProcessDpiAwareness") : NULL;
	GetDpiForMonitorFn getDpiForMonitor = shcore ? (GetDpiForMonitorFn)(void *)GetProcAddress(shcore, "GetDpiForMonitor") : NULL;
	if (!s.desc.highDpi) {
		s.dpi.aware = false;
		if (setAwareness) setAwareness(processDpiUnaware);
	} else if (setAwareness) {
		s.dpi.aware = true;
		if (!(setContext && setContext((HANDLE)(intptr_t)-4))) setAwareness(processSystemDpiAware);
	} else if (setAware) {
		s.dpi.aware = true;
		setAware();
	}
	float windowScale = 1.0f;
	if (getDpiForMonitor && s.dpi.aware) {
		POINT pt = { 1, 1 };
		UINT dpiX = 96, dpiY = 96;
		if (FAILED(getDpiForMonitor(MonitorFromPoint(pt, MONITOR_DEFAULTTONEAREST), monitorEffectiveDpi, &dpiX, &dpiY))) fail("GetDpiForMonitor");
		windowScale = (float)dpiX / 96.0f;
	}
	setScales(windowScale);
	if (user32) FreeLibrary(user32);
	if (shcore) FreeLibrary(shcore);
}

static void toWide(const char *utf8, WCHAR *wide) {
	if (MultiByteToWideChar(CP_UTF8, 0, utf8, -1, wide, TITLE_UNITS) == 0) fail("MultiByteToWideChar on the window title");
}

static void createWindow(void) {
	WNDCLASSW wc;
	ZeroMemory(&wc, sizeof wc);
	wc.style = CS_HREDRAW | CS_VREDRAW | CS_OWNDC;
	wc.lpfnWndProc = wndProc;
	wc.hInstance = GetModuleHandleW(NULL);
	wc.hCursor = LoadCursorW(NULL, (LPCWSTR)IDC_ARROW);
	wc.hIcon = LoadIconW(NULL, (LPCWSTR)IDI_WINLOGO);
	wc.lpszClassName = CLASS_NAME;
	if (!RegisterClassW(&wc)) fail("RegisterClassW");
	const DWORD exStyle = WS_EX_APPWINDOW | WS_EX_WINDOWEDGE;
	const DWORD style = WS_CLIPSIBLINGS | WS_CLIPCHILDREN | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_SIZEBOX;
	RECT rect = { 0, 0, (LONG)((float)s.windowWidth * s.dpi.windowScale), (LONG)((float)s.windowHeight * s.dpi.windowScale) };
	AdjustWindowRectEx(&rect, style, FALSE, exStyle);
	WCHAR title[TITLE_UNITS];
	toWide(s.desc.title, title);
	s.inCreateWindow = true;
	s.surrogate = 0;
	s.hwnd = CreateWindowExW(exStyle, CLASS_NAME, title, style, CW_USEDEFAULT, SW_HIDE,
		s.windowWidth == 0 ? CW_USEDEFAULT : rect.right - rect.left,
		s.windowHeight == 0 ? CW_USEDEFAULT : rect.bottom - rect.top,
		NULL, NULL, GetModuleHandleW(NULL), NULL);
	s.inCreateWindow = false;
	if (s.hwnd == NULL) fail("CreateWindowExW");
	updateDimensions();
	ShowWindow(s.hwnd, SW_SHOW);
	DragAcceptFiles(s.hwnd, TRUE);
}

void voidWin32Run(const VoidWin32Desc *desc) {
	memset(&s, 0, sizeof s);
	s.desc = *desc;
	s.windowWidth = s.framebufferWidth = desc->width;
	s.windowHeight = s.framebufferHeight = desc->height;
	s.mouse.shown = true;
	voidFrameTimingInit(&s.timing);
	initDpi();
	initCursors();
	createWindow();
	s.valid = true;
	bool done = false;
	while (!(done || s.quitOrdered)) {
		voidFrameTimingUpdate(&s.timing, 0.0);
		MSG msg;
		while (PeekMessageW(&msg, NULL, 0, 0, PM_REMOVE)) {
			if (msg.message == WM_QUIT) {
				done = true;
				continue;
			}
			TranslateMessage(&msg);
			DispatchMessageW(&msg);
		}
		frame(false);
		if (updateDimensions()) appEvent(VOID_EVENT_RESIZED);
		if (s.quitRequested) PostMessageW(s.hwnd, WM_CLOSE, 0, 0);
		updateMouseLock();
	}
	if (!s.cleanupCalled) {
		if (s.desc.cleanup) s.desc.cleanup();
		s.cleanupCalled = true;
	}
	DestroyWindow(s.hwnd);
	UnregisterClassW(CLASS_NAME, GetModuleHandleW(NULL));
	clearDropped();
	free(s.clipboard);
	memset(&s, 0, sizeof s);
}

bool voidWin32Valid(void) { return s.valid; }
HWND voidWin32Hwnd(void) { return s.hwnd; }
int voidWin32Width(void) { return s.framebufferWidth > 0 ? s.framebufferWidth : 1; }
int voidWin32Height(void) { return s.framebufferHeight > 0 ? s.framebufferHeight : 1; }
float voidWin32DpiScale(void) { return s.dpi.contentScale; }
uint64_t voidWin32FrameCount(void) { return s.frameCount; }
void voidWin32RequestQuit(void) { s.quitRequested = true; }

void voidWin32SetTitle(const char *title) {
	WCHAR wide[TITLE_UNITS];
	toWide(title, wide);
	SetWindowTextW(s.hwnd, wide);
}

void voidWin32CancelQuit(void) { s.quitRequested = false; }
double voidWin32FrameDuration(void) { return s.timing.smoothDt; }

void voidWin32SetClipboard(const char *utf8) {
	WCHAR *wide = utf8ToWide(utf8);
	const SIZE_T bytes = (wcslen(wide) + 1) * sizeof(WCHAR);
	bool ok = false;
	if (OpenClipboard(s.hwnd)) {
		HANDLE object = GlobalAlloc(GMEM_MOVEABLE, bytes);
		WCHAR *dst = object ? (WCHAR *)GlobalLock(object) : NULL;
		if (dst != NULL) {
			memcpy(dst, wide, bytes);
			GlobalUnlock(object);
			EmptyClipboard();
			ok = SetClipboardData(CF_UNICODETEXT, object) != NULL;
		}
		if (!ok && object) GlobalFree(object);
		CloseClipboard();
	}
	free(wide);
	if (!ok) fail("setting the clipboard");
}

const char *voidWin32Clipboard(void) {
	if (s.clipboard == NULL) s.clipboard = _strdup("");
	if (!OpenClipboard(s.hwnd)) return s.clipboard;
	HANDLE object = GetClipboardData(CF_UNICODETEXT);
	const WCHAR *wide = object ? (const WCHAR *)GlobalLock(object) : NULL;
	if (wide != NULL) {
		free(s.clipboard);
		s.clipboard = wideToUtf8(wide);
		GlobalUnlock(object);
	}
	CloseClipboard();
	return s.clipboard;
}

void voidWin32SetCursor(int cursor) {
	s.mouse.cursor = cursor;
	updateCursor(false);
}

int voidWin32Cursor(void) { return s.mouse.cursor; }

void voidWin32ShowMouse(bool shown) {
	s.mouse.shown = shown;
	updateCursor(false);
}

bool voidWin32MouseShown(void) { return s.mouse.shown; }
void voidWin32LockMouse(bool locked) { s.mouse.requestedLock = locked; }
bool voidWin32MouseLocked(void) { return s.mouse.locked; }
void voidWin32ToggleFullscreen(void) { setFullscreen(!s.fullscreen, SWP_SHOWWINDOW); }
bool voidWin32IsFullscreen(void) { return s.fullscreen; }
int voidWin32DroppedCount(void) { return s.droppedCount; }
const char *voidWin32DroppedPath(int i) { return s.droppedPaths[i]; }
