// Void 2D emitter — turns the tree walk into a display list and nothing else.
//
// Before P1 this file issued sokol calls as the tree was walked: every state change was a
// flush, every Label and Graphics owned an sg_buffer, and a Mask applied a scissor on the
// spot. Now it appends to the two streams in displayList.ms and `end2d()` hands the whole
// frame to `void2dReplay` once. The only sokol calls left here are the ones that are not
// drawing — creating a render target, opening a pass — and those are the host's, not the
// walk's.
//
// A batch ends when the state the replay would have to change ends: a different view, blend,
// sampler or colour pipeline. The reason is recorded with the command, so a T1 snapshot says
// `break: view` rather than leaving a count to be explained.

import {
	void2dSetup, void2dWhiteView, void2dSetDpiScale, void2dFrameBegin,
	void2dGlyphPageView, void2dGlyphUploadCount, void2dGlyphUploadBytes, void2dSetTextGamma,
	void2dReplay, void2dReplayTargets, void2dReplayList, void2dLayoutCheck, void2dSetScopes,
	void2dDrawCallCount, void2dUploadCount, void2dUploadBytes, void2dBuffersAlive,
	void2dVertexBufferBytes, void2dDroppedFrames, void2dGrowthTarget,
	void2dAtlasImagesAlive, void2dFrameEnd, void2dFrameSerial, void2dFailPendingTargets,
	void2dRememberContext, void2dActivateContext,
	void2dScissorMin, void2dScissorMax,
	void2dUiInstanceStride, void2dSpriteInstanceStride,
	void2dPackChannel,
	void2dProgramBase, void2dLayoutBase, void2dSetPipeline,
} from "./batcher.h";
import { void2dGlyphPageCount } from "./glyph.h";
import { beginGlyphFrame, setSdfRegime } from "./labelText";
import { GlyphPageHandle } from "./glyphAtlas";
import { gammaRatios, DEFAULT_TEXT_GAMMA, DEFAULT_TEXT_CONTRAST } from "./textGamma";
import { UiInstance } from "./instance";
import {
	CommandKind, BreakReason,
	COMMAND_FLOATS, EFFECT_FLOATS, VERTEX_FLOATS, NO_EFFECT,
	CMD_KIND, CMD_BREAK, CMD_VERTEX_OFFSET, CMD_VERTEX_COUNT, CMD_VIEW, CMD_VIEW_HIGH, CMD_BLEND,
	CMD_SAMPLER, CMD_EFFECT, CMD_CLIP_X, CMD_CLIP_U_X, CMD_ARG0, CMD_RT_MODE, CMD_CLEAR_R,
	CMD_PIPELINE,
	EFFECT_GRADIENT_META, EFFECT_GRADIENT_PARAMS, EFFECT_GRADIENT_COLOR0,
	EFFECT_GRADIENT_COLOR1, EFFECT_GRADIENT_COLOR2,
	SAMPLER_COUNT, SOURCE_PREMULTIPLIED, samplerIndex,
	DrawContext2D, currentContext, useContext, useDefaultContext, isDefaultContext, uploaded,
	spriteInstanceCount,
	effectField, effectMatrix,
	uiInstanceCount, pushUiInstance, recordUiDraw,
	resetContext, commandCount, targetCommandCount, effectCount, vertexCount, drawCommandCount,
	targetDepth, renderTargetScaleNow, beginTargetList, endTargetList,
	pushVertex as pushVertexRaw, pushEffect, pushGradientEffect, recordDraw, recordClip, recordBlur,
	Pipeline, NO_CLIP, Clip, MaskClip, NO_MASK_CLIP, NO_MASK, PaintIndex, pushMaskClip, maskClipAt,
	ScopeRecord, NO_SCOPE, pushScope, scopeRow, resolveScopes,
	pushSpriteInstance, putSpriteInstance, recordSpriteDraw, pipelineAt, runOffset, commandView,
	Program2D, PROGRAMS_2D, BLEND_MODES, PIPELINE_SLOTS, pipelineWanted, noPipelines,
	pipelineSlot, wantPipelineSlot,
} from "./displayList";
import { Vec2, Color, Tile, Transform2D, Smooth, rgba } from "./types";
import { Mat4 } from "../math/math3d";
import { sqrtf } from "../math/mat4";
import { NO_COLOR_MATRIX } from "./effect";
import {
	PassState, PixelFormat, passState, frameIndex, contextGeneration, endPass, imageAlive, viewAlive,
} from "../gpu/door";
import { doorBeginColorPass } from "../gpu/door.h";
when (voidProfiler) {
	import { profilerSetup, profilerCollect, profilerFrameOpened } from "./frameMarks";
}
import { PipelineCache, pipelineFor } from "../gpu/pipeline";
import { RenderState, Face, Compare, Blend, BlendMode } from "../gpu/state";
import { RenderTarget, TargetLayout, SWAPCHAIN_LAYOUT } from "../gpu/target";
import { fbWidth, fbHeight } from "../sokol/gpu";

const programBase: int32 = void2dProgramBase();
const layoutBase: int32 = void2dLayoutBase();

const OFFSCREEN_LAYOUT: TargetLayout = {
	color0: PixelFormat.Rgba8,
	color1: PixelFormat.None,
	color2: PixelFormat.None,
	color3: PixelFormat.None,
	depth: PixelFormat.None,
	sampleCount: 1,
};

let pipelines: PipelineCache = PipelineCache.empty();
let resolvedPipelines: Vec<boolean> = noPipelines();

function premultipliedSource(factor: Blend): Blend {
	return factor == Blend.SourceAlpha ? Blend.One : factor;
}

export function premultipliedBlend(mode: BlendMode): RenderState {
	const straight: RenderState = RenderState.defaults()
		.withCulling(Face.None)
		.withDepth(false, Compare.Always)
		.withBlendMode(mode);
	if (mode == BlendMode.Erase) { return straight.withBlend(Blend.Zero, Blend.OneMinusSourceAlpha); }
	return {
		...straight,
		blendSource: premultipliedSource(straight.blendSource),
		blendAlphaSource: premultipliedSource(straight.blendAlphaSource),
	};
}

function resolvePipelines(): void {
	const generation: int32 = contextGeneration();
	if (generation != pipelines.generation) {
		for (let slot: int32 = 0; slot < PIPELINE_SLOTS; slot++) { resolvedPipelines[slot] = false; }
	}
	for (let slot: int32 = 0; slot < PIPELINE_SLOTS; slot++) {
		if (resolvedPipelines[slot] || !pipelineWanted(slot)) { continue; }
		const blend: int32 = slot % BLEND_MODES;
		const target: int32 = (slot / BLEND_MODES) % 2;
		const program: int32 = slot / (BLEND_MODES * 2);
		const pipeline: uint32 = pipelineFor(
			pipelines,
			programBase + program,
			layoutBase + program,
			false,
			premultipliedBlend(blend as BlendMode),
			target == 1 ? OFFSCREEN_LAYOUT : SWAPCHAIN_LAYOUT,
		);
		void2dSetPipeline(program, target, blend, pipeline);
		resolvedPipelines[slot] = true;
	}
}



export function preparePipelines(modes: Readonly<Span<BlendMode>>): void {
	for (const mode of modes) {
		for (let program: int32 = 0; program < (Program2D.Blur as int32); program++) {
			wantPipelineSlot(pipelineSlot(program, 0, mode as int32));
			wantPipelineSlot(pipelineSlot(program, 1, mode as int32));
		}
	}
	wantPipelineSlot(pipelineSlot(Program2D.Blur as int32, 1, BlendMode.None as int32));
	resolvePipelines();
}

function pushVertex(
	x: float32, y: float32, u: float32, v: float32,
	r: float32, g: float32, b: float32, a: float32,
): void {
	const ctx: DrawContext2D = currentContext();
	pushVertexRaw(x - ctx.originX, y - ctx.originY, u, v, r, g, b, a);
}


export function drawCallCount(): int32 { return void2dDrawCallCount(); }
export function uploadCount(): int32 { return void2dUploadCount(); }
export function uploadBytes(): int32 { return void2dUploadBytes(); }
export function buffersAlive(): int32 { return void2dBuffersAlive(); }
export function vertexBufferBytes(): int32 { return void2dVertexBufferBytes(); }
export function droppedFrames(): int32 { return void2dDroppedFrames(); }
export function currentRenderScale(): float32 {
	const ctx: DrawContext2D = currentContext();
	const targetScale: float32 = renderTargetScaleNow();
	return targetScale != 0.0 ? targetScale : ctx.frameDpi;
}

