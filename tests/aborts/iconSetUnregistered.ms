// expect: void2d icon: setIcon: icon 7 is not registered
// flags: -d:voidSvg
import { IconId, registerIcon } from "../../src/void2d/icon";
import { Scene2D } from "../../src/void2d/node";
import "../../src/void2d/scene";
import { rgba } from "../../src/void2d/types";

const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
const r = registerIcon(
	`<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8" viewBox="0 0 8 8">` +
	`<rect width="8" height="8"/></svg>`,
);
if (r.ok) { s.icon(r.value, 24.0, 24.0, rgba(1.0, 1.0, 1.0, 1.0)).setIcon(7 as IconId); }
console.log("an icon was switched to one nobody registered");
