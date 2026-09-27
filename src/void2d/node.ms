import {
	Vec2,
	Color,
	Tile,
	Transform2D,
	Bounds,
	Filter,
	BlendMode,
	Smooth,
	Camera,
	ScaleMode,
	rgba,
	tile,
	identity2d,
	inverse2d,
	trs2d,
	noFilter,
} from "./types";
import { sinf, cosf } from "../math/mat4";
import { FlexStyle } from "../../../yoga/src/index";
import { BoxStyle, NO_BOX_STYLE, allocateBoxStyle, updateBoxStyle, releaseBoxStyle } from "./boxStyle";
import {
	LabelText,
	labelTexts,
	NO_LABEL_TEXT,
	allocateLabelText,
	releaseLabelText,
	releaseLabelGlyphs,
	setLabelRuns,
	setLabelShapingBreaks,
	setLabelLines,
	labelLines,
	setLabelSelection,
	setLabelCursor,
	setLabelBlinkTime,
} from "./labelText";
import { FontId } from "./font";
import { Align, TextRun, TextStyle, Truncate } from "./textLayout";
import {
	ImageStyle, NO_IMAGE_STYLE, allocateImageStyle, updateImageStyle, releaseImageStyle,
} from "./imageStyle";
import { DisplayList } from "./displayList";

export enum DrawKind { Group, Rect, Sprite, Label, Anim, Graphics, Mask, ScaleGrid, Underline, Selection }

export enum Changed {
	Local,
	Paint,
	Content,
	Text,
	Filter,
	Order,
	Tree,
}

export const NO_NODE: int32 = -1;
const NO_PAYLOAD: int32 = -1;
const LAST_GENERATION: int32 = 2147483647;
const NO_COLOR_MATRIX: float32[] = [];
const NO_FRAMES: Tile[] = [];

export struct NodeId {
	index: int32;
	generation: int32;
}

export struct NodeRef {
	scene: Scene;
	id: NodeId;
}

export struct Local2D {
	x: float32;
	y: float32;
	scaleX: float32;
	scaleY: float32;
	rotation: float32;
	pivotX: float32;
	pivotY: float32;
}

export struct Paint2D {
	color: Color;
	alpha: float32;
	colorAdd: Color;
	colorKey: Color;
	colorMatrix: float32[];
	blend: BlendMode;
	// h2d.Drawable.smooth / .tileWrap. `Smooth.Inherit` takes the scene's default, so a node
	// that says nothing follows the scene and a node that says something wins over it.
	// `tileWrap` is false by default: a Tile is a sub-rect of an atlas page, and REPEAT on a
	// sub-rect wraps a neighbour's pixels in at the seam rather than repeating the tile.
	smooth: Smooth;
	tileWrap: boolean;
}

export struct Content2D {
	w: float32;
	h: float32;
	tile: Tile;
	borderL: float32;
	borderT: float32;
	borderR: float32;
	borderB: float32;
}

export struct Order2D {
	zIndex: int32;
	visible: boolean;
	name: string;
}

export struct Layout2D {
	style: FlexStyle | null;
	lastStyle: FlexStyle | null;
	yg: Ptr<void> | null;
}

export struct AnimFrames {
	frames: Tile[];
	fps: float32;
	clock: float32;
	imageStyle: int32;
}

export interface GraphicsMesh {
	mesh: float32[];
	vertexCount: int32;
	records: float32[];
	view: uint32;
	stale: boolean;
}

export interface Scene {
	generations: Vec<int32>;
	free: Vec<int32>;
	retired: int32;
	kinds: Vec<DrawKind>;
	payloads: Vec<int32>;
	changed: Vec<BitSet<Changed>>;
	dirty: Vec<int32>;
	structureChanged: boolean;
	locals: Vec<Local2D>;
	paints: Vec<Paint2D>;
	contents: Vec<Content2D>;
	filters: Vec<Filter>;
	orders: Vec<Order2D>;
	layouts: Vec<Layout2D>;
	parents: Vec<int32>;
	children: Vec<Vec<int32>>;
	localMatrices: Vec<Transform2D>;
	worlds: Vec<Transform2D>;
	bounds: Vec<Bounds>;
	anims: Vec<AnimFrames>;
	freeAnims: Vec<int32>;
	meshes: Vec<GraphicsMesh>;
	freeMeshes: Vec<int32>;
	stack: Vec<int32>;
	root: int32;
	list: DisplayList;
	clear: Color;
	cam: Camera;
	scaleMode: ScaleMode;
	designW: float32;
	designH: float32;
	viewMat: Transform2D;
	viewInit: boolean;
	// What a node's `Smooth.Inherit` resolves to. h2d keeps this on the render context and
	// defaults it to nearest (`h2d/RenderContext.hx:52`); HEAPS.md "Do not copy from h2d"
	// rejects that default, because scaled UI and text are the common case here, not pixel
	// art. A pixel-art scene sets it false once instead of tagging every node.
	defaultSmooth: boolean;
}

