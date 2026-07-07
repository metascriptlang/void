import { Vec2, Transform2D, vec2, trs2d, identity2d, inverse2d, camera, viewMatrix } from "../void2d/types";
import { approx } from "./helpers";

const HALF_PI: float32 = 1.5707963;

test "identity maps point to itself" {
	const p = vec2(3.0, -4.0) * identity2d();
	assert approx(p.x, 3.0);
	assert approx(p.y, -4.0);
}

test "translate moves point" {
	const p = vec2(1.0, 2.0) * trs2d(10.0, 20.0, 0.0, 1.0, 1.0);
	assert approx(p.x, 11.0);
	assert approx(p.y, 22.0);
}

test "scale multiplies point" {
	const p = vec2(1.0, 1.0) * trs2d(0.0, 0.0, 0.0, 2.0, 3.0);
	assert approx(p.x, 2.0);
	assert approx(p.y, 3.0);
}

test "rotate 90deg maps +x to +y" {
	const p = vec2(1.0, 0.0) * trs2d(0.0, 0.0, HALF_PI, 1.0, 1.0);
	assert approx(p.x, 0.0);
	assert approx(p.y, 1.0);
}

test "trs applies scale then rotate then translate" {
	const p = vec2(1.0, 0.0) * trs2d(10.0, 20.0, HALF_PI, 2.0, 2.0);
	assert approx(p.x, 10.0);
	assert approx(p.y, 22.0);
}

test "compose applies right operand first" {
	const world = trs2d(10.0, 0.0, 0.0, 1.0, 1.0) * trs2d(0.0, 0.0, 0.0, 2.0, 2.0);
	const p = vec2(1.0, 0.0) * world;
	assert approx(p.x, 12.0);
	assert approx(p.y, 0.0);
}

test "compose is order sensitive" {
	const tThenR = trs2d(0.0, 0.0, HALF_PI, 1.0, 1.0) * trs2d(10.0, 0.0, 0.0, 1.0, 1.0);
	const rThenT = trs2d(10.0, 0.0, 0.0, 1.0, 1.0) * trs2d(0.0, 0.0, HALF_PI, 1.0, 1.0);
	const a = vec2(0.0, 0.0) * tThenR;
	const b = vec2(0.0, 0.0) * rThenT;
	assert approx(a.x, 0.0);
	assert approx(a.y, 10.0);
	assert approx(b.x, 10.0);
	assert approx(b.y, 0.0);
}

test "default camera is identity" {
	const m = camera().viewMatrix(800.0, 600.0);
	assert approx(m.a, 1.0);
	assert approx(m.b, 0.0);
	assert approx(m.c, 0.0);
	assert approx(m.d, 1.0);
	assert approx(m.tx, 0.0);
	assert approx(m.ty, 0.0);
}

test "camera shows target at anchor with zoom" {
	let cam = camera();
	cam.x = 100.0;
	cam.y = 50.0;
	cam.zoom = 2.0;
	cam.anchorX = 0.5;
	cam.anchorY = 0.5;
	const m = cam.viewMatrix(800.0, 600.0);
	const center = vec2(100.0, 50.0) * m;
	assert approx(center.x, 400.0);
	assert approx(center.y, 300.0);
	const offset = vec2(150.0, 50.0) * m;
	assert approx(offset.x, 500.0);
	assert approx(offset.y, 300.0);
}

test "inverse of identity is identity" {
	const inv = inverse2d(identity2d());
	assert approx(inv.a, 1.0);
	assert approx(inv.b, 0.0);
	assert approx(inv.c, 0.0);
	assert approx(inv.d, 1.0);
	assert approx(inv.tx, 0.0);
	assert approx(inv.ty, 0.0);
}

test "inverse of translate is negated translate" {
	const m = trs2d(10.0, 20.0, 0.0, 1.0, 1.0);
	const inv = inverse2d(m);
	const p = vec2(10.0, 20.0) * inv;
	assert approx(p.x, 0.0);
	assert approx(p.y, 0.0);
}

test "inverse of scale is reciprocal scale" {
	const m = trs2d(0.0, 0.0, 0.0, 2.0, 4.0);
	const inv = inverse2d(m);
	const p = vec2(2.0, 8.0) * inv;
	assert approx(p.x, 1.0);
	assert approx(p.y, 2.0);
}

test "inverse of degenerate transform returns identity" {
	const m: Transform2D = { a: 0.0, b: 0.0, c: 0.0, d: 0.0, tx: 5.0, ty: 5.0 };
	const inv = inverse2d(m);
	assert approx(inv.a, 1.0);
	assert approx(inv.d, 1.0);
}

test "compose then inverse round-trips a point" {
	const m = trs2d(30.0, 40.0, 0.3, 2.0, 3.0);
	const p = vec2(7.0, 11.0);
	const world = p * m;
	const back = world * inverse2d(m);
	assert approx(back.x, 7.0);
	assert approx(back.y, 11.0);
}
