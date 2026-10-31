// expect: 18:15 shaderProgram 'bigBlockProgram': uniform block 'big' is 65552 bytes; a uniform buffer binding holds at most 65536 bytes
import { shaderProgram } from "../../src/shader/program";
import { Mat4x4f, Vec4f, binding, builtin } from "../../src/shader/std";
struct In {
	position: Vec4f;
}
struct Out {
	@builtin(position) position: Vec4f;
}
struct Big {
	items: Vec4f[4097];
}
struct BigBindings {
	@binding(0) big: Big;
}
function bigVs(input: In): Out { return { position: input.position }; }
function bigFs(b: BigBindings): Vec4f { return b.big.items[0]; }
shaderProgram(bigBlockProgram, bigVs, bigFs);
