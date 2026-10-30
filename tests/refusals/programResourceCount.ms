// expect: 50:15 shaderProgram 'crowded': a shader module has over 16 resources
import { shaderProgram } from "../../src/shader/program";
import { Texture2d, Vec2i, Vec4f, binding, builtin, textureLoad } from "../../src/shader/std";
struct In {
	position: Vec4f;
}
struct Out {
	@builtin(position) position: Vec4f;
}
struct Crowd {
	@binding(0) t0: Texture2d;
	@binding(1) t1: Texture2d;
	@binding(2) t2: Texture2d;
	@binding(3) t3: Texture2d;
	@binding(4) t4: Texture2d;
	@binding(5) t5: Texture2d;
	@binding(6) t6: Texture2d;
	@binding(7) t7: Texture2d;
	@binding(8) t8: Texture2d;
	@binding(9) t9: Texture2d;
	@binding(10) t10: Texture2d;
	@binding(11) t11: Texture2d;
	@binding(12) t12: Texture2d;
	@binding(13) t13: Texture2d;
	@binding(14) t14: Texture2d;
	@binding(15) t15: Texture2d;
	@binding(16) t16: Texture2d;
}
function crowdedVs(input: In): Out { return { position: input.position }; }
function crowdedFs(b: Crowd): Vec4f {
	const at: Vec2i = { x: 0, y: 0 };
	return textureLoad(b.t0, at, 0) +
		textureLoad(b.t1, at, 0) +
		textureLoad(b.t2, at, 0) +
		textureLoad(b.t3, at, 0) +
		textureLoad(b.t4, at, 0) +
		textureLoad(b.t5, at, 0) +
		textureLoad(b.t6, at, 0) +
		textureLoad(b.t7, at, 0) +
		textureLoad(b.t8, at, 0) +
		textureLoad(b.t9, at, 0) +
		textureLoad(b.t10, at, 0) +
		textureLoad(b.t11, at, 0) +
		textureLoad(b.t12, at, 0) +
		textureLoad(b.t13, at, 0) +
		textureLoad(b.t14, at, 0) +
		textureLoad(b.t15, at, 0) +
		textureLoad(b.t16, at, 0);
}
shaderProgram(crowded, crowdedVs, crowdedFs);
