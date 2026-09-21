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
import { scene, add } from "../../src/void2d/scene";
import { Node2D, rect, mask, at, addChild, setBoxStyle } from "../../src/void2d/node";
import { sync, draw } from "../../src/void2d/render";
import { begin2d, finishRecording, uploadCount, growthTarget, setSceneSmooth } from "../../src/void2d/draw";
import {
	commandCount, vertexCount, drawCommandCount, commandField, vertexField,
	CMD_KIND, CMD_BREAK, CMD_VERTEX_OFFSET, CMD_VERTEX_COUNT, CMD_VIEW, CMD_BLEND,
	CMD_SAMPLER, CMD_EFFECT, CMD_CLIP_X, CMD_CLIP_Y, CMD_CLIP_W, CMD_CLIP_H, CMD_RT_MODE,
	commandKindName, breakReasonName,
	Pipeline, CMD_PIPELINE, CMD_INSTANCE_OFFSET, CMD_INSTANCE_COUNT,
	uiInstanceCount, spriteInstanceCount, spriteInstanceField, uiInstanceField,
} from "../../src/void2d/displayList";
import {
	REC_SPRITE_AFFINE, REC_SPRITE_ORIGIN_SIZE, REC_SPRITE_UV, REC_SPRITE_COLOR,
	REC_UI_AFFINE, REC_UI_ORIGIN_SIZE, REC_UI_UV_RADII, REC_UI_BORDERS, REC_UI_PARAMS0,
	REC_UI_COLOR_FILL, REC_UI_COLOR_BORDER,
} from "../../src/void2d/instance";
import { rgba, identity2d, BlendMode, Smooth } from "../../src/void2d/types";
import { boxStyle, cornerRadii, borderWidths } from "../../src/void2d/boxStyle";

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
		out = out + ` uvr`;
		out = out + ` ${f2(uiInstanceField(i, REC_UI_UV_RADII))}`;
		out = out + ` ${f2(uiInstanceField(i, REC_UI_UV_RADII + 1))}`;
		out = out + ` ${f2(uiInstanceField(i, REC_UI_UV_RADII + 2))}`;
		out = out + ` ${f2(uiInstanceField(i, REC_UI_UV_RADII + 3))}`;
		out = out + ` border`;
		out = out + ` ${f2(uiInstanceField(i, REC_UI_BORDERS))}`;
		out = out + ` ${f2(uiInstanceField(i, REC_UI_BORDERS + 1))}`;
		out = out + ` ${f2(uiInstanceField(i, REC_UI_BORDERS + 2))}`;
		out = out + ` ${f2(uiInstanceField(i, REC_UI_BORDERS + 3))}`;
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
	begin2d(w, h, dpi);
	// `sceneSmooth` is emitter state that only `Scene.present` sets, so without this a
	// snapshot's `sampler:` column depended on whether some other test in the same process
	// had rendered a scene with `defaultSmooth = false`. A snapshot that can pass for a
	// reason outside its own scene is not a snapshot.
	setSceneSmooth(true);
	root.sync(identity2d(), true);
	root.draw(1.0, w, h);
	finishRecording();
	return formatStream();
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

function boxStyleScene(): Node2D {
	const s = scene(rgba(0.0, 0.0, 0.0, 1.0));
	const box = s.add(rect(40.0, 28.0, rgba(0.2, 0.4, 0.6, 0.8)).at(16.0, 12.0));
	box.alpha = 0.5;
	box.setBoxStyle(boxStyle(
		cornerRadii(2.0, 4.0, 6.0, 8.0),
		borderWidths(1.0, 2.0, 3.0, 4.0),
		rgba(0.9, 0.7, 0.5, 0.6),
	));
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

test "T1 snapshot: box style reaches the per-corner and per-side instance lanes" {
	assert snapshot("boxStyle", record(boxStyleScene(), 128.0, 64.0, 1.0));
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
