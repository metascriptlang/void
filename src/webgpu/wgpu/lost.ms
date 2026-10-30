import { DeviceLoss } from "../types.ms";

const REASON_UNKNOWN: int32 = 1;
const REASON_DESTROYED: int32 = 2;
const REASON_CALLBACK_CANCELLED: int32 = 3;

@exportName("voidWebDeviceLostAction")
export function lostAction(reason: int32): int32 {
	const action = match (reason) {
		REASON_UNKNOWN | REASON_DESTROYED => DeviceLoss.Recover,
		REASON_CALLBACK_CANCELLED => DeviceLoss.None,
		_ => DeviceLoss.Fatal,
	};
	return action as int32;
}
