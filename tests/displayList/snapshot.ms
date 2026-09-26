// T1 - the display list is assertable with no GPU (docs/TESTING.md "T1").
//
// Every claim in VOID2D.md "Frame shape" and "Order and batching" is a statement about a POD
// stream, not about pixels. Recorded as data it is assertable in `msc test`, in milliseconds,
// on every platform - and it is the only tier that can assert a *negative*: that nothing was
// uploaded, that no pass was opened, that a subtree contributed no vertices.
//
// **No GPU is touched here.** The tree walk records and stops; `finishRecording` closes the
// open run, and the replay - the one part that needs a device - is never called. That is not
// a trick: `void2dWhiteView()` on an unset batcher returns 0, `void2dFrameBegin` only resets
// statics, and nothing else on the recording path calls sokol. What it costs is that a scene
// needing a real resource cannot appear here: a filter allocates a render target and text
// needs a fontstash context, so neither is in a snapshot. Target ordering and nesting are
// asserted directly in `src/void2d/displayList.ms` instead, where they need no scene at all.
//
// A snapshot is regenerated with `VOID_SNAPSHOT=1` on the same run that compares, so the two
// can never drift apart (rexa's shape, `vim_spec.rs:855-857`).

import { readFile, writeFile, ensureDir } from "std/fs";
import { env } from "std/process";
import { GLYPH_PAGE_SIZE } from "../../src/void2d/glyphAtlas";
import { scene, add } from "../../src/void2d/scene";
import {
	Node2D, rect, mask, at, addChild, setBoxStyle, setImageStyle, label, graphics, sprite,
	underline, selection,
} from "../../src/void2d/node";
import { sync, draw, labelEditingRefusals } from "../../src/void2d/render";
import {
	begin2d,
	beginTarget,
	endTarget,
	finishRecording,
	frameEnd,
	uploadCount,
	growthTarget,
	currentRenderScale,
	setSceneSmooth,
} from "../../src/void2d/draw";
import {
	commandCount, targetCommandCount, effectCount, vertexCount, drawCommandCount,
	commandField, targetCommandField, effectField, vertexField,
	CMD_KIND, CMD_BREAK, CMD_VERTEX_OFFSET, CMD_VERTEX_COUNT, CMD_VIEW, CMD_BLEND,
	CMD_SAMPLER, CMD_EFFECT, CMD_CLIP_X, CMD_CLIP_Y, CMD_CLIP_W, CMD_CLIP_H, CMD_RT_MODE,
	CMD_CLIP_U_X, CMD_CLIP_U_Y, CMD_CLIP_U_MIN, CMD_CLIP_U_MAX,
	CMD_CLIP_V_X, CMD_CLIP_V_Y, CMD_CLIP_V_MIN, CMD_CLIP_V_MAX,
	EFFECT_GRADIENT_META, EFFECT_GRADIENT_PARAMS, EFFECT_GRADIENT_COLOR0,
	EFFECT_GRADIENT_COLOR1, EFFECT_GRADIENT_COLOR2,
	commandKindName, breakReasonName,
	Pipeline, BreakReason, CMD_PIPELINE, CMD_INSTANCE_OFFSET, CMD_INSTANCE_COUNT,
	uiInstanceCount, spriteInstanceCount, spriteInstanceField, uiInstanceField,
} from "../../src/void2d/displayList";
import {
	REC_SPRITE_AFFINE, REC_SPRITE_ORIGIN_SIZE, REC_SPRITE_UV, REC_SPRITE_COLOR,
	REC_UI_AFFINE, REC_UI_ORIGIN_SIZE, REC_UI_UV_RADII, REC_UI_BORDERS, REC_UI_PARAMS0, REC_UI_PARAMS1,
	REC_UI_COLOR_FILL, REC_UI_COLOR_BORDER, REC_UI_FLOATS, InstanceMode,
} from "../../src/void2d/instance";
import { rgba, tile, identity2d, emptyBounds, BlendMode, Smooth } from "../../src/void2d/types";
import { CURSOR_WIDTH } from "../../src/void2d/labelText";
import { TextLayout } from "../../src/void2d/textLayout";
import { BoxStyle, uniformRadii, uniformBorders } from "../../src/void2d/boxStyle";
import {
	fillRect, fillGradientRectOklab, fillGradientRectStops, fillSlashRect, fillCheckerRect,
} from "../../src/void2d/graphics";
import { colorMatrixGrayscale } from "../../src/void2d/effect";
import { GradientSpace } from "../../src/void2d/gradient";
import { ObjectFit, imageStyle } from "../../src/void2d/imageStyle";
import { approx } from "../../src/test/helpers";

const SNAPSHOT_DIR: string = "tests/displayList";

// Fixed precision, because a snapshot that moves when a float prints differently cries wolf.
function f2(v: float32): string {
	const d: float64 = v as float64;
	const scaled: int32 = (d * 100.0 + (d >= 0.0 ? 0.5 : -0.5)) as int32;
	const whole: int32 = scaled / 100;
	let frac: int32 = scaled % 100;
	if (frac < 0) { frac = -frac; }
	const pad: string = frac < 10 ? "0" : "";
	return `${whole}.${pad}${frac}`;
}

