import {
	DrawKind, group, rect, sprite, label, anim, graphics, mask, scaleGrid, underline, selection,
	addChild, addChildAt, removeChild, removeChildren, at, update, dispose, localToGlobal,
	globalToLocal, setBoxStyle,
} from "../void2d/node";
import { sync, getBounds } from "../void2d/render";
import {
	Tile, rgba, identity2d, emptyBounds, BlendMode, vec2, tile, noFilter, blurFilter, glowFilter,
	dropShadowFilter, FilterKind,
} from "../void2d/types";
import { approx } from "./helpers";
import { boxStyle, uniformRadii, uniformBorders, castShadow } from "../void2d/boxStyle";

const HALF_PI: float32 = 1.5707963;

test "rect factory sets fields and defaults" {
	const n = rect(10.0, 5.0, rgba(1.0, 0.0, 0.0, 1.0));
	assert n.kind === DrawKind.Rect;
	assert approx(n.w, 10.0);
	assert approx(n.h, 5.0);
	assert approx(n.color.r, 1.0);
	assert approx(n.alpha, 1.0);
	assert n.visible;
	assert approx(n.scaleX, 1.0);
	assert approx(n.scaleY, 1.0);
	assert n.blend === BlendMode.Alpha;
	assert n.dirty;
}

test "sprite takes size from tile" {
	const n = sprite(tile(0, 32.0, 16.0));
	assert n.kind === DrawKind.Sprite;
	assert approx(n.w, 32.0);
	assert approx(n.h, 16.0);
}

test "anim takes size from first frame" {
	const frames: Tile[] = [tile(0, 8.0, 8.0), tile(0, 8.0, 8.0)];
	const n = anim(frames, 12.0);
	assert n.kind === DrawKind.Anim;
	assert approx(n.w, 8.0);
	assert approx(n.fps, 12.0);
}
test "underline factory reserves GPUI's three-thickness wavy bounds" {
	const straight = underline(80.0, 2.0, rgba(1.0, 0.0, 0.0, 1.0), false);
	const wavy = underline(80.0, 2.0, rgba(1.0, 0.0, 0.0, 1.0), true);
	assert straight.kind === DrawKind.Underline;
	assert approx(straight.h, 2.0);
	assert approx(wavy.h, 6.0);
	assert approx(wavy.size, 2.0);
	assert approx(wavy.align, 1.0);
}

test "selection factory retains adjacent-row geometry and gloop bounds" {
	const n = selection(80.0, 20.0, rgba(0.2, 0.4, 0.8, 0.6), -12.0, 60.0, 8.0, 90.0).at(40.0, 30.0);
	assert n.kind === DrawKind.Selection;
	assert approx(n.borderL, -12.0);
	assert approx(n.borderT, 60.0);
	assert approx(n.borderR, 8.0);
	assert approx(n.borderB, 90.0);
	n.sync(identity2d(), false);
	const b = emptyBounds();
	n.getBounds(b);
	assert approx(b.xMin, 32.0);
	assert approx(b.xMax, 128.0);
}


test "addChild appends and marks dirty" {
	const p = group();
	p.childrenDirty = false;
	p.addChild(rect(1.0, 1.0, rgba(1.0, 1.0, 1.0, 1.0)));
	assert (p.children.length as int32) === 1;
	assert p.childrenDirty;
}

test "at positions and chains" {
	const n = rect(1.0, 1.0, rgba(1.0, 1.0, 1.0, 1.0)).at(3.0, 4.0);
	assert approx(n.x, 3.0);
	assert approx(n.y, 4.0);
}

test "update advances anim clocks recursively" {
	const root = group();
	const a = anim([tile(0, 8.0, 8.0)], 10.0);
	root.addChild(a);
	root.update(0.5);
	assert approx(a.clock, 0.5);
	root.update(0.25);
	assert approx(a.clock, 0.75);
}

