import { sha256 } from "std/crypto/sha256";
import { ensureDir, exists, readDir, remove, writeFile } from "std/fs";
import { execFileResult } from "std/process";

class DxbcStage {
	key: string = "";
	path: string = "";
	compiled: boolean = false;
	error: string = "";
}

// The flags src/webgpu/d3d11/d3d11.c passes D3DCompile, in fxc's spelling; keep them in step.
function fxcFlags(): string[] { return ["-Zpc", "-O3"]; }

export function dxbcKey(profile: string, entry: string, code: string): string {
	const keyed = profile + " " + entry + " " + fxcFlags().join(" ") + "\n" + code;
	return sha256(keyed.asBytes()).toHex();
}

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
	const _dir = ensureDir(fresh);
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
		stage.error = "fxc " + profile + " refused " + source + ":\n" + run.output +
			run.errorOutput;
		return stage;
	}
	const _source = remove(source);
	stage.path = made;
	stage.compiled = true;
	return stage;
}

function versionKey(version: string): string {
	let key = "";
	for (const part of version.split(".")) { key += "0000000000".slice(part.length) + part + "."; }
	return key;
}

// The path `-d:fxc=` names, else the newest Windows Kit's; empty when this host has none. $FXC and
// PATH wait on card 2026-10-26-macro-vm-extern-env-process, because a macro cannot read them.
export function findFxc(named: string): string {
	if (named != "") { return exists(named) ? named : ""; }
	const kits = "C:/Program Files (x86)/Windows Kits/10/bin";
	let best = "";
	let bestKey = "";
	for (const entry of readDir(kits)) {
		const version = entry.replace("/", "");
		const candidate = kits + "/" + version + "/x64/fxc.exe";
		if (versionKey(version) > bestKey && exists(candidate)) {
			best = candidate;
			bestKey = versionKey(version);
		}
	}
	return best;
}
