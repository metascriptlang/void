import { fakeTexture } from "../../src/test/helpers";
import { add } from "../../src/void2d/scene";
import { Scene2D, NodeRef, TileCell, NO_SLOT } from "../../src/void2d/node";
import { paint, isDirty, tick } from "../../src/void2d/scene";
import { refreshScopes } from "../../src/void2d/render";
import { sync, draw, syncOrder, drawOrder } from "../../src/void2d/render";
import { begin2d, finishRecording, frameEnd, setSceneSmooth } from "../../src/void2d/draw";
import {
	commandCount,
	effectCount,
	vertexCount,
	uiInstanceCount,
	spriteInstanceCount,
	targetCommandCount,
	commandField,
	effectField,
	vertexField,
	uiInstanceField,
	spriteInstanceField,
	COMMAND_FLOATS,
	CMD_PIPELINE,
	CMD_VIEW,
	CMD_VIEW_HIGH,
	CMD_BLEND,
	CMD_SAMPLER,
	CMD_VERTEX_OFFSET,
	CMD_VERTEX_COUNT,
	CMD_INSTANCE_OFFSET,
	CMD_INSTANCE_COUNT,
	EFFECT_FLOATS,
	VERTEX_FLOATS,
	SCOPE_FLOATS,
	resolveScopes,
	PaintIndex,
	PaintState,
	paintStartOf,
	paintEndOf,
	paintStateOf,
	uploaded,
} from "../../src/void2d/displayList";
import {
	REC_UI_FLOATS, REC_SPRITE_FLOATS, REC_UI_ORIGIN_SIZE, REC_SPRITE_ORIGIN_SIZE,
} from "../../src/void2d/instanceLayout";
import { rgba, tile, identity2d, vec2, Tile, whiteTile } from "../../src/void2d/types";

const W: float32 = 200.0;
const H: float32 = 120.0;

struct Recording {
	counts: Vec<int32>;
	floats: Vec<float32>;
}

function capture(): Recording {
	const counts: Vec<int32> = [
		commandCount(), effectCount(), vertexCount(), uiInstanceCount(), spriteInstanceCount(),
		targetCommandCount(),
	];
	let floats: Vec<float32> = [];
	for (let i: int32 = 0; i < commandCount(); i++) {
		for (let f: int32 = 0; f < COMMAND_FLOATS; f++) { floats.push(commandField(i, f)); }
	}
	for (let i: int32 = 0; i < effectCount(); i++) {
		for (let f: int32 = 0; f < EFFECT_FLOATS; f++) { floats.push(effectField(i, f)); }
	}
	for (let i: int32 = 0; i < vertexCount(); i++) {
		for (let f: int32 = 0; f < VERTEX_FLOATS; f++) { floats.push(vertexField(i, f)); }
	}
	for (let i: int32 = 0; i < uiInstanceCount(); i++) {
		for (let f: int32 = 0; f < REC_UI_FLOATS; f++) { floats.push(uiInstanceField(i, f)); }
	}
	for (let i: int32 = 0; i < spriteInstanceCount(); i++) {
		for (let f: int32 = 0; f < REC_SPRITE_FLOATS; f++) {
			floats.push(spriteInstanceField(i, f));
		}
	}
	return { counts: counts, floats: floats };
}

function same(a: Recording, b: Recording): boolean {
	for (let k: int32 = 0; k < (a.counts.length as int32); k++) {
		if (a.counts[k] != b.counts[k]) {
			console.log(`recordings differ in count ${k}: ${a.counts[k]} against ${b.counts[k]}`);
			return false;
		}
	}
	for (let k: int32 = 0; k < (a.floats.length as int32); k++) {
		if (a.floats[k] != b.floats[k]) {
			console.log(`recordings differ at float ${k}: ${a.floats[k]} against ${b.floats[k]}`);
			return false;
		}
	}
	return true;
}

function walked(s: Scene2D): Recording {
	setSceneSmooth(true);
	begin2d(W, H, 1.0);
	s.refOf(s.root).sync(identity2d(), true);
	s.refOf(s.root).draw(1.0, W, H);
	finishRecording();
	let out: Recording = capture();
	frameEnd();
	return out;
}

function scanned(s: Scene2D): Recording {
	setSceneSmooth(true);
	begin2d(W, H, 1.0);
	s.refreshOrder();
	s.syncOrder(identity2d(), true);
	s.drawOrder(W, H);
	finishRecording();
	let out: Recording = capture();
	frameEnd();
	return out;
}