function freshBits(): BitSet<Changed> {
	return (0 as BitSet<Changed>).incl(Changed.Local);
}

function defaultLocal(): Local2D {
	return { x: 0.0, y: 0.0, scaleX: 1.0, scaleY: 1.0, rotation: 0.0, pivotX: 0.0, pivotY: 0.0 };
}

function defaultPaint(): Paint2D {
	return {
		color: rgba(1.0, 1.0, 1.0, 1.0),
		alpha: 1.0,
		colorAdd: rgba(0.0, 0.0, 0.0, 0.0),
		colorKey: rgba(0.0, 0.0, 0.0, 0.0),
		colorMatrix: NO_COLOR_MATRIX,
		blend: BlendMode.Alpha,
		smooth: Smooth.Inherit,
		tileWrap: false,
	};
}

function defaultContent(): Content2D {
	return {
		w: 0.0, h: 0.0, tile: tile(0, 0.0, 0.0), borderL: 0.0, borderT: 0.0, borderR: 0.0,
		borderB: 0.0,
	};
}

function noLayout(): Layout2D {
	return { style: null, lastStyle: null, yg: null };
}

function localMatrix(l: Local2D): Transform2D {
	return trs2d(l.x, l.y, l.rotation, l.scaleX, l.scaleY) *
		trs2d(-l.pivotX, -l.pivotY, 0.0, 1.0, 1.0);
}

export function newRow(this s: Scene, kind: DrawKind, payload: int32): int32 {
	const noBounds: Bounds = { xMin: 0.0, yMin: 0.0, xMax: 0.0, yMax: 0.0 };
	const order: Order2D = { zIndex: 0, visible: true, name: "" };
	const reusable: int32 = s.free.length as int32;
	if (reusable > 0) {
		const i: int32 = s.free.pop();
		s.kinds[i] = kind;
		s.payloads[i] = payload;
		s.locals[i] = defaultLocal();
		s.paints[i] = defaultPaint();
		s.contents[i] = defaultContent();
		s.filters[i] = noFilter();
		s.orders[i] = order;
		s.layouts[i] = noLayout();
		s.parents[i] = NO_NODE;
		s.localMatrices[i] = identity2d();
		s.worlds[i] = identity2d();
		s.bounds[i] = noBounds;
		const listed: boolean = !s.changed[i].isEmpty();
		s.changed[i] = freshBits();
		if (!listed) { s.dirty.push(i); }
		return i;
	}
	const i: int32 = s.kinds.length as int32;
	s.generations.push(1);
	s.kinds.push(kind);
	s.payloads.push(payload);
	s.changed.push(freshBits());
	s.dirty.push(i);
	s.locals.push(defaultLocal());
	s.paints.push(defaultPaint());
	s.contents.push(defaultContent());
	s.filters.push(noFilter());
	s.orders.push(order);
	s.layouts.push(noLayout());
	s.parents.push(NO_NODE);
	s.children.push(new Array(0));
	s.localMatrices.push(identity2d());
	s.worlds.push(identity2d());
	s.bounds.push(noBounds);
	return i;
}

export function refOf(this s: Scene, i: int32): NodeRef {
	return { scene: s, id: { index: i, generation: s.generations[i] } };
}

export function nodeCount(this s: Scene): int32 {
	return (s.kinds.length as int32) - (s.free.length as int32) - s.retired;
}

export function isLive(this n: NodeRef): boolean {
	const i: int32 = n.id.index;
	if (i < 0 || i >= (n.scene.generations.length as int32)) { return false; }
	return n.scene.generations[i] == n.id.generation;
}

export function liveRow(this n: NodeRef, call: string): int32 {
	if (n.isLive()) { return n.id.index; }
	const i: int32 = n.id.index;
	const rows: int32 = n.scene.generations.length as int32;
	const now: int32 = i >= 0 && i < rows ? n.scene.generations[i] : 0;
	console.log(
		`void2d: ${call} on stale node ${i}: the handle has generation ${n.id.generation}, ` +
		`the row ${now}`,
	);
	unreachable;
	return i;
}

export function markChanged(this s: Scene, i: int32, what: Changed): void {
	const bits: BitSet<Changed> = s.changed[i];
	if (bits.has(what)) { return; }
	if (bits.isEmpty()) { s.dirty.push(i); }
	s.changed[i] = bits.incl(what);
}

export function clearChanges(this s: Scene): void {
	while ((s.dirty.length as int32) > 0) {
		const i: int32 = s.dirty.pop();
		s.changed[i] = 0 as BitSet<Changed>;
	}
	s.structureChanged = false;
}

function requireKind(n: NodeRef, i: int32, kind: DrawKind, call: string, what: string): void {
	const actual: DrawKind = n.scene.kinds[i];
	if (actual === kind) { return; }
	console.log(
		`void2d: ${call} asked of a ${actual.toString()} node; ` +
		`only a ${kind.toString()} has ${what}`,
	);
	unreachable;
}

