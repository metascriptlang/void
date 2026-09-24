import { spawn } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';

const [runnerUrl, listPath, backend] = process.argv.slice(2);
const chrome = process.env.CHROME || 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const port = Number(process.env.VOID_CDP_PORT || 9337);
const sceneTimeoutMs = 30000;

const scenes = readFileSync(listPath, 'utf8').split(/\r?\n/).filter(Boolean).map((line, index) => {
	const [name, , w, h] = line.split('\t');
	return { index, name, w: Number(w), h: Number(h) };
});

const profile = mkdtempSync(join(tmpdir(), 'void-cdp-'));
const browser = spawn(chrome, [
	'--headless=new', `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`,
	'--force-device-scale-factor=1', '--window-size=1024,768', '--no-first-run', 'about:blank',
], { stdio: 'ignore' });

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function waitForBrowser() {
	for (let i = 0; i < 100; i++) {
		try {
			const r = await fetch(`http://127.0.0.1:${port}/json/version`);
			if (r.ok) return;
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
			logs.push(msg.params.args.map((a) => a.value ?? '').join(' '));
		} else if (msg.method === 'Runtime.exceptionThrown') {
			logs.push(`EXCEPTION ${msg.params.exceptionDetails.text}`);
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
	const r = await s.send('Runtime.evaluate', { expression, returnByValue: true });
	return r.result?.result?.value;
}

async function capture(scene) {
	const dir = `out/golden/${backend}/${dirname(scene.name)}`;
	const query = `scene=${scene.index}&w=${scene.w}&h=${scene.h}&dir=${encodeURIComponent(dir)}`;
	const created = await (await fetch(`http://127.0.0.1:${port}/json/new?about:blank`, { method: 'PUT' })).json();
	const s = session(created.webSocketDebuggerUrl);
	await s.open;
	await s.send('Runtime.enable');
	await s.send('Page.navigate', { url: `${runnerUrl}?${query}` });
	let done = null;
	for (let waited = 0; waited < sceneTimeoutMs && done === null; waited += 100) {
		await sleep(100);
		done = await evaluate(s, 'window.voidDone');
		if (done === undefined) done = null;
	}
	const path = `${dir}/${scene.name.split('/').pop()}.png`;
	let wrote = false;
	if (done === 0) {
		const b64 = await evaluate(s, `(() => { const b = FS.readFile(${JSON.stringify(path)}); let t = '';
			for (let i = 0; i < b.length; i++) t += String.fromCharCode(b[i]); return btoa(t); })()`);
		if (b64) {
			mkdirSync(dir, { recursive: true });
			writeFileSync(path, Buffer.from(b64, 'base64'));
			wrote = true;
		}
	}
	const shown = done === 0 && wrote ? /^(CAPTURED|FAIL|SKIP)/ : /^(CAPTURED|FAIL|SKIP|EXCEPTION)/;
	for (const line of s.logs) {
		if (shown.test(line)) console.log(line);
	}
	if (done === null) console.log(`FAIL ${scene.name} timed out after ${sceneTimeoutMs} ms in the browser`);
	else if (done !== 0) console.log(`FAIL ${scene.name} exited ${done} in the browser`);
	else if (!wrote) console.log(`FAIL ${scene.name} reported a capture but ${path} could not be read`);
	s.close();
	await fetch(`http://127.0.0.1:${port}/json/close/${created.id}`);
}

try {
	await waitForBrowser();
	for (const scene of scenes) await capture(scene);
} finally {
	browser.kill();
}
