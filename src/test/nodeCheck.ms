import { DrawKind, Changed, NodeRef, NodeId2D, Scene2D } from "../void2d/node";
import "../void2d/scene";
import { sync, getBounds, hitTest } from "../void2d/render";
import {
	Tile, Transform2D, rgba, identity2d, emptyBounds, vec2, tile, noFilter, blurFilter,
	glowFilter, dropShadowFilter, FilterKind,
} from "../void2d/types";
import { BlendMode } from "../gpu/state";
import { approx } from "./helpers";
import { BoxStyle, uniformRadii, uniformBorders } from "../void2d/boxStyle";
import { colorMatrixGrayscale } from "../void2d/effect";

const HALF_PI: float32 = 1.5707963;
const white = rgba(1.0, 1.0, 1.0, 1.0);

function fresh(): Scene2D { return Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0)); }

function worldOf(n: NodeRef): Transform2D { return n.scene.worlds[n.id.index]; }

function marked(n: NodeRef, what: Changed): boolean {
	return n.scene.changed[n.id.index].has(what);
}

function listed(n: NodeRef): int32 {
	let count: int32 = 0;
	for (const i of n.scene.dirty) {
		if (i == n.id.index) { count = count + 1; }
	}
	return count;
}

test "rect factory sets fields and defaults" {
	const s = fresh();
	const n = s.rect(10.0, 5.0, rgba(1.0, 0.0, 0.0, 1.0));
	assert n.kind() === DrawKind.Rect;
	assert approx(n.content().w, 10.0);
	assert approx(n.content().h, 5.0);
	assert approx(n.paint().color.r, 1.0);
	assert approx(n.paint().alpha, 1.0);
	assert n.order().visible;
	assert approx(n.local().scaleX, 1.0);
	assert approx(n.local().scaleY, 1.0);
	assert n.paint().blend === BlendMode.Alpha;
	assert marked(n, Changed.Local);
	assert listed(n) == 1;
}

test "sprite takes size from tile" {
	const n = fresh().sprite(tile(0, 32.0, 16.0));
	assert n.kind() === DrawKind.Sprite;
	assert approx(n.content().w, 32.0);
	assert approx(n.content().h, 16.0);
}

test "anim takes size from first frame" {
	const frames: Tile[] = [tile(0, 8.0, 8.0), tile(0, 8.0, 8.0)];
	const n = fresh().anim(frames, 12.0);
	assert n.kind() === DrawKind.Anim;
	assert approx(n.content().w, 8.0);
	assert approx(n.animFrames().fps, 12.0);
}

test "underline factory reserves GPUI's three-thickness wavy bounds" {
	const s = fresh();
	const straight = s.underline(80.0, 2.0, rgba(1.0, 0.0, 0.0, 1.0), false);
	const wavy = s.underline(80.0, 2.0, rgba(1.0, 0.0, 0.0, 1.0), true);
	assert straight.kind() === DrawKind.Underline;
	assert approx(straight.content().h, 2.0);
	assert approx(wavy.content().h, 6.0);
	assert approx(wavy.content().borderL, 2.0);
	assert approx(wavy.content().borderT, 1.0);
}

test "selection factory retains adjacent-row geometry and gloop bounds" {
	const n = fresh().selection(80.0, 20.0, rgba(0.2, 0.4, 0.8, 0.6), -12.0, 60.0, 8.0, 90.0)
		.at(40.0, 30.0);
	assert n.kind() === DrawKind.Selection;
	assert approx(n.content().borderL, -12.0);
	assert approx(n.content().borderT, 60.0);
	assert approx(n.content().borderR, 8.0);
	assert approx(n.content().borderB, 90.0);
	n.sync(identity2d(), false);
	let b = emptyBounds();
	n.getBounds(b);
	assert approx(b.xMin, 32.0);
	assert approx(b.xMax, 128.0);
}

test "addChild appends and marks the parent's tree" {
	const s = fresh();
	const p = s.group();
	s.clearChanges();
	p.addChild(s.rect(1.0, 1.0, white));
	assert p.numChildren() === 1;
	assert marked(p, Changed.Tree);
	assert s.structureChanged;
}