export function scissorMinDevice(edge: float32, scale: float32): int32 {
	return void2dScissorMin(edge, scale);
}
export function scissorMaxDevice(edge: float32, scale: float32): int32 {
	return void2dScissorMax(edge, scale);
}

export function atlasImagesAlive(): int32 { return void2dAtlasImagesAlive(); }
export function glyphUploadCount(): int32 { return void2dGlyphUploadCount(); }
export function glyphUploadBytes(): int32 { return void2dGlyphUploadBytes(); }
export function glyphPageView(handle: GlyphPageHandle): uint32 {
	return void2dGlyphPageView(handle as int32);
}
export function glyphPageCount(): int32 { return void2dGlyphPageCount(); }

export function setTextGamma(gamma: float32, contrast: float32): void {
	const r = gammaRatios(gamma);
	void2dSetTextGamma(r.r0, r.r1, r.r2, r.r3, contrast);
}

// `setup2d` registers this as the bridge's commit hook, so `commit()` already runs it and no
// frame has to call it. Exported so a test can close a frame it never committed.
export function frameEnd(): void { void2dFrameEnd(); }

export function growthTarget(have: int32, need: int32): int32 {
	return void2dGrowthTarget(have, need);
}

// Counted from the stream rather than from the GPU, so T1 can read them with no GPU at all.
export function recordedDrawCount(): int32 { return drawCommandCount(); }
export function recordedCommandCount(): int32 { return commandCount(); }
export function recordedVertexCount(): int32 { return vertexCount(); }


function clearEffect(): void {
	const ctx: DrawContext2D = currentContext();
	ctx.curEffect = NO_EFFECT;
	ctx.curMat = NO_COLOR_MATRIX;
	ctx.curAdd = rgba(0.0, 0.0, 0.0, 0.0);
	ctx.curKey = rgba(0.0, 0.0, 0.0, 0.0);
}

function restoreEffect(effect: int32): void {
	if (effect == NO_EFFECT) {
		clearEffect();
		return;
	}
	const ctx: DrawContext2D = currentContext();
	ctx.curEffect = effect;
	ctx.curMat = effectMatrix(effect);
	ctx.curAdd = rgba(
		effectField(effect, 16), effectField(effect, 17),
		effectField(effect, 18), effectField(effect, 19),
	);
	ctx.curKey = rgba(
		effectField(effect, 20), effectField(effect, 21),
		effectField(effect, 22), effectField(effect, 23),
	);
}

// Close the open run as one Draw command. Called when the state changes, when a clip moves,
// and at the end of the bracket — never in the middle of a primitive.
function closeRun(): void {
	const ctx: DrawContext2D = currentContext();
	if (!ctx.runOpen) { return; }
	match (ctx.curPipeline) {
		Pipeline.Sprite => {
			const instances: int32 = spriteInstanceCount() - ctx.runStart;
			if (instances > 0) {
				recordSpriteDraw(
					ctx.runReason, ctx.runStart, instances, ctx.curView, ctx.curBlend, ctx.curSampler,
				);
			}
		},
		Pipeline.Ui => {
			const instances: int32 = uiInstanceCount() - ctx.runStart;
			if (instances > 0) {
				recordUiDraw(
					ctx.runReason, ctx.runStart, instances, ctx.curView, ctx.curBlend, ctx.curSampler,
					ctx.curEffect,
				);
			}
		},
		Pipeline.Vertex => {
			const count: int32 = vertexCount() - ctx.runStart;
			if (count > 0) {
				recordDraw(
					ctx.runReason, ctx.runStart, count, ctx.curView, ctx.curBlend, ctx.curSampler,
					ctx.curEffect,
				);
			}
		},
	}
	ctx.runOpen = false;
}

// Close the open run so the streams are final. Naming the step separates *recording is
// finished* from *the GPU is told about it*: `flushTargets` and `end2d` both start with it,
// and T1 uses it on its own, because a display list is assertable with no GPU at all and the
// replay is the one part that is not.
export function finishRecording(): void {
	closeRun();
}

export function paintIndex(): PaintIndex {
	const ctx: DrawContext2D = currentContext();
	const l: DrawContext2D = currentContext();
	return {
		commands: l.commandTotal,
		effects: l.effectTotal,
		vertices: l.vertexTotal,
		uiInstances: l.uiInstanceTotal,
		spriteInstances: l.spriteInstanceTotal,
		runOpen: ctx.runOpen,
		runStart: ctx.runStart,
		pipeline: ctx.curPipeline,
		reason: ctx.runReason,
		view: ctx.curView,
		blend: ctx.curBlend,
		sampler: ctx.curSampler,
		effect: ctx.curEffect,
		mask: ctx.clipDepth > 0 ? ctx.maskIndices[ctx.clipDepth - 1] : NO_MASK,
		scope: l.scopeNow,
	};
}

export function resumePaint(p: PaintIndex): void {
	const ctx: DrawContext2D = currentContext();
	const l: DrawContext2D = currentContext();
	l.commandTotal = p.commands;
	l.effectTotal = p.effects;
	l.vertexTotal = p.vertices;
	l.uiInstanceTotal = p.uiInstances;
	l.spriteInstanceTotal = p.spriteInstances;
	ctx.runOpen = p.runOpen;
	ctx.runStart = p.runStart;
	ctx.curPipeline = p.pipeline;
	ctx.runReason = p.reason;
	ctx.curView = p.view;
	ctx.curBlend = p.blend;
	ctx.curSampler = p.sampler;
	restoreEffect(p.effect);
	l.scopeNow = p.scope;
	ctx.originX = 0.0;
	ctx.originY = 0.0;
	if (p.mask == NO_MASK) {
		ctx.clipDepth = 0;
		l.clip = NO_CLIP;
		return;
	}
	ctx.clipStack[0] = maskClipAt(p.mask);
	ctx.maskIndices[0] = p.mask;
	ctx.clipDepth = 1;
	l.clip = clipOf(ctx.clipStack[0]);
}

function streamOf(p: PaintIndex, pipeline: Pipeline): int32 {
	return match (pipeline) {
		Pipeline.Sprite => p.spriteInstances,
		Pipeline.Ui => p.uiInstances,
		Pipeline.Vertex => p.vertices,
	};
}

export function continuesLike(old: DrawContext2D, start: PaintIndex, end: PaintIndex): boolean {
	const ctx: DrawContext2D = currentContext();
	if (start.effect != NO_EFFECT || end.effect != NO_EFFECT || ctx.curEffect != NO_EFFECT) {
		return false;
	}
	if (start.commands != end.commands || start.effects != end.effects) { return false; }
	if (ctx.runOpen != start.runOpen || ctx.curPipeline != start.pipeline ||
			ctx.curView != start.view) {
		return false;
	}
	if (ctx.curBlend != start.blend || ctx.curSampler != start.sampler) { return false; }
	const l: DrawContext2D = currentContext();
	const cursor: int32 = match (ctx.curPipeline) {
		Pipeline.Sprite => l.spriteInstanceTotal,
		Pipeline.Ui => l.uiInstanceTotal,
		Pipeline.Vertex => l.vertexTotal,
	};
	const emptyThen: boolean = start.runStart == streamOf(start, start.pipeline);
	if ((ctx.runStart == cursor) != emptyThen) { return false; }
	if (scopeRow(l, l.scopeNow) != scopeRow(old, start.scope)) { return false; }
	const maskNow: int32 = ctx.clipDepth > 0 ? ctx.maskIndices[ctx.clipDepth - 1] : NO_MASK;
	if (maskNow == NO_MASK || start.mask == NO_MASK) { return maskNow == start.mask; }
	return ctx.clipStack[ctx.clipDepth - 1] == old.masks[start.mask];
}

