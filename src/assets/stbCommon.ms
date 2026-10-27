// Void Asset — what stb_image.h's decoders share: zeroed arrays and the size-overflow checks.

export const INT_MAX: int64 = 2147483647;

export function zeros8(count: int32): uint8[] {
	const out: uint8[] = new Array<uint8>(count);
	for (let i: int32 = 0; i < count; i++) { out[i] = 0; }
	return out;
}

export function zeros16(count: int32): uint16[] {
	const out: uint16[] = new Array<uint16>(count);
	for (let i: int32 = 0; i < count; i++) { out[i] = 0; }
	return out;
}

export function zeros32(count: int32): int32[] {
	const out: int32[] = new Array<int32>(count);
	for (let i: int32 = 0; i < count; i++) { out[i] = 0; }
	return out;
}

export function zerosU32(count: int32): uint32[] {
	const out: uint32[] = new Array<uint32>(count);
	for (let i: int32 = 0; i < count; i++) { out[i] = 0; }
	return out;
}

export function mulValid(a: int64, b: int64): boolean {
	return a >= 0 && b >= 0 && (b == 0 || a <= INT_MAX / b);
}

export function mad3Valid(a: int64, b: int64, c: int64, add: int64): boolean {
	return mulValid(a, b) && mulValid(a * b, c) && a * b * c <= INT_MAX - add;
}

export function mad2Valid(a: int64, b: int64, add: int64): boolean {
	return mulValid(a, b) && a * b <= INT_MAX - add;
}
