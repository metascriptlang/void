// The sprites scene of bench/web/README.md for the JavaScript libraries; void/spritesScene.ms is
// Void's copy, and every implementation reports its parameters so the runner can refuse a mismatch.
export const COUNT = 10000;
export const WIDTH = 1280;
export const HEIGHT = 720;
export const SIZE = 16;
export const TEXTURE_SIZE = 32;
const CHECKER = 8;

export function sprites() {
	let seed = 1;
	const random = () => {
		seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
		return seed / 4294967296;
	};
	const x = new Float32Array(COUNT), y = new Float32Array(COUNT);
	const vx = new Float32Array(COUNT), vy = new Float32Array(COUNT);
	for (let i = 0; i < COUNT; i++) {
		x[i] = random() * (WIDTH - SIZE);
		y[i] = random() * (HEIGHT - SIZE);
		vx[i] = (random() * 2 - 1) * 2;
		vy[i] = (random() * 2 - 1) * 2;
	}
	console.log(`bench.scene sprites count=${COUNT} size=${SIZE}`);
	return { x, y, vx, vy };
}

export function step(s) {
	const limitX = WIDTH - SIZE, limitY = HEIGHT - SIZE;
	for (let i = 0; i < COUNT; i++) {
		let p = s.x[i] + s.vx[i];
		if (p < 0) { p = -p; s.vx[i] = -s.vx[i]; } else if (p > limitX) { p = 2 * limitX - p; s.vx[i] = -s.vx[i]; }
		s.x[i] = p;
		p = s.y[i] + s.vy[i];
		if (p < 0) { p = -p; s.vy[i] = -s.vy[i]; } else if (p > limitY) { p = 2 * limitY - p; s.vy[i] = -s.vy[i]; }
		s.y[i] = p;
	}
}

// RGBA bytes of the 32x32 checker Void builds as packed 0xAABBGGRR words.
export function checkerPixels() {
	const pixels = new Uint8Array(TEXTURE_SIZE * TEXTURE_SIZE * 4);
	for (let y = 0; y < TEXTURE_SIZE; y++) {
		for (let x = 0; x < TEXTURE_SIZE; x++) {
			const warm = ((x / CHECKER | 0) + (y / CHECKER | 0)) % 2 === 0;
			pixels.set(warm ? [0xff, 0xc8, 0x40, 0xff] : [0x40, 0xa0, 0xff, 0xff], (y * TEXTURE_SIZE + x) * 4);
		}
	}
	return pixels;
}
