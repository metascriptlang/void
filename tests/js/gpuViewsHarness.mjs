import { readFileSync } from "node:fs";

const [bundlePath, backend] = process.argv.slice(2);
if (!bundlePath || (backend !== "gl" && backend !== "gpu")) {
	throw new Error("usage: node tests/js/gpuViewsHarness.mjs <bundle> gl|gpu   (msc build src/examples/viewsJsEntry.jms --target=js [-d:webgl2] --output=<bundle>)");
}

const doorStubs = ["doorSetup", "doorShutdown", "doorBeginScreenPass", "doorCommit"];
let source = readFileSync(bundlePath, "utf8").replace(/^import .* from "node:[a-z_/]+";$/gm, "");
for (const name of doorStubs) {
	const found = source.match(new RegExp(`function (${name}(?:__\\w+)?)\\(`));
	if (!found) throw new Error(`stub target ${name} is not in the bundle`);
	const present = name === "doorCommit" ? `${source.match(/function (viewsPresent__\w+)\(/)[1]}();` : "";
	source = source.replace(`function ${found[1]}(`, `function ${found[1]}() { globalThis.__door.push("${name}"); ${present} } function ${found[1]}Unused(`);
}
if (backend === "gpu") {
	const found = source.match(/function (surfaceUse__\w+)\(/);
	if (!found) throw new Error("surfaceUse is not in the bundle");
	source = source.replace(`function ${found[1]}(`, `function ${found[1]}(surface) { globalThis.__door.push("use:" + surface.context.name); ${found[1]}Used(surface); } function ${found[1]}Used(`);
}
globalThis.__door = [];

process.on("unhandledRejection", (reason) => {
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

let deviceCount = 0;
let deviceGate = Promise.resolve();
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
			return fakeDevice();
		},
	};
	Object.defineProperty(globalThis, "navigator", {
		configurable: true,
		value: { gpu: { requestAdapter: async () => adapter, getPreferredCanvasFormat: () => "bgra8unorm" } },
	});
}

const canvases = [];
function makeCanvas(name, width, height) {
	const attrs = new Map();
	const context = { name, configures: [], unconfigures: 0, configure(c) { this.configures.push(c); }, unconfigure() { this.unconfigures++; } };
	const canvas = Object.assign(target(), {
		name, attrs, context, clientWidth: width, clientHeight: height, width: 0, height: 0, style: {},
		setAttribute: (k, v) => attrs.set(k, v),
		removeAttribute: (k) => attrs.delete(k),
		getBoundingClientRect: () => ({ left: 0, top: 0 }),
		getContext(kind) {
			if (kind === "webgpu") return context;
			return new Proxy({}, { get: (_, n) => (n === "getExtension" ? () => ({}) : () => 0) });
		},
	});
	canvases.push(canvas);
	return canvas;
}
const a = makeCanvas("a", 300, 150);
const b = makeCanvas("b", 200, 100);
globalThis.document = Object.assign(target(), {
	title: "", pointerLockElement: null, activeElement: null, fullscreenElement: null,
	querySelector(selector) {
		const id = selector.match(/^\[data-void-view="(\d+)"\]$/)?.[1];
		return canvases.find((c) => c.attrs.get("data-void-view") === id) ?? null;
	},
	createElement: () => Object.assign(target(), { style: {}, setAttribute() {}, remove() {}, focus() {}, blur() {} }),
	body: { appendChild() {}, removeChild() {} },
});
globalThis.window = Object.defineProperty(target(), "devicePixelRatio", { get: () => 1 });
let rafQueue = [];
globalThis.requestAnimationFrame = (f) => { rafQueue.push(f); return rafQueue.length; };
globalThis.cancelAnimationFrame = () => { rafQueue = []; };

const logs = [];
const realLog = console.log;
console.log = (...x) => logs.push(x.join(" "));
(0, eval)(source);

let clock = 1000;
function step() { const q = rafQueue; rafQueue = []; clock += 16; q.forEach((f) => f(clock)); }
const settle = () => new Promise((r) => setTimeout(r, 20));
const errors = [];
const onError = (e) => errors.push(e.message);
const drawn = () => logs.filter((l) => l.startsWith("void js view frame")).map((l) => l.slice("void js view frame ".length));
const trace = (from) => globalThis.__door.slice(from).filter((n) => n !== "doorSetup" && n !== "doorShutdown");
const door = () => globalThis.__door.filter((n) => n === "doorSetup" || n === "doorShutdown").join(",");
function tick() {
	const from = globalThis.__door.length;
	logs.length = 0;
	step();
	return `${trace(from).join(",")} ${drawn().join(",")}`;
}
function refusal(call) {
	try { call(); } catch (error) { return error.message; }
	return "";
}