export function labelRow(this n: NodeRef, call: string): int32 {
	const i: int32 = n.liveRow(call);
	requireKind(n, i, DrawKind.Label, call, "text");
	return i;
}

export function kind(this n: NodeRef): DrawKind { return n.scene.kinds[n.liveRow("kind")]; }
export function local(this n: NodeRef): Local2D { return n.scene.locals[n.liveRow("local")]; }
export function paint(this n: NodeRef): Paint2D { return n.scene.paints[n.liveRow("paint")]; }
export function content(this n: NodeRef): Content2D {
	return n.scene.contents[n.liveRow("content")];
}
export function filter(this n: NodeRef): Filter { return n.scene.filters[n.liveRow("filter")]; }
export function order(this n: NodeRef): Order2D { return n.scene.orders[n.liveRow("order")]; }

function putLocal(this s: Scene, i: int32, l: Local2D): void {
	if (s.locals[i] == l) { return; }
	s.locals[i] = l;
	s.localMatrices[i] = localMatrix(l);
	s.markChanged(i, Changed.Local);
}

export function setLocal(this n: NodeRef, l: Local2D): NodeRef {
	n.scene.putLocal(n.liveRow("setLocal"), l);
	return n;
}

function putPaint(this s: Scene, i: int32, p: Paint2D): void {
	if (s.paints[i] == p) { return; }
	s.paints[i] = p;
	s.markChanged(i, Changed.Paint);
}

export function setPaint(this n: NodeRef, p: Paint2D): NodeRef {
	n.scene.putPaint(n.liveRow("setPaint"), p);
	return n;
}

function putContent(this s: Scene, i: int32, c: Content2D): void {
	if (s.contents[i] == c) { return; }
	s.contents[i] = c;
	s.markChanged(i, Changed.Content);
}

export function setContent(this n: NodeRef, c: Content2D): NodeRef {
	n.scene.putContent(n.liveRow("setContent"), c);
	return n;
}

function putFilter(this s: Scene, i: int32, f: Filter): void {
	if (s.filters[i] == f) { return; }
	s.filters[i] = f;
	s.markChanged(i, Changed.Filter);
}

export function setFilter(this n: NodeRef, f: Filter): NodeRef {
	n.scene.putFilter(n.liveRow("setFilter"), f);
	return n;
}

function putOrder(this s: Scene, i: int32, o: Order2D): void {
	if (s.orders[i] == o) { return; }
	const restack: boolean = s.orders[i].zIndex != o.zIndex;
	s.orders[i] = o;
	s.markChanged(i, Changed.Order);
	const parent: int32 = s.parents[i];
	if (restack && parent != NO_NODE) {
		for (let k: int32 = 0; k < (s.children[parent].length as int32); k++) {
			if (s.children[parent][k] == i) { s.settle(parent, k); break; }
		}
		s.markChanged(parent, Changed.Tree);
		s.structureChanged = true;
	}
}

export function setOrder(this n: NodeRef, o: Order2D): NodeRef {
	n.scene.putOrder(n.liveRow("setOrder"), o);
	return n;
}

export function setX(this n: NodeRef, x: float32): NodeRef {
	const i: int32 = n.liveRow("setX");
	n.scene.putLocal(i, { ...n.scene.locals[i], x: x });
	return n;
}

export function setY(this n: NodeRef, y: float32): NodeRef {
	const i: int32 = n.liveRow("setY");
	n.scene.putLocal(i, { ...n.scene.locals[i], y: y });
	return n;
}

export function setPosition(this n: NodeRef, x: float32, y: float32): NodeRef {
	const i: int32 = n.liveRow("setPosition");
	n.scene.putLocal(i, { ...n.scene.locals[i], x: x, y: y });
	return n;
}

export function at(this n: NodeRef, x: float32, y: float32): NodeRef {
	const i: int32 = n.liveRow("at");
	n.scene.putLocal(i, { ...n.scene.locals[i], x: x, y: y });
	return n;
}

export function move(this n: NodeRef, dx: float32, dy: float32): NodeRef {
	const i: int32 = n.liveRow("move");
	const l: Local2D = n.scene.locals[i];
	const co: float32 = cosf(l.rotation);
	const si: float32 = sinf(l.rotation);
	n.scene.putLocal(i, { ...l, x: l.x + dx * co - dy * si, y: l.y + dx * si + dy * co });
	return n;
}

export function setRotation(this n: NodeRef, rotation: float32): NodeRef {
	const i: int32 = n.liveRow("setRotation");
	n.scene.putLocal(i, { ...n.scene.locals[i], rotation: rotation });
	return n;
}

export function rotate(this n: NodeRef, v: float32): NodeRef {
	const i: int32 = n.liveRow("rotate");
	const l: Local2D = n.scene.locals[i];
	n.scene.putLocal(i, { ...l, rotation: l.rotation + v });
	return n;
}

export function setScale(this n: NodeRef, v: float32): NodeRef {
	const i: int32 = n.liveRow("setScale");
	n.scene.putLocal(i, { ...n.scene.locals[i], scaleX: v, scaleY: v });
	return n;
}