test "at positions and chains" {
	const n = fresh().rect(1.0, 1.0, white).at(3.0, 4.0);
	assert approx(n.local().x, 3.0);
	assert approx(n.local().y, 4.0);
}

test "tick advances anim clocks" {
	const s = fresh();
	const a = s.anim([tile(0, 8.0, 8.0)], 10.0);
	s.add(a);
	s.tick(0.5);
	assert approx(a.animFrames().clock, 0.5);
	s.tick(0.25);
	assert approx(a.animFrames().clock, 0.75);
}

test "sync composes child world from parent translate" {
	const s = fresh();
	const root = s.group().at(10.0, 20.0);
	const child = s.rect(1.0, 1.0, white).at(5.0, 5.0);
	root.addChild(child);
	root.sync(identity2d(), false);
	assert approx(worldOf(child).tx, 15.0);
	assert approx(worldOf(child).ty, 25.0);
}

test "sync propagates parent scale to child offset" {
	const s = fresh();
	const root = s.group().setScale(2.0);
	const child = s.rect(1.0, 1.0, white).at(5.0, 0.0);
	root.addChild(child);
	root.sync(identity2d(), false);
	assert approx(worldOf(child).tx, 10.0);
	assert approx(worldOf(child).a, 2.0);
}

test "sync writes rotation into world matrix" {
	const n = fresh().rect(1.0, 1.0, white).setRotation(HALF_PI);
	n.sync(identity2d(), false);
	assert approx(worldOf(n).a, 0.0);
	assert approx(worldOf(n).b, 1.0);
	assert approx(worldOf(n).c, -1.0);
	assert approx(worldOf(n).d, 0.0);
}
test "pivot shifts the node transform and its children around one local point" {
	const s = fresh();
	const root = s.group().at(100.0, 80.0).setPivot(10.0, 20.0);
	const child = s.rect(4.0, 6.0, white);
	root.addChild(child);
	root.sync(identity2d(), false);
	const pivotWorld = root.localToGlobal(vec2(10.0, 20.0));
	assert approx(pivotWorld.x, 100.0);
	assert approx(pivotWorld.y, 80.0);
	assert approx(worldOf(child).tx, 90.0);
	assert approx(worldOf(child).ty, 60.0);
	root.setPivot(20.0, 30.0);
	root.sync(identity2d(), false);
	assert approx(worldOf(child).tx, 80.0);
	assert approx(worldOf(child).ty, 50.0);
}

test "a centered Tile scales its visual offset with Sprite size" {
	const n = fresh().sprite(tile(1, 32.0, 16.0).center()).at(100.0, 50.0).setSize(64.0, 32.0);
	n.sync(identity2d(), false);
	let b = emptyBounds();
	n.getBounds(b);
	assert approx(b.xMin, 68.0);
	assert approx(b.yMin, 34.0);
	assert approx(b.xMax, 132.0);
	assert approx(b.yMax, 66.0);
}


test "resync after parent move updates clean child" {
	const s = fresh();
	const root = s.group().at(10.0, 0.0);
	const child = s.rect(1.0, 1.0, white).at(5.0, 0.0);
	root.addChild(child);
	root.sync(identity2d(), false);
	assert approx(worldOf(child).tx, 15.0);
	s.clearChanges();
	root.setX(30.0);
	root.sync(identity2d(), false);
	assert approx(worldOf(child).tx, 35.0);
}

test "sync without changes keeps cached world stable" {
	const s = fresh();
	const root = s.group().at(7.0, 0.0);
	const child = s.rect(1.0, 1.0, white).at(1.0, 2.0);
	root.addChild(child);
	root.sync(identity2d(), false);
	s.clearChanges();
	root.sync(identity2d(), false);
	assert approx(worldOf(child).tx, 8.0);
	assert approx(worldOf(child).ty, 2.0);
	assert (s.dirty.length as int32) == 0;
}

