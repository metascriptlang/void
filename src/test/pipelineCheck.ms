import {
	RenderState,
	Face,
	Compare,
	Blend,
	Operation,
	BlendMode,
	COLOR_MASK_ALL,
} from "../gpu/state";
import {
	Program,
	VertexLayout,
	doorProgram,
	doorLayout,
	ProgramKey,
} from "../void3d/gpu3d";
import { PixelFormat, LoadAction, StoreAction, contextGeneration } from "../gpu/door";
import {
	RenderTarget,
	ColorAttachment,
	TargetLayout,
	NO_DEPTH,
	SWAPCHAIN_LAYOUT,
	layoutOf,
} from "../gpu/target";
import {
	PipelineKey,
	PipelineCache,
	pipelineKey,
	describePipeline,
	releasePipelines,
	closePipelines,
	IndexType,
} from "../gpu/pipeline";
import { UniformBlock, NO_UNIFORMS } from "../void3d/material";
import { DrawContext, reserveUniforms, writeUniforms } from "../void3d/draw";
import { UniformError } from "../void3d/uniformPool";
import { Vec4 } from "../math/math3d";

// The campfire scene pass: unculled, depth-tested with LessEqual.
function sceneState(): RenderState {
	return RenderState.defaults().withCulling(Face.None).withDepth(true, Compare.LessEqual);
}

function target(format: PixelFormat): RenderTarget {
	return RenderTarget.unallocated(format, true);
}

function sceneLayout(): TargetLayout {
	const black: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 0.0 };
	const colors: Vec<ColorAttachment> = [
		target(PixelFormat.Rgba8).asColor(LoadAction.Clear, black),
		target(PixelFormat.Rgba8).asColor(LoadAction.Clear, black),
	];
	const depth: RenderTarget = target(PixelFormat.Depth);
	return layoutOf(colors, depth.asDepth(LoadAction.Clear, 1.0, StoreAction.DontCare));
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

function litKey(indexed: boolean, state: RenderState): PipelineKey {
	return pipelineKey(
		doorProgram(ProgramKey.of(Program.Lit)), doorLayout(VertexLayout.Lit), indexed, state,
		sceneLayout(),
	);
}

function billboardKey(state: RenderState, targets: TargetLayout): PipelineKey {
	return pipelineKey(
		doorProgram(ProgramKey.of(Program.Billboard)),
		doorLayout(VertexLayout.Billboard),
		NOT_INDEXED,
		state,
		targets,
	);
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
	assert (RenderState.defaults().withColorMask(true, false, true, false).colorMask as uint32) == 5;
	assert (RenderState.defaults().withColorMask(false, false, false, false).colorMask as uint32) == 0;
}

test "render state bits round-trip through fromBits" {
	const base: RenderState = sceneState().withColorMask(false, true, true, true);
	for (const mode of blendModes()) {
		const state: RenderState = base.withBlendMode(mode);
		assert RenderState.fromBits(state.bits()) == state;
	}
	const unwritten: RenderState = RenderState.defaults()
		.withDepth(false, Compare.Always)
		.withCulling(Face.Front);
	assert RenderState.fromBits(unwritten.bits()) == unwritten;
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
	const a: PipelineKey = litKey(NOT_INDEXED, sceneState());
	const b: PipelineKey = litKey(NOT_INDEXED, sceneState());
	assert a == b;
	// Built another way to the same fields.
	const rebuilt: RenderState = RenderState.defaults()
		.withBlendMode(BlendMode.Add)
		.withBlendMode(BlendMode.None)
		.withDepth(true, Compare.LessEqual)
		.withCulling(Face.None);
	assert litKey(NOT_INDEXED, rebuilt) == a;
}

