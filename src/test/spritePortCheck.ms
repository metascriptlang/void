import {
	SpriteError,
	drawSprite,
	spriteCanvasInk,
	spriteCodepoint,
	spriteCount,
	spriteIndex,
	spriteTableFault,
} from "../void2d/spriteGlyph";

const FNV_OFFSET: uint32 = 2166136261;
const FNV_PRIME: uint32 = 16777619;

const SIZES: int32[] = [
	18, 36, 4, 12, 24, 3, 11, 21, 2, 9, 17, 1,
	1, 1, 1, 2, 3, 1, 3, 2, 1, 5, 9, 2, 7, 15, 3, 8, 16, 2, 13, 27, 1,
	16, 8, 2, 24, 12, 1, 33, 65, 5, 64, 128, 8, 31, 31, 3, 20, 20, 7,
];
const RANGES: int32[] = [
	0x2500, 0x257F, 0x2580, 0x259F, 0x25E2, 0x25E5, 0x25F8, 0x25FA, 0x25FF, 0x25FF,
	0x2800, 0x28FF, 0xE0B0, 0xE0BF, 0xE0D2, 0xE0D2, 0xE0D4, 0xE0D4, 0x1CD00, 0x1CDE5,
	0x1FB00, 0x1FB3B, 0x1FB70, 0x1FB92, 0x1FB94, 0x1FB97,
];