export function carried(pi: PaintIndex, first: PaintIndex, at: PaintIndex): PaintIndex {
	const reopened: boolean = pi.pipeline != first.pipeline || pi.runStart != first.runStart ||
		pi.reason != first.reason;
	return {
		commands: pi.commands - first.commands + at.commands,
		effects: pi.effects - first.effects + at.effects,
		vertices: pi.vertices - first.vertices + at.vertices,
		uiInstances: pi.uiInstances - first.uiInstances + at.uiInstances,
		spriteInstances: pi.spriteInstances - first.spriteInstances + at.spriteInstances,
		runOpen: pi.runOpen,
		runStart: reopened
			? pi.runStart - streamOf(first, pi.pipeline) + streamOf(at, pi.pipeline)
			: at.runStart,
		pipeline: pi.pipeline,
		reason: reopened ? pi.reason : at.reason,
		view: pi.view,
		blend: pi.blend,
		sampler: pi.sampler,
		effect: pi.effect,
		mask: at.mask,
		scope: at.scope,
	};
}

export function continueAfter(start: PaintIndex, end: PaintIndex, at: PaintIndex): void {
	const ctx: DrawContext2D = currentContext();
	const reopened: boolean = end.pipeline != start.pipeline || end.runStart != start.runStart ||
		end.reason != start.reason;
	ctx.runOpen = end.runOpen;
	ctx.curPipeline = end.pipeline;
	ctx.curView = end.view;
	ctx.curBlend = end.blend;
	ctx.curSampler = end.sampler;
	if (reopened) {
		ctx.runStart = end.runStart - streamOf(start, end.pipeline) + streamOf(at, end.pipeline);
		ctx.runReason = end.reason;
	}
}

function runCursor(): int32 {
	const ctx: DrawContext2D = currentContext();
	return match (ctx.curPipeline) {
		Pipeline.Sprite => spriteInstanceCount(),
		Pipeline.Ui => uiInstanceCount(),
		Pipeline.Vertex => vertexCount(),
	};
}

export function splitRun(): boolean {
	const ctx: DrawContext2D = currentContext();
	if (!ctx.runOpen || runCursor() == ctx.runStart) { return false; }
	const reason: BreakReason = ctx.runReason;
	closeRun();
	openRun(reason);
	return true;
}


export function closeLaneRun(): boolean {
	const ctx: DrawContext2D = currentContext();
	ctx.laneRunWasOpen = ctx.runOpen;
	const before: int32 = commandCount();
	closeRun();
	return commandCount() > before;
}

export function restoreLaneRun(): void {
	const ctx: DrawContext2D = currentContext();
	ctx.runOpen = ctx.laneRunWasOpen;
}

export function reopenLast(): void {
	const ctx: DrawContext2D = currentContext();
	const l: DrawContext2D = currentContext();
	const last: int32 = l.commandTotal - 1;
	const base: int32 = last * COMMAND_FLOATS;
	ctx.curPipeline = pipelineAt(l.commands, base);
	ctx.curView = commandView(last);
	ctx.curBlend = ((l.commands[base + CMD_BLEND] as int32) as BlendMode);
	ctx.curSampler = l.commands[base + CMD_SAMPLER] as int32;
	restoreEffect(l.commands[base + CMD_EFFECT] as int32);
	ctx.runReason = (l.commands[base + CMD_BREAK] as int32) as BreakReason;
	ctx.runStart = runOffset(l.commands, base);
	ctx.runOpen = true;
	l.commandTotal = last;
}

export function endPatch(end: PaintIndex): void {
	const ctx: DrawContext2D = currentContext();
	resumePaint(end);
	ctx.runOpen = false;
}

function openRun(reason: BreakReason): void {
	const ctx: DrawContext2D = currentContext();
	ctx.runStart = match (ctx.curPipeline) {
		Pipeline.Sprite => spriteInstanceCount(),
		Pipeline.Ui => uiInstanceCount(),
		Pipeline.Vertex => vertexCount(),
	};
	ctx.runReason = reason;
	ctx.runOpen = true;
}

function useRun(pipeline: Pipeline, view: uint32, premultiplied: boolean, blend: BlendMode): void {
	const ctx: DrawContext2D = currentContext();
	const sampler: int32 = (ctx.curSampler % SOURCE_PREMULTIPLIED) +
		(premultiplied ? SOURCE_PREMULTIPLIED : 0);
	if (ctx.runOpen && view == ctx.curView && sampler == ctx.curSampler && blend == ctx.curBlend
		&& ctx.curPipeline == pipeline) { return; }
	const reason: BreakReason = !ctx.runOpen ? BreakReason.First
		: (ctx.curPipeline != pipeline ? BreakReason.Pipeline
		: (view != ctx.curView ? BreakReason.View
		: (blend != ctx.curBlend ? BreakReason.Blend : BreakReason.Sampler)));
	closeRun();
	ctx.curView = view;
	ctx.curSampler = sampler;
	ctx.curBlend = blend;
	ctx.curPipeline = pipeline;
	openRun(reason);
}

export function setup2d(): void {
	void2dSetup();
	when (voidProfiler) { profilerSetup(); }
	when (voidSdfText) { setSdfRegime(true); }
	setTextGamma(DEFAULT_TEXT_GAMMA, DEFAULT_TEXT_CONTRAST);
	// The emitter and the replay are two hand-written readers of one byte layout, so they
	// are made to agree out loud rather than by inspection.
	if (void2dLayoutCheck(
		COMMAND_FLOATS, EFFECT_FLOATS, VERTEX_FLOATS,
		CMD_KIND, CMD_BREAK, CMD_VERTEX_OFFSET, CMD_VERTEX_COUNT,
		CMD_VIEW, CMD_VIEW_HIGH, CMD_BLEND, CMD_SAMPLER, CMD_EFFECT, SAMPLER_COUNT,
		CMD_CLEAR_R,
		CMD_CLIP_X, CMD_CLIP_U_X, CMD_ARG0, CMD_RT_MODE,
		CommandKind.Draw as int32, CommandKind.Scissor as int32, CommandKind.Blur as int32,
		CommandKind.TargetBegin as int32, CommandKind.TargetEnd as int32,
		Program2D.Vertex as int32, Program2D.Sprite as int32, Program2D.Ui as int32,
		Program2D.Blur as int32, PROGRAMS_2D, BLEND_MODES,
	) == 0) {
		console.log("void2d: the display-list layout in displayList.ms and batcher.c disagree");
		unreachable;
	}
}

export function uiInstanceStride(): int32 { return void2dUiInstanceStride(); }

// The colour pack as C does it on the way into the GPU buffer, re-exported so T0 can hold it
// against `instance.ms`'s `packChannel`: guardrail 9 must not rest on two copies that look alike.
export function packChannelC(value: float32): int32 { return void2dPackChannel(value); }
export function spriteInstanceStride(): int32 { return void2dSpriteInstanceStride(); }


// h2d has no DPI concept; void2d needs one because snapping and the pixel-exact text regime
// are stated per device pixel. The logical size is a float — the `as int32` truncation that
// put every glyph off-grid at DPI 1.25 and 1.5 is gone (VOID2D.md "Known defects").
export function begin2d(w: float32, h: float32, dpi: float32): void {
	useDefaultContext();
	beginContext(w, h, dpi);
}

export function openBracket(w: float32, h: float32, dpi: float32): void {
	const ctx: DrawContext2D = currentContext();
	if (ctx.prepared) {
		console.log(`void2d: record context ${ctx.id} before drawScreen consumed its prepared frame`);
		unreachable;
	}
	void2dSetDpiScale(dpi);
	when (voidProfiler) { profilerCollect(); }
	void2dFrameBegin();
	when (voidProfiler) { profilerFrameOpened(); }
	beginGlyphFrame(void2dFrameSerial());
	ctx.frameDpi = dpi;
	ctx.fbW = w;
	ctx.fbH = h;
	ctx.targetsFlushed = false;
	ctx.frameLive = true;
	ctx.originX = 0.0;
	ctx.originY = 0.0;
}

export function beginContext(w: float32, h: float32, dpi: float32): void {
	openBracket(w, h, dpi);
	startContext();
}

export function startContext(): void {
	const ctx: DrawContext2D = currentContext();
	if (ctx.prepared) {
		console.log(`void2d: reset context ${ctx.id} before drawScreen consumed its prepared frame`);
		unreachable;
	}
	resetContext();
	ctx.runOpen = false;
	ctx.runStart = 0;
	ctx.curPipeline = Pipeline.Ui;
	ctx.runReason = BreakReason.First;
	ctx.curView = void2dWhiteView();
	ctx.curBlend = BlendMode.Alpha;
	ctx.curSampler = samplerIndex(ctx.sceneSmooth, false);
	clearEffect();
	ctx.clipDepth = 0;
	while ((ctx.scopeDepths.length as int32) > 0) { ctx.scopeDepths.pop(); }
}

