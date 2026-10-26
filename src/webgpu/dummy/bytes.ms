const scratch = Buffer.alloc(8);

export function copyBytes(destination: Span<uint8>, destinationOffset: int64, source: Readonly<Span<uint8>>, sourceOffset: int64, bytes: int64): void {
	const to = destinationOffset as int32;
	const from = sourceOffset as int32;
	const count = bytes as int32;
	if (to > from) {
		for (let i = count - 1; i >= 0; i--) { destination[to + i] = source[from + i]; }
	} else {
		for (let i = 0; i < count; i++) { destination[to + i] = source[from + i]; }
	}
}

export function zeroBytes(destination: Span<uint8>, destinationOffset: int64, bytes: int64): void {
	const to = destinationOffset as int32;
	const count = bytes as int32;
	for (let i = 0; i < count; i++) { destination[to + i] = 0; }
}

function putScratch(destination: Span<uint8>, at: int32, width: int32): void {
	for (let i = 0; i < width; i++) { destination[at + i] = scratch.byteAt(i) as uint8; }
}

function putElement(destination: Span<uint8>, at: int32, value: float32): void {
	scratch.writeFloatLE(value as float64, 0);
	putScratch(destination, at, 4);
}

function putElement(destination: Span<uint8>, at: int32, value: float64): void {
	scratch.writeDoubleLE(value, 0);
	putScratch(destination, at, 8);
}

function putElement(destination: Span<uint8>, at: int32, value: uint8): void { destination[at] = value; }

function putElement(destination: Span<uint8>, at: int32, value: int8): void { destination[at] = value as uint8; }

function putElement(destination: Span<uint8>, at: int32, value: uint16): void {
	destination[at] = value as uint8;
	destination[at + 1] = (value >> 8) as uint8;
}

function putElement(destination: Span<uint8>, at: int32, value: int16): void { putElement(destination, at, value as uint16); }

function putElement(destination: Span<uint8>, at: int32, value: uint32): void {
	for (let i = 0; i < 4; i++) { destination[at + i] = ((value >> ((i * 8) as uint32)) & 0xFF) as uint8; }
}

function putElement(destination: Span<uint8>, at: int32, value: int32): void { putElement(destination, at, value as uint32); }

function putElement(destination: Span<uint8>, at: int32, value: uint64): void {
	for (let i = 0; i < 8; i++) { destination[at + i] = ((value >> ((i * 8) as uint64)) & 0xFF) as uint8; }
}

function putElement(destination: Span<uint8>, at: int32, value: int64): void { putElement(destination, at, value as uint64); }

export function storeElements<T>(destination: Span<uint8>, destinationOffset: int64, data: Readonly<Span<T>>): void {
	const width = sizeof T as int32;
	const to = destinationOffset as int32;
	for (let i = 0; i < data.length; i++) { putElement(destination, to + i * width, data[i]); }
}

export function storeTicks(destination: Span<uint8>, destinationOffset: int64, values: Readonly<Span<uint64>>, first: int32, count: int32): void {
	const to = destinationOffset as int32;
	for (let i = 0; i < count; i++) { putElement(destination, to + i * 8, values[first + i]); }
}
