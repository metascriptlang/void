// Void SDL3 Platform — window, events, lifecycle

#include "sdl.h"

#include <SDL3/SDL.h>

// --- Lifecycle ---

int void_platform_init(void) {
	return SDL_Init(SDL_INIT_VIDEO) ? 1 : 0;
}

void void_platform_quit(void) {
	SDL_Quit();
}

void *void_window_create(const char *title, int width, int height) {
	return (void *)SDL_CreateWindow(title, width, height, SDL_WINDOW_RESIZABLE);
}

void void_window_destroy(void *window) {
	if (window) SDL_DestroyWindow((SDL_Window *)window);
}

// --- Legacy event polling ---

int void_poll_events(void) {
	SDL_Event event;
	while (SDL_PollEvent(&event)) {
		if (event.type == SDL_EVENT_QUIT) return 1;
	}
	return 0;
}

// --- Event system ---

static int s_key = 0;
static float s_mx = 0, s_my = 0;
static int s_button = 0;
static int s_win_w = 0, s_win_h = 0;

int void_poll_event(void) {
	SDL_Event event;
	if (!SDL_PollEvent(&event)) return 0;
	switch (event.type) {
		case SDL_EVENT_QUIT:
			return 1;
		case SDL_EVENT_KEY_DOWN:
			s_key = (int)event.key.scancode;
			return 2;
		case SDL_EVENT_KEY_UP:
			s_key = (int)event.key.scancode;
			return 3;
		case SDL_EVENT_MOUSE_MOTION:
			s_mx = event.motion.x;
			s_my = event.motion.y;
			return 4;
		case SDL_EVENT_MOUSE_BUTTON_DOWN:
			s_button = (int)event.button.button;
			s_mx = event.button.x;
			s_my = event.button.y;
			return 5;
		case SDL_EVENT_MOUSE_BUTTON_UP:
			s_button = (int)event.button.button;
			s_mx = event.button.x;
			s_my = event.button.y;
			return 6;
		case SDL_EVENT_MOUSE_WHEEL:
			s_mx = event.wheel.x;
			s_my = event.wheel.y;
			return 7;
		case SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED:
			s_win_w = event.window.data1;
			s_win_h = event.window.data2;
			return 8;
		default:
			return -1;
	}
}

int void_event_key(void) { return s_key; }
float void_event_x(void) { return s_mx; }
float void_event_y(void) { return s_my; }
int void_event_button(void) { return s_button; }
int void_event_width(void) { return s_win_w; }
int void_event_height(void) { return s_win_h; }

// --- Timing ---

uint64_t void_get_ticks_ns(void) {
	return SDL_GetTicksNS();
}

// --- Window queries ---

int void_window_get_pixel_width(void *window) {
	int w = 0, h = 0;
	SDL_GetWindowSizeInPixels((SDL_Window *)window, &w, &h);
	return w;
}

int void_window_get_pixel_height(void *window) {
	int w = 0, h = 0;
	SDL_GetWindowSizeInPixels((SDL_Window *)window, &w, &h);
	return h;
}
