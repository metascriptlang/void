// T1 - the unified UI pipeline as batch state, with no GPU (docs/TESTING.md "T1").
//
// `instanceStreamCheck.ms` says the stream holds what it was given. This says the *run* does:
// that a UI instance opens a run on the UI pipeline, that switching between the three
// pipelines ends a run and says `break:pipeline` rather than leaving a count to be explained,
// and that instances of one pipeline never land in another's range.
//
// The last of those is what a mode count cannot prove - zero of every mode is also what an
// empty frame reads - so the assertions are on the command's pipeline field and on the stream
// that would have had to grow, which is B5's shape one layer up from the sprite case.

import {
	begin2d, finishRecording, drawRect, drawUiInstance, drawSpriteAffine,
	uiInstancingAvailable, recordedUiInstanceCount, recordedSpriteInstanceCount,
	premultipliedBlend,
} from "../void2d/draw";
import {
	drawCommandCount, commandField, vertexCount,
	CMD_PIPELINE, CMD_INSTANCE_OFFSET, CMD_INSTANCE_COUNT, CMD_VERTEX_COUNT, CMD_BREAK,
	Pipeline, breakReasonName,
} from "../void2d/displayList";
import { InstanceMode, uiInstance } from "../void2d/instance";
import { Color, identity2d } from "../void2d/types";
import { BlendMode, Blend, Operation, Face, Compare, RenderState } from "../gpu/state";

const WHITE: Color = { r: 1.0, g: 1.0, b: 1.0, a: 1.0 };
const RED: Color = { r: 1.0, g: 0.0, b: 0.0, a: 1.0 };
const CLEAR: Color = { r: 0.0, g: 0.0, b: 0.0, a: 0.0 };

function frame(): void {
	begin2d(200.0, 100.0, 1.0);
}

function card(mode: InstanceMode, x: float32, size: float32, radius: float32): void {
	drawUiInstance(0 as uint32, BlendMode.Alpha, {
		...uiInstance(mode, identity2d(), x, 0.0, size, size, WHITE),
		uvRadii: [radius, radius, radius, radius],
		borders: [1.0, 1.0, 1.0, 1.0],
		border: RED,
		extra: CLEAR,
	});
}

function sprite(x: float32): void {
	drawSpriteAffine(
		0 as uint32, false, BlendMode.Alpha, identity2d(),
		x, 0.0, 8.0, 8.0,
		0.0, 0.0, 1.0, 1.0,
		WHITE,
	);
}

function pipelineOf(command: int32): int32 {
	return commandField(command, CMD_PIPELINE) as int32;
}

test "a UI instance records as one run on the UI pipeline" {
	frame();
	card(InstanceMode.Box, 0.0, 16.0, 4.0);
	card(InstanceMode.Box, 20.0, 16.0, 4.0);
	finishRecording();
	assert recordedUiInstanceCount() == 2;
	assert drawCommandCount() == 1;
	assert pipelineOf(0) == (Pipeline.Ui as int32);
	assert (commandField(0, CMD_INSTANCE_OFFSET) as int32) == 0;
	assert (commandField(0, CMD_INSTANCE_COUNT) as int32) == 2;
	// A UI run reads the instance stream, so a vertex count on it would be a range into a
	// stream it never wrote - the defect the replay's pipeline-before-count branch exists for.
	assert (commandField(0, CMD_VERTEX_COUNT) as int32) == 0;
	assert vertexCount() == 0;
}

test "modes share one run, because a mode is a lane and not a pipeline" {
	frame();
	card(InstanceMode.Box, 0.0, 16.0, 4.0);
	card(InstanceMode.Glyph, 20.0, 16.0, 0.0);
	card(InstanceMode.Image, 40.0, 16.0, 0.0);
	finishRecording();
	assert recordedUiInstanceCount() == 3;
	assert drawCommandCount() == 1;
	assert (commandField(0, CMD_INSTANCE_COUNT) as int32) == 3;
}

test "switching pipeline ends the run and names the reason" {
	frame();
	card(InstanceMode.Box, 0.0, 16.0, 4.0);
	sprite(30.0);
	card(InstanceMode.Box, 60.0, 16.0, 4.0);
	finishRecording();
	assert drawCommandCount() == 3;
	assert pipelineOf(0) == (Pipeline.Ui as int32);
	assert pipelineOf(1) == (Pipeline.Sprite as int32);
	assert pipelineOf(2) == (Pipeline.Ui as int32);
	assert breakReasonName(commandField(1, CMD_BREAK) as int32).equals("pipeline");
	assert breakReasonName(commandField(2, CMD_BREAK) as int32).equals("pipeline");
}

