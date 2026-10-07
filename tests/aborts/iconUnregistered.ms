// expect: void2d icon: scene.icon: icon 7 is not registered
// flags: -d:voidSvg
import { IconId } from "../../src/void2d/icon";
import { Scene2D } from "../../src/void2d/node";
import "../../src/void2d/scene";
import { rgba } from "../../src/void2d/types";

const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
s.icon(7 as IconId, 24.0, 24.0, rgba(1.0, 1.0, 1.0, 1.0));
console.log("an icon nobody registered was drawn");
