import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { runInNewContext } from 'node:vm';

const source = readFileSync(new URL('./web3d.mjs', import.meta.url), 'utf8');
const shell = readFileSync(new URL('./web3d.sh', import.meta.url), 'utf8');
const start = source.indexOf('async function run(spec) {');
const end = source.lastIndexOf('\ntry {');
assert(start >= 0 && end > start, 'web3d run boundary changed');
const runSource = source.slice(start, end);
const countPattern = shell.match(/passed=\$\(grep -c "([^"]+)"/);
assert(countPattern, 'web3d pass counter changed');

async function accepted(logs, done) {
	const output = [];
	let closed = false;
	const context = {
		baseUrl: 'http://fixture', port: 1, runTimeoutMs: 200,
		sleep: async () => {}, evaluate: async () => done,
		fetch: async () => ({ json: async () => ({ id: 'fixture', webSocketDebuggerUrl: 'ws://fixture' }) }),
		session: () => ({
			open: Promise.resolve(), logs, send: async () => {}, close: () => { closed = true; },
		}),
		console: { log: (line) => output.push(line) }, process: {},
	};
	await runInNewContext(runSource + '\nrun("fixture")', context);
	assert(closed, 'run must close its DevTools session');
	const passed = [...output.join('\n').matchAll(new RegExp(countPattern[1], 'gm'))].length;
	return passed === 1 && (context.process.exitCode ?? 0) === 0;
}

for (const [name, logs, done, expected] of [
	['one stage', ['PASS stage=0'], 0, true],
	['three stages count as one run', ['PASS stage=0', 'PASS stage=1', 'PASS stage=2'], 0, true],
	['targeted negative', ['FAIL stage=0'], 1, false],
	['failure despite zero exit', ['PASS stage=0', 'FAIL stage=1'], 0, false],
	['nonzero exit despite pass log', ['PASS stage=0'], 1, false],
	['timeout despite pass log', ['PASS stage=0'], null, false],
	['uncaught runtime failure', ['PASS stage=0', 'EXCEPTION Uncaught RuntimeError: unreachable'], 0, false],
	['successful emscripten exit', ['PASS stage=0', 'EXCEPTION Uncaught ExitStatus'], 0, true],
	['zero exit without assertions', [], 0, false],
]) {
	test(name, async () => assert.equal(await accepted(logs, done), expected));
}

test('shell preserves browser driver failure after pass output', () => {
	const folder = mkdtempSync(join(tmpdir(), 'void-web-verdict-'));
	try {
		const commandStart = shell.indexOf('node scripts/web3d.mjs ');
		const commandEnd = shell.indexOf('\ntotal=', commandStart);
		assert(commandStart >= 0 && commandEnd > commandStart, 'web3d driver boundary changed');
		const out = JSON.stringify(join(folder, 'runs').replaceAll('\\', '/'));
		const result = spawnSync('sh', ['-c', `set -e\nOUT=${out}\nruns=fixture
node() { printf 'RESULT fixture PASS\\n'; return 1; }
${shell.slice(commandStart, commandEnd)}`], { encoding: 'utf8' });
		assert.equal(result.status, 1, result.stdout + result.stderr);
	} finally {
		rmSync(folder, { recursive: true });
	}
});

test('WebGL2 matrix registers narrow and wide LOD with and without outline', () => {
	const declarationStart = shell.indexOf('WEB_CHECKS="');
	const declarationEnd = shell.indexOf('\n\n', declarationStart);
	const loopStart = shell.indexOf('runs=""');
	const loopEnd = shell.indexOf('\n\n(', loopStart);
	assert(declarationStart >= 0 && declarationEnd > declarationStart);
	assert(loopStart >= 0 && loopEnd > loopStart);
	const result = spawnSync('sh', ['-c', `set -e\nset -- --run\n` +
		shell.slice(declarationStart, declarationEnd) + '\n' + shell.slice(loopStart, loopEnd) +
		'\nprintf "%s\\n" "$runs"'], { encoding: 'utf8' });
	assert.equal(result.status, 0, result.stdout + result.stderr);
	const runs = result.stdout.trim().split(/\s+/);
	assert.deepEqual(runs.filter((run) => run.split(':')[0] === 'meshLod'), [
		'meshLod',
		'meshLod:VOID_MESH_LOD_INDEX32=1',
		'meshLod:VOID_MESH_LOD_OUTLINE=1',
		'meshLod:VOID_MESH_LOD_INDEX32=1&VOID_MESH_LOD_OUTLINE=1',
	]);
	assert.equal(runs.length, 31);
});
