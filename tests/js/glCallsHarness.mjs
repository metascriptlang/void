import { readFileSync } from "node:fs";

const [bundlePath] = process.argv.slice(2);
if (!bundlePath) {
	throw new Error("usage: node tests/js/glCallsHarness.mjs <bundle>   (msc build tests/js/glCallsEntry.jms --target=js -d:webgl2 --output=<bundle>)");
}

const calls = [];
const bytesOf = (v) => Array.from(new Uint8Array(v.buffer, v.byteOffset, v.byteLength));
const context = new Proxy({}, {
	get: (_, name) => {
		if (name === "getExtension") return () => ({});
		if (name === "bufferSubData") return (target, offset, view) => calls.push({ name, target, offset, bytes: bytesOf(view) });
		if (name === "getBufferSubData") return (target, offset, view) => { for (let i = 0; i < view.length; i++) view[i] = 11 + i; calls.push({ name, target, offset, length: view.length, kind: view.constructor.name }); };
		if (name === "uniform4fv") return (location, view) => calls.push({ name, floats: Array.from(view), kind: view.constructor.name });
		if (name === "texSubImage2D") return (...a) => calls.push({ name, args: a.slice(0, 8), bytes: bytesOf(a[8]), offset: a[9] });
		if (name === "texSubImage3D") return (...a) => calls.push({ name, args: a.slice(0, 10), bytes: bytesOf(a[10]), offset: a[11] });
		if (name === "getUniformLocation") return () => ({ uniform: true });
		return () => 0;
	},
});
const canvas = { getContext: () => context, addEventListener() {}, removeEventListener() {} };
globalThis.document = { querySelector: () => canvas };

const logs = [];
console.log = (...x) => logs.push(x.join(" "));
const source = readFileSync(bundlePath, "utf8").replace(/^import .* from "node:[a-z_/]+";$/gm, "");
(0, eval)(source);

let failed = 0;
function check(what, got, want) {
	const same = JSON.stringify(got, (_, v) => (typeof v === "bigint" ? `${v}n` : v)) === JSON.stringify(want, (_, v) => (typeof v === "bigint" ? `${v}n` : v));
	if (!same) { failed++; process.stderr.write(`FAIL ${what}\n  got    ${JSON.stringify(got, (_, v) => (typeof v === "bigint" ? `${v}n` : v))}\n  wanted ${JSON.stringify(want, (_, v) => (typeof v === "bigint" ? `${v}n` : v))}\n`); }
}
const f32 = (...v) => bytesOf(Float32Array.from(v));
const by = (name) => calls.filter((c) => c.name === name);

const sub = by("bufferSubData");
check("float32 vec at index 2 reaches bufferSubData", sub[0], { name: "bufferSubData", target: 0x8892, offset: 8, bytes: f32(1.5, 2.5, 3.5) });
check("uint8 vec at index 3 reaches bufferSubData", sub[1], { name: "bufferSubData", target: 0x8892, offset: 0, bytes: [2, 3, 4, 5] });
check("uint64 vec at index 1 reaches bufferSubData", sub[2], { name: "bufferSubData", target: 0x8892, offset: 16, bytes: bytesOf(BigUint64Array.of(4294967296n, 7n)) });
check("uniform4fv reads count*4 floats at the byte offset", by("uniform4fv")[0], { name: "uniform4fv", floats: [3, 4, 5, 6, 7, 8, 9, 10], kind: "Float32Array" });
check("getBufferSubData reads into a byte view", by("getBufferSubData")[0], { name: "getBufferSubData", target: 0x8F36, offset: 2, length: 4, kind: "Uint8Array" });
check("texSubImage2D gets the bytes from the element on", by("texSubImage2D")[0], { name: "texSubImage2D", args: [0x0DE1, 0, 1, 2, 1, 1, 0x1908, 0x1401], bytes: [5, 6, 7, 8], offset: 1 });
check("texSubImage3D for a 3D target", by("texSubImage3D")[0], { name: "texSubImage3D", args: [0x806F, 0, 0, 0, 3, 1, 1, 1, 0x1908, 0x1401], bytes: [0, 0, 5, 6, 7, 8], offset: 2 });
check("the mismatching constant is named, in the order of gl.c driverConstants", logs.filter((l) => l.startsWith("constants:"))[0], "constants: entry 9: GL_TEXTURE_2D is 3553 in glCalls.jms and 5 in backend.ms");
check("the count mismatch is named", logs.filter((l) => l.startsWith("constants:"))[1], "constants: backend.ms lists 21 constants and glCalls.jms checks 22");
check("the entry ran to its end", logs.includes("glCallsEntry done"), true);

if (failed > 0) process.exit(1);
console.error("glCalls harness: 10 checks passed");
