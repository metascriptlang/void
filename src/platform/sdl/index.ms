// Void SDL3 Platform — window, events, lifecycle

@include("./sdl.h")
@passC("-I/opt/homebrew/opt/sdl3/include")
@passL("-L/opt/homebrew/opt/sdl3/lib")
@passL("-lSDL3")
@passL("-Wl,-rpath,/opt/homebrew/opt/sdl3/lib")

import {
	void_platform_init, void_platform_quit,
	void_window_create, void_window_destroy,
	void_poll_events
} from "./sdl.h"

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

export function pollEvents(): boolean {
	return void_poll_events() === 0;
}
