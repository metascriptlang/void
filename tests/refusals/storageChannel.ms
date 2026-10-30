// expect: 8:14 storage texture 'image' holds u32 texels, and @format(r32sint) gives i32
import { glslCompute } from "../../src/shader/emit";
import { StorageTexture2dU32, Vec3u, binding, builtin, format, textureStore, vec2i, vec4u } from "../../src/shader/std";
struct Id {
	@builtin(globalInvocationId) id: Vec3u;
}
struct Images {
	@binding(1) @format(r32sint) image: StorageTexture2dU32;
}
function paint(input: Id, b: Images): void {
	textureStore(b.image, vec2i(0, 0), vec4u(1, 0, 0, 1));
}
console.log(glslCompute(paint, [32, 1, 1]));
