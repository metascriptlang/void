// expect: gpu door: close on a texture that was closed
import { Texture } from "../../src/gpu/texture";

const texture: Texture = Texture.adopt(3, 9, 2, 2);
const _handles = texture.detach();
texture.close();
console.log("a texture closed after detach returned");