// Digests of the C spriteGlyph.c, recorded before that file was deleted: "table" hashes the count,
// the table fault, the index of every code point from -2 to 0x2FFFF and the code point of every id;
// "WxH+T:R" hashes, for every code point of table range R at that cell, its id, the draw status and
// canvas, and the ink status, box and stride. Each FNV-1a is 32 bits over little-endian ints.
const SPRITE_PINS: string[] = [
	"table 0ed91977",
	"18x36+4:0 ff5f4981",
	"18x36+4:1 578a3a5b",
	"18x36+4:2 fa56db45",
	"18x36+4:3 6df0d462",
	"18x36+4:4 96375406",
	"18x36+4:5 7c4e5c1e",
	"18x36+4:6 c7f4194f",
	"18x36+4:7 927e1e5b",
	"18x36+4:8 c5d03f20",
	"18x36+4:9 7ec22183",
	"18x36+4:10 e068e889",
	"18x36+4:11 f433f385",
	"18x36+4:12 49074e2c",
	"12x24+3:0 303ca221",
	"12x24+3:1 61691c3e",
	"12x24+3:2 a1b29021",
	"12x24+3:3 f0fea97c",
	"12x24+3:4 721cc5c0",
	"12x24+3:5 eea5ddef",
	"12x24+3:6 a4895c85",
	"12x24+3:7 71b59db1",
	"12x24+3:8 72ab782a",
	"12x24+3:9 e9078b37",
	"12x24+3:10 b4f913b1",
	"12x24+3:11 7799821c",
	"12x24+3:12 c53c5b2f",
	"11x21+2:0 10e8972e",
	"11x21+2:1 cdee8ff8",
	"11x21+2:2 0f1924bb",
	"11x21+2:3 2be13307",
	"11x21+2:4 0a555459",
	"11x21+2:5 27c9ceef",
	"11x21+2:6 ba36d199",
	"11x21+2:7 e3935de0",
	"11x21+2:8 69078011",
	"11x21+2:9 d6360aae",
	"11x21+2:10 869c6dc0",
	"11x21+2:11 3d8c75bc",
	"11x21+2:12 0d0cfbfc",
	"9x17+1:0 fa96ab2a",
	"9x17+1:1 84c91676",
	"9x17+1:2 bcc97156",
	"9x17+1:3 c643b7e8",
	"9x17+1:4 0c073233",
	"9x17+1:5 a836e9b6",
	"9x17+1:6 d97a0b22",
	"9x17+1:7 431dc750",
	"9x17+1:8 d55ecb91",
	"9x17+1:9 1cf58798",
	"9x17+1:10 06a3a1ee",
	"9x17+1:11 9def539d",
	"9x17+1:12 b436c01a",
	"1x1+1:0 711159d4",
	"1x1+1:1 16455b9e",
	"1x1+1:2 14789cd9",
	"1x1+1:3 48391f78",
	"1x1+1:4 60e77376",
	"1x1+1:5 6c70809c",
	"1x1+1:6 2abdc01d",
	"1x1+1:7 35f928b5",
	"1x1+1:8 9dfdd4ec",
	"1x1+1:9 e31c56d7",
	"1x1+1:10 0e098db5",
	"1x1+1:11 249ce15c",
	"1x1+1:12 a51c2451",
	"2x3+1:0 12ee6df3",
	"2x3+1:1 5dacdc89",
	"2x3+1:2 7218d719",
	"2x3+1:3 e094d179",
	"2x3+1:4 ed4728c1",
	"2x3+1:5 ae27ddda",
	"2x3+1:6 64a7c145",
	"2x3+1:7 6220b70c",
	"2x3+1:8 b0eb2457",
	"2x3+1:9 70968663",
	"2x3+1:10 6d03e4a5",
	"2x3+1:11 0bbccd4d",
	"2x3+1:12 938e4309",
	"3x2+1:0 daca9dcc",
	"3x2+1:1 1fe392ef",
	"3x2+1:2 dba4f319",
	"3x2+1:3 bce5ac82",
	"3x2+1:4 f60221be",
	"3x2+1:5 ae27ddda",
	"3x2+1:6 dc3fe8ad",
	"3x2+1:7 2036325a",
	"3x2+1:8 fa33a209",
	"3x2+1:9 c69bfa5b",
	"3x2+1:10 15bc73f1",
	"3x2+1:11 878f646d",
	"3x2+1:12 e7e2c0f9",
	"5x9+2:0 16e96674",
	"5x9+2:1 1868d000",
	"5x9+2:2 280ce00f",
	"5x9+2:3 0ed3bcac",
	"5x9+2:4 b1a67bf2",
	"5x9+2:5 260a4b11",
	"5x9+2:6 d14cc0d5",
	"5x9+2:7 adfd6f54",
	"5x9+2:8 5ebcbef5",
	"5x9+2:9 08f8bc96",
	"5x9+2:10 a4731bf8",
	"5x9+2:11 730182ab",
	"5x9+2:12 0afd84ee",
	"7x15+3:0 f083d242",
	"7x15+3:1 b89f275a",
	"7x15+3:2 af8facea",
	"7x15+3:3 7442eee5",
	"7x15+3:4 7b50759e",
	"7x15+3:5 cb31448d",
	"7x15+3:6 a3e1cef2",
	"7x15+3:7 9fbdbf78",
	"7x15+3:8 956792a9",
	"7x15+3:9 84c8c89e",
	"7x15+3:10 d056ebb8",
	"7x15+3:11 bbe5e042",
	"7x15+3:12 16a1f071",
	"8x16+2:0 9dffe6bf",
	"8x16+2:1 d495cdc4",
	"8x16+2:2 9d725841",
	"8x16+2:3 7c466ab0",
	"8x16+2:4 05a16550",
	"8x16+2:5 13665d16",
	"8x16+2:6 79cd2577",
	"8x16+2:7 3823c097",
	"8x16+2:8 4a3efecc",
	"8x16+2:9 2575690f",
	"8x16+2:10 6dbb164b",
	"8x16+2:11 3a2dd2e0",
	"8x16+2:12 c82c0edd",
	"13x27+1:0 ef032fab",
	"13x27+1:1 79d68fb4",
	"13x27+1:2 fb5664a3",
	"13x27+1:3 c006fd9d",
	"13x27+1:4 eec85be9",
	"13x27+1:5 97cb104f",
	"13x27+1:6 f0289db5",
	"13x27+1:7 e77636f0",
	"13x27+1:8 e2abc579",
	"13x27+1:9 d03e2174",
	"13x27+1:10 3396669a",
	"13x27+1:11 9831f03d",
	"13x27+1:12 96503621",
	"16x8+2:0 4db5c8e7",
	"16x8+2:1 76a90d16",
	"16x8+2:2 3759e1c1",
	"16x8+2:3 d51dcad0",
	"16x8+2:4 db1b7044",
	"16x8+2:5 f2fcf34c",
	"16x8+2:6 abf2bc93",
	"16x8+2:7 3190ab5b",
	"16x8+2:8 25474a68",
	"16x8+2:9 f237457f",
	"16x8+2:10 719e80ab",
	"16x8+2:11 ce9b3056",
	"16x8+2:12 b82b26db",
	"24x12+1:0 6d8f0c33",
	"24x12+1:1 4174de1c",
	"24x12+1:2 d2b4a589",
	"24x12+1:3 e701d87d",
	"24x12+1:4 1f1261e9",
	"24x12+1:5 939b2b5b",
	"24x12+1:6 3b595567",
	"24x12+1:7 553cd923",
	"24x12+1:8 3b0b0698",
	"24x12+1:9 df568f75",
	"24x12+1:10 5205dc11",
	"24x12+1:11 d0a89900",
	"24x12+1:12 5530f0ba",
	"33x65+5:0 e46d0adc",
	"33x65+5:1 d3803326",
	"33x65+5:2 d634f17f",
	"33x65+5:3 ced76416",
	"33x65+5:4 9a7f36d6",
	"33x65+5:5 e1c51c94",
	"33x65+5:6 505c48dd",
	"33x65+5:7 8c71ea75",
	"33x65+5:8 1ac72ad8",
	"33x65+5:9 fa586d40",
	"33x65+5:10 b205a61e",
	"33x65+5:11 3ac24fd1",
	"33x65+5:12 cdfdc15a",
	"64x128+8:0 e7ec8ba9",
	"64x128+8:1 7bf2922d",
	"64x128+8:2 877c7201",
	"64x128+8:3 b3e8f6d2",
	"64x128+8:4 e77234c2",
	"64x128+8:5 89ce98a2",
	"64x128+8:6 2a878e97",
	"64x128+8:7 580daa87",
	"64x128+8:8 371616b4",
	"64x128+8:9 b91094c7",
	"64x128+8:10 199231fb",
	"64x128+8:11 d43a63fb",
	"64x128+8:12 8f80dcf9",
	"31x31+3:0 bd3667be",
	"31x31+3:1 f9ddb490",
	"31x31+3:2 b9683089",
	"31x31+3:3 1ca738f0",
	"31x31+3:4 2e0ee1ec",
	"31x31+3:5 a8d2e082",
	"31x31+3:6 928ffae5",
	"31x31+3:7 52aaff10",
	"31x31+3:8 2450ac01",
	"31x31+3:9 440a5f16",
	"31x31+3:10 d987fa78",
	"31x31+3:11 2a4ddb14",
	"31x31+3:12 12772b9f",
	"20x20+7:0 faac5c75",
	"20x20+7:1 08a1da9b",
	"20x20+7:2 a22c2c11",
	"20x20+7:3 96956f8f",
	"20x20+7:4 6784a74b",
	"20x20+7:5 2d477131",
	"20x20+7:6 18526b07",
	"20x20+7:7 e00729b9",
	"20x20+7:8 a93d27c2",
	"20x20+7:9 65e89481",
	"20x20+7:10 286b6ddf",
	"20x20+7:11 64877d57",
	"20x20+7:12 4848267c",
];

