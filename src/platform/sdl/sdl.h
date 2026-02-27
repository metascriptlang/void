// Void SDL3 Platform — window, events, lifecycle
// All handles are opaque pointers.

#ifndef VOID_SDL_H
#define VOID_SDL_H

#include <stdint.h>

// --- Lifecycle ---
int void_platform_init(void);
void void_platform_quit(void);
void *void_window_create(const char *title, int width, int height);
void void_window_destroy(void *window);

// --- Legacy event polling (returns 1 on quit) ---
int void_poll_events(void);

// --- Event system ---
// Poll one event, return type code:
//   0 = none, 1 = quit, 2 = key_down, 3 = key_up,
//   4 = mouse_move, 5 = mouse_down, 6 = mouse_up,
//   7 = mouse_wheel, 8 = window_resize, -1 = unhandled
int void_poll_event(void);

// Event data getters (read after void_poll_event)
int void_event_key(void);
float void_event_x(void);
float void_event_y(void);
int void_event_button(void);
int void_event_width(void);
int void_event_height(void);

// --- Timing ---
uint64_t void_get_ticks_ns(void);

// --- Window queries ---
int void_window_get_pixel_width(void *window);
int void_window_get_pixel_height(void *window);

#endif
