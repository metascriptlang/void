// Run in a process of its own (scripts/gate.sh): runPin sets the door's device up twice, which
// would pull the device from under every test that ran after it in src/test/index.ms.

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
// drew into the large target and was not read. The stats of frames 0-5, 18 and 19 were recorded again
// after sprite and UI runs began to skip a params block equal to the bound one: each of those
// frames makes two uniform applies (512 ring bytes) fewer than batcher.c did, and draws the same pixels.
// They were re-recorded again when the UI stride grew from 108 to 124 bytes; only upload and buffer
// bytes moved, 16 per UI instance.
const STATS_PINS: uint32[] = [
	2879984779, 1134072702, 508430390, 373187124, 2032707949, 3877287625, 3196029135,
	3196029135, 166738155, 2218285850, 4014481472, 708066378, 230865875, 708066378,
	4079223261, 2590490994, 431512101, 3604346767, 1659175716, 2574877897, 3196029135,
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

when (windows && !voidDummy && !voidVulkan && !voidGlCore) {
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
