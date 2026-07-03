import { Node2D, DrawKind, group, rect, sprite, anim, addChild, at, update, sync } from "../void2d/node";
import { Tile, tile, rgba, identity2d, BlendMode } from "../void2d/types";
import { approx } from "./helpers";

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
