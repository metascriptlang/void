import { sha256 } from "std/crypto/sha256";
import { exists, mkdir, remove, writeFile } from "std/fs";
import { execFileResult } from "std/process";

class DxbcStage {
	key: string = "";
	path: string = "";
	compiled: boolean = false;
	error: string = "";
}

// The flags src/webgpu/d3d11/d3d11.c passes D3DCompile, in fxc's spelling; keep them in step.
function fxcFlags(): string[] { return ["-Zpc", "-O3"]; }

function dxbcKey(profile: string, entry: string, code: string): string {
	const keyed = profile + " " + entry + " " + fxcFlags().join(" ") + "\n" + code;
	return sha256(keyed.asBytes()).toHex();
}

// The blob of a stage: `<cache>/<key>.dxbc`, else `<fresh>/<key>.dxbc`, else fxc compiles it into
// `<fresh>`; with no fxc the path stays empty and the stage has none. A refused compile leaves the
// source in `<fresh>` and its output in `error`.
export function dxbcStage(
	cache: string,
	fresh: string,
	fxc: string,
	profile: string,
	entry: string,
	code: string,
): DxbcStage {
	const stage = new DxbcStage();
	stage.key = dxbcKey(profile, entry, code);
	const cached = cache + "/" + stage.key + ".dxbc";
	if (exists(cached)) {
		stage.path = cached;
		return stage;
	}
	const made = fresh + "/" + stage.key + ".dxbc";
	if (exists(made)) {
		stage.path = made;
		return stage;
	}
	if (fxc == "") { return stage; }
	const _dir = mkdir(fresh);
	const source = fresh + "/" + stage.key + ".hlsl";
	if (!writeFile(source, code).ok) {
		stage.error = "cannot write " + source;
		return stage;
	}
	const run = execFileResult(
		fxc,
		["-nologo", "-T", profile, "-E", entry].concat(fxcFlags()).concat(["-Fo", made, source]),
	);
	if (!run.started || run.exitCode != 0) {
		stage.error = "fxc " + profile + " refused " + source + ":\n" + run.output + run.errorOutput;
		return stage;
	}
	const _source = remove(source);
	stage.path = made;
	stage.compiled = true;
	return stage;
}
