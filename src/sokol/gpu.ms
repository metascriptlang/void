// Void sokol GPU — native, per-OS backend. @platform blocks pick the native deps
// (Metal on macOS/iOS, GLES3+EGL on Android); the extern surface is backend-agnostic.

@passC("-I../../deps/sokol");
@include("bridge.h");

when (macos) {
	@passL("-framework Cocoa");
	@passL("-framework QuartzCore");
	@passL("-framework Metal");
	@passL("-framework MetalKit");
	@link("./sokol.o");
	@compile("./bridgeEmbed.m");
}

when (windows && !voidGlCore) {
	@compile("./sokolWin.c");
	@compile("./bridgeWin.c");
	@compile("./views.c");
	@compile("./bridge.c");
	@passL("-ld3d11");
	@passL("-ldxgi");
	@passL("-luser32");
	@passL("-lgdi32");
	@passL("-lshell32");
}

when (windows && voidGlCore) {
	@compile("./sokolWin.c");
	@compile("./bridgeWeb.c");
	@compile("./bridge.c");
	@passL("-lopengl32");
	@passL("-luser32");
	@passL("-lgdi32");
	@passL("-lshell32");
}

when (android) {
	@compile("./bridgeAndroid.c");
	@compile("./views.c");
	@compile("./bridge.c");
	@passL("-lEGL");
	@passL("-lGLESv3");
	@passL("-landroid");
	@passL("-llog");
}

when (ios) {
	@compile("./bridgeIos.m");
	@compile("./views.c");
	@compile("./bridge.c");
	@passL("-framework Metal");
	@passL("-framework QuartzCore");
	@passL("-framework UIKit");
	@passL("-framework Foundation");
}

when ((windows && !voidGlCore) || ios || android) {
	extern function voidEmbedRegister(init: () => void, frame: () => void): void;
	extern function voidViewsSetSampleCount(count: int32): void;
	extern function voidViewCreate(native: int64, w: int32, h: int32, scale: float32): int32;
	extern function voidViewResize(view: int32, w: int32, h: int32, scale: float32): void;
	extern function voidViewFrame(view: int32): int32;
	extern function voidViewDestroy(view: int32): void;
	extern function voidViewSwapChain(view: int32): int64;
	extern function voidCurrentView(): int32;

	export type ViewId = int32;
	export const ViewInvalid: ViewId = 0 as int32;

	export function embedRegister(init: () => void, frame: () => void): void { voidEmbedRegister(init, frame); }
	export function setViewSampleCount(count: int32): void { voidViewsSetSampleCount(count); }
	export function viewCreate(native: int64, w: int32, h: int32, scale: float32): ViewId { return voidViewCreate(native, w, h, scale); }
	export function viewResize(view: ViewId, w: int32, h: int32, scale: float32): void { voidViewResize(view, w, h, scale); }
	export function viewFrame(view: ViewId): boolean { return voidViewFrame(view) !== 0; }
	export function viewDestroy(view: ViewId): void { voidViewDestroy(view); }
	export function viewSwapChain(view: ViewId): int64 { return voidViewSwapChain(view); }
	export function currentView(): ViewId { return voidCurrentView(); }
}

extern function voidGfxSetup(): void;
extern function voidFbWidth(): int32;
extern function voidFbHeight(): int32;
extern function voidDpiScale(): float32;
extern function voidKeyDown(keycode: int32): int32;
extern function voidMakeImage(rgba: Ptr<void>, w: int32, h: int32): uint32;
extern function voidMakeView(image: uint32): uint32;

export function gfxSetup(): void { voidGfxSetup(); }
export function fbWidth(): int32 { return voidFbWidth(); }
export function fbHeight(): int32 { return voidFbHeight(); }
export function dpiScale(): float32 { return voidDpiScale(); }
export function keyDown(code: int32): boolean { return voidKeyDown(code) !== 0; }
export function makeImage(rgba: Ptr<void>, w: int32, h: int32): uint32 { return voidMakeImage(rgba, w, h); }
export function makeView(image: uint32): uint32 { return voidMakeView(image); }

// sokol_app keycodes (ASCII-aligned letters) for keyDown polling.
export const KEY_W: int32 = 87;
export const KEY_A: int32 = 65;
export const KEY_S: int32 = 83;
export const KEY_D: int32 = 68;
