@include("bridge.h");

extern function voidGfxSetup(): void;
extern function voidFbWidth(): int32;
extern function voidFbHeight(): int32;
extern function voidDpiScale(): float32;
extern function voidKeyDown(keycode: int32): int32;
extern function voidMakeImage(rgba: Borrow<uint32>, w: int32, h: int32): uint32;
extern function voidMakeView(image: uint32): uint32;

export function gfxSetup(): void { voidGfxSetup(); }
export function fbWidth(): int32 { return voidFbWidth(); }
export function fbHeight(): int32 { return voidFbHeight(); }
export function dpiScale(): float32 { return voidDpiScale(); }
export function keyDown(code: int32): boolean { return voidKeyDown(code) !== 0; }
export function makeImage(rgba: Readonly<Span<uint32>>, w: int32, h: int32): uint32 {
	if (rgba.length == 0) {
		const white: uint32[] = [0xFFFFFFFF];
		return voidMakeImage(white[0], 1, 1);
	}
	return voidMakeImage(rgba[0], w, h);
}
export function makeView(image: uint32): uint32 { return voidMakeView(image); }
