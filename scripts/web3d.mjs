// Runs void3d's readback checks in headless Chrome over DevTools: one page per run, the run's
// VOID_* settings in the query (tests/integration/web/runner3d.html puts them in ENV), its verdict
// the window.voidDone the capture library sets (tests/capture/capture.c voidCaptureExit).
import { spawn } from 'node:child_process';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const [baseUrl, ...runs] = process.argv.slice(2);
const chrome = process.env.CHROME || 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const port = Number(process.env.VOID_CDP_PORT || 9338);
const runTimeoutMs = 60000;
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const profile = mkdtempSync(join(tmpdir(), 'void3d-cdp-'));
const browser = spawn(chrome, [
	'--headless=new', `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`,
	'--force-device-scale-factor=1', '--window-size=1024,768', '--no-first-run', 'about:blank',
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
			logs.push(msg.params.args.map((a) => a.value ?? '').join(' '));
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
	const r = await s.send('Runtime.evaluate', { expression, returnByValue: true });
	return r.result?.result?.value;
}

// A run is name or name:VOID_SETTING=value.
async function run(spec) {
	const [name, setting] = spec.split(':');
	const query = `entry=${name}` + (setting ? `&${setting}` : '');
	const created = await (await fetch(`http://127.0.0.1:${port}/json/new?about:blank`, { method: 'PUT' })).json();
	const s = session(created.webSocketDebuggerUrl);
	await s.open;
	await s.send('Runtime.enable');
	await s.send('Page.navigate', { url: `${baseUrl}/${name}/gl/runner3d.html?${query}` });
	let done = null;
	for (let waited = 0; waited < runTimeoutMs && done === null; waited += 100) {
		await sleep(100);
		done = await evaluate(s, 'window.voidDone');
		if (done === undefined) done = null;
	}
	for (const line of s.logs) {
		if (/^(PASS|FAIL|EXCEPTION)/.test(line)) console.log(`${spec}\t${line}`);
	}
	if (done === null) console.log(`RUN ${spec} timed out after ${runTimeoutMs} ms`);
	else console.log(`RUN ${spec} exited ${done}`);
	s.close();
	await fetch(`http://127.0.0.1:${port}/json/close/${created.id}`);
}

try {
	await waitForBrowser();
	for (const spec of runs) await run(spec);
} finally {
	browser.kill();
}
