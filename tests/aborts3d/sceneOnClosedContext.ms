// expect: void3d: Scene3D.create on a draw context that was closed
import { DrawContext, closeContext } from "../../src/void3d/draw";
import { Scene3D } from "../../src/void3d/scene";

let context: DrawContext = DrawContext.withUniformCapacity(0);
let alias: DrawContext = context;
closeContext(context);
const _scene: Scene3D = Scene3D.create(alias);
console.log("a closed context made a scene");