export function scale(this n: NodeRef, v: float32): NodeRef {
	const i: int32 = n.liveRow("scale");
	const l: Local2D = n.scene.locals[i];
	n.scene.putLocal(i, { ...l, scaleX: l.scaleX * v, scaleY: l.scaleY * v });
	return n;
}

export function setScaleX(this n: NodeRef, v: float32): NodeRef {
	const i: int32 = n.liveRow("setScaleX");
	n.scene.putLocal(i, { ...n.scene.locals[i], scaleX: v });
	return n;
}

export function setScaleY(this n: NodeRef, v: float32): NodeRef {
	const i: int32 = n.liveRow("setScaleY");
	n.scene.putLocal(i, { ...n.scene.locals[i], scaleY: v });
	return n;
}

export function setPivot(this n: NodeRef, x: float32, y: float32): NodeRef {
	const i: int32 = n.liveRow("setPivot");
	n.scene.putLocal(i, { ...n.scene.locals[i], pivotX: x, pivotY: y });
	return n;
}

export function setColor(this n: NodeRef, c: Color): NodeRef {
	const i: int32 = n.liveRow("setColor");
	n.scene.putPaint(i, { ...n.scene.paints[i], color: c });
	return n;
}

export function setAlpha(this n: NodeRef, alpha: float32): NodeRef {
	const i: int32 = n.liveRow("setAlpha");
	n.scene.putPaint(i, { ...n.scene.paints[i], alpha: alpha });
	return n;
}

export function setColorAdd(this n: NodeRef, c: Color): NodeRef {
	const i: int32 = n.liveRow("setColorAdd");
	n.scene.putPaint(i, { ...n.scene.paints[i], colorAdd: c });
	return n;
}

export function setColorKey(this n: NodeRef, c: Color): NodeRef {
	const i: int32 = n.liveRow("setColorKey");
	n.scene.putPaint(i, { ...n.scene.paints[i], colorKey: c });
	return n;
}

export function setColorMatrix(this n: NodeRef, m: float32[]): NodeRef {
	const i: int32 = n.liveRow("setColorMatrix");
	n.scene.putPaint(i, { ...n.scene.paints[i], colorMatrix: m });
	return n;
}

export function setBlend(this n: NodeRef, blend: BlendMode): NodeRef {
	const i: int32 = n.liveRow("setBlend");
	n.scene.putPaint(i, { ...n.scene.paints[i], blend: blend });
	return n;
}

export function setSmooth(this n: NodeRef, smooth: Smooth): NodeRef {
	const i: int32 = n.liveRow("setSmooth");
	n.scene.putPaint(i, { ...n.scene.paints[i], smooth: smooth });
	return n;
}

export function setTileWrap(this n: NodeRef, wrap: boolean): NodeRef {
	const i: int32 = n.liveRow("setTileWrap");
	n.scene.putPaint(i, { ...n.scene.paints[i], tileWrap: wrap });
	return n;
}

export function setSize(this n: NodeRef, w: float32, h: float32): NodeRef {
	const i: int32 = n.liveRow("setSize");
	n.scene.putContent(i, { ...n.scene.contents[i], w: w, h: h });
	return n;
}

export function setTile(this n: NodeRef, t: Tile): NodeRef {
	const i: int32 = n.liveRow("setTile");
	n.scene.putContent(i, { ...n.scene.contents[i], tile: t });
	return n;
}

export function setVisible(this n: NodeRef, visible: boolean): NodeRef {
	const i: int32 = n.liveRow("setVisible");
	n.scene.putOrder(i, { ...n.scene.orders[i], visible: visible });
	return n;
}

export function setZIndex(this n: NodeRef, zIndex: int32): NodeRef {
	const i: int32 = n.liveRow("setZIndex");
	n.scene.putOrder(i, { ...n.scene.orders[i], zIndex: zIndex });
	return n;
}

export function setName(this n: NodeRef, name: string): NodeRef {
	const i: int32 = n.liveRow("setName");
	n.scene.putOrder(i, { ...n.scene.orders[i], name: name });
	return n;
}

export function setLayoutStyle(this n: NodeRef, style: FlexStyle | null): NodeRef {
	const i: int32 = n.liveRow("setLayoutStyle");
	n.scene.layouts[i] = { ...n.scene.layouts[i], style: style };
	return n;
}

export function group(this s: Scene): NodeRef {
	return s.refOf(s.newRow(DrawKind.Group, NO_PAYLOAD));
}

function sized(this s: Scene, kind: DrawKind, payload: int32, w: float32, h: float32): int32 {
	const i: int32 = s.newRow(kind, payload);
	s.contents[i] = { ...s.contents[i], w: w, h: h };
	return i;
}

export function rect(this s: Scene, w: float32, h: float32, color: Color): NodeRef {
	const i: int32 = s.sized(DrawKind.Rect, NO_BOX_STYLE, w, h);
	s.paints[i] = { ...s.paints[i], color: color };
	return s.refOf(i);
}

