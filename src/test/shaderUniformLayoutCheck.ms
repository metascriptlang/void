// A uniform block's host layout has one source: the type the shader lowering reads from the author's
// struct. The helper the host writer uses turns the same struct into the same members, so its
// offsets and size equal the ones the shader's own block reports on every target.

import { programModule } from "../shader/descriptor";
import { glslIr, glslLinkedIr } from "../shader/emit";
import { ShaderModule } from "../shader/ir";
import { ShaderTarget } from "../shader/layout";
import { reflectProgram } from "../shader/reflect";
import { layoutText, uniformLayoutText } from "./shaderUniformLayoutMacros";
import {
	Mat2x2f,
	Mat2x3f,
	Mat2x4f,
	Mat3x2f,
	Mat3x3f,
	Mat3x4f,
	Mat4x2f,
	Mat4x3f,
	Mat4x4f,
	Vec2f,
	Vec3f,
	Vec4f,
	binding,
	builtin,
	vec4f,
} from "../shader/std";

export struct Corner {
	position: Vec2f;
}

export struct Parts {
	@builtin(position) position: Vec4f;
}

export struct Scalars {
	a: float32;
	b: float32;
	c: float32;
}

export struct Packed {
	a: Vec2f;
	b: Vec3f;
	c: float32;
	d: Vec4f;
	e: Vec3f;
	f: Vec2f;
	g: float32;
}

export struct Matrices {
	three: Mat3x3f;
	lead: float32;
	four: Mat4x4f;
	two: Mat2x2f;
	tail: float32;
}

export struct Shapes {
	wide: Mat2x3f;
	tall: Mat4x3f;
	basis: Mat3x4f;
	extra: Mat2x4f;
	narrow: Mat3x2f;
	slim: Mat4x2f;
}

export struct Lights {
	items: Vec4f[4];
	count: float32;
}

export struct Views {
	items: Mat4x4f[2];
	time: float32;
}

export struct ScalarBindings { @binding(0) scalars: Scalars; }
export struct PackedBindings { @binding(0) packed: Packed; }
export struct MatrixBindings { @binding(0) matrices: Matrices; }
export struct ShapeBindings { @binding(0) shapes: Shapes; }
export struct LightBindings { @binding(0) light: Lights; }
export struct ViewBindings { @binding(0) view: Views; }

export function cornerVs(input: Corner): Parts {
	return { position: vec4f(input.position.x, input.position.y, 0.0, 1.0) };
}

export function scalarFs(input: Parts, b: ScalarBindings): Vec4f {
	return vec4f(b.scalars.a, b.scalars.b, b.scalars.c, 1.0);
}

export function packedFs(input: Parts, b: PackedBindings): Vec4f {
	return vec4f(b.packed.a.x + b.packed.b.z, b.packed.c, b.packed.d.w + b.packed.e.x, b.packed.f.y + b.packed.g);
}

export function matrixFs(input: Parts, b: MatrixBindings): Vec4f {
	return b.matrices.four.columns[3] + vec4f(b.matrices.three.columns[2].z, b.matrices.lead,
		b.matrices.two.columns[1].y, b.matrices.tail);
}

export function shapeFs(input: Parts, b: ShapeBindings): Vec4f {
	return b.shapes.extra.columns[1] + b.shapes.basis.columns[2] + vec4f(b.shapes.wide.columns[1].z,
		b.shapes.tall.columns[3].y, b.shapes.narrow.columns[2].y, b.shapes.slim.columns[3].x);
}

export function lightFs(input: Parts, b: LightBindings): Vec4f {
	return b.light.items[3] * b.light.count;
}

export function viewFs(input: Parts, b: ViewBindings): Vec4f {
	return b.view.items[1].columns[3] * b.view.time;
}

const TARGETS = [ShaderTarget.Wgsl, ShaderTarget.Glsl300es, ShaderTarget.Glsl430, ShaderTarget.Hlsl5,
	ShaderTarget.Msl, ShaderTarget.Spirv];

function reflectedSize(m: ShaderModule, target: ShaderTarget): int32 {
	const r = reflectProgram(m, 0, 1, target);
	if (!r.ok) { throw new Error(r.error); }
	if (r.value.bindings.length != 1) { throw new Error("the probe shader reflects one binding"); }
	return r.value.bindings[0].size;
}

function mismatch(m: ShaderModule, helper: string): string {
	if (m.resources.length != 1) { return "the probe shader has " + String(m.resources.length) + " resources"; }
	const own = layoutText(m, 0);
	if (own != helper) { return "shader " + own + " | helper " + helper; }
	const size = reflectedSize(m, ShaderTarget.Wgsl);
	if (!own.endsWith("size " + String(size))) { return "reflected size " + String(size) + " | " + own; }
	for (const target of TARGETS) {
		if (reflectedSize(m, target) != size) { return "target " + target.toString() + " reflects another size"; }
	}
	return "";
}

function programOf(m: Result<ShaderModule, string>): ShaderModule {
	if (!m.ok) { throw new Error(m.error); }
	return m.value;
}

test "scalars pack four bytes apart" {
	const m = programOf(programModule(glslIr(cornerVs), glslLinkedIr(scalarFs, cornerVs), []));
	assert uniformLayoutText<Scalars>() == "a:f32@0; b:f32@4; c:f32@8; size 16";
	assert mismatch(m, uniformLayoutText<Scalars>()) == "";
}

test "a vec3 takes a float into its last lane, a vec2 sits on eight" {
	const m = programOf(programModule(glslIr(cornerVs), glslLinkedIr(packedFs, cornerVs), []));
	assert uniformLayoutText<Packed>() ==
		"a:f32x2@0; b:f32x3@16; c:f32@28; d:f32x4@32; e:f32x3@48; f:f32x2@64; g:f32@72; size 80";
	assert mismatch(m, uniformLayoutText<Packed>()) == "";
}

test "a matrix's columns sit on sixteen, a two-row matrix's on eight" {
	const m = programOf(programModule(glslIr(cornerVs), glslLinkedIr(matrixFs, cornerVs), []));
	assert uniformLayoutText<Matrices>() ==
		"three:mat3x3@0; lead:f32@48; four:mat4x4@64; two:mat2x2@128; tail:f32@144; size 160";
	assert mismatch(m, uniformLayoutText<Matrices>()) == "";
}

test "every non-square shape agrees with the shader's block" {
	const m = programOf(programModule(glslIr(cornerVs), glslLinkedIr(shapeFs, cornerVs), []));
	assert mismatch(m, uniformLayoutText<Shapes>()) == "";
}

test "a vec4 array and a mat4 array take sixteen bytes a column" {
	const lights = programOf(programModule(glslIr(cornerVs), glslLinkedIr(lightFs, cornerVs), []));
	assert uniformLayoutText<Lights>() == "items:[f32x4; 4]@0; count:f32@64; size 80";
	assert mismatch(lights, uniformLayoutText<Lights>()) == "";
	const views = programOf(programModule(glslIr(cornerVs), glslLinkedIr(viewFs, cornerVs), []));
	assert uniformLayoutText<Views>() == "items:[mat4x4; 2]@0; time:f32@128; size 144";
	assert mismatch(views, uniformLayoutText<Views>()) == "";
}
