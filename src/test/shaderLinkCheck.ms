import { mkdir, writeFile } from "std/fs";
import { programModule, programSource, stageSource } from "../shader/descriptor";
import { glslIr, glslLinkedIr, glslSegmentIr } from "../shader/emit";
import {
	ExprKind,
	Intrinsic,
	IoDirection,
	ShaderExpr,
	ShaderModule,
	ShaderStage,
	StmtKind,
	exprOf,
	irErrors,
	rootOf,
} from "../shader/ir";
import { irFromText, irText } from "../shader/irText";
import { ShaderTarget } from "../shader/layout";
import { link, linkedProgram } from "../shader/link";
import {
	Sampler,
	Texture2d,
	Vec2f,
	Vec3f,
	Vec4f,
	binding,
	builtin,
	discard,
	feature,
	hook,
	length,
	textureSample,
	vec2f,
	vec3f,
	vec4f,
} from "../shader/std";

struct UvStage {
	uv: Vec2f;
}

struct Frame {
	time: float32;
}

struct ScrollBindings {
	frame: Frame;
}

function uvScroll(stage: UvStage, b: ScrollBindings): UvStage {
	return { uv: stage.uv + vec2f(b.frame.time, 0.0) };
}

struct Shaded {
	color: Vec4f;
}

struct Tint {
	tint: Vec4f;
}

struct TintBindings {
	tintParams: Tint;
}

function colourAdd(shaded: Shaded, b: TintBindings): Shaded {
	return { color: shaded.color + b.tintParams.tint };
}

function killAlpha(shaded: Shaded): Shaded {
	if (shaded.color.w < 0.5) { discard(); }
	return shaded;
}

struct Depth {
	z: float32;
}

function depthBias(depth: Depth): Depth {
	return { z: depth.z + 0.5 };
}

struct Corner {
	position: Vec2f;
}

struct Placed {
	@builtin(position) clip: Vec4f;
	uv: Vec2f;
}

struct Pixel {
	@builtin(position) position: Vec4f;
	uv: Vec2f;
}

struct BaseBindings {
	@binding(0) frame: Frame;
}

function baseVs(input: Corner): Placed {
	return { clip: vec4f(input.position.x, input.position.y, 0.0, 1.0), uv: input.position };
}

function baseFs(input: Pixel, b: BaseBindings): Vec4f {
	const start: UvStage = { uv: input.uv };
	const stage = hook(start);
	const lit: Shaded = { color: vec4f(stage.uv.x, stage.uv.y, b.frame.time, 1.0) };
	return hook(lit).color;
}

function plainFs(input: Pixel, b: BaseBindings): Vec4f {
	return vec4f(input.uv.x, input.uv.y, b.frame.time, 1.0);
}

struct Surface {
	base: Vec2f;
	detail: Vec2f;
}

struct SplitPlaced {
	@builtin(position) clip: Vec4f;
	a: Vec2f;
	b: Vec2f;
}

struct SplitPixel {
	@builtin(position) position: Vec4f;
	a: Vec2f;
	b: Vec2f;
}

function splitVs(input: Corner): SplitPlaced {
	return {
		clip: vec4f(input.position.x, input.position.y, 0.0, 1.0),
		a: input.position,
		b: vec2f(input.position.y, input.position.x),
	};
}

function splitFs(input: SplitPixel): Vec4f {
	const start: Surface = { base: input.a, detail: input.b };
	const surface = hook(start);
	return vec4f(surface.base.x, surface.base.y, 0.0, 1.0);
}

function addDetail(surface: Surface): Surface {
	return { base: surface.base + surface.detail, detail: surface.detail };
}

function chainedFs(input: Pixel, b: BaseBindings, tint: TintBindings): Vec4f {
	const stage = uvScroll({ uv: input.uv }, { frame: b.frame });
	const lit: Shaded = { color: vec4f(stage.uv.x, stage.uv.y, b.frame.time, 1.0) };
	return killAlpha(colourAdd(lit, tint)).color;
}