function maskedScene(): Scene2D {
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	const panel = s.mask(120.0, 80.0).at(10.0, 10.0);
	panel.addChild(s.rect(200.0, 20.0, rgba(1.0, 0.0, 0.0, 1.0)).at(-10.0, 5.0));
	const inner = s.mask(60.0, 30.0).at(20.0, 30.0);
	inner.addChild(s.rect(90.0, 12.0, rgba(0.0, 1.0, 0.0, 1.0)).at(-5.0, 8.0));
	inner.addChild(s.sprite(whiteTile(16.0, 16.0)).at(40.0, 20.0));
	panel.addChild(inner);
	const hidden = s.rect(20.0, 20.0, rgba(0.0, 0.0, 1.0, 1.0)).setVisible(false);
	hidden.addChild(s.rect(10.0, 10.0, rgba(1.0, 1.0, 0.0, 1.0)));
	panel.addChild(hidden);
	panel.addChild(s.label("masked", 12.0, rgba(1.0, 1.0, 1.0, 1.0)).at(4.0, 60.0));
	s.add(panel);
	const tilted = s.mask(50.0, 50.0).at(150.0, 20.0).setRotation(0.4);
	tilted.addChild(s.rect(80.0, 80.0, rgba(0.5, 0.5, 1.0, 1.0)).at(-10.0, -10.0));
	s.add(tilted);
	const faded = s.rect(30.0, 30.0, rgba(0.0, 0.0, 1.0, 1.0)).at(150.0, 80.0).setAlpha(0.5);
	faded.addChild(s.rect(10.0, 10.0, rgba(1.0, 1.0, 1.0, 1.0)).at(5.0, 5.0).setAlpha(0.5));
	s.add(faded);
	return s;
}

test "the flat order records what the tree walk records" {
	const s = maskedScene();
	const byWalk: Recording = walked(s);
	const byScan: Recording = scanned(s);
	assert byWalk.counts[0] > 4;
	assert same(byWalk, byScan);
}

test "the draw order is rebuilt on a structural change and on nothing else" {
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	const a = s.rect(10.0, 10.0, rgba(1.0, 0.0, 0.0, 1.0));
	const b = s.rect(10.0, 10.0, rgba(0.0, 1.0, 0.0, 1.0));
	s.add(a);
	s.add(b);
	s.refreshOrder();
	s.clearChanges();
	const built: int32 = s.orderBuilds;
	a.setX(5.0).setColor(rgba(0.0, 0.0, 1.0, 1.0)).setAlpha(0.5).setVisible(false).setName("a");
	s.refreshOrder();
	s.clearChanges();
	assert s.orderBuilds == built;
	a.setZIndex(2);
	s.refreshOrder();
	s.clearChanges();
	assert s.orderBuilds == built + 1;
	assert s.order[s.slots[a.id.index]] == a.id.index;
	assert s.slots[a.id.index] > s.slots[b.id.index];
	s.add(s.group());
	s.refreshOrder();
	s.clearChanges();
	assert s.orderBuilds == built + 2;
	b.remove();
	s.refreshOrder();
	s.clearChanges();
	assert s.orderBuilds == built + 3;
	assert s.slots[b.id.index] == NO_SLOT;
}

function frame(s: Scene2D): Recording {
	s.paint(W, H, 1.0);
	let out: Recording = capture();
	frameEnd();
	s.clearChanges();
	s.retryRefused();
	return out;
}

function fullFrame(s: Scene2D): Recording {
	s.context.painted = false;
	s.viewInit = false;
	return frame(s);
}

let reusedByRetained: int32 = 0;

function ranges(s: Scene2D): Vec<int32> {
	let out: Vec<int32> = [];
	for (let r: int32 = 0; r < (s.kinds.length as int32); r++) {
		if (s.slots[r] == NO_SLOT || paintStateOf(r) != PaintState.Painted) { continue; }
		const a: PaintIndex = paintStartOf(r);
		const b: PaintIndex = paintEndOf(r);
		out.push(r);
		out.push(a.commands); out.push(a.uiInstances); out.push(a.spriteInstances); out.push(a.vertices);
		out.push(a.runStart); out.push(a.reason as int32); out.push(a.mask);
		out.push(b.commands); out.push(b.uiInstances); out.push(b.spriteInstances); out.push(b.vertices);
		out.push(b.runStart); out.push(b.reason as int32); out.push(b.mask);
	}
	return out;
}

function check(s: Scene2D, what: string, path: string): boolean {
	const patches: int32 = s.patches;
	const splices: int32 = s.splices;
	s.paint(W, H, 1.0);
	const retained: Recording = capture();
	const retainedRanges: Vec<int32> = ranges(s);
	frameEnd();
	s.clearChanges();
	s.retryRefused();
	reusedByRetained = s.reused;
	const taken: string = s.patches > patches ? "patch" : (s.splices > splices ? "splice" : "full");
	s.context.painted = false;
	s.viewInit = false;
	s.paint(W, H, 1.0);
	const full: Recording = capture();
	const fullRanges: Vec<int32> = ranges(s);
	frameEnd();
	s.clearChanges();
	s.retryRefused();
	if ((retainedRanges.length as int32) != (fullRanges.length as int32)) {
		console.log(`${what}: ${retainedRanges.length} paint range values against ${fullRanges.length}`);
		return false;
	}
	for (let k: int32 = 0; k < (fullRanges.length as int32); k++) {
		if (retainedRanges[k] != fullRanges[k]) {
			console.log(`${what}: paint range value ${k} is ${retainedRanges[k]} against ${fullRanges[k]}`);
			return false;
		}
	}
	if (!taken.equals(path)) {
		console.log(`${what}: took the ${taken} path, expected the ${path} path`);
		return false;
	}
	if (!same(retained, full)) {
		console.log(`${what}: the retained frame differs from a full one`);
		return false;
	}
	return true;
}

