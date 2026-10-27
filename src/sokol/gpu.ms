// Void sokol GPU — native, per-OS backend. @platform blocks pick the native deps
// (Metal on macOS/iOS, GLES3+EGL on Android); the extern surface is backend-agnostic.

@include("bridge.h");
import "../gpu/doorGpu";

when (macos && !voidDummy) {
	@passL("-framework Cocoa");
	@passL("-framework QuartzCore");
	@passL("-framework Metal");
	@passL("-framework MetalKit");
	@compile("../platform/macos/window.m", "-fobjc-arc");
	@compile("./bridgeEmbed.m");
	@compile("./metalSurface.m", "-fobjc-arc");
	@compile("./presentGate.m", "-fobjc-arc");
	@compile("./appWindowPlatform.c");
	import "./appWindowExports";
	import "./viewsExports";
	@compile("./bridge.c");
}

when (windows && voidVulkan && !voidDummy) {
	@compile("./bridgeWin.c", "-DVOID_VULKAN");
	@compile("./windowVulkan.c", "-DVOID_VULKAN");
	import "../webgpu/vulkan/window";
} else when (windows && !voidDummy) {
	@compile("./bridgeWin.c");
}

when (windows && !voidDummy) {
	@compile("../platform/win32/window.c");
	@compile("./appWindowPlatform.c");
	import "./appWindowExports";
	import "./viewsExports";
	@compile("./bridge.c");
	@passL("-ld3d11");
	@passL("-ldxgi");
	@passL("-ldwmapi");
	@passL("-limm32");
	@passL("-lcomctl32");
	@passL("-luser32");
	@passL("-lgdi32");
	@passL("-lshell32");
}

when (windows && voidGlCore && !voidDummy) {
	@compile("./windowGl.c");
	@passL("-lopengl32");
}

when (android && !voidDummy) {
	@compile("./bridgeAndroid.c");
	@compile("./bridgeAndroidApp.c");
	@compile("./appWindowPlatform.c");
	import "./appWindowExports";
	import "./viewsExports";
	@compile("./bridge.c");
	@passL("-lEGL");
	@passL("-lGLESv3");
	@passL("-landroid");
	@passL("-llog");
}

when (ios && !voidDummy) {
	@compile("./bridgeIos.m");
	@compile("./metalSurface.m", "-fobjc-arc");
	@compile("./presentGate.m", "-fobjc-arc");
	@compile("./bridgeIosApp.m", "-fobjc-arc");
	@compile("./appWindowPlatform.c");
	import "./appWindowExports";
	import "./viewsExports";
	@compile("./bridge.c");
	@passL("-framework Metal");
	@passL("-framework QuartzCore");
	@passL("-framework CoreGraphics");
	@passL("-framework UIKit");
	@passL("-framework Foundation");
}

when (linux && !voidDummy) {
	@compile("../platform/linux/window.c");
	@compile("./bridgeLinux.c");
	@compile("./appWindowPlatform.c");
	import "./appWindowExports";
	@compile("./bridge.c");
	@passL("-lX11");
	@passL("-ldl");
	@passL("-lm");
}

when (linux && voidGles3 && !voidDummy) {
	@passC("-DVOID_GLES3");
	@passL("-lEGL");
	@passL("-lGLESv2");
} else when (linux && voidEgl && !voidDummy) {
	@passC("-DVOID_FORCE_EGL");
	@passL("-lEGL");
	@passL("-lGL");
} else when (linux && !voidDummy) {
	@passL("-lGL");
}

when (voidDummy) {
	@compile("./bridgeDummy.c");
	@compile("./appWindowPlatform.c", "-DVOID_DUMMY");
	import "./appWindowExports";
	@compile("./bridge.c", "-DVOID_DUMMY");
}

when ((macos || (windows && !voidGlCore) || ios || android) && !voidDummy) {
	import {
		exportCurrentView,
		exportRegister,
		exportSetSampleCount,
		exportViewCreate,
		exportViewDestroy,
		exportViewFrame,
		exportViewReady,
		exportViewResize,
		exportViewSwapChain,
	} from "./viewsExports";

	export type ViewId = int32;
	export const ViewInvalid: ViewId = 0 as int32;

	export function embedRegister(init: () => void, frame: () => void): void {
		exportRegister(init, frame);
	}
	export function setViewSampleCount(count: int32): void { exportSetSampleCount(count); }
	export function viewCreate(native: int64, w: int32, h: int32, scale: float32): ViewId {
		return exportViewCreate(native, w, h, scale);
	}
	export function viewResize(view: ViewId, w: int32, h: int32, scale: float32): void {
		exportViewResize(view, w, h, scale);
	}
	export function viewReady(view: ViewId): boolean { return exportViewReady(view) !== 0; }
	export function viewFrame(view: ViewId): boolean { return exportViewFrame(view) !== 0; }
	export function viewDestroy(view: ViewId): void { exportViewDestroy(view); }
	export function viewSwapChain(view: ViewId): int64 { return exportViewSwapChain(view); }
	export function currentView(): ViewId { return exportCurrentView(); }
}

export * from "./gpuCommon";