// Upload the frame and run every render-target pass. Called with NO pass open, before the
// swapchain pass is begun: that ordering is the phase's whole point, because a target pass
// opened inside the swapchain pass is what sokol asserts on.
export function flushTargets(): void {
	const ctx: DrawContext2D = currentContext();
	finishRecording();
	const l: DrawContext2D = currentContext();
	resolveScopes();
	resolvePipelines();
	void2dSetDpiScale(l.frameDpi);
	void2dSetScopes(l.scopeValues[0], l.scopeTotal);
	const targets: int32 = l.targetsPending ? targetCommandCount() : 0;
	l.targetsPending = false;
	if (isDefaultContext(l)) {
		ctx.frameLive = void2dReplayTargets(
			l.targetCommands[0], targets,
			l.effects[0], effectCount(),
			l.vertices[0], vertexCount(),
			l.spriteInstances[0], spriteInstanceCount(),
			l.uiInstances[0], uiInstanceCount(),
		) != 0;
	} else {
		ctx.frameLive = void2dReplayList(
			l.id, l.targetCommands[0], targets,
			l.effects[0], effectCount(),
			l.vertices[0], vertexCount(), (l.uploadAll || l.dirtyVertices) ? 1 : 0,
			l.spriteInstances[0], spriteInstanceCount(), (l.uploadAll || l.dirtySprites) ? 1 : 0,
			l.uiInstances[0], uiInstanceCount(),
			l.dirtyUi[0], l.uploadAll ? -1 : l.dirtyUiTotal,
		) != 0;
	}
	void2dRememberContext(l.id, l.frameLive ? 1 : 0);
	uploaded();
	ctx.targetsFlushed = true;
}

export function prepare(this ctx: DrawContext2D): void {
	if (ctx.prepared) {
		console.log(`void2d: prepare context ${ctx.id} again before drawScreen`);
		unreachable;
	}
	if (passState() != PassState.None) {
		console.log(`void2d: prepare context ${ctx.id} with a pass already open`);
		unreachable;
	}
	useContext(ctx);
	flushTargets();
	ctx.prepared = true;
	ctx.preparedFrame = frameIndex();
}

export function drawScreen(this ctx: DrawContext2D): void {
	if (!ctx.prepared) {
		console.log(`void2d: drawScreen context ${ctx.id} with no prepared frame`);
		unreachable;
	}
	if (passState() != PassState.Screen) {
		console.log(`void2d: drawScreen context ${ctx.id} outside a screen pass`);
		unreachable;
	}
	if (ctx.preparedFrame != frameIndex()) {
		console.log(`void2d: drawScreen context ${ctx.id} after its prepared frame expired`);
		unreachable;
	}
	const screenW: int32 = fbWidth();
	const screenH: int32 = fbHeight();
	if (!(ctx.frameDpi > 0.0) || !Number.isFinite(ctx.frameDpi) ||
		ctx.fbW != (screenW as float32) / ctx.frameDpi ||
		ctx.fbH != (screenH as float32) / ctx.frameDpi) {
		console.log(`void2d: drawScreen ${screenW}x${screenH} does not match prepared ` +
			`${ctx.fbW}x${ctx.fbH} at DPI ${ctx.frameDpi}`);
		unreachable;
	}
	ctx.prepared = false;
	useContext(ctx);
	end2d();
}

export function drawTarget(this ctx: DrawContext2D, target: RenderTarget, clear: Color): void {
	if (!ctx.prepared) {
		console.log(`void2d: drawTarget context ${ctx.id} with no prepared frame`);
		unreachable;
	}
	if (passState() != PassState.None) {
		console.log(`void2d: drawTarget context ${ctx.id} with a pass already open`);
		unreachable;
	}
	if (ctx.preparedFrame != frameIndex()) {
		console.log(`void2d: drawTarget context ${ctx.id} after its prepared frame expired`);
		unreachable;
	}
	target.requireCurrent("drawTarget");
	if (target.format != PixelFormat.Rgba8 || target.width <= 0 || target.height <= 0 ||
		target.image == 0 || target.attachment == 0) {
		console.log("void2d: drawTarget needs an allocated Rgba8 target " +
			"with a positive pixel size");
		unreachable;
	}
	if (!imageAlive(target.image) || !viewAlive(target.attachment)) {
		console.log("void2d: drawTarget on a render target that was released");
		unreachable;
	}
	if (!(ctx.frameDpi > 0.0) || !Number.isFinite(ctx.frameDpi) ||
		ctx.fbW != (target.width as float32) / ctx.frameDpi ||
		ctx.fbH != (target.height as float32) / ctx.frameDpi) {
		console.log(`void2d: drawTarget ${target.width}x${target.height} does not match prepared ` +
			`${ctx.fbW}x${ctx.fbH} at DPI ${ctx.frameDpi}`);
		unreachable;
	}
	for (let i: int32 = 0; i < ctx.commandTotal; i++) {
		const base: int32 = i * COMMAND_FLOATS;
		if ((ctx.commands[base + CMD_KIND] as int32) != (CommandKind.Draw as int32)) { continue; }
		const program: int32 = ctx.commands[base + CMD_PIPELINE] as int32;
		const blend: int32 = ctx.commands[base + CMD_BLEND] as int32;
		wantPipelineSlot(pipelineSlot(program, 1, blend));
	}
	resolvePipelines();
	ctx.prepared = false;
	useContext(ctx);
	doorBeginColorPass(target.attachment,
		clear.r * clear.a, clear.g * clear.a, clear.b * clear.a, clear.a);
	end2d();
	endPass();
}

export function end2d(): void {
	const ctx: DrawContext2D = currentContext();
	finishRecording();
	if (targetCommandCount() > 0 && !ctx.targetsFlushed) {
		void2dFailPendingTargets();
		return;
	}
	if (commandCount() == 0) { return; }
	const l: DrawContext2D = currentContext();
	void2dSetDpiScale(l.frameDpi);
	void2dSetScopes(l.scopeValues[0], l.scopeTotal);
	if (void2dActivateContext(l.id) == 0) { return; }
	void2dReplay(
		l.commands[0], commandCount(),
		l.effects[0], effectCount(),
		ctx.fbW, ctx.fbH,
	);
}

function absf(v: float32): float32 { return v < 0.0 ? -v : v; }

function minFour(a: float32, b: float32, c: float32, d: float32): float32 {
	let out: float32 = a < b ? a : b;
	if (c < out) { out = c; }
	if (d < out) { out = d; }
	return out;
}

function maxFour(a: float32, b: float32, c: float32, d: float32): float32 {
	let out: float32 = a > b ? a : b;
	if (c > out) { out = c; }
	if (d > out) { out = d; }
	return out;
}

function clipOf(c: MaskClip): Clip {
	const ctx: DrawContext2D = currentContext();
	const ix: float32 = c.x0;
	const iy: float32 = c.y0;
	let iw: float32 = c.x1 - c.x0;
	let ih: float32 = c.y1 - c.y0;
	if (iw < 0.0) { iw = 0.0; }
	if (ih < 0.0) { ih = 0.0; }
	const uShift: float32 = ctx.originX * c.ux + ctx.originY * c.uy;
	const vShift: float32 = ctx.originX * c.vx + ctx.originY * c.vy;
	return {
		x: ix - ctx.originX, y: iy - ctx.originY, w: iw, h: ih,
		ux: c.ux, uy: c.uy, uMin: c.uMin - uShift, uMax: c.uMax - uShift,
		vx: c.vx, vy: c.vy, vMin: c.vMin - vShift, vMax: c.vMax - vShift,
	};
}

function applyClip(d: int32): void {
	const ctx: DrawContext2D = currentContext();
	closeRun();
	recordClip(clipOf(ctx.clipStack[d]));
	openRun(BreakReason.Clip);
}

