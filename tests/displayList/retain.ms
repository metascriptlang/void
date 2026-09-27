import { scene, add } from "../../src/void2d/scene";
import { Scene, NodeRef, NO_SLOT } from "../../src/void2d/node";
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
} from "../../src/void2d/displayList";
import { REC_UI_FLOATS, REC_SPRITE_FLOATS } from "../../src/void2d/instanceLayout";
import { rgba, tile, identity2d } from "../../src/void2d/types";

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
