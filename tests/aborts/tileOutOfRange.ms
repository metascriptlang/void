// expect: setTile(3) on tile group 1, which holds 3 tiles
import { fakeTexture } from "../../src/test/helpers";
import "../../src/sokol/gpu";
import { Scene2D, TileCell } from "../../src/void2d/node";
import "../../src/void2d/scene";
import { rgba, tile } from "../../src/void2d/types";

const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
const map = s.add(s.tileGroup());
const one: TileCell = {
	x: 0.0, y: 0.0, tile: tile(fakeTexture(11), 8.0, 8.0), color: rgba(1.0, 1.0, 1.0, 1.0), scaleX: 1.0,
	scaleY: 1.0, rotation: 0.0,
};
const three: TileCell[] = [one, one, one];
map.setTiles(three);
map.setTile(3, one);
console.log("a tile past the end of its group was written");