const LINKED =
	"[[],[[\"Frame\",[[\"time\",[1,0,1,1,0,[],-1,0,0,0]]]],[\"UvStage\",[[\"uv\",[2,0,2,1,0,[" +
	"],-1,0,0,0]]]],[\"Shaded\",[[\"color\",[2,0,4,1,0,[],-1,0,0,0]]]],[\"Tint\",[[\"tint\",[" +
	"2,0,4,1,0,[],-1,0,0,0]]]]],[],[[0,\"frame\",0,0,[6,0,1,1,0,[],0,0,0,0],0,0,0,[0,\"\",[]]" +
	"],[0,\"tintParams\",0,1,[6,0,1,1,0,[],3,0,0,0],0,0,0,[0,\"\",[]]]],[[\"position\",0,0,[" +
	"2,0,2,1,0,[],-1,0,0,0],-1,0,0,0,[0,\"\",[]]],[\"clip\",0,1,[2,0,4,1,0,[],-1,0,0,0],-1,3," +
	"0,0,[0,\"\",[]]],[\"uv\",0,1,[2,0,2,1,0,[],-1,0,0,0],-1,0,0,0,[0,\"\",[]]],[\"position\"" +
	",1,0,[2,0,4,1,0,[],-1,0,0,0],-1,3,0,0,[0,\"\",[]]],[\"uv\",1,0,[2,0,2,1,0,[],-1,0,0,0],-" +
	"1,0,0,0,[0,\"\",[]]],[\"fragColor\",1,1,[2,0,4,1,0,[],-1,0,0,0],0,0,0,0,[0,\"\",[]]]],[[" +
	"\"baseVs\",[],[],[0,0,1,1,0,[],-1,0,0,0],[[2,-1,0,[4,[2,0,4,1,0,[],-1,0,0,0],0,1,-1,0,0," +
	"0,[],false,[]],[12,[2,0,4,1,0,[],-1,0,0,0],0,-1,-1,0,0,0,[],false,[[15,[1,0,1,1,0,[],-1," +
	"0,0,0],0,-1,-1,0,0,0,[0],false,[[4,[2,0,2,1,0,[],-1,0,0,0],0,0,-1,0,0,0,[],false,[]]]],[" +
	"15,[1,0,1,1,0,[],-1,0,0,0],0,-1,-1,0,0,0,[1],false,[[4,[2,0,2,1,0,[],-1,0,0,0],0,0,-1,0," +
	"0,0,[],false,[]]]],[0,[1,0,1,1,0,[],-1,0,0,0],0,-1,-1,0,0,0,[],false,[]],[0,[1,0,1,1,0,[" +
	"],-1,0,0,0],1,-1,-1,0,0,0,[],false,[]]]],[0,\"\",[]],[],[],[],[],[]],[2,-1,0,[4,[2,0,2,1" +
	",0,[],-1,0,0,0],0,2,-1,0,0,0,[],false,[]],[4,[2,0,2,1,0,[],-1,0,0,0],0,0,-1,0,0,0,[],fal" +
	"se,[]],[0,\"\",[]],[],[],[],[],[]],[11,-1,0,[0,[0,0,1,1,0,[],-1,0,0,0],0,-1,-1,0,0,0,[]," +
	"false,[]],[0,[0,0,1,1,0,[],-1,0,0,0],0,-1,-1,0,0,0,[],false,[]],[0,\"\",[]],[],[],[],[]," +
	"[]]],[0,\"\",[]]],[\"baseFs\",[],[[\"start\",[6,0,1,1,0,[],1,0,0,0]],[\"stage\",[6,0,1,1" +
	",0,[],1,0,0,0]],[\"lit\",[6,0,1,1,0,[],2,0,0,0]]],[0,0,1,1,0,[],-1,0,0,0],[[1,0,0,[0,[0," +
	"0,1,1,0,[],-1,0,0,0],0,-1,-1,0,0,0,[],false,[]],[12,[6,0,1,1,0,[],1,0,0,0],0,-1,-1,0,0,0" +
	",[],false,[[4,[2,0,2,1,0,[],-1,0,0,0],0,4,-1,0,0,0,[],false,[]]]],[0,\"\",[]],[],[],[],[" +
	"],[]],[1,1,0,[0,[0,0,1,1,0,[],-1,0,0,0],0,-1,-1,0,0,0,[],false,[]],[10,[6,0,1,1,0,[],1,0" +
	",0,0],0,2,-1,0,0,0,[],false,[[1,[6,0,1,1,0,[],1,0,0,0],0,0,-1,0,0,0,[],false,[]]]],[0,\"" +
	"\",[]],[],[],[],[],[]],[1,2,0,[0,[0,0,1,1,0,[],-1,0,0,0],0,-1,-1,0,0,0,[],false,[]],[12," +
	"[6,0,1,1,0,[],2,0,0,0],0,-1,-1,0,0,0,[],false,[[12,[2,0,4,1,0,[],-1,0,0,0],0,-1,-1,0,0,0" +
	",[],false,[[15,[1,0,1,1,0,[],-1,0,0,0],0,-1,-1,0,0,0,[0],false,[[14,[2,0,2,1,0,[],-1,0,0" +
	",0],0,0,-1,0,0,0,[],false,[[1,[6,0,1,1,0,[],1,0,0,0],0,1,-1,0,0,0,[],false,[]]]]]],[15,[" +
	"1,0,1,1,0,[],-1,0,0,0],0,-1,-1,0,0,0,[1],false,[[14,[2,0,2,1,0,[],-1,0,0,0],0,0,-1,0,0,0" +
	",[],false,[[1,[6,0,1,1,0,[],1,0,0,0],0,1,-1,0,0,0,[],false,[]]]]]],[6,[1,0,1,1,0,[],-1,0" +
	",0,0],0,0,0,0,0,0,[],false,[]],[0,[1,0,1,1,0,[],-1,0,0,0],1,-1,-1,0,0,0,[],false,[]]]]]]" +
	",[0,\"\",[]],[],[],[],[],[]],[2,-1,0,[4,[2,0,4,1,0,[],-1,0,0,0],0,5,-1,0,0,0,[],false,[]" +
	"],[14,[2,0,4,1,0,[],-1,0,0,0],0,0,-1,0,0,0,[],false,[[10,[6,0,1,1,0,[],2,0,0,0],0,3,-1,0" +
	",0,0,[],false,[[1,[6,0,1,1,0,[],2,0,0,0],0,2,-1,0,0,0,[],false,[]]]]]],[0,\"\",[]],[],[]" +
	",[],[],[]],[11,-1,0,[0,[0,0,1,1,0,[],-1,0,0,0],0,-1,-1,0,0,0,[],false,[]],[0,[0,0,1,1,0," +
	"[],-1,0,0,0],0,-1,-1,0,0,0,[],false,[]],[0,\"\",[]],[],[],[],[],[]]],[0,\"\",[]]],[\"UvS" +
	"tage\",[[\"phase\",[6,0,1,1,0,[],1,0,0,0]]],[],[6,0,1,1,0,[],1,0,0,0],[[11,-1,0,[0,[0,0," +
	"1,1,0,[],-1,0,0,0],0,-1,-1,0,0,0,[],false,[]],[10,[6,0,1,1,0,[],1,0,0,0],0,4,-1,0,0,0,[]" +
	",false,[[2,[6,0,1,1,0,[],1,0,0,0],0,0,-1,0,0,0,[],false,[]]]],[0,\"\",[]],[],[],[],[],[]" +
	"]],[0,\"\",[]]],[\"Shaded\",[[\"phase\",[6,0,1,1,0,[],2,0,0,0]]],[],[6,0,1,1,0,[],2,0,0," +
	"0],[[11,-1,0,[0,[0,0,1,1,0,[],-1,0,0,0],0,-1,-1,0,0,0,[],false,[]],[10,[6,0,1,1,0,[],2,0" +
	",0,0],0,6,-1,0,0,0,[],false,[[10,[6,0,1,1,0,[],2,0,0,0],0,5,-1,0,0,0,[],false,[[2,[6,0,1" +
	",1,0,[],2,0,0,0],0,0,-1,0,0,0,[],false,[]]]]]],[0,\"\",[]],[],[],[],[],[]]],[0,\"\",[]]]" +
	",[\"uvScroll\",[[\"stage\",[6,0,1,1,0,[],1,0,0,0]]],[],[6,0,1,1,0,[],1,0,0,0],[[11,-1,0," +
	"[0,[0,0,1,1,0,[],-1,0,0,0],0,-1,-1,0,0,0,[],false,[]],[12,[6,0,1,1,0,[],1,0,0,0],0,-1,-1" +
	",0,0,0,[],false,[[8,[2,0,2,1,0,[],-1,0,0,0],0,-1,-1,0,0,0,[],false,[[14,[2,0,2,1,0,[],-1" +
	",0,0,0],0,0,-1,0,0,0,[],false,[[2,[6,0,1,1,0,[],1,0,0,0],0,0,-1,0,0,0,[],false,[]]]],[12" +
	",[2,0,2,1,0,[],-1,0,0,0],0,-1,-1,0,0,0,[],false,[[6,[1,0,1,1,0,[],-1,0,0,0],0,0,0,0,0,0," +
	"[],false,[]],[0,[1,0,1,1,0,[],-1,0,0,0],0,-1,-1,0,0,0,[],false,[]]]]]]]],[0,\"\",[]],[]," +
	"[],[],[],[]]],[0,\"\",[]]],[\"colourAdd\",[[\"shaded\",[6,0,1,1,0,[],2,0,0,0]]],[],[6,0," +
	"1,1,0,[],2,0,0,0],[[11,-1,0,[0,[0,0,1,1,0,[],-1,0,0,0],0,-1,-1,0,0,0,[],false,[]],[12,[6" +
	",0,1,1,0,[],2,0,0,0],0,-1,-1,0,0,0,[],false,[[8,[2,0,4,1,0,[],-1,0,0,0],0,-1,-1,0,0,0,[]" +
	",false,[[14,[2,0,4,1,0,[],-1,0,0,0],0,0,-1,0,0,0,[],false,[[2,[6,0,1,1,0,[],2,0,0,0],0,0" +
	",-1,0,0,0,[],false,[]]]],[6,[2,0,4,1,0,[],-1,0,0,0],0,1,0,0,0,0,[],false,[]]]]]],[0,\"\"" +
	",[]],[],[],[],[],[]]],[0,\"\",[]]],[\"killAlpha\",[[\"shaded\",[6,0,1,1,0,[],2,0,0,0]]]," +
	"[],[6,0,1,1,0,[],2,0,0,0],[[4,-1,0,[0,[0,0,1,1,0,[],-1,0,0,0],0,-1,-1,0,0,0,[],false,[]]" +
	",[8,[1,3,1,1,0,[],-1,0,0,0],0,-1,-1,0,14,0,[],false,[[15,[1,0,1,1,0,[],-1,0,0,0],0,-1,-1" +
	",0,0,0,[3],false,[[14,[2,0,4,1,0,[],-1,0,0,0],0,0,-1,0,0,0,[],false,[[2,[6,0,1,1,0,[],2," +
	"0,0,0],0,0,-1,0,0,0,[],false,[]]]]]],[0,[1,0,1,1,0,[],-1,0,0,0],0.5,-1,-1,0,0,0,[],false" +
	",[]]]],[0,\"\",[]],[],[],[[12,-1,0,[0,[0,0,1,1,0,[],-1,0,0,0],0,-1,-1,0,0,0,[],false,[]]" +
	",[0,[0,0,1,1,0,[],-1,0,0,0],0,-1,-1,0,0,0,[],false,[]],[0,\"\",[]],[],[],[],[],[]]],[],[" +
	"]],[11,-1,0,[0,[0,0,1,1,0,[],-1,0,0,0],0,-1,-1,0,0,0,[],false,[]],[2,[6,0,1,1,0,[],2,0,0" +
	",0],0,0,-1,0,0,0,[],false,[]],[0,\"\",[]],[],[],[],[],[]]],[0,\"\",[]]]],[[\"baseVs\",0," +
	"0,[1,1,1]],[\"baseFs\",1,1,[1,1,1]]],[[2,0],[2,1],[0,1],[2,2],[0,2],[2,3],[2,4],[2,5],[2" +
	",6]],[]]";

