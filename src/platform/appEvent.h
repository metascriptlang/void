// The window event Void's platform layer delivers. Ordinals, keycodes, modifier bits and mouse
// buttons are sokol_app.h's (pin 2e75443d), and src/host/window.ms AppEventType mirrors the
// event ordinals; the keycodes are GLFW's.
#ifndef VOID_PLATFORM_APP_EVENT_H
#define VOID_PLATFORM_APP_EVENT_H

#include <stdbool.h>
#include <stdint.h>

typedef enum {
	VOID_EVENT_INVALID,
	VOID_EVENT_KEY_DOWN,
	VOID_EVENT_KEY_UP,
	VOID_EVENT_CHAR,
	VOID_EVENT_MOUSE_DOWN,
	VOID_EVENT_MOUSE_UP,
	VOID_EVENT_MOUSE_SCROLL,
	VOID_EVENT_MOUSE_MOVE,
	VOID_EVENT_MOUSE_ENTER,
	VOID_EVENT_MOUSE_LEAVE,
	VOID_EVENT_TOUCHES_BEGAN,
	VOID_EVENT_TOUCHES_MOVED,
	VOID_EVENT_TOUCHES_ENDED,
	VOID_EVENT_TOUCHES_CANCELLED,
	VOID_EVENT_RESIZED,
	VOID_EVENT_ICONIFIED,
	VOID_EVENT_RESTORED,
	VOID_EVENT_FOCUSED,
	VOID_EVENT_UNFOCUSED,
	VOID_EVENT_SUSPENDED,
	VOID_EVENT_RESUMED,
	VOID_EVENT_QUIT_REQUESTED,
	VOID_EVENT_CLIPBOARD_PASTED,
	VOID_EVENT_FILES_DROPPED,
	VOID_EVENT_PREEDIT,
	VOID_EVENT_TEXT_INPUT,
	VOID_EVENT_COUNT,
} VoidAppEventType;

_Static_assert(VOID_EVENT_PREEDIT == 24 && VOID_EVENT_TEXT_INPUT == 25 && VOID_EVENT_COUNT == 26,
	"the event ordinals moved: renumber AppEventType in src/host/window.ms");

typedef enum {
	VOID_KEY_INVALID = 0,
	VOID_KEY_SPACE = 32,
	VOID_KEY_APOSTROPHE = 39,
	VOID_KEY_COMMA = 44,
	VOID_KEY_MINUS = 45,
	VOID_KEY_PERIOD = 46,
	VOID_KEY_SLASH = 47,
	VOID_KEY_0 = 48,
	VOID_KEY_1 = 49,
	VOID_KEY_2 = 50,
	VOID_KEY_3 = 51,
	VOID_KEY_4 = 52,
	VOID_KEY_5 = 53,
	VOID_KEY_6 = 54,
	VOID_KEY_7 = 55,
	VOID_KEY_8 = 56,
	VOID_KEY_9 = 57,
	VOID_KEY_SEMICOLON = 59,
	VOID_KEY_EQUAL = 61,
	VOID_KEY_A = 65,
	VOID_KEY_B = 66,
	VOID_KEY_C = 67,
	VOID_KEY_D = 68,
	VOID_KEY_E = 69,
	VOID_KEY_F = 70,
	VOID_KEY_G = 71,
	VOID_KEY_H = 72,
	VOID_KEY_I = 73,
	VOID_KEY_J = 74,
	VOID_KEY_K = 75,
	VOID_KEY_L = 76,
	VOID_KEY_M = 77,
	VOID_KEY_N = 78,
	VOID_KEY_O = 79,
	VOID_KEY_P = 80,
	VOID_KEY_Q = 81,
	VOID_KEY_R = 82,
	VOID_KEY_S = 83,
	VOID_KEY_T = 84,
	VOID_KEY_U = 85,
	VOID_KEY_V = 86,
	VOID_KEY_W = 87,
	VOID_KEY_X = 88,
	VOID_KEY_Y = 89,
	VOID_KEY_Z = 90,
	VOID_KEY_LEFT_BRACKET = 91,
	VOID_KEY_BACKSLASH = 92,
	VOID_KEY_RIGHT_BRACKET = 93,
	VOID_KEY_GRAVE_ACCENT = 96,
	VOID_KEY_WORLD_1 = 161,
	VOID_KEY_WORLD_2 = 162,
	VOID_KEY_ESCAPE = 256,
	VOID_KEY_ENTER = 257,
	VOID_KEY_TAB = 258,
	VOID_KEY_BACKSPACE = 259,
	VOID_KEY_INSERT = 260,
	VOID_KEY_DELETE = 261,
	VOID_KEY_RIGHT = 262,
	VOID_KEY_LEFT = 263,
	VOID_KEY_DOWN = 264,
	VOID_KEY_UP = 265,
	VOID_KEY_PAGE_UP = 266,
	VOID_KEY_PAGE_DOWN = 267,
	VOID_KEY_HOME = 268,
	VOID_KEY_END = 269,
	VOID_KEY_CAPS_LOCK = 280,
	VOID_KEY_SCROLL_LOCK = 281,
	VOID_KEY_NUM_LOCK = 282,
	VOID_KEY_PRINT_SCREEN = 283,
	VOID_KEY_PAUSE = 284,
	VOID_KEY_F1 = 290,
	VOID_KEY_F2 = 291,
	VOID_KEY_F3 = 292,
	VOID_KEY_F4 = 293,
	VOID_KEY_F5 = 294,
	VOID_KEY_F6 = 295,
	VOID_KEY_F7 = 296,
	VOID_KEY_F8 = 297,
	VOID_KEY_F9 = 298,
	VOID_KEY_F10 = 299,
	VOID_KEY_F11 = 300,
	VOID_KEY_F12 = 301,
	VOID_KEY_F13 = 302,
	VOID_KEY_F14 = 303,
	VOID_KEY_F15 = 304,
	VOID_KEY_F16 = 305,
	VOID_KEY_F17 = 306,
	VOID_KEY_F18 = 307,
	VOID_KEY_F19 = 308,
	VOID_KEY_F20 = 309,
	VOID_KEY_F21 = 310,
	VOID_KEY_F22 = 311,
	VOID_KEY_F23 = 312,
	VOID_KEY_F24 = 313,
	VOID_KEY_F25 = 314,
	VOID_KEY_KP_0 = 320,
	VOID_KEY_KP_1 = 321,
	VOID_KEY_KP_2 = 322,
	VOID_KEY_KP_3 = 323,
	VOID_KEY_KP_4 = 324,
	VOID_KEY_KP_5 = 325,
	VOID_KEY_KP_6 = 326,
	VOID_KEY_KP_7 = 327,
	VOID_KEY_KP_8 = 328,
	VOID_KEY_KP_9 = 329,
	VOID_KEY_KP_DECIMAL = 330,
	VOID_KEY_KP_DIVIDE = 331,
	VOID_KEY_KP_MULTIPLY = 332,
	VOID_KEY_KP_SUBTRACT = 333,
	VOID_KEY_KP_ADD = 334,
	VOID_KEY_KP_ENTER = 335,
	VOID_KEY_KP_EQUAL = 336,
	VOID_KEY_LEFT_SHIFT = 340,
	VOID_KEY_LEFT_CONTROL = 341,
	VOID_KEY_LEFT_ALT = 342,
	VOID_KEY_LEFT_SUPER = 343,
	VOID_KEY_RIGHT_SHIFT = 344,
	VOID_KEY_RIGHT_CONTROL = 345,
	VOID_KEY_RIGHT_ALT = 346,
	VOID_KEY_RIGHT_SUPER = 347,
	VOID_KEY_MENU = 348,
	VOID_KEY_COUNT = 512,
} VoidKeyCode;

