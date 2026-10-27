@include("bridge.h");

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
export function makeImage(rgba: Ptr<void>, w: int32, h: int32): uint32 {
	return voidMakeImage(rgba, w, h);
}
export function makeView(image: uint32): uint32 { return voidMakeView(image); }