const BASE =
	"[[],[[\"Frame\",[[\"time\",[1,0,1,1,0,[],-1,0,0,0]]]],[\"UvStage\",[[\"uv\",[2,0,2,1,0,[" +
	"],-1,0,0,0]]]],[\"Shaded\",[[\"color\",[2,0,4,1,0,[],-1,0,0,0]]]]],[],[[0,\"frame\",0,0," +
	"[6,0,1,1,0,[],0,0,0,0],0,0,0,[0,\"\",[]]]],[[\"position\",0,0,[2,0,2,1,0,[],-1,0,0,0],-1" +
	",0,0,0,[0,\"\",[]]],[\"clip\",0,1,[2,0,4,1,0,[],-1,0,0,0],-1,3,0,0,[0,\"\",[]]],[\"uv\"," +
	"0,1,[2,0,2,1,0,[],-1,0,0,0],-1,0,0,0,[0,\"\",[]]],[\"position\",1,0,[2,0,4,1,0,[],-1,0,0" +
	",0],-1,3,0,0,[0,\"\",[]]],[\"uv\",1,0,[2,0,2,1,0,[],-1,0,0,0],-1,0,0,0,[0,\"\",[]]],[\"f" +
	"ragColor\",1,1,[2,0,4,1,0,[],-1,0,0,0],0,0,0,0,[0,\"\",[]]]],[[\"baseVs\",[],[],[0,0,1,1" +
	",0,[],-1,0,0,0],[[2,-1,0,[4,[2,0,4,1,0,[],-1,0,0,0],0,1,-1,0,0,0,[],false,[]],[12,[2,0,4" +
	",1,0,[],-1,0,0,0],0,-1,-1,0,0,0,[],false,[[15,[1,0,1,1,0,[],-1,0,0,0],0,-1,-1,0,0,0,[0]," +
	"false,[[4,[2,0,2,1,0,[],-1,0,0,0],0,0,-1,0,0,0,[],false,[]]]],[15,[1,0,1,1,0,[],-1,0,0,0" +
	"],0,-1,-1,0,0,0,[1],false,[[4,[2,0,2,1,0,[],-1,0,0,0],0,0,-1,0,0,0,[],false,[]]]],[0,[1," +
	"0,1,1,0,[],-1,0,0,0],0,-1,-1,0,0,0,[],false,[]],[0,[1,0,1,1,0,[],-1,0,0,0],1,-1,-1,0,0,0" +
	",[],false,[]]]],[0,\"\",[]],[],[],[],[],[]],[2,-1,0,[4,[2,0,2,1,0,[],-1,0,0,0],0,2,-1,0," +
	"0,0,[],false,[]],[4,[2,0,2,1,0,[],-1,0,0,0],0,0,-1,0,0,0,[],false,[]],[0,\"\",[]],[],[]," +
	"[],[],[]],[11,-1,0,[0,[0,0,1,1,0,[],-1,0,0,0],0,-1,-1,0,0,0,[],false,[]],[0,[0,0,1,1,0,[" +
	"],-1,0,0,0],0,-1,-1,0,0,0,[],false,[]],[0,\"\",[]],[],[],[],[],[]]],[0,\"\",[]]],[\"base" +
	"Fs\",[],[[\"start\",[6,0,1,1,0,[],1,0,0,0]],[\"stage\",[6,0,1,1,0,[],1,0,0,0]],[\"lit\"," +
	"[6,0,1,1,0,[],2,0,0,0]]],[0,0,1,1,0,[],-1,0,0,0],[[1,0,0,[0,[0,0,1,1,0,[],-1,0,0,0],0,-1" +
	",-1,0,0,0,[],false,[]],[12,[6,0,1,1,0,[],1,0,0,0],0,-1,-1,0,0,0,[],false,[[4,[2,0,2,1,0," +
	"[],-1,0,0,0],0,4,-1,0,0,0,[],false,[]]]],[0,\"\",[]],[],[],[],[],[]],[1,1,0,[0,[0,0,1,1," +
	"0,[],-1,0,0,0],0,-1,-1,0,0,0,[],false,[]],[10,[6,0,1,1,0,[],1,0,0,0],0,2,-1,0,0,0,[],fal" +
	"se,[[1,[6,0,1,1,0,[],1,0,0,0],0,0,-1,0,0,0,[],false,[]]]],[0,\"\",[]],[],[],[],[],[]],[1" +
	",2,0,[0,[0,0,1,1,0,[],-1,0,0,0],0,-1,-1,0,0,0,[],false,[]],[12,[6,0,1,1,0,[],2,0,0,0],0," +
	"-1,-1,0,0,0,[],false,[[12,[2,0,4,1,0,[],-1,0,0,0],0,-1,-1,0,0,0,[],false,[[15,[1,0,1,1,0" +
	",[],-1,0,0,0],0,-1,-1,0,0,0,[0],false,[[14,[2,0,2,1,0,[],-1,0,0,0],0,0,-1,0,0,0,[],false" +
	",[[1,[6,0,1,1,0,[],1,0,0,0],0,1,-1,0,0,0,[],false,[]]]]]],[15,[1,0,1,1,0,[],-1,0,0,0],0," +
	"-1,-1,0,0,0,[1],false,[[14,[2,0,2,1,0,[],-1,0,0,0],0,0,-1,0,0,0,[],false,[[1,[6,0,1,1,0," +
	"[],1,0,0,0],0,1,-1,0,0,0,[],false,[]]]]]],[6,[1,0,1,1,0,[],-1,0,0,0],0,0,0,0,0,0,[],fals" +
	"e,[]],[0,[1,0,1,1,0,[],-1,0,0,0],1,-1,-1,0,0,0,[],false,[]]]]]],[0,\"\",[]],[],[],[],[]," +
	"[]],[2,-1,0,[4,[2,0,4,1,0,[],-1,0,0,0],0,5,-1,0,0,0,[],false,[]],[14,[2,0,4,1,0,[],-1,0," +
	"0,0],0,0,-1,0,0,0,[],false,[[10,[6,0,1,1,0,[],2,0,0,0],0,3,-1,0,0,0,[],false,[[1,[6,0,1," +
	"1,0,[],2,0,0,0],0,2,-1,0,0,0,[],false,[]]]]]],[0,\"\",[]],[],[],[],[],[]],[11,-1,0,[0,[0" +
	",0,1,1,0,[],-1,0,0,0],0,-1,-1,0,0,0,[],false,[]],[0,[0,0,1,1,0,[],-1,0,0,0],0,-1,-1,0,0," +
	"0,[],false,[]],[0,\"\",[]],[],[],[],[],[]]],[0,\"\",[]]],[\"UvStage\",[[\"phase\",[6,0,1" +
	",1,0,[],1,0,0,0]]],[],[6,0,1,1,0,[],1,0,0,0],[[11,-1,0,[0,[0,0,1,1,0,[],-1,0,0,0],0,-1,-" +
	"1,0,0,0,[],false,[]],[2,[6,0,1,1,0,[],1,0,0,0],0,0,-1,0,0,0,[],false,[]],[0,\"\",[]],[]," +
	"[],[],[],[]]],[0,\"\",[]]],[\"Shaded\",[[\"phase\",[6,0,1,1,0,[],2,0,0,0]]],[],[6,0,1,1," +
	"0,[],2,0,0,0],[[11,-1,0,[0,[0,0,1,1,0,[],-1,0,0,0],0,-1,-1,0,0,0,[],false,[]],[2,[6,0,1," +
	"1,0,[],2,0,0,0],0,0,-1,0,0,0,[],false,[]],[0,\"\",[]],[],[],[],[],[]]],[0,\"\",[]]]],[[\"" +
	"baseVs\",0,0,[1,1,1]],[\"baseFs\",1,1,[1,1,1]]],[[2,0],[2,1],[0,1],[2,2],[0,2],[2,3]],[]" +
	"]";

