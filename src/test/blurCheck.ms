// BlurPass's CPU side; tests/oracle/blur3d.cases holds the kernel itself to real Heaps.

import {
	BlurSettings,
	BlurKernel,
	BLUR_MAX_TAPS,
	BLUR_PIXEL,
	BLUR_TAPS,
	BLUR_UNIFORM_LENGTH,
	blurKernel,
	writeBlurBlock,
} from "../void3d/blur";

function accepts(settings: BlurSettings): boolean {
	return settings.valid();
}

test "a blur is refused once its kernel outgrows the program's taps" {
	const settings: BlurSettings = BlurSettings.defaults();
	assert settings.radius == 1.0 && settings.gain == 1.0 && settings.valid();
	assert accepts({ ...settings, radius: 0.0 }) && accepts({ ...settings, radius: 31.0 });
	assert !accepts({ ...settings, radius: 1000.0 });
	assert (blurKernel({ ...settings, radius: 1000.0 }).values.length as int32) > BLUR_MAX_TAPS;
	assert !accepts({ ...settings, radius: -1.0 }) && !accepts({ ...settings, gain: 0.0 });
}

test "the block carries the step, the weight count and each tap's weight and offset" {
	const kernel: BlurKernel = blurKernel({ ...BlurSettings.defaults(), radius: 4.0 });
	let out: Vec<float32> = new Array(BLUR_UNIFORM_LENGTH);
	writeBlurBlock(kernel, 0.25, 0.0, out);
	assert out[BLUR_PIXEL] == 0.25 && out[BLUR_PIXEL + 1] == 0.0 && out[BLUR_PIXEL + 2] == 3.0;
	for (let i = 0; i < 3; i++) {
		assert out[BLUR_TAPS + i * 4] == kernel.values[i];
		assert out[BLUR_TAPS + i * 4 + 1] == kernel.offsets[i];
	}
	assert out[BLUR_TAPS + 12] == 0.0 && out[BLUR_TAPS + 13] == 0.0;
	assert BLUR_UNIFORM_LENGTH == BLUR_TAPS + BLUR_MAX_TAPS * 4;
}