test "a different state, program, layout or target gives a different key" {
	const state: RenderState = sceneState();
	const targets: TargetLayout = sceneLayout();
	const keys: Vec<PipelineKey> = [
		billboardKey(state, targets),
		billboardKey(state.withDepth(false, Compare.LessEqual), targets),
		billboardKey(state.withDepth(true, Compare.Less), targets),
		billboardKey(state.withCulling(Face.Back), targets),
		billboardKey(state.withBlendMode(BlendMode.Alpha), targets),
		billboardKey(state.withColorMask(true, true, true, false), targets),
		pipelineKey(
			doorProgram(ProgramKey.of(Program.Lit)), doorLayout(VertexLayout.Billboard),
			NOT_INDEXED, state, targets,
		),
		pipelineKey(
			doorProgram(ProgramKey.of(Program.Billboard)), doorLayout(VertexLayout.Lit),
			NOT_INDEXED, state, targets,
		),
		pipelineKey(
			doorProgram(ProgramKey.of(Program.Billboard)), doorLayout(VertexLayout.Billboard),
			true, state, targets,
		),
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

// Enough for any descriptor; the exact length lives in door.h, which this directory must not
// import (msc 0.2.53 would compile door.c a second time, see docs/VOID3D.md).
const DESCRIPTOR_ROOM: int32 = 32;

function described(
	layout: VertexLayout,
	indexed: boolean,
	state: RenderState,
	targets: TargetLayout,
): Vec<uint32> {
	let descriptor: Vec<uint32> = new Array(DESCRIPTOR_ROOM);
	for (let i = 0; i < DESCRIPTOR_ROOM; i++) {
		descriptor[i] = 0;
	}
	describePipeline(descriptor, 7, doorLayout(layout), indexed, state, targets);
	return descriptor;
}

function sameWords(a: Readonly<Span<uint32>>, b: Readonly<Span<uint32>>): boolean {
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

test "the indexed flag keys apart from every layout id" {
	const state: RenderState = sceneState();
	const targets: TargetLayout = sceneLayout();
	const plain: PipelineKey = litKey(NOT_INDEXED, state);
	const indexed: PipelineKey = litKey(true, state);
	assert plain.indexType == IndexType.None && indexed.indexType == IndexType.Uint16;
	assert plain != indexed;
	const layoutEight: PipelineKey = pipelineKey(0, 8, NOT_INDEXED, state, targets);
	assert layoutEight.indexType == IndexType.None && layoutEight.layout == 8;
	assert layoutEight != pipelineKey(0, 0, NOT_INDEXED, state, targets);
	assert layoutEight != pipelineKey(0, 0, true, state, targets);
}

test "a program id past sixteen keys apart from a target format" {
	const state: RenderState = sceneState();
	const targets: TargetLayout = sceneLayout();
	const sixteen: PipelineKey = pipelineKey(16, 0, NOT_INDEXED, state, targets);
	assert sixteen.program == 16;
	assert sixteen != pipelineKey(0, 0, NOT_INDEXED, state, targets);
	const depthColor: TargetLayout = { ...targets, color0: PixelFormat.Depth };
	assert sixteen != pipelineKey(0, 0, NOT_INDEXED, state, depthColor);
}

test "a sample count of sixteen keys apart from the render state" {
	const state: RenderState = sceneState();
	const targets: TargetLayout = sceneLayout();
	const sixteen: PipelineKey =
		pipelineKey(0, 0, NOT_INDEXED, state, { ...targets, sampleCount: 16 });
	assert sixteen.targetLayout().sampleCount == 16;
	const culled: PipelineKey = pipelineKey(
		0, 0, NOT_INDEXED, state.withCulling(Face.Back), { ...targets, sampleCount: 0 },
	);
	assert sixteen != culled;
}

test "uniform pool hands out ranges once and refuses to overflow" {
	let context: DrawContext = DrawContext.withUniformCapacity(8);
	const first: UniformBlock = try reserveUniforms(context, 0, 6) catch NO_UNIFORMS;
	assert first.offset == 0 && first.length == 6;
	const second: Result<UniformBlock, UniformError> = reserveUniforms(context, 1, 4);
	assert !second.ok;
	const third: UniformBlock = try reserveUniforms(context, 1, 2) catch NO_UNIFORMS;
	assert third.offset == 6 && third.slot == 1;
	const tooMany: Vec<float32> = [1.0, 2.0, 3.0];
	const refused: Result<int32, UniformError> = writeUniforms(context, third, tooMany);
	assert !refused.ok && refused.error == UniformError.WrongLength;
	const tooFew: Vec<float32> = [5.0];
	assert !writeUniforms(context, third, tooFew).ok;
	const exact: Vec<float32> = [1.0, 2.0];
	assert writeUniforms(context, third, exact).ok;
	assert context.uniforms.values[6] == 1.0 && context.uniforms.values[7] == 2.0;
}


test "a pipeline key decodes back into what built it" {
	const state: RenderState = sceneState()
		.withBlendMode(BlendMode.Alpha)
		.withColorMask(true, true, true, false);
	const key: PipelineKey = pipelineKey(
		doorProgram(ProgramKey.of(Program.Billboard)),
		doorLayout(VertexLayout.Billboard),
		true,
		state,
		sceneLayout(),
	);
	assert key.program == doorProgram(ProgramKey.of(Program.Billboard));
	assert key.layout == doorLayout(VertexLayout.Billboard);
	assert key.indexType == IndexType.Uint16;
	assert key.renderState() == state;
	assert key.targetLayout().formatBits() == sceneLayout().formatBits();
	const screen: TargetLayout = TargetLayout.fromFormatBits(SWAPCHAIN_LAYOUT.formatBits());
	assert screen.formatBits() == SWAPCHAIN_LAYOUT.formatBits();
}

function environmentWith(samples: int32): TargetLayout {
	return {
		color0: PixelFormat.Bgra8,
		color1: PixelFormat.None,
		color2: PixelFormat.None,
		color3: PixelFormat.None,
		depth: PixelFormat.DepthStencil,
		sampleCount: samples,
	};
}

function screenKey(targets: TargetLayout): PipelineKey {
	return pipelineKey(
		doorProgram(ProgramKey.of(Program.Lit)),
		doorLayout(VertexLayout.Lit),
		true,
		sceneState(),
		targets,
	);
}

test "the screen layout resolves to the environment's formats and sample count" {
	const environment: TargetLayout = environmentWith(4);
	assert SWAPCHAIN_LAYOUT.namesEnvironment();
	assert SWAPCHAIN_LAYOUT.resolvedIn(environment) == environment;
	assert !environment.namesEnvironment();
	assert screenKey(SWAPCHAIN_LAYOUT.resolvedIn(environment)) == screenKey(environment);
}

test "screen layouts of two environments that differ only in samples key apart" {
	const single: TargetLayout = SWAPCHAIN_LAYOUT.resolvedIn(environmentWith(1));
	const multi: TargetLayout = SWAPCHAIN_LAYOUT.resolvedIn(environmentWith(4));
	assert screenKey(single) != screenKey(multi);
	assert screenKey(SWAPCHAIN_LAYOUT) != screenKey(single);
}

test "a layout that names its formats is left as it is" {
	assert !sceneLayout().namesEnvironment();
	assert sceneLayout().resolvedIn(environmentWith(4)) == sceneLayout();
	const halfNamed: TargetLayout = { ...sceneLayout(), depth: PixelFormat.Default, sampleCount: 0 };
	assert halfNamed.namesEnvironment();
	const resolved: TargetLayout = halfNamed.resolvedIn(environmentWith(4));
	assert resolved.color0 == PixelFormat.Rgba8 && resolved.color1 == PixelFormat.Rgba8;
	assert resolved.depth == PixelFormat.DepthStencil && resolved.sampleCount == 4;
}

test "releasing a cache of another GPU context drops its handles without destroying them" {
	const cache: PipelineCache = PipelineCache.empty();
	cache.entries.push({ key: litKey(false, sceneState()), pipeline: 7 });
	cache.shaders.push(9);
	cache.generation = contextGeneration() + 1;
	releasePipelines(cache);
	assert cache.entries[0].pipeline == 0 && cache.shaders[0] == 0;
}

test "closing a cache of another GPU context empties it and answers false after" {
	const cache: PipelineCache = PipelineCache.empty();
	cache.entries.push({ key: litKey(false, sceneState()), pipeline: 7 });
	cache.shaders.push(9);
	cache.blockSlots.push(1);
	cache.generation = contextGeneration() + 1;
	assert !cache.isClosed();
	assert cache.contains(litKey(false, sceneState())) && cache.declaresBlock(0, 0);
	closePipelines(cache);
	assert cache.isClosed();
	assert cache.entries.length == 0 && cache.shaders.length == 0;
	assert cache.blockSlots.length == 0 && cache.descriptor.length == 0;
	assert !cache.contains(litKey(false, sceneState())) && !cache.declaresBlock(0, 0);
}