const CHAIN_WGSL =
	"struct Frame {\n" +
	"  time : f32,\n" +
	"}\n" +
	"\n" +
	"struct UvStage {\n" +
	"  uv : vec2f,\n" +
	"}\n" +
	"\n" +
	"struct Shaded {\n" +
	"  color : vec4f,\n" +
	"}\n" +
	"\n" +
	"struct Tint {\n" +
	"  tint : vec4f,\n" +
	"}\n" +
	"\n" +
	"@binding(0) @group(0) var<uniform> frame : Frame;\n" +
	"\n" +
	"@binding(1) @group(0) var<uniform> tintParams : Tint;\n" +
	"\n" +
	"var<private> position : vec4f;\n" +
	"\n" +
	"var<private> uv : vec2f;\n" +
	"\n" +
	"var<private> fragColor : vec4f;\n" +
	"\n" +
	"fn baseFs() {\n" +
	"  var start : UvStage = UvStage(uv);\n" +
	"  var stage : UvStage = UvStage_1(start);\n" +
	"  var lit : Shaded = Shaded(vec4f(stage.uv.x, stage.uv.y, frame.time, 1f));\n" +
	"  fragColor = Shaded_1(lit).color;\n" +
	"  return;\n" +
	"}\n" +
	"\n" +
	"fn UvStage_1(phase : UvStage) -> UvStage {\n" +
	"  return uvScroll(phase);\n" +
	"}\n" +
	"\n" +
	"fn Shaded_1(phase : Shaded) -> Shaded {\n" +
	"  return killAlpha(colourAdd(phase));\n" +
	"}\n" +
	"\n" +
	"fn uvScroll(stage : UvStage) -> UvStage {\n" +
	"  return UvStage((stage.uv + vec2f(frame.time, 0f)));\n" +
	"}\n" +
	"\n" +
	"fn colourAdd(shaded : Shaded) -> Shaded {\n" +
	"  return Shaded((shaded.color + tintParams.tint));\n" +
	"}\n" +
	"\n" +
	"fn killAlpha(shaded : Shaded) -> Shaded {\n" +
	"  if ((shaded.color.w < 0.5f)) {\n" +
	"    discard;\n" +
	"  }\n" +
	"  return shaded;\n" +
	"}\n" +
	"\n" +
	"struct main_out {\n" +
	"  @location(0) fragColor : vec4f,\n" +
	"}\n" +
	"\n" +
	"@fragment\n" +
	"fn main(@builtin(position) position_param : vec4f, " +
	"@location(0) uv_param : vec2f) -> main_out {\n" +
	"  position = position_param;\n" +
	"  uv = uv_param;\n" +
	"  baseFs();\n" +
	"  return main_out(fragColor);\n" +
	"}\n";

const CHAIN_HLSL =
	"struct UvStage\n" +
	"{\n" +
	"    float2 uv;\n" +
	"};\n" +
	"\n" +
	"struct Shaded\n" +
	"{\n" +
	"    float4 color;\n" +
	"};\n" +
	"\n" +
	"cbuffer frame : register(b0)\n" +
	"{\n" +
	"    float _0_time : packoffset(c0);\n" +
	"};\n" +
	"\n" +
	"cbuffer tintParams : register(b1)\n" +
	"{\n" +
	"    float4 _1_tint : packoffset(c0);\n" +
	"};\n" +
	"\n" +
	"static float4 position;\n" +
	"static float2 uv;\n" +
	"static float4 fragColor;\n" +
	"\n" +
	"UvStage makeUvStage(float2 v0)\n" +
	"{\n" +
	"    UvStage r = (UvStage)0;\n" +
	"    r.uv = v0;\n" +
	"    return r;\n" +
	"}\n" +
	"\n" +
	"Shaded makeShaded(float4 v0)\n" +
	"{\n" +
	"    Shaded r = (Shaded)0;\n" +
	"    r.color = v0;\n" +
	"    return r;\n" +
	"}\n" +
	"\n" +
	"UvStage uvScroll(UvStage stage)\n" +
	"{\n" +
	"    return makeUvStage(stage.uv + float2(_0_time, 0.0));\n" +
	"}\n" +
	"\n" +
	"UvStage UvStage_1(UvStage phase)\n" +
	"{\n" +
	"    return uvScroll(phase);\n" +
	"}\n" +
	"\n" +
	"Shaded killAlpha(Shaded shaded)\n" +
	"{\n" +
	"    if (shaded.color.w < 0.5)\n" +
	"    {\n" +
	"        discard;\n" +
	"    }\n" +
	"    return shaded;\n" +
	"}\n" +
	"\n" +
	"Shaded colourAdd(Shaded shaded)\n" +
	"{\n" +
	"    return makeShaded(shaded.color + _1_tint);\n" +
	"}\n" +
	"\n" +
	"Shaded Shaded_1(Shaded phase)\n" +
	"{\n" +
	"    return killAlpha(colourAdd(phase));\n" +
	"}\n" +
	"\n" +
	"void baseFs()\n" +
	"{\n" +
	"    UvStage start = makeUvStage(uv);\n" +
	"    UvStage stage = UvStage_1(start);\n" +
	"    Shaded lit_1 = makeShaded(float4(stage.uv.x, stage.uv.y, _0_time, 1.0));\n" +
	"    fragColor = Shaded_1(lit_1).color;\n" +
	"    return;\n" +
	"}\n" +
	"\n" +
	"struct StageInput\n" +
	"{\n" +
	"    float2 uv : TEXCOORD0;\n" +
	"    float4 position : SV_Position;\n" +
	"};\n" +
	"\n" +
	"struct StageOutput\n" +
	"{\n" +
	"    float4 fragColor : SV_Target0;\n" +
	"};\n" +
	"\n" +
	"StageOutput main(StageInput stage_input)\n" +
	"{\n" +
	"    uv = stage_input.uv;\n" +
	"    position = stage_input.position;\n" +
	"    position.w = 1.0 / position.w;\n" +
	"    baseFs();\n" +
	"    StageOutput stage_output;\n" +
	"    stage_output.fragColor = fragColor;\n" +
	"    return stage_output;\n" +
	"}\n";

const CHAIN_REFLECTED =
	"0/0 uniform -1,0/1 uniform -1\n" +
	"0/0 uniform 0,0/1 uniform 1\n" +
	"0/0 uniform -1 frame,0/1 uniform -1 tintParams\n" +
	"0/0 uniform -1 frame,0/1 uniform -1 tintParams\n" +
	"0/0 uniform 0,0/1 uniform 1";

const DETAIL_REFLECTED =
	"0/0 uniform -1,0/1 uniform -1,1/0 texture -1,1/1 texture -1,1/32 sampler -1," +
	"1/33 sampler -1\n" +
	"0/0 uniform 0,0/1 uniform 1,1/0 texture 0,1/1 texture 1,1/32 sampler 0,1/33 sampler 1\n" +
	"0/0 uniform -1 frame,0/1 uniform -1 tintParams,1/0 texture -1,1/1 texture -1," +
	"1/32 sampler -1 detailA_detailASampler,1/33 sampler -1 detailB_detailBSampler\n" +
	"0/0 uniform -1 frame,0/1 uniform -1 tintParams,1/0 texture -1,1/1 texture -1," +
	"1/32 sampler -1 detailA_detailASampler,1/33 sampler -1 detailB_detailBSampler\n" +
	"0/0 uniform 0,0/1 uniform 1,1/0 texture 0,1/1 texture 1,1/32 sampler 0,1/33 sampler 1";

const SPLIT_VS_WGSL =
	"var<private> position : vec2f;\n" +
	"\n" +
	"var<private> clip : vec4f;\n" +
	"\n" +
	"var<private> a : vec2f;\n" +
	"\n" +
	"fn splitVs() {\n" +
	"  clip = vec4f(position.x, position.y, 0f, 1f);\n" +
	"  a = position;\n" +
	"  return;\n" +
	"}\n" +
	"\n" +
	"struct main_out {\n" +
	"  @builtin(position) clip : vec4f,\n" +
	"  @location(0) a : vec2f,\n" +
	"}\n" +
	"\n" +
	"@vertex\n" +
	"fn main(@location(0) position_param : vec2f) -> main_out {\n" +
	"  position = position_param;\n" +
	"  splitVs();\n" +
	"  return main_out(clip, a);\n" +
	"}\n";
const SPLIT_FS_WGSL =
	"struct Surface {\n" +
	"  base : vec2f,\n" +
	"  detail : vec2f,\n" +
	"}\n" +
	"\n" +
	"var<private> position : vec4f;\n" +
	"\n" +
	"var<private> a : vec2f;\n" +
	"\n" +
	"var<private> fragColor : vec4f;\n" +
	"\n" +
	"fn splitFs() {\n" +
	"  var start : Surface = Surface(a, vec2f(0f));\n" +
	"  var surface : Surface = Surface_1(start);\n" +
	"  fragColor = vec4f(surface.base.x, surface.base.y, 0f, 1f);\n" +
	"  return;\n" +
	"}\n" +
	"\n" +
	"fn Surface_1(phase : Surface) -> Surface {\n" +
	"  return phase;\n" +
	"}\n" +
	"\n" +
	"struct main_out {\n" +
	"  @location(0) fragColor : vec4f,\n" +
	"}\n" +
	"\n" +
	"@fragment\n" +
	"fn main(@builtin(position) position_param : vec4f, " +
	"@location(0) a_param : vec2f) -> main_out {\n" +
	"  position = position_param;\n" +
	"  a = a_param;\n" +
	"  splitFs();\n" +
	"  return main_out(fragColor);\n" +
	"}\n";
