import "../void2d/textOutlineSwitch";
import { add } from "../void2d/scene";
import { Scene2D, NodeRef } from "../void2d/node";
import { sync, draw, getBounds } from "../void2d/render";
import { begin2d, finishRecording, frameEnd } from "../void2d/draw";
import {
	commandCount, commandField, uiInstanceCount, uiInstanceField, vertexCount, CMD_PIPELINE,
	Pipeline,
} from "../void2d/displayList";
import { REC_UI_COLOR_FILL, REC_UI_FLOATS, REC_UI_PARAMS0 } from "../void2d/instanceLayout";
import { SDF_GLYPH_FLAG } from "../void2d/instance";
when (voidSdfText) {
	import { setSdfRegime } from "../void2d/labelText";
}
import { Bounds2D, Color, emptyBounds, identity2d, rgba } from "../void2d/types";

const WHITE = rgba(1.0, 1.0, 1.0, 1.0);
const RED = rgba(1.0, 0.0, 0.0, 1.0);
const CLEAR = rgba(1.0, 0.0, 0.0, 0.0);

function label(s: Scene2D, text: string, width: float32, color: Color): NodeRef {
	const n = s.label(text, 16.0, WHITE).at(20.0, 10.0);
	n.setOutline(width, color);
	return s.add(n);
}

function recordAt(root: NodeRef, node: float32, dpi: float32): void {
	begin2d(128.0, 64.0, dpi);
	root.sync(identity2d(), true);
	root.draw(node, 128.0, 64.0);
	finishRecording();
}

function record(root: NodeRef): void {
	recordAt(root, 1.0, 1.0);
}

function streamHash(): uint64 {
	let hash: uint64 = 1469598103934665603;
	for (let i: int32 = 0; i < uiInstanceCount(); i++) {
		for (let f: int32 = 0; f < REC_UI_FLOATS; f++) {
			const bits: uint64 = (uiInstanceField(i, f) * 4096.0) as int64 as uint64;
			hash = (hash ^ bits) * 1099511628211;
		}
	}
	return hash;
}

function greenAt(i: int32): float32 {
	return uiInstanceField(i, REC_UI_COLOR_FILL + 1);
}

function alphaAt(i: int32): float32 {
	return uiInstanceField(i, REC_UI_COLOR_FILL + 3);
}

test "an outlined label records its glyphs twice, every outline before every fill" {
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	record(label(s, "Flat", 2.0, RED));
	assert uiInstanceCount() == 8;
	for (let i: int32 = 0; i < 4; i++) {
		assert greenAt(i) == 0.0;
		assert greenAt(i + 4) == 1.0;
	}
	assert commandCount() == 1;
	frameEnd();
}

test "tight letter spacing still puts every outline under every fill" {
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	const n = label(s, "Tightly", 4.0, RED).setLetterSpacing(-3.0);
	record(n);
	assert uiInstanceCount() == 14;
	let seenFill: boolean = false;
	for (let i: int32 = 0; i < uiInstanceCount(); i++) {
		const outline: boolean = greenAt(i) == 0.0;
		if (!outline) { seenFill = true; }
		assert !(seenFill && outline);
	}
	assert seenFill;
	frameEnd();
}

test "the outline shares the fill's page so it costs no draw call" {
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	record(label(s, "Flat", 0.0, RED));
	const plain: int32 = commandCount();
	frameEnd();
	record(label(s, "Flat", 2.0, RED));
	assert commandCount() == plain;
	frameEnd();
}

test "a zero width and a clear colour record exactly the stream of a label with no outline" {
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	const bare = s.add(s.label("Flat", 16.0, WHITE).at(20.0, 10.0));
	record(bare);
	const want: uint64 = streamHash();
	const count: int32 = uiInstanceCount();
	frameEnd();
	record(label(s, "Flat", 0.0, RED));
	assert uiInstanceCount() == count && streamHash() == want;
	frameEnd();
	record(label(s, "Flat", 2.0, CLEAR));
	assert uiInstanceCount() == count && streamHash() == want;
	frameEnd();
}

test "the outline colour and the node alpha multiply, and the fill keeps its own" {
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	record(label(s, "Flat", 2.0, rgba(1.0, 0.0, 0.0, 0.5)));
	const full: float32 = alphaAt(0);
	frameEnd();
	recordAt(label(s, "Flat", 2.0, rgba(1.0, 0.0, 0.0, 0.5)), 0.5, 1.0);
	assert alphaAt(0) == full * 0.5;
	assert alphaAt(4) == 0.5;
	frameEnd();
}