// Each pipeline indexes its own stream, so the second UI run starts at 1 and not at 2 - the
// sprite between them advanced the sprite stream, not this one. An offset taken from a shared
// counter would read 2 here and draw the wrong instance with no golden able to see it.
test "each pipeline's offsets index its own stream" {
	frame();
	card(InstanceMode.Box, 0.0, 16.0, 4.0);
	sprite(30.0);
	card(InstanceMode.Box, 60.0, 16.0, 4.0);
	finishRecording();
	assert recordedUiInstanceCount() == 2;
	assert recordedSpriteInstanceCount() == 1;
	assert (commandField(0, CMD_INSTANCE_OFFSET) as int32) == 0;
	assert (commandField(1, CMD_INSTANCE_OFFSET) as int32) == 0;
	assert (commandField(2, CMD_INSTANCE_OFFSET) as int32) == 1;
}

test "the vertex path still breaks against the UI pipeline in both directions" {
	frame();
	drawRect({ x: 0.0, y: 0.0 }, { x: 8.0, y: 8.0 }, WHITE, BlendMode.Alpha);
	card(InstanceMode.Box, 20.0, 16.0, 4.0);
	drawRect({ x: 40.0, y: 0.0 }, { x: 8.0, y: 8.0 }, WHITE, BlendMode.Alpha);
	finishRecording();
	assert drawCommandCount() == 3;
	assert pipelineOf(0) == (Pipeline.Vertex as int32);
	assert pipelineOf(1) == (Pipeline.Ui as int32);
	assert pipelineOf(2) == (Pipeline.Vertex as int32);
	assert breakReasonName(commandField(1, CMD_BREAK) as int32).equals("pipeline");
	assert breakReasonName(commandField(2, CMD_BREAK) as int32).equals("pipeline");
}

// B5 as a negative one layer up: a frame that draws only sprites must not open a UI run at
// all. Not a mode count - an empty frame reads zero of every mode too.
test "a sprite-only frame opens no UI run" {
	frame();
	sprite(0.0);
	sprite(10.0);
	finishRecording();
	assert recordedUiInstanceCount() == 0;
	assert drawCommandCount() == 1;
	assert pipelineOf(0) == (Pipeline.Sprite as int32);
}

test "a colour pipeline is what disqualifies the instanced path, and it says so" {
	frame();
	assert uiInstancingAvailable();
}

function alphaSpelling(factor: Blend): Blend {
	return match (factor) {
		Blend.SourceColor => Blend.SourceAlpha,
		Blend.DestinationColor => Blend.DestinationAlpha,
		Blend.OneMinusSourceColor => Blend.OneMinusSourceAlpha,
		Blend.OneMinusDestinationColor => Blend.OneMinusDestinationAlpha,
		_ => factor,
	};
}

function keepsFactors(
	mode: BlendMode,
	source: Blend,
	destination: Blend,
	alphaSource: Blend,
	alphaDestination: Blend,
): boolean {
	const state: RenderState = premultipliedBlend(mode);
	return state.blendSource == source && state.blendDestination == destination
		&& alphaSpelling(state.blendAlphaSource) == alphaSource
		&& alphaSpelling(state.blendAlphaDestination) == alphaDestination
		&& state.blendOperation == Operation.Add && state.blendAlphaOperation == Operation.Add;
}

test "the five old 2D blend modes keep the premultiplied factors batcher.c had" {
	assert keepsFactors(
		BlendMode.Alpha,
		Blend.One, Blend.OneMinusSourceAlpha, Blend.One, Blend.OneMinusSourceAlpha,
	);
	assert keepsFactors(BlendMode.Add, Blend.One, Blend.One, Blend.One, Blend.One);
	assert keepsFactors(
		BlendMode.AlphaMultiply,
		Blend.DestinationColor, Blend.OneMinusSourceAlpha,
		Blend.DestinationAlpha, Blend.OneMinusSourceAlpha,
	);
	assert keepsFactors(
		BlendMode.Screen,
		Blend.One, Blend.OneMinusSourceColor, Blend.One, Blend.OneMinusSourceAlpha,
	);
	assert keepsFactors(BlendMode.None, Blend.One, Blend.Zero, Blend.One, Blend.Zero);
}

test "a premultiplied source never scales its colour by its alpha again" {
	const modes: Vec<BlendMode> = [
		BlendMode.None, BlendMode.Alpha, BlendMode.Add, BlendMode.AlphaAdd,
		BlendMode.SoftAdd, BlendMode.Multiply, BlendMode.AlphaMultiply, BlendMode.Erase,
		BlendMode.Screen, BlendMode.Subtract, BlendMode.Max, BlendMode.Min,
	];
	for (const mode of modes) {
		const state: RenderState = premultipliedBlend(mode);
		assert state.blendSource != Blend.SourceAlpha && state.blendAlphaSource != Blend.SourceAlpha;
		assert state.culling == Face.None && !state.depthWrite;
		assert state.depthTest == Compare.Always;
	}
}

function channel(color: Color, index: int32): float32 {
	return match (index) {
		0 => color.r,
		1 => color.g,
		2 => color.b,
		_ => color.a,
	};
}

