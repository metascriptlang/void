import { NodeRef, GraphicsMesh, Scene2D, clear } from "../void2d/node";
import "../void2d/scene";
import { fillTriangle, fillRect, fillConvex, fillPolygon, fillCircle, fillEllipse, fillPie, fillRing, fillRoundedRect, fillTexRect, fillTexPolygon, strokeLine, strokePoly, strokeRect, quadBezier, cubicBezier } from "../void2d/graphics";
import { Vec2, vec2, rgba, tile, sub } from "../void2d/types";
import { approx, approxRel, meshTriArea, meshHasVert, meshHasVertUV, fakeTexture } from "./helpers";

const QUARTER: float32 = 1.5707963;
const PI_AREA_R10: float32 = 314.159;
const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));

function geometry(g: NodeRef): GraphicsMesh { return g.scene.meshes[g.scene.payloads[g.id.index]]; }

test "fillTriangle emits one triangle of 8-float verts" {
	const g = s.graphics().fillTriangle(vec2(0.0, 0.0), vec2(10.0, 0.0), vec2(0.0, 10.0), rgba(1.0, 0.0, 0.0, 1.0));
	assert (geometry(g).mesh.length as int32) === 24;
	assert geometry(g).stale;
	assert approx(geometry(g).mesh[0], 0.0);
	assert approx(geometry(g).mesh[1], 0.0);
	assert approx(geometry(g).mesh[4], 1.0);
	assert approx(geometry(g).mesh[5], 0.0);
	assert approx(geometry(g).mesh[7], 1.0);
	assert approxRel(meshTriArea(geometry(g).mesh), 50.0, 0.1);
}

test "fillRect emits two triangles covering the rect" {
	const g = s.graphics().fillRect(2.0, 3.0, 10.0, 5.0, rgba(1.0, 1.0, 1.0, 1.0));
	assert (geometry(g).mesh.length as int32) === 48;
	assert meshHasVert(geometry(g).mesh, 2.0, 3.0);
	assert meshHasVert(geometry(g).mesh, 12.0, 8.0);
	assert approxRel(meshTriArea(geometry(g).mesh), 50.0, 0.1);
}

test "fillConvex fans n-2 triangles" {
	const pts: Vec2[] = [vec2(0.0, 0.0), vec2(10.0, 0.0), vec2(12.0, 8.0), vec2(5.0, 12.0), vec2(-2.0, 8.0)];
	const g = s.graphics().fillConvex(pts, rgba(1.0, 1.0, 1.0, 1.0));
	assert (geometry(g).mesh.length as int32) === 72;
}

test "fillPolygon square matches shoelace area" {
	const pts: Vec2[] = [vec2(0.0, 0.0), vec2(10.0, 0.0), vec2(10.0, 10.0), vec2(0.0, 10.0)];
	const g = s.graphics().fillPolygon(pts, rgba(1.0, 1.0, 1.0, 1.0));
	assert (geometry(g).mesh.length as int32) === 48;
	assert approxRel(meshTriArea(geometry(g).mesh), 100.0, 0.1);
}

test "fillPolygon concave arrow ear-clips without overlap" {
	const pts: Vec2[] = [vec2(0.0, 32.0), vec2(48.0, 32.0), vec2(48.0, 6.0), vec2(95.0, 52.0), vec2(48.0, 98.0), vec2(48.0, 72.0), vec2(0.0, 72.0)];
	const g = s.graphics().fillPolygon(pts, rgba(1.0, 1.0, 1.0, 1.0));
	assert (geometry(g).mesh.length as int32) === 120;
	assert approxRel(meshTriArea(geometry(g).mesh), 4082.0, 0.5);
}

