import { DeviceLoss } from "../types.ms";

const DXGI_ERROR_DEVICE_REMOVED: int32 = 0x887A0005 as int32;
const DXGI_ERROR_DEVICE_HUNG: int32 = 0x887A0006 as int32;
const DXGI_ERROR_DEVICE_RESET: int32 = 0x887A0007 as int32;
const DXGI_ERROR_DRIVER_INTERNAL_ERROR: int32 = 0x887A0020 as int32;

@exportName("voidD3d11RemovalAction")
export function removalAction(hr: int32): int32 {
	const action = match (hr) {
		DXGI_ERROR_DEVICE_REMOVED | DXGI_ERROR_DEVICE_HUNG | DXGI_ERROR_DEVICE_RESET => DeviceLoss.Recover,
		DXGI_ERROR_DRIVER_INTERNAL_ERROR => DeviceLoss.Fatal,
		_ => DeviceLoss.None,
	};
	return action as int32;
}
