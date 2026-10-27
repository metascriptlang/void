// The MetaScript side of the window event contract (src/platform/appEvent.ms) held to the C
// header it mirrors (src/platform/appEvent.h): every ordinal, keycode, modifier bit and mouse
// button the .ms side names, and the event struct field by field, read from a C-filled event.
// A header is C-only, so a js run has nothing to compare against.

import {
	AppEventType,
	CURSOR_COUNT,
	EVENT_COUNT,
	KEY_COUNT,
	KeyCode,
	MAX_TOUCHPOINTS,
	MODIFIER_ALT,
	MODIFIER_CTRL,
	MODIFIER_LMB,
	MODIFIER_MMB,
	MODIFIER_RMB,
	MODIFIER_SHIFT,
	MODIFIER_SUPER,
	MouseButton,
	MouseCursor,
	NativeAppEvent,
} from "../platform/appEvent";

when (js) {
} else {
	import { VoidAppEvent } from "../platform/appEvent.h";
	import { appEventProbeEventSize, appEventProbeFilled, appEventProbeValue } from "./appEventProbe.h";

	let mismatches: int32 = 0;

	function same(value: int32, name: string): void {
		const header = appEventProbeValue(name);
		if (header != (value as int64)) {
			mismatches++;
			console.log(`DIFFERS ${name}: .ms ${value}, header ${header}`);
		}
	}

	test "the event ordinals and cursor ordinals agree with appEvent.h" {
		mismatches = 0;
		same(AppEventType.Invalid as int32, "VOID_EVENT_INVALID");
		same(AppEventType.KeyDown as int32, "VOID_EVENT_KEY_DOWN");
		same(AppEventType.KeyUp as int32, "VOID_EVENT_KEY_UP");
		same(AppEventType.Char as int32, "VOID_EVENT_CHAR");
		same(AppEventType.MouseDown as int32, "VOID_EVENT_MOUSE_DOWN");
		same(AppEventType.MouseUp as int32, "VOID_EVENT_MOUSE_UP");
		same(AppEventType.MouseScroll as int32, "VOID_EVENT_MOUSE_SCROLL");
		same(AppEventType.MouseMove as int32, "VOID_EVENT_MOUSE_MOVE");
		same(AppEventType.MouseEnter as int32, "VOID_EVENT_MOUSE_ENTER");
		same(AppEventType.MouseLeave as int32, "VOID_EVENT_MOUSE_LEAVE");
		same(AppEventType.TouchesBegan as int32, "VOID_EVENT_TOUCHES_BEGAN");
		same(AppEventType.TouchesMoved as int32, "VOID_EVENT_TOUCHES_MOVED");
		same(AppEventType.TouchesEnded as int32, "VOID_EVENT_TOUCHES_ENDED");
		same(AppEventType.TouchesCancelled as int32, "VOID_EVENT_TOUCHES_CANCELLED");
		same(AppEventType.Resized as int32, "VOID_EVENT_RESIZED");
		same(AppEventType.Iconified as int32, "VOID_EVENT_ICONIFIED");
		same(AppEventType.Restored as int32, "VOID_EVENT_RESTORED");
		same(AppEventType.Focused as int32, "VOID_EVENT_FOCUSED");
		same(AppEventType.Unfocused as int32, "VOID_EVENT_UNFOCUSED");
		same(AppEventType.Suspended as int32, "VOID_EVENT_SUSPENDED");
		same(AppEventType.Resumed as int32, "VOID_EVENT_RESUMED");
		same(AppEventType.QuitRequested as int32, "VOID_EVENT_QUIT_REQUESTED");
		same(AppEventType.ClipboardPasted as int32, "VOID_EVENT_CLIPBOARD_PASTED");
		same(AppEventType.FilesDropped as int32, "VOID_EVENT_FILES_DROPPED");
		same(AppEventType.Preedit as int32, "VOID_EVENT_PREEDIT");
		same(AppEventType.TextInput as int32, "VOID_EVENT_TEXT_INPUT");
		same(EVENT_COUNT, "VOID_EVENT_COUNT");
		same(MouseCursor.Default as int32, "VOID_CURSOR_DEFAULT");
		same(MouseCursor.Arrow as int32, "VOID_CURSOR_ARROW");
		same(MouseCursor.IBeam as int32, "VOID_CURSOR_IBEAM");
		same(MouseCursor.Crosshair as int32, "VOID_CURSOR_CROSSHAIR");
		same(MouseCursor.PointingHand as int32, "VOID_CURSOR_POINTING_HAND");
		same(MouseCursor.ResizeEW as int32, "VOID_CURSOR_RESIZE_EW");
		same(MouseCursor.ResizeNS as int32, "VOID_CURSOR_RESIZE_NS");
		same(MouseCursor.ResizeNWSE as int32, "VOID_CURSOR_RESIZE_NWSE");
		same(MouseCursor.ResizeNESW as int32, "VOID_CURSOR_RESIZE_NESW");
		same(MouseCursor.ResizeAll as int32, "VOID_CURSOR_RESIZE_ALL");
		same(MouseCursor.NotAllowed as int32, "VOID_CURSOR_NOT_ALLOWED");
		same(CURSOR_COUNT, "VOID_CURSOR_COUNT");
		assert mismatches == 0;
	}

	test "every keycode agrees with appEvent.h" {
		mismatches = 0;
		same(KeyCode.Invalid as int32, "VOID_KEY_INVALID");
		same(KeyCode.Space as int32, "VOID_KEY_SPACE");
		same(KeyCode.Apostrophe as int32, "VOID_KEY_APOSTROPHE");
		same(KeyCode.Comma as int32, "VOID_KEY_COMMA");
		same(KeyCode.Minus as int32, "VOID_KEY_MINUS");
		same(KeyCode.Period as int32, "VOID_KEY_PERIOD");
		same(KeyCode.Slash as int32, "VOID_KEY_SLASH");
		same(KeyCode.Digit0 as int32, "VOID_KEY_0");
		same(KeyCode.Digit1 as int32, "VOID_KEY_1");
		same(KeyCode.Digit2 as int32, "VOID_KEY_2");
		same(KeyCode.Digit3 as int32, "VOID_KEY_3");
		same(KeyCode.Digit4 as int32, "VOID_KEY_4");
		same(KeyCode.Digit5 as int32, "VOID_KEY_5");
		same(KeyCode.Digit6 as int32, "VOID_KEY_6");
		same(KeyCode.Digit7 as int32, "VOID_KEY_7");
		same(KeyCode.Digit8 as int32, "VOID_KEY_8");
		same(KeyCode.Digit9 as int32, "VOID_KEY_9");
		same(KeyCode.Semicolon as int32, "VOID_KEY_SEMICOLON");
		same(KeyCode.Equal as int32, "VOID_KEY_EQUAL");
		same(KeyCode.A as int32, "VOID_KEY_A");
		same(KeyCode.B as int32, "VOID_KEY_B");
		same(KeyCode.C as int32, "VOID_KEY_C");
		same(KeyCode.D as int32, "VOID_KEY_D");
		same(KeyCode.E as int32, "VOID_KEY_E");
		same(KeyCode.F as int32, "VOID_KEY_F");
		same(KeyCode.G as int32, "VOID_KEY_G");
		same(KeyCode.H as int32, "VOID_KEY_H");
		same(KeyCode.I as int32, "VOID_KEY_I");
		same(KeyCode.J as int32, "VOID_KEY_J");
		same(KeyCode.K as int32, "VOID_KEY_K");
		same(KeyCode.L as int32, "VOID_KEY_L");
		same(KeyCode.M as int32, "VOID_KEY_M");
		same(KeyCode.N as int32, "VOID_KEY_N");
		same(KeyCode.O as int32, "VOID_KEY_O");
		same(KeyCode.P as int32, "VOID_KEY_P");
		same(KeyCode.Q as int32, "VOID_KEY_Q");
		same(KeyCode.R as int32, "VOID_KEY_R");
		same(KeyCode.S as int32, "VOID_KEY_S");
		same(KeyCode.T as int32, "VOID_KEY_T");
		same(KeyCode.U as int32, "VOID_KEY_U");
		same(KeyCode.V as int32, "VOID_KEY_V");
		same(KeyCode.W as int32, "VOID_KEY_W");
		same(KeyCode.X as int32, "VOID_KEY_X");
		same(KeyCode.Y as int32, "VOID_KEY_Y");
		same(KeyCode.Z as int32, "VOID_KEY_Z");
		same(KeyCode.LeftBracket as int32, "VOID_KEY_LEFT_BRACKET");
		same(KeyCode.Backslash as int32, "VOID_KEY_BACKSLASH");
		same(KeyCode.RightBracket as int32, "VOID_KEY_RIGHT_BRACKET");
		same(KeyCode.GraveAccent as int32, "VOID_KEY_GRAVE_ACCENT");
		same(KeyCode.World1 as int32, "VOID_KEY_WORLD_1");
		same(KeyCode.World2 as int32, "VOID_KEY_WORLD_2");
		same(KeyCode.Escape as int32, "VOID_KEY_ESCAPE");
		same(KeyCode.Enter as int32, "VOID_KEY_ENTER");
		same(KeyCode.Tab as int32, "VOID_KEY_TAB");
		same(KeyCode.Backspace as int32, "VOID_KEY_BACKSPACE");
		same(KeyCode.Insert as int32, "VOID_KEY_INSERT");
		same(KeyCode.Delete as int32, "VOID_KEY_DELETE");
		same(KeyCode.Right as int32, "VOID_KEY_RIGHT");
		same(KeyCode.Left as int32, "VOID_KEY_LEFT");
		same(KeyCode.Down as int32, "VOID_KEY_DOWN");
		same(KeyCode.Up as int32, "VOID_KEY_UP");
		same(KeyCode.PageUp as int32, "VOID_KEY_PAGE_UP");
		same(KeyCode.PageDown as int32, "VOID_KEY_PAGE_DOWN");
		same(KeyCode.Home as int32, "VOID_KEY_HOME");
		same(KeyCode.End as int32, "VOID_KEY_END");
		same(KeyCode.CapsLock as int32, "VOID_KEY_CAPS_LOCK");
		same(KeyCode.ScrollLock as int32, "VOID_KEY_SCROLL_LOCK");
		same(KeyCode.NumLock as int32, "VOID_KEY_NUM_LOCK");
		same(KeyCode.PrintScreen as int32, "VOID_KEY_PRINT_SCREEN");
		same(KeyCode.Pause as int32, "VOID_KEY_PAUSE");
		same(KeyCode.F1 as int32, "VOID_KEY_F1");
		same(KeyCode.F2 as int32, "VOID_KEY_F2");
		same(KeyCode.F3 as int32, "VOID_KEY_F3");
		same(KeyCode.F4 as int32, "VOID_KEY_F4");
		same(KeyCode.F5 as int32, "VOID_KEY_F5");
		same(KeyCode.F6 as int32, "VOID_KEY_F6");
		same(KeyCode.F7 as int32, "VOID_KEY_F7");
		same(KeyCode.F8 as int32, "VOID_KEY_F8");
		same(KeyCode.F9 as int32, "VOID_KEY_F9");
		same(KeyCode.F10 as int32, "VOID_KEY_F10");
		same(KeyCode.F11 as int32, "VOID_KEY_F11");
		same(KeyCode.F12 as int32, "VOID_KEY_F12");
		same(KeyCode.F13 as int32, "VOID_KEY_F13");
		same(KeyCode.F14 as int32, "VOID_KEY_F14");
		same(KeyCode.F15 as int32, "VOID_KEY_F15");
		same(KeyCode.F16 as int32, "VOID_KEY_F16");
		same(KeyCode.F17 as int32, "VOID_KEY_F17");
		same(KeyCode.F18 as int32, "VOID_KEY_F18");
		same(KeyCode.F19 as int32, "VOID_KEY_F19");
		same(KeyCode.F20 as int32, "VOID_KEY_F20");
		same(KeyCode.F21 as int32, "VOID_KEY_F21");
		same(KeyCode.F22 as int32, "VOID_KEY_F22");
		same(KeyCode.F23 as int32, "VOID_KEY_F23");
		same(KeyCode.F24 as int32, "VOID_KEY_F24");
		same(KeyCode.F25 as int32, "VOID_KEY_F25");
		same(KeyCode.Keypad0 as int32, "VOID_KEY_KP_0");
		same(KeyCode.Keypad1 as int32, "VOID_KEY_KP_1");
		same(KeyCode.Keypad2 as int32, "VOID_KEY_KP_2");
		same(KeyCode.Keypad3 as int32, "VOID_KEY_KP_3");
		same(KeyCode.Keypad4 as int32, "VOID_KEY_KP_4");
		same(KeyCode.Keypad5 as int32, "VOID_KEY_KP_5");
		same(KeyCode.Keypad6 as int32, "VOID_KEY_KP_6");
		same(KeyCode.Keypad7 as int32, "VOID_KEY_KP_7");
		same(KeyCode.Keypad8 as int32, "VOID_KEY_KP_8");
		same(KeyCode.Keypad9 as int32, "VOID_KEY_KP_9");
		same(KeyCode.KeypadDecimal as int32, "VOID_KEY_KP_DECIMAL");
		same(KeyCode.KeypadDivide as int32, "VOID_KEY_KP_DIVIDE");
		same(KeyCode.KeypadMultiply as int32, "VOID_KEY_KP_MULTIPLY");
		same(KeyCode.KeypadSubtract as int32, "VOID_KEY_KP_SUBTRACT");
		same(KeyCode.KeypadAdd as int32, "VOID_KEY_KP_ADD");
		same(KeyCode.KeypadEnter as int32, "VOID_KEY_KP_ENTER");
		same(KeyCode.KeypadEqual as int32, "VOID_KEY_KP_EQUAL");
		same(KeyCode.LeftShift as int32, "VOID_KEY_LEFT_SHIFT");
		same(KeyCode.LeftControl as int32, "VOID_KEY_LEFT_CONTROL");
		same(KeyCode.LeftAlt as int32, "VOID_KEY_LEFT_ALT");
		same(KeyCode.LeftSuper as int32, "VOID_KEY_LEFT_SUPER");
		same(KeyCode.RightShift as int32, "VOID_KEY_RIGHT_SHIFT");
		same(KeyCode.RightControl as int32, "VOID_KEY_RIGHT_CONTROL");
		same(KeyCode.RightAlt as int32, "VOID_KEY_RIGHT_ALT");
		same(KeyCode.RightSuper as int32, "VOID_KEY_RIGHT_SUPER");
		same(KeyCode.Menu as int32, "VOID_KEY_MENU");
		same(KEY_COUNT, "VOID_KEY_COUNT");
		assert mismatches == 0;
	}

	test "the mouse buttons, modifier bits and touch limit agree with appEvent.h" {
		mismatches = 0;
		same(MouseButton.Left as int32, "VOID_MOUSE_LEFT");
		same(MouseButton.Right as int32, "VOID_MOUSE_RIGHT");
		same(MouseButton.Middle as int32, "VOID_MOUSE_MIDDLE");
		same(MouseButton.Invalid as int32, "VOID_MOUSE_INVALID");
		same((MODIFIER_SHIFT as int32), "VOID_MODIFIER_SHIFT");
		same((MODIFIER_CTRL as int32), "VOID_MODIFIER_CTRL");
		same((MODIFIER_ALT as int32), "VOID_MODIFIER_ALT");
		same((MODIFIER_SUPER as int32), "VOID_MODIFIER_SUPER");
		same((MODIFIER_LMB as int32), "VOID_MODIFIER_LMB");
		same((MODIFIER_RMB as int32), "VOID_MODIFIER_RMB");
		same((MODIFIER_MMB as int32), "VOID_MODIFIER_MMB");
		same(MAX_TOUCHPOINTS, "VOID_MAX_TOUCHPOINTS");
		assert mismatches == 0;
	}

	test "the event struct reads every field where C wrote it" {
		assert appEventProbeEventSize() == (sizeof NativeAppEvent as int32);
		assert sizeof NativeAppEvent == sizeof VoidAppEvent;
		const e = (appEventProbeFilled() as Ptr<NativeAppEvent>)[0];
		assert e.frameCount == 0x1122334455667788;
		assert e.type == AppEventType.TextInput;
		assert e.keyCode == (KeyCode.Menu as int32);
		assert e.charCode == 0xAABBCCDD;
		assert e.keyRepeat;
		assert e.modifiers == (MODIFIER_SHIFT | MODIFIER_MMB);
		assert e.mouseButton == (MouseButton.Middle as int32);
		assert e.mouseX == 1.5 && e.mouseY == 2.5 && e.mouseDx == 3.5 && e.mouseDy == 4.5;
		assert e.scrollX == 5.5 && e.scrollY == 6.5;
		assert e.windowWidth == 7 && e.windowHeight == 8;
		assert e.framebufferWidth == 9 && e.framebufferHeight == 10;
		assert e.touchCount == MAX_TOUCHPOINTS;
		for (let i: int32 = 0; i < MAX_TOUCHPOINTS; i++) {
			assert e.touches[i].identifier == ((100 + i) as uint64);
			assert e.touches[i].x == 0.25 * ((i + 1) as float32);
			assert e.touches[i].y == 0.5 * ((i + 1) as float32);
			assert e.touches[i].changed == (i % 2 == 1);
		}
	}
}
