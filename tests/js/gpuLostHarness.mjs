import { readFileSync, writeFileSync, mkdtempSync, rmSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join } from "node:path";

const minifyAfterPatch = process.argv.includes("--minify");

const [bundlePath, backend, driver] = process.argv.slice(2).filter((a) => a !== "--minify");
if (!bundlePath || (backend !== "gl" && backend !== "gpu") || (driver !== "views" && driver !== "window")) {
	throw new Error("usage: node tests/js/gpuLostHarness.mjs <bundle> gl|gpu views|window [--minify]   (msc build src/examples/viewsJsEntry.jms|windowJsEntry.jms --target=js [-d:webgl2] --output=<bundle>)");
}
const windowMode = driver === "window";

const doorStubs = ["doorSetup", "doorShutdown", "doorBeginScreenPass", "doorCommit"];
let source = readFileSync(bundlePath, "utf8").replace(/^import .* from "node:[a-z_/]+";$/gm, "");
for (const name of doorStubs) {
	const found = source.match(new RegExp(`function (${name}(?:__\\w+)?)\\(`));
	if (!found) throw new Error(`stub target ${name} is not in the bundle`);
	const present = name === "doorCommit" ? `${source.match(/function (viewsPresent__\w+)\(/)[1]}();` : "";
	source = source.replace(`function ${found[1]}(`, `function ${found[1]}() { globalThis.__door.push("${name}"); ${present} } function ${found[1]}Unused(`);
}
if (minifyAfterPatch) {
	const dir = mkdtempSync(join(tmpdir(), "voidMin-"));
	writeFileSync(join(dir, "patched.js"), source);
	execFileSync("sh", ["scripts/jsMinify.sh", join(dir, "patched.js"), join(dir, "patched.min.js")], { stdio: "inherit" });
	source = readFileSync(join(dir, "patched.min.js"), "utf8");
	rmSync(dir, { recursive: true });
}
globalThis.__door = [];

const rejections = [];
process.on("unhandledRejection", (reason) => {
	if (windowMode) { rejections.push(reason.message); return; }
	console.error("rejection:", reason && (reason.message ?? reason));
	process.exit(2);
});

function target() {
	const listeners = new Map();
	return {
		listeners,
		addEventListener(type, f) {
			if (!listeners.has(type)) listeners.set(type, []);
			listeners.get(type).push(f);
		},
		removeEventListener(type, f) {
			const list = listeners.get(type) ?? [];
			const at = list.indexOf(f);
			if (at >= 0) list.splice(at, 1);
		},
	};
}
function count(t, type) { return (t.listeners.get(type) ?? []).length; }
function fire(t, type, event = {}) {
	let prevented = false;
	const e = { ...event, preventDefault() { prevented = true; } };
	for (const f of [...(t.listeners.get(type) ?? [])]) f(e);
	return prevented;
}

let deviceCount = 0;
let nextDeviceFails = false;
let deviceGate = Promise.resolve();
let releaseDevices;
const devices = [];
function fakeDevice() {
	let resolveLost;
	const device = Object.assign(target(), {
		lost: new Promise((resolve) => { resolveLost = resolve; }),
		queue: {},
		limits: {},
		features: new Set(),
		loseWith(reason, message) { resolveLost({ reason, message }); },
	});
	devices.push(device);
	return device;
}
if (backend === "gpu") {
	const adapter = {
		features: new Set(),
		limits: { maxColorAttachments: 8, maxSampledTexturesPerShaderStage: 16, maxStorageBuffersPerShaderStage: 8, maxStorageTexturesPerShaderStage: 4 },
		requestDevice: async () => {
			deviceCount++;
			await deviceGate;
			if (nextDeviceFails) throw new Error("no adapter left");
			return fakeDevice();
		},
	};
	Object.defineProperty(globalThis, "navigator", {
		configurable: true,
		value: { gpu: { requestAdapter: async () => adapter, getPreferredCanvasFormat: () => "bgra8unorm" } },
	});
}