test "getBounds covers single rect" {
	const n = fresh().rect(30.0, 40.0, white).at(10.0, 20.0);
	n.sync(identity2d(), false);
	let b = emptyBounds();
	n.getBounds(b);
	assert approx(b.xMin, 10.0);
	assert approx(b.yMin, 20.0);
	assert approx(b.xMax, 40.0);
	assert approx(b.yMax, 60.0);
}

test "getBounds includes an outset analytic box shadow" {
	const n = fresh().rect(20.0, 10.0, rgba(0.3, 0.5, 0.8, 1.0)).at(50.0, 40.0);
	n.setBoxStyle(BoxStyle.create(
		uniformRadii(0.0),
		uniformBorders(0.0),
		rgba(0.0, 0.0, 0.0, 0.0),
	).castShadow(rgba(0.0, 0.0, 0.0, 0.8), 2.0, -3.0, 4.0));
	n.sync(identity2d(), false);
	let b = emptyBounds();
	n.getBounds(b);
	assert approx(b.xMin, 41.0);
	assert approx(b.yMin, 30.0);
	assert approx(b.xMax, 79.0);
	assert approx(b.yMax, 60.0);
}

test "getBounds covers parent and child" {
	const s = fresh();
	const root = s.rect(10.0, 10.0, white).at(0.0, 0.0);
	const child = s.rect(5.0, 5.0, white).at(20.0, 20.0);
	root.addChild(child);
	root.sync(identity2d(), false);
	let b = emptyBounds();
	root.getBounds(b);
	assert approx(b.xMin, 0.0);
	assert approx(b.yMin, 0.0);
	assert approx(b.xMax, 25.0);
	assert approx(b.yMax, 25.0);
}

test "getBounds skips invisible children" {
	const s = fresh();
	const root = s.rect(10.0, 10.0, white);
	const child = s.rect(5.0, 5.0, white).at(20.0, 20.0).setVisible(false);
	root.addChild(child);
	root.sync(identity2d(), false);
	let b = emptyBounds();
	root.getBounds(b);
	assert approx(b.xMin, 0.0);
	assert approx(b.yMin, 0.0);
	assert approx(b.xMax, 10.0);
	assert approx(b.yMax, 10.0);
}

test "getBounds applies parent scale" {
	const s = fresh();
	const root = s.group().setScale(2.0);
	const child = s.rect(10.0, 10.0, white).at(5.0, 5.0);
	root.addChild(child);
	root.sync(identity2d(), false);
	let b = emptyBounds();
	root.getBounds(b);
	assert approx(b.xMin, 10.0);
	assert approx(b.yMin, 10.0);
	assert approx(b.xMax, 30.0);
	assert approx(b.yMax, 30.0);
}

test "addChildAt inserts at correct index" {
	const s = fresh();
	const root = s.group();
	const a = s.rect(1.0, 1.0, white);
	const b = s.rect(2.0, 2.0, white);
	const c = s.rect(3.0, 3.0, white);
	root.addChild(a);
	root.addChild(c);
	root.addChildAt(b, 1);
	assert root.getChildAt(0) == a;
	assert root.getChildAt(1) == b;
	assert root.getChildAt(2) == c;
	assert root.getChildIndex(c) == 2;
}

test "addChildAt negative index clamps to 0" {
	const s = fresh();
	const root = s.group();
	const a = s.rect(1.0, 1.0, white);
	const b = s.rect(2.0, 2.0, white);
	root.addChild(a);
	root.addChildAt(b, -1);
	assert root.getChildAt(0) == b;
}

test "a child is stacked by zIndex, ties keeping the order they were added in" {
	const s = fresh();
	const root = s.group();
	const a = root.addChild(s.rect(1.0, 1.0, white).setZIndex(1));
	const b = root.addChild(s.rect(1.0, 1.0, white));
	const c = root.addChild(s.rect(1.0, 1.0, white));
	assert root.getChildIndex(b) == 0;
	assert root.getChildIndex(c) == 1;
	assert root.getChildIndex(a) == 2;
	b.setZIndex(2);
	assert root.getChildIndex(c) == 0;
	assert root.getChildIndex(a) == 1;
	assert root.getChildIndex(b) == 2;
}