test "fillPolygon degenerate input emits nothing" {
	const two: Vec2[] = [vec2(0.0, 0.0), vec2(10.0, 0.0)];
	const g = s.graphics().fillPolygon(two, rgba(1.0, 1.0, 1.0, 1.0));
	assert (geometry(g).mesh.length as int32) === 0;
	const none: Vec2[] = [];
	const g2 = s.graphics().fillPolygon(none, rgba(1.0, 1.0, 1.0, 1.0));
	assert (geometry(g2).mesh.length as int32) === 0;
}

test "fillCircle area approximates pi r squared" {
	const g = s.graphics().fillCircle(0.0, 0.0, 10.0, rgba(1.0, 1.0, 1.0, 1.0));
	assert (geometry(g).mesh.length as int32) === 312;
	assert approxRel(meshTriArea(geometry(g).mesh), PI_AREA_R10, 5.0);
}

test "fillEllipse area approximates pi rx ry" {
	const g = s.graphics().fillEllipse(0.0, 0.0, 10.0, 5.0, rgba(1.0, 1.0, 1.0, 1.0));
	assert (geometry(g).mesh.length as int32) > 0;
	assert ((geometry(g).mesh.length as int32) % 24) === 0;
	assert approxRel(meshTriArea(geometry(g).mesh), 157.08, 5.0);
}

test "fillPie quarter slice area" {
	const g = s.graphics().fillPie(0.0, 0.0, 10.0, 0.0, QUARTER, rgba(1.0, 1.0, 1.0, 1.0));
	assert approxRel(meshTriArea(geometry(g).mesh), 78.54, 5.0);
	assert meshHasVert(geometry(g).mesh, 0.0, 0.0);
}

test "fillRing annulus area" {
	const TAU: float32 = 6.2831853;
	const g = s.graphics().fillRing(0.0, 0.0, 10.0, 5.0, 0.0, TAU, rgba(1.0, 1.0, 1.0, 1.0));
	assert approxRel(meshTriArea(geometry(g).mesh), 235.62, 5.0);
}

test "fillRoundedRect zero radius falls back to rect" {
	const g = s.graphics().fillRoundedRect(0.0, 0.0, 20.0, 10.0, 0.0, rgba(1.0, 1.0, 1.0, 1.0));
	assert (geometry(g).mesh.length as int32) === 48;
	assert approxRel(meshTriArea(geometry(g).mesh), 200.0, 0.1);
}

test "fillRoundedRect clamps radius to half min side" {
	const g = s.graphics().fillRoundedRect(0.0, 0.0, 20.0, 20.0, 100.0, rgba(1.0, 1.0, 1.0, 1.0));
	assert approxRel(meshTriArea(geometry(g).mesh), PI_AREA_R10, 5.0);
}

test "fillTexRect writes tile UVs and view" {
	const t = tile(fakeTexture(7), 64.0, 64.0).sub(16.0, 16.0, 32.0, 32.0);
	const g = s.graphics().fillTexRect(t, 0.0, 0.0, 32.0, 32.0, rgba(1.0, 1.0, 1.0, 1.0));
	assert geometry(g).source.view() === 7;
	assert (geometry(g).mesh.length as int32) === 48;
	assert meshHasVertUV(geometry(g).mesh, 0.0, 0.0, 0.25, 0.25);
	assert meshHasVertUV(geometry(g).mesh, 32.0, 32.0, 0.75, 0.75);
}

test "fillTexPolygon maps UVs from origin over tile size" {
	const t = tile(fakeTexture(9), 64.0, 64.0);
	const pts: Vec2[] = [vec2(0.0, 0.0), vec2(10.0, 0.0), vec2(10.0, 10.0), vec2(0.0, 10.0)];
	const g = s.graphics().fillTexPolygon(t, pts, 0.0, 0.0, 10.0, 10.0, rgba(1.0, 1.0, 1.0, 1.0));
	assert geometry(g).source.view() === 9;
	assert meshHasVertUV(geometry(g).mesh, 0.0, 0.0, 0.0, 0.0);
	assert meshHasVertUV(geometry(g).mesh, 10.0, 10.0, 1.0, 1.0);
}

