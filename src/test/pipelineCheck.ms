import {
	RenderState,
	Face,
	Compare,
	Blend,
	Operation,
	BlendMode,
	COLOR_MASK_ALL,
} from "../void3d/pass";
import { Program, VertexLayout, IndexType, PixelFormat, LoadAction } from "../void3d/gpu3d";
import {
	RenderTarget,
	ColorAttachment,
	TargetLayout,
	NO_DEPTH,
	SWAPCHAIN_LAYOUT,
	layoutOf,
} from "../void3d/target";
import { PipelineKey, pipelineKey, describePipeline, LAYOUT_LIMIT } from "../void3d/pipelineCache";
import { UniformBlock, NO_UNIFORMS } from "../void3d/material";
import { DrawContext, UniformError, reserveUniforms, writeUniforms } from "../void3d/draw";
import { Vec4 } from "../math/math3d";

// Field by field: `==` on a struct over 24 bytes fails C compile on msc 0.2.53.
function sameState(a: RenderState, b: RenderState): boolean {
	return a.culling == b.culling &&
		a.depthWrite == b.depthWrite &&
		a.depthTest == b.depthTest &&
		a.blendSource == b.blendSource &&
		a.blendDestination == b.blendDestination &&
		a.blendAlphaSource == b.blendAlphaSource &&
		a.blendAlphaDestination == b.blendAlphaDestination &&
		a.blendOperation == b.blendOperation &&
		a.blendAlphaOperation == b.blendAlphaOperation &&
		a.colorMask == b.colorMask;
}

// The campfire scene pass: unculled, depth-tested with LessEqual.
function sceneState(): RenderState {
	return RenderState.defaults().withCulling(Face.None).withDepth(true, Compare.LessEqual);
}

function target(format: PixelFormat): RenderTarget {
	return {
		width: 360,
		height: 800,
		format: format,
		sampled: true,
		image: 1,
		attachment: 2,
		texture: 3,
	};
}

function sceneLayout(): TargetLayout {
	const black: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 0.0 };
	const colors: Vec<ColorAttachment> = [
		target(PixelFormat.Rgba8).asColor(LoadAction.Clear, black),
		target(PixelFormat.Rgba8).asColor(LoadAction.Clear, black),
	];
	return layoutOf(colors, target(PixelFormat.Depth).asDepth(LoadAction.Clear, 1.0));
}

function blendModes(): Vec<BlendMode> {
	return [
		BlendMode.None,
		BlendMode.Alpha,
		BlendMode.Add,
		BlendMode.AlphaAdd,
		BlendMode.SoftAdd,
		BlendMode.Multiply,
		BlendMode.AlphaMultiply,
		BlendMode.Erase,
		BlendMode.Screen,
		BlendMode.Subtract,
		BlendMode.Max,
		BlendMode.Min,
	];
}

const NOT_INDEXED: boolean = false;

function billboardKey(state: RenderState, targets: TargetLayout): uint64 {
	return pipelineKey(Program.Billboard, VertexLayout.Billboard, NOT_INDEXED, state, targets).bits;
}

test "render state defaults match new h3d.mat.Pass" {
	const state: RenderState = RenderState.defaults();
	assert state.culling == Face.Back;
	assert state.depthWrite;
	assert state.depthTest == Compare.Less;
	assert state.blendSource == Blend.One && state.blendDestination == Blend.Zero;
	assert state.blendOperation == Operation.Add && state.blendAlphaOperation == Operation.Add;
	assert state.colorMask == COLOR_MASK_ALL;
}

test "setBlendMode Alpha keeps the source alpha and blends the destination" {
	const state: RenderState = RenderState.defaults().withBlendMode(BlendMode.Alpha);
	assert state.blendSource == Blend.SourceAlpha;
	assert state.blendDestination == Blend.OneMinusSourceAlpha;
	assert state.blendAlphaSource == Blend.One;
	assert state.blendAlphaDestination == Blend.OneMinusSourceAlpha;
	const subtract: RenderState = state.withBlendMode(BlendMode.Subtract);
	assert subtract.blendOperation == Operation.ReverseSubtract;
	assert subtract.withBlendMode(BlendMode.None).blendOperation == Operation.Add;
}

test "color mask packs r g b a as bits 1 2 4 8" {
	assert RenderState.defaults().withColorMask(true, false, true, false).colorMask == 5;
	assert RenderState.defaults().withColorMask(false, false, false, false).colorMask == 0;
}

