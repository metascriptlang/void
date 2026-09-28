import { DrawKind, Changed, NodeRef, Scene, TileCell, ALL_TILES } from "../void2d/node";
import { scene } from "../void2d/scene";
import { sync, getBounds } from "../void2d/render";
import { Bounds, Color, Tile, rgba, tile, identity2d, emptyBounds } from "../void2d/types";
import { approx } from "./helpers";

const HALF_PI: float32 = 1.5707963;
const white: Color = rgba(1.0, 1.0, 1.0, 1.0);

function fresh(): Scene { return scene(rgba(0.0, 0.0, 0.0, 1.0)); }

function cell(x: float32, y: float32, t: Tile): TileCell {
	return { x: x, y: y, tile: t, color: white, scaleX: 1.0, scaleY: 1.0, rotation: 0.0 };
}

function marked(n: NodeRef, what: Changed): boolean {
	return n.scene.changed[n.id.index].has(what);
}

function settled(n: NodeRef): void {
	n.scene.refOf(n.scene.root).sync(identity2d(), true);
	n.scene.clearChanges();
}

function cellAt(n: NodeRef, k: int32): TileCell {
	return n.scene.tileCells[n.scene.payloads[n.id.index]][k];
}

function three(): TileCell[] {
	return [cell(0.0, 0.0, tile(11, 8.0, 8.0)), cell(8.0, 0.0, tile(11, 8.0, 8.0)),
		cell(16.0, 0.0, tile(12, 8.0, 8.0))];
}

test "a tile group starts empty, with every tile in its range" {
	const s = fresh();
	const g = s.tileGroup();
	assert g.kind() === DrawKind.TileGroup;
	assert g.count() == 0;
	const row = s.tileGroups[s.payloads[g.id.index]];
	assert row.first == 0 && row.count == ALL_TILES;
}

test "setTiles replaces the tiles and marks the group; the same tiles again mark nothing" {
	const s = fresh();
	const g = s.add(s.tileGroup());
	settled(g);
	g.setTiles(three());
	assert g.count() == 3;
	assert cellAt(g, 2).tile.view == 12;
	assert marked(g, Changed.Content);
	settled(g);
	g.setTiles(three());
	assert !marked(g, Changed.Content);
	const two: TileCell[] = [cell(1.0, 2.0, tile(13, 4.0, 4.0)), cell(3.0, 4.0, tile(13, 4.0, 4.0))];
	g.setTiles(two);
	assert g.count() == 2;
	assert cellAt(g, 0).tile.view == 13 && approx(cellAt(g, 1).y, 4.0);
	assert marked(g, Changed.Content);
}

test "appendTiles grows the group and leaves the tiles already there as they were" {
	const s = fresh();
	const g = s.add(s.tileGroup());
	g.setTiles(three());
	settled(g);
	const more: TileCell[] = [cell(24.0, 0.0, tile(12, 8.0, 8.0))];
	g.appendTiles(more);
	assert g.count() == 4;
	assert approx(cellAt(g, 0).x, 0.0) && approx(cellAt(g, 3).x, 24.0);
	assert marked(g, Changed.Content);
	settled(g);
	const none: TileCell[] = [];
	g.appendTiles(none);
	assert !marked(g, Changed.Content);
}

test "setTile rewrites one tile; the same tile again marks nothing" {
	const s = fresh();
	const g = s.add(s.tileGroup());
	g.setTiles(three());
	settled(g);
	const red: TileCell = { ...cell(8.0, 0.0, tile(11, 8.0, 8.0)), color: rgba(1.0, 0.0, 0.0, 1.0) };
	g.setTile(1, red);
	assert approx(cellAt(g, 1).color.g, 0.0);
	assert approx(cellAt(g, 0).color.g, 1.0) && approx(cellAt(g, 2).color.g, 1.0);
	assert marked(g, Changed.Content);
	settled(g);
	g.setTile(1, red);
	assert !marked(g, Changed.Content);
}

test "setRange marks the group; the same range again marks nothing" {
	const s = fresh();
	const g = s.add(s.tileGroup());
	g.setTiles(three());
	settled(g);
	g.setRange(1, 1);
	const row = s.tileGroups[s.payloads[g.id.index]];
	assert row.first == 1 && row.count == 1;
	assert marked(g, Changed.Content);
	settled(g);
	g.setRange(1, 1);
	assert !marked(g, Changed.Content);
}

test "clear empties a group and marks it; clearing an empty group marks nothing" {
	const s = fresh();
	const g = s.add(s.tileGroup());
	g.setTiles(three());
	settled(g);
	g.clear();
	assert g.count() == 0;
	assert marked(g, Changed.Content);
	settled(g);
	g.clear();
	assert !marked(g, Changed.Content);
}

test "a group's bounds hold every tile's corners, turned and scaled, whatever its range" {
	const s = fresh();
	const g = s.add(s.tileGroup()).at(100.0, 50.0);
	const centred: Tile = { ...tile(11, 8.0, 4.0), dx: -4.0, dy: -2.0 };
	const cells: TileCell[] = [
		cell(0.0, 0.0, tile(11, 10.0, 10.0)),
		{ ...cell(10.0, 20.0, centred), scaleX: 2.0, scaleY: 2.0, rotation: HALF_PI },
	];
	g.setTiles(cells);
	g.setRange(0, 1);
	settled(g);
	let b: Bounds = emptyBounds();
	g.getBounds(b);
	assert approx(b.xMin, 100.0) && approx(b.yMin, 50.0);
	assert approx(b.xMax, 114.0) && approx(b.yMax, 78.0);
}

test "an empty group bounds as a point at its origin" {
	const s = fresh();
	const g = s.add(s.tileGroup()).at(7.0, 9.0);
	settled(g);
	let b: Bounds = emptyBounds();
	g.getBounds(b);
	assert approx(b.xMin, 7.0) && approx(b.xMax, 7.0) && approx(b.yMin, 9.0) && approx(b.yMax, 9.0);
}

test "a disposed group's row is taken again, empty" {
	const s = fresh();
	const g = s.add(s.tileGroup());
	g.setTiles(three());
	const payload: int32 = s.payloads[g.id.index];
	g.dispose();
	const again = s.add(s.tileGroup());
	assert s.payloads[again.id.index] == payload;
	assert again.count() == 0;
	const row = s.tileGroups[payload];
	assert row.first == 0 && row.count == ALL_TILES;
}