export function sprite(this s: Scene, t: Tile): NodeRef {
	const i: int32 = s.sized(DrawKind.Sprite, NO_IMAGE_STYLE, t.w, t.h);
	s.contents[i] = { ...s.contents[i], tile: t };
	return s.refOf(i);
}

export function label(this s: Scene, text: string, size: float32, color: Color): NodeRef {
	const payload: int32 = allocateLabelText();
	labelTexts[payload].text = text;
	labelTexts[payload].style = { ...labelTexts[payload].style, size: size };
	const i: int32 = s.newRow(DrawKind.Label, payload);
	s.paints[i] = { ...s.paints[i], color: color };
	return s.refOf(i);
}

export function anim(this s: Scene, frames: Tile[], fps: float32): NodeRef {
	const row: AnimFrames = { frames: frames, fps: fps, clock: 0.0, imageStyle: NO_IMAGE_STYLE };
	let payload: int32 = s.anims.length as int32;
	if ((s.freeAnims.length as int32) > 0) {
		payload = s.freeAnims.pop();
		s.anims[payload] = row;
	} else {
		s.anims.push(row);
	}
	const first: boolean = (frames.length as int32) > 0;
	const w: float32 = first ? frames[0].w : 0.0;
	const h: float32 = first ? frames[0].h : 0.0;
	return s.refOf(s.sized(DrawKind.Anim, payload, w, h));
}

export function graphics(this s: Scene): NodeRef {
	const row: GraphicsMesh = { mesh: [], vertexCount: 0, records: [], view: 0, stale: true };
	let payload: int32 = s.meshes.length as int32;
	if ((s.freeMeshes.length as int32) > 0) {
		payload = s.freeMeshes.pop();
		s.meshes[payload] = row;
	} else {
		s.meshes.push(row);
	}
	return s.refOf(s.newRow(DrawKind.Graphics, payload));
}

export function mask(this s: Scene, w: float32, h: float32): NodeRef {
	return s.refOf(s.sized(DrawKind.Mask, NO_PAYLOAD, w, h));
}

export function scaleGrid(
	this s: Scene,
	t: Tile,
	borderL: float32,
	borderT: float32,
	borderR: float32,
	borderB: float32,
): NodeRef {
	const i: int32 = s.newRow(DrawKind.ScaleGrid, NO_PAYLOAD);
	s.contents[i] = {
		w: t.w, h: t.h, tile: t, borderL: borderL, borderT: borderT, borderR: borderR,
		borderB: borderB,
	};
	return s.refOf(i);
}

export function underline(
	this s: Scene,
	w: float32,
	thickness: float32,
	color: Color,
	wavy: boolean,
): NodeRef {
	const i: int32 = s.newRow(DrawKind.Underline, NO_PAYLOAD);
	const h: float32 = wavy ? thickness * 3.0 : thickness;
	s.contents[i] = {
		...s.contents[i],
		w: w,
		h: h,
		borderL: thickness,
		borderT: wavy ? 1.0 : 0.0,
	};
	s.paints[i] = { ...s.paints[i], color: color };
	return s.refOf(i);
}

export function selection(
	this s: Scene,
	w: float32,
	h: float32,
	color: Color,
	prevOffsetX: float32,
	prevWidth: float32,
	nextOffsetX: float32,
	nextWidth: float32,
): NodeRef {
	const i: int32 = s.newRow(DrawKind.Selection, NO_PAYLOAD);
	s.contents[i] = {
		...s.contents[i],
		w: w,
		h: h,
		borderL: prevOffsetX,
		borderT: prevWidth,
		borderR: nextOffsetX,
		borderB: nextWidth,
	};
	s.paints[i] = { ...s.paints[i], color: color };
	return s.refOf(i);
}

export function animFrames(this n: NodeRef): AnimFrames {
	const i: int32 = n.liveRow("animFrames");
	requireKind(n, i, DrawKind.Anim, "animFrames", "frames");
	return n.scene.anims[n.scene.payloads[i]];
}

export function setBoxStyle(this n: NodeRef, style: BoxStyle): NodeRef {
	const i: int32 = n.liveRow("setBoxStyle");
	requireKind(n, i, DrawKind.Rect, "setBoxStyle", "a box style");
	const s: Scene = n.scene;
	if (s.payloads[i] == NO_BOX_STYLE) {
		s.payloads[i] = allocateBoxStyle(style);
	} else {
		updateBoxStyle(s.payloads[i], style);
	}
	s.markChanged(i, Changed.Content);
	return n;
}