test "addChildAt into a stacked list lands where a stable sort by zIndex puts it" {
	const s = fresh();
	const root = s.group();
	const a = root.addChild(s.rect(1.0, 1.0, white));
	const b = root.addChild(s.rect(1.0, 1.0, white));
	const c = root.addChild(s.rect(1.0, 1.0, white).setZIndex(1));
	const d = root.addChild(s.rect(1.0, 1.0, white).setZIndex(1));
	const low = root.addChildAt(s.rect(1.0, 1.0, white), 3);
	assert root.getChildIndex(low) == 2;
	const high = root.addChildAt(s.rect(1.0, 1.0, white).setZIndex(1), 0);
	assert root.getChildIndex(a) == 0;
	assert root.getChildIndex(b) == 1;
	assert root.getChildIndex(low) == 2;
	assert root.getChildIndex(high) == 3;
	assert root.getChildIndex(c) == 4;
	assert root.getChildIndex(d) == 5;
}

test "removeChild removes correct node and marks the parent's tree" {
	const s = fresh();
	const root = s.group();
	const a = s.rect(1.0, 1.0, white);
	const b = s.rect(2.0, 2.0, white);
	root.addChild(a);
	root.addChild(b);
	s.clearChanges();
	root.removeChild(a);
	assert root.numChildren() === 1;
	assert root.getChildAt(0) == b;
	assert marked(root, Changed.Tree);
	assert a.parent() === null;
	assert a.isLive();
}

test "removeChild of a node that is not a child changes nothing" {
	const s = fresh();
	const root = s.group();
	const other = s.group();
	const a = other.addChild(s.rect(1.0, 1.0, white));
	s.clearChanges();
	root.removeChild(a);
	assert other.numChildren() == 1;
	assert (s.dirty.length as int32) == 0;
}

test "removeChildren clears all" {
	const s = fresh();
	const root = s.group();
	root.addChild(s.rect(1.0, 1.0, white));
	root.addChild(s.rect(2.0, 2.0, white));
	root.removeChildren();
	assert root.numChildren() === 0;
}

test "remove takes a node out of its parent and leaves it alive" {
	const s = fresh();
	const root = s.group();
	const a = root.addChild(s.rect(1.0, 1.0, white));
	a.remove();
	assert root.numChildren() == 0;
	assert a.parent() === null;
	assert a.isLive();
	a.remove();
	assert root.numChildren() == 0;
}

test "addChild moves a child out of its old parent first" {
	const s = fresh();
	const panel = s.group();
	const other = s.group();
	const b = panel.addChild(s.rect(1.0, 1.0, white));
	other.addChild(b);
	assert panel.numChildren() == 0;
	assert other.numChildren() == 1;
	const up = b.parent();
	assert up !== null;
	if (up !== null) { assert up == other; }
}

test "addChild of a child that is already there moves it to the top" {
	const s = fresh();
	const root = s.group();
	const a = root.addChild(s.rect(1.0, 1.0, white));
	const b = root.addChild(s.rect(1.0, 1.0, white));
	root.addChild(a);
	assert root.numChildren() == 2;
	assert root.getChildAt(0) == b;
	assert root.getChildAt(1) == a;
}

test "a reparented node's world follows its new parent" {
	const s = fresh();
	const left = s.group().at(10.0, 0.0);
	const right = s.group().at(100.0, 0.0);
	const child = left.addChild(s.rect(1.0, 1.0, white).at(1.0, 0.0));
	left.sync(identity2d(), false);
	right.sync(identity2d(), false);
	s.clearChanges();
	right.addChild(child);
	right.sync(identity2d(), false);
	assert approx(worldOf(child).tx, 101.0);
}

test "a node moved while detached is drawn where it was moved once added back" {
	const s = fresh();
	const card = s.group();
	const title = card.addChild(s.rect(1.0, 1.0, white));
	s.clearChanges();
	title.setX(7.0);
	s.clearChanges();
	s.add(card.at(10.0, 0.0));
	s.refOf(s.root).sync(identity2d(), false);
	assert approx(worldOf(title).tx, 17.0);
}

