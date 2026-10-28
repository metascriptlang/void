const scratch = Buffer.alloc(4);

export function float32At(bytes: Readonly<Span<uint8>>, at: int32): float32 {
	if (at < 0 || (at as int64) + 4 > (bytes.length as int64)) { return 0.0; }
	for (let i = 0; i < 4; i++) { scratch.set(i, bytes[at + i]); }
	return scratch.readFloatLE(0) as float32;
}