// One line per command, then one per vertex. The break reason is a word and not a number: a
// regression then names its own cause instead of leaving a count to be explained.
function formatStream(): string {
	let out: string = "";
	out = out + `commands ${commandCount()} draws ${drawCommandCount()}`
		+ ` vertices ${vertexCount()} uiInstances ${uiInstanceCount()}`
		+ ` spriteInstances ${spriteInstanceCount()}` + "\n";
	for (let i: int32 = 0; i < commandCount(); i++) {
		const kind: string = commandKindName(commandField(i, CMD_KIND) as int32);
		const why: string = breakReasonName(commandField(i, CMD_BREAK) as int32);
		out = out + `cmd ${i} ${kind} break:${why}`;
		out = out + ` view:${commandField(i, CMD_VIEW) as int32}`;
		out = out + ` blend:${commandField(i, CMD_BLEND) as int32}`;
		out = out + ` sampler:${commandField(i, CMD_SAMPLER) as int32}`;
		out = out + ` effect:${commandField(i, CMD_EFFECT) as int32}`;
		out = out + ` rt:${commandField(i, CMD_RT_MODE) as int32}`;
		// A run reads ONE stream, so the line names which and prints only that range.
		// Printing `verts:0+0` for an instanced run is how a snapshot stops being able to fail.
		if ((commandField(i, CMD_PIPELINE) as int32) == (Pipeline.Sprite as int32)) {
			out = out + ` pipe:sprite inst:${commandField(i, CMD_INSTANCE_OFFSET) as int32}`
				+ `+${commandField(i, CMD_INSTANCE_COUNT) as int32}`;
		} else if ((commandField(i, CMD_PIPELINE) as int32) == (Pipeline.Ui as int32)) {
			out = out + ` pipe:ui inst:${commandField(i, CMD_INSTANCE_OFFSET) as int32}`
				+ `+${commandField(i, CMD_INSTANCE_COUNT) as int32}`;
		} else {
			out = out + ` pipe:vertex verts:${commandField(i, CMD_VERTEX_OFFSET) as int32}`
				+ `+${commandField(i, CMD_VERTEX_COUNT) as int32}`;
		}
		out = out + ` clip:${f2(commandField(i, CMD_CLIP_X))},${f2(commandField(i, CMD_CLIP_Y))},${f2(commandField(i, CMD_CLIP_W))},${f2(commandField(i, CMD_CLIP_H))}`;
		if (commandField(i, CMD_CLIP_U_MAX) > commandField(i, CMD_CLIP_U_MIN)) {
			out = out + ` edges:${f2(commandField(i, CMD_CLIP_U_X))},${f2(commandField(i, CMD_CLIP_U_Y))}`;
			out = out + `,${f2(commandField(i, CMD_CLIP_U_MIN))},${f2(commandField(i, CMD_CLIP_U_MAX))}`;
			out = out + ` ${f2(commandField(i, CMD_CLIP_V_X))},${f2(commandField(i, CMD_CLIP_V_Y))}`;
			out = out + `,${f2(commandField(i, CMD_CLIP_V_MIN))},${f2(commandField(i, CMD_CLIP_V_MAX))}`;
		}
		out = out + "\n";
	}
	for (let i: int32 = 0; i < effectCount(); i++) {
		const kind: int32 = effectField(i, EFFECT_GRADIENT_META) as int32;
		if (kind == 0) { continue; }
		out = out + `fx ${i} gradient:${kind}`;
		out = out + ` space:${effectField(i, EFFECT_GRADIENT_META + 1) as int32}`;
		out = out + ` dither:${effectField(i, EFFECT_GRADIENT_META + 2) as int32}`;
		out = out + ` middle:${f2(effectField(i, EFFECT_GRADIENT_META + 3))}`;
		out = out + ` params:${f2(effectField(i, EFFECT_GRADIENT_PARAMS))}`;
		out = out + `,${f2(effectField(i, EFFECT_GRADIENT_PARAMS + 1))}`;
		out = out + `,${f2(effectField(i, EFFECT_GRADIENT_PARAMS + 2))}`;
		out = out + `,${f2(effectField(i, EFFECT_GRADIENT_PARAMS + 3))}`;
		out = out + ` c0:${f2(effectField(i, EFFECT_GRADIENT_COLOR0))}`;
		out = out + `,${f2(effectField(i, EFFECT_GRADIENT_COLOR0 + 1))}`;
		out = out + `,${f2(effectField(i, EFFECT_GRADIENT_COLOR0 + 2))}`;
		out = out + `,${f2(effectField(i, EFFECT_GRADIENT_COLOR0 + 3))}`;
		out = out + ` c1:${f2(effectField(i, EFFECT_GRADIENT_COLOR1))}`;
		out = out + `,${f2(effectField(i, EFFECT_GRADIENT_COLOR1 + 1))}`;
		out = out + `,${f2(effectField(i, EFFECT_GRADIENT_COLOR1 + 2))}`;
		out = out + `,${f2(effectField(i, EFFECT_GRADIENT_COLOR1 + 3))}`;
		out = out + ` c2:${f2(effectField(i, EFFECT_GRADIENT_COLOR2))}`;
		out = out + `,${f2(effectField(i, EFFECT_GRADIENT_COLOR2 + 1))}`;
		out = out + `,${f2(effectField(i, EFFECT_GRADIENT_COLOR2 + 2))}`;
		out = out + `,${f2(effectField(i, EFFECT_GRADIENT_COLOR2 + 3))}`;
		out = out + "\n";
	}
	for (let i: int32 = 0; i < vertexCount(); i++) {
		out = out + `v ${i} ${f2(vertexField(i, 0))} ${f2(vertexField(i, 1))}`;
		out = out + ` uv ${f2(vertexField(i, 2))} ${f2(vertexField(i, 3))}`;
		out = out + ` rgba ${f2(vertexField(i, 4))} ${f2(vertexField(i, 5))} ${f2(vertexField(i, 6))} ${f2(vertexField(i, 7))}`;
		out = out + "\n";
	}
	// One line per UI instance, and it prints the mode: P2's whole thesis is that a card, a
	// label and an image differ by one float in one stream, so the float that says which is
	// the one a snapshot must not leave out.
	for (let i: int32 = 0; i < uiInstanceCount(); i++) {
		out = out + `u ${i} mode ${uiInstanceField(i, REC_UI_PARAMS0) as int32}`;
		out = out + ` affine`;
		out = out + ` ${f2(uiInstanceField(i, REC_UI_AFFINE))}`;
		out = out + ` ${f2(uiInstanceField(i, REC_UI_AFFINE + 1))}`;
		out = out + ` ${f2(uiInstanceField(i, REC_UI_AFFINE + 2))}`;
		out = out + ` ${f2(uiInstanceField(i, REC_UI_AFFINE + 3))}`;
		out = out + ` at`;
		out = out + ` ${f2(uiInstanceField(i, REC_UI_ORIGIN_SIZE))}`;
		out = out + ` ${f2(uiInstanceField(i, REC_UI_ORIGIN_SIZE + 1))}`;
		out = out + ` size`;
		out = out + ` ${f2(uiInstanceField(i, REC_UI_ORIGIN_SIZE + 2))}`;
		out = out + ` ${f2(uiInstanceField(i, REC_UI_ORIGIN_SIZE + 3))}`;
		if (uiInstanceField(i, REC_UI_PARAMS0) as int32 == InstanceMode.Glyph as int32) {
			// A glyph's UV is where the atlas happened to pack it, which depends on every
			// label the process shaped before; its extent in texels is what the display list owns.
			const page: float32 = GLYPH_PAGE_SIZE as float32;
			const u0: float32 = uiInstanceField(i, REC_UI_UV_RADII);
			const v0: float32 = uiInstanceField(i, REC_UI_UV_RADII + 1);
			const u1: float32 = uiInstanceField(i, REC_UI_UV_RADII + 2);
			const v1: float32 = uiInstanceField(i, REC_UI_UV_RADII + 3);
			out = out + ` tile ${f2((u1 - u0) * page)} ${f2((v1 - v0) * page)}`;
		} else {
			out = out + ` uvr`;
			out = out + ` ${f2(uiInstanceField(i, REC_UI_UV_RADII))}`;
			out = out + ` ${f2(uiInstanceField(i, REC_UI_UV_RADII + 1))}`;
			out = out + ` ${f2(uiInstanceField(i, REC_UI_UV_RADII + 2))}`;
			out = out + ` ${f2(uiInstanceField(i, REC_UI_UV_RADII + 3))}`;
		}
		out = out + ` border`;
		out = out + ` ${f2(uiInstanceField(i, REC_UI_BORDERS))}`;
		out = out + ` ${f2(uiInstanceField(i, REC_UI_BORDERS + 1))}`;
		out = out + ` ${f2(uiInstanceField(i, REC_UI_BORDERS + 2))}`;
		out = out + ` ${f2(uiInstanceField(i, REC_UI_BORDERS + 3))}`;
		// The two param lanes are where a mode's meaning lives - the shadow's half extents
		// and blur in one, its offset in the other - and a lane swap here is invisible to
		// every other field. The offset-lane swap shipped a golden whose shadow hugged the
		// box un-offset; this line is what makes the next one a snapshot diff.
		out = out + ` params`;
		out = out + ` ${f2(uiInstanceField(i, REC_UI_PARAMS0 + 1))}`;
		out = out + ` ${f2(uiInstanceField(i, REC_UI_PARAMS0 + 2))}`;
		out = out + ` ${f2(uiInstanceField(i, REC_UI_PARAMS0 + 3))}`;
		out = out + ` ${f2(uiInstanceField(i, REC_UI_PARAMS1))}`;
		out = out + ` ${f2(uiInstanceField(i, REC_UI_PARAMS1 + 1))}`;
		out = out + ` ${f2(uiInstanceField(i, REC_UI_PARAMS1 + 2))}`;
		out = out + ` ${f2(uiInstanceField(i, REC_UI_PARAMS1 + 3))}`;
		out = out + ` fill`;
		out = out + ` ${f2(uiInstanceField(i, REC_UI_COLOR_FILL))}`;
		out = out + ` ${f2(uiInstanceField(i, REC_UI_COLOR_FILL + 1))}`;
		out = out + ` ${f2(uiInstanceField(i, REC_UI_COLOR_FILL + 2))}`;
		out = out + ` ${f2(uiInstanceField(i, REC_UI_COLOR_FILL + 3))}`;
		out = out + ` edge`;
		out = out + ` ${f2(uiInstanceField(i, REC_UI_COLOR_BORDER))}`;
		out = out + ` ${f2(uiInstanceField(i, REC_UI_COLOR_BORDER + 1))}`;
		out = out + ` ${f2(uiInstanceField(i, REC_UI_COLOR_BORDER + 2))}`;
		out = out + ` ${f2(uiInstanceField(i, REC_UI_COLOR_BORDER + 3))}`;
		out = out + "\n";
	}
	for (let i: int32 = 0; i < spriteInstanceCount(); i++) {
		out = out + `s ${i}`;
		out = out + ` affine`;
		out = out + ` ${f2(spriteInstanceField(i, REC_SPRITE_AFFINE))}`;
		out = out + ` ${f2(spriteInstanceField(i, REC_SPRITE_AFFINE + 1))}`;
		out = out + ` ${f2(spriteInstanceField(i, REC_SPRITE_AFFINE + 2))}`;
		out = out + ` ${f2(spriteInstanceField(i, REC_SPRITE_AFFINE + 3))}`;
		out = out + ` at`;
		out = out + ` ${f2(spriteInstanceField(i, REC_SPRITE_ORIGIN_SIZE))}`;
		out = out + ` ${f2(spriteInstanceField(i, REC_SPRITE_ORIGIN_SIZE + 1))}`;
		out = out + ` size`;
		out = out + ` ${f2(spriteInstanceField(i, REC_SPRITE_ORIGIN_SIZE + 2))}`;
		out = out + ` ${f2(spriteInstanceField(i, REC_SPRITE_ORIGIN_SIZE + 3))}`;
		out = out + ` uv`;
		out = out + ` ${f2(spriteInstanceField(i, REC_SPRITE_UV))}`;
		out = out + ` ${f2(spriteInstanceField(i, REC_SPRITE_UV + 1))}`;
		out = out + ` ${f2(spriteInstanceField(i, REC_SPRITE_UV + 2))}`;
		out = out + ` ${f2(spriteInstanceField(i, REC_SPRITE_UV + 3))}`;
		out = out + ` rgba`;
		out = out + ` ${f2(spriteInstanceField(i, REC_SPRITE_COLOR))}`;
		out = out + ` ${f2(spriteInstanceField(i, REC_SPRITE_COLOR + 1))}`;
		out = out + ` ${f2(spriteInstanceField(i, REC_SPRITE_COLOR + 2))}`;
		out = out + ` ${f2(spriteInstanceField(i, REC_SPRITE_COLOR + 3))}`;
		out = out + "\n";
	}
	return out;
}

