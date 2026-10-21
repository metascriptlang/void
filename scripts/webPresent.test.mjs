import { test } from 'node:test';
import assert from 'node:assert/strict';
import { deflateSync } from 'node:zlib';
import { decodePng, differingShare, verdict } from './webPresent.mjs';

function crc32(bytes) {
	let crc = ~0;
	for (const b of bytes) {
		crc ^= b;
		for (let k = 0; k < 8; k++) crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1));
	}
	return ~crc >>> 0;
}

function chunk(kind, body) {
	const head = Buffer.alloc(8);
	head.writeUInt32BE(body.length, 0);
	head.write(kind, 4, 'latin1');
	const crc = Buffer.alloc(4);
	crc.writeUInt32BE(crc32(Buffer.concat([head.subarray(4), body])), 0);
	return Buffer.concat([head, body, crc]);
}

function encodePng(width, height, channels, pixelAt, filterOf = () => 0) {
	const ihdr = Buffer.alloc(13);
	ihdr.writeUInt32BE(width, 0);
	ihdr.writeUInt32BE(height, 4);
	ihdr[8] = 8;
	ihdr[9] = channels === 4 ? 6 : 2;
	const stride = width * channels;
	const rows = [];
	let previous = Buffer.alloc(stride);
	for (let y = 0; y < height; y++) {
		const line = Buffer.alloc(stride);
		for (let x = 0; x < width; x++) pixelAt(x, y).slice(0, channels).forEach((v, c) => { line[x * channels + c] = v; });
		const filter = filterOf(y);
		const out = Buffer.alloc(stride);
		for (let i = 0; i < stride; i++) {
			const left = i >= channels ? line[i - channels] : 0;
			const up = previous[i];
			const upLeft = i >= channels ? previous[i - channels] : 0;
			const p = left + up - upLeft;
			const paeth = Math.abs(p - left) <= Math.abs(p - up) && Math.abs(p - left) <= Math.abs(p - upLeft)
				? left : Math.abs(p - up) <= Math.abs(p - upLeft) ? up : upLeft;
			const predictor = [0, left, up, (left + up) >> 1, paeth][filter];
			out[i] = (line[i] - predictor) & 0xff;
		}
		rows.push(Buffer.from([filter]), out);
		previous = line;
	}
	return Buffer.concat([
		Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
		chunk('IHDR', ihdr), chunk('IDAT', deflateSync(Buffer.concat(rows))), chunk('IEND', Buffer.alloc(0)),
	]);
}

const gradient = (x, y) => [x * 16, y * 16, (x * y) & 0xff, 255];

test('decodePng undoes every row filter', () => {
	for (const channels of [3, 4]) {
		const image = decodePng(encodePng(8, 10, channels, gradient, (y) => y % 5));
		assert.equal(image.width, 8);
		assert.equal(image.height, 10);
		for (let y = 0; y < 10; y++) {
			for (let x = 0; x < 8; x++) {
				assert.deepEqual([...image.pixels.subarray((y * 8 + x) * channels, (y * 8 + x + 1) * channels)], gradient(x, y).slice(0, channels));
			}
		}
	}
});

test('decodePng refuses a format it does not read', () => {
	const png = encodePng(2, 2, 4, gradient);
	png[24] = 16;
	assert.throws(() => decodePng(png), /depth 16/);
});

test('differingShare is zero for one colour and counts the rest', () => {
	assert.equal(differingShare(decodePng(encodePng(10, 10, 4, () => [0, 0, 0, 255]))), 0);
	const share = differingShare(decodePng(encodePng(10, 10, 4, (x, y) => (x === 0 && y < 3 ? [255, 0, 0, 255] : [0, 0, 0, 255]))));
	assert.ok(Math.abs(share - 0.03) < 1e-9);
});

test('verdict refuses an unpresented or one-colour canvas and skips only a missing WebGPU adapter', () => {
	const ok = { label: 'x', backend: 'wgpu', presented: 3, adapter: true, errors: [], share: 0.2 };
	assert.match(verdict(ok), /^PASS/);
	assert.match(verdict({ ...ok, presented: 0 }), /^FAIL .*presented 0 frames.*with a WebGPU adapter/);
	assert.match(verdict({ ...ok, presented: 0, adapter: null }), /^FAIL .*never requested an adapter/);
	assert.match(verdict({ ...ok, share: 0 }), /^FAIL .*one colour/);
	assert.match(verdict({ ...ok, errors: ['device lost'] }), /^FAIL .*device lost/);
	assert.match(verdict({ ...ok, adapter: false, presented: 0 }), /^SKIP/);
	assert.match(verdict({ ...ok, backend: 'gl', adapter: false }), /^PASS/);
});
