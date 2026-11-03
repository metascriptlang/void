// Builds every implementation of a bench scene, runs each in headless Chrome, and writes what it
// measured to bench/web/baseline/. bench/web/README.md says what is measured and how to read it.
//
//   node bench/web/run.mjs [--scene sprites] [--only void-js-webgpu,pixi-webgl] [--runs 3] [--no-build]
import { execFileSync, spawn } from 'node:child_process';
import { createReadStream, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { cpus, hostname, loadavg, tmpdir } from 'node:os';
import { dirname, extname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { gzipSync } from 'node:zlib';
import { createRequire } from 'node:module';
import { build } from 'esbuild';
import { COUNT, SIZE } from './cases/sprites/scene.js';

const benchDir = dirname(fileURLToPath(import.meta.url));
const root = resolve(benchDir, '..', '..');
const outDir = join(root, 'out', 'bench');
const runTimeoutMs = 90000;
const scenes = { sprites: `bench.scene sprites count=${COUNT} size=${SIZE}` };

const args = process.argv.slice(2);
const option = (name, fallback) => { const i = args.indexOf(name); return i < 0 ? fallback : args[i + 1]; };
const scene = option('--scene', 'sprites');
const runs = Number(option('--runs', '3'));
if (!(scene in scenes)) throw new Error(`no scene ${scene}; scenes: ${Object.keys(scenes).join(', ')}`);

// One entry per library and backend. `dir` is what the page downloads, `page` the tags that load it.
const voidWasm = (backend) => ({
	dir: join(outDir, 'void', backend === 'webgpu' ? 'wgpu' : 'gl'),
	page: `<script>window.Module = { canvas: document.getElementById('canvas') };</script><script src="${scene}.js"></script>`,
});
const voidJs = (backend) => ({
	dir: join(outDir, 'void', backend === 'webgpu' ? 'js-wgpu' : 'js-gl'),
	page: `<script src="${scene}Web.js"></script>`,
});
const library = (name) => (backend) => ({
	dir: join(outDir, `${name}-${backend}`),
	page: `<script type="module" src="${scene}.js"></script>`,
	bundle: { entry: join(benchDir, 'cases', scene, `${name}.js`), backend },
});
const implementations = {};
for (const backend of ['webgpu', 'webgl']) {
	implementations[`void-wasm-${backend}`] = voidWasm(backend);
	implementations[`void-js-${backend}`] = voidJs(backend);
	implementations[`pixi-${backend}`] = library('pixi')(backend);
	implementations[`three-${backend}`] = library('three')(backend);
}
const only = option('--only', null);
const chosen = only === null ? Object.keys(implementations) : only.split(',');
for (const name of chosen) if (!(name in implementations)) throw new Error(`no implementation ${name}`);

const buildErrors = {};
const voidBackends = { 'void-wasm-webgpu': 'wgpu', 'void-wasm-webgl': 'gl', 'void-js-webgpu': 'js-wgpu', 'void-js-webgl': 'js-gl' };

async function buildOne(name) {
	const impl = implementations[name];
	rmSync(impl.dir, { recursive: true, force: true });
	if (name in voidBackends) {
		const logs = join(outDir, 'logs');
		mkdirSync(logs, { recursive: true });
		execFileSync('sh', ['scripts/build-web.sh'], {
			cwd: root, stdio: 'inherit',
			env: {
				...process.env, VOID_WEB_MSCFLAGS: '--release', VOID_WEB_ENTRY: `bench/web/cases/${scene}/void/${scene}.ms`,
				VOID_WEB_JS_ENTRY: `bench/web/cases/${scene}/void/${scene}Web.jms`, VOID_WEB_DEST: join(outDir, 'void'), VOID_WEB_LOGDIR: logs,
				VOID_WEB_PRELOAD: '', VOID_WEB_JS_ASSETS: '', VOID_WEB_BACKENDS: voidBackends[name],
			},
		});
		return;
	}
	const b = impl.bundle;
	await build({
		entryPoints: [b.entry], bundle: true, format: 'esm', target: 'es2022', minify: true, logLevel: 'warning',
		define: { BENCH_BACKEND: JSON.stringify(b.backend) }, outfile: join(impl.dir, `${scene}.js`),
		alias: b.backend === 'webgpu'
			? { three: createRequire(import.meta.url).resolve('three/webgpu'), 'bench-three-renderer': join(benchDir, 'cases', 'threeRendererWebgpu.js') }
			: { 'bench-three-renderer': join(benchDir, 'cases', 'threeRendererWebgl.js') },
	});
}

async function buildAll() {
	for (const name of chosen) {
		try {
			await buildOne(name);
		} catch (e) {
			rmSync(implementations[name].dir, { recursive: true, force: true });
			buildErrors[name] = name in voidBackends
				? `build failed, log out/bench/logs/void_web_${voidBackends[name]}.log`
				: `build failed: ${String(e.message).split('\n')[0]}`;
		}
	}
}

function bytes(dir) {
	let raw = 0, gzip = 0;
	const walk = (d) => {
		for (const entry of readdirSync(d)) {
			const path = join(d, entry);
			if (statSync(path).isDirectory()) { walk(path); continue; }
			const data = readFileSync(path);
			raw += data.length;
			gzip += gzipSync(data, { level: 9 }).length;
		}
	};
	walk(dir);
	return { raw, gzip };
}

const types = { '.js': 'text/javascript', '.wasm': 'application/wasm', '.html': 'text/html' };
const page = (impl) => `<!DOCTYPE html><meta charset="utf-8"><body style="margin:0;background:#000">
<canvas id="canvas" width="1280" height="720" style="display:block;width:1280px;height:720px"></canvas>
<script src="/driver.js"></script>
${impl.page}`;

function serve(impl) {
	const server = createServer((req, res) => {
		const path = new URL(req.url, 'http://x').pathname;
		res.setHeader('cross-origin-opener-policy', 'same-origin');
		res.setHeader('cross-origin-embedder-policy', 'require-corp');
		if (path === '/') { res.setHeader('content-type', types['.html']); res.end(page(impl)); return; }
		const file = path === '/driver.js' ? join(benchDir, 'driver.js') : join(impl.dir, path.slice(1));
		if (!file.startsWith(impl.dir) && file !== join(benchDir, 'driver.js') || !existsSync(file)) { res.statusCode = 404; res.end(); return; }
		res.setHeader('content-type', types[extname(file)] ?? 'application/octet-stream');
		createReadStream(file).pipe(res);
	});
	return new Promise((done) => server.listen(0, '127.0.0.1', () => done(server)));
}

const sleep = (ms) => new Promise((done) => setTimeout(done, ms));
const chromePath = process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
let chromeVersion = null;

async function runOnce(impl) {
	const loadBefore = loadavg()[0];
	const server = await serve(impl);
	const port = 9400 + Math.floor(Math.random() * 500);
	const profile = mkdtempSync(join(tmpdir(), 'void-bench-'));
	const chrome = spawn(chromePath, [
		'--headless=new', `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`, '--no-first-run',
		'--force-device-scale-factor=1', '--window-size=1280,720', '--enable-precise-memory-info',
		'--disable-gpu-vsync', '--disable-frame-rate-limit', 'about:blank',
	], { stdio: 'ignore' });
	try {
		let target = null;
		for (let i = 0; i < 100 && target === null; i++) {
			try {
				chromeVersion ??= (await (await fetch(`http://127.0.0.1:${port}/json/version`)).json()).Browser;
				target = (await (await fetch(`http://127.0.0.1:${port}/json/list`)).json()).find((t) => t.type === 'page') ?? null;
			} catch {}
			if (target === null) await sleep(100);
		}
		if (target === null) throw new Error('Chrome did not open its DevTools port');
		const ws = new WebSocket(target.webSocketDebuggerUrl);
		let next = 1;
		const pending = new Map(), logs = [];
		ws.onmessage = (event) => {
			const msg = JSON.parse(event.data);
			if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id); }
			else if (msg.method === 'Runtime.consoleAPICalled') logs.push(msg.params.args.map((a) => a.value ?? a.description ?? '').join(' '));
			else if (msg.method === 'Runtime.exceptionThrown') logs.push(`EXCEPTION ${msg.params.exceptionDetails.exception?.description ?? msg.params.exceptionDetails.text}`);
		};
		const send = (method, params = {}) => new Promise((done) => { const id = next++; pending.set(id, done); ws.send(JSON.stringify({ id, method, params })); });
		await new Promise((done, fail) => { ws.onopen = done; ws.onerror = fail; });
		await send('Runtime.enable');
		await send('Page.navigate', { url: `http://127.0.0.1:${server.address().port}/` });
		const evaluate = async (expression) => (await send('Runtime.evaluate', { expression, returnByValue: true })).result?.result?.value;
		const started = Date.now();
		let result = null;
		while (result === null && Date.now() - started < runTimeoutMs) {
			await sleep(250);
			result = await evaluate('window.benchResult');
			const errors = (await evaluate('window.benchErrors')) ?? [];
			const thrown = logs.filter((l) => l.startsWith('EXCEPTION'));
			if (errors.length > 0 || thrown.length > 0) return { stopped: [...errors, ...thrown][0].split('\n').slice(0, 3).join(' | ') };
		}
		if (result === null) return { stopped: `no result after ${runTimeoutMs} ms; console: ${logs.slice(-3).join(' | ')}` };
		const shot = (await send('Page.captureScreenshot', { format: 'png' })).result?.data;
		if (shot) { mkdirSync(join(outDir, 'shots'), { recursive: true }); writeFileSync(join(outDir, 'shots', `${impl.name}.png`), Buffer.from(shot, 'base64')); }
		if (!logs.includes(scenes[scene])) return { stopped: `scene row missing or different; want "${scenes[scene]}", console: ${logs.filter((l) => l.startsWith('bench.')).join(' | ')}` };
		return { ...result, load: Math.max(loadBefore, loadavg()[0]) };
	} finally {
		chrome.kill();
		server.close();
		await sleep(200);
		try { rmSync(profile, { recursive: true, force: true }); } catch {}
	}
}