export function clipIntersectsQuad(tl: Vec2, tr: Vec2, br: Vec2, bl: Vec2): boolean {
	const ctx: DrawContext2D = currentContext();
	if (ctx.clipDepth <= 0) { return true; }
	const c: MaskClip = ctx.clipStack[ctx.clipDepth - 1];
	if (c.x1 <= c.x0 || c.y1 <= c.y0) { return false; }
	if (maxFour(tl.x, tr.x, br.x, bl.x) <= c.x0
		|| minFour(tl.x, tr.x, br.x, bl.x) >= c.x1
		|| maxFour(tl.y, tr.y, br.y, bl.y) <= c.y0
		|| minFour(tl.y, tr.y, br.y, bl.y) >= c.y1) { return false; }
	if (c.uMax <= c.uMin) { return true; }
	const u0: float32 = tl.x * c.ux + tl.y * c.uy;
	const u1: float32 = tr.x * c.ux + tr.y * c.uy;
	const u2: float32 = br.x * c.ux + br.y * c.uy;
	const u3: float32 = bl.x * c.ux + bl.y * c.uy;
	if (maxFour(u0, u1, u2, u3) <= c.uMin
		|| minFour(u0, u1, u2, u3) >= c.uMax) { return false; }
	const v0: float32 = tl.x * c.vx + tl.y * c.vy;
	const v1: float32 = tr.x * c.vx + tr.y * c.vy;
	const v2: float32 = br.x * c.vx + br.y * c.vy;
	const v3: float32 = bl.x * c.vx + bl.y * c.vy;
	return maxFour(v0, v1, v2, v3) > c.vMin
		&& minFour(v0, v1, v2, v3) < c.vMax;
}

export function pushClip(tl: Vec2, tr: Vec2, br: Vec2, bl: Vec2): boolean {
	const ctx: DrawContext2D = currentContext();
	let x0: float32 = minFour(tl.x, tr.x, br.x, bl.x);
	let y0: float32 = minFour(tl.y, tr.y, br.y, bl.y);
	let x1: float32 = maxFour(tl.x, tr.x, br.x, bl.x);
	let y1: float32 = maxFour(tl.y, tr.y, br.y, bl.y);
	const parent: int32 = ctx.clipDepth - 1;
	let next: MaskClip = NO_MASK_CLIP;
	if (parent >= 0) {
		next = ctx.clipStack[parent];
		if (next.x0 > x0) { x0 = next.x0; }
		if (next.y0 > y0) { y0 = next.y0; }
		if (next.x1 < x1) { x1 = next.x1; }
		if (next.y1 < y1) { y1 = next.y1; }
	}
	while (ctx.clipDepth >= ctx.clipStack.length as int32) { ctx.clipStack.push(NO_MASK_CLIP); }
	while (ctx.clipDepth >= ctx.maskIndices.length as int32) { ctx.maskIndices.push(NO_MASK); }
	const d: int32 = ctx.clipDepth;

	const ex: float32 = tr.x - tl.x;
	const ey: float32 = tr.y - tl.y;
	const fx: float32 = bl.x - tl.x;
	const fy: float32 = bl.y - tl.y;
	const exLen: float32 = Math.sqrt((ex * ex + ey * ey) as float64) as float32;
	const fLen: float32 = Math.sqrt((fx * fx + fy * fy) as float64) as float32;
	let supported: boolean = true;
	const axisAligned: boolean = (absf(ey) < 0.0001 && absf(fx) < 0.0001)
		|| (absf(ex) < 0.0001 && absf(fy) < 0.0001);
	if (!axisAligned && exLen > 0.0 && fLen > 0.0) {
		const ux: float32 = ex / exLen;
		const uy: float32 = ey / exLen;
		const vx: float32 = fx / fLen;
		const vy: float32 = fy / fLen;
		if (next.uMax > next.uMin) {
			const same: boolean =
				(absf(next.ux * ux + next.uy * uy) > 0.9999
					&& absf(next.vx * vx + next.vy * vy) > 0.9999)
				|| (absf(next.ux * vx + next.uy * vy) > 0.9999
					&& absf(next.vx * ux + next.vy * uy) > 0.9999);
			if (!same) {
				console.log("void2d: nested rotated Masks use different edge axes");
				x1 = x0;
				y1 = y0;
				supported = false;
			} else {
				const pu0: float32 = tl.x * next.ux + tl.y * next.uy;
				const pu1: float32 = tr.x * next.ux + tr.y * next.uy;
				const pu2: float32 = br.x * next.ux + br.y * next.uy;
				const pu3: float32 = bl.x * next.ux + bl.y * next.uy;
				const pv0: float32 = tl.x * next.vx + tl.y * next.vy;
				const pv1: float32 = tr.x * next.vx + tr.y * next.vy;
				const pv2: float32 = br.x * next.vx + br.y * next.vy;
				const pv3: float32 = bl.x * next.vx + bl.y * next.vy;
				const uMin: float32 = minFour(pu0, pu1, pu2, pu3);
				const uMax: float32 = maxFour(pu0, pu1, pu2, pu3);
				const vMin: float32 = minFour(pv0, pv1, pv2, pv3);
				const vMax: float32 = maxFour(pv0, pv1, pv2, pv3);
				if (uMin > next.uMin) { next.uMin = uMin; }
				if (uMax < next.uMax) { next.uMax = uMax; }
				if (vMin > next.vMin) { next.vMin = vMin; }
				if (vMax < next.vMax) { next.vMax = vMax; }
			}
		} else {
			const u0: float32 = tl.x * ux + tl.y * uy;
			const u1: float32 = tr.x * ux + tr.y * uy;
			const u2: float32 = br.x * ux + br.y * uy;
			const u3: float32 = bl.x * ux + bl.y * uy;
			const v0: float32 = tl.x * vx + tl.y * vy;
			const v1: float32 = tr.x * vx + tr.y * vy;
			const v2: float32 = br.x * vx + br.y * vy;
			const v3: float32 = bl.x * vx + bl.y * vy;
			next = {
				...next,
				ux: ux, uy: uy, vx: vx, vy: vy,
				uMin: minFour(u0, u1, u2, u3), uMax: maxFour(u0, u1, u2, u3),
				vMin: minFour(v0, v1, v2, v3), vMax: maxFour(v0, v1, v2, v3),
			};
		}
	}
	ctx.clipStack[d] = { ...next, x0: x0, y0: y0, x1: x1, y1: y1 };
	ctx.maskIndices[d] = pushMaskClip(ctx.clipStack[d]);
	ctx.clipDepth = ctx.clipDepth + 1;
	applyClip(d);
	return supported;
}


export function inScope(): boolean {
	const l: DrawContext2D = currentContext();
	return l.scopeNow != NO_SCOPE && l.scopeNow != l.cameraScope;
}

export function enterCamera(row: int32, dx: float32, dy: float32): void {
	const ctx: DrawContext2D = currentContext();
	const l: DrawContext2D = currentContext();
	const record: ScopeRecord = {
		row: row,
		parent: NO_SCOPE,
		scale: currentRenderScale(),
		dx: dx,
		dy: dy,
		x: 0.0,
		y: 0.0,
		w: ctx.fbW,
		h: ctx.fbH,
	};
	l.scopeNow = pushScope(record);
	l.cameraScope = l.scopeNow;
}

export function enterScope(
	row: int32, tl: Vec2, tr: Vec2, br: Vec2, bl: Vec2, dx: float32, dy: float32,
): void {
	const ctx: DrawContext2D = currentContext();
	let x0: float32 = minFour(tl.x, tr.x, br.x, bl.x);
	let y0: float32 = minFour(tl.y, tr.y, br.y, bl.y);
	let x1: float32 = maxFour(tl.x, tr.x, br.x, bl.x);
	let y1: float32 = maxFour(tl.y, tr.y, br.y, bl.y);
	if (ctx.clipDepth > 0) {
		const outer: MaskClip = ctx.clipStack[ctx.clipDepth - 1];
		if (outer.x0 > x0) { x0 = outer.x0; }
		if (outer.y0 > y0) { y0 = outer.y0; }
		if (outer.x1 < x1) { x1 = outer.x1; }
		if (outer.y1 < y1) { y1 = outer.y1; }
	}
	closeRun();
	const l: DrawContext2D = currentContext();
	const record: ScopeRecord = {
		row: row,
		parent: l.scopeNow,
		scale: currentRenderScale(),
		dx: dx,
		dy: dy,
		x: x0 - ctx.originX,
		y: y0 - ctx.originY,
		w: x1 > x0 ? x1 - x0 : 0.0,
		h: y1 > y0 ? y1 - y0 : 0.0,
	};
	l.scopeNow = pushScope(record);
	ctx.scopeDepths.push(ctx.clipDepth);
	ctx.clipDepth = 0;
	l.clip = NO_CLIP;
	openRun(BreakReason.Clip);
}

