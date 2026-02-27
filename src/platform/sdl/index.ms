// Void SDL3 Platform — window, events, lifecycle

@include("./sdl.h")
@passC("-I/opt/homebrew/opt/sdl3/include")
@passL("-L/opt/homebrew/opt/sdl3/lib")
@passL("-lSDL3")
@passL("-Wl,-rpath,/opt/homebrew/opt/sdl3/lib")

import {
	void_platform_init, void_platform_quit,
	void_window_create, void_window_destroy,
	void_poll_events,
	void_poll_event,
	void_event_key, void_event_x, void_event_y,
	void_event_button, void_event_width, void_event_height,
	void_get_ticks_ns,
	void_window_get_pixel_width, void_window_get_pixel_height
} from "./sdl.h"

// --- Event type codes (match C bridge return values) ---

export const EventType = {
	NONE: 0 as int32,
	QUIT: 1 as int32,
	KEY_DOWN: 2 as int32,
	KEY_UP: 3 as int32,
	MOUSE_MOVE: 4 as int32,
	MOUSE_DOWN: 5 as int32,
	MOUSE_UP: 6 as int32,
	MOUSE_WHEEL: 7 as int32,
	WINDOW_RESIZE: 8 as int32,
};

// --- Key scancodes (SDL3 values) ---

export const Key = {
	A: 4 as int32,
	B: 5 as int32,
	C: 6 as int32,
	D: 7 as int32,
	E: 8 as int32,
	F: 9 as int32,
	G: 10 as int32,
	H: 11 as int32,
	I: 12 as int32,
	J: 13 as int32,
	K: 14 as int32,
	L: 15 as int32,
	M: 16 as int32,
	N: 17 as int32,
	O: 18 as int32,
	P: 19 as int32,
	Q: 20 as int32,
	R: 21 as int32,
	S: 22 as int32,
	T: 23 as int32,
	U: 24 as int32,
	V: 25 as int32,
	W: 26 as int32,
	X: 27 as int32,
	Y: 28 as int32,
	Z: 29 as int32,
	NUM_1: 30 as int32,
	NUM_2: 31 as int32,
	NUM_3: 32 as int32,
	NUM_4: 33 as int32,
	NUM_5: 34 as int32,
	NUM_6: 35 as int32,
	NUM_7: 36 as int32,
	NUM_8: 37 as int32,
	NUM_9: 38 as int32,
	NUM_0: 39 as int32,
	RETURN: 40 as int32,
	ESCAPE: 41 as int32,
	BACKSPACE: 42 as int32,
	TAB: 43 as int32,
	SPACE: 44 as int32,
	UP: 82 as int32,
	DOWN: 81 as int32,
	LEFT: 80 as int32,
	RIGHT: 79 as int32,
	LSHIFT: 225 as int32,
	LCTRL: 224 as int32,
	LALT: 226 as int32,
};

// --- Lifecycle ---

export function initPlatform(): boolean {
	return void_platform_init() === 1;
}

export function quitPlatform(): void {
	void_platform_quit();
}

export function createWindow(title: string, width: int32, height: int32): unknown {
	return void_window_create(title, width, height);
}

export function destroyWindow(window: unknown): void {
	void_window_destroy(window);
}

// --- Legacy event polling ---

export function pollEvents(): boolean {
	return void_poll_events() === 0;
}

// --- Event system ---

export function pollEvent(): int32 {
	return void_poll_event();
}

export function eventKey(): int32 {
	return void_event_key();
}

export function eventX(): float32 {
	return void_event_x();
}

export function eventY(): float32 {
	return void_event_y();
}

export function eventButton(): int32 {
	return void_event_button();
}

export function eventWidth(): int32 {
	return void_event_width();
}

export function eventHeight(): int32 {
	return void_event_height();
}

// --- Timing ---

export function getTicksNS(): uint64 {
	return void_get_ticks_ns();
}

// --- Window queries ---

export function getWindowPixelWidth(window: unknown): int32 {
	return void_window_get_pixel_width(window);
}

export function getWindowPixelHeight(window: unknown): int32 {
	return void_window_get_pixel_height(window);
}