export function setImageStyle(this n: NodeRef, style: ImageStyle): NodeRef {
	const i: int32 = n.liveRow("setImageStyle");
	const s: Scene = n.scene;
	const kind: DrawKind = s.kinds[i];
	if (kind !== DrawKind.Sprite && kind !== DrawKind.Anim) {
		console.log(
			`void2d: setImageStyle asked of a ${kind.toString()} node; only a Sprite or an ` +
			"Anim has an image style",
		);
		unreachable;
	}
	const current: int32 = s.imageStyleOf(i);
	let next: int32 = current;
	if (current == NO_IMAGE_STYLE) {
		next = allocateImageStyle(style);
	} else {
		updateImageStyle(current, style);
	}
	if (kind === DrawKind.Anim) {
		s.anims[s.payloads[i]].imageStyle = next;
	} else {
		s.payloads[i] = next;
	}
	s.markChanged(i, Changed.Content);
	return n;
}

export function imageStyleOf(this s: Scene, i: int32): int32 {
	match (s.kinds[i]) {
		DrawKind.Sprite => { return s.payloads[i]; },
		DrawKind.Anim => { return s.anims[s.payloads[i]].imageStyle; },
		_ => { return NO_IMAGE_STYLE; },
	}
}

function labelEntry(n: NodeRef, call: string): int32 {
	return n.scene.payloads[n.labelRow(call)];
}

function textChanged(n: NodeRef, call: string): int32 {
	const i: int32 = n.labelRow(call);
	const payload: int32 = n.scene.payloads[i];
	labelTexts[payload].stale = true;
	n.scene.markChanged(i, Changed.Text);
	return payload;
}

export function text(this n: NodeRef): string {
	return labelTexts[labelEntry(n, "text")].text;
}

export function textStyle(this n: NodeRef): TextStyle {
	return labelTexts[labelEntry(n, "textStyle")].style;
}

export function setText(this n: NodeRef, value: string): NodeRef {
	const i: int32 = n.labelRow("setText");
	const entry: LabelText = labelTexts[n.scene.payloads[i]];
	if (entry.text.equals(value)) { return n; }
	entry.text = value;
	entry.stale = true;
	n.scene.markChanged(i, Changed.Text);
	return n;
}

function putTextStyle(n: NodeRef, i: int32, style: TextStyle): void {
	const entry: LabelText = labelTexts[n.scene.payloads[i]];
	if (entry.style == style) { return; }
	entry.style = style;
	entry.stale = true;
	n.scene.markChanged(i, Changed.Text);
}

export function setTextStyle(this n: NodeRef, style: TextStyle): NodeRef {
	putTextStyle(n, n.labelRow("setTextStyle"), style);
	return n;
}

export function setFont(this n: NodeRef, font: FontId): NodeRef {
	const i: int32 = n.labelRow("setFont");
	putTextStyle(n, i, { ...labelTexts[n.scene.payloads[i]].style, font: font });
	return n;
}

export function setTextAlign(this n: NodeRef, align: Align): NodeRef {
	const i: int32 = n.labelRow("setTextAlign");
	putTextStyle(n, i, { ...labelTexts[n.scene.payloads[i]].style, align: align });
	return n;
}

export function setLetterSpacing(this n: NodeRef, spacing: float32): NodeRef {
	const i: int32 = n.labelRow("setLetterSpacing");
	putTextStyle(n, i, { ...labelTexts[n.scene.payloads[i]].style, letterSpacing: spacing });
	return n;
}

export function setLineSpacing(this n: NodeRef, spacing: float32): NodeRef {
	const i: int32 = n.labelRow("setLineSpacing");
	putTextStyle(n, i, { ...labelTexts[n.scene.payloads[i]].style, lineSpacing: spacing });
	return n;
}

export function setMaxWidth(this n: NodeRef, width: float32): NodeRef {
	const i: int32 = n.labelRow("setMaxWidth");
	putTextStyle(n, i, { ...labelTexts[n.scene.payloads[i]].style, maxWidth: width });
	return n;
}

export function setTextRuns(this n: NodeRef, runs: Span<TextRun>): NodeRef {
	setLabelRuns(textChanged(n, "setTextRuns"), runs);
	return n;
}

export function setShapingBreaks(this n: NodeRef, breaks: Span<int32>): NodeRef {
	setLabelShapingBreaks(textChanged(n, "setShapingBreaks"), breaks);
	return n;
}

export function setTruncate(this n: NodeRef, truncate: Truncate): NodeRef {
	const index: int32 = textChanged(n, "setTruncate");
	setLabelLines(index, { ...labelLines(index), truncate: truncate });
	return n;
}

export function setHangingIndent(this n: NodeRef, indent: float32): NodeRef {
	const index: int32 = textChanged(n, "setHangingIndent");
	setLabelLines(index, { ...labelLines(index), hangingIndent: indent });
	return n;
}

// h2d's TextInput.selectionRange; a length of 0 clears it.
export struct SelectionRange {
	start: int32;
	length: int32;
}

export function setSelectionRange(this n: NodeRef, range: SelectionRange, color: Color): NodeRef {
	const i: int32 = n.labelRow("setSelectionRange");
	setLabelSelection(n.scene.payloads[i], range.start, range.length, color);
	n.scene.markChanged(i, Changed.Text);
	return n;
}