test "sync composes child world from parent translate" {
	const root = group().at(10.0, 20.0);
	const child = rect(1.0, 1.0, rgba(1.0, 1.0, 1.0, 1.0)).at(5.0, 5.0);
	root.addChild(child);
	root.sync(identity2d(), false);
	assert approx(child.cachedWorld.tx, 15.0);
	assert approx(child.cachedWorld.ty, 25.0);
}

test "sync propagates parent scale to child offset" {
	const root = group();
	root.scaleX = 2.0;
	root.scaleY = 2.0;
	const child = rect(1.0, 1.0, rgba(1.0, 1.0, 1.0, 1.0)).at(5.0, 0.0);
	root.addChild(child);
	root.sync(identity2d(), false);
	assert approx(child.cachedWorld.tx, 10.0);
	assert approx(child.cachedWorld.a, 2.0);
}

test "sync writes rotation into world matrix" {
	const n = rect(1.0, 1.0, rgba(1.0, 1.0, 1.0, 1.0));
	n.rotation = HALF_PI;
	n.sync(identity2d(), false);
	assert approx(n.cachedWorld.a, 0.0);
	assert approx(n.cachedWorld.b, 1.0);
	assert approx(n.cachedWorld.c, -1.0);
	assert approx(n.cachedWorld.d, 0.0);
}
test "pivot shifts the node transform and its children around one local point" {
	const root = group().at(100.0, 80.0);
	root.pivotX = 10.0;
	root.pivotY = 20.0;
	const child = rect(4.0, 6.0, rgba(1.0, 1.0, 1.0, 1.0));
	root.addChild(child);
	root.sync(identity2d(), false);
	const pivotWorld = root.localToGlobal(vec2(10.0, 20.0));
	assert approx(pivotWorld.x, 100.0);
	assert approx(pivotWorld.y, 80.0);
	assert approx(child.cachedWorld.tx, 90.0);
	assert approx(child.cachedWorld.ty, 60.0);
	root.pivotX = 20.0;
	root.pivotY = 30.0;
	root.sync(identity2d(), false);
	assert approx(child.cachedWorld.tx, 80.0);
	assert approx(child.cachedWorld.ty, 50.0);
}

test "a centered Tile scales its visual offset with Sprite size" {
	const n = sprite(tile(1, 32.0, 16.0).center()).at(100.0, 50.0);
	n.w = 64.0;
	n.h = 32.0;
	n.sync(identity2d(), false);
	const b = emptyBounds();
	n.getBounds(b);
	assert approx(b.xMin, 68.0);
	assert approx(b.yMin, 34.0);
	assert approx(b.xMax, 132.0);
	assert approx(b.yMax, 66.0);
}


test "resync after parent move updates clean child" {
	const root = group().at(10.0, 0.0);
	const child = rect(1.0, 1.0, rgba(1.0, 1.0, 1.0, 1.0)).at(5.0, 0.0);
	root.addChild(child);
	root.sync(identity2d(), false);
	assert approx(child.cachedWorld.tx, 15.0);
	root.x = 30.0;
	root.sync(identity2d(), false);
	assert approx(child.cachedWorld.tx, 35.0);
}

test "sync without changes keeps cached world stable" {
	const root = group().at(7.0, 0.0);
	const child = rect(1.0, 1.0, rgba(1.0, 1.0, 1.0, 1.0)).at(1.0, 2.0);
	root.addChild(child);
	root.sync(identity2d(), false);
	root.sync(identity2d(), false);
	assert approx(child.cachedWorld.tx, 8.0);
	assert approx(child.cachedWorld.ty, 2.0);
	assert !root.dirty;
	assert !child.dirty;
}

test "getBounds covers single rect" {
	const n = rect(30.0, 40.0, rgba(1.0, 1.0, 1.0, 1.0)).at(10.0, 20.0);
	n.sync(identity2d(), false);
	const b = emptyBounds();
	n.getBounds(b);
	assert approx(b.xMin, 10.0);
	assert approx(b.yMin, 20.0);
	assert approx(b.xMax, 40.0);
	assert approx(b.yMax, 60.0);
}