// Record one scene and stop. No pass is opened and no upload happens, which is the point.
function record(root: Node2D, w: float32, h: float32, dpi: float32): string {
	setSceneSmooth(true);
	begin2d(w, h, dpi);
	root.sync(identity2d(), true);
	root.draw(1.0, w, h);
	finishRecording();
	const text: string = formatStream();
	frameEnd();
	return text;
}

test "scene smoothing seeds the first run before recording begins" {
	setSceneSmooth(false);
	const root = rect(8.0, 8.0, rgba(1.0, 1.0, 1.0, 1.0));
	begin2d(16.0, 16.0, 1.0);
	root.sync(identity2d(), true);
	root.draw(1.0, 16.0, 16.0);
	finishRecording();
	assert commandCount() == 1;
	assert commandField(0, CMD_BREAK) == (BreakReason.First as int32) as float32;
	assert commandField(0, CMD_SAMPLER) == 0.0;
	frameEnd();
	setSceneSmooth(true);
}

function snapshot(name: string, actual: string): boolean {
	const path: string = `${SNAPSHOT_DIR}/${name}.txt`;
	if (env.get("VOID_SNAPSHOT").equals("1")) {
		ensureDir(SNAPSHOT_DIR);
		writeFile(path, actual);
		console.log(`SNAPSHOT wrote ${path}`);
		return true;
	}
	const stored = readFile(path);
	if (!stored.ok) {
		console.log(`FAIL ${path} is missing - run with VOID_SNAPSHOT=1 to write it`);
		return false;
	}
	if (stored.value.equals(actual)) { return true; }
	console.log(`FAIL ${path} differs from what the tree recorded`);
	const want = stored.value.split("\n");
	const got = actual.split("\n");
	const n: int32 = (want.length as int32) > (got.length as int32)
		? want.length as int32
		: got.length as int32;
	let shown: int32 = 0;
	for (let i: int32 = 0; i < n && shown < 8; i++) {
		const a: string = i < (want.length as int32) ? want[i] : "<missing>";
		const b: string = i < (got.length as int32) ? got[i] : "<missing>";
		if (a.equals(b)) { continue; }
		console.log(`  line ${i} stored: ${a}`);
		console.log(`  line ${i} now:    ${b}`);
		shown = shown + 1;
	}
	return false;
}

