export const REMOVAL_NONE: int32 = 0;
export const REMOVAL_RECOVER: int32 = 1;
export const REMOVAL_FATAL: int32 = 2;

const DXGI_ERROR_DEVICE_REMOVED: int32 = 0x887A0005 as int32;
const DXGI_ERROR_DEVICE_HUNG: int32 = 0x887A0006 as int32;
const DXGI_ERROR_DEVICE_RESET: int32 = 0x887A0007 as int32;
const DXGI_ERROR_DRIVER_INTERNAL_ERROR: int32 = 0x887A0020 as int32;

@exportName("voidD3d11RemovalAction")
export function removalAction(hr: int32): int32 {
	return match (hr) {
		DXGI_ERROR_DEVICE_REMOVED | DXGI_ERROR_DEVICE_HUNG | DXGI_ERROR_DEVICE_RESET => REMOVAL_RECOVER,
		DXGI_ERROR_DRIVER_INTERNAL_ERROR => REMOVAL_FATAL,
		_ => REMOVAL_NONE,
	};
}