test "getBounds includes an outset analytic box shadow" {
	const n = rect(20.0, 10.0, rgba(0.3, 0.5, 0.8, 1.0)).at(50.0, 40.0);
	n.setBoxStyle(castShadow(boxStyle(
		uniformRadii(0.0),
		uniformBorders(0.0),
		rgba(0.0, 0.0, 0.0, 0.0),
	), rgba(0.0, 0.0, 0.0, 0.8), 2.0, -3.0, 4.0));
	n.sync(identity2d(), false);
	const b = emptyBounds();
	n.getBounds(b);
	assert approx(b.xMin, 41.0);
	assert approx(b.yMin, 30.0);
	assert approx(b.xMax, 79.0);
	assert approx(b.yMax, 60.0);
}

test "getBounds covers parent and child" {
	const root = rect(10.0, 10.0, rgba(1.0, 1.0, 1.0, 1.0)).at(0.0, 0.0);
	const child = rect(5.0, 5.0, rgba(1.0, 1.0, 1.0, 1.0)).at(20.0, 20.0);
	root.addChild(child);
	root.sync(identity2d(), false);
	const b = emptyBounds();
	root.getBounds(b);
	assert approx(b.xMin, 0.0);
	assert approx(b.yMin, 0.0);
	assert approx(b.xMax, 25.0);
	assert approx(b.yMax, 25.0);
}

test "getBounds skips invisible children" {
	const root = rect(10.0, 10.0, rgba(1.0, 1.0, 1.0, 1.0));
	const child = rect(5.0, 5.0, rgba(1.0, 1.0, 1.0, 1.0)).at(20.0, 20.0);
	child.visible = false;
	root.addChild(child);
	root.sync(identity2d(), false);
	const b = emptyBounds();
	root.getBounds(b);
	assert approx(b.xMin, 0.0);
	assert approx(b.yMin, 0.0);
	assert approx(b.xMax, 10.0);
	assert approx(b.yMax, 10.0);
}

test "getBounds applies parent scale" {
	const root = group();
	root.scaleX = 2.0;
	root.scaleY = 2.0;
	const child = rect(10.0, 10.0, rgba(1.0, 1.0, 1.0, 1.0)).at(5.0, 5.0);
	root.addChild(child);
	root.sync(identity2d(), false);
	const b = emptyBounds();
	root.getBounds(b);
	assert approx(b.xMin, 10.0);
	assert approx(b.yMin, 10.0);
	assert approx(b.xMax, 30.0);
	assert approx(b.yMax, 30.0);
}

test "addChildAt inserts at correct index" {
	const root = group();
	const a = rect(1.0, 1.0, rgba(1.0, 1.0, 1.0, 1.0));
	const b = rect(2.0, 2.0, rgba(1.0, 1.0, 1.0, 1.0));
	const c = rect(3.0, 3.0, rgba(1.0, 1.0, 1.0, 1.0));
	root.addChild(a);
	root.addChild(c);
	root.addChildAt(b, 1);
	assert root.children[0] === a;
	assert root.children[1] === b;
	assert root.children[2] === c;
}

test "addChildAt negative index clamps to 0" {
	const root = group();
	const a = rect(1.0, 1.0, rgba(1.0, 1.0, 1.0, 1.0));
	const b = rect(2.0, 2.0, rgba(1.0, 1.0, 1.0, 1.0));
	root.addChild(a);
	root.addChildAt(b, -1);
	assert root.children[0] === b;
}

test "removeChild removes correct node and marks dirty" {
	const root = group();
	const a = rect(1.0, 1.0, rgba(1.0, 1.0, 1.0, 1.0));
	const b = rect(2.0, 2.0, rgba(1.0, 1.0, 1.0, 1.0));
	root.addChild(a);
	root.addChild(b);
	root.childrenDirty = false;
	root.removeChild(a);
	assert (root.children.length as int32) === 1;
	assert root.children[0] === b;
	assert root.childrenDirty;
}

