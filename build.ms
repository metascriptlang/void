import { defineConfig } from 'std/build';

export default defineConfig({
	root: "src/index.ms",
	build: {
		target: "native",
		outDir: "out",
		outFile: "void",
		optimize: "debug",
	},
});
