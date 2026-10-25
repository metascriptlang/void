export const LOST_IGNORE: int32 = 0;
export const LOST_RECOVER: int32 = 1;
export const LOST_FATAL: int32 = 2;

const REASON_UNKNOWN: int32 = 1;
const REASON_DESTROYED: int32 = 2;
const REASON_CALLBACK_CANCELLED: int32 = 3;

@exportName("voidWebDeviceLostAction")
export function lostAction(reason: int32): int32 {
	return match (reason) {
		REASON_UNKNOWN | REASON_DESTROYED => LOST_RECOVER,
		REASON_CALLBACK_CANCELLED => LOST_IGNORE,
		_ => LOST_FATAL,
	};
}