test "clear resets mesh and view" {
	const g = s.graphics().fillRect(0.0, 0.0, 5.0, 5.0, rgba(1.0, 1.0, 1.0, 1.0));
	g.clear();
	assert (geometry(g).mesh.length as int32) === 0;
	assert geometry(g).source.view() === 0;
	assert geometry(g).stale;
}

test "strokeLine extrudes width perpendicular" {
	const g = s.graphics()
		.strokeLine(vec2(0.0, 0.0), vec2(10.0, 0.0), 4.0, rgba(1.0, 1.0, 1.0, 1.0));
	assert (geometry(g).mesh.length as int32) === 48;
	assert meshHasVert(geometry(g).mesh, 0.0, 2.0);
	assert meshHasVert(geometry(g).mesh, 10.0, 2.0);
	assert meshHasVert(geometry(g).mesh, 10.0, -2.0);
	assert meshHasVert(geometry(g).mesh, 0.0, -2.0);
}

test "strokeLine degenerate emits nothing" {
	const g = s.graphics()
		.strokeLine(vec2(5.0, 5.0), vec2(5.0, 5.0), 4.0, rgba(1.0, 1.0, 1.0, 1.0));
	assert (geometry(g).mesh.length as int32) === 0;
}

test "strokePoly open emits segment quads" {
	const pts: Vec2[] = [vec2(0.0, 0.0), vec2(10.0, 0.0), vec2(10.0, 10.0)];
	const g = s.graphics().strokePoly(pts, 2.0, rgba(1.0, 1.0, 1.0, 1.0), false);
	assert (geometry(g).mesh.length as int32) === 96;
}

test "strokePoly closed square miters right-angle corner" {
	const pts: Vec2[] = [vec2(0.0, 0.0), vec2(10.0, 0.0), vec2(10.0, 10.0), vec2(0.0, 10.0)];
	const g = s.graphics().strokePoly(pts, 2.0, rgba(1.0, 1.0, 1.0, 1.0), true);
	assert (geometry(g).mesh.length as int32) === 192;
	assert meshHasVert(geometry(g).mesh, 1.0, 1.0);
	assert meshHasVert(geometry(g).mesh, -1.0, -1.0);
}

test "strokeRect equals closed strokePoly" {
	const g = s.graphics().strokeRect(0.0, 0.0, 10.0, 10.0, 2.0, rgba(1.0, 1.0, 1.0, 1.0));
	assert (geometry(g).mesh.length as int32) === 192;
}

test "quadBezier hits endpoints and midpoint" {
	const pts = quadBezier(vec2(0.0, 0.0), vec2(5.0, 10.0), vec2(10.0, 0.0), 2);
	assert (pts.length as int32) === 3;
	assert approx(pts[0].x, 0.0);
	assert approx(pts[0].y, 0.0);
	assert approx(pts[1].x, 5.0);
	assert approx(pts[1].y, 5.0);
	assert approx(pts[2].x, 10.0);
	assert approx(pts[2].y, 0.0);
}

test "quadBezier clamps zero segments" {
	const pts = quadBezier(vec2(0.0, 0.0), vec2(5.0, 10.0), vec2(10.0, 0.0), 0);
	assert (pts.length as int32) === 2;
	assert approx(pts[0].x, 0.0);
	assert approx(pts[1].x, 10.0);
}

test "cubicBezier hits endpoints and midpoint" {
	const pts = cubicBezier(vec2(0.0, 0.0), vec2(0.0, 10.0), vec2(10.0, 10.0), vec2(10.0, 0.0), 2);
	assert (pts.length as int32) === 3;
	assert approx(pts[0].x, 0.0);
	assert approx(pts[0].y, 0.0);
	assert approx(pts[1].x, 5.0);
	assert approx(pts[1].y, 7.5);
	assert approx(pts[2].x, 10.0);
	assert approx(pts[2].y, 0.0);
}
