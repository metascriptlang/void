// Void's web host views in headless Chrome over DevTools (tests/web/views.html): a view started on
// one canvas, stopped, then started on a second canvas in the same document. Each started view
// must show its clear colour (src/examples/webViews.ms); each stop must leave no animation frame
// scheduled and release the canvas's GL or WebGPU context.
import { spawn } from 'node:child_process';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { inflateSync } from 'node:zlib';

const [baseUrl, ...backends] = process.argv.slice(2);
const chrome = process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const port = Number(process.env.VOID_CDP_PORT || 9339);
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const profile = mkdtempSync(join(tmpdir(), 'void-views-cdp-'));
const browser = spawn(chrome, [
	'--headless=new', `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`,
	'--force-device-scale-factor=1', '--window-size=640,480', '--no-first-run',
	// Headless Chrome on macOS hands out neither WebGL2 nor a WebGPU adapter on the GPU; both
	// come up on SwiftShader.
	'--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--enable-unsafe-webgpu', 'about:blank',
], { stdio: 'ignore' });

async function waitForBrowser() {
	for (let i = 0; i < 100; i++) {
		try {
			if ((await fetch(`http://127.0.0.1:${port}/json/version`)).ok) return;
		} catch {}
		await sleep(100);
	}
	throw new Error('Chrome did not open its DevTools port');
}

function session(url) {
	const ws = new WebSocket(url);
	let next = 1;
	const pending = new Map();
	const logs = [];
	ws.onmessage = (event) => {
		const msg = JSON.parse(event.data);
		if (msg.id && pending.has(msg.id)) {
			pending.get(msg.id)(msg);
			pending.delete(msg.id);
		} else if (msg.method === 'Runtime.consoleAPICalled') {
			logs.push(msg.params.args.map((a) => a.value ?? a.description ?? '').join(' '));
		} else if (msg.method === 'Runtime.exceptionThrown') {
			const details = msg.params.exceptionDetails;
			logs.push(`EXCEPTION ${details.text} ${details.exception?.description ?? ''}`);
		}
	};
	const send = (method, params = {}) => new Promise((resolve) => {
		const id = next++;
		pending.set(id, resolve);
		ws.send(JSON.stringify({ id, method, params }));
	});
	const open = new Promise((resolve, reject) => { ws.onopen = resolve; ws.onerror = reject; });
	return { open, send, logs, close: () => ws.close() };
}

async function evaluate(s, expression) {
	const r = await s.send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
	if (r.result?.exceptionDetails) throw new Error(r.result.exceptionDetails.exception?.description);
	return r.result?.result?.value;
}

// Chrome's screenshots are 8-bit, non-interlaced RGB or RGBA PNGs.
function decodePng(png) {
	let offset = 8;
	let width = 0;
	let channels = 0;
	const data = [];
	while (offset < png.length) {
		const length = png.readUInt32BE(offset);
		const kind = png.toString('latin1', offset + 4, offset + 8);
		const body = png.subarray(offset + 8, offset + 8 + length);
		if (kind === 'IHDR') {
			width = body.readUInt32BE(0);
			if (body[8] !== 8 || body[12] !== 0) throw new Error('screenshot is not an 8-bit progressive PNG');
			channels = { 2: 3, 6: 4 }[body[9]];
			if (!channels) throw new Error(`screenshot PNG colour type ${body[9]}`);
		} else if (kind === 'IDAT') data.push(body);
		offset += 12 + length;
	}
	const raw = inflateSync(Buffer.concat(data));
	const stride = width * channels;
	const rows = raw.length / (stride + 1);
	const out = Buffer.alloc(rows * stride);
	for (let y = 0; y < rows; y++) {
		const filter = raw[y * (stride + 1)];
		for (let x = 0; x < stride; x++) {
			const value = raw[y * (stride + 1) + 1 + x];
			const left = x >= channels ? out[y * stride + x - channels] : 0;
			const up = y > 0 ? out[(y - 1) * stride + x] : 0;
			const upLeft = y > 0 && x >= channels ? out[(y - 1) * stride + x - channels] : 0;
			let predicted = 0;
			if (filter === 1) predicted = left;
			else if (filter === 2) predicted = up;
			else if (filter === 3) predicted = (left + up) >> 1;
			else if (filter === 4) {
				const p = left + up - upLeft;
				const pa = Math.abs(p - left);
				const pb = Math.abs(p - up);
				const pc = Math.abs(p - upLeft);
				predicted = pa <= pb && pa <= pc ? left : pb <= pc ? up : upLeft;
			} else if (filter !== 0) throw new Error(`PNG filter ${filter}`);
			out[y * stride + x] = (value + predicted) & 255;
		}
	}
	return { width, channels, pixels: out };
}

