import { readFileSync } from "node:fs";

const [bundlePath] = process.argv.slice(2);
if (!bundlePath) {
	throw new Error("usage: node tests/js/webgl2FrameHarness.mjs <bundle>   (msc build src/examples/webgl2JsFrame.jms --target=js -d:webgl2 --output=<bundle>)");
}

const calls = [];
const results = {
	getShaderParameter: true,
	getProgramParameter: true,
	getError: 0,
	getUniformLocation: { uniform: true },
	getParameter: 16,
	checkFramebufferStatus: 0x8cd5,
	getExtension: {},
};
const context = new Proxy({}, {
	get: (_, name) => {
		if (typeof name !== "string") return undefined;
		if (/^[A-Z_0-9]+$/.test(name)) return 0;
		return (...args) => {
			calls.push(name);
			return name in results ? results[name] : { handle: name };
		};
	},
});
const canvas = { width: 64, height: 64, clientWidth: 64, clientHeight: 64, getContext: () => context, addEventListener() {}, removeEventListener() {} };
globalThis.document = { querySelector: () => canvas };

const logs = [];
console.log = (...x) => logs.push(x.join(" "));
const source = readFileSync(bundlePath, "utf8").replace(/^import .* from "node:[a-z_/]+";$/gm, "");
const failures = [];
process.on("unhandledRejection", (reason) => failures.push(`rejection: ${reason && (reason.stack ?? reason)}`));
(0, eval)(source);
await new Promise((resolve) => setTimeout(resolve, 50));

const draws = calls.filter((c) => c === "drawArrays" || c === "drawElements" || c === "drawArraysInstanced" || c === "drawElementsInstanced");
if (!logs.includes("webgl2 js frame submitted")) failures.push(`the frame did not submit; logs: ${JSON.stringify(logs)}`);
if (draws.length !== 1) failures.push(`expected one draw call, got ${draws.length}`);
if (failures.length > 0) {
	process.stderr.write(`FAIL\n${failures.join("\n")}\n  gl calls: ${calls.join(" ")}\n`);
	process.exit(1);
}
console.error(`webgl2 frame harness: device created, frame submitted, ${draws.length} draw over ${calls.length} GL calls`);
