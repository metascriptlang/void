import { readFileSync } from "node:fs";
import { gzipSync } from "node:zlib";

const [mode, bundlePath] = process.argv.slice(2);
const bytes = readFileSync(bundlePath);
const gzipBytes = (buffer) => gzipSync(buffer, { level: 9 }).length;

if (mode === "size") {
	console.log(`${bytes.length} ${gzipBytes(bytes)}`);
} else if (mode === "split") {
	const text = bytes.toString("utf8");
	const marker = /^\/\/ --- Module: (.+) ---$/gm;
	const starts = [{ name: "runtime", at: 0 }];
	for (const found of text.matchAll(marker)) starts.push({ name: found[1], at: found.index });
	const directory = (name) => {
		if (name === "runtime") return "runtime";
		if (name.startsWith("std/")) return "std";
		return name.startsWith("src/void2d/kb/") ? "src/void2d/kb" : name.split("/").slice(0, 2).join("/");
	};
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
} else {
	throw new Error("usage: node scripts/jsBudgetMeasure.mjs size|split <bundle>");
}