const SPLIT_VS_HLSL =
	"static float2 position;\n" +
	"static float4 clip_1;\n" +
	"static float2 a;\n" +
	"\n" +
	"void splitVs()\n" +
	"{\n" +
	"    clip_1 = float4(position.x, position.y, 0.0, 1.0);\n" +
	"    a = position;\n" +
	"    return;\n" +
	"}\n" +
	"\n" +
	"struct StageInput\n" +
	"{\n" +
	"    float2 position : TEXCOORD0;\n" +
	"};\n" +
	"\n" +
	"struct StageOutput\n" +
	"{\n" +
	"    float2 a : TEXCOORD0;\n" +
	"    float4 clip_1 : SV_Position;\n" +
	"};\n" +
	"\n" +
	"StageOutput main(StageInput stage_input)\n" +
	"{\n" +
	"    position = stage_input.position;\n" +
	"    splitVs();\n" +
	"    StageOutput stage_output;\n" +
	"    stage_output.a = a;\n" +
	"    stage_output.clip_1 = clip_1;\n" +
	"    return stage_output;\n" +
	"}\n";
const SPLIT_FS_HLSL =
	"struct Surface\n" +
	"{\n" +
	"    float2 base;\n" +
	"    float2 detail;\n" +
	"};\n" +
	"\n" +
	"static float4 position;\n" +
	"static float2 a;\n" +
	"static float4 fragColor;\n" +
	"\n" +
	"Surface makeSurface(float2 v0, float2 v1)\n" +
	"{\n" +
	"    Surface r = (Surface)0;\n" +
	"    r.base = v0;\n" +
	"    r.detail = v1;\n" +
	"    return r;\n" +
	"}\n" +
	"\n" +
	"Surface Surface_1(Surface phase)\n" +
	"{\n" +
	"    return phase;\n" +
	"}\n" +
	"\n" +
	"void splitFs()\n" +
	"{\n" +
	"    Surface start = makeSurface(a, ((float2)0.0));\n" +
	"    Surface surface = Surface_1(start);\n" +
	"    fragColor = float4(surface.base.x, surface.base.y, 0.0, 1.0);\n" +
	"    return;\n" +
	"}\n" +
	"\n" +
	"struct StageInput\n" +
	"{\n" +
	"    float2 a : TEXCOORD0;\n" +
	"    float4 position : SV_Position;\n" +
	"};\n" +
	"\n" +
	"struct StageOutput\n" +
	"{\n" +
	"    float4 fragColor : SV_Target0;\n" +
	"};\n" +
	"\n" +
	"StageOutput main(StageInput stage_input)\n" +
	"{\n" +
	"    a = stage_input.a;\n" +
	"    position = stage_input.position;\n" +
	"    position.w = 1.0 / position.w;\n" +
	"    splitFs();\n" +
	"    StageOutput stage_output;\n" +
	"    stage_output.fragColor = fragColor;\n" +
	"    return stage_output;\n" +
	"}\n";

function moduleOf(text: string): ShaderModule {
	const m = irFromText(text);
	if (!m.ok) { throw "internal: segment text does not parse: " + m.error; }
	return m.value;
}

function programBase(vertex: string, fragment: string): ShaderModule {
	const m = programModule(vertex, fragment, []);
	if (!m.ok) { throw "internal: base program does not build: " + m.error; }
	return m.value;
}

function linkedOn(base: ShaderModule, effects: ShaderModule[]): ShaderModule {
	const m = link(base, effects);
	if (!m.ok) { throw "internal: link refused where it should succeed: " + m.error; }
	return m.value;
}

function baseOf(): ShaderModule {
	return programBase(glslIr(baseVs), glslLinkedIr(baseFs, baseVs));
}

const UV_SCROLL = glslSegmentIr(uvScroll);
const COLOUR_ADD = glslSegmentIr(colourAdd);
const KILL_ALPHA = glslSegmentIr(killAlpha);

function linked(effects: string[]): string {
	return irText(linkedModule(effects));
}

function refusal(base: ShaderModule, effects: ShaderModule[]): string {
	const m = link(base, effects);
	if (m.ok) { throw "internal: link succeeded where a refusal was expected"; }
	return m.error;
}

function printed(m: ShaderModule, target: ShaderTarget, path: string, entry: int32): string {
	const text = stageSource(m, entry, target);
	if (!text.ok) { throw "internal: stage " + path + " does not print: " + text.error; }
	const _out = mkdir("out");
	const _folder = mkdir("out/linkCheck");
	const _written = writeFile("out/linkCheck/" + path, text.value);
	return text.value;
}

function chainOf(m: ShaderModule, e: ShaderExpr): string {
	if (e.kind == ExprKind.Param) { return "phase"; }
	return m.functions[e.index].name + "(" + chainOf(m, e.operands[0]) + ")";
}

function siteChain(m: ShaderModule, phase: string): string {
	const site = m.functions.find((f) => f.name == phase);
	if (site == null || site.body.length != 1 || site.body[0].kind != StmtKind.Return) {
		return "no hook site for " + phase;
	}
	return chainOf(m, site.body[0].expr);
}

function linkedModule(effects: string[]): ShaderModule {
	return linkedOn(baseOf(), effects.map((t) => moduleOf(t)));
}

function sameColour(a: Vec4f, b: Vec4f): boolean {
	return a.x == b.x && a.y == b.y && a.z == b.z && a.w == b.w;
}

const PIXEL: Pixel = { position: vec4f(0.0), uv: vec2f(0.25, 0.5) };
const FRAME: BaseBindings = { frame: { time: 0.5 } };
const TINT: TintBindings = { tintParams: { tint: vec4f(0.25, 0.0, 0.25, 0.0) } };

test "a base hooks each phase struct once and runs on the CPU as the plain base" {
	assert irText(baseOf()) == BASE;
	const base = baseOf();
	assert siteChain(base, "UvStage") == "phase" && siteChain(base, "Shaded") == "phase";
	assert sameColour(baseFs(PIXEL, FRAME), plainFs(PIXEL, FRAME));
}

test "a base with no effects links to itself" {
	assert linked([]) == BASE;
}

test "the effects of a phase chain at its hook site in the author's order" {
	assert linked([UV_SCROLL, COLOUR_ADD, KILL_ALPHA]) == LINKED;
	const m = linkedModule([UV_SCROLL, COLOUR_ADD, KILL_ALPHA]);
	assert siteChain(m, "UvStage") == "uvScroll(phase)";
	assert siteChain(m, "Shaded") == "killAlpha(colourAdd(phase))";
	assert m.resources.map((r) => r.name + "@" + String(r.binding)).join(",") ==
		"frame@0,tintParams@1";
}

test "the linked chain folds on the CPU to the chained base" {
	const stage = uvScroll({ uv: PIXEL.uv }, { frame: FRAME.frame });
	const lit: Shaded = { color: vec4f(stage.uv.x, stage.uv.y, FRAME.frame.time, 1.0) };
	const folded = killAlpha(colourAdd(lit, TINT)).color;
	assert sameColour(folded, vec4f(1.0, 0.5, 0.75, 1.0));
	assert sameColour(chainedFs(PIXEL, FRAME, TINT), folded);
}

test "the linked fragment prints for WGSL and HLSL with its effect bindings numbered" {
	const m = linkedModule([UV_SCROLL, COLOUR_ADD, KILL_ALPHA]);
	assert irErrors(m).length == 0;
	assert printed(m, ShaderTarget.Wgsl, "chainFs.wgsl", 1) == CHAIN_WGSL;
	assert printed(m, ShaderTarget.Hlsl5, "chainFs.ps.hlsl", 1) == CHAIN_HLSL;
}

const TARGETS = [
	ShaderTarget.Wgsl,
	ShaderTarget.Hlsl5,
	ShaderTarget.Glsl430,
	ShaderTarget.Glsl300es,
	ShaderTarget.Msl,
];

function reflected(m: ShaderModule): string {
	let out: string[] = [];
	for (const target of TARGETS) {
		const s = programSource(m, target);
		if (!s.ok) { throw "internal: program does not print: " + s.error; }
		if (s.value.refusal != "") { throw "internal: program is refused: " + s.value.refusal; }
		out.push(s.value.reflection.bindings.map((b) => String(b.group) + "/" +
			String(b.binding) + " " + b.kind + " " + String(b.nativeSlot) +
			(b.nativeName == null ? "" : " " + b.nativeName)).join(","));
	}
	return out.join("\n");
}