test "render state bits round-trip through fromBits" {
	const base: RenderState = sceneState().withColorMask(false, true, true, true);
	for (const mode of blendModes()) {
		const state: RenderState = base.withBlendMode(mode);
		assert sameState(RenderState.fromBits(state.bits()), state);
	}
	const unwritten: RenderState = RenderState.defaults()
		.withDepth(false, Compare.Always)
		.withCulling(Face.Front);
	assert sameState(RenderState.fromBits(unwritten.bits()), unwritten);
}

test "every blend mode packs to different bits" {
	const modes: Vec<BlendMode> = blendModes();
	for (let i = 0; i < (modes.length as int32); i++) {
		for (let j = i + 1; j < (modes.length as int32); j++) {
			const a: uint32 = RenderState.defaults().withBlendMode(modes[i]).bits();
			const b: uint32 = RenderState.defaults().withBlendMode(modes[j]).bits();
			assert a != b;
		}
	}
}

test "same pipeline inputs give the same key" {
	const a: uint64 = pipelineKey(Program.Lit, VertexLayout.Lit, NOT_INDEXED, sceneState(), sceneLayout()).bits;
	const b: uint64 = pipelineKey(Program.Lit, VertexLayout.Lit, NOT_INDEXED, sceneState(), sceneLayout()).bits;
	assert a == b;
	// Built another way to the same fields.
	const rebuilt: RenderState = RenderState.defaults()
		.withBlendMode(BlendMode.Add)
		.withBlendMode(BlendMode.None)
		.withDepth(true, Compare.LessEqual)
		.withCulling(Face.None);
	assert pipelineKey(Program.Lit, VertexLayout.Lit, NOT_INDEXED, rebuilt, sceneLayout()).bits == a;
}

test "a different state, program, layout or target gives a different key" {
	const state: RenderState = sceneState();
	const targets: TargetLayout = sceneLayout();
	const keys: Vec<uint64> = [
		billboardKey(state, targets),
		billboardKey(state.withDepth(false, Compare.LessEqual), targets),
		billboardKey(state.withDepth(true, Compare.Less), targets),
		billboardKey(state.withCulling(Face.Back), targets),
		billboardKey(state.withBlendMode(BlendMode.Alpha), targets),
		billboardKey(state.withColorMask(true, true, true, false), targets),
		pipelineKey(Program.Lit, VertexLayout.Billboard, NOT_INDEXED, state, targets).bits,
		pipelineKey(Program.Billboard, VertexLayout.Lit, NOT_INDEXED, state, targets).bits,
		pipelineKey(Program.Billboard, VertexLayout.Billboard, true, state, targets).bits,
		billboardKey(state, { ...targets, depth: PixelFormat.None }),
		billboardKey(state, { ...targets, color1: PixelFormat.None }),
		billboardKey(state, { ...targets, sampleCount: 4 }),
		billboardKey(state, SWAPCHAIN_LAYOUT),
	];
	for (let i = 0; i < (keys.length as int32); i++) {
		for (let j = i + 1; j < (keys.length as int32); j++) {
			assert keys[i] != keys[j];
		}
	}
}

test "target layout of a pass reads its attachment formats" {
	const layout: TargetLayout = sceneLayout();
	assert layout.color0 == PixelFormat.Rgba8 && layout.color1 == PixelFormat.Rgba8;
	assert layout.color2 == PixelFormat.None && layout.color3 == PixelFormat.None;
	assert layout.depth == PixelFormat.Depth;
	assert layout.sampleCount == 1;
	const unused: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 0.0 };
	const post: Vec<ColorAttachment> = [
		target(PixelFormat.Rgba8).asColor(LoadAction.DontCare, unused),
	];
	assert layoutOf(post, NO_DEPTH).depth == PixelFormat.None;
	assert layoutOf(post, NO_DEPTH).formatBits() != layout.formatBits();
}

// Enough for any descriptor; the exact length lives in gpu3d.h, which this directory must not
// import (msc 0.2.53 would compile gpu3d.c a second time, see docs/VOID3D.md).
const DESCRIPTOR_ROOM: int32 = 32;

function described(
	layout: VertexLayout,
	indexed: boolean,
	state: RenderState,
	targets: TargetLayout,
): Vec<uint32> {
	const descriptor: Vec<uint32> = new Array(DESCRIPTOR_ROOM);
	for (let i = 0; i < DESCRIPTOR_ROOM; i++) {
		descriptor[i] = 0;
	}
	describePipeline(descriptor, 7, layout, indexed, state, targets);
	return descriptor;
}

function sameWords(a: Span<uint32>, b: Span<uint32>): boolean {
	for (let i = 0; i < (a.length as int32); i++) {
		if (a[i] != b[i]) { return false; }
	}
	return true;
}

