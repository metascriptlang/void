// Unity .prefab (Force Text YAML) to ParticleEffect (docs/PARTICLES-AUTHORING.md §3). Every
// ParticleSystem component (class 198) becomes one system, in hierarchy order, so a sub-emitter
// child comes after its parent. Only ParticleSystem serializedVersion 8 is read, and every field
// the importer maps must be present; a value the asset cannot hold is an error naming its path.
//
// Not read, because no ParticleSystemAsset field holds them and a particle simulation does not
// depend on them: materials, shadows, probes, lightmap and GI keys, sorting layer and mask
// interaction, GPU instancing, mesh and sprite references, custom vertex streams, shape texture
// clip settings, collision quality/voxelSize/maxCollisionShapes/colliderForce keys,
// collidesWithDynamic, interiorCollisions, trigger colliderQueryMode, trail shadowBias and
// generateLightingData, custom data labels, the soft particle and camera fade distances (Unity
// keeps those on the material). Left at the asset default: space2D. A system without a
// ParticleSystemRenderer, or with a disabled one, gets RenderMode.None. An Rigidbody emitter
// velocity mode reads as Transform when the prefab has no Rigidbody, as Unity does.

import { Vec3, vec3 } from "../math/math3d";
import {
	Range, ParticleSystemAsset, ParticleEffect, SimulationSpace, GravitySource, ScalingMode,
	EmitterVelocityMode, StopAction, CullingMode, RingBufferMode, Burst, ShapeType,
	ShapeMultiModeValue, InheritVelocityMode, NoiseQuality, CollisionType, CollisionMode,
	CollisionPlane, TriggerAction, SubEmitter, SubEmitterType, SubEmitterProperty, TextureSheetMode,
	TextureSheetAnimationType, TextureSheetRowMode, TextureSheetTimeMode, TrailMode,
	TrailTextureMode, CustomDataMode, CustomDataStream, RenderMode, RenderAlignment,
	ParticleSortMode,
} from "./asset";
import {
	MinMaxCurve, MinMaxGradient, ParticleColor, AnimationCurve, CurveKey, CurveMode, WeightedMode,
	Gradient, GradientMode, GradientKind, ParticleColorSpace, ColorKey, AlphaKey, rgbaColor,
	WHITE, MAX_GRADIENT_KEYS,
} from "./curve";

export enum PrefabErrorKind {
	Syntax,
	UnsupportedVersion,
	MissingField,
	BadNumber,
	BadEnum,
	BadReference,
	// A value the asset cannot hold.
	Unsupported,
	// A sub-emitter that is not after its parent in hierarchy order.
	SubEmitterOrder,
	NoParticleSystem,
}

// `path` is the first failing field, such as `ParticleSystem[1].InitialModule.startLifetime.minMaxState`.
export struct PrefabError {
	kind: PrefabErrorKind;
	path: string;
	detail: string;
}

enum YKind {
	Scalar,
	Map,
	Seq,
}

// A node of the parsed YAML. A Map pairs keys[i] with kids[i]; a Seq has kids only.
struct YNode {
	kind: YKind;
	text: string;
	keys: Vec<string>;
	kids: Vec<int32>;
}

struct Line {
	indent: int32;
	text: string;
}

struct Doc {
	classId: int32;
	fileId: string;
	// The map under the document's type name, or -1 for a stripped document.
	body: int32;
}

struct Reader {
	nodes: Vec<YNode>;
	docs: Vec<Doc>;
	lines: Vec<Line>;
	pos: int32;
	psIds: Vec<string>;
	systemScope: string;
	scope: string;
	hasRigidbody: boolean;
	failed: boolean;
	error: PrefabError;
}

const PARTICLE_SYSTEM: int32 = 198;
const PARTICLE_RENDERER: int32 = 199;
const TRANSFORM: int32 = 4;
const RECT_TRANSFORM: int32 = 224;
const LIGHT: int32 = 108;
const PREFAB_INSTANCE: int32 = 1001;
const RIGIDBODY: int32 = 54;
const RIGIDBODY_2D: int32 = 50;
const SERIALIZED_VERSION: int32 = 8;
const MAX_DEPTH: int32 = 64;
const GRADIENT_TIME: float32 = 65535.0;
const ONE_THIRD: float32 = (1.0 / 3.0) as float32;

function fail(ref r: Reader, kind: PrefabErrorKind, path: string, detail: string): void {
	if (r.failed) { return; }
	r.failed = true;
	r.error = { kind: kind, path: path, detail: detail };
}

// ---- YAML ----

function indentOf(text: string): int32 {
	let n: int32 = 0;
	while (n < (text.length as int32) && (text.charCodeAt(n) as int32) == 32) { n = n + 1; }
	return n;
}

function isSeqItem(text: string): boolean {
	return text == "-" || text.startsWith("- ");
}

// The index of the colon that ends a block mapping key, or -1.
function keyEnd(text: string): int32 {
	const first: string = text.charAt(0);
	if (first == "{" || first == "[" || first == "'" || first == "\"") { return -1; }
	const at: int32 = text.indexOf(": ") as int32;
	if (at >= 0) { return at; }
	if (text.endsWith(":")) { return (text.length as int32) - 1; }
	return -1;
}

function unquote(text: string): string {
	const n: int32 = text.length as int32;
	if (n >= 2) {
		const first: string = text.charAt(0);
		if ((first == "'" || first == "\"") && text.charAt(n - 1) == first) {
			return text.substring(1, n - 1);
		}
	}
	return text;
}

function newNode(ref r: Reader, kind: YKind, text: string): int32 {
	r.nodes.push({ kind: kind, text: text, keys: [], kids: [] });
	return (r.nodes.length as int32) - 1;
}

function addFlowPart(ref r: Reader, node: int32, part: string): void {
	if (r.nodes[node].kind == YKind.Seq) {
		const child: int32 = parseInline(r, part);
		r.nodes[node].kids.push(child);
		return;
	}
	const colon: int32 = part.indexOf(":") as int32;
	if (colon < 0) {
		fail(r, PrefabErrorKind.Syntax, "yaml", "flow mapping entry without a colon: " + part);
		return;
	}
	const key: string = part.substring(0, colon).trim();
	const child: int32 = parseInline(r, part.substring(colon + 1, part.length as int32).trim());
	r.nodes[node].keys.push(key);
	r.nodes[node].kids.push(child);
}

// A flow mapping or sequence on one line: `{fileID: 5, guid: ab}`, `[]`.
function parseFlow(ref r: Reader, text: string): int32 {
	const n: int32 = text.length as int32;
	const open: string = text.charAt(0);
	const close: string = open == "{" ? "}" : "]";
	if (n < 2 || text.charAt(n - 1) != close) {
		fail(r, PrefabErrorKind.Syntax, "yaml", "unterminated flow collection: " + text);
		return newNode(r, YKind.Scalar, "");
	}
	const node: int32 = newNode(r, open == "{" ? YKind.Map : YKind.Seq, "");
	const inner: string = text.substring(1, n - 1).trim();
	const length: int32 = inner.length as int32;
	if (length == 0) { return node; }
	let depth: int32 = 0;
	let start: int32 = 0;
	for (let i = 0; i <= length; i++) {
		const ch: string = i == length ? "," : inner.charAt(i);
		if (ch == "{" || ch == "[") {
			depth = depth + 1;
		} else if (ch == "}" || ch == "]") {
			depth = depth - 1;
		} else if (ch == "," && depth == 0) {
			addFlowPart(r, node, inner.substring(start, i).trim());
			start = i + 1;
		}
	}
	return node;
}