test "the linked program prints and reflects for every target" {
	assert reflected(linkedModule([UV_SCROLL, COLOUR_ADD, KILL_ALPHA])) == CHAIN_REFLECTED;
}

test "two effects on one phase chain in the order given" {
	assert siteChain(linkedModule([COLOUR_ADD, KILL_ALPHA]), "Shaded") ==
		"killAlpha(colourAdd(phase))";
	assert siteChain(linkedModule([KILL_ALPHA, COLOUR_ADD]), "Shaded") ==
		"colourAdd(killAlpha(phase))";
}

test "an effect on a phase the base never hooks is refused" {
	assert refusal(baseOf(), [moduleOf(glslSegmentIr(depthBias))]) ==
		"link: effect 'depthBias' works on phase 'Depth', which the base has no hook site for";
}

test "a struct named as the base's with other members is refused" {
	let effect = moduleOf(COLOUR_ADD);
	effect.structs[0].name = "Frame";
	assert refusal(baseOf(), [effect]) ==
		"link: effect 'colourAdd' declares struct 'Frame' with other members than the linked " +
		"module's 'Frame'";
}

test "a resource named as the base's with another type is refused" {
	let effect = moduleOf(COLOUR_ADD);
	effect.resources[0].name = "frame";
	assert refusal(baseOf(), [effect]) ==
		"link: effect 'colourAdd' declares resource 'frame' with another kind or type than " +
		"the linked module's 'frame'";
}

const ADD_DETAIL = glslSegmentIr(addDetail);

function splitLinked(effects: string[]): ShaderModule {
	const base = programBase(glslIr(splitVs), glslLinkedIr(splitFs, splitVs));
	return linkedOn(base, effects.map((t) => moduleOf(t)));
}

function iosOf(m: ShaderModule): string {
	return m.ios.map((io) => (io.stage == ShaderStage.Vertex ? "vs " : "fs ") +
		(io.direction == IoDirection.In ? "in " : "out ") + io.name).join(",");
}

test "a varying the linked fragment never reads is dropped from both stages" {
	assert iosOf(splitLinked([ADD_DETAIL])) ==
		"vs in position,vs out clip,vs out a,vs out b," +
		"fs in position,fs in a,fs in b,fs out fragColor";
	assert iosOf(splitLinked([])) ==
		"vs in position,vs out clip,vs out a,fs in position,fs in a,fs out fragColor";
}

test "the linked stages print without the dropped varying" {
	const full = splitLinked([ADD_DETAIL]);
	const detail = [
		printed(full, ShaderTarget.Wgsl, "splitDetailVs.wgsl", 0),
		printed(full, ShaderTarget.Wgsl, "splitDetailFs.wgsl", 1),
		printed(full, ShaderTarget.Hlsl5, "splitDetailVs.vs.hlsl", 0),
		printed(full, ShaderTarget.Hlsl5, "splitDetailFs.ps.hlsl", 1),
	];
	const m = splitLinked([]);
	const vsWgsl = printed(m, ShaderTarget.Wgsl, "splitVs.wgsl", 0);
	const fsWgsl = printed(m, ShaderTarget.Wgsl, "splitFs.wgsl", 1);
	const vsHlsl = printed(m, ShaderTarget.Hlsl5, "splitVs.vs.hlsl", 0);
	const fsHlsl = printed(m, ShaderTarget.Hlsl5, "splitFs.ps.hlsl", 1);
	assert detail.every((t) => t.includes(" main("));
	assert vsWgsl == SPLIT_VS_WGSL && fsWgsl == SPLIT_FS_WGSL;
	assert vsHlsl == SPLIT_VS_HLSL && fsHlsl == SPLIT_FS_HLSL;
}

struct DetailABindings {
	detailA: Texture2d;
	detailASampler: Sampler;
}

struct DetailBBindings {
	detailB: Texture2d;
	detailBSampler: Sampler;
}

function detailA(shaded: Shaded, b: DetailABindings): Shaded {
	return { color: shaded.color * textureSample(b.detailA, b.detailASampler, vec2f(0.25, 0.5)) };
}

function detailB(shaded: Shaded, b: DetailBBindings): Shaded {
	return { color: shaded.color * textureSample(b.detailB, b.detailBSampler, vec2f(0.5, 0.25)) };
}

const DETAIL_A = glslSegmentIr(detailA);
const DETAIL_B = glslSegmentIr(detailB);

test "two texture effects get distinct views and samplers" {
	const m = linkedModule([COLOUR_ADD, DETAIL_A, DETAIL_B]);
	assert m.resources.map((r) => r.name + "@" + String(r.group) + "/" + String(r.binding))
		.join(",") ==
		"frame@0/0,tintParams@0/1,detailA@1/0,detailASampler@2/0,detailB@1/1,detailBSampler@2/1";
	assert irErrors(m).length == 0;
	assert reflected(m) == DETAIL_REFLECTED;
	assert printed(m, ShaderTarget.Wgsl, "detailFs.wgsl", 1).includes(" main(");
	assert printed(m, ShaderTarget.Hlsl5, "detailFs.ps.hlsl", 1).includes(" main(");
}

test "an effect past the last view binding is refused" {
	let effects: ShaderModule[] = [];
	for (let i = 0; i < 33; i++) {
		let e = moduleOf(DETAIL_A);
		e.resources[0].name = "detail" + String(i);
		effects.push(e);
	}
	assert refusal(baseOf(), effects) ==
		"link: effect 'detailA' finds no binding for Texture 'detail32': bindings 0..31 are taken";
}

struct VPhase {
	offset: Vec2f;
}

function hookedVs(input: Corner): Placed {
	const start: VPhase = { offset: input.position };
	const moved = hook(start);
	return { clip: vec4f(moved.offset.x, moved.offset.y, 0.0, 1.0), uv: input.position };
}

function nudge(phase: VPhase): VPhase {
	return { offset: phase.offset + vec2f(0.5, 0.0) };
}

const NUDGE = glslSegmentIr(nudge);

function hookedBase(): ShaderModule {
	return programBase(glslIr(hookedVs), glslLinkedIr(baseFs, hookedVs));
}

function hookedLinked(effects: string[]): ShaderModule {
	return linkedOn(hookedBase(), effects.map((t) => moduleOf(t)));
}

test "a vertex effect chains at the vertex entry's hook site" {
	const m = hookedLinked([NUDGE]);
	assert siteChain(m, "VPhase") == "nudge(phase)";
	assert irErrors(m).length == 0;
	const vs = printed(m, ShaderTarget.Wgsl, "hookedVs.wgsl", 0);
	assert vs.includes("fn nudge(") && vs.includes("return nudge(phase);");
	assert !printed(m, ShaderTarget.Wgsl, "hookedFs.wgsl", 1).includes("nudge");
}

test "a vertex effect and a fragment effect each land in their own stage" {
	const m = hookedLinked([NUDGE, COLOUR_ADD]);
	assert siteChain(m, "VPhase") == "nudge(phase)" && siteChain(m, "Shaded") == "colourAdd(phase)";
	assert irErrors(m).length == 0;
	const vs = printed(m, ShaderTarget.Wgsl, "hookedTintVs.wgsl", 0);
	const fs = printed(m, ShaderTarget.Wgsl, "hookedTintFs.wgsl", 1);
	assert vs.includes("return nudge(phase);") && !vs.includes("colourAdd");
	assert fs.includes("return colourAdd(phase);") && !fs.includes("nudge");
}

struct Carried {
	lift: Vec2f;
	fade: float32;
}

function carryLift(phase: VPhase): Carried {
	return { lift: phase.offset * 2.0, fade: phase.offset.x };
}

function liftColour(shaded: Shaded, b: TintBindings, carried: Carried): Shaded {
	return {
		color: shaded.color + b.tintParams.tint +
			vec4f(carried.lift.x, carried.lift.y, carried.fade, 0.0),
	};
}

function liftOnly(shaded: Shaded, b: TintBindings, carried: Carried): Shaded {
	return {
		color: shaded.color + b.tintParams.tint + vec4f(carried.lift.x, carried.lift.y, 0.0, 0.0),
	};
}

const CARRY_LIFT = glslSegmentIr(carryLift);
const LIFT_COLOUR = glslSegmentIr(liftColour);
const LIFT_ONLY = glslSegmentIr(liftOnly);
const HOOKED_IOS = "vs in position,vs out clip,vs out uv,fs in position,fs in uv,fs out fragColor";

