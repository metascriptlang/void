export function zeroFloats(count: int32): float32[] {
	const values: float32[] = [];
	for (let i: int32 = 0; i < count; i++) { values.push(0.0); }
	return values;
}

export function zeroWords(count: int32): uint32[] {
	const values: uint32[] = [];
	for (let i: int32 = 0; i < count; i++) { values.push(0); }
	return values;
}

export function zeroFlags(count: int32): Vec<boolean> {
	let values: Vec<boolean> = [];
	for (let i: int32 = 0; i < count; i++) { values.push(false); }
	return values;
}
