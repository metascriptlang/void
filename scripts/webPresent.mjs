// Loads a web build in headless Chrome over DevTools and screenshots its canvas only once the page
// has presented frames: a rAF tick that drew to the canvas (WebGPU: getCurrentTexture then a
// submit; WebGL2: a draw or clear on the default framebuffer). A page that presents nothing, or
// whose screenshot is one colour, fails; a Chrome that hands WebGPU no adapter skips.
//
//   node scripts/webPresent.mjs <label> <pageUrl> <png>
import { spawn } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { inflateSync } from 'node:zlib';

const framesWanted = 3;
const presentTimeoutMs = 30000;
const minDifferingShare = 0.005;

const countPresents = `(() => {
	const state = { presented: 0, adapter: null, errors: [] };
	window.__voidPresent = state;
	let acquired = false, submitted = false, drew = false, defaultBound = true;
	const raf = window.requestAnimationFrame.bind(window);
	window.requestAnimationFrame = (cb) => raf((t) => {
		acquired = submitted = drew = false;
		cb(t);
		if ((acquired && submitted) || drew) state.presented++;
	});
	if (window.GPU) {
		const requestAdapter = GPU.prototype.requestAdapter;
		GPU.prototype.requestAdapter = async function (...args) {
			const adapter = await requestAdapter.apply(this, args);
			state.adapter = !!adapter;
			return adapter;
		};
		const requestDevice = GPUAdapter.prototype.requestDevice;
		GPUAdapter.prototype.requestDevice = async function (...args) {
			const device = await requestDevice.apply(this, args);
			device.addEventListener('uncapturederror', (e) => state.errors.push('GPU ' + e.error.message));
			device.lost.then((info) => state.errors.push('device lost ' + info.reason + ' ' + info.message));
			return device;
		};
		const getCurrentTexture = GPUCanvasContext.prototype.getCurrentTexture;
		GPUCanvasContext.prototype.getCurrentTexture = function () { acquired = true; return getCurrentTexture.call(this); };
		const submit = GPUQueue.prototype.submit;
		GPUQueue.prototype.submit = function (...args) { if (acquired) submitted = true; return submit.apply(this, args); };
	}
	const gl = WebGL2RenderingContext.prototype;
	const bindFramebuffer = gl.bindFramebuffer;
	gl.bindFramebuffer = function (target, framebuffer) {
		if (target !== this.READ_FRAMEBUFFER) defaultBound = framebuffer === null;
		return bindFramebuffer.call(this, target, framebuffer);
	};
	for (const name of ['clear', 'drawArrays', 'drawElements', 'drawArraysInstanced', 'drawElementsInstanced', 'blitFramebuffer']) {
		const draw = gl[name];
		gl[name] = function (...args) { if (defaultBound) drew = true; return draw.apply(this, args); };
	}
})();`;

// The 8-bit RGB or RGBA, non-interlaced PNG Chrome's Page.captureScreenshot writes.
export function decodePng(bytes) {
	const view = Buffer.from(bytes);
	if (view.readUInt32BE(0) !== 0x89504e47) throw new Error('not a PNG');
	let width = 0, height = 0, channels = 0;
	const data = [];
	for (let at = 8; at < view.length;) {
		const length = view.readUInt32BE(at);
		const kind = view.toString('latin1', at + 4, at + 8);
		const body = view.subarray(at + 8, at + 8 + length);
		if (kind === 'IHDR') {
			width = body.readUInt32BE(0);
			height = body.readUInt32BE(4);
			const depth = body[8], colour = body[9], interlace = body[12];
			channels = colour === 6 ? 4 : colour === 2 ? 3 : 0;
			if (depth !== 8 || channels === 0 || interlace !== 0) {
				throw new Error(`PNG depth ${depth}, colour type ${colour}, interlace ${interlace}: only 8-bit RGB/RGBA, non-interlaced`);
			}
		} else if (kind === 'IDAT') {
			data.push(body);
		}
		at += 12 + length;
	}
	const raw = inflateSync(Buffer.concat(data));
	const stride = width * channels;
	const pixels = Buffer.alloc(height * stride);
	for (let y = 0; y < height; y++) {
		const filter = raw[y * (stride + 1)];
		const line = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
		for (let x = 0; x < stride; x++) {
			const left = x >= channels ? pixels[y * stride + x - channels] : 0;
			const up = y > 0 ? pixels[(y - 1) * stride + x] : 0;
			const upLeft = x >= channels && y > 0 ? pixels[(y - 1) * stride + x - channels] : 0;
			let value = line[x];
			if (filter === 1) value += left;
			else if (filter === 2) value += up;
			else if (filter === 3) value += (left + up) >> 1;
			else if (filter === 4) {
				const p = left + up - upLeft;
				const pa = Math.abs(p - left), pb = Math.abs(p - up), pc = Math.abs(p - upLeft);
				value += pa <= pb && pa <= pc ? left : pb <= pc ? up : upLeft;
			} else if (filter !== 0) throw new Error(`PNG filter ${filter} on row ${y}`);
			pixels[y * stride + x] = value & 0xff;
		}
	}
	return { width, height, channels, pixels };
}