test "an equal write marks nothing" {
	const s = fresh();
	const n = s.rect(4.0, 4.0, white).at(3.0, 4.0).setAlpha(0.5);
	s.clearChanges();
	n.at(3.0, 4.0).setAlpha(0.5).setColor(white).setSize(4.0, 4.0).setVisible(true);
	assert (s.dirty.length as int32) == 0;
	assert s.changed[n.id.index].isEmpty();
}

test "a write sets its group's bit and lists the node once" {
	const s = fresh();
	const n = s.rect(4.0, 4.0, white);
	s.clearChanges();
	n.setX(1.0);
	n.setX(2.0);
	n.move(1.0, 1.0);
	assert marked(n, Changed.Local);
	assert !marked(n, Changed.Paint);
	assert listed(n) == 1;
	n.setColor(rgba(1.0, 0.0, 0.0, 1.0));
	assert marked(n, Changed.Paint);
	assert listed(n) == 1;
	assert (s.dirty.length as int32) == 1;
	s.clearChanges();
	assert s.changed[n.id.index].isEmpty();
	assert (s.dirty.length as int32) == 0;
}

test "move follows the node's rotation, as h2d's does" {
	const s = fresh();
	const n = s.rect(1.0, 1.0, white).at(10.0, 10.0);
	n.move(4.0, 2.0);
	assert approx(n.local().x, 14.0);
	assert approx(n.local().y, 12.0);
	n.setRotation(HALF_PI).move(3.0, 0.0);
	assert approx(n.local().x, 14.0);
	assert approx(n.local().y, 15.0);
}

test "rotate, scale and setScale compose as h2d's" {
	const n = fresh().rect(1.0, 1.0, white).setRotation(0.25).rotate(0.5).setScale(2.0).scale(1.5);
	assert approx(n.local().rotation, 0.75);
	assert approx(n.local().scaleX, 3.0);
	assert approx(n.local().scaleY, 3.0);
}

test "dispose frees the row, its subtree and the handle" {
	const s = fresh();
	const before: int32 = s.nodeCount();
	const card = s.add(s.rect(10.0, 10.0, white));
	const title = card.addChild(s.label("Untitled", 16.0, white));
	assert s.nodeCount() == before + 2;
	card.dispose();
	assert s.nodeCount() == before;
	assert !card.isLive();
	assert !title.isLive();
	assert s.refOf(s.root).numChildren() == 0;
	const next = s.group();
	assert next.id.index == title.id.index;
	assert next.id.generation == title.id.generation + 1;
	assert next != title;
}

test "localToGlobal transforms point through world matrix" {
	const n = fresh().rect(10.0, 10.0, white).at(100.0, 200.0);
	n.sync(identity2d(), false);
	const gp = n.localToGlobal(vec2(5.0, 5.0));
	assert approx(gp.x, 105.0);
	assert approx(gp.y, 205.0);
}

test "localToGlobal answers after a write, before any sync" {
	const s = fresh();
	const root = s.group().at(10.0, 0.0);
	const child = root.addChild(s.rect(1.0, 1.0, white).at(5.0, 0.0));
	root.setX(30.0);
	const gp = child.localToGlobal(vec2(0.0, 0.0));
	assert approx(gp.x, 35.0);
}

test "globalToLocal inverse-transforms a point" {
	const n = fresh().rect(10.0, 10.0, white).at(100.0, 200.0);
	n.sync(identity2d(), false);
	const lp = n.globalToLocal(vec2(105.0, 205.0));
	assert approx(lp.x, 5.0);
	assert approx(lp.y, 5.0);
}

test "localToGlobal respects parent scale" {
	const s = fresh();
	const root = s.group().setScaleX(2.0).setScaleY(3.0);
	const child = s.rect(1.0, 1.0, white).at(10.0, 10.0);
	root.addChild(child);
	root.sync(identity2d(), false);
	const gp = child.localToGlobal(vec2(5.0, 5.0));
	assert approx(gp.x, 30.0);
	assert approx(gp.y, 45.0);
}

