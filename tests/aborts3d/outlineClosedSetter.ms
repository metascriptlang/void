// expect: void3d: setOutlineBlend on a forward preset that was closed
import { DrawContext } from "../../src/void3d/draw";
import { ForwardOutlineSettings } from "../../src/void3d/forwardOutline";
import {
	ForwardRenderer, FORWARD_UNIFORM_LENGTH, setOutlineBlend, setOutlineSettings, closeForward,
} from "../../src/void3d/forwardRenderer";
const context: DrawContext = DrawContext.withUniformCapacity(FORWARD_UNIFORM_LENGTH);
const made = ForwardRenderer.create(context, { x: 0.0, y: 0.0, z: 0.0, w: 0.0 });
if (!made.ok) { unreachable; }
const renderer: ForwardRenderer = made.value;
closeForward(renderer);
setOutlineBlend(renderer, 0.5);