// The share of pixels whose RGB differs from the most common one.
export function differingShare({ width, height, channels, pixels }) {
	const counts = new Map();
	let top = 0;
	for (let i = 0; i < width * height; i++) {
		const key = (pixels[i * channels] << 16) | (pixels[i * channels + 1] << 8) | pixels[i * channels + 2];
		const n = (counts.get(key) ?? 0) + 1;
		counts.set(key, n);
		if (n > top) top = n;
	}
	return width * height === 0 ? 0 : 1 - top / (width * height);
}

export function verdict({ label, backend, presented, adapter, errors, share }) {
	if (backend === 'wgpu' && adapter === false) return `SKIP  ${label}: this Chrome hands WebGPU no adapter`;
	if (errors.length > 0) return `FAIL  ${label}: ${errors[0]}`;
	if (presented < framesWanted) return `FAIL  ${label}: presented ${presented} frames in ${presentTimeoutMs / 1000} s`;
	if (share < minDifferingShare) {
		return `FAIL  ${label}: presented ${presented} frames, but the canvas is one colour (${(share * 100).toFixed(2)}% of pixels differ)`;
	}
	return `PASS  ${label}: presented ${presented} frames, ${(share * 100).toFixed(1)}% of pixels differ from the clear colour`;
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function look(label, pageUrl, png) {
	const chrome = process.env.CHROME || 'C:/Program Files/Google/Chrome/Application/chrome.exe';
	const port = Number(process.env.VOID_CDP_PORT || 9339);
	const profile = mkdtempSync(join(tmpdir(), 'void-present-'));
	const browser = spawn(chrome, [
		'--headless=new', `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`,
		'--force-device-scale-factor=1', '--window-size=800,600', '--no-first-run', 'about:blank',
	], { stdio: 'ignore' });
	try {
		let page = null;
		for (let i = 0; i < 100 && page === null; i++) {
			try {
				page = (await (await fetch(`http://127.0.0.1:${port}/json/list`)).json()).find((t) => t.type === 'page') ?? null;
			} catch {}
			if (page === null) await sleep(100);
		}
		if (page === null) throw new Error('Chrome did not open its DevTools port');
		const ws = new WebSocket(page.webSocketDebuggerUrl);
		let next = 1;
		const pending = new Map();
		const exceptions = [];
		ws.onmessage = (event) => {
			const msg = JSON.parse(event.data);
			if (msg.id && pending.has(msg.id)) {
				pending.get(msg.id)(msg);
				pending.delete(msg.id);
			} else if (msg.method === 'Runtime.exceptionThrown') {
				const details = msg.params.exceptionDetails;
				const text = `exception ${details.exception?.description ?? details.text}`;
				if (!text.includes('ExitStatus')) exceptions.push(text);
			}
		};
		const send = (method, params = {}) => new Promise((resolve) => {
			const id = next++;
			pending.set(id, resolve);
			ws.send(JSON.stringify({ id, method, params }));
		});
		const evaluate = async (expression) => (await send('Runtime.evaluate', { expression, returnByValue: true })).result?.result?.value;
		await new Promise((resolve, reject) => { ws.onopen = resolve; ws.onerror = reject; });
		await send('Runtime.enable');
		await send('Page.enable');
		await send('Page.addScriptToEvaluateOnNewDocument', { source: countPresents });
		await send('Page.navigate', { url: pageUrl });
		let state = null;
		for (let waited = 0; waited < presentTimeoutMs; waited += 100) {
			await sleep(100);
			state = await evaluate('JSON.stringify(window.__voidPresent ?? null)').then((s) => JSON.parse(s ?? 'null'));
			if (state !== null && (state.presented >= framesWanted || state.adapter === false || state.errors.length > 0)) break;
		}
		state ??= { presented: 0, adapter: null, errors: [] };
		const rect = await evaluate(`(() => {
			document.getElementById('status')?.remove();
			const r = document.getElementById('canvas').getBoundingClientRect();
			return { x: r.x, y: r.y, width: r.width, height: r.height };
		})()`);
		const shot = await send('Page.captureScreenshot', { format: 'png', clip: { ...rect, scale: 1 } });
		const bytes = Buffer.from(shot.result.data, 'base64');
		writeFileSync(png, bytes);
		const backend = new URL(pageUrl).searchParams.has('wgpu') ? 'wgpu' : 'gl';
		await send('Browser.close');
		ws.close();
		return verdict({ label, backend, ...state, errors: [...state.errors, ...exceptions], share: differingShare(decodePng(bytes)) });
	} finally {
		browser.kill();
		await new Promise((resolve) => (browser.exitCode === null ? browser.once('exit', resolve) : resolve()));
		rmSync(profile, { recursive: true, force: true, maxRetries: 5, retryDelay: 200 });
	}
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
	const [label, pageUrl, png] = process.argv.slice(2);
	const line = await look(label, pageUrl, png).catch((error) => `FAIL  ${label}: ${error.message}`);
	console.log(line);
	if (line.startsWith('FAIL')) process.exitCode = 1;
}
