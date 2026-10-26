const scratch = Buffer.alloc(4);

// The bits of `f`, flipped so that unsigned order is float order: negatives reversed under
// the positives. -0 sorts just below +0.
export function sortKeyOf(f: float32): uint32 {
	scratch.writeFloatLE(f as float64, 0);
	const u = scratch.readUInt32LE(0) as uint32;
	return (u & 0x80000000) != 0 ? ~u : (u | 0x80000000);
}