// ===== the scenes =====

// Painter order: three siblings and a child, drawn in array order, each a later range in one
// shared vertex stream. A reordering shows up as the ranges swapping.
function orderScene(): Node2D {
	const s = scene(rgba(0.0, 0.0, 0.0, 1.0));
	s.add(rect(10.0, 10.0, rgba(1.0, 0.0, 0.0, 1.0)).at(0.0, 0.0));
	const middle = s.add(rect(10.0, 10.0, rgba(0.0, 1.0, 0.0, 1.0)).at(20.0, 0.0));
	middle.addChild(rect(4.0, 4.0, rgba(0.0, 0.0, 1.0, 1.0)).at(1.0, 1.0));
	s.add(rect(10.0, 10.0, rgba(1.0, 1.0, 0.0, 1.0)).at(40.0, 0.0));
	return s.root;
}

// One batch per reason: the same geometry with one piece of state different each time, so
// every command in the snapshot carries a `break:` word.
//
// A limit of that field the snapshot makes visible: `cmd 2` reads `break:blend` although the
// first thing to change for that node was its sampler. `emitNode` calls `setSampler` before
// `useState`, so two state changes land back to back with no vertex between them; the run the
// first one opened is empty, `closeRun` records nothing for it, and the reason that survives
// is the *last* cause rather than the first. The field is therefore "a reason", not "the only
// reason" - enough to name a regression, not enough to conclude from alone.
function breaksScene(): Node2D {
	const s = scene(rgba(0.0, 0.0, 0.0, 1.0));
	s.add(rect(8.0, 8.0, rgba(1.0, 0.0, 0.0, 1.0)).at(0.0, 0.0));
	const added = s.add(rect(8.0, 8.0, rgba(0.0, 1.0, 0.0, 1.0)).at(10.0, 0.0));
	added.blend = BlendMode.Add;
	const nearest = s.add(rect(8.0, 8.0, rgba(0.0, 0.0, 1.0, 1.0)).at(20.0, 0.0));
	nearest.smooth = Smooth.Off;
	const wrapped = s.add(rect(8.0, 8.0, rgba(1.0, 1.0, 0.0, 1.0)).at(30.0, 0.0));
	wrapped.tileWrap = true;
	const firstView = s.add(sprite(tile(11, 8.0, 8.0)).at(40.0, 0.0));
	firstView.smooth = Smooth.On;
	const secondView = s.add(sprite(tile(12, 8.0, 8.0)).at(50.0, 0.0));
	secondView.smooth = Smooth.On;
	return s.root;
}

// A Mask records a scissor, its children inherit it, and the clip is given back afterwards.
function clipScene(): Node2D {
	const s = scene(rgba(0.0, 0.0, 0.0, 1.0));
	s.add(rect(6.0, 6.0, rgba(1.0, 0.0, 0.0, 1.0)).at(0.0, 0.0));
	const m = mask(24.0, 16.0).at(10.0, 4.0);
	m.addChild(rect(40.0, 40.0, rgba(0.0, 1.0, 0.0, 1.0)).at(0.0, 0.0));
	s.add(m);
	s.add(rect(6.0, 6.0, rgba(0.0, 0.0, 1.0, 1.0)).at(60.0, 0.0));
	return s.root;
}
function rotatedClipScene(): Node2D {
	const s = scene(rgba(0.0, 0.0, 0.0, 1.0));
	const m = mask(40.0, 24.0).at(44.0, 24.0);
	m.pivotX = 20.0;
	m.pivotY = 12.0;
	m.rotation = 0.4;
	m.addChild(rect(80.0, 64.0, rgba(0.0, 1.0, 0.0, 1.0)).at(-20.0, -20.0));
	s.add(m);
	return s.root;
}