struct Corpus {
	s: Scene2D;
	card: NodeRef;
	label: NodeRef;
	group: NodeRef;
	editor: NodeRef;
	mask: NodeRef;
	other: NodeRef;
}

function corpus(): Corpus {
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	const white = rgba(1.0, 1.0, 1.0, 1.0);
	for (let k: int32 = 0; k < 4; k++) {
		const row = s.rect(40.0, 16.0, rgba(0.2, 0.3, 0.5, 1.0)).at(4.0 + 44.0 * (k as float32), 4.0);
		row.addChild(s.label(String(10 + k), 8.0, white).at(2.0, 2.0));
		s.add(row);
	}
	const card = s.rect(40.0, 16.0, rgba(0.2, 0.3, 0.5, 1.0)).at(4.0, 24.0);
	const label = s.label("12", 8.0, white).at(2.0, 2.0);
	card.addChild(label);
	s.add(card);
	const group = s.group().at(100.0, 24.0);
	group.addChild(s.rect(20.0, 20.0, rgba(0.0, 1.0, 0.0, 1.0)));
	group.addChild(s.label("g", 8.0, white).at(2.0, 2.0));
	s.add(group);
	const frames: Tile[] = [
		whiteTile(8.0, 8.0),
		{ ...whiteTile(8.0, 8.0), u0: 0.5 },
		{ ...whiteTile(8.0, 8.0), v0: 0.5 },
	];
	s.add(s.anim(frames, 4.0).at(150.0, 24.0));
	const editor = s.label("caret", 8.0, white).at(4.0, 50.0);
	editor.setCursorIndex(2, rgba(1.0, 0.8, 0.3, 1.0));
	s.add(editor);
	const mask = s.mask(60.0, 30.0).at(100.0, 60.0);
	mask.addChild(s.rect(80.0, 10.0, rgba(1.0, 0.0, 0.0, 1.0)).at(-5.0, 5.0));
	mask.addChild(s.rect(8.0, 8.0, rgba(0.0, 1.0, 1.0, 1.0)).at(50.0, 18.0));
	s.add(mask);
	const other = s.group().at(4.0, 90.0);
	s.add(other);
	return {
		s: s, card: card, label: label, group: group, editor: editor, mask: mask, other: other,
	};
}

test "a retained frame records what a full frame records, write by write" {
	const c: Corpus = corpus();
	const s: Scene2D = c.s;
	frame(s);
	assert check(s, "a still frame", "patch");
	c.card.setColor(rgba(0.9, 0.1, 0.1, 1.0));
	assert check(s, "a colour", "patch");
	c.card.setX(4.5);
	assert check(s, "a move", "patch");
	c.group.setAlpha(0.5);
	assert check(s, "a group's alpha", "patch");
	c.label.setText("34");
	assert check(s, "text of the same length", "patch");
	s.tick(0.3);
	assert check(s, "an Anim frame", "patch");
	s.tick(0.3);
	assert check(s, "a caret that flips", "patch");
	c.label.setText("5");
	assert check(s, "text of another length", "splice");
	assert reusedByRetained > 10;
	c.other.addChild(c.card);
	assert check(s, "a reparent", "splice");
	c.group.setZIndex(3);
	assert check(s, "setZIndex", "splice");
	c.group.setVisible(false);
	assert check(s, "a visibility flip", "splice");
	c.mask.setSize(40.0, 30.0);
	assert check(s, "a mask resize", "splice");
	c.mask.scrollTo(0.0, 6.0);
	assert check(s, "a mask's first scroll", "splice");
	c.mask.scrollBy(0.0, 3.0);
	assert check(s, "a scroll", "patch");
	c.card.setX(6.0);
	assert check(s, "a move after the splices", "patch");
	s.cam.x = 3.0;
	assert check(s, "a camera pan", "patch");
	s.cam.x = 150.0;
	assert check(s, "a camera pan that takes rows off", "splice");
}

test "a card's colour rewrites its one UI record and nothing else" {
	const c: Corpus = corpus();
	const s: Scene2D = c.s;
	frame(s);
	const before: Recording = frame(s);
	c.card.setColor(rgba(0.9, 0.1, 0.1, 1.0));
	s.paint(W, H, 1.0);
	const after: Recording = capture();
	frameEnd();
	s.clearChanges();
	assert s.repainted == 1;
	const start: PaintIndex = paintStartOf(c.card.id.index);
	const end: PaintIndex = paintEndOf(c.card.id.index);
	assert end.uiInstances == start.uiInstances + 1;
	assert end.spriteInstances == start.spriteInstances;
	assert end.vertices == start.vertices;
	assert end.effects == start.effects;
	assert end.commands == start.commands;
	const uiBase: int32 = before.counts[0] * COMMAND_FLOATS + before.counts[1] * EFFECT_FLOATS +
		before.counts[2] * VERTEX_FLOATS;
	const from: int32 = uiBase + start.uiInstances * REC_UI_FLOATS;
	const to: int32 = from + REC_UI_FLOATS;
	let changed: int32 = 0;
	for (let k: int32 = 0; k < (before.floats.length as int32); k++) {
		if (before.floats[k] != after.floats[k]) {
			if (k < from || k >= to) {
				console.log(`float ${k} changed outside the card's record [${from}, ${to})`);
				assert false;
			}
			changed = changed + 1;
		}
	}
	assert changed > 0;
	assert same({ counts: before.counts, floats: before.floats }, fullFrame(s)) == false;
}