test "label factory sets text size and color" {
	const n = fresh().label("Hello", 16.0, rgba(1.0, 0.5, 0.0, 1.0));
	assert n.kind() === DrawKind.Label;
	assert n.text().equals("Hello");
	assert approx(n.textStyle().size, 16.0);
	assert approx(n.paint().color.r, 1.0);
	assert approx(n.paint().color.g, 0.5);
}

test "setText marks the label and an equal text marks nothing" {
	const s = fresh();
	const n = s.label("Untitled", 16.0, white);
	s.clearChanges();
	n.setText("Untitled");
	assert (s.dirty.length as int32) == 0;
	n.setText("Saved");
	assert marked(n, Changed.Text);
	assert n.text().equals("Saved");
}

test "mask factory sets dimensions" {
	const n = fresh().mask(200.0, 100.0);
	assert n.kind() === DrawKind.Mask;
	assert approx(n.content().w, 200.0);
	assert approx(n.content().h, 100.0);
}

test "scaleGrid factory sets sheet and borders" {
	const t = tile(0, 100.0, 50.0);
	const n = fresh().scaleGrid(t, 10.0, 5.0, 10.0, 5.0);
	assert n.kind() === DrawKind.ScaleGrid;
	assert approx(n.content().w, 100.0);
	assert approx(n.content().borderL, 10.0);
	assert approx(n.content().borderT, 5.0);
}

test "noFilter produces kind None" {
	const f = noFilter();
	assert f.kind === FilterKind.None;
}

test "blurFilter sets kind and radius" {
	const f = blurFilter(5.0);
	assert f.kind === FilterKind.Blur;
	assert approx(f.radius, 5.0);
}

test "glowFilter sets kind color and gain" {
	const f = glowFilter(rgba(1.0, 0.0, 0.0, 1.0), 3.0, 1.5);
	assert f.kind === FilterKind.Glow;
	assert approx(f.color.r, 1.0);
	assert approx(f.radius, 3.0);
	assert approx(f.gain, 1.5);
}

test "dropShadowFilter sets offset" {
	const f = dropShadowFilter(rgba(0.0, 0.0, 0.0, 1.0), 4.0, 2.0, 3.0);
	assert f.kind === FilterKind.DropShadow;
	assert approx(f.offsetX, 2.0);
	assert approx(f.offsetY, 3.0);
}

test "add hands back the node that was added, not the parent" {
	// It used to hand back the parent, so `const n = s.add(node); n.alpha = 0.5;` - the h2d
	// idiom with the handle kept - configured the scene root instead, in silence. Found by
	// writing a T1 scene the way a Heaps user would.
	const s = fresh();
	const parent = s.group();
	const child = s.rect(4.0, 4.0, rgba(1.0, 0.0, 0.0, 1.0));
	const handle = parent.addChild(child);
	handle.setAlpha(0.25);
	assert parent.numChildren() == 1;
	assert parent.getChildAt(0).paint().alpha == 0.25;
	assert parent.paint().alpha == 1.0;

	// And a second child through the handle becomes a grandchild, not a sibling.
	const grand = handle.addChild(s.rect(2.0, 2.0, rgba(0.0, 1.0, 0.0, 1.0)));
	assert parent.numChildren() == 1;
	assert parent.getChildAt(0).numChildren() == 1;
	grand.setAlpha(0.5);
	assert parent.getChildAt(0).getChildAt(0).paint().alpha == 0.5;
}

test "addChildAt hands back the node that was added too" {
	const s = fresh();
	const parent = s.group();
	parent.addChild(s.rect(4.0, 4.0, rgba(1.0, 0.0, 0.0, 1.0)));
	const inserted = parent.addChildAt(s.rect(2.0, 2.0, rgba(0.0, 1.0, 0.0, 1.0)), 0);
	inserted.setAlpha(0.75);
	assert parent.numChildren() == 2;
	assert parent.getChildAt(0).paint().alpha == 0.75;
}