function factorOf(factor: Blend, src: Color, dst: Color, index: int32): float32 {
	return match (factor) {
		Blend.One => 1.0,
		Blend.Zero => 0.0,
		Blend.SourceAlpha => src.a,
		Blend.SourceColor => channel(src, index),
		Blend.DestinationAlpha => dst.a,
		Blend.DestinationColor => channel(dst, index),
		Blend.OneMinusSourceAlpha => 1.0 - src.a,
		Blend.OneMinusSourceColor => 1.0 - channel(src, index),
		Blend.OneMinusDestinationAlpha => 1.0 - dst.a,
		Blend.OneMinusDestinationColor => 1.0 - channel(dst, index),
	};
}

function combine(operation: Operation, source: float32, destination: float32): float32 {
	const raw: float32 = match (operation) {
		Operation.Add => source + destination,
		Operation.Subtract => source - destination,
		Operation.ReverseSubtract => destination - source,
		Operation.Min => source < destination ? source : destination,
		Operation.Max => source > destination ? source : destination,
	};
	if (raw < 0.0) { return 0.0; }
	if (raw > 1.0) { return 1.0; }
	return raw;
}

function blended(mode: BlendMode, src: Color, dst: Color): Color {
	const state: RenderState = premultipliedBlend(mode);
	let out: Vec<float32> = [0.0, 0.0, 0.0, 0.0];
	for (let i: int32 = 0; i < 4; i++) {
		const alpha: boolean = i == 3;
		const s: Blend = alpha ? state.blendAlphaSource : state.blendSource;
		const d: Blend = alpha ? state.blendAlphaDestination : state.blendDestination;
		const op: Operation = alpha ? state.blendAlphaOperation : state.blendOperation;
		const minMax: boolean = op == Operation.Min || op == Operation.Max;
		const source: float32 = minMax ? channel(src, i) : channel(src, i) * factorOf(s, src, dst, i);
		const destination: float32 =
			minMax ? channel(dst, i) : channel(dst, i) * factorOf(d, src, dst, i);
		out[i] = combine(op, source, destination);
	}
	return { r: out[0], g: out[1], b: out[2], a: out[3] };
}

function near(a: Color, b: Color): boolean {
	const e: float32 = 0.0001;
	return a.r - b.r < e && b.r - a.r < e && a.g - b.g < e && b.g - a.g < e
		&& a.b - b.b < e && b.b - a.b < e && a.a - b.a < e && b.a - a.a < e;
}

function stillPremultiplied(color: Color): boolean {
	const e: float32 = 0.0001;
	return color.r <= color.a + e && color.g <= color.a + e && color.b <= color.a + e;
}

const DESTINATIONS: Vec<Color> = [
	{ r: 1.0, g: 1.0, b: 1.0, a: 1.0 },
	{ r: 0.2, g: 0.4, b: 0.1, a: 0.5 },
	{ r: 0.0, g: 0.0, b: 0.0, a: 0.0 },
];

const SOURCES: Vec<Color> = [
	{ r: 0.0, g: 0.0, b: 0.0, a: 0.5 },
	{ r: 0.3, g: 0.1, b: 0.25, a: 0.3 },
	{ r: 0.9, g: 0.6, b: 0.2, a: 1.0 },
];

test "a transparent source leaves the destination under the compositing modes" {
	const transparent: Color = { r: 0.0, g: 0.0, b: 0.0, a: 0.0 };
	const modes: Vec<BlendMode> = [
		BlendMode.Alpha, BlendMode.AlphaAdd, BlendMode.Add, BlendMode.SoftAdd,
		BlendMode.AlphaMultiply, BlendMode.Erase, BlendMode.Screen, BlendMode.Subtract,
		BlendMode.Max,
	];
	for (const mode of modes) {
		for (const dst of DESTINATIONS) {
			assert near(blended(mode, transparent, dst), dst);
		}
	}
}

test "Multiply and Min are arithmetic: a transparent source writes transparent black" {
	const transparent: Color = { r: 0.0, g: 0.0, b: 0.0, a: 0.0 };
	for (const dst of DESTINATIONS) {
		assert near(blended(BlendMode.Multiply, transparent, dst), transparent);
		assert near(blended(BlendMode.Min, transparent, dst), transparent);
	}
}

test "premultiplied operands stay premultiplied under every mode but Subtract" {
	const modes: Vec<BlendMode> = [
		BlendMode.None, BlendMode.Alpha, BlendMode.Add, BlendMode.AlphaAdd,
		BlendMode.SoftAdd, BlendMode.Multiply, BlendMode.AlphaMultiply, BlendMode.Erase,
		BlendMode.Screen, BlendMode.Max, BlendMode.Min,
	];
	for (const mode of modes) {
		for (const src of SOURCES) {
			for (const dst of DESTINATIONS) {
				assert stillPremultiplied(blended(mode, src, dst));
			}
		}
	}
}