async function centre(s, left) {
	const shot = await s.send('Page.captureScreenshot', {
		format: 'png', clip: { x: left + 100, y: 100, width: 1, height: 1, scale: 1 },
	});
	const { pixels } = decodePng(Buffer.from(shot.result.data, 'base64'));
	return [pixels[0], pixels[1], pixels[2]];
}

// src/examples/webViews.ms clears an odd view id to (0.9, 0.4, 0.1) and an even one to
// (0.1, 0.4, 0.9); either way green is 102 and one of red or blue is bright.
const cleared = ([r, g, b]) => Math.abs(g - 102) <= 8 && Math.max(r, b) >= 220 && Math.min(r, b) <= 40;

const released = {
	gl: (id) => `document.getElementById('${id}').getContext('webgl2').isContextLost()`,
	wgpu: (id) => `(() => { try { document.getElementById('${id}').getContext('webgpu').getCurrentTexture();
		return false; } catch (e) { return true; } })()`,
};

async function run(backend) {
	const created = await (await fetch(`http://127.0.0.1:${port}/json/new?about:blank`, { method: 'PUT' })).json();
	const s = session(created.webSocketDebuggerUrl);
	await s.open;
	await s.send('Runtime.enable');
	const fail = (what) => { console.log(`FAIL ${backend} ${what}`); process.exitCode = 1; };
	try {
		await s.send('Page.navigate', { url: `${baseUrl}/${backend}/views.html` });
		await sleep(200);
		if (backend === 'wgpu') {
			const adapter = await evaluate(s, `navigator.gpu ? navigator.gpu.requestAdapter().then((a) => !!a) : false`);
			if (!adapter) { console.log(`SKIP ${backend}: this Chrome hands WebGPU no adapter`); return; }
		}
		let ready = false;
		for (let waited = 0; waited < 30000 && !ready; waited += 100) {
			await sleep(100);
			ready = (await evaluate(s, 'window.voidReady === true')) === true;
		}
		if (!ready) return fail('Module.voidStart was never installed');

		for (const [id, left] of [['first', 0], ['second', 220]]) {
			await evaluate(s, `window.rafAtStart = window.rafCalls; window.stop = Module.voidStart(place('${id}', ${left})); true`);
			// A WebGPU view starts once its device arrives, which SwiftShader takes seconds to hand out.
			let frames = 0;
			for (let waited = 0; waited < 30000 && frames < 10; waited += 100) {
				await sleep(100);
				frames = await evaluate(s, 'window.rafCalls - window.rafAtStart');
			}
			if (frames < 10) return fail(`${id} view ran ${frames} animation frames in 30 s`);
			const pixel = await centre(s, left);
			if (cleared(pixel)) console.log(`PASS ${backend} ${id} view shows its clear colour ${pixel}`);
			else fail(`${id} view shows ${pixel}, not its clear colour`);

			await evaluate(s, `window.stop(); window.rafAtStop = window.rafCalls; true`);
			await sleep(300);
			const after = await evaluate(s, 'window.rafCalls - window.rafAtStop');
			if (after === 0) console.log(`PASS ${backend} ${id} stop leaves no animation frame scheduled`);
			else fail(`${id} stop left ${after} animation frames requested in 300 ms`);
			if (await evaluate(s, released[backend](id))) console.log(`PASS ${backend} ${id} stop releases the context`);
			else fail(`${id} stop still holds the canvas context`);
		}
	} finally {
		for (const line of s.logs) {
			if (/^(EXCEPTION|Aborted|void)/.test(line)) fail(`page logged: ${line}`);
		}
		s.close();
		await fetch(`http://127.0.0.1:${port}/json/close/${created.id}`);
	}
}

try {
	await waitForBrowser();
	for (const backend of backends) await run(backend);
} catch (error) {
	console.log(`FAIL webViews: ${error.message}`);
	process.exitCode = 1;
} finally {
	browser.kill();
}