let failed = 0;
let passed = 0;
function check(name, got, want) {
	const ok = got === want;
	if (ok) passed++; else failed++;
	realLog(`${ok ? "ok  " : "FAIL"} ${name}${ok ? "" : `\n     got  ${got}\n     want ${want}`}`);
}

if (backend === "gl") {
	const stopA = globalThis.voidStart(a, onError);
	await settle();
	check("the first view draws", tick(), "doorBeginScreenPass,doorCommit 300x150");
	check("a second WebGL2 view is refused, naming the case", refusal(() => globalThis.voidStart(b, onError)), "void: voidViewCreate: WebGL2 runs one view at a time; stop view 1 first");
	check("a refused start takes its canvas attribute back", `${a.attrs.get("data-void-view")} ${b.attrs.size}`, "1 0");
	check("the refusal leaves the live view drawing", tick(), "doorBeginScreenPass,doorCommit 300x150");
	stopA();
	const stopB = globalThis.voidStart(b, onError);
	await settle();
	check("a view started after the stop draws", tick(), "doorBeginScreenPass,doorCommit 200x100");
	stopB();
	check("no error reached the caller", errors.length, 0);
} else {
	const stopA = globalThis.voidStart(a, onError);
	const stopB = globalThis.voidStart(b, onError);
	await settle();
	check("two views share one device", deviceCount, 1);
	check("the door is set up once for both", door(), "doorShutdown,doorSetup");
	check("each view's canvas is configured once, on that device", `${a.context.configures.length} ${b.context.configures.length} ${a.context.configures[0].device === devices[0] && b.context.configures[0].device === devices[0]}`, "1 1 true");
	check("both views draw each tick in insertion order, each on its own surface", tick(), "use:a,doorBeginScreenPass,doorCommit,use:b,doorBeginScreenPass,doorCommit 300x150,200x100");
	check("the loop is one frame callback", rafQueue.length, 1);

	a.clientWidth = 400;
	check("a resized view still draws at its new size", tick(), "use:a,doorBeginScreenPass,doorCommit,use:b,doorBeginScreenPass,doorCommit 400x150,200x100");
	check("resizing one view reconfigures only its surface", `${a.context.configures.length} ${b.context.configures.length}`, "2 1");

	stopA();
	check("stopping one view leaves the other drawing", tick(), "use:b,doorBeginScreenPass,doorCommit 200x100");
	check("the stopped view's surface is released, the other's is not", `${a.context.unconfigures} ${b.context.unconfigures}`, "1 0");
	check("stopping one view keeps the door up", door(), "doorShutdown,doorSetup");
	check("the loop keeps running for the live view", rafQueue.length, 1);
	stopB();
	check("stopping the last view ends the loop", rafQueue.length, 0);
	check("stopping the last view keeps the door up, as the C", door(), "doorShutdown,doorSetup");
	check("stopping the last view keeps the device", deviceCount, 1);

	const again = [globalThis.voidStart(a, onError), globalThis.voidStart(b, onError)];
	await settle();
	check("views started after the stop reuse the device and the door", `${deviceCount} ${door()}`, "1 doorShutdown,doorSetup");
	tick();

	let release;
	deviceGate = new Promise((resolve) => { release = resolve; });
	devices[0].loseWith("unknown", "gpu process crashed");
	await settle();
	check("a device loss asks for one new device, not one per view", deviceCount, 2);
	check("frames are skipped for every view while the GPU is gone", tick(), " ");
	release();
	await settle();
	check("a loss alone leaves the door alone", door(), "doorShutdown,doorSetup");
	check("the first view after the new device rebuilds the door, once for both", `${tick()} ${door()}`, "use:a,doorBeginScreenPass,doorCommit,use:b,doorBeginScreenPass,doorCommit 400x150,200x100 doorShutdown,doorSetup,doorShutdown,doorSetup");
	check("both canvases are configured again, on the new device", `${a.context.configures.at(-1).device === devices[1]} ${b.context.configures.at(-1).device === devices[1]}`, "true true");
	check("the door is not rebuilt again", `${tick() !== ""} ${door()}`, "true doorShutdown,doorSetup,doorShutdown,doorSetup");
	again.forEach((stop) => stop());
	check("no error reached the caller", errors.length, 0);
}

realLog(failed === 0 ? `ALL OK (${passed})` : `${failed} FAILED of ${passed + failed}`);
if (failed !== 0) process.exit(1);