export function leaveScope(): void {
	const ctx: DrawContext2D = currentContext();
	closeRun();
	const l: DrawContext2D = currentContext();
	l.scopeNow = l.scopes[l.scopeNow].parent;
	ctx.clipDepth = ctx.scopeDepths.pop();
	if (ctx.clipDepth > 0) {
		applyClip(ctx.clipDepth - 1);
		return;
	}
	recordClip(NO_CLIP);
	openRun(BreakReason.Clip);
}

export function popClip(): void {
	const ctx: DrawContext2D = currentContext();
	if (ctx.clipDepth > 0) { ctx.clipDepth = ctx.clipDepth - 1; }
	if (ctx.clipDepth > 0) {
		applyClip(ctx.clipDepth - 1);
	} else {
		closeRun();
		recordClip(NO_CLIP);
		openRun(BreakReason.Clip);
	}
}

function currentGradientKind(): int32 {
	const ctx: DrawContext2D = currentContext();
	if (ctx.curEffect == NO_EFFECT) { return 0; }
	return effectField(ctx.curEffect, EFFECT_GRADIENT_META) as int32;
}
export function setEffect(mat: Mat4, add: Color, key: Color): void {
	const ctx: DrawContext2D = currentContext();
	const hasMat: boolean = mat != NO_COLOR_MATRIX;
	const wantsEffect: boolean = hasMat || add.r != 0.0 || add.g != 0.0 || add.b != 0.0 ||
		add.a != 0.0 || key.a > 0.0;
	if (!wantsEffect && ctx.curEffect == NO_EFFECT) { return; }
	if (wantsEffect && ctx.curEffect != NO_EFFECT && currentGradientKind() == 0
		&& add == ctx.curAdd && key == ctx.curKey
		&& mat == ctx.curMat) { return; }
	closeRun();
	ctx.curMat = mat;
	ctx.curAdd = add;
	ctx.curKey = key;
	ctx.curEffect = wantsEffect ? pushEffect(mat, add, key) : NO_EFFECT;
	openRun(BreakReason.Effect);
}
export function setGradientEffect(
	mat: Mat4,
	add: Color,
	key: Color,
	kind: int32,
	space: int32,
	dither: boolean,
	middle: float32,
	p0: float32,
	p1: float32,
	p2: float32,
	p3: float32,
	c0: Color,
	c1: Color,
	c2: Color,
): void {
	const ctx: DrawContext2D = currentContext();
	if (ctx.curEffect != NO_EFFECT
		&& (effectField(ctx.curEffect, EFFECT_GRADIENT_META) as int32) == kind
		&& (effectField(ctx.curEffect, EFFECT_GRADIENT_META + 1) as int32) == space
		&& effectField(ctx.curEffect, EFFECT_GRADIENT_META + 2) == (dither ? 1.0 : 0.0)
		&& effectField(ctx.curEffect, EFFECT_GRADIENT_META + 3) == middle
		&& effectField(ctx.curEffect, EFFECT_GRADIENT_PARAMS) == p0
		&& effectField(ctx.curEffect, EFFECT_GRADIENT_PARAMS + 1) == p1
		&& effectField(ctx.curEffect, EFFECT_GRADIENT_PARAMS + 2) == p2
		&& effectField(ctx.curEffect, EFFECT_GRADIENT_PARAMS + 3) == p3
		&& effectField(ctx.curEffect, EFFECT_GRADIENT_COLOR0) == c0.r
		&& effectField(ctx.curEffect, EFFECT_GRADIENT_COLOR0 + 1) == c0.g
		&& effectField(ctx.curEffect, EFFECT_GRADIENT_COLOR0 + 2) == c0.b
		&& effectField(ctx.curEffect, EFFECT_GRADIENT_COLOR0 + 3) == c0.a
		&& effectField(ctx.curEffect, EFFECT_GRADIENT_COLOR1) == c1.r
		&& effectField(ctx.curEffect, EFFECT_GRADIENT_COLOR1 + 1) == c1.g
		&& effectField(ctx.curEffect, EFFECT_GRADIENT_COLOR1 + 2) == c1.b
		&& effectField(ctx.curEffect, EFFECT_GRADIENT_COLOR1 + 3) == c1.a
		&& effectField(ctx.curEffect, EFFECT_GRADIENT_COLOR2) == c2.r
		&& effectField(ctx.curEffect, EFFECT_GRADIENT_COLOR2 + 1) == c2.g
		&& effectField(ctx.curEffect, EFFECT_GRADIENT_COLOR2 + 2) == c2.b
		&& effectField(ctx.curEffect, EFFECT_GRADIENT_COLOR2 + 3) == c2.a
		&& add == ctx.curAdd && key == ctx.curKey
		&& mat == ctx.curMat) { return; }
	closeRun();
	ctx.curMat = mat;
	ctx.curAdd = add;
	ctx.curKey = key;
	ctx.curEffect = pushGradientEffect(mat, add, key, kind, space, dither, middle,
		p0, p1, p2, p3, c0, c1, c2);
	openRun(BreakReason.Effect);
}

// The scene's default for nodes whose `smooth` is `Smooth.Inherit`. Set once per bracket by
// `Scene.present`, before the walk; changing it mid-walk would make two nodes with identical
// state sample differently, which is exactly the bug a tri-state invites.
export function setSceneSmooth(s: boolean): void {
	const ctx: DrawContext2D = currentContext();
	ctx.sceneSmooth = s;
}

export function sceneSmoothDefault(): boolean {
	const ctx: DrawContext2D = currentContext();
	return ctx.sceneSmooth;
}

// h2d.Drawable.smooth and h2d.Drawable.tileWrap, resolved: linear vs nearest sampling, and
// repeat vs clamp at the tile's edge. Batch state — a change closes the run, because a
// sampler is bound per draw.
export function setSampler(smooth: Smooth, tileWrap: boolean): void {
	const ctx: DrawContext2D = currentContext();
	const on: boolean = smooth == Smooth.Inherit ? ctx.sceneSmooth : smooth == Smooth.On;
	const want: int32 = samplerIndex(on, tileWrap) +
		(ctx.curSampler >= SOURCE_PREMULTIPLIED ? SOURCE_PREMULTIPLIED : 0);
	if (want == ctx.curSampler) { return; }
	closeRun();
	ctx.curSampler = want;
	openRun(BreakReason.Sampler);
}

function quad(
	view: uint32, premultiplied: boolean, blend: BlendMode,
	x: float32, y: float32, w: float32, h: float32, c: Color,
	u0: float32, v0: float32, u1: float32, v1: float32,
): void {
	useRun(Pipeline.Vertex, view, premultiplied, blend);
	const x1: float32 = x + w;
	const y1: float32 = y + h;
	pushVertex(x, y, u0, v0, c.r, c.g, c.b, c.a);
	pushVertex(x1, y, u1, v0, c.r, c.g, c.b, c.a);
	pushVertex(x1, y1, u1, v1, c.r, c.g, c.b, c.a);
	pushVertex(x, y, u0, v0, c.r, c.g, c.b, c.a);
	pushVertex(x1, y1, u1, v1, c.r, c.g, c.b, c.a);
	pushVertex(x, y1, u0, v1, c.r, c.g, c.b, c.a);
}

export function drawRect(pos: Vec2, size: Vec2, color: Color, blend: BlendMode): void {
	quad(void2dWhiteView(), false, blend, pos.x, pos.y, size.x, size.y, color, 0.0, 0.0, 1.0, 1.0);
}

export function drawImage(t: Tile, pos: Vec2, size: Vec2, tint: Color, blend: BlendMode): void {
	quad(t.source.view(), t.alphaPremultiplied, blend, pos.x, pos.y, size.x, size.y, tint,
		t.u0, t.v0, t.u1, t.v1);
}

