// The IR path's reflection, lowered again in this binary, equals the committed descriptors, field
// by field and in any binding order, for a sample of programs on the target this binary is built
// for.

import { glslIr, glslLinkedIr } from "../shader/emit";
import { programModule, programSource } from "../shader/descriptor";
import { irErrors } from "../shader/ir";
import { irFromText, irText } from "../shader/irText";
import { ShaderTarget } from "../shader/layout";
import { Reflection } from "../shader/reflect";
import { GPUShaderModuleDescriptor } from "../webgpu/types.ms";
import {
	billboardFs,
	billboardVs,
	copyFs,
	litFs,
	litTexturedFs,
	litTexturedVs,
	litVs,
	particleVisualVs,
	shadowLitTexturedFs,
} from "../void3d/shader3d";
import { fullscreenVs, outlineMixFs } from "../void3d/post3d";
import { pixelArtLitTexturedFs, pixelArtLitTexturedVs } from "../void3d/pixelArt3d";
import { blurFs, blurVs, uiFs, uiVs } from "../void2d/shader2d";
import {
	copyShaderModule,
	litShaderModule,
	litTexturedDissolveEmissiveShaderModule,
	outlineMixShaderModule,
	particleVisualCutoutShaderModule,
	pixelArtLitTexturedCutoutShadowedShaderModule,
	shadowLitTexturedDissolveShaderModule,
	skinLitTexturedEmissiveNormalMapShadowedNormalMrtShaderModule,
} from "../void3d/programModules";
import { blurShaderModule, uiShaderModule } from "../void2d/shader2dModules";

when (webgpu) {
	function builtTarget(): ShaderTarget { return ShaderTarget.Wgsl; }
} else when (webgl2 || android || (linux && voidGles3)) {
	function builtTarget(): ShaderTarget { return ShaderTarget.Glsl300es; }
} else when (ios || macos) {
	function builtTarget(): ShaderTarget { return ShaderTarget.Msl; }
} else when (voidGlCore || linux) {
	function builtTarget(): ShaderTarget { return ShaderTarget.Glsl430; }
} else {
	function builtTarget(): ShaderTarget { return ShaderTarget.Hlsl5; }
}

const LIT_VS = glslIr(litVs);
const LIT_TEXTURED_VS = glslIr(litTexturedVs);
const LIT_TEXTURED_FS = glslLinkedIr(litTexturedFs, litTexturedVs);
const FULLSCREEN_VS = glslIr(fullscreenVs);

function mismatches(reflected: Reflection, committed: GPUShaderModuleDescriptor): string[] {
	let out: string[] = [];
	let committedCount = 0;
	for (let i = 0; i < 24; i++) {
		const kind: string = committed.bindings[i].kind;
		if (kind != "") { committedCount++; }
	}
	if (committedCount != reflected.bindings.length) {
		out.push(String(reflected.bindings.length) + " bindings against " + String(committedCount));
	}
	for (const r of reflected.bindings) {
		const at = "binding " + String(r.group) + "/" + String(r.binding) + " ";
		let found = -1;
		for (let i = 0; i < committedCount; i++) {
			const b = committed.bindings[i];
			if (b.group == r.group && b.binding == r.binding) { found = i; }
		}
		if (found < 0) {
			out.push(at + "is not in the committed descriptor");
			continue;
		}
		const c = committed.bindings[found];
		const ckind: string = c.kind;
		const rkind: string = r.kind;
		const rsample: string = r.sampleType;
		const csample: string = c.sampleType;
		const rsampler: string = r.samplerType;
		const csampler: string = c.samplerType;
		const rname = r.nativeName ?? "";
		const cname = c.nativeName ?? "";
		if (rkind != ckind || r.visibility != c.visibility) {
			out.push(at + rkind + " " + String(r.visibility) + " against " + ckind + " " +
				String(c.visibility));
		}
		if (r.size != c.size) { out.push(at + "size " + String(r.size) + " against " + String(c.size)); }
		if (rsample != csample || rsampler != csampler) { out.push(at + "sample or sampler type"); }
		if (r.nativeSlot != c.nativeSlot) {
			out.push(at + "native slot " + String(r.nativeSlot) + " against " + String(c.nativeSlot));
		}
		if (rname != cname) { out.push(at + "native name " + rname + " against " + cname); }
		if (r.textureBinding != c.textureBinding) { out.push(at + "texture binding"); }
	}
	for (let i = 0; i < 16; i++) {
		const c = committed.attributes[i];
		if (i >= reflected.attributes.length) {
			if (c.location != 0 || c.semanticIndex != 0 || c.nativeName !== null && c.nativeName != "") {
				out.push("attribute " + String(i) + ": the IR has none");
			}
			continue;
		}
		const r = reflected.attributes[i];
		if (r.location != c.location || r.semanticIndex != c.semanticIndex ||
			(r.nativeName ?? "") != (c.nativeName ?? "")) {
			out.push("attribute " + String(i) + " differs");
		}
	}
	return out;
}

