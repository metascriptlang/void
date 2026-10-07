// expect: gpu door: detach on a texture that was closed
import { Texture } from "../../src/gpu/texture";

const texture: Texture = Texture.adopt(3, 9, 2, 2);
const _first = texture.detach();
const _second = texture.detach();
console.log("a texture detached twice returned");
