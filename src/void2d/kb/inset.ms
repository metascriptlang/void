// KBTS__IN_SET and KBTS__SET32/SET64. The C shifts by a runtime class, so a class past the set width
// is undefined there; x86 masks the count (5 bits for the 32-bit sets, 6 for the 64-bit ones) and
// the port does the same.

export function kbSet32(members: uint8[]): uint32 {
	let result: uint32 = 0;
	for (let i = 0; i < members.length; i++) {
		result |= (1 as uint32) << (members[i] as uint32);
	}
	return result;
}

export function kbSet64(members: uint8[]): uint64 {
	let result: uint64 = 0;
	for (let i = 0; i < members.length; i++) {
		result |= (1 as uint64) << (members[i] as uint64);
	}
	return result;
}

export function kbInSet32(member: int64, set: uint32): boolean {
	return (((1 as uint32) << ((member & 31) as uint32)) & set) != 0;
}

export function kbInSet64(member: int64, set: uint64): boolean {
	return (((1 as uint64) << ((member & 63) as uint64)) & set) != 0;
}