function culledListScene(): Node2D {
	const s = scene(rgba(0.0, 0.0, 0.0, 1.0));
	const m = mask(200.0, 90.0).at(28.0, 30.0);
	for (let i: int32 = 0; i < 40; i++) {
		m.addChild(rect(190.0, 18.0, rgba(0.0, 1.0, 0.0, 1.0))
			.at(5.0, (i as float32) * 22.0 - 240.0));
	}
	s.add(m);
	return s.root;
}

function boxStyleScene(): Node2D {
	const s = scene(rgba(0.0, 0.0, 0.0, 1.0));
	const box = s.add(rect(40.0, 28.0, rgba(0.2, 0.4, 0.6, 0.8)).at(16.0, 12.0));
	box.alpha = 0.5;
	box.setBoxStyle(BoxStyle.create(
		{ topLeft: 2.0, topRight: 4.0, bottomRight: 6.0, bottomLeft: 8.0 },
		{ left: 1.0, top: 2.0, right: 3.0, bottom: 4.0 },
		rgba(0.9, 0.7, 0.5, 0.6),
	).dashed());
	return s.root;
}

function rejectedBoxEffectScene(): Node2D {
	const s = scene(rgba(0.0, 0.0, 0.0, 1.0));
	const box = s.add(rect(40.0, 28.0, rgba(0.2, 0.4, 0.6, 0.8)).at(16.0, 12.0));
	box.setBoxStyle(BoxStyle.create(
		uniformRadii(6.0),
		uniformBorders(2.0),
		rgba(0.9, 0.9, 0.95, 1.0),
	));
	box.colorMatrix = colorMatrixGrayscale(1.0);
	return s.root;
}

function snapScene(): Node2D {
	const s = scene(rgba(0.0, 0.0, 0.0, 1.0));
	s.add(rect(40.4, 28.75, rgba(0.9, 0.4, 0.3, 1.0)).at(16.3, 12.6));
	const boxed = s.add(rect(30.0, 20.0, rgba(0.3, 0.5, 0.9, 1.0)).at(64.35, 16.8));
	boxed.setBoxStyle(BoxStyle.create(
		uniformRadii(4.0),
		{ left: 0.8, top: 1.3, right: 0.0, bottom: 2.2 },
		rgba(0.95, 0.95, 1.0, 1.0),
	));
	return s.root;
}

function glyphScene(): Node2D {
	const s = scene(rgba(0.0, 0.0, 0.0, 1.0));
	const card = s.add(rect(64.0, 40.0, rgba(0.2, 0.4, 0.6, 0.8)).at(8.0, 6.0));
	card.setBoxStyle(BoxStyle.create(
		uniformRadii(6.0),
		uniformBorders(2.0),
		rgba(0.9, 0.9, 0.95, 1.0),
	));
	s.add(label("Hi void", 16.0, rgba(0.95, 0.96, 1.0, 1.0)).at(16.0, 14.0));
	return s.root;
}

function boxShadowScene(): Node2D {
	const s = scene(rgba(0.0, 0.0, 0.0, 1.0));
	const box = s.add(rect(40.0, 28.0, rgba(0.2, 0.4, 0.6, 0.8)).at(16.0, 12.0));
	box.setBoxStyle(BoxStyle.create(
		{ topLeft: 4.0, topRight: 6.0, bottomRight: 8.0, bottomLeft: 10.0 },
		uniformBorders(1.0),
		rgba(0.9, 0.9, 0.95, 1.0),
	).castShadow(rgba(0.0, 0.0, 0.1, 0.5), 3.0, 2.0, 1.0));
	const well = s.add(rect(36.0, 22.0, rgba(0.85, 0.88, 0.94, 1.0)).at(64.0, 16.0));
	well.setBoxStyle(BoxStyle.create(
		uniformRadii(5.0),
		uniformBorders(0.0),
		rgba(0.0, 0.0, 0.0, 0.0),
	).castInsetShadow(rgba(0.0, 0.0, 0.05, 0.6), 2.5));
	return s.root;
}

function shadowOnlyVisibleScene(): Node2D {
	const s = scene(rgba(0.0, 0.0, 0.0, 1.0));
	const box = s.add(rect(20.0, 20.0, rgba(0.2, 0.4, 0.6, 0.8)).at(104.0, 10.0));
	box.setBoxStyle(BoxStyle.create(
		uniformRadii(4.0),
		uniformBorders(0.0),
		rgba(0.0, 0.0, 0.0, 0.0),
	).castShadow(rgba(0.0, 0.0, 0.0, 0.8), 3.0, -6.0, 0.0));
	return s.root;
}

function gradientScene(): Node2D {
	const s = scene(rgba(0.0, 0.0, 0.0, 1.0));
	const g = s.add(graphics());
	g.fillRect(0.0, 0.0, 8.0, 8.0, rgba(0.2, 0.3, 0.4, 1.0));
	g.fillGradientRectOklab(10.0, 0.0, 16.0, 8.0,
		rgba(1.0, 0.0, 0.0, 1.0), rgba(0.0, 0.0, 1.0, 0.8), 0.0);
	g.fillGradientRectStops(28.0, 0.0, 16.0, 8.0,
		rgba(0.0, 0.0, 0.0, 1.0), rgba(0.5, 0.7, 0.2, 0.9),
		rgba(1.0, 1.0, 1.0, 0.7), 0.35, 0.0, GradientSpace.Srgb);
	g.fillSlashRect(46.0, 0.0, 16.0, 8.0,
		rgba(0.1, 0.1, 0.1, 1.0), rgba(0.8, 0.6, 0.2, 1.0), 6.0, 2.0);
	g.fillCheckerRect(64.0, 0.0, 16.0, 8.0,
		rgba(0.2, 0.2, 0.2, 1.0), rgba(0.8, 0.8, 0.8, 1.0), 4.0);
	return s.root;
}
function imageStyleScene(): Node2D {
	const s = scene(rgba(0.0, 0.0, 0.0, 1.0));
	const image = sprite(tile(17, 200.0, 100.0)).at(10.0, 12.0);
	image.w = 100.0;
	image.h = 80.0;
	image.setImageStyle(imageStyle(
		{ topLeft: 3.0, topRight: 6.0, bottomRight: 9.0, bottomLeft: 12.0 },
		true,
		ObjectFit.Cover,
	));
	s.add(image);
	return s.root;
}
function textPrimitiveScene(): Node2D {
	const s = scene(rgba(0.0, 0.0, 0.0, 1.0));
	s.add(underline(72.0, 2.0, rgba(0.9, 0.3, 0.2, 1.0), false).at(8.0, 8.0));
	const wave = s.add(underline(84.0, 3.0, rgba(0.3, 0.7, 1.0, 0.8), true).at(8.0, 18.0));
	wave.rotation = 0.2;
	s.add(selection(80.0, 18.0, rgba(0.2, 0.5, 0.9, 0.65),
		-6.0, 58.0, 12.0, 92.0).at(28.0, 42.0));
	return s.root;
}