// h2d's TextInput.cursorIndex; -1 hides the caret, and moving it restarts the blink.
export function setCursorIndex(this n: NodeRef, index: int32, color: Color): NodeRef {
	const i: int32 = n.labelRow("setCursorIndex");
	setLabelCursor(n.scene.payloads[i], index, color);
	n.scene.markChanged(i, Changed.Text);
	return n;
}

// h2d's TextInput.cursorBlinkTime, 0.5 s by default; 0 keeps the caret on, for a host that
// blinks it itself through setCursorIndex.
export function setCursorBlinkTime(this n: NodeRef, seconds: float32): NodeRef {
	const i: int32 = n.labelRow("setCursorBlinkTime");
	setLabelBlinkTime(n.scene.payloads[i], seconds);
	n.scene.markChanged(i, Changed.Text);
	return n;
}

export function setForceWidth(this n: NodeRef, cell: float32): NodeRef {
	const index: int32 = textChanged(n, "setForceWidth");
	setLabelLines(index, { ...labelLines(index), forceWidth: cell });
	return n;
}

function settle(this s: Scene, parent: int32, at: int32): void {
	const child: int32 = s.children[parent][at];
	const z: int32 = s.orders[child].zIndex;
	let k: int32 = at;
	while (k > 0 && s.orders[s.children[parent][k - 1]].zIndex > z) {
		s.children[parent][k] = s.children[parent][k - 1];
		k = k - 1;
	}
	const last: int32 = (s.children[parent].length as int32) - 1;
	while (k < last && s.orders[s.children[parent][k + 1]].zIndex < z) {
		s.children[parent][k] = s.children[parent][k + 1];
		k = k + 1;
	}
	s.children[parent][k] = child;
}

function detach(this s: Scene, child: int32): void {
	const parent: int32 = s.parents[child];
	if (parent == NO_NODE) { return; }
	const count: int32 = s.children[parent].length as int32;
	for (let k: int32 = 0; k < count; k++) {
		if (s.children[parent][k] == child) {
			for (let j: int32 = k; j < count - 1; j++) {
				s.children[parent][j] = s.children[parent][j + 1];
			}
			s.children[parent].pop();
			break;
		}
	}
	s.parents[child] = NO_NODE;
	s.markChanged(parent, Changed.Tree);
	s.structureChanged = true;
}

function releaseGlyphs(this s: Scene, top: int32): void {
	s.stack.push(top);
	while ((s.stack.length as int32) > 0) {
		const i: int32 = s.stack.pop();
		if (s.kinds[i] === DrawKind.Label && s.payloads[i] != NO_LABEL_TEXT) {
			releaseLabelGlyphs(s.payloads[i]);
		}
		for (let k: int32 = 0; k < (s.children[i].length as int32); k++) {
			s.stack.push(s.children[i][k]);
		}
	}
}

// Returns the CHILD, not the parent. It used to return the parent, which made
// `const n = s.add(node); n.alpha = 0.5;` - the h2d idiom, `new Bitmap(tile, parent)` with
// the handle kept - silently configure the scene root instead, and
// `s.add(a).addChild(b)` silently make `b` a sibling of `a` rather than its child. Nothing
// read the old return value, so nothing depended on the chaining it offered; what it cost was
// that the obvious reading of `add(x)` was wrong and said nothing.
export function addChild(this n: NodeRef, c: NodeRef): NodeRef {
	const count: int32 = n.scene.children[n.liveRow("addChild")].length as int32;
	return n.addChildAt(c, count);
}

export function addChildAt(this n: NodeRef, c: NodeRef, index: int32): NodeRef {
	const parent: int32 = n.liveRow("addChildAt");
	const child: int32 = c.liveRow("addChildAt");
	const s: Scene = n.scene;
	if (c.scene !== s) {
		console.log(`void2d: addChild of node ${child} from another scene under node ${parent}`);
		unreachable;
	}
	if (child == s.root) {
		console.log(`void2d: addChild of the scene root under node ${parent}`);
		unreachable;
	}
	let up: int32 = parent;
	while (up != NO_NODE) {
		if (up == child) {
			console.log(
				`void2d: addChild would put node ${child} under node ${parent}, which is inside it`,
			);
			unreachable;
		}
		up = s.parents[up];
	}
	s.detach(child);
	const count: int32 = s.children[parent].length as int32;
	const at: int32 = Math.max(0, Math.min(index, count));
	s.children[parent].push(child);
	for (let k: int32 = count; k > at; k--) {
		s.children[parent][k] = s.children[parent][k - 1];
	}
	s.children[parent][at] = child;
	s.parents[child] = parent;
	s.settle(parent, at);
	s.markChanged(parent, Changed.Tree);
	s.markChanged(child, Changed.Local);
	s.structureChanged = true;
	return c;
}

export function removeChild(this n: NodeRef, c: NodeRef): void {
	const parent: int32 = n.liveRow("removeChild");
	const child: int32 = c.liveRow("removeChild");
	if (c.scene !== n.scene || n.scene.parents[child] != parent) { return; }
	n.scene.detach(child);
	n.scene.releaseGlyphs(child);
}

