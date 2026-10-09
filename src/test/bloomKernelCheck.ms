import { bloomMipWidth, bloomMipCount, bloomBlendFactor, BloomSettings } from "../void3d/bloom";

struct BloomKernelFrame {
	width: int32;
	height: int32;
	pixels: Vec<float64>;
}

function sample(
	this frame: BloomKernelFrame,
	u: float64,
	v: float64,
	dx: int32,
	dy: int32,
): float64 {
	const x: float64 = u * (frame.width as float64) - 0.5 + (dx as float64);
	const y: float64 = v * (frame.height as float64) - 0.5 + (dy as float64);
	const ix: int32 = Math.floor(x) as int32;
	const iy: int32 = Math.floor(y) as int32;
	const fx: float64 = x - (ix as float64);
	const fy: float64 = y - (iy as float64);
	const x0: int32 = Math.max(0, Math.min(ix, frame.width - 1));
	const x1: int32 = Math.max(0, Math.min(ix + 1, frame.width - 1));
	const y0: int32 = Math.max(0, Math.min(iy, frame.height - 1));
	const y1: int32 = Math.max(0, Math.min(iy + 1, frame.height - 1));
	return (frame.pixels[y0 * frame.width + x0] * (1.0 - fx) +
		frame.pixels[y0 * frame.width + x1] * fx) * (1.0 - fy) +
		(frame.pixels[y1 * frame.width + x0] * (1.0 - fx) +
		frame.pixels[y1 * frame.width + x1] * fx) * fy;
}

function karis(group: float64): float64 {
	return group / (1.0 + group / 4.0);
}

function downsample(
	this source: BloomKernelFrame,
	width: int32,
	height: int32,
	first: boolean,
): BloomKernelFrame {
	let target: BloomKernelFrame = {
		width: width, height: height, pixels: new Array(width * height),
	};
	for (let y = 0; y < height; y++) {
		for (let x = 0; x < width; x++) {
			const u: float64 = ((x as float64) + 0.5) / (width as float64);
			const v: float64 = ((y as float64) + 0.5) / (height as float64);
			const a: float64 = source.sample(u, v, -2, 2);
			const b: float64 = source.sample(u, v, 0, 2);
			const c: float64 = source.sample(u, v, 2, 2);
			const d: float64 = source.sample(u, v, -2, 0);
			const e: float64 = source.sample(u, v, 0, 0);
			const f: float64 = source.sample(u, v, 2, 0);
			const g: float64 = source.sample(u, v, -2, -2);
			const h: float64 = source.sample(u, v, 0, -2);
			const i: float64 = source.sample(u, v, 2, -2);
			const j: float64 = source.sample(u, v, -1, 1);
			const k: float64 = source.sample(u, v, 1, 1);
			const l: float64 = source.sample(u, v, -1, -1);
			const m: float64 = source.sample(u, v, 1, -1);
			const value: float64 = first ? Math.max(0.0001,
				karis((a + b + d + e) * 0.03125) + karis((b + c + e + f) * 0.03125) +
				karis((d + e + g + h) * 0.03125) + karis((e + f + h + i) * 0.03125) +
				karis((j + k + l + m) * 0.125)) :
				(a + c + g + i) * 0.03125 + (b + d + f + h) * 0.0625 +
				(e + j + k + l + m) * 0.125;
			target.pixels[y * width + x] = value;
		}
	}
	return target;
}

function upsample(source: BloomKernelFrame, ref target: BloomKernelFrame, factor: float64): void {
	for (let y = 0; y < target.height; y++) {
		for (let x = 0; x < target.width; x++) {
			const u: float64 = ((x as float64) + 0.5) / (target.width as float64);
			const v: float64 = ((y as float64) + 0.5) / (target.height as float64);
			let sum: float64 = 0.0;
			for (let dy = -1; dy <= 1; dy++) {
				for (let dx = -1; dx <= 1; dx++) {
					sum = sum + source.sample(u, v, dx, dy) *
						(dx == 0 ? 0.5 : 0.25) * (dy == 0 ? 0.5 : 0.25);
				}
			}
			const at: int32 = y * target.width + x;
			target.pixels[at] = sum * factor + target.pixels[at] * (1.0 - factor);
		}
	}
}

function chain(width: int32, height: int32): BloomKernelFrame {
	let frame: BloomKernelFrame = {
		width: width, height: height, pixels: new Array(width * height),
	};
	for (let y = height / 2 - 4; y < height / 2 + 4; y++) {
		for (let x = width / 2 - 4; x < width / 2 + 4; x++) {
			frame.pixels[y * width + x] = 4.0;
		}
	}
	const settings: BloomSettings = BloomSettings.natural();
	const count: int32 = bloomMipCount(settings.maxMipDimension);
	const mipWidth: int32 = bloomMipWidth(width, height, settings.maxMipDimension);
	let mips: Vec<BloomKernelFrame> = [];
	mips.push(frame.downsample(mipWidth, settings.maxMipDimension, true));
	for (let i = 1; i < count; i++) {
		mips.push(mips[i - 1].downsample(mipWidth >> i, settings.maxMipDimension >> i, false));
	}
	for (let i = count - 1; i > 0; i--) {
		upsample(mips[i], mips[i - 1],
			bloomBlendFactor(settings, i as float32, (count - 1) as float32) as float64);
	}
	upsample(mips[0], frame, settings.intensity as float64);
	return frame;
}

function mirrorError(this frame: BloomKernelFrame): float64 {
	let error: float64 = 0.0;
	for (let y = 0; y < frame.height; y++) {
		for (let x = 0; x < frame.width; x++) {
			const value: float64 = frame.pixels[y * frame.width + x];
			error = Math.max(error,
				Math.abs(value - frame.pixels[y * frame.width + frame.width - 1 - x]));
			error = Math.max(error,
				Math.abs(value - frame.pixels[(frame.height - 1 - y) * frame.width + x]));
		}
	}
	return error;
}

test "Bevy's pixel-centred bloom kernels keep symmetry through odd mip widths" {
	for (const width of [320, 1280]) {
		const height: int32 = width == 320 ? 240 : 720;
		const frame: BloomKernelFrame = chain(width, height);
		assert frame.mirrorError() < 0.00000001;
		const cx: int32 = width / 2;
		const cy: int32 = height / 2;
		const right: float64 = frame.pixels[cy * width + cx + 8];
		const mirrored: float64 = frame.pixels[cy * width + width - 1 - (cx + 8)];
		const oldLeft: float64 = frame.pixels[cy * width + cx - 8];
		assert Math.abs(right - mirrored) < 0.00000001;
		assert oldLeft - right > 0.001;
	}
}