function spriteLast(): Scene2D {
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	s.add(s.sprite(tile(fakeTexture(11), 8.0, 8.0)).at(4.0, 4.0));
	return s;
}

test "a bracket records the same stream whatever the bracket before it ended in" {
	const s = maskedScene();
	walked(spriteLast());
	const afterSprites: Recording = walked(s);
	walked(maskedScene());
	const afterUi: Recording = walked(s);
	assert same(afterSprites, afterUi);
}

test "a card's colour marks one UI range one record long, and an undone write marks none" {
	const c: Corpus = corpus();
	const s: Scene2D = c.s;
	frame(s);
	uploaded();
	frame(s);
	assert s.repainted == 0;
	assert !s.context.uploadAll && s.context.dirtyUiTotal == 0;
	c.card.setColor(rgba(0.9, 0.1, 0.1, 1.0));
	frame(s);
	const start: PaintIndex = paintStartOf(c.card.id.index);
	assert !s.context.uploadAll;
	assert s.context.dirtyUiTotal == 1;
	assert s.context.dirtyUi[0] == start.uiInstances;
	assert s.context.dirtyUi[1] == start.uiInstances + 1;
	assert !s.context.dirtySprites && !s.context.dirtyVertices;
	uploaded();
	c.label.setText("99");
	c.label.setText("12");
	frame(s);
	assert s.repainted == 1;
	assert !s.context.uploadAll && s.context.dirtyUiTotal == 0;
	assert !s.context.dirtySprites && !s.context.dirtyVertices;
}

function caretScene(): Scene2D {
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	const editor = s.label("caret", 8.0, rgba(1.0, 1.0, 1.0, 1.0)).at(4.0, 4.0);
	editor.setCursorIndex(2, rgba(1.0, 0.8, 0.3, 1.0));
	s.add(editor);
	return s;
}

test "a caret blink writes the caret's instance and nothing else" {
	const s: Scene2D = caretScene();
	const editor: int32 = s.children[s.root][0];
	frame(s);
	uploaded();
	s.tick(0.3);
	frame(s);
	assert s.repainted == 0 && s.context.dirtyUiTotal == 0;
	const patches: int32 = s.patches;
	s.tick(0.3);
	const hidden: Recording = frame(s);
	assert s.patches == patches + 1;
	assert s.repainted == 1;
	const end: PaintIndex = paintEndOf(editor);
	assert s.context.dirtyUiTotal == 1;
	assert s.context.dirtyUi[0] == end.uiInstances - 1;
	assert s.context.dirtyUi[1] == end.uiInstances;
	assert !s.context.dirtySprites && !s.context.dirtyVertices;
	assert same(hidden, fullFrame(s));
}

test "a scene is dirty until a frame draws what changed, and a still frame leaves it clean" {
	const c: Corpus = corpus();
	const s: Scene2D = c.s;
	assert s.isDirty();
	frame(s);
	assert !s.isDirty();
	s.tick(0.1);
	assert !s.isDirty();
	c.card.setColor(rgba(0.9, 0.1, 0.1, 1.0));
	assert s.isDirty();
	frame(s);
	assert !s.isDirty();
	c.card.setColor(rgba(0.9, 0.1, 0.1, 1.0));
	assert !s.isDirty();
	s.tick(0.2);
	assert s.isDirty();
	frame(s);
	s.cam.x = 12.0;
	assert s.isDirty();
	frame(s);
	assert !s.isDirty();
	s.defaultSmooth = false;
	assert s.isDirty();
	frame(s);
	c.other.addChild(s.group());
	assert s.isDirty();
	frame(s);
	assert !s.isDirty();
}

test "a scroll writes no instance and no command, only its scope's shift" {
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	const m = s.mask(100.0, 40.0).at(10.0, 10.0);
	for (let i: int32 = 0; i < 12; i++) {
		const row = s.rect(90.0, 18.0, rgba(0.2, 0.3, 0.5, 1.0)).at(5.0, (i as float32) * 22.0);
		row.addChild(s.label(String(i), 10.0, rgba(1.0, 1.0, 1.0, 1.0)).at(4.0, 2.0));
		m.addChild(row);
	}
	s.add(m);
	m.scrollTo(0.0, 30.0);
	frame(s);
	const before: Recording = frame(s);
	s.refreshScopes();
	assert s.context.scopeTotal == 2;
	assert s.context.cameraScope == 0;
	assert s.context.scopes[1].dy == -30.0;
	const patches: int32 = s.patches;
	m.scrollBy(0.0, 22.0);
	assert s.isDirty();
	const after: Recording = frame(s);
	assert s.patches == patches + 1;
	assert s.repainted == 0;
	assert same(before, after);
	s.refreshScopes();
	assert s.context.scopes[1].dy == -52.0;
	assert s.context.uiInstanceTotal == 26;
}

