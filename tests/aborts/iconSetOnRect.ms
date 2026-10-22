// expect: setIcon asked of a Rect node
// flags: -d:voidSvg
import { registerIcon } from "../../src/void2d/icon";
import { Scene2D } from "../../src/void2d/node";
import "../../src/void2d/scene";
import { rgba } from "../../src/void2d/types";

const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
const r = registerIcon(
	`<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8" viewBox="0 0 8 8">` +
	`<rect width="8" height="8"/></svg>`,
);
if (r.ok) { s.rect(40.0, 20.0, rgba(1.0, 1.0, 1.0, 1.0)).setIcon(r.value); }
console.log("a Rect took an icon");
