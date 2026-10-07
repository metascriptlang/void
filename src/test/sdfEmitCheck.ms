import { add } from "../void2d/scene";
import { Scene2D, NodeRef } from "../void2d/node";
import { sync, draw } from "../void2d/render";
import { begin2d, finishRecording, frameEnd, setSceneSmooth } from "../void2d/draw";
import {
	commandCount, commandField, uiInstanceCount, uiInstanceField, vertexCount,
	CMD_PIPELINE, CMD_SAMPLER, Pipeline,
} from "../void2d/displayList";
import { REC_UI_AFFINE, REC_UI_PARAMS0 } from "../void2d/instanceLayout";
import { InstanceMode, SDF_GLYPH_FLAG } from "../void2d/instance";
import { setSdfRegime } from "../void2d/labelText";
import { identity2d, rgba } from "../void2d/types";

const GLYPH_MODE: float32 = (InstanceMode.Glyph as int32) as float32;

function recordAt(label: (s: Scene2D) => NodeRef, smooth: boolean, dpi: float32): void {
	setSceneSmooth(smooth);
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	const root = label(s);
	begin2d(128.0, 64.0, dpi);
	root.sync(identity2d(), true);
	root.draw(1.0, 128.0, 64.0);
	finishRecording();
}

function record(label: (s: Scene2D) => NodeRef, smooth: boolean): void {
	recordAt(label, smooth, 1.0);
}

function turned(s: Scene2D): NodeRef {
	return s.add(s.label("Turned", 16.0, rgba(1.0, 1.0, 1.0, 1.0)).at(20.0, 10.0).setRotation(0.5));
}

function zoomed(s: Scene2D): NodeRef {
	const label = s.label("Zoomed", 16.0, rgba(1.0, 1.0, 1.0, 1.0)).at(4.0, 4.0);
	return s.add(label.setScaleX(3.0).setScaleY(3.0));
}

function flat(s: Scene2D): NodeRef {
	return s.add(s.label("Flat", 16.0, rgba(1.0, 1.0, 1.0, 1.0)).at(8.0, 8.0));
}

function noisy(s: Scene2D): NodeRef {
	const label = s.label("Noisy", 16.0, rgba(1.0, 1.0, 1.0, 1.0)).at(8.0, 8.0);
	return s.add(label.setScaleX(0.99999994).setScaleY(1.00000012));
}

function tinted(s: Scene2D): NodeRef {
	return turned(s).setColorAdd(rgba(0.2, 0.0, 0.0, 0.0));
}

function glyphInstances(): int32 {
	let count: int32 = 0;
	for (let i: int32 = 0; i < uiInstanceCount(); i++) {
		if (uiInstanceField(i, REC_UI_PARAMS0) == GLYPH_MODE) { count = count + 1; }
	}
	return count;
}

function flaggedGlyphs(): int32 {
	let count: int32 = 0;
	for (let i: int32 = 0; i < uiInstanceCount(); i++) {
		if (uiInstanceField(i, REC_UI_PARAMS0) != GLYPH_MODE) { continue; }
		if (uiInstanceField(i, REC_UI_PARAMS0 + 1) == SDF_GLYPH_FLAG) { count = count + 1; }
	}
	return count;
}

test "every glyph of a rotated label carries the SDF flag and the world affine" {
	setSdfRegime(true);
	defer setSdfRegime(false);
	record(turned, true);
	const glyphs = glyphInstances();
	assert glyphs == 6;
	assert flaggedGlyphs() == glyphs;
	for (let i: int32 = 0; i < uiInstanceCount(); i++) {
		assert uiInstanceField(i, REC_UI_AFFINE + 1) != 0.0;
	}
	frameEnd();
}

test "every glyph of a zoomed label carries the SDF flag and the zoom in its affine" {
	setSdfRegime(true);
	defer setSdfRegime(false);
	record(zoomed, true);
	const glyphs = glyphInstances();
	assert glyphs == 6;
	assert flaggedGlyphs() == glyphs;
	assert uiInstanceField(0, REC_UI_AFFINE) == 3.0;
	frameEnd();
}

test "a label at translation and DPI carries no SDF flag" {
	setSdfRegime(true);
	defer setSdfRegime(false);
	record(flat, true);
	assert glyphInstances() == 4;
	assert flaggedGlyphs() == 0;
	frameEnd();
}

test "with the regime off a rotated label carries no SDF flag" {
	setSdfRegime(false);
	record(turned, true);
	assert glyphInstances() == 6;
	assert flaggedGlyphs() == 0;
	frameEnd();
}

test "an SDF label samples linearly whatever the scene's smoothing" {
	setSdfRegime(true);
	defer setSdfRegime(false);
	record(turned, false);
	assert commandCount() == 1;
	assert commandField(0, CMD_SAMPLER) == 2.0;
	assert flaggedGlyphs() == 6;
	frameEnd();
	setSceneSmooth(true);
}

test "a label at identity plus float noise stays pixel exact and unflagged" {
	setSdfRegime(true);
	defer setSdfRegime(false);
	record(noisy, true);
	assert glyphInstances() == 5;
	assert flaggedGlyphs() == 0;
	frameEnd();
}

test "a rotated label at DPI 2 is flagged and places by the world affine alone" {
	setSdfRegime(true);
	defer setSdfRegime(false);
	recordAt(turned, true, 2.0);
	assert glyphInstances() == 6;
	assert flaggedGlyphs() == 6;
	assert uiInstanceField(0, REC_UI_AFFINE + 1) != 0.0;
	frameEnd();
}

test "a rotated label under a colour add records on the vertex program, one run" {
	setSdfRegime(true);
	defer setSdfRegime(false);
	record(tinted, true);
	assert uiInstanceCount() == 0;
	assert commandCount() == 1;
	assert commandField(0, CMD_PIPELINE) == ((Pipeline.Vertex as int32) as float32);
	assert vertexCount() == 36;
	frameEnd();
}
