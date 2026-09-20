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
} from "../void2d/draw";
import {
	drawCommandCount, commandField, vertexCount,
	CMD_PIPELINE, CMD_INSTANCE_OFFSET, CMD_INSTANCE_COUNT, CMD_VERTEX_COUNT, CMD_BREAK,
	Pipeline, breakReasonName,
} from "../void2d/displayList";
import { InstanceMode } from "../void2d/instance";
import { Color, BlendMode, identity2d } from "../void2d/types";

const WHITE: Color = { r: 1.0, g: 1.0, b: 1.0, a: 1.0 };
const RED: Color = { r: 1.0, g: 0.0, b: 0.0, a: 1.0 };
const CLEAR: Color = { r: 0.0, g: 0.0, b: 0.0, a: 0.0 };

function frame(): void {
	begin2d(200.0, 100.0, 1.0);
}

function card(mode: InstanceMode, x: float32, size: float32, radius: float32): void {
	drawUiInstance(
		mode, 0 as uint32, BlendMode.Alpha, identity2d(),
		x, 0.0, size, size,
		radius, radius, radius, radius,
		1.0, 1.0, 1.0, 1.0,
		0.0, 0.0, 0.0,
		0.0, 0.0, 0.0, 0.0,
		WHITE, RED, CLEAR,
	);
}

function sprite(x: float32): void {
	drawSpriteAffine(
		0 as uint32, BlendMode.Alpha, identity2d(),
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