// Which pipeline set the following draws need: the offscreen one (single sample, no depth)
// or the swapchain one. Recorded per command rather than flipped here, because the replay
// runs after the recording has finished — the demo caught this the moment the display list
// landed, with every render-target draw replaying under the swapchain set.
// Open a render-target bracket. Nothing touches the GPU here: the commands that follow are
// moved into the hoisted target list when `endTarget` closes them, and the pass itself is
// opened by the replay, outside the swapchain pass. The emitter's run state is saved because
// the target has its own viewport and its own idea of what is already bound.
function stopOnTarget(target: RenderTarget, scale: float32): void {
	console.log(`void2d: beginTarget needs an allocated Rgba8 target and a positive scale, got ` +
		`${target.format.toString()} ${target.width}x${target.height} view ${target.attachment}` +
		` at scale ${scale}`);
	unreachable;
}

function stopOnEndWithoutTarget(): void {
	console.log("void2d: endTarget with no target open; every endTarget closes one beginTarget");
	unreachable;
}

function stopOnBlurOutsideTarget(): void {
	console.log("void2d: blurPass outside beginTarget; the blur draws only into a target");
	unreachable;
}

export function beginTarget(
	target: RenderTarget,
	w: float32,
	h: float32,
	scale: float32,
	ox: float32,
	oy: float32,
	clear: Color,
): void {
	target.requireCurrent("beginTarget");
	if (target.format != PixelFormat.Rgba8 || target.attachment == 0 || scale <= 0.0) {
		stopOnTarget(target, scale);
	}
	const rt: uint32 = target.attachment;
	const ctx: DrawContext2D = currentContext();
	ctx.targetsFlushed = false;
	closeRun();
	if (targetDepth() == (ctx.savedView.length as int32)) {
		ctx.savedView.push(0 as uint32);
		for (let k: int32 = 0; k < 3; k++) { ctx.savedRun.push(0.0 as float32); }
		for (let k: int32 = 0; k < 4; k++) { ctx.savedSize.push(0.0 as float32); }
	}
	const slot: int32 = targetDepth() * 3;
	ctx.savedView[targetDepth()] = ctx.curView;
	ctx.savedRun[slot] = (ctx.curBlend as int32) as float32;
	ctx.savedRun[slot + 1] = ctx.curSampler as float32;
	ctx.savedRun[slot + 2] = ctx.curEffect as float32;
	ctx.savedSize[targetDepth() * 4] = ctx.fbW;
	ctx.savedSize[targetDepth() * 4 + 1] = ctx.fbH;
	ctx.savedSize[targetDepth() * 4 + 2] = ctx.originX;
	ctx.savedSize[targetDepth() * 4 + 3] = ctx.originY;
	beginTargetList(rt, w, h, scale, clear.r, clear.g, clear.b, clear.a);
	ctx.fbW = w;
	ctx.fbH = h;
	ctx.originX = ox;
	ctx.originY = oy;
	// A fresh pass has nothing bound, so the first draw in it must not be told it can skip a
	// bind it never made.
	ctx.curView = void2dWhiteView();
	ctx.curBlend = BlendMode.Alpha;
	ctx.curSampler = samplerIndex(ctx.sceneSmooth, false);
	clearEffect();
	openRun(BreakReason.Barrier);
}

export function endTarget(): void {
	const ctx: DrawContext2D = currentContext();
	closeRun();
	const depth: int32 = targetDepth();
	if (!endTargetList()) { stopOnEndWithoutTarget(); }
	const slot: int32 = (depth - 1) * 3;
	ctx.curView = ctx.savedView[depth - 1];
	ctx.curBlend = (ctx.savedRun[slot] as int32) as BlendMode;
	ctx.curSampler = ctx.savedRun[slot + 1] as int32;
	restoreEffect(ctx.savedRun[slot + 2] as int32);
	ctx.fbW = ctx.savedSize[(depth - 1) * 4];
	ctx.fbH = ctx.savedSize[(depth - 1) * 4 + 1];
	ctx.originX = ctx.savedSize[(depth - 1) * 4 + 2];
	ctx.originY = ctx.savedSize[(depth - 1) * 4 + 3];
	openRun(BreakReason.Barrier);
}

// One separable-blur tap pass (h2d.filter.Blur) recorded into the stream. `step` is the
// per-tap UV offset; run horizontal (step,0) then vertical (0,step) ping-ponging two RTs.
export function blurPass(srcView: uint32, stepX: float32, stepY: float32): void {
	if (targetDepth() == 0) { stopOnBlurOutsideTarget(); }
	closeRun();
	recordBlur(srcView, stepX, stepY);
	openRun(BreakReason.Barrier);
}

// ===== world-space geometry from a retained local-space mesh =====

// A Label's glyphs and a Graphics' triangles are built once in LOCAL space and kept on the
// node. Before P1 each owned an sg_buffer and was drawn with an object matrix in the shader,
// which is why at most about 126 of them could exist at all. Now the mesh is transformed
// here and appended to the frame's stream, so any number of them share one buffer and one
// draw per state run. P2 gives the transform back to the GPU as a per-instance affine; until
// then the CPU does it, which is what the old dynamic path already did for every Rect.
export const FRINGE_HALF_WIDTH: float32 = 0.5;
export const EDGE_FLOATS: int32 = 10;
export const EDGE_NORMAL_BEFORE: int32 = 0;
export const EDGE_NORMAL_AFTER: int32 = 2;
export const EDGE_SHIFT: int32 = 4;
export const EDGE_LIMIT: int32 = 5;
export const EDGE_UV: int32 = 6;
const EDGE_MITER_LIMIT: float32 = 4.0;
const EDGE_PARALLEL: float32 = 0.0001;

struct EdgeMove {
	x: float32;
	y: float32;
	coverage: float32;
}

function normalScale(m: Transform2D, inverseDet: float32, nx: float32, ny: float32): float32 {
	const x: float32 = (m.d * nx - m.b * ny) * inverseDet;
	const y: float32 = (m.a * ny - m.c * nx) * inverseDet;
	return sqrtf(x * x + y * y);
}

function edgeMove(
	edges: float32[],
	e: int32,
	m: Transform2D,
	inverseDet: float32,
	worldPerDevice: float32,
): EdgeMove {
	const n1x: float32 = edges[e + EDGE_NORMAL_BEFORE];
	const n1y: float32 = edges[e + EDGE_NORMAL_BEFORE + 1];
	const n2x: float32 = edges[e + EDGE_NORMAL_AFTER];
	const n2y: float32 = edges[e + EDGE_NORMAL_AFTER + 1];
	const shift: float32 = edges[e + EDGE_SHIFT] * worldPerDevice;
	let t1: float32 = shift * normalScale(m, inverseDet, n1x, n1y);
	let t2: float32 = shift * normalScale(m, inverseDet, n2x, n2y);
	const a1: float32 = t1 < 0.0 ? -t1 : t1;
	const a2: float32 = t2 < 0.0 ? -t2 : t2;
	const reach: float32 = a1 > a2 ? a1 : a2;
	const limit: float32 = edges[e + EDGE_LIMIT];
	let coverage: float32 = 1.0;
	let extent: float32 = reach;
	if (limit > 0.0 && reach > limit) {
		extent = shift < 0.0 ? limit : 2.0 * reach - limit;
		t1 = t1 * extent / reach;
		t2 = t2 * extent / reach;
		if (shift < 0.0) { coverage = limit / reach; }
	}
	const det: float32 = n1x * n2y - n1y * n2x;
	let x: float32 = n1x * t1;
	let y: float32 = n1y * t1;
	if (det > EDGE_PARALLEL || det < -EDGE_PARALLEL) {
		x = (t1 * n2y - t2 * n1y) / det;
		y = (n1x * t2 - n2x * t1) / det;
	}
	const length: float32 = sqrtf(x * x + y * y);
	const longest: float32 = EDGE_MITER_LIMIT * extent;
	if (length > longest && length > 0.0) {
		x = x * longest / length;
		y = y * longest / length;
	}
	return { x: x, y: y, coverage: coverage };
}

