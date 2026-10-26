// expect: 13:25 printGlsl450: bgra8unorm has no GLSL image format
import { glslCompute } from "../../src/shader/emit";
import { StorageTexture2d, Vec3u, binding, builtin, format, textureStore, vec2i, vec4f } from "../../src/shader/std";
struct Id {
	@builtin(globalInvocationId) id: Vec3u;
}
struct Images {
	@binding(1) @format(bgra8unorm) image: StorageTexture2d;
}
function paint(input: Id, b: Images): void {
	textureStore(b.image, vec2i(0, 0), vec4f(1.0, 0.0, 0.0, 1.0));
}
console.log(glslCompute(paint, [32, 1, 1]));