test "a colour effect records the outline on the vertex program beside the fill" {
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	const n = label(s, "Flat", 2.0, RED).setColorAdd(rgba(0.2, 0.0, 0.0, 0.0));
	record(n);
	assert uiInstanceCount() == 0;
	assert commandCount() == 1;
	assert commandField(0, CMD_PIPELINE) == ((Pipeline.Vertex as int32) as float32);
	assert vertexCount() == 48;
	frameEnd();
}

when (voidSprites) {
	test "a sprite glyph is recorded once, without an outline" {
		const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
		record(label(s, "a\u{2588}", 2.0, RED));
		assert uiInstanceCount() == 3;
		frameEnd();
	}
}

test "the outline grows the cull reach and leaves the queried bounds alone" {
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	const bare = s.add(s.label("Flat", 16.0, WHITE).at(20.0, 10.0));
	record(bare);
	const plain: Bounds2D = s.culls[bare.id.index];
	let plainQuery: Bounds2D = emptyBounds();
	bare.getBounds(plainQuery);
	frameEnd();
	const outlined = label(s, "Flat", 3.0, RED);
	record(outlined);
	const reach: Bounds2D = s.culls[outlined.id.index];
	let query: Bounds2D = emptyBounds();
	outlined.getBounds(query);
	assert reach.xMin <= plain.xMin - 3.0 && reach.yMin <= plain.yMin - 3.0;
	assert reach.xMax >= plain.xMax + 3.0 && reach.yMax >= plain.yMax + 3.0;
	assert query.xMin == plainQuery.xMin && query.xMax == plainQuery.xMax;
	assert query.yMin == plainQuery.yMin && query.yMax == plainQuery.yMax;
	frameEnd();
}

test "a later frame follows a change of width and colour on the same label" {
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	const n = label(s, "Flat", 2.0, RED);
	record(n);
	assert uiInstanceCount() == 8;
	assert greenAt(0) == 0.0;
	frameEnd();
	n.setOutline(2.0, rgba(0.0, 1.0, 0.0, 1.0));
	record(n);
	assert uiInstanceCount() == 8;
	assert greenAt(0) == 1.0 && uiInstanceField(0, REC_UI_COLOR_FILL) == 0.0;
	frameEnd();
	n.setOutline(0.0, RED);
	record(n);
	assert uiInstanceCount() == 4;
	frameEnd();
	n.setOutline(3.0, RED);
	record(n);
	assert uiInstanceCount() == 8;
	frameEnd();
}

test "an outline reaching into the viewport keeps a label whose body is left of it" {
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	const bare = s.add(s.label("I", 16.0, WHITE).at(-14.0, 10.0));
	record(bare);
	assert uiInstanceCount() == 0;
	frameEnd();
	const near = s.label("I", 16.0, WHITE).at(-14.0, 10.0);
	near.setOutline(6.0, RED);
	record(s.add(near));
	assert uiInstanceCount() == 0;
	frameEnd();
	const reaching = s.label("I", 16.0, WHITE).at(-14.0, 10.0);
	reaching.setOutline(14.0, RED);
	record(s.add(reaching));
	assert uiInstanceCount() == 2;
	frameEnd();
}

when (voidSdfText) {
	function flagged(i: int32): boolean {
		return uiInstanceField(i, REC_UI_PARAMS0 + 1) == SDF_GLYPH_FLAG;
	}

	test "a turned outlined label records its outlines and fills as SDF glyphs, outlines first" {
		setSdfRegime(true);
		defer setSdfRegime(false);
		const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
		const n = label(s, "Turned", 2.0, RED).setRotation(0.5);
		record(n);
		assert uiInstanceCount() == 12;
		for (let i: int32 = 0; i < 12; i++) {
			assert flagged(i);
			assert (greenAt(i) == 0.0) == (i < 6);
		}
		assert commandCount() == 1;
		frameEnd();
	}

	test "a zoomed outlined label draws the same tiles at four times the size" {
		setSdfRegime(true);
		defer setSdfRegime(false);
		const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
		const n = label(s, "Zoom", 2.0, RED).setScale(4.0);
		record(n);
		assert uiInstanceCount() == 8;
		assert uiInstanceField(0, 0) == 4.0;
		frameEnd();
	}
}
