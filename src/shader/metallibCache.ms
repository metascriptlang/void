import { sha256 } from "std/crypto/sha256";
import { ensureDir, exists, writeFile } from "std/fs";
import { execFileResult } from "std/process";

class MetallibStage {
	key: string = "";
	path: string = "";
	compiled: boolean = false;
	error: string = "";
	missing: string = "";
}

// What each Metal language compiles with: the SDK, MSL 2.4 and the OS it starts on (iOS 15.0 as in
// scripts/iosDevice.sh, macOS 12.0; the printed stages compile down to MSL 2.2), and the fast math
// newLibraryWithSource defaults to in src/webgpu/metal/metal.m. A blob built for a newer OS or MSL
// than the device has fails newLibraryWithData.
export function metalFlags(language: string): string[] {
	if (language == "metal_macos") {
		return ["macosx", "-std=macos-metal2.4", "-mmacosx-version-min=12.0", "-ffast-math"];
	}
	if (language == "metal_ios") {
		return ["iphoneos", "-std=ios-metal2.4", "-miphoneos-version-min=15.0", "-ffast-math"];
	}
	if (language == "spirv" || language == "wgsl" || language == "glsl300es" || language == "glsl430" ||
		language == "hlsl5") { return []; }
	console.error("no Metal flags decision for " + language);
	unreachable;
}

// Arrays, not a Map, until card 2026-10-22-macro-extension-call-on-class-field lands.
const SDKS_ASKED: string[] = [];
const SDKS_FOUND: boolean[] = [];

function hasMetalSdk(sdk: string): boolean {
	const asked = SDKS_ASKED.indexOf(sdk);
	if (asked >= 0) { return SDKS_FOUND[asked]; }
	const run = execFileResult("xcrun", ["-sdk", sdk, "-f", "metal"]);
	const found = run.started && run.exitCode == 0;
	SDKS_ASKED.push(sdk);
	SDKS_FOUND.push(found);
	return found;
}

function xcrunMetal(sdk: string, args: string[]): string {
	const run = execFileResult("xcrun", ["-sdk", sdk].concat(args));
	if (!run.started || run.exitCode != 0) {
		return "xcrun " + args.join(" ") + " refused:\n" + run.output + run.errorOutput;
	}
	return "";
}

// A stage with no path and no error is one this host cannot compile: `missing` names the tool.
export function metallibStage(
	cache: string,
	fresh: string,
	language: string,
	entry: string,
	code: string,
): MetallibStage {
	const stage = new MetallibStage();
	const flags = metalFlags(language);
	const sdk = flags[0];
	stage.key = sha256((flags.join(" ") + " " + entry + "\n" + code).asBytes()).toHex();
	const cached = cache + "/" + stage.key + ".metallib";
	if (exists(cached)) {
		stage.path = cached;
		return stage;
	}
	const made = fresh + "/" + stage.key + ".metallib";
	if (exists(made)) {
		stage.path = made;
		return stage;
	}
	if (!hasMetalSdk(sdk)) {
		stage.missing = "xcrun -sdk " + sdk + " metal";
		return stage;
	}
	const _dir = ensureDir(fresh);
	const source = fresh + "/" + stage.key + ".metal";
	const air = fresh + "/" + stage.key + ".air";
	if (!writeFile(source, code).ok) {
		stage.error = "cannot write " + source;
		return stage;
	}
	const compile = xcrunMetal(sdk, ["metal", "-c"].concat(flags.slice(1)).concat(["-o", air, source]));
	if (compile != "") {
		stage.error = compile + " (" + source + ")";
		return stage;
	}
	const link = xcrunMetal(sdk, ["metallib", air, "-o", made]);
	if (link != "") {
		stage.error = link;
		return stage;
	}
	stage.path = made;
	stage.compiled = true;
	return stage;
}
