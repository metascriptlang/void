import { readFileSync } from "node:fs";
import { gzipSync } from "node:zlib";

const [mode, bundlePath] = process.argv.slice(2);
const bytes = readFileSync(bundlePath);
const gzipBytes = (buffer) => gzipSync(buffer, { level: 9 }).length;
const directory = (name) => {
	if (name === "runtime") return "runtime";
	if (name.startsWith("std/")) return "std";
	return name.startsWith("src/void2d/kb/") ? "src/void2d/kb" : name.split("/").slice(0, 2).join("/");
};

if (mode === "size") {
	console.log(`${bytes.length} ${gzipBytes(bytes)}`);
} else if (mode === "split") {
	const text = bytes.toString("utf8");
	const marker = /^\/\/ --- Module: (.+) ---$/gm;
	const starts = [{ name: "runtime", at: 0 }];
	for (const found of text.matchAll(marker)) starts.push({ name: found[1], at: found.index });
	const share = new Map();
	let previous = 0;
	starts.forEach((start, index) => {
		const end = index + 1 < starts.length ? starts[index + 1].at : text.length;
		const prefix = gzipBytes(Buffer.from(text.slice(0, end), "utf8"));
		const key = directory(start.name);
		const row = share.get(key) ?? { gzip: 0, raw: 0, modules: 0 };
		row.gzip += prefix - previous;
		row.raw += Buffer.byteLength(text.slice(start.at, end), "utf8");
		row.modules += start.name === "runtime" ? 0 : 1;
		share.set(key, row);
		previous = prefix;
	});
	for (const [key, row] of [...share].sort((a, b) => b[1].gzip - a[1].gzip))
		console.log(`${key} gzip ${row.gzip} raw ${row.raw} modules ${row.modules}`);
} else if (mode === "wasm-split") {
	// The wasm twin of split, over `llvm-nm --print-size` of a --profiling-funcs build: a function's
	// msc name carries its module (srcZvoid2dZbatcherOms is src/void2d/batcher.ms, U4C an escaped L),
	// so its code bytes go to the same directory split counts; C, libc and emscripten code is runtime,
	// and data segments are data. Raw bytes only: wasm gzips as one stream.
	const moduleOf = (symbol) => {
		const found = symbol.match(/(S?)((?:[A-Za-z0-9]+Z)+[A-Za-z0-9]+)O(ms|jms|cms|wms)/);
		if (found === null) return "runtime";
		const path = found[2].replace(/U([0-9A-F]{2})/g, (_, hex) => String.fromCharCode(parseInt(hex, 16))).replaceAll("Z", "/");
		return path + "." + found[3];
	};
	const share = new Map();
	for (const line of bytes.toString("utf8").split(/\r?\n/)) {
		const found = line.match(/^[0-9a-f]+ ([0-9a-f]+) ([A-Za-z]) (.*)$/);
		if (found === null) continue;
		const key = /[dDbBrR]/.test(found[2]) ? "data" : directory(moduleOf(found[3]));
		const row = share.get(key) ?? { raw: 0, symbols: 0 };
		row.raw += parseInt(found[1], 16);
		row.symbols += 1;
		share.set(key, row);
	}
	for (const [key, row] of [...share].sort((a, b) => b[1].raw - a[1].raw))
		console.log(`${key} raw ${row.raw} symbols ${row.symbols}`);
} else {
	throw new Error("usage: node scripts/jsBudgetMeasure.mjs size|split <bundle> | wasm-split <llvm-nm --print-size output>");
}
