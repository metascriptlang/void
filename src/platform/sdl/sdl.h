// Void SDL3 Platform — window, events, lifecycle
// All handles are opaque pointers.

#ifndef VOID_SDL_H
#define VOID_SDL_H

int void_platform_init(void);
void void_platform_quit(void);
void *void_window_create(const char *title, int width, int height);
void void_window_destroy(void *window);
int void_poll_events(void);

#endif