test "pipeline descriptor follows the key" {
	const rebuilt: RenderState = RenderState.defaults()
		.withBlendMode(BlendMode.Alpha)
		.withBlendMode(BlendMode.None)
		.withCulling(Face.None)
		.withDepth(true, Compare.LessEqual);
	const a: Vec<uint32> = described(VertexLayout.Lit, NOT_INDEXED, sceneState(), sceneLayout());
	const b: Vec<uint32> = described(VertexLayout.Lit, NOT_INDEXED, rebuilt, sceneLayout());
	assert sameWords(a, b);
	assert a[0] == 7;
	const added: RenderState = sceneState().withBlendMode(BlendMode.Add);
	assert !sameWords(a, described(VertexLayout.Lit, NOT_INDEXED, added, sceneLayout()));
	const unmasked: RenderState = sceneState().withColorMask(true, true, true, false);
	assert !sameWords(a, described(VertexLayout.Lit, NOT_INDEXED, unmasked, sceneLayout()));
	assert !sameWords(a, described(VertexLayout.Lit, NOT_INDEXED, sceneState(), SWAPCHAIN_LAYOUT));
}

test "the descriptor carries the index type, and only the index type, for an indexed mesh" {
	const plain: Vec<uint32> = described(VertexLayout.Lit, NOT_INDEXED, sceneState(), sceneLayout());
	const indexed: Vec<uint32> = described(VertexLayout.Lit, true, sceneState(), sceneLayout());
	assert !sameWords(plain, indexed);
	let differing: int32 = 0;
	for (let i = 0; i < DESCRIPTOR_ROOM; i++) {
		if (plain[i] != indexed[i]) { differing = differing + 1; }
	}
	assert differing == 1;
}

// The key packs the vertex layout in three bits and the indexed flag in the fourth; one more
// layout than this and it needs a second word (pipelineCache.ms).
test "every vertex layout still fits the three bits the key gives it" {
	assert (VertexLayout.Lit as int32) < LAYOUT_LIMIT;
	assert (VertexLayout.Billboard as int32) < LAYOUT_LIMIT;
	assert (VertexLayout.Fullscreen as int32) < LAYOUT_LIMIT;
}

test "uniform pool hands out ranges once and refuses to overflow" {
	let context: DrawContext = DrawContext.withUniformCapacity(8);
	const first: UniformBlock = try reserveUniforms(context, 0, 6) catch NO_UNIFORMS;
	assert first.offset == 0 && first.length == 6;
	const second: Result<UniformBlock, UniformError> = reserveUniforms(context, 1, 4);
	assert !second.ok;
	const third: UniformBlock = try reserveUniforms(context, 1, 2) catch NO_UNIFORMS;
	assert third.offset == 6 && third.slot == 1;
	const values: Vec<float32> = [1.0, 2.0, 3.0];
	writeUniforms(context, third, values);
	assert context.uniforms[6] == 1.0 && context.uniforms[7] == 2.0;
}

test "render state and target layout print one readable line" {
	const expected: string = "culling=Back depthWrite=true depthTest=Less blend=One,Zero" +
		" alphaBlend=One,Zero operation=Add,Add colorMask=15";
	assert RenderState.defaults().toString() == expected;
	assert sceneLayout().toString() == "colors=Rgba8,Rgba8 depth=Depth sampleCount=1";
	assert SWAPCHAIN_LAYOUT.toString() == "colors=Default depth=Default sampleCount=0";
}

test "a pipeline key decodes back into what built it" {
	const state: RenderState = sceneState()
		.withBlendMode(BlendMode.Alpha)
		.withColorMask(true, true, true, false);
	const key: PipelineKey = pipelineKey(
		Program.Billboard,
		VertexLayout.Billboard,
		true,
		state,
		sceneLayout(),
	);
	assert key.program() == Program.Billboard;
	assert key.vertexLayout() == VertexLayout.Billboard;
	assert key.isIndexed();
	assert key.indexType() == IndexType.Uint16;
	assert sameState(key.renderState(), state);
	assert key.targetLayout().formatBits() == sceneLayout().formatBits();
	const screen: TargetLayout = TargetLayout.fromFormatBits(SWAPCHAIN_LAYOUT.formatBits());
	assert screen.toString() == SWAPCHAIN_LAYOUT.toString();
	const text: string = key.toString();
	assert text.indexOf("program=Billboard layout=Billboard indexType=Uint16 colors=Rgba8,Rgba8") == 0;
	assert text.indexOf("blend=SourceAlpha,OneMinusSourceAlpha") > 0;
	assert text.indexOf("colorMask=7") > 0;
}
