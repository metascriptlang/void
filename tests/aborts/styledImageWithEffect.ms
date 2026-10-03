// expect: void2d: an image style cannot take a colorMatrix, colorAdd or colorKey
import "../../src/sokol/gpu";
import { begin2d, finishRecording } from "../../src/void2d/draw";
import { Scene2D } from "../../src/void2d/node";
import { add } from "../../src/void2d/scene";
import { draw, sync } from "../../src/void2d/render";
import { rgba, tile, identity2d } from "../../src/void2d/types";
import { imageStyle, ObjectFit } from "../../src/void2d/imageStyle";
import { colorMatrixGrayscale } from "../../src/void2d/effect";

const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
const image = s.sprite(tile(17, 64.0, 64.0));
image.setImageStyle(imageStyle(
	{ topLeft: 4.0, topRight: 4.0, bottomRight: 4.0, bottomLeft: 4.0 },
	false,
	ObjectFit.Cover,
));
image.setColorMatrix(colorMatrixGrayscale(1.0));
s.add(image);
const root = s.refOf(s.root);
begin2d(64.0, 64.0, 1.0);
root.sync(identity2d(), true);
root.draw(1.0, 64.0, 64.0);
finishRecording();
console.log("an image style with a colour matrix was dropped");