function parseInline(ref r: Reader, text: string): int32 {
	const t: string = text.trim();
	if (t.length > 0 && (t.charAt(0) == "{" || t.charAt(0) == "[")) { return parseFlow(r, t); }
	return newNode(r, YKind.Scalar, unquote(t));
}

function parseBlock(ref r: Reader, depth: int32): int32 {
	if (r.pos >= (r.lines.length as int32) || depth > MAX_DEPTH) {
		fail(r, PrefabErrorKind.Syntax, "yaml", "unexpected end or depth of the document");
		return newNode(r, YKind.Scalar, "");
	}
	const line: Line = r.lines[r.pos];
	if (isSeqItem(line.text)) { return parseSeq(r, line.indent, depth + 1); }
	if (keyEnd(line.text) >= 0) { return parseMap(r, line.indent, depth + 1); }
	r.pos = r.pos + 1;
	return parseInline(r, line.text);
}

function parseMap(ref r: Reader, indent: int32, depth: int32): int32 {
	const node: int32 = newNode(r, YKind.Map, "");
	while (!r.failed && r.pos < (r.lines.length as int32)) {
		const line: Line = r.lines[r.pos];
		if (line.indent < indent || isSeqItem(line.text)) { break; }
		if (line.indent > indent) {
			fail(r, PrefabErrorKind.Syntax, "yaml", "unexpected indent at: " + line.text);
			break;
		}
		const at: int32 = keyEnd(line.text);
		if (at < 0) {
			fail(r, PrefabErrorKind.Syntax, "yaml", "expected key: value at: " + line.text);
			break;
		}
		const key: string = line.text.substring(0, at).trim();
		const rest: string = line.text.substring(at + 1, line.text.length as int32).trim();
		r.pos = r.pos + 1;
		let child: int32 = -1;
		if (rest.length == 0) {
			if (r.pos < (r.lines.length as int32)) {
				const next: Line = r.lines[r.pos];
				if (next.indent > indent || (next.indent == indent && isSeqItem(next.text))) {
					child = parseBlock(r, depth);
				}
			}
			if (child < 0) { child = newNode(r, YKind.Scalar, ""); }
		} else {
			child = parseInline(r, rest);
		}
		r.nodes[node].keys.push(key);
		r.nodes[node].kids.push(child);
	}
	return node;
}

// Unity writes a sequence at its key's indent, and an item's map continues at the item's text column.
function parseSeq(ref r: Reader, indent: int32, depth: int32): int32 {
	const node: int32 = newNode(r, YKind.Seq, "");
	while (!r.failed && r.pos < (r.lines.length as int32)) {
		const line: Line = r.lines[r.pos];
		if (line.indent != indent || !isSeqItem(line.text)) { break; }
		const rest: string = line.text.substring(1, line.text.length as int32);
		const pad: int32 = indentOf(rest);
		const content: string = rest.substring(pad, rest.length as int32);
		let child: int32 = -1;
		if (content.length == 0) {
			r.pos = r.pos + 1;
			if (r.pos < (r.lines.length as int32) && r.lines[r.pos].indent > indent) {
				child = parseBlock(r, depth);
			} else {
				child = newNode(r, YKind.Scalar, "");
			}
		} else {
			r.lines[r.pos] = { indent: indent + 1 + pad, text: content };
			child = parseBlock(r, depth);
		}
		r.nodes[node].kids.push(child);
	}
	return node;
}

// `--- !u!198 &2953250315399755358`, optionally followed by `stripped`.
function finishDoc(ref r: Reader, header: string, lines: Vec<Line>): void {
	const bang: int32 = header.indexOf("!u!") as int32;
	const amp: int32 = header.indexOf(" &") as int32;
	if (bang < 0 || amp < bang) {
		fail(r, PrefabErrorKind.Syntax, "yaml", "bad document header: " + header);
		return;
	}
	const classId: float64 = Number(header.substring(bang + 3, amp));
	const tail: string = header.substring(amp + 2, header.length as int32);
	const space: int32 = tail.indexOf(" ") as int32;
	const fileId: string = space < 0 ? tail : tail.substring(0, space);
	if (Number.isNaN(classId) || fileId.length == 0) {
		fail(r, PrefabErrorKind.Syntax, "yaml", "bad document header: " + header);
		return;
	}
	let body: int32 = -1;
	if (tail.indexOf("stripped") < 0) {
		r.lines = lines;
		r.pos = 0;
		if (lines.length == 0) {
			fail(r, PrefabErrorKind.Syntax, "yaml", "empty document: " + header);
			return;
		}
		const top: int32 = parseBlock(r, 0);
		if (r.failed) { return; }
		if (r.pos != (r.lines.length as int32) || r.nodes[top].kind != YKind.Map || r.nodes[top].kids.length != 1) {
			fail(r, PrefabErrorKind.Syntax, "yaml", "document is not one typed object: " + header);
			return;
		}
		body = r.nodes[top].kids[0];
	}
	r.docs.push({ classId: classId as int32, fileId: fileId, body: body });
}

function parseStream(ref r: Reader, text: string): void {
	let current: Vec<Line> = [];
	let header: string = "";
	let have: boolean = false;
	for (const raw of text.split("\n")) {
		let line: string = raw;
		if (line.endsWith("\r")) { line = line.substring(0, (line.length as int32) - 1); }
		if (line.startsWith("--- ")) {
			if (have) { finishDoc(r, header, current); }
			header = line;
			current = [];
			have = true;
			continue;
		}
		if (line.trim().length == 0 || line.startsWith("%") || line.startsWith("#")) { continue; }
		if (!have) {
			fail(r, PrefabErrorKind.Syntax, "yaml", "content before the first document: " + line);
			return;
		}
		if (line.indexOf("\t") >= 0) {
			fail(r, PrefabErrorKind.Syntax, "yaml", "tab in: " + line);
			return;
		}
		const indent: int32 = indentOf(line);
		current.push({ indent: indent, text: line.substring(indent, line.length as int32) });
		if (r.failed) { return; }
	}
	if (have) { finishDoc(r, header, current); }
	if (!have) { fail(r, PrefabErrorKind.Syntax, "yaml", "no document"); }
}

// ---- field access ----

function find(r: Reader, n: int32, key: string): int32 {
	if (n < 0 || r.nodes[n].kind != YKind.Map) { return -1; }
	for (let i = 0; i < (r.nodes[n].keys.length as int32); i++) {
		if (r.nodes[n].keys[i] == key) { return r.nodes[n].kids[i]; }
	}
	return -1;
}

function pathOf(r: Reader, key: string): string {
	return r.scope + "." + key;
}

function field(ref r: Reader, n: int32, key: string): int32 {
	const k: int32 = find(r, n, key);
	if (k < 0) { fail(r, PrefabErrorKind.MissingField, pathOf(r, key), ""); }
	return k;
}

function enter(ref r: Reader, key: string): string {
	const saved: string = r.scope;
	r.scope = saved + "." + key;
	return saved;
}

function scalarOf(ref r: Reader, n: int32, key: string): string {
	const k: int32 = field(r, n, key);
	if (k < 0) { return ""; }
	if (r.nodes[k].kind != YKind.Scalar) {
		fail(r, PrefabErrorKind.Syntax, pathOf(r, key), "expected a scalar");
		return "";
	}
	return r.nodes[k].text;
}