function strip(): Scene2D {
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	for (let k: int32 = 0; k < 10; k++) {
		const cell = s.rect(40.0, 20.0, rgba(0.2, 0.3, 0.5, 1.0)).at(10.0 + 50.0 * (k as float32), 30.0);
		cell.addChild(s.label(String(k), 8.0, rgba(1.0, 1.0, 1.0, 1.0)).at(2.0, 2.0));
		s.add(cell);
	}
	const m = s.mask(60.0, 30.0).at(20.0, 70.0);
	m.addChild(s.rect(50.0, 60.0, rgba(0.0, 1.0, 0.0, 1.0)).at(5.0, 0.0));
	m.scrollTo(0.0, 10.0);
	s.add(m);
	return s;
}

test "a camera pan writes no instance and re-multiplies no node, only the root's shift" {
	const s = strip();
	const cell = s.refOf(s.children[s.root][2]);
	frame(s);
	const before: Recording = frame(s);
	const world = s.worlds[cell.id.index];
	const at: float32 = cell.localToGlobal(vec2(0.0, 0.0)).x;
	const patches: int32 = s.patches;
	s.cam.x = 7.0;
	assert s.isDirty();
	const after: Recording = frame(s);
	assert s.patches == patches + 1;
	assert s.repainted == 0;
	assert same(before, after);
	assert s.worlds[cell.id.index] == world;
	assert cell.localToGlobal(vec2(0.0, 0.0)).x == at - 7.0;
	assert !s.isDirty();
	s.refreshScopes();
	resolveScopes();
	assert s.context.scopeValues[0] == -7.0;
	assert s.context.scopeValues[SCOPE_FLOATS] == -7.0;
	assert s.context.scopeValues[SCOPE_FLOATS + 1] == -10.0;
	assert s.context.scopeValues[SCOPE_FLOATS + 2] == 13.0;
}

test "a camera pan emits the rows it brings on screen and drops the rows it takes off" {
	const s = strip();
	frame(s);
	const shown: int32 = s.context.uiInstanceTotal;
	s.cam.x = 60.0;
	assert check(s, "a pan that uncovers rows", "splice");
	s.cam.x = 61.0;
	assert check(s, "a pan that uncovers nothing", "patch");
	s.cam.x = 0.0;
	assert check(s, "a pan back", "splice");
	assert s.context.uiInstanceTotal == shown;
	s.cam.x = 0.4;
	assert check(s, "a pan under half a device pixel", "patch");
	s.cam.zoom = 1.5;
	assert check(s, "a zoom", "full");
}

function tileCell(x: float32, y: float32, view: uint32): TileCell {
	return {
		x: x, y: y, tile: tile(fakeTexture(view), 8.0, 8.0), color: rgba(1.0, 1.0, 1.0, 1.0), scaleX: 1.0,
		scaleY: 1.0, rotation: 0.0,
	};
}

function fourTiles(): TileCell[] {
	return [tileCell(0.0, 0.0, 11), tileCell(8.0, 0.0, 11), tileCell(16.0, 0.0, 12),
		tileCell(24.0, 0.0, 11)];
}

struct Tiles {
	s: Scene2D;
	map: NodeRef;
}

function tiles(): Tiles {
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	s.add(s.rect(20.0, 20.0, rgba(0.2, 0.3, 0.5, 1.0)).at(4.0, 4.0));
	const map = s.add(s.tileGroup().at(30.0, 4.0));
	map.setTiles(fourTiles());
	s.add(s.sprite(tile(fakeTexture(11), 8.0, 8.0)).at(80.0, 4.0));
	s.add(s.label("after", 8.0, rgba(1.0, 1.0, 1.0, 1.0)).at(4.0, 40.0));
	return { s: s, map: map };
}

test "a tile group's writes record what a full frame records, write by write" {
	const t: Tiles = tiles();
	const s: Scene2D = t.s;
	frame(s);
	assert s.context.spriteInstanceTotal == 5;
	assert check(s, "a still frame", "patch");
	const red: TileCell = { ...tileCell(8.0, 0.0, 11), color: rgba(1.0, 0.0, 0.0, 1.0) };
	t.map.setTile(1, red);
	assert check(s, "a tile's colour", "patch");
	const other: TileCell = tileCell(8.0, 2.0, 12);
	t.map.setTile(1, other);
	assert check(s, "a tile's texture, the runs kept", "patch");
	const back: TileCell = tileCell(8.0, 0.0, 11);
	t.map.setTile(1, back);
	const joined: TileCell = tileCell(16.0, 0.0, 11);
	t.map.setTile(2, joined);
	assert check(s, "a tile's texture, two runs joined", "splice");
	const more: TileCell[] = [tileCell(32.0, 0.0, 12)];
	t.map.appendTiles(more);
	assert check(s, "tiles appended", "splice");
	t.map.setRange(1, 2);
	assert check(s, "a range", "splice");
	t.map.setRange(1, 2);
	assert check(s, "the same range", "patch");
	t.map.setAlpha(0.5);
	assert check(s, "the group's alpha", "patch");
	t.map.setX(31.0);
	assert check(s, "the group moved", "patch");
	t.map.clear();
	assert check(s, "cleared", "splice");
	t.map.setTiles(fourTiles());
	assert check(s, "tiles set again", "splice");
}

