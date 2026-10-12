import { env } from "std/process";
import { Scene2D } from "./src/void2d/node";
import { add, paint, isDirty, close } from "./src/void2d/scene";
import { frameEnd } from "./src/void2d/draw";
import { glyphAtlas, labelTexts } from "./src/void2d/labelText";
import { dispose, cached, colourKey } from "./src/void2d/glyphAtlas";
import { addFont } from "./src/void2d/font";
import { rgba } from "./src/void2d/types";
import { retryColourArm, retryColourFailures, retryColourPngReason } from "./colourAllocFault.h";

function frame(s: Scene2D): void {
	s.paint(200.0, 120.0, 1.0);
	frameEnd();
	s.clearChanges();
	s.retryRefused();
}

function colourRecovery(path: string, stage: int32): boolean {
	glyphAtlas.dispose();
	defer glyphAtlas.dispose();
	const loaded = addFont(path);
	if (!loaded.ok) {
		console.log(`colour probe font failed: ${path}`);
		unreachable;
	}
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	defer s.close();
	const label = s.label("\u{1F600}", 16.0, rgba(1.0, 1.0, 1.0, 1.0)).setFont(loaded.value);
	const payload: int32 = s.payloads[label.id.index];
	s.add(label);
	retryColourArm(stage);
	frame(s);
	const failures: int32 = retryColourFailures();
	const incomplete: boolean = !labelTexts[payload].placedValid;
	const refused: int32 = labelTexts[payload].refused;
	const dirty: boolean = s.isDirty();
	const glyph = labelTexts[payload].layout.glyphs[0];
	const key = colourKey(glyph.face, glyph.glyph, glyph.size);
	const uncached: boolean = !glyphAtlas.cached(key);
	if (stage == 3) { console.log(`colour PNG reason: ${retryColourPngReason()}`); }
	console.log(`colour allocation stage ${stage}: failures=${failures} ` +
		`incomplete=${incomplete} refused=${refused} dirty=${dirty}`);
	if (dirty) { frame(s); }
	const recovered: boolean = labelTexts[payload].placedValid &&
		labelTexts[payload].placed.length == 1 && labelTexts[payload].colourGlyphs == 1;
	console.log(`colour allocation stage ${stage}: recovered=${recovered} dirty=${s.isDirty()}`);
	return failures == 1 && retryColourFailures() == 1 && incomplete && refused == 1 &&
		dirty && uncached && recovered && glyphAtlas.cached(key) && !s.isDirty();
}

test "colour layers recover after one coverage allocation fails" {
	assert colourRecovery("tests/fonts/colrSynthetic.ttf", 1);
}

test "colour bitmap conversion recovers after one source allocation fails" {
	assert colourRecovery("tests/fonts/sbixSynthetic.ttf", 2);
}

test "colour PNG decode recovers after one decode allocation fails" {
	assert colourRecovery("tests/fonts/sbixSynthetic.ttf", 3);
}

test "a malformed colour PNG stays incomplete without a memory retry loop" {
	glyphAtlas.dispose();
	defer glyphAtlas.dispose();
	const loaded = addFont(env.get("VOID_COLOUR_BAD_PNG"));
	assert loaded.ok;
	if (!loaded.ok) { return; }
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	defer s.close();
	const label = s.label("\u{1F600}", 16.0, rgba(1.0, 1.0, 1.0, 1.0)).setFont(loaded.value);
	const payload: int32 = s.payloads[label.id.index];
	s.add(label);
	retryColourArm(0);
	for (let i: int32 = 0; i < 4; i++) {
		frame(s);
		assert retryColourFailures() == 0;
		assert !labelTexts[payload].placedValid && labelTexts[payload].refused == 1;
		assert labelTexts[payload].placed.length == 0 && !s.isDirty();
	}
	console.log(`colour permanent PNG reason: ${retryColourPngReason()}, dirty=${s.isDirty()}`);
}