test "a Mask's scroll moves its own space and its children, and its clip stays, as in h2d" {
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	const m = s.mask(80.0, 60.0).at(10.0, 20.0);
	const child = s.rect(20.0, 10.0, rgba(1.0, 1.0, 1.0, 1.0)).at(5.0, 100.0);
	m.addChild(child);
	s.add(m);
	m.scrollTo(3.0, 90.0);
	const p = child.localToGlobal(vec2(0.0, 0.0));
	assert approx(p.x, 12.0);
	assert approx(p.y, 30.0);
	const back = child.globalToLocal(vec2(12.0, 30.0));
	assert approx(back.x, 0.0);
	assert approx(back.y, 0.0);
	const origin = m.localToGlobal(vec2(0.0, 0.0));
	assert approx(origin.x, 7.0);
	assert approx(origin.y, -70.0);
	const corner = m.localToGlobal(vec2(3.0, 90.0));
	assert approx(corner.x, 10.0);
	assert approx(corner.y, 20.0);
	s.refOf(s.root).sync(identity2d(), true);
	let b = emptyBounds();
	child.getBounds(b);
	assert approx(b.xMin, 12.0);
	assert approx(b.yMin, 30.0);
	assert approx(b.xMax, 32.0);
	assert approx(b.yMax, 40.0);
}

test "scrollBounds clamps a scroll as h2d's setters do, and an equal scroll marks nothing" {
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	const m = s.mask(80.0, 60.0);
	s.add(m);
	m.setScrollBounds({ xMin: 0.0, yMin: 0.0, xMax: 100.0, yMax: 300.0 });
	m.scrollTo(50.0, 400.0);
	assert m.scroll().x == 20.0;
	assert m.scroll().y == 240.0;
	m.scrollBy(-30.0, -10.0);
	assert m.scroll().x == 0.0;
	assert m.scroll().y == 230.0;
	s.clearChanges();
	m.scrollTo(0.0, 230.0);
	assert s.changed[m.id.index].isEmpty();
	m.setScrollY(231.0);
	assert s.changed[m.id.index].has(Changed.Scroll);
	assert !s.changed[m.id.index].has(Changed.Local);
}

test "setNoOverlap is a write to the order group; the same promise again marks nothing" {
	const s = fresh();
	const list = s.add(s.group());
	assert !list.order().noOverlap;
	s.clearChanges();
	list.setNoOverlap(true);
	assert list.order().noOverlap;
	assert marked(list, Changed.Order);
	s.clearChanges();
	list.setNoOverlap(true);
	assert !marked(list, Changed.Order);
	assert s.dirty.length == 0;
}

test "getBounds of an editing label is its text alone, as h2d's TextInput" {
	const s = fresh();
	const plain = s.label("hello", 10.0, white).at(0.0, 0.0);
	plain.sync(identity2d(), false);
	let a = emptyBounds();
	let b = emptyBounds();
	let c = emptyBounds();
	plain.getBounds(a);
	const editing = s.label("hello", 10.0, white);
	editing.setCursorIndex(2, white);
	editing.sync(identity2d(), false);
	editing.getBounds(b);
	assert approx(b.xMin, a.xMin);
	assert approx(b.yMin, a.yMin);
	assert approx(b.xMax, a.xMax);
	assert approx(b.yMax, a.yMax);
	assert !editing.hitTest(vec2(a.xMax + 4.0, (a.yMin + a.yMax) * 0.5));
	const parent = s.group();
	parent.addChild(editing);
	parent.sync(identity2d(), false);
	parent.getBounds(c);
	assert approx(c.xMin, a.xMin);
	assert approx(c.yMin, a.yMin);
	assert approx(c.xMax, a.xMax);
	assert approx(c.yMax, a.yMax);
	editing.setSelectionRange({ start: 1, length: 3 }, white);
	editing.setLineSpacing(6.0);
	plain.setLineSpacing(6.0);
	parent.sync(identity2d(), false);
	plain.sync(identity2d(), false);
	plain.getBounds(a);
	parent.getBounds(c);
	assert approx(c.xMin, a.xMin);
	assert approx(c.yMin, a.yMin);
	assert approx(c.xMax, a.xMax);
	assert approx(c.yMax, a.yMax);
}