test "T1 snapshot: painter order" {
	assert snapshot("order", record(orderScene(), 128.0, 64.0, 1.0));
}

test "T1 snapshot: every batch names why it broke" {
	assert snapshot("breaks", record(breaksScene(), 128.0, 64.0, 1.0));
}

test "T1 snapshot: a Mask scissors its children and gives the clip back" {
	assert snapshot("clip", record(clipScene(), 128.0, 64.0, 1.0));
}

test "T1 production emitters reach every batch-break reason" {
	const breaks: string = record(breaksScene(), 128.0, 64.0, 1.0);
	assert breaks.indexOf("break:first") >= 0;
	assert breaks.indexOf("break:view") >= 0;
	assert breaks.indexOf("break:blend") >= 0;
	assert breaks.indexOf("break:sampler") >= 0;
	assert breaks.indexOf("break:pipeline") >= 0;
	assert record(gradientScene(), 128.0, 64.0, 1.0).indexOf("break:effect") >= 0;
	assert record(clipScene(), 128.0, 64.0, 1.0).indexOf("break:clip") >= 0;

	setSceneSmooth(true);
	begin2d(16.0, 16.0, 1.5);
	assert currentRenderScale() == 1.5;
	beginTarget(1, 16.0, 16.0, 1.25, 0.0, 0.0, rgba(0.0, 0.0, 0.0, 0.0));
	assert currentRenderScale() == 1.25;
	const targetRoot = rect(8.0, 8.0, rgba(1.0, 1.0, 1.0, 1.0));
	targetRoot.sync(identity2d(), true);
	targetRoot.draw(1.0, 16.0, 16.0);
	endTarget();
	assert currentRenderScale() == 1.5;
	finishRecording();
	assert targetCommandCount() == 3;
	assert targetCommandField(1, CMD_BREAK) == (BreakReason.Barrier as int32) as float32;
	assert targetCommandField(1, CMD_RT_MODE) == 1.25;
	frameEnd();
}
test "T1 snapshot: a rotated Mask carries four exact edge distances" {
	assert snapshot("rotatedClip", record(rotatedClipScene(), 128.0, 64.0, 1.0));
}

test "T1 active-clip culling drops rows outside a Mask" {
	record(culledListScene(), 256.0, 150.0, 1.0);
	assert uiInstanceCount() == 4;
}

test "T1 snapshot: dashed box style reaches the per-corner and per-side instance lanes" {
	assert snapshot("boxStyle", record(boxStyleScene(), 128.0, 64.0, 1.0));
}

test "T1 styled Rect rejects a color effect instead of losing its style" {
	record(rejectedBoxEffectScene(), 128.0, 64.0, 1.0);
	assert uiInstanceCount() == 0;
	assert vertexCount() == 0;
	assert drawCommandCount() == 0;
}

test "T1 snapshot: a card and its label are one UI run of mixed modes" {
	assert snapshot("glyphs", record(glyphScene(), 128.0, 64.0, 1.0));
}

test "T1 snapshot: a fractional box records device-integral edges and snapped strokes" {
	assert snapshot("snap", record(snapScene(), 128.0, 64.0, 1.25));
}

test "T1 shadow inflation preserves the snapped visible box" {
	// A fractional margin must not move the reconstructed fill edge off-grid.
	const dpi: float32 = 1.25;
	assert snapshot("boxShadow", record(boxShadowScene(), 128.0, 64.0, dpi));
	const affineX: float32 = uiInstanceField(0, REC_UI_AFFINE);
	const originX: float32 = uiInstanceField(0, REC_UI_ORIGIN_SIZE);
	const quadWidth: float32 = uiInstanceField(0, REC_UI_ORIGIN_SIZE + 2);
	const offsetX: float32 = uiInstanceField(0, REC_UI_PARAMS1);
	const sigma: float32 = uiInstanceField(0, REC_UI_PARAMS1 + 2);
	const margin: float32 = 3.0 * sigma + offsetX;
	const visibleLeft: float32 = (originX + margin * affineX) * dpi;
	const visibleRight: float32 = (originX + (quadWidth - margin) * affineX) * dpi;
	assert approx(visibleLeft as float64, Math.round(visibleLeft as float64));
	assert approx(visibleRight as float64, Math.round(visibleRight as float64));
}

test "T1 an offscreen box still emits when its shadow reaches the viewport" {
	record(shadowOnlyVisibleScene(), 100.0, 50.0, 1.0);
	assert uiInstanceCount() == 1;
}

test "T1 snapshot: gradients and patterns keep draw order and effect records" {
	assert snapshot("gradients", record(gradientScene(), 128.0, 64.0, 1.0));
}
test "T1 snapshot: image style reaches UV, radii, grayscale, and image mode lanes" {
	assert snapshot("imageStyle", record(imageStyleScene(), 128.0, 108.0, 1.0));
}
test "T1 snapshot: retained underline and selection nodes reach their UI modes" {
	assert snapshot("textPrimitives", record(textPrimitiveScene(), 160.0, 96.0, 1.0));
}


