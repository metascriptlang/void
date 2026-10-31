import { BuildConfig } from "std/build";

const config: BuildConfig = {
	entry: "./src/examples/main2d.ms",
	fmt: {
		printWidth: 100,
		tabWidth: 4,
		useTabs: true,
	},
	package: {
		name: "@metascript/void",
		version: "0.0.4",
		description: "WebGPU game engine for MetaScript",
		license: "MIT",
		files: ["src/**/*.ms", "src/**/*.wms"],
	},
};

export default config;
