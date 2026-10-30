// expect: 8:2 shaderCompute builds one program, so 'wide' cannot be @feature
import { shaderCompute } from "../../src/shader/program";
import { Vec3u, builtin, feature } from "../../src/shader/std";
struct In {
	@builtin(globalInvocationId) id: Vec3u;
}
struct Key {
	@feature(WIDE) wide: boolean;
}
function featured(input: In, key: Key): void {}
shaderCompute(family, featured, [64, 1, 1]);
