// Void sokol GPU — native, per-OS backend. @platform blocks pick the native deps
// (Metal on macOS/iOS, GLES3+EGL on Android); the extern surface is backend-agnostic.

@passC("-Ideps/sokol");
@include("bridge.h");

@platform("macos") {
	@passL("-framework Cocoa");
	@passL("-framework QuartzCore");
	@passL("-framework Metal");
	@passL("-framework MetalKit");
	@link("./sokol.o");
	@link("./bridgeEmbed.o");
}

@platform("android") {
	@compile("./bridgeAndroid.c");
	@passL("-lEGL");
	@passL("-lGLESv3");
	@passL("-landroid");
	@passL("-llog");
}

@platform("ios") {
	@compile("./bridgeIos.m");
	@passL("-framework Metal");
	@passL("-framework QuartzCore");
	@passL("-framework UIKit");
	@passL("-framework Foundation");
}

extern function voidGfxSetup(): void;
extern function voidFbWidth(): int32;
extern function voidFbHeight(): int32;
extern function voidKeyDown(keycode: int32): int32;
extern function voidMakeVertexBuffer(data: Borrow<float32>, size: int32): uint32;
extern function voidMakeIndexBuffer(data: Borrow<uint16>, size: int32): uint32;
extern function voidMakeCubeShader(): uint32;
extern function voidMakePipeline(shader: uint32): uint32;
extern function voidMakeImage(rgba: unknown, w: int32, h: int32): uint32;
extern function voidMakeView(image: uint32): uint32;
extern function voidMakeSampler(): uint32;
extern function voidBeginPass(r: float32, g: float32, b: float32, a: float32): void;
extern function voidApplyPipeline(pipeline: uint32): void;
extern function voidApplyBindings(vbuf: uint32, ibuf: uint32, view: uint32, sampler: uint32): void;
extern function voidApplyMvp(mvp: unknown): void;
extern function voidDraw(count: int32): void;
extern function voidEndPass(): void;
extern function voidCommit(): void;

export function gfxSetup(): void { voidGfxSetup(); }
export function fbWidth(): int32 { return voidFbWidth(); }
export function fbHeight(): int32 { return voidFbHeight(); }
export function keyDown(code: int32): boolean { return voidKeyDown(code) !== 0; }
export function makeVertexBuffer(data: Borrow<float32>, size: int32): uint32 { return voidMakeVertexBuffer(data, size); }
export function makeIndexBuffer(data: Borrow<uint16>, size: int32): uint32 { return voidMakeIndexBuffer(data, size); }
export function makeCubeShader(): uint32 { return voidMakeCubeShader(); }
export function makePipeline(shader: uint32): uint32 { return voidMakePipeline(shader); }
export function makeImage(rgba: unknown, w: int32, h: int32): uint32 { return voidMakeImage(rgba, w, h); }
export function makeView(image: uint32): uint32 { return voidMakeView(image); }
export function makeSampler(): uint32 { return voidMakeSampler(); }
export function beginPass(r: float32, g: float32, b: float32, a: float32): void { voidBeginPass(r, g, b, a); }
export function applyPipeline(pipeline: uint32): void { voidApplyPipeline(pipeline); }
export function applyBindings(vbuf: uint32, ibuf: uint32, view: uint32, sampler: uint32): void { voidApplyBindings(vbuf, ibuf, view, sampler); }
export function applyMvp(mvp: unknown): void { voidApplyMvp(mvp); }
export function draw(count: int32): void { voidDraw(count); }
export function endPass(): void { voidEndPass(); }
export function commit(): void { voidCommit(); }

// sokol_app keycodes (ASCII-aligned letters) for keyDown polling.
export const KEY_W: int32 = 87;
export const KEY_A: int32 = 65;
export const KEY_S: int32 = 83;
export const KEY_D: int32 = 68;
