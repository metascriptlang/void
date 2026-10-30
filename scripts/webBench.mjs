// Runs one tests/bench scene built for the browser in headless Chrome and prints the rows its wasm
// logs, in the `name value` format scripts/bench-ab.sh parses, so it can stand in for the exe:
//
//   node scripts/webBench.mjs <wgpu|gl> <dir>/bench<Scene>.exe
//
// The `.exe` path is only a name: the driver serves <dir> and loads <dir>/bench<Scene>.js, the
// output of scripts/abBench.sh `build web`. bench-ab.sh reaches it through AB_RUN.
import { spawn } from 'node:child_process';
import { createReadStream, existsSync, mkdtempSync, rmSync } from 'node:fs';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { basename, dirname, extname, join } from 'node:path';
import { pathToFileURL } from 'node:url';

const rowPattern = /^[A-Za-z0-9]+\.[A-Za-z0-9.]+ -?[0-9.eE+-]+$/;
const runTimeoutMs = 180000;
const quietMs = 1000;
const types = { '.js': 'text/javascript', '.wasm': 'application/wasm', '.html': 'text/html' };

export function benchRows(logs) {
	return logs.flatMap((entry) => entry.split(/\r?\n/)).map((line) => line.trim()).filter((line) => rowPattern.test(line));
}

export function pageFor(scene) {
	return `<!DOCTYPE html><meta charset="utf-8"><body style="margin:0;background:#000">
<canvas id="canvas" style="display:block;width:1280px;height:720px"></canvas>
<script>
window.voidExit = null;
window.Module = { canvas: document.getElementById('canvas'), onExit: (code) => { window.voidExit = code; } };
</script>
<script src="bench${scene}.js"></script>`;
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

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
			logs.push(msg.params.args.map((a) => a.value ?? '').join(' '));
		} else if (msg.method === 'Runtime.exceptionThrown') {
			logs.push(`EXCEPTION ${msg.params.exceptionDetails.exception?.description ?? msg.params.exceptionDetails.text}`);
		}
	};
	const send = (method, params = {}) => new Promise((resolve) => {
		const id = next++;
		pending.set(id, resolve);
		ws.send(JSON.stringify({ id, method, params }));
	});
	const open = new Promise((resolve, reject) => { ws.onopen = resolve; ws.onerror = reject; });
	return { open, send, logs };
}

async function evaluate(s, expression) {
	return (await s.send('Runtime.evaluate', { expression, returnByValue: true })).result?.result?.value;
}

async function run(backend, dir, scene) {
	const server = createServer((req, res) => {
		const path = new URL(req.url, 'http://x').pathname.slice(1);
		const file = path === '' ? null : join(dir, basename(path));
		if (path === '') { res.setHeader('content-type', types['.html']); res.end(pageFor(scene)); return; }
		if (!existsSync(file)) { res.statusCode = 404; res.end(); return; }
		res.setHeader('content-type', types[extname(file)] ?? 'application/octet-stream');
		createReadStream(file).pipe(res);
	});
	await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
	const chrome = process.env.CHROME || 'C:/Program Files/Google/Chrome/Application/chrome.exe';
	const port = Number(process.env.VOID_CDP_PORT || 9341);
	const profile = mkdtempSync(join(tmpdir(), 'void-webbench-'));
	const browser = spawn(chrome, [
		'--headless=new', `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`,
		'--force-device-scale-factor=1', '--window-size=1280,800', '--no-first-run', 'about:blank',
	], { stdio: 'ignore' });
	try {
		let page = null;
		for (let i = 0; i < 100 && page === null; i++) {
			try { page = (await (await fetch(`http://127.0.0.1:${port}/json/list`)).json()).find((t) => t.type === 'page') ?? null; } catch {}
			if (page === null) await sleep(100);
		}
		if (page === null) throw new Error('Chrome did not open its DevTools port');
		const s = session(page.webSocketDebuggerUrl);
		await s.open;
		await s.send('Runtime.enable');
		await s.send('Page.navigate', { url: `http://127.0.0.1:${server.address().port}/` });
		let rows = 0, lastChange = Date.now();
		const started = Date.now();
		for (;;) {
			await sleep(100);
			const count = benchRows(s.logs).length;
			if (count !== rows) { rows = count; lastChange = Date.now(); }
			const seen = benchRows(s.logs).some((row) => row.includes('.present.ms '));
			if (seen && (Date.now() - lastChange > quietMs || (await evaluate(s, 'window.voidExit')) !== null)) break;
			if (Date.now() - started > runTimeoutMs) { console.log(`FAIL ${backend} ${scene} timed out after ${runTimeoutMs} ms`); break; }
		}
		for (const line of s.logs.filter((l) => /^EXCEPTION/.test(l))) console.log(line);
		for (const row of benchRows(s.logs)) console.log(row);
	} finally {
		browser.kill();
		server.close();
		try { rmSync(profile, { recursive: true, force: true }); } catch {}
	}
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
	const [backend, exe] = process.argv.slice(2);
	const match = /^bench([A-Za-z0-9]+)\.exe$/.exec(basename(exe ?? ''));
	if (!['wgpu', 'gl'].includes(backend) || !match) {
		console.error('usage: node scripts/webBench.mjs <wgpu|gl> <dir>/bench<Scene>.exe');
		process.exit(2);
	}
	await run(backend, dirname(exe), match[1]);
}