test "removeChildren clears all" {
	const root = group();
	root.addChild(rect(1.0, 1.0, rgba(1.0, 1.0, 1.0, 1.0)));
	root.addChild(rect(2.0, 2.0, rgba(1.0, 1.0, 1.0, 1.0)));
	root.removeChildren();
	assert (root.children.length as int32) === 0;
}

test "localToGlobal transforms point through world matrix" {
	const n = rect(10.0, 10.0, rgba(1.0, 1.0, 1.0, 1.0)).at(100.0, 200.0);
	n.sync(identity2d(), false);
	const gp = n.localToGlobal(vec2(5.0, 5.0));
	assert approx(gp.x, 105.0);
	assert approx(gp.y, 205.0);
}

test "globalToLocal inverse-transforms a point" {
	const n = rect(10.0, 10.0, rgba(1.0, 1.0, 1.0, 1.0)).at(100.0, 200.0);
	n.sync(identity2d(), false);
	const lp = n.globalToLocal(vec2(105.0, 205.0));
	assert approx(lp.x, 5.0);
	assert approx(lp.y, 5.0);
}

test "localToGlobal respects parent scale" {
	const root = group();
	root.scaleX = 2.0;
	root.scaleY = 3.0;
	const child = rect(1.0, 1.0, rgba(1.0, 1.0, 1.0, 1.0)).at(10.0, 10.0);
	root.addChild(child);
	root.sync(identity2d(), false);
	const gp = child.localToGlobal(vec2(5.0, 5.0));
	assert approx(gp.x, 30.0);
	assert approx(gp.y, 45.0);
}

test "label factory sets text size and color" {
	const n = label("Hello", 16.0, rgba(1.0, 0.5, 0.0, 1.0));
	assert n.kind === DrawKind.Label;
	assert n.text.equals("Hello");
	assert approx(n.size, 16.0);
	assert approx(n.color.r, 1.0);
	assert approx(n.color.g, 0.5);
}

test "mask factory sets dimensions" {
	const n = mask(200.0, 100.0);
	assert n.kind === DrawKind.Mask;
	assert approx(n.w, 200.0);
	assert approx(n.h, 100.0);
}

test "scaleGrid factory sets sheet and borders" {
	const t = tile(0, 100.0, 50.0);
	const n = scaleGrid(t, 10.0, 5.0, 10.0, 5.0);
	assert n.kind === DrawKind.ScaleGrid;
	assert approx(n.w, 100.0);
	assert approx(n.borderL, 10.0);
	assert approx(n.borderT, 5.0);
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
	const parent = group();
	const child = rect(4.0, 4.0, rgba(1.0, 0.0, 0.0, 1.0));
	const handle = parent.addChild(child);
	handle.alpha = 0.25;
	assert (parent.children.length as int32) == 1;
	assert parent.children[0].alpha == 0.25;
	assert parent.alpha == 1.0;

	// And a second child through the handle becomes a grandchild, not a sibling.
	const grand = handle.addChild(rect(2.0, 2.0, rgba(0.0, 1.0, 0.0, 1.0)));
	assert (parent.children.length as int32) == 1;
	assert (parent.children[0].children.length as int32) == 1;
	grand.alpha = 0.5;
	assert parent.children[0].children[0].alpha == 0.5;
}

test "addChildAt hands back the node that was added too" {
	const parent = group();
	parent.addChild(rect(4.0, 4.0, rgba(1.0, 0.0, 0.0, 1.0)));
	const inserted = parent.addChildAt(rect(2.0, 2.0, rgba(0.0, 1.0, 0.0, 1.0)), 0);
	inserted.alpha = 0.75;
	assert (parent.children.length as int32) == 2;
	assert parent.children[0].alpha == 0.75;
}