test "a tile's colour rewrites its one sprite record and nothing else" {
	const t: Tiles = tiles();
	const s: Scene2D = t.s;
	frame(s);
	const before: Recording = frame(s);
	const red: TileCell = { ...tileCell(8.0, 0.0, 11), color: rgba(1.0, 0.0, 0.0, 1.0) };
	t.map.setTile(1, red);
	const after: Recording = frame(s);
	assert s.retiled == 1 && s.repainted == 0;
	const start: PaintIndex = paintStartOf(t.map.id.index);
	const spriteBase: int32 = before.counts[0] * COMMAND_FLOATS + before.counts[1] * EFFECT_FLOATS +
		before.counts[2] * VERTEX_FLOATS + before.counts[3] * REC_UI_FLOATS;
	const from: int32 = spriteBase + (start.spriteInstances + 1) * REC_SPRITE_FLOATS;
	const to: int32 = from + REC_SPRITE_FLOATS;
	let changed: int32 = 0;
	for (let k: int32 = 0; k < (before.floats.length as int32); k++) {
		if (before.floats[k] != after.floats[k]) {
			if (k < from || k >= to) {
				console.log(`float ${k} changed outside the tile's record [${from}, ${to})`);
				assert false;
			}
			changed = changed + 1;
		}
	}
	assert changed == 2;
	assert s.context.dirtySprites && s.context.dirtyUiTotal == 0 && !s.context.dirtyVertices;
}

test "a tile edit writes in place only while the group keeps its shape, place and alpha" {
	const t: Tiles = tiles();
	const s: Scene2D = t.s;
	frame(s);
	const red: TileCell = { ...tileCell(8.0, 0.0, 11), color: rgba(1.0, 0.0, 0.0, 1.0) };
	t.map.setTile(1, red);
	assert check(s, "a colour, in place", "patch");
	const shifted: TileCell = { ...red, y: 3.0 };
	t.map.setTile(1, shifted);
	frame(s);
	assert s.retiled == 0 && s.repainted == 1;
	const green: TileCell = { ...shifted, color: rgba(0.0, 1.0, 0.0, 1.0) };
	t.map.setTile(1, green);
	t.map.setX(32.0);
	assert check(s, "an edit and a move", "patch");
	frame(s);
	const blue: TileCell = { ...green, color: rgba(0.0, 0.0, 1.0, 1.0) };
	t.map.setTile(1, blue);
	t.map.setAlpha(0.5);
	frame(s);
	assert s.retiled == 0 && s.repainted == 1;
	t.map.setRange(0, 2);
	frame(s);
	uploaded();
	const past: TileCell = { ...tileCell(24.0, 0.0, 11), color: rgba(1.0, 1.0, 0.0, 1.0) };
	t.map.setTile(3, past);
	frame(s);
	assert s.retiled == 1 && !s.context.dirtySprites;
	assert check(s, "an edit outside the range", "patch");
}

test "tile edits past an eighth of the group's tiles re-record the group" {
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	const map = s.add(s.tileGroup());
	const cells: TileCell[] = [];
	for (let k: int32 = 0; k < 200; k++) {
		cells.push(tileCell((k % 20) as float32 * 8.0, (k / 20) as float32 * 8.0, 11));
	}
	map.setTiles(cells);
	frame(s);
	for (let k: int32 = 0; k < 24; k++) {
		const warm: TileCell = { ...cells[k * 3], color: rgba(1.0, 0.5, 0.0, 1.0) };
		map.setTile(k * 3, warm);
	}
	const edited: Recording = frame(s);
	assert s.retiled == 1 && s.repainted == 0;
	assert same(edited, fullFrame(s));
	for (let k: int32 = 0; k < 26; k++) {
		const cool: TileCell = { ...cells[k * 3], color: rgba(0.0, 0.5, 1.0, 1.0) };
		map.setTile(k * 3, cool);
	}
	frame(s);
	assert s.retiled == 0 && s.repainted == 1;
}

test "a camera pan that takes a group off screen wins over its tile edit" {
	const t: Tiles = tiles();
	const s: Scene2D = t.s;
	frame(s);
	const red: TileCell = { ...tileCell(8.0, 0.0, 11), color: rgba(1.0, 0.0, 0.0, 1.0) };
	t.map.setTile(1, red);
	s.cam.x = 70.0;
	assert check(s, "an edit under a pan that hides the group", "splice");
	const green: TileCell = { ...red, color: rgba(0.0, 1.0, 0.0, 1.0) };
	t.map.setTile(1, green);
	s.cam.x = 0.0;
	assert check(s, "an edit under a pan that shows it again", "splice");
}

test "a tile edit under a parent that moved or faded re-records the group" {
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	const holder = s.add(s.group().at(10.0, 10.0));
	const map = holder.addChild(s.tileGroup());
	map.setTiles(fourTiles());
	frame(s);
	const red: TileCell = { ...tileCell(8.0, 0.0, 11), color: rgba(1.0, 0.0, 0.0, 1.0) };
	map.setTile(1, red);
	holder.setX(14.0);
	assert check(s, "an edit under a parent that moved", "patch");
	const green: TileCell = { ...red, color: rgba(0.0, 1.0, 0.0, 1.0) };
	map.setTile(1, green);
	holder.setAlpha(0.5);
	assert check(s, "an edit under a parent that faded", "patch");
	holder.setY(12.0);
	const blue: TileCell = { ...red, color: rgba(0.0, 0.0, 1.0, 1.0) };
	map.setTile(1, blue);
	assert check(s, "a parent that moved, then an edit", "patch");
}

