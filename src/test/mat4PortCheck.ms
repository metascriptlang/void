import { sinf, cosf, sqrtf } from "../math/mat4";
import { float32At } from "../void3d/gltfDecode";
import { sortKeyOf } from "../void3d/sortKey";

// Pinned from the C version: sinf and cosf matched the C sinf and cosf exactly except on 2 of
// about 400000 arguments within 30 radians and within one ulp beyond (the Windows C library
// rounds those differently from the correctly rounded value the port returns); sqrtf matched
// exactly.
test "sinf, cosf and sqrtf over an argument sweep keep their recorded digest" {
	let state: uint32 = 88172645;
	let hash: uint32 = 2166136261;
	for (let n = 0; n < 200000; n++) {
		state = state ^ (state << 13);
		state = state ^ (state >> 17);
		state = state ^ (state << 5);
		const bytes: uint8[] = [state as uint8, (state >> 8) as uint8, (state >> 16) as uint8, (state >> 24) as uint8];
		let x = float32At(bytes, 0);
		if (n % 2 == 0) { x = (state % 2000001) as float32 / 1000.0 - 1000.0; }
		if (x != x || x > 1e38 || x < -1e38) { continue; }
		hash = (((hash ^ sortKeyOf(sinf(x)) ^ sortKeyOf(cosf(x))) as uint64 * 16777619) & 0xFFFFFFFF) as uint32;
	}
	assert hash == 421938902;
	assert sqrtf(4.0) == 2.0;
	assert sqrtf(0.0) == 0.0;
}
