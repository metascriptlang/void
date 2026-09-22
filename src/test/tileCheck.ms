import { Tile, tile, sub, center, setCenterRatio, flipX, flipY } from "../void2d/types";
import { approx } from "./helpers";

test "tile covers full texture" {
	const t = tile(3, 64.0, 32.0);
	assert t.view === 3;
	assert approx(t.u0, 0.0);
	assert approx(t.v0, 0.0);
	assert approx(t.u1, 1.0);
	assert approx(t.v1, 1.0);
	assert approx(t.w, 64.0);
	assert approx(t.h, 32.0);
	assert approx(t.texW, 64.0);
	assert approx(t.texH, 32.0);
}
test "center and setCenterRatio place the visual origin without changing UVs" {
	const original = tile(3, 64.0, 32.0);
	const centered = original.center();
	assert approx(original.dx, 0.0);
	assert approx(original.dy, 0.0);
	assert approx(centered.dx, -32.0);
	assert approx(centered.dy, -16.0);
	assert approx(centered.u0, original.u0);
	assert approx(centered.v1, original.v1);
	let ratio = original;
	setCenterRatio(ratio, 0.25, 0.75);
	assert approx(ratio.dx, -16.0);
	assert approx(ratio.dy, -24.0);
}


test "sub maps pixel rect to UVs" {
	const s = tile(3, 64.0, 64.0).sub(16.0, 16.0, 32.0, 32.0);
	assert s.view === 3;
	assert approx(s.u0, 0.25);
	assert approx(s.v0, 0.25);
	assert approx(s.u1, 0.75);
	assert approx(s.v1, 0.75);
	assert approx(s.w, 32.0);
	assert approx(s.h, 32.0);
	assert approx(s.texW, 64.0);
	assert approx(s.texH, 64.0);
}
test "sub resets the visual offset like h2d Tile.sub" {
	const centered = tile(3, 64.0, 64.0).center();
	const s = centered.sub(8.0, 8.0, 16.0, 24.0);
	assert approx(s.dx, 0.0);
	assert approx(s.dy, 0.0);
}


test "flipX swaps horizontal UVs and mirrors the visual offset" {
	const s = tile(1, 64.0, 64.0).sub(0.0, 0.0, 16.0, 16.0);
	const f = s.flipX();
	assert approx(f.u0, s.u1);
	assert approx(f.u1, s.u0);
	assert approx(f.v0, s.v0);
	assert approx(f.v1, s.v1);
	assert approx(f.w, s.w);
	assert approx(f.h, s.h);
	assert approx(f.dx, -16.0);
	assert approx(f.dy, 0.0);
}

test "flipY swaps vertical UVs and mirrors the visual offset" {
	const s = tile(1, 64.0, 64.0).sub(0.0, 0.0, 16.0, 16.0);
	const f = s.flipY();
	assert approx(f.v0, s.v1);
	assert approx(f.v1, s.v0);
	assert approx(f.u0, s.u0);
	assert approx(f.u1, s.u1);
	assert approx(f.dx, 0.0);
	assert approx(f.dy, -16.0);
}

test "double flip restores original UVs and offsets" {
	const s = tile(1, 128.0, 128.0).sub(32.0, 0.0, 64.0, 64.0);
	const f = s.flipX().flipX();
	assert approx(f.u0, s.u0);
	assert approx(f.u1, s.u1);
	assert approx(f.v0, s.v0);
	assert approx(f.v1, s.v1);
	assert approx(f.dx, s.dx);
	assert approx(f.dy, s.dy);
}
