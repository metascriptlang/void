// Void SDL3 Platform — window, events, lifecycle

#include "sdl.h"

#include <SDL3/SDL.h>

int void_platform_init(void) {
	return SDL_Init(SDL_INIT_VIDEO) ? 1 : 0;
}

void void_platform_quit(void) {
	SDL_Quit();
}

void *void_window_create(const char *title, int width, int height) {
	return (void *)SDL_CreateWindow(title, width, height, 0);
}

void void_window_destroy(void *window) {
	if (window) SDL_DestroyWindow((SDL_Window *)window);
}

int void_poll_events(void) {
	SDL_Event event;
	while (SDL_PollEvent(&event)) {
		if (event.type == SDL_EVENT_QUIT) return 1;
	}
	return 0;
}
