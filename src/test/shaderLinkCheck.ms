import { mkdir, writeFile } from "std/fs";
import { programModule, stageSource } from "../shader/descriptor";
import { glslIr, glslLinkedIr, glslSegmentIr } from "../shader/emit";
import {
	ExprKind,
	ResourceKind,
	ShaderExpr,
	ShaderModule,
	ShaderResource,
	StmtKind,
} from "../shader/ir";
import { irFromText, irText } from "../shader/irText";
import { ShaderTarget } from "../shader/layout";
import { link } from "../shader/link";
import {
	Vec2f,
	Vec4f,
	binding,
	builtin,
	discard,
	hook,
	vec2f,
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

function chainedFs(input: Pixel, b: BaseBindings, tint: TintBindings): Vec4f {
	const stage = uvScroll({ uv: input.uv }, { frame: b.frame });
	const lit: Shaded = { color: vec4f(stage.uv.x, stage.uv.y, b.frame.time, 1.0) };
	return killAlpha(colourAdd(lit, tint)).color;
}

const LINKED =
	"[[],[[\"Frame\",[[\"time\",[1,0,1,1,0,[],-1,0,0,0]]]],[\"UvStage\",[[\"uv\",[2,0,2,1,0,[" +
	"],-1,0,0,0]]]],[\"Shaded\",[[\"color\",[2,0,4,1,0,[],-1,0,0,0]]]],[\"Tint\",[[\"tint\",[" +
	"2,0,4,1,0,[],-1,0,0,0]]]]],[],[[0,\"frame\",0,0,[6,0,1,1,0,[],0,0,0,0],0,0,0,[0,\"\",[]]" +
	"],[0,\"tintParams\",0,-1,[6,0,1,1,0,[],3,0,0,0],0,0,0,[0,\"\",[]]]],[[\"position\",0,0,[" +
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
	"fn main(@builtin(position) position_param : vec4f, @location(0) uv_param : vec2f) -> main_out {\n" +
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

function moduleOf(text: string): ShaderModule {
	const m = irFromText(text);
	return m.ok ? m.value : new ShaderModule();
}

function baseOf(): ShaderModule {
	const m = programModule(glslIr(baseVs), glslLinkedIr(baseFs, baseVs), []);
	return m.ok ? m.value : new ShaderModule();
}

const UV_SCROLL = glslSegmentIr(uvScroll);
const COLOUR_ADD = glslSegmentIr(colourAdd);
const KILL_ALPHA = glslSegmentIr(killAlpha);

function linked(effects: string[]): string {
	const m = link(baseOf(), effects.map((t) => moduleOf(t)));
	return m.ok ? irText(m.value) : m.error;
}

function refusal(base: ShaderModule, effects: ShaderModule[]): string {
	const m = link(base, effects);
	return m.ok ? "" : m.error;
}

function spaceOf(r: ShaderResource): int32 {
	if (r.kind == ResourceKind.UniformBlock) { return 0; }
	return r.kind == ResourceKind.Sampler ? 1 : 2;
}

function numberedForTest(m: ShaderModule): ShaderModule {
	for (const r of m.resources) {
		if (r.binding >= 0) { continue; }
		let free = 0;
		while (m.resources.some((o) => o.binding == free && spaceOf(o) == spaceOf(r))) { free++; }
		r.binding = free;
	}
	return m;
}

function printed(m: ShaderModule, target: ShaderTarget, path: string): string {
	const text = stageSource(m, 1, target);
	if (!text.ok) { return text.error; }
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
	const m = link(baseOf(), effects.map((t) => moduleOf(t)));
	return m.ok ? m.value : new ShaderModule();
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
		"frame@0,tintParams@-1";
}

test "the linked chain folds on the CPU to the chained base" {
	const stage = uvScroll({ uv: PIXEL.uv }, { frame: FRAME.frame });
	const lit: Shaded = { color: vec4f(stage.uv.x, stage.uv.y, FRAME.frame.time, 1.0) };
	const folded = killAlpha(colourAdd(lit, TINT)).color;
	assert sameColour(folded, vec4f(1.0, 0.5, 0.75, 1.0));
	assert sameColour(chainedFs(PIXEL, FRAME, TINT), folded);
}

test "the linked fragment prints for WGSL and HLSL once its effect bindings are numbered" {
	const m = numberedForTest(linkedModule([UV_SCROLL, COLOUR_ADD, KILL_ALPHA]));
	assert printed(m, ShaderTarget.Wgsl, "chainFs.wgsl") == CHAIN_WGSL;
	assert printed(m, ShaderTarget.Hlsl5, "chainFs.ps.hlsl") == CHAIN_HLSL;
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