function numberOf(ref r: Reader, text: string, path: string): float64 {
	const v: float64 = text.length == 0 ? Number("x") : Number(text);
	if (Number.isNaN(v)) {
		fail(r, PrefabErrorKind.BadNumber, path, text);
		return 0.0;
	}
	return v;
}

function num(ref r: Reader, n: int32, key: string): float32 {
	const text: string = scalarOf(r, n, key);
	if (r.failed) { return 0.0; }
	return numberOf(r, text, pathOf(r, key)) as float32;
}

function intOf(ref r: Reader, n: int32, key: string): int32 {
	const text: string = scalarOf(r, n, key);
	if (r.failed) { return 0; }
	const v: float64 = numberOf(r, text, pathOf(r, key));
	if (v != Math.floor(v) || v < -2147483648.0 || v > 2147483647.0) {
		fail(r, PrefabErrorKind.BadNumber, pathOf(r, key), text);
		return 0;
	}
	return v as int32;
}

function uintOf(ref r: Reader, n: int32, key: string): uint32 {
	const text: string = scalarOf(r, n, key);
	if (r.failed) { return 0; }
	const v: float64 = numberOf(r, text, pathOf(r, key));
	if (v != Math.floor(v) || v < 0.0 || v > 4294967295.0) {
		fail(r, PrefabErrorKind.BadNumber, pathOf(r, key), text);
		return 0;
	}
	return v as uint32;
}

function flag(ref r: Reader, n: int32, key: string): boolean {
	const text: string = scalarOf(r, n, key);
	if (r.failed) { return false; }
	if (text != "0" && text != "1") {
		fail(r, PrefabErrorKind.BadNumber, pathOf(r, key), text);
	}
	return text == "1";
}

// An enum written as an integer in [0, count).
function pick(ref r: Reader, n: int32, key: string, count: int32): int32 {
	const v: int32 = intOf(r, n, key);
	if (!r.failed && (v < 0 || v >= count)) {
		fail(r, PrefabErrorKind.BadEnum, pathOf(r, key), v.toString());
		return 0;
	}
	return v;
}

function vec3Of(ref r: Reader, n: int32, key: string): Vec3 {
	const k: int32 = field(r, n, key);
	const saved: string = enter(r, key);
	const v: Vec3 = vec3(num(r, k, "x"), num(r, k, "y"), num(r, k, "z"));
	r.scope = saved;
	return v;
}

// The fields of a Vector2 are x and y.
function rangeOf(ref r: Reader, n: int32, key: string): Range {
	const k: int32 = field(r, n, key);
	const saved: string = enter(r, key);
	const v: Range = { min: num(r, k, "x"), max: num(r, k, "y") };
	r.scope = saved;
	return v;
}

function colorOf(ref r: Reader, n: int32, key: string): ParticleColor {
	const k: int32 = field(r, n, key);
	const saved: string = enter(r, key);
	const c: ParticleColor = rgbaColor(num(r, k, "r"), num(r, k, "g"), num(r, k, "b"), num(r, k, "a"));
	r.scope = saved;
	return c;
}

// The sequence under `key`, or -1 after a failure.
function seqOf(ref r: Reader, n: int32, key: string): int32 {
	const k: int32 = field(r, n, key);
	if (k >= 0 && r.nodes[k].kind != YKind.Seq) {
		fail(r, PrefabErrorKind.Syntax, pathOf(r, key), "expected a sequence");
		return -1;
	}
	return k;
}

// The fileID of a `{fileID: ...}` reference; "0" is the null reference.
function refOf(ref r: Reader, n: int32, key: string): string {
	const k: int32 = field(r, n, key);
	const saved: string = enter(r, key);
	const id: string = k < 0 ? "0" : scalarOf(r, k, "fileID");
	r.scope = saved;
	return id;
}

function docOf(r: Reader, fileId: string): int32 {
	for (let i = 0; i < (r.docs.length as int32); i++) {
		if (r.docs[i].fileId == fileId) { return i; }
	}
	return -1;
}

// ---- curves and gradients ----

function animationCurve(ref r: Reader, n: int32, key: string): AnimationCurve {
	const c: int32 = field(r, n, key);
	const saved: string = enter(r, key);
	let keys: Vec<CurveKey> = [];
	const list: int32 = seqOf(r, c, "m_Curve");
	if (list >= 0) {
		for (let i = 0; i < (r.nodes[list].kids.length as int32); i++) {
			const item: int32 = r.nodes[list].kids[i];
			const outer: string = enter(r, `m_Curve[${i}]`);
			const mode: int32 = pick(r, item, "weightedMode", 4);
			const inWeighted: boolean = mode == (WeightedMode.In as int32) || mode == (WeightedMode.Both as int32);
			const outWeighted: boolean = mode == (WeightedMode.Out as int32) || mode == (WeightedMode.Both as int32);
			const inWeight: float32 = num(r, item, "inWeight");
			const outWeight: float32 = num(r, item, "outWeight");
			keys.push({
				time: num(r, item, "time"), value: num(r, item, "value"),
				inSlope: num(r, item, "inSlope"), outSlope: num(r, item, "outSlope"),
				weightedMode: mode as WeightedMode,
				inWeight: inWeighted ? inWeight : ONE_THIRD, outWeight: outWeighted ? outWeight : ONE_THIRD,
			});
			r.scope = outer;
		}
	}
	if (intOf(r, c, "m_PreInfinity") != 2) { fail(r, PrefabErrorKind.Unsupported, pathOf(r, "m_PreInfinity"), "only Clamp is read"); }
	if (intOf(r, c, "m_PostInfinity") != 2) { fail(r, PrefabErrorKind.Unsupported, pathOf(r, "m_PostInfinity"), "only Clamp is read"); }
	r.scope = saved;
	return { keys: keys };
}

function minMaxCurve(ref r: Reader, n: int32, key: string): MinMaxCurve {
	const c: int32 = field(r, n, key);
	const saved: string = enter(r, key);
	const state: int32 = pick(r, c, "minMaxState", 4);
	const scalar: float32 = num(r, c, "scalar");
	const minScalar: float32 = num(r, c, "minScalar");
	const maxCurve: AnimationCurve = animationCurve(r, c, "maxCurve");
	const minCurve: AnimationCurve = animationCurve(r, c, "minCurve");
	r.scope = saved;
	return { mode: state as CurveMode, scalar: scalar, minScalar: minScalar, maxCurve: maxCurve, minCurve: minCurve };
}

