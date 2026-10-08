// expect: got a checker BoxFill with cell 0; it must be > 0
import { Scene2D } from "../../src/void2d/node";
import "../../src/void2d/scene";
import { rgba } from "../../src/void2d/types";
import {
	BoxFillKind, BoxStyle, solidFill, uniformBorders, uniformRadii,
} from "../../src/void2d/boxStyle";

const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
const style = BoxStyle.create(uniformRadii(2.0), uniformBorders(0.0), rgba(0.0, 0.0, 0.0, 0.0));
const box = s.add(s.rect(10.0, 10.0, rgba(1.0, 1.0, 1.0, 1.0)));
box.setBoxStyle({ ...style, fill: { ...solidFill(), kind: BoxFillKind.Checker, cell: 0.0 } });
console.log("a checker fill of no cell size was taken");