test "a tile edit re-records a group that took another write, drew through the vertex path or was culled" {
	const t: Tiles = tiles();
	const s: Scene2D = t.s;
	frame(s);
	const red: TileCell = { ...tileCell(8.0, 0.0, 11), color: rgba(1.0, 0.0, 0.0, 1.0) };
	t.map.setTile(1, red);
	t.map.setColor(rgba(0.5, 1.0, 1.0, 1.0));
	assert check(s, "an edit and the group's colour", "patch");
	t.map.setColorAdd(rgba(0.1, 0.0, 0.0, 0.0));
	frame(s);
	const green: TileCell = { ...red, color: rgba(0.0, 1.0, 0.0, 1.0) };
	t.map.setTile(1, green);
	assert check(s, "an edit on the vertex path", "patch");
	t.map.setColorAdd(rgba(0.0, 0.0, 0.0, 0.0));
	t.map.setX(260.0);
	frame(s);
	const blue: TileCell = { ...red, color: rgba(0.0, 0.0, 1.0, 1.0) };
	t.map.setTile(1, blue);
	assert check(s, "an edit on a culled group", "patch");
}

function iconList(promise: boolean, icons: boolean): Scene2D {
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	s.add(s.rect(8.0, 8.0, rgba(0.9, 0.9, 0.9, 1.0)).at(180.0, 4.0));
	const list = s.add(s.group().at(4.0, 4.0));
	for (let k: int32 = 0; k < 6; k++) {
		const row = s.rect(120.0, 16.0, rgba(0.2, 0.3, 0.5, 1.0)).at(0.0, (k as float32) * 18.0);
		if (icons) { row.addChild(s.sprite(tile(fakeTexture(21), 12.0, 12.0)).at(2.0, 2.0)); }
		row.addChild(s.label(String(10 + k), 8.0, rgba(1.0, 1.0, 1.0, 1.0)).at(18.0, 3.0));
		list.addChild(row);
	}
	list.setNoOverlap(promise);
	s.add(s.rect(8.0, 8.0, rgba(0.9, 0.9, 0.9, 1.0)).at(180.0, 20.0));
	return s;
}

function draws(r: Recording): int32 {
	let count: int32 = 0;
	for (let c: int32 = 0; c < r.counts[0]; c++) {
		if (r.floats[c * COMMAND_FLOATS] == 0.0) { count = count + 1; }
	}
	return count;
}

test "a list that promises no overlap draws each of its rows' runs once, not once a row" {
	const painter: Recording = frame(iconList(false, true));
	const lanes: Recording = frame(iconList(true, true));
	assert draws(painter) == 13;
	assert draws(lanes) == 3;
	assert lanes.counts[3] == painter.counts[3] && lanes.counts[4] == painter.counts[4];
}

test "a promise with nothing to gain records what no promise records, byte for byte" {
	const without: Recording = frame(iconList(false, false));
	const promised: Recording = frame(iconList(true, false));
	assert draws(promised) == 1;
	assert same(without, promised);
}

test "a region holding a clip keeps painter's order, byte for byte" {
	const plain = iconList(false, true);
	const promised = iconList(true, true);
	for (const s of [plain, promised]) {
		const list = s.refOf(s.children[s.root][1]);
		const clip = s.mask(40.0, 10.0).at(60.0, 2.0);
		clip.addChild(s.rect(80.0, 20.0, rgba(0.0, 1.0, 0.0, 1.0)));
		list.getChildAt(2).addChild(clip);
	}
	assert same(frame(plain), frame(promised));
}

test "writes inside a list that promises no overlap record what a full frame records" {
	const s = iconList(true, true);
	const list = s.refOf(s.children[s.root][1]);
	frame(s);
	assert check(s, "a still frame", "patch");
	list.getChildAt(2).setColor(rgba(0.8, 0.2, 0.2, 1.0));
	assert check(s, "a row's colour", "patch");
	list.getChildAt(3).getChildAt(1).setText("99");
	assert check(s, "a label's text, the same length", "patch");
	list.getChildAt(3).getChildAt(0).setTile(tile(fakeTexture(22), 12.0, 12.0));
	assert check(s, "an icon's texture", "splice");
	list.getChildAt(4).setX(2.0);
	assert check(s, "a row moved", "patch");
	list.getChildAt(1).getChildAt(1).setText("123");
	assert check(s, "a label's text, longer", "splice");
	const extra = s.rect(120.0, 16.0, rgba(0.3, 0.3, 0.3, 1.0)).at(0.0, 110.0);
	extra.addChild(s.sprite(tile(fakeTexture(21), 12.0, 12.0)).at(2.0, 2.0));
	list.addChild(extra);
	assert check(s, "a row added", "splice");
	list.getChildAt(0).setVisible(false);
	assert check(s, "a row hidden", "splice");
	list.setNoOverlap(false);
	assert check(s, "the promise withdrawn", "splice");
	list.setNoOverlap(true);
	assert check(s, "the promise made again", "splice");
	s.cam.x = 3.0;
	assert check(s, "a camera pan", "patch");
}