function gradient(ref r: Reader, n: int32, key: string): Gradient {
	const g: int32 = field(r, n, key);
	const saved: string = enter(r, key);
	const mode: int32 = pick(r, g, "m_Mode", 3);
	// -1 is Unity's "project colour space", which a prefab does not carry.
	const space: int32 = intOf(r, g, "m_ColorSpace");
	if (space < -1 || space > 1) { fail(r, PrefabErrorKind.BadEnum, pathOf(r, "m_ColorSpace"), space.toString()); }
	const colorCount: int32 = intOf(r, g, "m_NumColorKeys");
	const alphaCount: int32 = intOf(r, g, "m_NumAlphaKeys");
	if (colorCount < 1 || colorCount > MAX_GRADIENT_KEYS) { fail(r, PrefabErrorKind.BadNumber, pathOf(r, "m_NumColorKeys"), colorCount.toString()); }
	if (alphaCount < 1 || alphaCount > MAX_GRADIENT_KEYS) { fail(r, PrefabErrorKind.BadNumber, pathOf(r, "m_NumAlphaKeys"), alphaCount.toString()); }
	let colorKeys: Vec<ColorKey> = [];
	let alphaKeys: Vec<AlphaKey> = [];
	if (!r.failed) {
		for (let i = 0; i < colorCount; i++) {
			const c: ParticleColor = colorOf(r, g, `key${i}`);
			colorKeys.push({ color: rgbaColor(c.r, c.g, c.b, 1.0), time: num(r, g, `ctime${i}`) / GRADIENT_TIME });
		}
		for (let i = 0; i < alphaCount; i++) {
			const c: ParticleColor = colorOf(r, g, `key${i}`);
			alphaKeys.push({ alpha: c.a, time: num(r, g, `atime${i}`) / GRADIENT_TIME });
		}
	}
	r.scope = saved;
	return {
		colorKeys: colorKeys, alphaKeys: alphaKeys, mode: mode as GradientMode,
		colorSpace: space == 1 ? ParticleColorSpace.Linear : ParticleColorSpace.Gamma,
	};
}

function minMaxGradient(ref r: Reader, n: int32, key: string): MinMaxGradient {
	const c: int32 = field(r, n, key);
	const saved: string = enter(r, key);
	const state: int32 = pick(r, c, "minMaxState", 5);
	const minColor: ParticleColor = colorOf(r, c, "minColor");
	const maxColor: ParticleColor = colorOf(r, c, "maxColor");
	const maxGradient: Gradient = gradient(r, c, "maxGradient");
	const minGradient: Gradient = gradient(r, c, "minGradient");
	r.scope = saved;
	return {
		mode: state as GradientKind, minColor: minColor, maxColor: maxColor,
		maxGradient: maxGradient, minGradient: minGradient,
	};
}

// ---- modules ----

// Opens module `name` of the ParticleSystem body `ps`; fields are then read under its path.
function block(ref r: Reader, ps: int32, name: string): int32 {
	r.scope = r.systemScope;
	const m: int32 = field(r, ps, name);
	r.scope = r.systemScope + "." + name;
	return m;
}

function spaceOf(world: boolean): SimulationSpace {
	return world ? SimulationSpace.World : SimulationSpace.Local;
}

function readMain(ref r: Reader, ps: int32, ref a: ParticleSystemAsset): void {
	r.scope = r.systemScope;
	a.main.duration = num(r, ps, "lengthInSec");
	a.main.loop = flag(r, ps, "looping");
	a.main.prewarm = flag(r, ps, "prewarm");
	a.main.playOnAwake = flag(r, ps, "playOnAwake");
	a.main.startDelay = minMaxCurve(r, ps, "startDelay");
	a.main.simulationSpeed = num(r, ps, "simulationSpeed");
	a.main.stopAction = pick(r, ps, "stopAction", 4) as StopAction;
	a.main.cullingMode = pick(r, ps, "cullingMode", 4) as CullingMode;
	a.main.ringBufferMode = pick(r, ps, "ringBufferMode", 3) as RingBufferMode;
	a.main.ringBufferLoopRange = rangeOf(r, ps, "ringBufferLoopRange");
	a.main.useAutoRandomSeed = flag(r, ps, "autoRandomSeed");
	a.main.randomSeed = uintOf(r, ps, "randomSeed");
	a.main.scalingMode = pick(r, ps, "scalingMode", 3) as ScalingMode;
	if (flag(r, ps, "useUnscaledTime")) {
		fail(r, PrefabErrorKind.Unsupported, pathOf(r, "useUnscaledTime"), "the asset has no unscaled time");
	}
	// moveWithTransform holds ParticleSystemSimulationSpace: 0 Local, 1 World, 2 Custom.
	const space: int32 = pick(r, ps, "moveWithTransform", 3);
	if (space == 2) { fail(r, PrefabErrorKind.Unsupported, pathOf(r, "moveWithTransform"), "custom simulation space"); }
	a.main.simulationSpace = spaceOf(space == 1);
	const velocityMode: int32 = pick(r, ps, "emitterVelocityMode", 3);
	if (velocityMode == 1 && r.hasRigidbody) {
		fail(r, PrefabErrorKind.Unsupported, pathOf(r, "emitterVelocityMode"), "Rigidbody emitter velocity");
	}
	a.main.emitterVelocityMode = velocityMode == 2 ? EmitterVelocityMode.Custom : EmitterVelocityMode.Transform;

	const m: int32 = block(r, ps, "InitialModule");
	a.main.startLifetime = minMaxCurve(r, m, "startLifetime");
	a.main.startSpeed = minMaxCurve(r, m, "startSpeed");
	a.main.startSize3D = flag(r, m, "size3D");
	a.main.startSizeX = minMaxCurve(r, m, "startSize");
	a.main.startSizeY = minMaxCurve(r, m, "startSizeY");
	a.main.startSizeZ = minMaxCurve(r, m, "startSizeZ");
	a.main.startRotation3D = flag(r, m, "rotation3D");
	a.main.startRotationX = minMaxCurve(r, m, "startRotationX");
	a.main.startRotationY = minMaxCurve(r, m, "startRotationY");
	a.main.startRotationZ = minMaxCurve(r, m, "startRotation");
	a.main.flipRotation = num(r, m, "randomizeRotationDirection");
	a.main.startColor = minMaxGradient(r, m, "startColor");
	a.main.gravitySource = pick(r, m, "gravitySource", 2) as GravitySource;
	a.main.gravityModifier = minMaxCurve(r, m, "gravityModifier");
	a.main.maxParticles = intOf(r, m, "maxNumParticles");
	a.main.emitterVelocity = vec3Of(r, m, "customEmitterVelocity");
}

function readEmission(ref r: Reader, ps: int32, ref a: ParticleSystemAsset): void {
	const m: int32 = block(r, ps, "EmissionModule");
	a.emission.enabled = flag(r, m, "enabled");
	a.emission.rateOverTime = minMaxCurve(r, m, "rateOverTime");
	a.emission.rateOverDistance = minMaxCurve(r, m, "rateOverDistance");
	const list: int32 = seqOf(r, m, "m_Bursts");
	let bursts: Vec<Burst> = [];
	if (list >= 0) {
		for (let i = 0; i < (r.nodes[list].kids.length as int32); i++) {
			const item: int32 = r.nodes[list].kids[i];
			const saved: string = enter(r, `m_Bursts[${i}]`);
			bursts.push({
				time: num(r, item, "time"), count: minMaxCurve(r, item, "countCurve"),
				cycleCount: intOf(r, item, "cycleCount"), repeatInterval: num(r, item, "repeatInterval"),
				probability: num(r, item, "probability"),
			});
			r.scope = saved;
		}
	}
	a.emission.bursts = bursts;
}

// Unity's shape numbering; the shell variants (1, 3, 7, 9, 11) are the base shape at thickness 0.
function shapeTypeOf(v: int32): ShapeType {
	return match (v) {
		0 | 1 => ShapeType.Sphere,
		2 | 3 => ShapeType.Hemisphere,
		4 | 7 => ShapeType.Cone,
		5 => ShapeType.Box,
		6 => ShapeType.Mesh,
		8 | 9 => ShapeType.ConeVolume,
		10 | 11 => ShapeType.Circle,
		12 => ShapeType.SingleSidedEdge,
		13 => ShapeType.MeshRenderer,
		14 => ShapeType.SkinnedMeshRenderer,
		15 => ShapeType.BoxShell,
		16 => ShapeType.BoxEdge,
		17 => ShapeType.Donut,
		18 => ShapeType.Rectangle,
		19 => ShapeType.Sprite,
		_ => ShapeType.SpriteRenderer,
	};
}