test "a carrier a vertex segment writes reaches the fragment segment as varyings" {
	const m = hookedLinked([CARRY_LIFT, LIFT_COLOUR]);
	assert iosOf(hookedLinked([])) == HOOKED_IOS;
	assert iosOf(m) == HOOKED_IOS + ",vs out lift,fs in lift,vs out fade,fs in fade";
	assert irErrors(m).length == 0;
	const vs = printed(m, ShaderTarget.Wgsl, "carriedVs.wgsl", 0);
	const fs = printed(m, ShaderTarget.Wgsl, "carriedFs.wgsl", 1);
	assert vs.includes("var carried : Carried = carryLift(phase);") &&
		vs.includes("lift = carried.lift;") && vs.includes("fade = carried.fade;");
	assert fs.includes("return liftColour(phase, Carried(lift, fade));");
	assert reflected(m).split("\n").length == TARGETS.length;
}

test "a carried field no fragment segment reads gets no varying" {
	const m = hookedLinked([CARRY_LIFT, LIFT_ONLY]);
	assert iosOf(m) == HOOKED_IOS + ",vs out lift,fs in lift";
	assert printed(m, ShaderTarget.Wgsl, "liftOnlyFs.wgsl", 1)
		.includes("return liftOnly(phase, Carried(lift, 0f));");
	assert iosOf(hookedLinked([CARRY_LIFT])) == HOOKED_IOS;
}

test "a fragment segment reading a carrier no vertex segment writes is refused" {
	assert refusal(hookedBase(), [moduleOf(LIFT_COLOUR)]) ==
		"link: effect 'liftColour' reads varying 'lift' of carrier 'Carried', which no vertex " +
		"segment writes";
}

struct DetailStage {
	base: Vec2f;
	detail: Vec2f;
}

struct ExtraStage {
	base: Vec2f;
	extra: Vec2f;
}

struct LayerPlaced {
	@builtin(position) clip: Vec4f;
	a: Vec2f;
	b: Vec2f;
	c: Vec2f;
}

struct LayerPixel {
	@builtin(position) position: Vec4f;
	a: Vec2f;
	b: Vec2f;
	c: Vec2f;
}

function layerVs(input: Corner): LayerPlaced {
	return {
		clip: vec4f(input.position.x, input.position.y, 0.0, 1.0),
		a: input.position,
		b: vec2f(input.position.y, input.position.x),
		c: input.position * 2.0,
	};
}

function layerFs(input: LayerPixel): Vec4f {
	const first: DetailStage = { base: input.a, detail: input.b };
	const detailed = hook(first);
	const second: ExtraStage = { base: detailed.base, extra: input.c };
	const layered = hook(second);
	return vec4f(layered.base.x, layered.base.y, 0.0, 1.0);
}

function layerDetail(stage: DetailStage): DetailStage {
	return { base: stage.base + stage.detail, detail: stage.detail };
}

function layerExtra(stage: ExtraStage): ExtraStage {
	return { base: stage.base + stage.extra, extra: stage.extra };
}

const LAYER_DETAIL = glslSegmentIr(layerDetail);
const LAYER_EXTRA = glslSegmentIr(layerExtra);

function layerBase(): ShaderModule {
	return programBase(glslIr(layerVs), glslLinkedIr(layerFs, layerVs));
}

function layerLinked(effect: string): ShaderModule {
	return linkedOn(layerBase(), [moduleOf(effect)]);
}

test "two programs on one base each keep the varyings their own fragment reads" {
	const detail = layerLinked(LAYER_DETAIL);
	const extra = layerLinked(LAYER_EXTRA);
	assert iosOf(detail) ==
		"vs in position,vs out clip,vs out a,vs out b," +
		"fs in position,fs in a,fs in b,fs out fragColor";
	assert iosOf(extra) ==
		"vs in position,vs out clip,vs out a,vs out c," +
		"fs in position,fs in a,fs in c,fs out fragColor";
	const outputs =
		"struct main_out {\n  @builtin(position) clip : vec4f,\n" +
		"  @location(0) a : vec2f,\n";
	assert printed(detail, ShaderTarget.Wgsl, "layerDetailVs.wgsl", 0)
		.includes(outputs + "  @location(1) b : vec2f,\n}");
	assert printed(extra, ShaderTarget.Wgsl, "layerExtraVs.wgsl", 0)
		.includes(outputs + "  @location(1) c : vec2f,\n}");
}

test "a dropped varying whose stored value has an effect is refused" {
	let base = layerBase();
	const c = base.ios.findIndex((io) => io.stage == ShaderStage.Vertex && io.name == "c");
	const vs = base.functions.find((f) => f.name == "layerVs");
	assert c >= 0 && vs != null;
	if (vs == null) { return; }
	let stores = 0;
	for (const s of vs.body) {
		const root = rootOf(s.target);
		if (s.kind != StmtKind.Assign || root.kind != ExprKind.Io || root.index != c) { continue; }
		let add = exprOf(ExprKind.Intrinsic, s.expr.type, -1, [s.expr]);
		add.intrinsic = Intrinsic.AtomicAdd;
		s.expr = add;
		stores++;
	}
	assert stores == 1;
	assert refusal(base, [moduleOf(LAYER_DETAIL)]) ==
		"link: varying 'c' is read by no fragment, and the value its vertex stores has an effect";
}

struct FadePlaced {
	@builtin(position) clip: Vec4f;
	uv: Vec2f;
	@feature(F) world: Vec3f;
}

struct FadePixel {
	@builtin(position) position: Vec4f;
	uv: Vec2f;
	@feature(F) world: Vec3f;
}

struct FadeKey {
	@feature(F) f: boolean;
}

struct FadeShaded {
	color: Vec4f;
	world: Vec3f;
}

struct Fade {
	range: Vec4f;
}

struct FadeBindings {
	fadeParams: Fade;
}

function fadeVs(input: Corner, key: FadeKey): FadePlaced {
	return {
		clip: vec4f(input.position.x, input.position.y, 0.0, 1.0),
		uv: input.position,
		world: vec3f(input.position.x, input.position.y, 1.0),
	};
}

function fadeFs(input: FadePixel, b: BaseBindings, key: FadeKey): Vec4f {
	let world = vec3f(0.0);
	if (key.f) {
		world = input.world;
	}
	const lit: FadeShaded = {
		color: vec4f(input.uv.x, input.uv.y, b.frame.time, 1.0),
		world: world,
	};
	return hook(lit).color;
}

function distanceFade(shaded: FadeShaded, b: FadeBindings): FadeShaded {
	return {
		color: vec4f(shaded.color.x, shaded.color.y, shaded.color.z,
			shaded.color.w * length(shaded.world) * b.fadeParams.range.x),
		world: shaded.world,
	};
}

const FADE_VS = glslIr(fadeVs);
const FADE_FS = glslLinkedIr(fadeFs, fadeVs);
const DISTANCE_FADE = glslSegmentIr(distanceFade);

function keyedProgram(
	vertex: string,
	fragment: string,
	on: string[],
	segments: string[],
): ShaderModule {
	const m = linkedProgram(vertex, fragment, on, segments);
	if (!m.ok) { throw "internal: keyed program does not link: " + m.error; }
	return m.value;
}

function fadeProgram(on: string[]): ShaderModule {
	const segments = on.includes("F") ? [DISTANCE_FADE] : [];
	return keyedProgram(FADE_VS, FADE_FS, on, segments);
}

test "a key links only the effects listed for its features, after it is specialized" {
	const keyed = fadeProgram(["F"]);
	assert siteChain(keyed, "FadeShaded") == "distanceFade(phase)";
	assert iosOf(keyed) == "vs in position,vs out clip,vs out uv,vs out world," +
		"fs in position,fs in uv,fs in world,fs out fragColor";
	const plain = fadeProgram([]);
	assert irText(plain) == irText(programBase(FADE_VS, FADE_FS));
	assert !plain.functions.some((f) => f.name == "distanceFade");
	assert iosOf(plain) ==
		"vs in position,vs out clip,vs out uv,fs in position,fs in uv,fs out fragColor";
}

struct Gain {
	amount: Vec4f;
}

struct SlotBindings {
	@binding(0) frame: Frame;
	@binding(3) params: Gain;
}

struct GainBindings {
	params: Gain;
}

