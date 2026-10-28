import { glslSegmentIr } from "../shader/emit";
import {
	ResourceKind,
	ShaderModule,
	ShaderTypeKind,
	StmtKind,
	sameShaderType,
} from "../shader/ir";
import { irFromText } from "../shader/irText";
import {
	Sampler,
	Texture2d,
	Vec2f,
	Vec4f,
	discard,
	feature,
	textureSample,
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

struct Surface {
	albedo: Vec4f;
	roughness: float32;
}

struct LitStage {
	uv: Vec2f;
	surface: Surface;
}

struct Light {
	color: Vec4f;
}

struct DetailBindings {
	detail: Texture2d;
	detailSampler: Sampler;
	lights: Light[];
}

function detailMap(stage: LitStage, b: DetailBindings): LitStage {
	const texel = textureSample(b.detail, b.detailSampler, stage.uv);
	const surface: Surface = {
		albedo: stage.surface.albedo * texel * b.lights[0].color,
		roughness: stage.surface.roughness,
	};
	return { uv: stage.uv, surface };
}

const UV_SCROLL =
	"[[],[[\"Frame\",[[\"time\",[1,0,1,1,0,[],-1,0,0,0]]]],[\"UvStage\",[[\"uv\",[2,0,2,1,0,[],-1,0" +
	",0,0]]]]],[],[[0,\"frame\",0,-1,[6,0,1,1,0,[],0,0,0,0],0,0,0,[0,\"\",[]]]],[],[[\"uvScroll\"" +
	",[[\"stage\",[6,0,1,1,0,[],1,0,0,0]]],[],[6,0,1,1,0,[],1,0,0,0],[[11,-1,0,[0,[0,0,1,1,0," +
	"[],-1,0,0,0],0,-1,-1,0,0,0,[],false,[]],[12,[6,0,1,1,0,[],1,0,0,0],0,-1,-1,0,0,0,[],fa" +
	"lse,[[8,[2,0,2,1,0,[],-1,0,0,0],0,-1,-1,0,0,0,[],false,[[14,[2,0,2,1,0,[],-1,0,0,0],0," +
	"0,-1,0,0,0,[],false,[[2,[6,0,1,1,0,[],1,0,0,0],0,0,-1,0,0,0,[],false,[]]]],[12,[2,0,2," +
	"1,0,[],-1,0,0,0],0,-1,-1,0,0,0,[],false,[[6,[1,0,1,1,0,[],-1,0,0,0],0,0,0,0,0,0,[],fal" +
	"se,[]],[0,[1,0,1,1,0,[],-1,0,0,0],0,-1,-1,0,0,0,[],false,[]]]]]]]],[0,\"\",[]],[],[],[]," +
	"[],[]]],[0,\"\",[]]]],[],[[0,1],[2,0]],[]]";

const COLOUR_ADD =
	"[[],[[\"Tint\",[[\"tint\",[2,0,4,1,0,[],-1,0,0,0]]]],[\"Shaded\",[[\"color\",[2,0,4,1,0,[],-1," +
	"0,0,0]]]]],[],[[0,\"tintParams\",0,-1,[6,0,1,1,0,[],0,0,0,0],0,0,0,[0,\"\",[]]]],[],[[\"col" +
	"ourAdd\",[[\"shaded\",[6,0,1,1,0,[],1,0,0,0]]],[],[6,0,1,1,0,[],1,0,0,0],[[11,-1,0,[0,[0," +
	"0,1,1,0,[],-1,0,0,0],0,-1,-1,0,0,0,[],false,[]],[12,[6,0,1,1,0,[],1,0,0,0],0,-1,-1,0,0" +
	",0,[],false,[[8,[2,0,4,1,0,[],-1,0,0,0],0,-1,-1,0,0,0,[],false,[[14,[2,0,4,1,0,[],-1,0" +
	",0,0],0,0,-1,0,0,0,[],false,[[2,[6,0,1,1,0,[],1,0,0,0],0,0,-1,0,0,0,[],false,[]]]],[6," +
	"[2,0,4,1,0,[],-1,0,0,0],0,0,0,0,0,0,[],false,[]]]]]],[0,\"\",[]],[],[],[],[],[]]],[0,\"\"," +
	"[]]]],[],[[0,1],[2,0]],[]]";

const KILL_ALPHA =
	"[[],[[\"Shaded\",[[\"color\",[2,0,4,1,0,[],-1,0,0,0]]]]],[],[],[],[[\"killAlpha\",[[\"shaded\"" +
	",[6,0,1,1,0,[],0,0,0,0]]],[],[6,0,1,1,0,[],0,0,0,0],[[4,-1,0,[0,[0,0,1,1,0,[],-1,0,0,0" +
	"],0,-1,-1,0,0,0,[],false,[]],[8,[1,3,1,1,0,[],-1,0,0,0],0,-1,-1,0,14,0,[],false,[[15,[" +
	"1,0,1,1,0,[],-1,0,0,0],0,-1,-1,0,0,0,[3],false,[[14,[2,0,4,1,0,[],-1,0,0,0],0,0,-1,0,0" +
	",0,[],false,[[2,[6,0,1,1,0,[],0,0,0,0],0,0,-1,0,0,0,[],false,[]]]]]],[0,[1,0,1,1,0,[]," +
	"-1,0,0,0],0.5,-1,-1,0,0,0,[],false,[]]]],[0,\"\",[]],[],[],[[12,-1,0,[0,[0,0,1,1,0,[],-1" +
	",0,0,0],0,-1,-1,0,0,0,[],false,[]],[0,[0,0,1,1,0,[],-1,0,0,0],0,-1,-1,0,0,0,[],false,[" +
	"]],[0,\"\",[]],[],[],[],[],[]]],[],[]],[11,-1,0,[0,[0,0,1,1,0,[],-1,0,0,0],0,-1,-1,0,0,0" +
	",[],false,[]],[2,[6,0,1,1,0,[],0,0,0,0],0,0,-1,0,0,0,[],false,[]],[0,\"\",[]],[],[],[],[" +
	"],[]]],[0,\"\",[]]]],[],[[0,0],[2,0]],[]]";

const DETAIL_MAP =
	"[[],[[\"Surface\",[[\"albedo\",[2,0,4,1,0,[],-1,0,0,0]],[\"roughness\",[1,0,1,1,0,[],-1,0,0," +
	"0]]]],[\"LitStage\",[[\"uv\",[2,0,2,1,0,[],-1,0,0,0]],[\"surface\",[6,0,1,1,0,[],0,0,0,0]]]]" +
	",[\"Light\",[[\"color\",[2,0,4,1,0,[],-1,0,0,0]]]]],[],[[1,\"detail\",1,-1,[7,0,1,1,0,[],-1," +
	"0,0,0],0,0,0,[0,\"\",[]]],[2,\"detailSampler\",2,-1,[8,0,1,1,0,[],-1,0,0,0],0,0,0,[0,\"\",[]" +
	"]],[3,\"lights\",1,-1,[5,0,1,1,-1,[[6,0,1,1,0,[],2,0,0,0]],-1,0,0,0],0,0,0,[0,\"\",[]]]],[" +
	"],[[\"detailMap\",[[\"stage\",[6,0,1,1,0,[],1,0,0,0]]],[[\"texel\",[2,0,4,1,0,[],-1,0,0,0]]," +
	"[\"surface\",[6,0,1,1,0,[],0,0,0,0]]],[6,0,1,1,0,[],1,0,0,0],[[1,0,0,[0,[0,0,1,1,0,[],-1" +
	",0,0,0],0,-1,-1,0,0,0,[],false,[]],[11,[2,0,4,1,0,[],-1,0,0,0],0,-1,-1,0,0,89,[],false" +
	",[[5,[7,0,1,1,0,[],-1,0,0,0],0,0,-1,0,0,0,[],false,[]],[5,[8,0,1,1,0,[],-1,0,0,0],0,1," +
	"-1,0,0,0,[],false,[]],[14,[2,0,2,1,0,[],-1,0,0,0],0,0,-1,0,0,0,[],false,[[2,[6,0,1,1,0" +
	",[],1,0,0,0],0,0,-1,0,0,0,[],false,[]]]]]],[0,\"\",[]],[],[],[],[],[]],[1,1,0,[0,[0,0,1," +
	"1,0,[],-1,0,0,0],0,-1,-1,0,0,0,[],false,[]],[12,[6,0,1,1,0,[],0,0,0,0],0,-1,-1,0,0,0,[" +
	"],false,[[8,[2,0,4,1,0,[],-1,0,0,0],0,-1,-1,0,2,0,[],false,[[8,[2,0,4,1,0,[],-1,0,0,0]" +
	",0,-1,-1,0,2,0,[],false,[[14,[2,0,4,1,0,[],-1,0,0,0],0,0,-1,0,0,0,[],false,[[14,[6,0,1" +
	",1,0,[],0,0,0,0],0,1,-1,0,0,0,[],false,[[2,[6,0,1,1,0,[],1,0,0,0],0,0,-1,0,0,0,[],fals" +
	"e,[]]]]]],[1,[2,0,4,1,0,[],-1,0,0,0],0,0,-1,0,0,0,[],false,[]]]],[14,[2,0,4,1,0,[],-1," +
	"0,0,0],0,0,-1,0,0,0,[],false,[[16,[6,0,1,1,0,[],2,0,0,0],0,-1,-1,0,0,0,[],false,[[5,[5" +
	",0,1,1,-1,[[6,0,1,1,0,[],2,0,0,0]],-1,0,0,0],0,2,-1,0,0,0,[],false,[]],[0,[1,1,1,1,0,[" +
	"],-1,0,0,0],0,-1,-1,0,0,0,[],false,[]]]]]]]],[14,[1,0,1,1,0,[],-1,0,0,0],0,1,-1,0,0,0," +
	"[],false,[[14,[6,0,1,1,0,[],0,0,0,0],0,1,-1,0,0,0,[],false,[[2,[6,0,1,1,0,[],1,0,0,0]," +
	"0,0,-1,0,0,0,[],false,[]]]]]]]],[0,\"\",[]],[],[],[],[],[]],[11,-1,0,[0,[0,0,1,1,0,[],-1" +
	",0,0,0],0,-1,-1,0,0,0,[],false,[]],[12,[6,0,1,1,0,[],1,0,0,0],0,-1,-1,0,0,0,[],false,[" +
	"[14,[2,0,2,1,0,[],-1,0,0,0],0,0,-1,0,0,0,[],false,[[2,[6,0,1,1,0,[],1,0,0,0],0,0,-1,0," +
	"0,0,[],false,[]]]],[1,[6,0,1,1,0,[],0,0,0,0],0,1,-1,0,0,0,[],false,[]]]],[0,\"\",[]],[]," +
	"[],[],[],[]]],[0,\"\",[]]]],[],[[0,0],[0,1],[2,0],[0,2]],[]]";

function lowered(text: string): ShaderModule {
	const m = irFromText(text);
	return m.ok ? m.value : new ShaderModule();
}

function holdsSegment(m: ShaderModule, name: string, phase: string): boolean {
	if (m.functions.length == 0) { return false; }
	const f = m.functions[m.functions.length - 1];
	return m.entries.length == 0 && m.ios.length == 0 && f.name == name &&
		f.params.length == 1 && f.result.kind == ShaderTypeKind.Struct &&
		sameShaderType(f.params[0].type, f.result) &&
		m.structs[f.result.structIndex].name == phase &&
		m.resources.every((r) => r.binding == -1);
}

test "a segment over its phase struct reads a frame time through its unnumbered bindings" {
	assert glslSegmentIr(uvScroll) == UV_SCROLL;
	const m = lowered(UV_SCROLL);
	assert holdsSegment(m, "uvScroll", "UvStage");
	assert m.resources.length == 1 && m.resources[0].kind == ResourceKind.UniformBlock;
	assert m.resources[0].name == "frame";
	const moved = uvScroll({ uv: vec2f(0.25, 0.5) }, { frame: { time: 0.5 } });
	assert moved.uv.x == 0.75 && moved.uv.y == 0.5;
}

test "a colour add segment returns the phase struct it was handed" {
	assert glslSegmentIr(colourAdd) == COLOUR_ADD;
	assert holdsSegment(lowered(COLOUR_ADD), "colourAdd", "Shaded");
	const added = colourAdd({ color: vec4f(0.25, 0.25, 0.25, 1.0) },
		{ tintParams: { tint: vec4f(0.5, 0.0, 0.25, 0.0) } });
	assert added.color.x == 0.75 && added.color.z == 0.5 && added.color.w == 1.0;
}

test "a segment without bindings discards" {
	assert glslSegmentIr(killAlpha) == KILL_ALPHA;
	const m = lowered(KILL_ALPHA);
	assert holdsSegment(m, "killAlpha", "Shaded");
	assert m.resources.length == 0;
	assert killAlpha({ color: vec4f(1.0, 0.0, 0.0, 1.0) }).color.x == 1.0;
}

test "a nested phase struct and a texture, sampler and storage buffer, all unnumbered" {
	assert glslSegmentIr(detailMap) == DETAIL_MAP;
	const m = lowered(DETAIL_MAP);
	assert holdsSegment(m, "detailMap", "LitStage");
	assert m.resources.map((r) => r.name).join(",") == "detail,detailSampler,lights";
	assert m.resources[0].group == m.resources[2].group;
}

struct GlowKey {
	@feature(GLOW) glow: boolean;
}

function glowOnly(shaded: Shaded, key: GlowKey): Shaded {
	let color = shaded.color;
	if (key.glow) {
		color = color * 2.0;
	}
	return { color: color };
}

test "a segment's key struct lowers to a feature branch its module names" {
	const m = lowered(glslSegmentIr(glowOnly));
	assert holdsSegment(m, "glowOnly", "Shaded");
	assert m.features.join(",") == "GLOW";
	assert m.functions[m.functions.length - 1].body.some((s) => s.kind == StmtKind.FeatureIf);
	assert glowOnly({ color: vec4f(0.25) }, { glow: true }).color.x == 0.5;
}