test "recording an unchanged tree twice is byte-identical" {
	// The precondition for persistent instance ranges in P5. Without it, "a node that did not
	// change has byte-identical instance data" is a hope rather than a property.
	const root = orderScene();
	const first: string = record(root, 128.0, 64.0, 1.0);
	const second: string = record(root, 128.0, 64.0, 1.0);
	assert first.equals(second);
}

test "the walk records and uploads nothing" {
	// The negative only this tier can assert. A frame that has been recorded but not replayed
	// has commands and vertices and has touched no buffer: the one upload per frame happens in
	// the replay, which T1 never calls.
	const before: int32 = uploadCount();
	const text: string = record(breaksScene(), 128.0, 64.0, 1.0);
	assert (text.length as int32) > 0;
	assert commandCount() > 0;
	// Geometry landed in one stream or the other. Asserting `vertexCount() > 0` alone
	// stopped being true the moment sprites became instances, and an assertion that a
	// refactor can silently satisfy by emitting nothing is worse than none.
	assert vertexCount() + spriteInstanceCount() + uiInstanceCount() > 0;
	assert uploadCount() == before;
}

test "the growth policy: max(2x, pow2), no shrink, and a drop past the cap" {
	const initial: int32 = 1 << 20;
	const cap: int32 = 192 << 20;
	// From nothing the first allocation is the initial size, however small the need.
	assert growthTarget(0, 1) == initial;
	assert growthTarget(0, initial) == initial;
	// A need inside what is already held changes nothing - no shrink, ever.
	assert growthTarget(initial, 1) == initial;
	assert growthTarget(initial, initial) == initial;
	// One byte past the boundary doubles.
	assert growthTarget(initial, initial + 1) == initial * 2;
	// And keeps doubling until it fits rather than growing to exactly what was asked for.
	assert growthTarget(initial, initial * 5) == initial * 8;
	// At the cap it stops at the cap.
	assert growthTarget(cap / 2, cap) == cap;
	// Past it, 0 - the caller's signal to drop the frame with an error instead of truncating
	// it silently, which is the defect this replaced (VOID2D.md P1).
	assert growthTarget(cap, cap + 1) == 0;
	assert growthTarget(0, cap + 1) == 0;
}

function recordedInstances(root: Node2D, w: float32, h: float32): Vec<float32> {
	setSceneSmooth(true);
	begin2d(w, h, 1.0);
	root.sync(identity2d(), true);
	root.draw(1.0, w, h);
	finishRecording();
	const out: Vec<float32> = new Array(0);
	for (let i = 0; i < uiInstanceCount(); i++) {
		for (let f = 0; f < REC_UI_FLOATS; f++) { out.push(uiInstanceField(i, f)); }
	}
	frameEnd();
	return out;
}

test "a caret blink changes no instance but the caret's" {
	const s = scene(rgba(0.0, 0.0, 0.0, 1.0));
	const text = s.add(label("let x = 1;\nx + 2", 16.0, rgba(0.9, 0.9, 0.9, 1.0)).at(8.0, 6.0));
	text.setSelectionRange({ start: 4, length: 9 }, rgba(0.3, 0.5, 0.9, 0.5));
	text.setCursorIndex(13, rgba(1.0, 1.0, 1.0, 1.0));
	const shown = recordedInstances(s.root, 160.0, 64.0);
	text.update(0.6);
	const hidden = recordedInstances(s.root, 160.0, 64.0);
	assert (shown.length as int32) == (hidden.length as int32) + REC_UI_FLOATS;
	let differing: int32 = 0;
	for (let i = 0; i < (hidden.length as int32); i++) {
		if (shown[i] != hidden[i]) { differing = differing + 1; }
	}
	if (differing > 0) { console.log(`t1: ${differing} instance floats moved on a blink`); }
	assert differing == 0;
	text.update(0.5);
	const back = recordedInstances(s.root, 160.0, 64.0);
	assert (back.length as int32) == (shown.length as int32);
}

test "a ragged selection is one row quad per line, each carrying its neighbours" {
	const s = scene(rgba(0.0, 0.0, 0.0, 1.0));
	const text = s.add(label("abcdef\nab\nabcdefgh", 16.0, rgba(0.9, 0.9, 0.9, 1.0)));
	text.setSelectionRange({ start: 2, length: 14 }, rgba(0.3, 0.5, 0.9, 0.5));
	setSceneSmooth(true);
	begin2d(200.0, 80.0, 1.0);
	s.root.sync(identity2d(), true);
	s.root.draw(1.0, 200.0, 80.0);
	finishRecording();
	let rows: int32 = 0;
	let firstRow: int32 = -1;
	for (let i = 0; i < uiInstanceCount(); i++) {
		if (uiInstanceField(i, REC_UI_PARAMS0) == (InstanceMode.Selection as int32) as float32) {
			if (firstRow < 0) { firstRow = i; }
			rows = rows + 1;
		}
	}
	assert rows == 3;
	assert uiInstanceField(firstRow, REC_UI_PARAMS1 + 1) == 0.0;
	assert uiInstanceField(firstRow, REC_UI_PARAMS1 + 3) > 0.0;
	assert uiInstanceField(firstRow + 1, REC_UI_PARAMS1 + 1) > 0.0;
	assert uiInstanceField(firstRow + 1, REC_UI_PARAMS1 + 3) > 0.0;
	assert uiInstanceField(firstRow + 2, REC_UI_PARAMS1 + 3) == 0.0;
	frameEnd();
}