function readShape(ref r: Reader, ps: int32, ref a: ParticleSystemAsset): void {
	const m: int32 = block(r, ps, "ShapeModule");
	a.shape.enabled = flag(r, m, "enabled");
	const unityType: int32 = pick(r, m, "type", 21);
	a.shape.shapeType = shapeTypeOf(unityType);
	a.shape.radiusThickness = num(r, m, "radiusThickness");
	if (unityType == 1 || unityType == 3 || unityType == 7 || unityType == 9 || unityType == 11) {
		a.shape.radiusThickness = 0.0;
	}
	a.shape.angle = num(r, m, "angle");
	a.shape.length = num(r, m, "length");
	a.shape.boxThickness = vec3Of(r, m, "boxThickness");
	a.shape.donutRadius = num(r, m, "donutRadius");
	a.shape.position = vec3Of(r, m, "m_Position");
	a.shape.rotation = vec3Of(r, m, "m_Rotation");
	a.shape.scale = vec3Of(r, m, "m_Scale");
	a.shape.alignToDirection = flag(r, m, "alignToDirection");
	a.shape.randomDirectionAmount = num(r, m, "randomDirectionAmount");
	a.shape.sphericalDirectionAmount = num(r, m, "sphericalDirectionAmount");
	a.shape.randomPositionAmount = num(r, m, "randomPositionAmount");
	if (refOf(r, m, "m_Texture") != "0") {
		fail(r, PrefabErrorKind.Unsupported, pathOf(r, "m_Texture"), "shape texture tint and clip");
	}
	const radius: int32 = field(r, m, "radius");
	let saved: string = enter(r, "radius");
	a.shape.radius = num(r, radius, "value");
	a.shape.radiusMode = pick(r, radius, "mode", 4) as ShapeMultiModeValue;
	a.shape.radiusSpread = num(r, radius, "spread");
	a.shape.radiusSpeed = minMaxCurve(r, radius, "speed");
	r.scope = saved;
	const arc: int32 = field(r, m, "arc");
	saved = enter(r, "arc");
	a.shape.arc = num(r, arc, "value");
	a.shape.arcMode = pick(r, arc, "mode", 4) as ShapeMultiModeValue;
	a.shape.arcSpread = num(r, arc, "spread");
	a.shape.arcSpeed = minMaxCurve(r, arc, "speed");
	r.scope = saved;
}

function readVelocity(ref r: Reader, ps: int32, ref a: ParticleSystemAsset): void {
	let m: int32 = block(r, ps, "VelocityModule");
	a.velocityOverLifetime.enabled = flag(r, m, "enabled");
	a.velocityOverLifetime.x = minMaxCurve(r, m, "x");
	a.velocityOverLifetime.y = minMaxCurve(r, m, "y");
	a.velocityOverLifetime.z = minMaxCurve(r, m, "z");
	a.velocityOverLifetime.space = spaceOf(flag(r, m, "inWorldSpace"));
	a.velocityOverLifetime.orbitalX = minMaxCurve(r, m, "orbitalX");
	a.velocityOverLifetime.orbitalY = minMaxCurve(r, m, "orbitalY");
	a.velocityOverLifetime.orbitalZ = minMaxCurve(r, m, "orbitalZ");
	a.velocityOverLifetime.orbitalOffsetX = minMaxCurve(r, m, "orbitalOffsetX");
	a.velocityOverLifetime.orbitalOffsetY = minMaxCurve(r, m, "orbitalOffsetY");
	a.velocityOverLifetime.orbitalOffsetZ = minMaxCurve(r, m, "orbitalOffsetZ");
	a.velocityOverLifetime.radial = minMaxCurve(r, m, "radial");
	a.velocityOverLifetime.speedModifier = minMaxCurve(r, m, "speedModifier");

	m = block(r, ps, "ClampVelocityModule");
	a.limitVelocityOverLifetime.enabled = flag(r, m, "enabled");
	a.limitVelocityOverLifetime.separateAxes = flag(r, m, "separateAxis");
	a.limitVelocityOverLifetime.limit = minMaxCurve(r, m, "magnitude");
	a.limitVelocityOverLifetime.limitX = minMaxCurve(r, m, "x");
	a.limitVelocityOverLifetime.limitY = minMaxCurve(r, m, "y");
	a.limitVelocityOverLifetime.limitZ = minMaxCurve(r, m, "z");
	a.limitVelocityOverLifetime.space = spaceOf(flag(r, m, "inWorldSpace"));
	a.limitVelocityOverLifetime.dampen = num(r, m, "dampen");
	a.limitVelocityOverLifetime.drag = minMaxCurve(r, m, "drag");
	a.limitVelocityOverLifetime.multiplyDragByParticleSize = flag(r, m, "multiplyDragByParticleSize");
	a.limitVelocityOverLifetime.multiplyDragByParticleVelocity = flag(r, m, "multiplyDragByParticleVelocity");

	m = block(r, ps, "InheritVelocityModule");
	a.inheritVelocity.enabled = flag(r, m, "enabled");
	a.inheritVelocity.mode = pick(r, m, "m_Mode", 2) as InheritVelocityMode;
	a.inheritVelocity.curve = minMaxCurve(r, m, "m_Curve");

	m = block(r, ps, "LifetimeByEmitterSpeedModule");
	a.lifetimeByEmitterSpeed.enabled = flag(r, m, "enabled");
	a.lifetimeByEmitterSpeed.curve = minMaxCurve(r, m, "m_Curve");
	a.lifetimeByEmitterSpeed.range = rangeOf(r, m, "m_Range");

	m = block(r, ps, "ForceModule");
	a.forceOverLifetime.enabled = flag(r, m, "enabled");
	a.forceOverLifetime.x = minMaxCurve(r, m, "x");
	a.forceOverLifetime.y = minMaxCurve(r, m, "y");
	a.forceOverLifetime.z = minMaxCurve(r, m, "z");
	a.forceOverLifetime.space = spaceOf(flag(r, m, "inWorldSpace"));
	a.forceOverLifetime.randomized = flag(r, m, "randomizePerFrame");

	m = block(r, ps, "ExternalForcesModule");
	a.externalForces.enabled = flag(r, m, "enabled");
	a.externalForces.multiplier = minMaxCurve(r, m, "multiplierCurve");
	if (pick(r, m, "influenceFilter", 3) != 0) {
		fail(r, PrefabErrorKind.Unsupported, pathOf(r, "influenceFilter"), "force field lists are references");
	}
	const mask: int32 = field(r, m, "influenceMask");
	const saved: string = enter(r, "influenceMask");
	a.externalForces.influenceMask = uintOf(r, mask, "m_Bits");
	r.scope = saved;
}

