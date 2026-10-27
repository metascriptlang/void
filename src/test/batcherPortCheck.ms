import { runPin, PinRun } from "./batcherPortScript";

// Digests recorded from batcher.c on a D3D11 WARP device before that file was deleted, over the
// scenes of batcherPortScript.ms: a mixed scene (rects, rounded borders, graphics, sprites, mask
// and rounded-mask scissors, blur, colour add, every blend mode), a rect added to a clean scene,
// text gamma and three DPI values, the immediate path with a render-target bracket, buffer growth
// past the 1 MiB start for UI instances, sprites and vertices with their retirement and a scene
// close, then a device re-setup with the same scenes drawn again. A frame's stats digest is an
// FNV-1a over the door's eleven frame stats and the ten counters void2d keeps (draws, uploads,
// bytes, buffers, atlas images, glyph pages), each as its low then high 32-bit word; a pixel
// digest is an FNV-1a over the RGBA bytes read back from the 128x96 target, 0 where the frame
// drew into the large target and was not read.
const STATS_PINS: uint32[] = [
	4024651159, 650172362, 4182532266, 1341702672, 2115513041, 115799565, 3196029135,
	3196029135, 73455003, 2218285850, 4141310964, 708066378, 1263971339, 708066378,
	1350250673, 3961606470, 603858565, 3604346767, 324314176, 3957270277, 3196029135,
];
const PIXEL_PINS: uint32[] = [
	914777899, 914777899, 798363115, 1578569633, 1963176038, 798363115, 1077462645, 414271032,
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 798363115, 798363115, 1077462645,
];

let cached: PinRun | null = null;

function pinRun(): PinRun {
	if (cached == null) { cached = runPin(); }
	return cached as PinRun;
}

test "the batcher port reproduces the door stats and counters recorded from the C" {
	const run = pinRun();
	assert (run.stats.length as int32) == (STATS_PINS.length as int32);
	let bad: int32 = 0;
	for (let i: int32 = 0; i < (STATS_PINS.length as int32); i++) {
		if (run.stats[i] != STATS_PINS[i]) {
			bad++;
			console.log(`DIFFERS stats frame ${i} ${run.stats[i]} vs ${STATS_PINS[i]}`);
		}
	}
	assert bad == 0;
}

when (voidDummy) {
} else {
	test "the batcher port reproduces the pixels recorded from the C" {
		const run = pinRun();
		assert (run.pixels.length as int32) == (PIXEL_PINS.length as int32);
		let bad: int32 = 0;
		for (let i: int32 = 0; i < (PIXEL_PINS.length as int32); i++) {
			if (run.pixels[i] != PIXEL_PINS[i]) {
				bad++;
				console.log(`DIFFERS pixels frame ${i} ${run.pixels[i]} vs ${PIXEL_PINS[i]}`);
			}
		}
		assert bad == 0;
	}
}