test "a row of a promised list that is itself a promised list lays out both" {
	const s = iconList(true, true);
	const list = s.refOf(s.children[s.root][1]);
	const inner = list.getChildAt(5);
	inner.addChild(s.sprite(tile(fakeTexture(21), 12.0, 12.0)).at(60.0, 2.0));
	inner.addChild(s.label("x", 8.0, rgba(1.0, 1.0, 1.0, 1.0)).at(80.0, 3.0));
	inner.setNoOverlap(true);
	frame(s);
	assert check(s, "nested promises", "patch");
	inner.getChildAt(2).setTile(tile(fakeTexture(21), 10.0, 12.0));
	assert check(s, "an icon resized inside the inner list", "patch");
}

function drawnInstances(r: Recording): Map<string, int32> {
	const out = new Map<string, int32>();
	const vertexBase: int32 = r.counts[0] * COMMAND_FLOATS + r.counts[1] * EFFECT_FLOATS;
	const uiBase: int32 = vertexBase + r.counts[2] * VERTEX_FLOATS;
	const spriteBase: int32 = uiBase + r.counts[3] * REC_UI_FLOATS;
	for (let c: int32 = 0; c < r.counts[0]; c++) {
		const base: int32 = c * COMMAND_FLOATS;
		if (r.floats[base] != 0.0) { continue; }
		const pipeline: int32 = r.floats[base + CMD_PIPELINE] as int32;
		const state: string = `${pipeline} ${r.floats[base + CMD_VIEW]} ${r.floats[base + CMD_VIEW_HIGH]}` +
			` ${r.floats[base + CMD_BLEND]} ${r.floats[base + CMD_SAMPLER]}`;
		let first: int32 = r.floats[base + CMD_INSTANCE_OFFSET] as int32;
		let count: int32 = r.floats[base + CMD_INSTANCE_COUNT] as int32;
		let width: int32 = pipeline == 1 ? REC_SPRITE_FLOATS : REC_UI_FLOATS;
		let at: int32 = pipeline == 1 ? spriteBase : uiBase;
		if (pipeline == 0) {
			first = r.floats[base + CMD_VERTEX_OFFSET] as int32;
			count = r.floats[base + CMD_VERTEX_COUNT] as int32;
			width = VERTEX_FLOATS;
			at = vertexBase;
		}
		for (let k: int32 = first; k < first + count; k++) {
			let key: string = state;
			for (let f: int32 = 0; f < width; f++) { key = key + ` ${r.floats[at + k * width + f]}`; }
			out.set(key, (out.get(key) ?? 0) + 1);
		}
	}
	return out;
}

test "lanes draw every instance of painter's order under the same draw state, only regrouped" {
	const painter = drawnInstances(frame(iconList(false, true)));
	const lanes = drawnInstances(frame(iconList(true, true)));
	assert painter.size == lanes.size;
	let kinds: int32 = 0;
	for (const key of painter) {
		assert (lanes.get(key) ?? 0) == (painter.get(key) ?? 0);
		kinds = kinds + 1;
	}
	assert kinds > 12;
}

function rowSequence(r: Recording, row: int32): string {
	const vertexBase: int32 = r.counts[0] * COMMAND_FLOATS + r.counts[1] * EFFECT_FLOATS;
	const uiBase: int32 = vertexBase + r.counts[2] * VERTEX_FLOATS;
	const spriteBase: int32 = uiBase + r.counts[3] * REC_UI_FLOATS;
	let out: string = "";
	for (let c: int32 = 0; c < r.counts[0]; c++) {
		const base: int32 = c * COMMAND_FLOATS;
		if (r.floats[base] != 0.0) { continue; }
		const sprite: boolean = (r.floats[base + CMD_PIPELINE] as int32) == 1;
		const width: int32 = sprite ? REC_SPRITE_FLOATS : REC_UI_FLOATS;
		const at: int32 = sprite ? spriteBase : uiBase;
		const origin: int32 = sprite ? REC_SPRITE_ORIGIN_SIZE : REC_UI_ORIGIN_SIZE;
		const first: int32 = r.floats[base + CMD_INSTANCE_OFFSET] as int32;
		const count: int32 = r.floats[base + CMD_INSTANCE_COUNT] as int32;
		for (let k: int32 = first; k < first + count; k++) {
			const x: float32 = r.floats[at + k * width + origin];
			const y: float32 = r.floats[at + k * width + origin + 1];
			if (x > 150.0 || ((y - 4.0) / 18.0) as int32 != row) { continue; }
			out = out + `${sprite ? "s" : "u"}(${x},${y}) `;
		}
	}
	return out;
}

test "lanes keep each row's own draws in painter's order" {
	const painter: Recording = frame(iconList(false, true));
	const lanes: Recording = frame(iconList(true, true));
	for (let row: int32 = 0; row < 6; row++) {
		const want: string = rowSequence(painter, row);
		assert want.length > 10;
		assert rowSequence(lanes, row).equals(want);
	}
}