function selectedSpans(root: Node2D, w: float32, h: float32): Vec<float32> {
	setSceneSmooth(true);
	begin2d(w, h, 1.0);
	root.sync(identity2d(), true);
	root.draw(1.0, w, h);
	finishRecording();
	const spans: Vec<float32> = new Array(0);
	for (let i = 0; i < uiInstanceCount(); i++) {
		if (uiInstanceField(i, REC_UI_PARAMS0) != (InstanceMode.Selection as int32) as float32) {
			continue;
		}
		const x0: float32 = uiInstanceField(i, REC_UI_ORIGIN_SIZE) +
			uiInstanceField(i, REC_UI_BORDERS + 3);
		const x1: float32 = x0 + uiInstanceField(i, REC_UI_BORDERS) * 2.0;
		spans.push(x0);
		spans.push(x1);
	}
	frameEnd();
	return spans;
}

test "a selection across a wrap with no separator lights only the text it covers" {
	const s = scene(rgba(0.0, 0.0, 0.0, 1.0));
	const text = s.add(label("well-known", 16.0, rgba(0.9, 0.9, 0.9, 1.0)));
	text.maxWidth = text.calcTextWidth("well-") + 1.0;
	const lines = text.textLayout().lines;
	assert (lines.length as int32) == 2;
	assert lines[0].indexEnd == 5 && lines[1].indexStart == 5;
	const color = rgba(0.3, 0.5, 0.9, 0.5);
	text.setSelectionRange({ start: 5, length: 5 }, color);
	const fromWrap = selectedSpans(s.root, 200.0, 80.0);
	assert (fromWrap.length as int32) == 2;
	assert approx(fromWrap[0], lines[1].x);
	text.setSelectionRange({ start: 2, length: 6 }, color);
	const acrossWrap = selectedSpans(s.root, 200.0, 80.0);
	assert (acrossWrap.length as int32) == 4;
	assert approx(acrossWrap[1], lines[0].x + lines[0].width);
}

test "a label's bounds hold its selection tail and a caret after its widest line" {
	const s = scene(rgba(0.0, 0.0, 0.0, 1.0));
	const text = s.add(label("abcd\nab", 16.0, rgba(0.9, 0.9, 0.9, 1.0)));
	text.setSelectionRange({ start: 2, length: 4 }, rgba(0.3, 0.5, 0.9, 0.5));
	text.setCursorIndex(4, rgba(1.0, 1.0, 1.0, 1.0));
	const spans = selectedSpans(s.root, 200.0, 80.0);
	const bounds = emptyBounds();
	text.getBounds(bounds);
	const first = text.textLayout().lines[0];
	assert first.x + first.width + CURSOR_WIDTH <= bounds.xMax;
	assert (spans.length as int32) == 4;
	assert spans[1] <= bounds.xMax;
}

test "a label's runs, selection and caret under a colour effect are refused aloud" {
	const s = scene(rgba(0.0, 0.0, 0.0, 1.0));
	const text = s.add(label("ab\ncd", 16.0, rgba(0.9, 0.9, 0.9, 1.0)));
	text.setSelectionRange({ start: 1, length: 3 }, rgba(0.3, 0.5, 0.9, 0.5));
	text.setCursorIndex(4, rgba(1.0, 1.0, 1.0, 1.0));
	const before: int32 = labelEditingRefusals();
	selectedSpans(s.root, 200.0, 80.0);
	assert labelEditingRefusals() == before;
	text.colorMatrix = colorMatrixGrayscale(1.0);
	const spans = selectedSpans(s.root, 200.0, 80.0);
	assert (spans.length as int32) == 0;
	assert labelEditingRefusals() == before + 1;
}

test "a selected row covers its trailing spaces, and a blank indented row its indent" {
	const s = scene(rgba(0.0, 0.0, 0.0, 1.0));
	const text = s.add(label("ab  \n    \ncd", 16.0, rgba(0.9, 0.9, 0.9, 1.0)));
	text.setSelectionRange({ start: 0, length: 11 }, rgba(0.3, 0.5, 0.9, 0.5));
	text.setCursorIndex(4, rgba(1.0, 1.0, 1.0, 1.0));
	const spans = selectedSpans(s.root, 200.0, 80.0);
	const l = text.textLayout();
	const spaces = l.glyphs[3];
	const indent = l.glyphs[l.lines[1].firstGlyph + 3];
	assert (spans.length as int32) == 6;
	assert spans[1] > spaces.x + spaces.advance;
	assert spans[3] > indent.x + indent.advance;
	const bounds = emptyBounds();
	text.getBounds(bounds);
	assert l.xForIndex(4) + CURSOR_WIDTH <= bounds.xMax;
	assert spans[1] <= bounds.xMax && spans[3] <= bounds.xMax;
}

test "selected rows meet across line spacing, half of it above each row and half below" {
	const s = scene(rgba(0.0, 0.0, 0.0, 1.0));
	const text = s.add(label("ab\ncd\nef", 16.0, rgba(0.9, 0.9, 0.9, 1.0)));
	text.lineSpacing = 6.0;
	text.setSelectionRange({ start: 0, length: 8 }, rgba(0.3, 0.5, 0.9, 0.5));
	setSceneSmooth(true);
	begin2d(200.0, 100.0, 1.0);
	s.root.sync(identity2d(), true);
	s.root.draw(1.0, 200.0, 100.0);
	finishRecording();
	const tops: Vec<float32> = new Array(0);
	const bottoms: Vec<float32> = new Array(0);
	for (let i = 0; i < uiInstanceCount(); i++) {
		if (uiInstanceField(i, REC_UI_PARAMS0) != (InstanceMode.Selection as int32) as float32) {
			continue;
		}
		const top: float32 = uiInstanceField(i, REC_UI_ORIGIN_SIZE + 1);
		const bottom: float32 = top + uiInstanceField(i, REC_UI_ORIGIN_SIZE + 3);
		tops.push(top);
		bottoms.push(bottom);
	}
	frameEnd();
	const lines = text.textLayout().lines;
	assert (tops.length as int32) == 3;
	assert approx(bottoms[0], tops[1]) && approx(bottoms[1], tops[2]);
	assert approx(tops[0], lines[0].top - 3.0);
	const bounds = emptyBounds();
	text.getBounds(bounds);
	assert bounds.yMin <= tops[0] && bottoms[2] <= bounds.yMax;
}