const attrs = new Map();
const selectors = [];
let pageHasCanvas = true;
let contextCount = 0;
const canvas = Object.assign(target(), {
	clientWidth: 300, clientHeight: 150, width: 0, height: 0, style: {},
	setAttribute: (k, v) => attrs.set(k, v),
	removeAttribute: (k) => attrs.delete(k),
	getBoundingClientRect: () => ({ left: 0, top: 0 }),
	insertAdjacentElement() {},
	requestPointerLock() {},
	getContext(kind) {
		contextCount++;
		if (kind === "webgpu") return { configure() {}, unconfigure() {} };
		return new Proxy({}, { get: (_, n) => (n === "getExtension" ? () => ({}) : () => 0) });
	},
});
globalThis.document = Object.assign(target(), {
	title: "", pointerLockElement: null, activeElement: null, fullscreenElement: null,
	querySelector: (selector) => { selectors.push(selector); return pageHasCanvas ? canvas : null; },
	createElement: () => Object.assign(target(), { style: {}, setAttribute() {}, remove() {}, focus() {}, blur() {} }),
	body: { appendChild() {}, removeChild() {} },
});
globalThis.window = Object.defineProperty(target(), "devicePixelRatio", { get: () => 1 });
let rafQueue = [];
globalThis.requestAnimationFrame = (f) => { rafQueue.push(f); return rafQueue.length; };
globalThis.cancelAnimationFrame = () => { rafQueue = []; };

const logs = [];
const realLog = console.log;
console.log = (...a) => logs.push(a.join(" "));
(0, eval)(source);

const w = windowMode ? globalThis.voidAppWindow : null;
const appEvents = [];
if (w) { w.setHandler(() => { appEvents.push(w.eventType()); }); }
const SUSPENDED = 19;
const RESUMED = 20;
const QUIT_REQUESTED = 21;

let clock = 1000;
function step() { const q = rafQueue; rafQueue = []; clock += 16; q.forEach((f) => f(clock)); }
const settle = () => new Promise((r) => setTimeout(r, 20));
const frames = () => logs.filter((l) => l.startsWith(`void js ${windowMode ? "window" : "view"} frame`)).length;
const door = () => globalThis.__door.filter((n) => n === "doorSetup" || n === "doorShutdown").join(",");
const errors = windowMode ? rejections : [];
const onError = (e) => errors.push(e.message);

let failed = 0;
let passed = 0;
function check(name, got, want) {
	const ok = got === want;
	if (ok) passed++; else failed++;
	realLog(`${ok ? "ok  " : "FAIL"} ${name}${ok ? "" : `\n     got  ${got}\n     want ${want}`}`);
}

function quit() { w.requestQuit(); step(); }
function startRun() {
	if (!windowMode) { return globalThis.voidStart(canvas, onError); }
	globalThis.voidWindowRestart();
	return quit;
}
let stop = windowMode ? quit : globalThis.voidStart(canvas, onError);
await settle();
step();
check("the first frame runs", frames(), 1);
if (windowMode) {
	check("the window picks #canvas", selectors[0], "#canvas");
	check("the window's init ran once", logs.filter((l) => l === "void js window init").length, 1);
}
const START = windowMode ? "doorSetup" : "doorShutdown,doorSetup";
const AGAIN = `${START},doorShutdown,doorSetup`;
check("the door is set up once at start", door(), START);

const before = frames();
if (backend === "gl") {
	check("contextlost is prevented so the browser may restore", fire(canvas, "webglcontextlost"), true);
} else {
	let release;
	deviceGate = new Promise((resolve) => { release = resolve; });
	devices[0].loseWith("unknown", "gpu process crashed");
	await settle();
	releaseDevices = release;
}
if (windowMode) { check("a loss tells the app it is suspended", appEvents.join(","), `${SUSPENDED}`); }
step();
step();
const duringLoss = windowMode && backend === "gl" ? 2 : 0;
check(duringLoss ? "a GL window keeps drawing while the context is gone, as the C does" : "frames are skipped while the GPU is gone", frames(), before + duringLoss);
check("the loop keeps running while the GPU is gone", rafQueue.length, 1);
check("a loss alone leaves the door alone", door(), START);
if (backend === "gpu") {
	check("a lost device asks for a new one", deviceCount, 2);
	releaseDevices();
	await settle();
	if (windowMode) { check("a new device tells the app it is resumed", appEvents.join(","), `${SUSPENDED},${RESUMED}`); }
} else {
	fire(canvas, "webglcontextlost");
	if (windowMode) { check("a second loss event is not a second suspend", appEvents.join(","), `${SUSPENDED}`); }
	fire(canvas, "webglcontextrestored");
	if (windowMode) { check("a restored context tells the app it is resumed", appEvents.join(","), `${SUSPENDED},${RESUMED}`); }
}
check("the door waits for the next frame", door(), START);
step();
check("the next frame shuts the door down and sets it up again", door(), AGAIN);
check("frames resume", frames(), before + duringLoss + 1);
step();
check("the door is rebuilt once per loss", door(), AGAIN);
check("frames keep running", frames(), before + duringLoss + 2);
check("no error reached the caller", errors.length, 0);