function readAppearance(ref r: Reader, ps: int32, ref a: ParticleSystemAsset): void {
	let m: int32 = block(r, ps, "ColorModule");
	a.colorOverLifetime.enabled = flag(r, m, "enabled");
	a.colorOverLifetime.color = minMaxGradient(r, m, "gradient");

	m = block(r, ps, "ColorBySpeedModule");
	a.colorBySpeed.enabled = flag(r, m, "enabled");
	a.colorBySpeed.color = minMaxGradient(r, m, "gradient");
	a.colorBySpeed.range = rangeOf(r, m, "range");

	m = block(r, ps, "SizeModule");
	a.sizeOverLifetime.enabled = flag(r, m, "enabled");
	a.sizeOverLifetime.separateAxes = flag(r, m, "separateAxes");
	a.sizeOverLifetime.x = minMaxCurve(r, m, "curve");
	a.sizeOverLifetime.y = minMaxCurve(r, m, "y");
	a.sizeOverLifetime.z = minMaxCurve(r, m, "z");

	m = block(r, ps, "SizeBySpeedModule");
	a.sizeBySpeed.enabled = flag(r, m, "enabled");
	a.sizeBySpeed.separateAxes = flag(r, m, "separateAxes");
	a.sizeBySpeed.x = minMaxCurve(r, m, "curve");
	a.sizeBySpeed.y = minMaxCurve(r, m, "y");
	a.sizeBySpeed.z = minMaxCurve(r, m, "z");
	a.sizeBySpeed.range = rangeOf(r, m, "range");

	// Radians per second in the file and in the asset.
	m = block(r, ps, "RotationModule");
	a.rotationOverLifetime.enabled = flag(r, m, "enabled");
	a.rotationOverLifetime.separateAxes = flag(r, m, "separateAxes");
	a.rotationOverLifetime.x = minMaxCurve(r, m, "x");
	a.rotationOverLifetime.y = minMaxCurve(r, m, "y");
	a.rotationOverLifetime.z = minMaxCurve(r, m, "curve");

	m = block(r, ps, "RotationBySpeedModule");
	a.rotationBySpeed.enabled = flag(r, m, "enabled");
	a.rotationBySpeed.separateAxes = flag(r, m, "separateAxes");
	a.rotationBySpeed.x = minMaxCurve(r, m, "x");
	a.rotationBySpeed.y = minMaxCurve(r, m, "y");
	a.rotationBySpeed.z = minMaxCurve(r, m, "curve");
	a.rotationBySpeed.range = rangeOf(r, m, "range");

	m = block(r, ps, "NoiseModule");
	a.noise.enabled = flag(r, m, "enabled");
	a.noise.separateAxes = flag(r, m, "separateAxes");
	a.noise.strengthX = minMaxCurve(r, m, "strength");
	a.noise.strengthY = minMaxCurve(r, m, "strengthY");
	a.noise.strengthZ = minMaxCurve(r, m, "strengthZ");
	a.noise.frequency = num(r, m, "frequency");
	a.noise.scrollSpeed = minMaxCurve(r, m, "scrollSpeed");
	a.noise.damping = flag(r, m, "damping");
	a.noise.octaveCount = intOf(r, m, "octaves");
	a.noise.octaveMultiplier = num(r, m, "octaveMultiplier");
	a.noise.octaveScale = num(r, m, "octaveScale");
	a.noise.quality = pick(r, m, "quality", 3) as NoiseQuality;
	a.noise.remapEnabled = flag(r, m, "remapEnabled");
	a.noise.remapX = minMaxCurve(r, m, "remap");
	a.noise.remapY = minMaxCurve(r, m, "remapY");
	a.noise.remapZ = minMaxCurve(r, m, "remapZ");
	a.noise.positionAmount = minMaxCurve(r, m, "positionAmount");
	a.noise.rotationAmount = minMaxCurve(r, m, "rotationAmount");
	a.noise.sizeAmount = minMaxCurve(r, m, "sizeAmount");

	m = block(r, ps, "UVModule");
	a.textureSheetAnimation.enabled = flag(r, m, "enabled");
	a.textureSheetAnimation.mode = pick(r, m, "mode", 2) as TextureSheetMode;
	a.textureSheetAnimation.numTilesX = intOf(r, m, "tilesX");
	a.textureSheetAnimation.numTilesY = intOf(r, m, "tilesY");
	a.textureSheetAnimation.animation = pick(r, m, "animationType", 2) as TextureSheetAnimationType;
	const rowMode: int32 = pick(r, m, "rowMode", 3);
	if (rowMode == 2) { fail(r, PrefabErrorKind.Unsupported, pathOf(r, "rowMode"), "mesh index rows"); }
	a.textureSheetAnimation.rowMode = rowMode == 1 ? TextureSheetRowMode.Random : TextureSheetRowMode.Custom;
	a.textureSheetAnimation.rowIndex = intOf(r, m, "rowIndex");
	a.textureSheetAnimation.timeMode = pick(r, m, "timeMode", 3) as TextureSheetTimeMode;
	a.textureSheetAnimation.frameOverTime = minMaxCurve(r, m, "frameOverTime");
	a.textureSheetAnimation.startFrame = minMaxCurve(r, m, "startFrame");
	a.textureSheetAnimation.fps = num(r, m, "fps");
	a.textureSheetAnimation.speedRange = rangeOf(r, m, "speedRange");
	a.textureSheetAnimation.cycleCount = intOf(r, m, "cycles");
	a.textureSheetAnimation.flipU = num(r, m, "flipU");
	a.textureSheetAnimation.flipV = num(r, m, "flipV");
	const sprites: int32 = seqOf(r, m, "sprites");
	if (sprites >= 0) { a.textureSheetAnimation.spriteCount = r.nodes[sprites].kids.length as int32; }
}

// A Light component's colour for the Lights module, or white when the module names none.
function lightColor(ref r: Reader, m: int32): ParticleColor {
	const id: string = refOf(r, m, "light");
	if (id == "0" || r.failed) { return WHITE; }
	const d: int32 = docOf(r, id);
	if (d < 0 || r.docs[d].classId != LIGHT) {
		fail(r, PrefabErrorKind.BadReference, pathOf(r, "light"), id);
		return WHITE;
	}
	return colorOf(r, r.docs[d].body, "m_Color");
}

function readLightsTrailsData(ref r: Reader, ps: int32, ref a: ParticleSystemAsset): void {
	let m: int32 = block(r, ps, "LightsModule");
	a.lights.enabled = flag(r, m, "enabled");
	a.lights.ratio = num(r, m, "ratio");
	a.lights.useRandomDistribution = flag(r, m, "randomDistribution");
	a.lights.useParticleColor = flag(r, m, "color");
	a.lights.sizeAffectsRange = flag(r, m, "range");
	a.lights.alphaAffectsIntensity = flag(r, m, "intensity");
	a.lights.range = minMaxCurve(r, m, "rangeCurve");
	a.lights.intensity = minMaxCurve(r, m, "intensityCurve");
	a.lights.maxLights = intOf(r, m, "maxLights");
	a.lights.color = lightColor(r, m);

	m = block(r, ps, "TrailModule");
	a.trails.enabled = flag(r, m, "enabled");
	a.trails.mode = pick(r, m, "mode", 2) as TrailMode;
	a.trails.ratio = num(r, m, "ratio");
	a.trails.lifetime = minMaxCurve(r, m, "lifetime");
	a.trails.minVertexDistance = num(r, m, "minVertexDistance");
	a.trails.textureMode = pick(r, m, "textureMode", 5) as TrailTextureMode;
	const scale: int32 = field(r, m, "textureScale");
	const saved: string = enter(r, "textureScale");
	a.trails.textureScale = vec3(num(r, scale, "x"), num(r, scale, "y"), 0.0);
	r.scope = saved;
	a.trails.worldSpace = flag(r, m, "worldSpace");
	a.trails.dieWithParticles = flag(r, m, "dieWithParticles");
	a.trails.sizeAffectsWidth = flag(r, m, "sizeAffectsWidth");
	a.trails.sizeAffectsLifetime = flag(r, m, "sizeAffectsLifetime");
	a.trails.inheritParticleColor = flag(r, m, "inheritParticleColor");
	a.trails.colorOverLifetime = minMaxGradient(r, m, "colorOverLifetime");
	a.trails.widthOverTrail = minMaxCurve(r, m, "widthOverTrail");
	a.trails.colorOverTrail = minMaxGradient(r, m, "colorOverTrail");
	a.trails.ribbonCount = intOf(r, m, "ribbonCount");
	a.trails.splitSubEmitterRibbons = flag(r, m, "splitSubEmitterRibbons");
	a.trails.attachRibbonsToTransform = flag(r, m, "attachRibbonsToTransform");

	m = block(r, ps, "CustomDataModule");
	a.customData.enabled = flag(r, m, "enabled");
	a.customData.first = customStream(r, m, 0);
	a.customData.second = customStream(r, m, 1);
}