export function drawMeshRange(
	mesh: float32[],
	edges: float32[],
	vertexOffset: int32,
	vertexTotal: int32,
	view: uint32,
	premultiplied: boolean,
	blend: BlendMode,
	m: Transform2D,
	tint: Color,
	alpha: float32,
): void {
	const first: int32 = vertexOffset * VERTEX_FLOATS;
	let upto: int32 = first + vertexTotal * VERTEX_FLOATS;
	if (first < 0 || first >= (mesh.length as int32)) { return; }
	if (upto > (mesh.length as int32)) { upto = mesh.length as int32; }
	useRun(Pipeline.Vertex, view == 0 ? void2dWhiteView() : view, premultiplied, blend);
	const det: float32 = m.a * m.d - m.b * m.c;
	const scale: float32 = currentRenderScale();
	const extrudes: boolean = (edges.length as int32) > 0 && scale > 0.0 &&
		(det > EDGE_PARALLEL || det < -EDGE_PARALLEL);
	const inverseDet: float32 = extrudes ? 1.0 / det : 0.0;
	const worldPerDevice: float32 = extrudes ? 1.0 / scale : 0.0;
	for (let i: int32 = first; i + VERTEX_FLOATS <= upto; i = i + VERTEX_FLOATS) {
		let lx: float32 = mesh[i];
		let ly: float32 = mesh[i + 1];
		let u: float32 = mesh[i + 2];
		let v: float32 = mesh[i + 3];
		let coverage: float32 = 1.0;
		const e: int32 = (i / VERTEX_FLOATS) * EDGE_FLOATS;
		if (extrudes && edges[e + EDGE_SHIFT] != 0.0) {
			const moved: EdgeMove = edgeMove(edges, e, m, inverseDet, worldPerDevice);
			lx = lx + moved.x;
			ly = ly + moved.y;
			u = u + edges[e + EDGE_UV] * moved.x + edges[e + EDGE_UV + 1] * moved.y;
			v = v + edges[e + EDGE_UV + 2] * moved.x + edges[e + EDGE_UV + 3] * moved.y;
			coverage = moved.coverage;
		}
		pushVertex(
			m.a * lx + m.c * ly + m.tx,
			m.b * lx + m.d * ly + m.ty,
			u,
			v,
			mesh[i + 4] * tint.r,
			mesh[i + 5] * tint.g,
			mesh[i + 6] * tint.b,
			mesh[i + 7] * tint.a * alpha * coverage,
		);
	}
}

export function drawMesh(
	mesh: float32[],
	edges: float32[],
	view: uint32,
	premultiplied: boolean,
	blend: BlendMode,
	m: Transform2D,
	tint: Color,
	alpha: float32,
): void {
	drawMeshRange(mesh, edges, 0, (mesh.length as int32) / VERTEX_FLOATS,
		view, premultiplied, blend, m, tint, alpha);
}

// ===== arbitrary-corner quads (for rotated/affine nodes; a=TL b=TR c=BR d=BL) =====

function quad4(
	view: uint32, premultiplied: boolean, blend: BlendMode, a: Vec2, b: Vec2, c: Vec2, d: Vec2,
	u0: float32, v0: float32, u1: float32, v1: float32, color: Color,
): void {
	useRun(Pipeline.Vertex, view, premultiplied, blend);
	pushVertex(a.x, a.y, u0, v0, color.r, color.g, color.b, color.a);
	pushVertex(b.x, b.y, u1, v0, color.r, color.g, color.b, color.a);
	pushVertex(c.x, c.y, u1, v1, color.r, color.g, color.b, color.a);
	pushVertex(a.x, a.y, u0, v0, color.r, color.g, color.b, color.a);
	pushVertex(c.x, c.y, u1, v1, color.r, color.g, color.b, color.a);
	pushVertex(d.x, d.y, u0, v1, color.r, color.g, color.b, color.a);
}

// One instanced sprite: the node's world affine, the origin its local bounds map to, and
// its local size. The shader rebuilds the corners, so the walk stops writing six transformed
// vertices and writes 64 unchanged bytes instead.
//
// colorAdd, no colorKey - so a node with one stays on the vertex path. That is a decision the
// caller makes, not a silent fallback: `spriteInstancingAvailable` is what render.ms asks.
export function drawSpriteAffine(
	view: uint32,
	premultiplied: boolean,
	blend: BlendMode,
	world: Transform2D,
	originX: float32,
	originY: float32,
	sizeX: float32,
	sizeY: float32,
	u0: float32, v0: float32, u1: float32, v1: float32,
	color: Color,
): void {
	beginSprites(view, premultiplied, blend);
	appendSprite(world, originX, originY, sizeX, sizeY, u0, v0, u1, v1, color);
}

export function rewriteSprite(
	index: int32,
	world: Transform2D,
	originX: float32,
	originY: float32,
	sizeX: float32,
	sizeY: float32,
	u0: float32, v0: float32, u1: float32, v1: float32,
	color: Color,
): void {
	putSpriteInstance(
		index, world.a, world.b, world.c, world.d, originX, originY, sizeX, sizeY,
		u0, v0, u1, v1, color,
	);
}

export function beginSprites(view: uint32, premultiplied: boolean, blend: BlendMode): void {
	useRun(Pipeline.Sprite, view == 0 ? void2dWhiteView() : view, premultiplied, blend);
}

export function appendSprite(
	world: Transform2D,
	originX: float32,
	originY: float32,
	sizeX: float32,
	sizeY: float32,
	u0: float32, v0: float32, u1: float32, v1: float32,
	color: Color,
): void {
	pushSpriteInstance(
		world.a, world.b, world.c, world.d,
		originX - originXOffset(), originY - originYOffset(), sizeX, sizeY,
		u0, v0, u1, v1,
		color,
	);
}

// One unified-UI instance: the node's world affine, the origin its local bounds map to, its
// local size, and the six lanes the modes share. The fragment stage re-derives the SDF in
// local space from these, so a rounded, bordered card at 37 degrees keeps its corner radius
// and its edge softness instead of having them baked in here.
//
// `mode` is a lane and not a pipeline - that is P2's whole thesis. A card, its label and its
// image differ by one float and stay in one run; the alternative is GPUI's per-kind pipelines,
// which is what forces its BoundsTree (guardrail 1).
//
// The modes that leave a lane unused pass zeros; `instance.ms` says which lane means what.
export function drawUiInstance(view: uint32, blend: BlendMode, inst: UiInstance): void {
	useRun(Pipeline.Ui, view == 0 ? void2dWhiteView() : view, false, blend);
	pushUiInstance(inst, originXOffset(), originYOffset());
}

export function uiInstancingAvailable(): boolean {
	const ctx: DrawContext2D = currentContext();
	return ctx.curEffect == NO_EFFECT;
}

// Counted from the stream rather than from the GPU, so T1 reads them with no GPU at all.
export function recordedUiInstanceCount(): int32 { return uiInstanceCount(); }
export function recordedSpriteInstanceCount(): int32 { return spriteInstanceCount(); }

// A filter records its subtree into an object-local target by subtracting the target's
// origin as each vertex is written. An instance carries its origin once, so the same
// subtraction applies there - and it has to be the same two numbers, or a filtered sprite
// lands somewhere else than a filtered anything else.
function originXOffset(): float32 {
	const ctx: DrawContext2D = currentContext(); return ctx.originX; }
function originYOffset(): float32 {
	const ctx: DrawContext2D = currentContext(); return ctx.originY; }

// True when the instanced path is legal for the state the emitter is in. The only thing that
// disqualifies it is a colour pipeline, which the sprite program does not have.
export function spriteInstancingAvailable(): boolean {
	const ctx: DrawContext2D = currentContext();
	return ctx.curEffect == NO_EFFECT;
}

export function fillQuad(a: Vec2, b: Vec2, c: Vec2, d: Vec2, color: Color, blend: BlendMode): void {
	quad4(void2dWhiteView(), false, blend, a, b, c, d, 0.0, 0.0, 1.0, 1.0, color);
}

export function imageQuad(
	t: Tile,
	a: Vec2,
	b: Vec2,
	c: Vec2,
	d: Vec2,
	color: Color,
	blend: BlendMode,
): void {
	quad4(t.source.view(), t.alphaPremultiplied, blend, a, b, c, d, t.u0, t.v0, t.u1, t.v1, color);
}

// explicit-UV textured quad — ScaleGrid 9-slice cells carry their own UV sub-rect.
export function imageQuadUV(
	view: uint32, premultiplied: boolean, u0: float32, v0: float32, u1: float32, v1: float32,
	a: Vec2, b: Vec2, c: Vec2, d: Vec2, color: Color, blend: BlendMode,
): void {
	quad4(view, premultiplied, blend, a, b, c, d, u0, v0, u1, v1, color);
}
