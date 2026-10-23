// expect: 15:34 textureSampleBias samples only in a fragment entry, as WGSL's does
import { glsl } from "../../src/shader/emit";
import { Sampler, Texture2d, Vec2f, Vec4f, binding, builtin, textureSampleBias, vec4f } from "../../src/shader/std";
struct Corner {
	position: Vec2f;
}
struct Placed {
	@builtin(position) clip: Vec4f;
}
struct Terrain {
	@binding(0) height: Texture2d;
	@binding(0) heightSampler: Sampler;
}
function liftedVs(input: Corner, b: Terrain): Placed {
	const height = textureSampleBias(b.height, b.heightSampler, input.position, 1.0);
	return { clip: vec4f(input.position.x, input.position.y, height.x, 1.0) };
}
console.log(glsl(liftedVs));