function customStream(ref r: Reader, m: int32, i: int32): CustomDataStream {
	return {
		mode: pick(r, m, `mode${i}`, 3) as CustomDataMode,
		vectorComponentCount: intOf(r, m, `vectorComponentCount${i}`),
		x: minMaxCurve(r, m, `vector${i}_0`), y: minMaxCurve(r, m, `vector${i}_1`),
		z: minMaxCurve(r, m, `vector${i}_2`), w: minMaxCurve(r, m, `vector${i}_3`),
		color: minMaxGradient(r, m, `color${i}`),
	};
}

// ---- hierarchy ----

function rotate(q: Vec3, w: float32, v: Vec3): Vec3 {
	const t: Vec3 = vec3(
		2.0 * (q.y * v.z - q.z * v.y), 2.0 * (q.z * v.x - q.x * v.z), 2.0 * (q.x * v.y - q.y * v.x));
	return vec3(
		v.x + w * t.x + (q.y * t.z - q.z * t.y),
		v.y + w * t.y + (q.z * t.x - q.x * t.z),
		v.z + w * t.z + (q.x * t.y - q.y * t.x));
}

// The document of class `classId` among the components of document `d`'s GameObject, or -1.
function componentOf(ref r: Reader, d: int32, classId: int32): int32 {
	const object: int32 = docOf(r, refOf(r, r.docs[d].body, "m_GameObject"));
	if (object < 0) { return -1; }
	const list: int32 = seqOf(r, r.docs[object].body, "m_Component");
	if (list < 0) { return -1; }
	for (let i = 0; i < (r.nodes[list].kids.length as int32); i++) {
		const c: int32 = docOf(r, refOf(r, r.nodes[list].kids[i], "component"));
		if (c >= 0 && r.docs[c].classId == classId) { return c; }
	}
	return -1;
}

// A collision plane from a Transform document: its world position and its up axis, with the
// prefab root at the origin.
function planeOf(ref r: Reader, transform: int32): CollisionPlane {
	let t: int32 = transform;
	let point: Vec3 = vec3(0.0, 0.0, 0.0);
	let normal: Vec3 = vec3(0.0, 1.0, 0.0);
	let first: boolean = true;
	for (let depth = 0; t >= 0 && depth < MAX_DEPTH; depth++) {
		const body: int32 = r.docs[t].body;
		const rot: int32 = field(r, body, "m_LocalRotation");
		const q: Vec3 = vec3(num(r, rot, "x"), num(r, rot, "y"), num(r, rot, "z"));
		const w: float32 = num(r, rot, "w");
		const pos: Vec3 = vec3Of(r, body, "m_LocalPosition");
		const scale: Vec3 = vec3Of(r, body, "m_LocalScale");
		if (first) {
			point = pos;
			first = false;
		} else {
			const scaled: Vec3 = vec3(point.x * scale.x, point.y * scale.y, point.z * scale.z);
			const turned: Vec3 = rotate(q, w, scaled);
			point = vec3(pos.x + turned.x, pos.y + turned.y, pos.z + turned.z);
		}
		normal = rotate(q, w, normal);
		const father: string = refOf(r, body, "m_Father");
		t = father == "0" ? -1 : docOf(r, father);
		if (r.failed) { break; }
	}
	return { point: point, normal: normal };
}

function readCollision(ref r: Reader, ps: int32, ref a: ParticleSystemAsset): void {
	let m: int32 = block(r, ps, "CollisionModule");
	a.collision.enabled = flag(r, m, "enabled");
	a.collision.collisionType = pick(r, m, "type", 2) as CollisionType;
	a.collision.mode = pick(r, m, "collisionMode", 2) as CollisionMode;
	a.collision.dampen = minMaxCurve(r, m, "m_Dampen");
	a.collision.bounce = minMaxCurve(r, m, "m_Bounce");
	a.collision.lifetimeLoss = minMaxCurve(r, m, "m_EnergyLossOnCollision");
	a.collision.minKillSpeed = num(r, m, "minKillSpeed");
	a.collision.maxKillSpeed = num(r, m, "maxKillSpeed");
	a.collision.radiusScale = num(r, m, "radiusScale");
	a.collision.sendCollisionMessages = flag(r, m, "collisionMessages");
	const mask: int32 = field(r, m, "collidesWith");
	let saved: string = enter(r, "collidesWith");
	a.collision.collidesWith = uintOf(r, mask, "m_Bits");
	r.scope = saved;
	const list: int32 = seqOf(r, m, "m_Planes");
	let planes: Vec<CollisionPlane> = [];
	if (list >= 0) {
		for (let i = 0; i < (r.nodes[list].kids.length as int32); i++) {
			saved = enter(r, `m_Planes[${i}]`);
			const id: string = scalarOf(r, r.nodes[list].kids[i], "fileID");
			if (id != "0" && !r.failed) {
				const t: int32 = docOf(r, id);
				if (t < 0 || (r.docs[t].classId != TRANSFORM && r.docs[t].classId != RECT_TRANSFORM)) {
					fail(r, PrefabErrorKind.BadReference, r.scope, id);
				} else {
					planes.push(planeOf(r, t));
				}
			}
			r.scope = saved;
		}
	}
	a.collision.planes = planes;

	m = block(r, ps, "TriggerModule");
	a.trigger.enabled = flag(r, m, "enabled");
	a.trigger.inside = pick(r, m, "inside", 3) as TriggerAction;
	a.trigger.outside = pick(r, m, "outside", 3) as TriggerAction;
	a.trigger.enter = pick(r, m, "enter", 3) as TriggerAction;
	a.trigger.exit = pick(r, m, "exit", 3) as TriggerAction;
	a.trigger.radiusScale = num(r, m, "radiusScale");
	const primitives: int32 = seqOf(r, m, "primitives");
	if (primitives >= 0) {
		for (let i = 0; i < (r.nodes[primitives].kids.length as int32); i++) {
			saved = enter(r, `primitives[${i}]`);
			if (scalarOf(r, r.nodes[primitives].kids[i], "fileID") != "0") {
				fail(r, PrefabErrorKind.Unsupported, r.scope, "trigger colliders are scene references");
			}
			r.scope = saved;
		}
	}
}

