import { float32At } from "../void3d/gltfDecode";
import { sortKeyOf } from "../void3d/sortKey";

// Pinned from the C version: gltfDecodeFloat32At and sortKeyOf agreed bit for bit with it on
// every non-NaN word of this sweep. The 804 NaN words are not compared: the C kept the payload
// of a signaling NaN and the port returns the quiet NaN.
test "float32At and sortKeyOf over a bit pattern sweep keep their recorded digest" {
	const specials: uint32[] = [0, 0x80000000, 0x3F800000, 0xBF800000, 0x7FC00000, 0x7F800000, 0xFF800000, 1];
	let state: uint32 = 2463534242;
	let nans = 0;
	let hash: uint32 = 2166136261;
	for (let n = 0; n < 200000; n++) {
		state = state ^ (state << 13);
		state = state ^ (state >> 17);
		state = state ^ (state << 5);
		const word = n < 8 ? specials[n] : state;
		const bytes: uint8[] = [word as uint8, (word >> 8) as uint8, (word >> 16) as uint8, (word >> 24) as uint8];
		const value = float32At(bytes, 0);
		if (value != value) {
			nans++;
			continue;
		}
		hash = (((hash ^ sortKeyOf(value)) as uint64 * 16777619) & 0xFFFFFFFF) as uint32;
	}
	assert nans == 804;
	assert hash == 1504410601;
}

test "float32At reads zero outside the bytes" {
	const bytes: uint8[] = [0, 0, 128, 63, 0];
	assert float32At(bytes, 0) == 1.0;
	assert float32At(bytes, 2) == 0.0;
	assert float32At(bytes, -1) == 0.0;
	assert float32At(bytes, 2147483647) == 0.0;
}

test "sortKeyOf orders floats as unsigned integers" {
	assert sortKeyOf(-2.0) < sortKeyOf(-1.0);
	assert sortKeyOf(-1.0) < sortKeyOf(-0.0);
	assert sortKeyOf(-0.0) < sortKeyOf(0.0);
	assert sortKeyOf(0.0) < sortKeyOf(1.5);
	assert sortKeyOf(1.5) == 0xBFC00000;
}
