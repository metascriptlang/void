import {
	closeSurface,
	fitSurface,
	openSurface,
	presentSurface,
	removedReason,
	surfaceHeight,
	surfaceNative,
	surfaceWaitable,
	surfaceWidth,
} from "./backend.ms";
import "../dxgi/removal";

@exportName("voidD3d12SurfaceOpen")
export function exportSurfaceOpen(window: uint64, composition: int32, width: int32, height: int32, presentMode: int32): uint32 {
	return openSurface(window, composition != 0, width, height, presentMode);
}

@exportName("voidD3d12SurfaceWaitable")
export function exportSurfaceWaitable(surface: uint32): uint64 { return surfaceWaitable(surface); }

@exportName("voidD3d12SurfaceNative")
export function exportSurfaceNative(surface: uint32): uint64 { return surfaceNative(surface); }

@exportName("voidD3d12SurfaceFit")
export function exportSurfaceFit(surface: uint32, width: int32, height: int32): void { fitSurface(surface, width, height); }

@exportName("voidD3d12SurfaceWidth")
export function exportSurfaceWidth(surface: uint32): int32 { return surfaceWidth(surface); }

@exportName("voidD3d12SurfaceHeight")
export function exportSurfaceHeight(surface: uint32): int32 { return surfaceHeight(surface); }

@exportName("voidD3d12SurfacePresent")
export function exportSurfacePresent(surface: uint32, modal: int32): int32 { return presentSurface(surface, modal != 0); }

@exportName("voidD3d12SurfaceClose")
export function exportSurfaceClose(surface: uint32): void { closeSurface(surface); }

@exportName("voidD3d12RemovedReason")
export function exportRemovedReason(): int32 { return removedReason(); }