function readSubEmitters(ref r: Reader, ps: int32, index: int32, ref a: ParticleSystemAsset): void {
	const m: int32 = block(r, ps, "SubModule");
	a.subEmitters.enabled = flag(r, m, "enabled");
	const list: int32 = seqOf(r, m, "subEmitters");
	let entries: Vec<SubEmitter> = [];
	if (list >= 0 && a.subEmitters.enabled) {
		for (let i = 0; i < (r.nodes[list].kids.length as int32); i++) {
			const item: int32 = r.nodes[list].kids[i];
			const saved: string = enter(r, `subEmitters[${i}]`);
			const id: string = refOf(r, item, "emitter");
			const kind: int32 = pick(r, item, "type", 5);
			const bits: int32 = intOf(r, item, "properties");
			const probability: float32 = num(r, item, "emitProbability");
			if (bits < 0 || bits > 31) { fail(r, PrefabErrorKind.BadEnum, pathOf(r, "properties"), bits.toString()); }
			if (id != "0" && !r.failed) {
				let child: int32 = -1;
				for (let s = 0; s < (r.psIds.length as int32); s++) {
					if (r.psIds[s] == id) { child = s; }
				}
				if (child < 0) {
					fail(r, PrefabErrorKind.BadReference, pathOf(r, "emitter"), id);
				} else if (child <= index) {
					fail(r, PrefabErrorKind.SubEmitterOrder, pathOf(r, "emitter"), `child ${child} is not after parent ${index}`);
				} else {
					entries.push({
						system: child, subEmitterType: kind as SubEmitterType,
						properties: (bits as uint8) as BitSet<SubEmitterProperty>, emitProbability: probability,
					});
				}
			}
			r.scope = saved;
		}
	}
	a.subEmitters.subEmitters = entries;
}

function readRenderer(ref r: Reader, renderer: int32, ref a: ParticleSystemAsset): void {
	if (renderer < 0) {
		a.renderer.renderMode = RenderMode.None;
		return;
	}
	const m: int32 = renderer;
	r.scope = r.systemScope + ".ParticleSystemRenderer";
	const enabled: boolean = flag(r, m, "m_Enabled");
	a.renderer.renderMode = pick(r, m, "m_RenderMode", 6) as RenderMode;
	if (!enabled) { a.renderer.renderMode = RenderMode.None; }
	a.renderer.alignment = pick(r, m, "m_RenderAlignment", 5) as RenderAlignment;
	a.renderer.sortMode = pick(r, m, "m_SortMode", 7) as ParticleSortMode;
	a.renderer.sortingFudge = num(r, m, "m_SortingFudge");
	a.renderer.sortingOrder = intOf(r, m, "m_SortingOrder");
	a.renderer.minParticleSize = num(r, m, "m_MinParticleSize");
	a.renderer.maxParticleSize = num(r, m, "m_MaxParticleSize");
	a.renderer.lengthScale = num(r, m, "m_LengthScale");
	a.renderer.velocityScale = num(r, m, "m_VelocityScale");
	a.renderer.cameraVelocityScale = num(r, m, "m_CameraVelocityScale");
	a.renderer.normalDirection = num(r, m, "m_NormalDirection");
	a.renderer.pivot = vec3Of(r, m, "m_Pivot");
	a.renderer.flip = vec3Of(r, m, "m_Flip");
	a.renderer.allowRoll = flag(r, m, "m_AllowRoll");
	a.renderer.freeformStretching = flag(r, m, "m_FreeformStretching");
	a.renderer.rotateWithStretchDirection = flag(r, m, "m_RotateWithStretchDirection");
}

// Depth-first from a transform: the particle systems on its GameObject, then its children's.
function collect(ref r: Reader, transform: int32, depth: int32, ref order: Vec<int32>): void {
	if (depth > MAX_DEPTH) {
		fail(r, PrefabErrorKind.Syntax, "hierarchy", "transform hierarchy deeper than " + MAX_DEPTH.toString());
		return;
	}
	const body: int32 = r.docs[transform].body;
	const system: int32 = componentOf(r, transform, PARTICLE_SYSTEM);
	if (system >= 0) { order.push(system); }
	const children: int32 = seqOf(r, body, "m_Children");
	if (children < 0) { return; }
	for (let i = 0; i < (r.nodes[children].kids.length as int32); i++) {
		const child: int32 = docOf(r, scalarOf(r, r.nodes[children].kids[i], "fileID"));
		if (child < 0) {
			fail(r, PrefabErrorKind.BadReference, "hierarchy", "a child transform is not in the prefab");
			return;
		}
		collect(r, child, depth + 1, order);
	}
}

function assemble(ref r: Reader): ParticleEffect {
	let systems: Vec<ParticleSystemAsset> = [];
	let order: Vec<int32> = [];
	for (let d = 0; d < (r.docs.length as int32); d++) {
		const classId: int32 = r.docs[d].classId;
		if (classId == PREFAB_INSTANCE) {
			fail(r, PrefabErrorKind.Unsupported, "PrefabInstance", "a nested or variant prefab has overrides to resolve");
		}
		if (classId == RIGIDBODY || classId == RIGIDBODY_2D) { r.hasRigidbody = true; }
	}
	for (let d = 0; d < (r.docs.length as int32) && !r.failed; d++) {
		const isTransform: boolean = r.docs[d].classId == TRANSFORM || r.docs[d].classId == RECT_TRANSFORM;
		if (!isTransform || r.docs[d].body < 0) { continue; }
		r.scope = "hierarchy";
		if (refOf(r, r.docs[d].body, "m_Father") == "0") { collect(r, d, 0, order); }
	}
	if (!r.failed && order.length == 0) {
		fail(r, PrefabErrorKind.NoParticleSystem, "ParticleSystem", "the prefab has no ParticleSystem component");
	}
	for (const d of order) { r.psIds.push(r.docs[d].fileId); }
	for (let i = 0; i < (order.length as int32) && !r.failed; i++) {
		const d: int32 = order[i];
		r.systemScope = `ParticleSystem[${i}]`;
		r.scope = r.systemScope;
		const ps: int32 = r.docs[d].body;
		const version: int32 = intOf(r, ps, "serializedVersion");
		if (!r.failed && version != SERIALIZED_VERSION) {
			fail(r, PrefabErrorKind.UnsupportedVersion, pathOf(r, "serializedVersion"), version.toString());
		}
		const rendererDoc: int32 = componentOf(r, d, PARTICLE_RENDERER);
		let a: ParticleSystemAsset = ParticleSystemAsset.defaults();
		readMain(r, ps, a);
		readEmission(r, ps, a);
		readShape(r, ps, a);
		readVelocity(r, ps, a);
		readAppearance(r, ps, a);
		readCollision(r, ps, a);
		readSubEmitters(r, ps, i, a);
		readLightsTrailsData(r, ps, a);
		readRenderer(r, rendererDoc < 0 ? -1 : r.docs[rendererDoc].body, a);
		systems.push(a);
	}
	return { systems: systems };
}

export function importUnityPrefab(text: string): Result<ParticleEffect, PrefabError> {
	let r: Reader = {
		nodes: [], docs: [], lines: [], pos: 0, psIds: [], systemScope: "", scope: "",
		hasRigidbody: false, failed: false, error: { kind: PrefabErrorKind.Syntax, path: "", detail: "" },
	};
	parseStream(r, text);
	if (r.failed) { return Result.err(r.error); }
	const effect: ParticleEffect = assemble(r);
	if (r.failed) { return Result.err(r.error); }
	return Result.ok(effect);
}
