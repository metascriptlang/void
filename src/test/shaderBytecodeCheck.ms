// shaderModule precompiles each HLSL stage to DXBC at msc compile time, keyed by its source, and
// the descriptor then carries the blob and no text. A Windows host without fxc keeps the text.

import { byteAt, byteLength } from "std/core/string/bytes";
import { readFileBytes } from "std/fs";
import { glslIr, glslLinkedIr } from "../shader/emit";
import { programModule, programSource } from "../shader/descriptor";
import { dxbcKey } from "../shader/dxbcCache";
import { ShaderTarget } from "../shader/layout";
import { shaderModule, stageBlob } from "../shader/program";
import {
	Sampler,
	Texture2d,
	Vec2f,
	Vec4f,
	binding,
	builtin,
	textureSample,
	vec4f,
} from "../shader/std";

struct BlobInput {
	position: Vec2f;
	uv: Vec2f;
}

struct BlobVarying {
	@builtin(position) position: Vec4f;
	uv: Vec2f;
}

struct BlobFragment {
	uv: Vec2f;
}

struct BlobTint {
	tint: Vec4f;
}

struct BlobBindings {
	@binding(1) tintParams: BlobTint;
	@binding(0) picture: Texture2d;
	@binding(0) smoothing: Sampler;
}

function blobVs(input: BlobInput): BlobVarying {
	return { position: vec4f(input.position.x, input.position.y, 0.0, 1.0), uv: input.uv };
}

function blobFs(input: BlobFragment, b: BlobBindings): Vec4f {
	return textureSample(b.picture, b.smoothing, input.uv) * b.tintParams.tint;
}

struct FlatVarying {
	@builtin(position) position: Vec4f;
}

function flatVs(input: BlobInput): FlatVarying {
	return { position: vec4f(input.position.x, input.position.y, 0.5, 1.0) };
}

function flatFs(): Vec4f {
	return vec4f(0.25, 0.5, 0.75, 1.0);
}

shaderModule(blob, blobVs, blobFs);
shaderModule(flat, flatVs, flatFs);

when (windows) {
	function cachedBlob(profile: string, entry: string, code: string): uint8[] {
		const name = dxbcKey(profile, entry, code) + ".dxbc";
		const tracked = readFileBytes("shaders/dxbc/" + name);
		if (tracked.ok) { return tracked.value; }
		const made = readFileBytes("out/shaders/dxbc/" + name);
		return made.ok ? made.value : [];
	}

	function sameBytes(bytecode: Readonly<Vec<uint8>>, file: uint8[]): boolean {
		if (file.length == 0 || bytecode.length != file.length) { return false; }
		for (let i = 0; i < bytecode.length; i++) {
			if (bytecode[i] != file[i]) { return false; }
		}
		return true;
	}

	test "a shaderModule on the HLSL target carries DXBC for each stage and no text" {
		for (const module of [blobModule, flatModule]) {
			assert module.vertexCode == "" && module.vertexBytecode.length > 0;
			assert module.fragmentCode == "" && module.fragmentBytecode.length > 0;
		}
	}

	test "the descriptor's bytecode is the cache file keyed by the stage's printed source" {
		const printed = programModule(glslIr(blobVs), glslLinkedIr(blobFs, blobVs), []);
		assert printed.ok;
		const source = programSource(printed.value, ShaderTarget.Hlsl5);
		assert source.ok;
		const s = source.value;
		const vertex = cachedBlob("vs_5_0", s.entryPoint, s.vertexCode);
		const fragment = cachedBlob("ps_5_0", s.entryPoint, s.fragmentCode);
		assert sameBytes(blobModule.vertexBytecode, vertex);
		assert sameBytes(blobModule.fragmentBytecode, fragment);
		assert stageBlob("hlsl5", "vertex", s.vertexCode, s.entryPoint, "").path != "";
	}

	test "a stage with no blob and no tool is not an error, and a Metal stage names xcrun" {
		const metal = stageBlob("metal_macos", "vertex", "// no such stage", "main0", "");
		assert metal.path == "" && metal.error == "" && metal.missing == "xcrun -sdk macosx metal";
	}
}

test "a stage with no blob and no fxc keeps its text and names the tool" {
	const found = stageBlob("hlsl5", "fragment", "// no such stage", "main", "");
	assert found.path == "" && found.error == "" && found.missing == "fxc";
}

test "a language with no bytecode form has no blob and misses no tool" {
	const found = stageBlob("wgsl", "vertex", "// no such stage", "main", "");
	assert found.path == "" && found.error == "" && found.missing == "";
}