if (backend === "gpu") {
	const wasDevices = deviceCount;
	devices[devices.length - 1].loseWith("destroyed", "destroyed by the page");
	await settle();
	check("a destroyed device is recovered too", deviceCount, wasDevices + 1);
	step();
	check("and the door follows it", door(), `${AGAIN},doorShutdown,doorSetup`);
}

const setups = door().split(",").filter((n) => n === "doorSetup").length;
stop();
const keepsDoor = backend === "gpu" && !windowMode;
check(windowMode ? "quit shuts the door down" : keepsDoor ? "stop keeps the WebGPU door up, as the C" : "stop shuts the door down", door().split(",").at(-1), keepsDoor ? "doorSetup" : "doorShutdown");
check(windowMode ? "quit ends the loop" : "stop ends the loop", rafQueue.length, 0);
if (windowMode) {
	check("quit tells the app once", appEvents.filter((e) => e === QUIT_REQUESTED).length, 1);
	check("quit takes the canvas attribute back", attrs.size, 0);
}
const eventsAtStop = appEvents.length;
if (backend === "gl") { fire(canvas, "webglcontextlost"); fire(canvas, "webglcontextrestored"); }
else { devices[devices.length - 1].loseWith("unknown", "after stop"); await settle(); }
check("a loss after stop reaches nobody", appEvents.length, eventsAtStop);

stop = startRun();
await settle();
step();
check("a start after a stop sets the door up again", door().split(",").filter((n) => n === "doorSetup").length, setups + 1);
check("the restarted view draws", frames() > before + 2, true);
if (backend === "gl") {
	check("a restart replaces the context listeners instead of adding to them", `${count(canvas, "webglcontextlost")} ${count(canvas, "webglcontextrestored")}`, "1 1");
}
check("no error after the restart", errors.length, 0);

if (backend === "gpu") {
	const seen = appEvents.length;
	nextDeviceFails = true;
	devices[devices.length - 1].loseWith("unknown", "second loss");
	await settle();
	check("a device that cannot be replaced reaches onError, naming the case", /^void: the WebGPU device was lost and a new one could not be made: .*no adapter left/.test(errors.join("|")), true);
	if (windowMode) check("and the app stays suspended", appEvents.slice(seen).join(","), `${SUSPENDED}`);
	nextDeviceFails = false;
	stop();

	stop = startRun();
	await settle();
	step();
	const quiet = errors.length;
	const resumedBefore = appEvents.filter((e) => e === RESUMED).length;
	devices[devices.length - 1].loseWith("unknown", "lost then stopped");
	stop();
	await settle();
	check("a stop during recovery drops the new device quietly", `${errors.length - quiet} ${appEvents.filter((e) => e === RESUMED).length - resumedBefore}`, "0 0");
	stop = startRun();
	await settle();
	step();
	check("a start after a stop during recovery is not suspended", frames() > 0 && rafQueue.length === 1, true);
}

function refusal(call) {
	try { call(); } catch (error) { return error.message; }
	return "";
}
if (windowMode) {
	check("a second live window is refused, naming the case", refusal(() => globalThis.voidRun(800, 600, () => {}, () => {})), "void: voidWebRun: the browser window already runs");
} else {
	if (backend === "gl") {
		check("a second live view is refused, naming the case", refusal(() => globalThis.voidStart(canvas, onError)), "void: voidViewCreate: WebGL2 runs one view at a time; stop view 2 first");
	} else {
		let second;
		check("a second WebGPU view is accepted", refusal(() => { second = globalThis.voidStart(canvas, onError); }), "");
		await settle();
		second();
	}
	check("a window is refused beside host views, naming the case", refusal(() => globalThis.voidRun(800, 600, () => {}, () => {})), "void: voidRun: this document already drives Void through host views");
}
const drawn = frames();
step();
check("the refusal leaves the live run drawing", frames(), drawn + 1);
stop();
if (windowMode) {
	pageHasCanvas = false;
	check("a page without #canvas is refused, naming the case", refusal(() => globalThis.voidWindowRestart()), "void: no canvas #canvas: the page has no #canvas");
	pageHasCanvas = true;
}

realLog(failed === 0 ? `ALL OK (${passed})` : `${failed} FAILED of ${passed + failed}`);
if (failed !== 0) process.exit(1);
