// expect: void2d: setPaint cannot move a node's color matrix row
import "../../src/sokol/gpu";
import { Scene2D } from "../../src/void2d/node";
import "../../src/void2d/scene";
import { rgba } from "../../src/void2d/types";
import { colorMatrixGrayscale } from "../../src/void2d/effect";

const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
const white = rgba(1.0, 1.0, 1.0, 1.0);
const grey = s.rect(4.0, 4.0, white).setColorMatrix(colorMatrixGrayscale(1.0));
const plain = s.rect(4.0, 4.0, white);
plain.setPaint(grey.paint());
console.log("a paint carried another node's color matrix row across");