function matched(vertex: string, fragment: string, features: string[],
	committed: GPUShaderModuleDescriptor): string {
	const m = programModule(vertex, fragment, features);
	if (!m.ok) { return m.error; }
	const s = programSource(m.value, builtTarget());
	if (!s.ok) { return s.error; }
	if (s.value.reflection.attributes.length == 0) { return "the IR reflects no attribute"; }
	const found = mismatches(s.value.reflection, committed).join("; ");
	if (found != "") { console.error((committed.label ?? "") + ": " + found); }
	return found;
}

test "a lowered stage reads back as the module it was" {
	const m = irFromText(LIT_TEXTURED_FS);
	assert m.ok;
	if (m.ok) {
		assert irErrors(m.value).length == 0;
		assert irText(m.value) == LIT_TEXTURED_FS;
	}
}

test "the plain lit program reflects as shdc's" {
	assert matched(LIT_VS, glslLinkedIr(litFs, litVs), [], litShaderModule()) == "";
}

test "a textured key with every texture reflects as shdc's" {
	assert matched(LIT_TEXTURED_VS, LIT_TEXTURED_FS,
		["EMISSIVE", "NORMAL_MAP", "SHADOWED", "NORMAL_MRT", "SKINNED"],
		skinLitTexturedEmissiveNormalMapShadowedNormalMrtShaderModule()) == "";
	assert matched(LIT_TEXTURED_VS, LIT_TEXTURED_FS, ["DISSOLVE", "EMISSIVE"],
		litTexturedDissolveEmissiveShaderModule()) == "";
}

test "a shadow caster reflects as shdc's" {
	assert matched(LIT_TEXTURED_VS, glslLinkedIr(shadowLitTexturedFs, litTexturedVs),
		["DISSOLVE"], shadowLitTexturedDissolveShaderModule()) == "";
}

test "a pixel-art key reflects as shdc's" {
	assert matched(glslIr(pixelArtLitTexturedVs),
		glslLinkedIr(pixelArtLitTexturedFs, pixelArtLitTexturedVs), ["CUTOUT", "SHADOWED"],
		pixelArtLitTexturedCutoutShadowedShaderModule()) == "";
}

test "a fragment over another vertex entry reflects as shdc's" {
	assert matched(glslIr(particleVisualVs), glslLinkedIr(billboardFs, billboardVs), ["CUTOUT"],
		particleVisualCutoutShaderModule()) == "";
}

test "fullscreen passes reflect as shdc's" {
	assert matched(FULLSCREEN_VS, glslIr(copyFs), [], copyShaderModule()) == "";
	assert matched(FULLSCREEN_VS, glslIr(outlineMixFs), [], outlineMixShaderModule()) == "";
}

test "void2d programs reflect as shdc's" {
	assert matched(glslIr(uiVs), glslLinkedIr(uiFs, uiVs), [], uiShaderModule()) == "";
	assert matched(glslIr(blurVs), glslLinkedIr(blurFs, blurVs), [], blurShaderModule()) == "";
}
