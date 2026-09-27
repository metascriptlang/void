import { scene, add } from "../../src/void2d/scene";
import { Scene, NodeRef, NO_SLOT } from "../../src/void2d/node";
import { paint } from "../../src/void2d/scene";
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
	EFFECT_FLOATS,
	VERTEX_FLOATS,
	PaintIndex,
	paintStartOf,
	paintEndOf,
} from "../../src/void2d/displayList";
import { REC_UI_FLOATS, REC_SPRITE_FLOATS } from "../../src/void2d/instanceLayout";
import { rgba, tile, identity2d, Tile } from "../../src/void2d/types";

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
	const floats: Vec<float32> = [];
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

function walked(s: Scene): Recording {
	setSceneSmooth(true);
	begin2d(W, H, 1.0);
	s.refOf(s.root).sync(identity2d(), true);
	s.refOf(s.root).draw(1.0, W, H);
	finishRecording();
	const out: Recording = capture();
	frameEnd();
	return out;
}

function scanned(s: Scene): Recording {
	setSceneSmooth(true);
	begin2d(W, H, 1.0);
	s.refreshOrder();
	s.syncOrder(identity2d(), true);
	s.drawOrder(W, H);
	finishRecording();
	const out: Recording = capture();
	frameEnd();
	return out;
}

function maskedScene(): Scene {
	const s = scene(rgba(0.0, 0.0, 0.0, 1.0));
	const panel = s.mask(120.0, 80.0).at(10.0, 10.0);
	panel.addChild(s.rect(200.0, 20.0, rgba(1.0, 0.0, 0.0, 1.0)).at(-10.0, 5.0));
	const inner = s.mask(60.0, 30.0).at(20.0, 30.0);
	inner.addChild(s.rect(90.0, 12.0, rgba(0.0, 1.0, 0.0, 1.0)).at(-5.0, 8.0));
	inner.addChild(s.sprite(tile(0, 16.0, 16.0)).at(40.0, 20.0));
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
	const s = scene(rgba(0.0, 0.0, 0.0, 1.0));
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

function frame(s: Scene): Recording {
	s.paint(W, H, 1.0);
	const out: Recording = capture();
	frameEnd();
	s.clearChanges();
	s.retryRefused();
	return out;
}

function fullFrame(s: Scene): Recording {
	s.list.painted = false;
	s.viewInit = false;
	return frame(s);
}

function check(s: Scene, what: string, kept: boolean): boolean {
	const before: int32 = s.list.patches;
	const retained: Recording = frame(s);
	const patched: boolean = s.list.patches == before + 1;
	const full: Recording = fullFrame(s);
	if (patched != kept) {
		console.log(`${what}: patched ${patched}, expected ${kept}`);
		return false;
	}
	if (!same(retained, full)) {
		console.log(`${what}: the retained frame differs from a full one`);
		return false;
	}
	return true;
}

struct Corpus {
	s: Scene;
	card: NodeRef;
	label: NodeRef;
	group: NodeRef;
	editor: NodeRef;
	mask: NodeRef;
	other: NodeRef;
}

function corpus(): Corpus {
	const s = scene(rgba(0.0, 0.0, 0.0, 1.0));
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
		tile(0, 8.0, 8.0),
		{ ...tile(0, 8.0, 8.0), u0: 0.5 },
		{ ...tile(0, 8.0, 8.0), v0: 0.5 },
	];
	s.add(s.anim(frames, 4.0).at(150.0, 24.0));
	const editor = s.label("caret", 8.0, white).at(4.0, 50.0);
	editor.setCursorIndex(2, rgba(1.0, 0.8, 0.3, 1.0));
	s.add(editor);
	const mask = s.mask(60.0, 30.0).at(100.0, 60.0);
	mask.addChild(s.rect(80.0, 10.0, rgba(1.0, 0.0, 0.0, 1.0)).at(-5.0, 5.0));
	s.add(mask);
	const other = s.group().at(4.0, 90.0);
	s.add(other);
	return {
		s: s, card: card, label: label, group: group, editor: editor, mask: mask, other: other,
	};
}

test "a retained frame records what a full frame records, write by write" {
	const c: Corpus = corpus();
	const s: Scene = c.s;
	frame(s);
	assert check(s, "a still frame", true);
	c.card.setColor(rgba(0.9, 0.1, 0.1, 1.0));
	assert check(s, "a colour", true);
	c.card.setX(4.5);
	assert check(s, "a move", true);
	c.group.setAlpha(0.5);
	assert check(s, "a group's alpha", true);
	c.label.setText("34");
	assert check(s, "text of the same length", true);
	s.tick(0.3);
	assert check(s, "an Anim frame", true);
	s.tick(0.3);
	assert check(s, "a caret that flips", false);
	c.label.setText("5");
	assert check(s, "text of another length", false);
	c.other.addChild(c.card);
	assert check(s, "a reparent", false);
	c.group.setZIndex(3);
	assert check(s, "setZIndex", false);
	c.group.setVisible(false);
	assert check(s, "a visibility flip", false);
	c.mask.setSize(40.0, 30.0);
	assert check(s, "a mask resize", false);
	c.card.setX(6.0);
	assert check(s, "a move after the fallbacks", true);
}

test "a card's colour rewrites its one UI record and nothing else" {
	const c: Corpus = corpus();
	const s: Scene = c.s;
	frame(s);
	const before: Recording = frame(s);
	c.card.setColor(rgba(0.9, 0.1, 0.1, 1.0));
	s.paint(W, H, 1.0);
	const after: Recording = capture();
	frameEnd();
	s.clearChanges();
	assert s.list.repainted == 1;
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

function spriteLast(): Scene {
	const s = scene(rgba(0.0, 0.0, 0.0, 1.0));
	s.add(s.sprite(tile(11, 8.0, 8.0)).at(4.0, 4.0));
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