const median = (v) => { const s = [...v].sort((a, b) => a - b); return s[Math.floor(s.length / 2)]; };

if (!args.includes('--no-build')) await buildAll();
const rows = [];
for (const name of chosen) {
	const impl = { ...implementations[name], name };
	const size = existsSync(impl.dir) ? bytes(impl.dir) : null;
	const samples = [];
	let stopped = buildErrors[name] ?? (size === null ? `not built: ${impl.dir}` : null);
	for (let i = 0; i < runs && stopped === null; i++) {
		const r = await runOnce(impl);
		if (r.stopped) stopped = r.stopped; else samples.push(r);
	}
	const row = { implementation: name, bytes: size, stopped };
	if (stopped === null) {
		for (const key of ['firstFrameMs', 'cpuMedianMs', 'cpuP95Ms', 'intervalMedianMs', 'intervalP95Ms', 'jsHeapMB']) {
			row[key] = samples[0][key] === null ? null : median(samples.map((s) => s[key]));
		}
		row.isolated = samples.every((s) => s.isolated);
		row.loadMax = Math.max(...samples.map((s) => s.load));
	}
	rows.push(row);
	console.log(JSON.stringify(row));
}

const pkg = JSON.parse(readFileSync(join(benchDir, 'package.json'), 'utf8')).devDependencies;
let msc = null;
try { msc = execFileSync('msc', ['--version'], { encoding: 'utf8' }).replace(/\x1b\[[0-9;]*m/g, '').trim(); } catch {}
const record = {
	scene, date: new Date().toISOString(), host: process.env.BENCH_HOST || hostname(), cores: cpus().length, chrome: chromeVersion, runs,
	void: process.env.BENCH_VOID_COMMIT || null, msc: process.env.BENCH_MSC || msc, three: pkg.three, pixi: pkg['pixi.js'], rows,
};
mkdirSync(join(benchDir, 'baseline'), { recursive: true });
const file = join(benchDir, 'baseline', `${scene}-${record.host}-${record.date.slice(0, 10)}.json`);
writeFileSync(file, JSON.stringify(record, null, '\t') + '\n');

const fmt = (v, d = 2) => v === null || v === undefined ? '—' : v.toFixed(d);
console.log(`\n${scene} on ${record.host}, ${record.chrome}, ${runs} runs, medians`);
console.log('| implementation | gzip KB | first frame ms | CPU/frame ms (p95) | frame interval ms (p95) | JS heap MB | load |');
console.log('|---|---|---|---|---|---|---|');
for (const r of rows) {
	if (r.stopped) { console.log(`| ${r.implementation} | ${r.bytes ? fmt(r.bytes.gzip / 1024, 1) : '—'} | stopped: ${r.stopped} | | | |`); continue; }
	console.log(`| ${r.implementation} | ${fmt(r.bytes.gzip / 1024, 1)} | ${fmt(r.firstFrameMs, 0)} | ${fmt(r.cpuMedianMs)} (${fmt(r.cpuP95Ms)}) | ${fmt(r.intervalMedianMs)} (${fmt(r.intervalP95Ms)}) | ${fmt(r.jsHeapMB, 1)} | ${fmt(r.loadMax, 1)} |`);
}
console.log(`\nwritten ${file}`);