typedef enum {
	VOID_MOUSE_LEFT = 0x0,
	VOID_MOUSE_RIGHT = 0x1,
	VOID_MOUSE_MIDDLE = 0x2,
	VOID_MOUSE_INVALID = 0x100,
} VoidMouseButton;

enum {
	VOID_MODIFIER_SHIFT = 0x1,
	VOID_MODIFIER_CTRL = 0x2,
	VOID_MODIFIER_ALT = 0x4,
	VOID_MODIFIER_SUPER = 0x8,
	VOID_MODIFIER_LMB = 0x100,
	VOID_MODIFIER_RMB = 0x200,
	VOID_MODIFIER_MMB = 0x400,
};

typedef enum {
	VOID_CURSOR_DEFAULT,
	VOID_CURSOR_ARROW,
	VOID_CURSOR_IBEAM,
	VOID_CURSOR_CROSSHAIR,
	VOID_CURSOR_POINTING_HAND,
	VOID_CURSOR_RESIZE_EW,
	VOID_CURSOR_RESIZE_NS,
	VOID_CURSOR_RESIZE_NWSE,
	VOID_CURSOR_RESIZE_NESW,
	VOID_CURSOR_RESIZE_ALL,
	VOID_CURSOR_NOT_ALLOWED,
	VOID_CURSOR_COUNT,
} VoidMouseCursor;

_Static_assert(VOID_CURSOR_NOT_ALLOWED == 10 && VOID_CURSOR_COUNT == 11,
	"the cursor ordinals moved: renumber MouseCursor in src/host/window.ms");

#define VOID_MAX_TOUCHPOINTS 8

typedef struct {
	uintptr_t identifier;
	float x;
	float y;
	bool changed;
} VoidTouchPoint;

typedef struct {
	uint64_t frameCount;
	VoidAppEventType type;
	VoidKeyCode keyCode;
	uint32_t charCode;
	bool keyRepeat;
	uint32_t modifiers;
	VoidMouseButton mouseButton;
	float mouseX;
	float mouseY;
	float mouseDx;
	float mouseDy;
	float scrollX;
	float scrollY;
	int windowWidth;
	int windowHeight;
	int framebufferWidth;
	int framebufferHeight;
	int touchCount;
	VoidTouchPoint touches[VOID_MAX_TOUCHPOINTS];
} VoidAppEvent;

typedef struct {
	bool down[VOID_KEY_COUNT];
} VoidKeysHeld;

static inline void voidKeysHeldTrack(VoidKeysHeld *h, VoidAppEventType type, VoidKeyCode key) {
	if (key <= VOID_KEY_INVALID || key >= VOID_KEY_COUNT) return;
	if (type == VOID_EVENT_KEY_DOWN) h->down[key] = true;
	else if (type == VOID_EVENT_KEY_UP) h->down[key] = false;
}

static inline bool voidKeysHeldDown(const VoidKeysHeld *h, int key) {
	return key > VOID_KEY_INVALID && key < VOID_KEY_COUNT && h->down[key];
}

static inline void voidKeysHeldRelease(VoidKeysHeld *h, void (*keyUp)(VoidKeyCode key)) {
	for (int key = VOID_KEY_INVALID + 1; key < VOID_KEY_COUNT; key++) {
		if (!h->down[key]) continue;
		h->down[key] = false;
		keyUp((VoidKeyCode)key);
	}
}

#endif