test "hitTest answers through the node's own transform" {
	const s = fresh();
	const n = s.rect(10.0, 10.0, white).at(20.0, 0.0);
	n.sync(identity2d(), false);
	assert n.hitTest(vec2(25.0, 5.0));
	assert !n.hitTest(vec2(35.0, 5.0));
	const root = s.add(s.group().setRotation(HALF_PI));
	const turned = s.rect(10.0, 10.0, white).at(20.0, 0.0);
	root.addChild(turned);
	root.sync(identity2d(), false);
	assert turned.hitTest(vec2(0.0, 20.0));
	assert turned.hitTest(vec2(-5.0, 25.0));
	assert !turned.hitTest(vec2(5.0, 25.0));
}

test "hitTest is cut by every Mask above the node" {
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	const m = s.mask(80.0, 60.0).at(10.0, 20.0);
	const child = s.rect(20.0, 10.0, white).at(5.0, 55.0);
	m.addChild(child);
	s.add(m);
	assert child.hitTest(vec2(20.0, 78.0));
	assert !child.hitTest(vec2(20.0, 82.0));
}

test "hitTest follows a scroll scope's shift" {
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	const m = s.mask(80.0, 60.0).at(10.0, 20.0);
	const child = s.rect(20.0, 10.0, white).at(5.0, 5.0);
	m.addChild(child);
	s.add(m);
	assert child.hitTest(vec2(20.0, 30.0));
	m.scrollTo(0.0, 10.0);
	assert child.hitTest(vec2(20.0, 23.0));
	assert !child.hitTest(vec2(20.0, 17.0));
	assert !child.hitTest(vec2(20.0, 30.0));
}

test "hitTest is false on an invisible node or through an invisible parent" {
	const s = fresh();
	const root = s.group();
	const child = s.rect(10.0, 10.0, white).at(0.0, 0.0);
	root.addChild(child);
	s.add(root);
	root.sync(identity2d(), false);
	assert child.hitTest(vec2(5.0, 5.0));
	child.setVisible(false);
	assert !child.hitTest(vec2(5.0, 5.0));
	child.setVisible(true);
	root.setVisible(false);
	assert !child.hitTest(vec2(5.0, 5.0));
}

test "hitTest reads changed transforms before any frame and rejects collapsed geometry" {
	const s = fresh();
	const root = s.add(s.group());
	const child = root.addChild(s.rect(10.0, 10.0, white));
	assert child.hitTest(vec2(5.0, 5.0));
	child.at(20.0, 30.0);
	assert !child.hitTest(vec2(5.0, 5.0));
	assert child.hitTest(vec2(25.0, 35.0));
	root.setScale(0.0);
	assert !child.hitTest(vec2(0.0, 0.0));
	root.setScale(1.0);
	child.setSize(0.0, 10.0);
	assert !child.hitTest(vec2(20.0, 35.0));
}

test "hitTest intersects nested Mask clips through a rotated Mask" {
	const s = fresh();
	const outer = s.add(s.mask(50.0, 25.0).at(10.0, 20.0));
	const inner = outer.addChild(s.mask(20.0, 20.0).at(30.0, 10.0).setRotation(HALF_PI));
	const child = inner.addChild(s.rect(30.0, 10.0, white).at(5.0, 5.0));
	assert child.hitTest(vec2(30.0, 40.0));
	assert !child.hitTest(vec2(30.0, 48.0));
	outer.setSize(50.0, 50.0);
	assert !child.hitTest(vec2(30.0, 55.0));
}

test "a paint read from a node is a value: its matrix reaches the node only through setPaint" {
	const s = fresh();
	const n = s.rect(4.0, 4.0, white).setColorMatrix(colorMatrixGrayscale(1.0));
	s.clearChanges();
	let p = n.paint();
	p.colorMatrix.m11 = 2.0;
	assert n.paint().colorMatrix == colorMatrixGrayscale(1.0);
	assert (s.dirty.length as int32) == 0;
	n.setPaint(p);
	assert marked(n, Changed.Paint);
	assert n.paint().colorMatrix.m11 == 2.0;
}
