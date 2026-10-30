let names: string[] = [];
let held: uint8[][] = [];

export function fontBytesFind(name: string): int32 {
	for (let i: int32 = 0; i < (names.length as int32); i++) {
		if (names[i] == name) { return i; }
	}
	return -1;
}

export function fontBytesSize(index: int32): int64 {
	return held[index].length as int64;
}

export function fontBytesRead(index: int32, at: int64, into: Span<uint8>): boolean {
	const bytes = held[index];
	const size = bytes.length as int64;
	const count = into.length as int64;
	if (at < 0 || at > size || count > size - at) { return false; }
	for (let i: int64 = 0; i < count; i++) { into[i] = bytes[at + i]; }
	return true;
}

export function fontBytesAdd(name: string, bytes: Readonly<Span<uint8>>): boolean {
	const known = fontBytesFind(name);
	if (known >= 0) {
		const had = held[known];
		if (had.length != bytes.length) { return false; }
		for (let i: int32 = 0; i < (bytes.length as int32); i++) {
			if (had[i] != bytes[i]) { return false; }
		}
		return true;
	}
	let copy: uint8[] = new Array<uint8>(bytes.length as int32);
	for (let i: int32 = 0; i < (bytes.length as int32); i++) { copy[i] = bytes[i]; }
	names.push(name);
	held.push(copy);
	return true;
}