export function removeChildren(this n: NodeRef): void {
	const parent: int32 = n.liveRow("removeChildren");
	const s: Scene = n.scene;
	const count: int32 = s.children[parent].length as int32;
	if (count == 0) { return; }
	for (let k: int32 = 0; k < count; k++) {
		const child: int32 = s.children[parent][k];
		s.parents[child] = NO_NODE;
		s.releaseGlyphs(child);
	}
	s.children[parent] = new Array(0);
	s.markChanged(parent, Changed.Tree);
	s.structureChanged = true;
}

export function remove(this n: NodeRef): void {
	const i: int32 = n.liveRow("remove");
	const parent: int32 = n.scene.parents[i];
	if (parent == NO_NODE) { return; }
	n.scene.refOf(parent).removeChild(n);
}

export function parent(this n: NodeRef): NodeRef | null {
	const up: int32 = n.scene.parents[n.liveRow("parent")];
	if (up == NO_NODE) { return null; }
	return n.scene.refOf(up);
}

export function numChildren(this n: NodeRef): int32 {
	return n.scene.children[n.liveRow("numChildren")].length as int32;
}

export function getChildAt(this n: NodeRef, index: int32): NodeRef {
	const i: int32 = n.liveRow("getChildAt");
	const count: int32 = n.scene.children[i].length as int32;
	if (index < 0 || index >= count) {
		console.log(`void2d: getChildAt(${index}) on node ${i}, which has ${count} children`);
		unreachable;
	}
	return n.scene.refOf(n.scene.children[i][index]);
}

export function getChildIndex(this n: NodeRef, c: NodeRef): int32 {
	const i: int32 = n.liveRow("getChildIndex");
	const child: int32 = c.liveRow("getChildIndex");
	if (c.scene !== n.scene) { return -1; }
	for (let k: int32 = 0; k < (n.scene.children[i].length as int32); k++) {
		if (n.scene.children[i][k] == child) { return k; }
	}
	return -1;
}

function absoluteMatrix(s: Scene, i: int32): Transform2D {
	let m: Transform2D = s.localMatrices[i];
	let top: int32 = i;
	while (s.parents[top] != NO_NODE) {
		top = s.parents[top];
		m = s.localMatrices[top] * m;
	}
	return top == s.root ? s.viewMat * m : m;
}

export function localToGlobal(this n: NodeRef, p: Vec2): Vec2 {
	return p * absoluteMatrix(n.scene, n.liveRow("localToGlobal"));
}

export function globalToLocal(this n: NodeRef, p: Vec2): Vec2 {
	return p * inverse2d(absoluteMatrix(n.scene, n.liveRow("globalToLocal")));
}

function releasePayload(this s: Scene, i: int32): void {
	const payload: int32 = s.payloads[i];
	match (s.kinds[i]) {
		DrawKind.Rect => {
			if (payload != NO_BOX_STYLE) { releaseBoxStyle(payload); }
		},
		DrawKind.Sprite => {
			if (payload != NO_IMAGE_STYLE) { releaseImageStyle(payload); }
		},
		DrawKind.Anim => {
			const style: int32 = s.anims[payload].imageStyle;
			if (style != NO_IMAGE_STYLE) { releaseImageStyle(style); }
			s.anims[payload].frames = NO_FRAMES;
			s.freeAnims.push(payload);
		},
		DrawKind.Label => {
			if (payload != NO_LABEL_TEXT) { releaseLabelText(payload); }
		},
		DrawKind.Graphics => {
			s.meshes[payload].mesh = [];
			s.meshes[payload].records = [];
			s.freeMeshes.push(payload);
		},
		DrawKind.Group | DrawKind.Mask | DrawKind.ScaleGrid => {},
		DrawKind.Underline | DrawKind.Selection => {},
	}
	s.payloads[i] = NO_PAYLOAD;
}

function freeRow(this s: Scene, i: int32): void {
	s.releasePayload(i);
	s.kinds[i] = DrawKind.Group;
	s.parents[i] = NO_NODE;
	s.children[i] = new Array(0);
	s.paints[i] = defaultPaint();
	s.orders[i] = { zIndex: 0, visible: true, name: "" };
	s.layouts[i] = noLayout();
	const generation: int32 = s.generations[i];
	if (generation == LAST_GENERATION) {
		s.generations[i] = 0;
		s.retired = s.retired + 1;
	} else {
		s.generations[i] = generation + 1;
		s.free.push(i);
	}
}

export function dispose(this n: NodeRef): void {
	const top: int32 = n.liveRow("dispose");
	const s: Scene = n.scene;
	if (top == s.root) {
		console.log("void2d: dispose asked of the scene root");
		unreachable;
	}
	s.detach(top);
	s.stack.push(top);
	while ((s.stack.length as int32) > 0) {
		const i: int32 = s.stack.pop();
		for (let k: int32 = 0; k < (s.children[i].length as int32); k++) {
			s.stack.push(s.children[i][k]);
		}
		s.freeRow(i);
	}
}