function slotFs(input: Pixel, b: SlotBindings, key: FadeKey): Vec4f {
	let color = vec4f(input.uv.x, input.uv.y, b.frame.time, 1.0);
	if (key.f) {
		color = color * b.params.amount;
	}
	const lit: Shaded = { color: color };
	return hook(lit).color;
}

function gain(shaded: Shaded, b: GainBindings): Shaded {
	return { color: shaded.color + b.params.amount };
}

const SLOT_VS = glslIr(baseVs);
const SLOT_FS = glslLinkedIr(slotFs, baseVs);
const GAIN = glslSegmentIr(gain);

function slotsOf(on: string[], segments: string[]): string {
	const m = keyedProgram(SLOT_VS, SLOT_FS, on, segments);
	return m.resources.map((r) => r.name + "@" + String(r.binding)).join(",");
}

test "an effect's block keeps the base's binding where the key leaves the base's read out" {
	assert slotsOf(["F"], [GAIN]) == "frame@0,params@3";
	assert slotsOf([], [GAIN]) == "frame@0,params@3";
	assert slotsOf([], []) == "frame@0";
	assert slotsOf([], [COLOUR_ADD]) == "frame@0,tintParams@1";
	assert slotsOf([], [GAIN, COLOUR_ADD]) == "frame@0,params@3,tintParams@4";
}

struct TintKey {
	@feature(F) f: boolean;
}

function keyedTint(shaded: Shaded, b: TintBindings, key: TintKey): Shaded {
	let color = shaded.color;
	if (key.f) {
		color = color + b.tintParams.tint;
	} else {
		color = color * b.tintParams.tint;
	}
	return { color: color };
}

const KEYED_TINT = glslSegmentIr(keyedTint);
const ADDED = "color = (color + tintParams.tint);";
const SCALED = "color = (color * tintParams.tint);";

function keyedFragment(fragment: string, on: string[]): string {
	const m = keyedProgram(SLOT_VS, fragment, on, [KEYED_TINT]);
	return printed(m, ShaderTarget.Wgsl, "keyedTintFs.wgsl", 1);
}

test "a keyed segment links the branch its row's features pick" {
	const on = keyedFragment(SLOT_FS, ["F"]);
	const off = keyedFragment(SLOT_FS, []);
	assert on.includes(ADDED) && !on.includes(SCALED);
	assert off.includes(SCALED) && !off.includes(ADDED);
}

test "a segment's feature folds by the row even when the base declares no such key" {
	const fragment = glslLinkedIr(baseFs, baseVs);
	assert keyedFragment(fragment, ["F"]).includes(ADDED);
	assert keyedFragment(fragment, []).includes(SCALED);
}

struct Wide {
	tint: Vec4f;
	extra: Vec4f;
}

struct AltKey {
	@feature(W) w: boolean;
}

struct AltBaseBindings {
	@binding(0) frame: Frame;
	@binding(1) tintParams: Tint;
	@binding(1) wide: Wide;
}

struct AltBindings {
	tintParams: Tint;
	wide: Wide;
}

struct WideBindings {
	wide: Wide;
}

function altFs(input: Pixel, b: AltBaseBindings, key: AltKey): Vec4f {
	let color = vec4f(input.uv.x, input.uv.y, b.frame.time, 1.0);
	if (key.w) {
		color = color * b.wide.extra;
	} else {
		color = color * b.tintParams.tint;
	}
	const lit: Shaded = { color: color };
	return hook(lit).color;
}

function altAdd(shaded: Shaded, b: AltBindings, key: AltKey): Shaded {
	if (key.w) {
		return { color: shaded.color + b.wide.tint };
	} else {
		return { color: shaded.color + b.tintParams.tint };
	}
}

function wideAdd(shaded: Shaded, b: WideBindings): Shaded {
	return { color: shaded.color + b.wide.tint };
}

function bothAdd(shaded: Shaded, b: AltBindings): Shaded {
	return { color: shaded.color + b.wide.tint + b.tintParams.tint };
}

const ALT_FS = glslLinkedIr(altFs, baseVs);
const ALT_ADD = glslSegmentIr(altAdd);
const WIDE_ADD = glslSegmentIr(wideAdd);
const BOTH_ADD = glslSegmentIr(bothAdd);

function altProgram(on: string[]): ShaderModule {
	return keyedProgram(SLOT_VS, ALT_FS, on, [ALT_ADD]);
}

test "a segment's alternative blocks merge onto the base's blocks at one binding" {
	const wide = altProgram(["W"]);
	const plain = altProgram([]);
	assert wide.resources.map((r) => r.name + "@" + String(r.binding)).join(",") ==
		"frame@0,wide@1";
	assert plain.resources.map((r) => r.name + "@" + String(r.binding)).join(",") ==
		"frame@0,tintParams@1";
	assert irErrors(wide).length == 0 && irErrors(plain).length == 0;
	const wideWgsl = printed(wide, ShaderTarget.Wgsl, "altWideFs.wgsl", 1);
	const plainWgsl = printed(plain, ShaderTarget.Wgsl, "altPlainFs.wgsl", 1);
	assert wideWgsl.includes("(shaded.color + wide.tint)") && !wideWgsl.includes("tintParams");
	assert plainWgsl.includes("(shaded.color + tintParams.tint)") && !plainWgsl.includes("wide");
	assert reflected(wide).split("\n").length == TARGETS.length;
	assert reflected(plain).split("\n").length == TARGETS.length;
}

test "two effect blocks at numbered bindings that share a member name are refused" {
	assert refusal(baseOf(), [moduleOf(COLOUR_ADD), moduleOf(WIDE_ADD)]) ==
		"link: effect 'wideAdd': 'tint' names two things in one stage";
	assert refusal(baseOf(), [moduleOf(BOTH_ADD)]) ==
		"link: effect 'bothAdd': 'tint' names two things in one stage";
}

struct TintedBindings {
	@binding(2) vertexTint: Tint;
}

function tintedVs(input: Corner, b: TintedBindings): Placed {
	return {
		clip: vec4f(input.position.x, input.position.y, 0.0, 1.0) + b.vertexTint.tint,
		uv: input.position,
	};
}

test "a vertex block and an effect's fragment block may share a member name" {
	const base = programBase(glslIr(tintedVs), glslLinkedIr(baseFs, tintedVs));
	const m = linkedOn(base, [moduleOf(COLOUR_ADD)]);
	assert m.resources.map((r) => r.name + "@" + String(r.binding)).join(",") ==
		"vertexTint@2,frame@0,tintParams@3";
	assert reflected(m).split("\n").length == TARGETS.length;
}

function brighten(c: Vec4f): Vec4f {
	return c * 2.0;
}

function dim(c: Vec4f): Vec4f {
	return c * 0.5;
}

function brightFs(input: Pixel, b: BaseBindings): Vec4f {
	const lit: Shaded = { color: brighten(vec4f(input.uv.x, input.uv.y, b.frame.time, 1.0)) };
	return hook(lit).color;
}

function brightAdd(shaded: Shaded): Shaded {
	return { color: brighten(shaded.color) };
}

function dimAdd(shaded: Shaded): Shaded {
	return { color: dim(shaded.color) };
}

const BRIGHT_ADD = glslSegmentIr(brightAdd);
const DIM_ADD = glslSegmentIr(dimAdd);

function helperLinked(effect: ShaderModule): ShaderModule {
	const base = programBase(glslIr(baseVs), glslLinkedIr(brightFs, baseVs));
	return linkedOn(base, [effect]);
}

test "an effect's helper identical to the base's links to the base's one copy" {
	const m = helperLinked(moduleOf(BRIGHT_ADD));
	assert m.functions.map((f) => f.name).join(",") == "baseVs,brighten,brightFs,Shaded,brightAdd";
	assert siteChain(m, "Shaded") == "brightAdd(phase)";
	assert irErrors(m).length == 0;
	assert printed(m, ShaderTarget.Wgsl, "brightFs.wgsl", 1)
		.includes("return Shaded(brighten(shaded.color));");
}

test "an effect's helper named as the base's with another body is renamed" {
	let effect = moduleOf(DIM_ADD);
	effect.functions[0].name = "brighten";
	const m = helperLinked(effect);
	assert m.functions.map((f) => f.name).join(",") ==
		"baseVs,brighten,brightFs,Shaded,brighten_1,dimAdd";
	assert irErrors(m).length == 0;
	assert printed(m, ShaderTarget.Wgsl, "dimFs.wgsl", 1)
		.includes("return Shaded(brighten_1(shaded.color));");
}