class Digest {
	h: uint32 = FNV_OFFSET;
}

function mix(d: Digest, byte: int32): void {
	d.h = (d.h ^ ((byte & 255) as uint32)) * FNV_PRIME;
}

function mixInt(d: Digest, value: int32): void {
	for (let i: int32 = 0; i < 4; i++) { mix(d, (value >> (8 * i)) & 255); }
}

function hex32(value: uint32): string {
	const digits: string = "0123456789abcdef";
	let out: string = "";
	for (let shift: int32 = 28; shift >= 0; shift = shift - 4) {
		out = out + digits[((value >> (shift as uint32)) & 15) as int32];
	}
	return out;
}

function statusOf(error: SpriteError): int32 {
	return match (error) {
		SpriteError.NoSuchSprite => 1,
		SpriteError.BadCell => 2,
		SpriteError.Geometry => 3,
	};
}

function digestRange(first: int32, last: int32, w: int32, h: int32, t: int32): uint32 {
	const d = new Digest();
	for (let codepoint: int32 = first; codepoint <= last; codepoint++) {
		const id: int32 = spriteIndex(codepoint);
		mixInt(d, id);
		const drawn = drawSprite(codepoint, w, h, t);
		if (!drawn.ok) {
			mixInt(d, statusOf(drawn.error));
		} else {
			mixInt(d, 0);
			for (let i: int32 = 0; i < (drawn.value.pixels.length as int32); i++) {
				mix(d, drawn.value.pixels[i] as int32);
			}
		}
		const ink = spriteCanvasInk(id, w, h, t);
		if (!ink.ok) {
			mixInt(d, statusOf(ink.error));
			for (let k: int32 = 0; k < 5; k++) { mixInt(d, 0); }
		} else {
			mixInt(d, 0);
			mixInt(d, ink.value.left);
			mixInt(d, ink.value.top);
			mixInt(d, ink.value.right);
			mixInt(d, ink.value.bottom);
			mixInt(d, ink.value.stride);
		}
	}
	return d.h;
}

function digestTable(): uint32 {
	const d = new Digest();
	mixInt(d, spriteCount());
	mixInt(d, spriteTableFault());
	for (let cp: int32 = -2; cp < 0x30000; cp++) { mixInt(d, spriteIndex(cp)); }
	for (let id: int32 = -2; id < spriteCount() + 3; id++) { mixInt(d, spriteCodepoint(id)); }
	return d.h;
}

test "the sprite port reproduces the digests recorded from the C" {
	assert SPRITE_PINS.length == 1 + (SIZES.length as int32) / 3 * (RANGES.length as int32) / 2;
	let bad: int32 = 0;
	let at: int32 = 0;
	const table: string = `table ${hex32(digestTable())}`;
	if (table != SPRITE_PINS[at]) {
		bad++;
		console.log(`DIFFERS ${table} vs ${SPRITE_PINS[at]}`);
	}
	at++;
	for (let s: int32 = 0; s < (SIZES.length as int32) / 3; s++) {
		for (let r: int32 = 0; r < (RANGES.length as int32) / 2; r++) {
			const w: int32 = SIZES[3 * s];
			const h: int32 = SIZES[3 * s + 1];
			const t: int32 = SIZES[3 * s + 2];
			const digest: uint32 = digestRange(RANGES[2 * r], RANGES[2 * r + 1], w, h, t);
			const got: string = `${w}x${h}+${t}:${r} ${hex32(digest)}`;
			if (got != SPRITE_PINS[at]) {
				bad++;
				console.log(`DIFFERS ${got} vs ${SPRITE_PINS[at]}`);
			}
			at++;
		}
	}
	assert bad == 0;
}
