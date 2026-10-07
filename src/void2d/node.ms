import {
	Vec2,
	Color,
	Tile,
	Transform2D,
	Bounds2D,
	Filter,
	Smooth,
	Camera,
	ScaleMode,
	rgba,
	whiteTile,
	TextureSource,
	WHITE_SOURCE,
	identity2d,
	inverse2d,
	trs2d,
	vec2,
	noFilter,
	emptyBounds,
} from "./types";
import { BlendMode } from "../gpu/state";
import { sinf, cosf } from "../math/mat4";
import { Mat4 } from "../math/math3d";
import { NO_COLOR_MATRIX } from "./effect";
import { FlexStyle, YGNode, freeLayoutTree } from "../../../yoga/src/index";
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
import { DrawContext2D, PaintIndex } from "./displayList";

export enum DrawKind {
	Group,
	Rect,
	Sprite,
	Label,
	Anim,
	Graphics,
	Mask,
	ScaleGrid,
	Underline,
	Selection,
	TileGroup,
}

export enum Changed {
	Local,
	Paint,
	Content,
	Text,
	Filter,
	Order,
	Tree,
	Scroll,
}

export const NO_NODE_2D: int32 = -1;
export const NO_SLOT: int32 = -1;
const NO_PAYLOAD: int32 = -1;
const LAST_GENERATION: int32 = 2147483647;
const NO_FRAMES: Tile[] = [];
export const NO_COLOR_MATRIX_ROW: int32 = -1;
export const NO_FRAME: int32 = -1;
export const ALL_TILES: int32 = 2147483647;

export struct NodeId2D {
	index: int32;
	generation: int32;
}

export struct NodeRef {
	scene: Scene2D;
	id: NodeId2D;
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
	colorMatrixRow: int32;
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
	noOverlap: boolean;
}

export enum Enclosure {
	Clip,
	Scope,
	Lanes,
}

export struct LaneFrame {
	row: int32;
	marks: int32;
	opened: PaintIndex;
	openSplit: boolean;
	targets: int32;
}

export struct Layout2D {
	style: FlexStyle | null;
	lastStyle: FlexStyle | null;
	yg: Ptr<YGNode> | null;
}

export struct Scroll2D {
	x: float32;
	y: float32;
	bounded: boolean;
	bounds: Bounds2D;
}

const NO_SCROLL: Scroll2D = {
	x: 0.0, y: 0.0, bounded: false, bounds: { xMin: 0.0, yMin: 0.0, xMax: 0.0, yMax: 0.0 },
};

export struct AnimFrames {
	frames: Tile[];
	fps: float32;
	clock: float32;
	imageStyle: int32;
	delaysMs: Vec<int32>;
	speed: float32;
	looping: boolean;
	paused: boolean;
	current: int32;
	carryMs: float32;
}

export interface GraphicsMesh {
	mesh: float32[];
	edges: float32[];
	antialias: boolean;
	fringed: boolean;
	vertexCount: int32;
	records: float32[];
	source: TextureSource;
	alphaPremultiplied: boolean;
	stale: boolean;
}

export struct TileCell {
	x: float32;
	y: float32;
	tile: Tile;
	color: Color;
	scaleX: float32;
	scaleY: float32;
	rotation: float32;
}

export struct TileGroupRow {
	first: int32;
	count: int32;
	boundsStale: boolean;
	reshaped: boolean;
	retileSerial: int32;
}

export interface Scene2D {
	closed: boolean;
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
	order: Vec<int32>;
	orderEnd: Vec<int32>;
	slots: Vec<int32>;
	orderBuilds: int32;
	localMatrices: Vec<Transform2D>;
	worlds: Vec<Transform2D>;
	bounds: Vec<Bounds2D>;
	culls: Vec<Bounds2D>;
	alphas: Vec<float32>;
	moved: Vec<boolean>;
	maskEnds: Vec<int32>;
	maskKinds: Vec<Enclosure>;
	lanes: Vec<LaneFrame>;
	laneMarks: Vec<int32>;
	repaint: Vec<int32>;
	queued: Vec<int32>;
	patchSerial: int32;
	retry: Vec<int32>;
	scanNeeded: boolean;
	patches: int32;
	splices: int32;
	repainted: int32;
	reused: int32;
	anims: Vec<AnimFrames>;
	freeAnims: Vec<int32>;
	colorMatrices: Vec<Mat4>;
	freeColorMatrices: Vec<int32>;
	meshes: Vec<GraphicsMesh>;
	freeMeshes: Vec<int32>;
	tileGroups: Vec<TileGroupRow>;
	tileCells: Vec<Vec<TileCell>>;
	tileEdits: Vec<Vec<int32>>;
	freeTileGroups: Vec<int32>;
	retile: Vec<int32>;
	retiled: int32;
	scrolls: Vec<Scroll2D>;
	freeScrolls: Vec<int32>;
	stack: Vec<int32>;
	root: int32;
	context: DrawContext2D;
	spareContext: DrawContext2D;
	clear: Color;
	cam: Camera;
	scaleMode: ScaleMode;
	designW: float32;
	designH: float32;
	viewMat: Transform2D;
	viewShift: Vec2;
	culledShift: Vec2;
	viewInit: boolean;
	// What a node's `Smooth.Inherit` resolves to. h2d keeps this on the render context and
	// defaults it to nearest (`h2d/RenderContext.hx:52`); HEAPS.md "Do not copy from h2d"
	// rejects that default, because scaled UI and text are the common case here, not pixel
	// art. A pixel-art scene sets it false once instead of tagging every node.
	defaultSmooth: boolean;
}

export function frameIndex(this a: AnimFrames): int32 {
	if ((a.frames.length as int32) == 0) { return NO_FRAME; }
	return a.current;
}

export function frameDelayMs(this a: AnimFrames, index: int32): float32 {
	if ((a.delaysMs.length as int32) > 0) { return a.delaysMs[index] as float32; }
	if (a.fps <= 0.0) { return 0.0; }
	return 1000.0 / a.fps;
}

function cycleMs(a: AnimFrames): float32 {
	let total: float32 = 0.0;
	for (let i: int32 = 0; i < (a.frames.length as int32); i++) {
		total = total + a.frameDelayMs(i);
	}
	return total;
}

export function advanceAnim(this s: Scene2D, payload: int32, dt: float32): void {
	if (dt < 0.0) {
		console.log(`void2d: an Anim was advanced by ${dt} s; time only moves forward`);
		unreachable;
	}
	const len: int32 = s.anims[payload].frames.length as int32;
	if (s.anims[payload].paused || len == 0) { return; }
	const step: float32 = dt * s.anims[payload].speed;
	s.anims[payload].clock = s.anims[payload].clock + step;
	const total: float32 = cycleMs(s.anims[payload]);
	if (total <= 0.0) { return; }
	const looping: boolean = s.anims[payload].looping;
	let wide: float64 = (s.anims[payload].carryMs as float64) + (step as float64) * 1000.0;
	if (looping) { wide = wide - Math.floor(wide / (total as float64)) * (total as float64); }
	let carry: float32 = wide as float32;
	let current: int32 = s.anims[payload].current;
	let delay: float32 = s.anims[payload].frameDelayMs(current);
	while (carry >= delay) {
		carry = carry - delay;
		if (current + 1 < len) {
			current = current + 1;
		} else if (looping) {
			current = 0;
		} else {
			carry = 0.0;
			break;
		}
		delay = s.anims[payload].frameDelayMs(current);
	}
	s.anims[payload].current = current;
	s.anims[payload].carryMs = carry;
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
		colorMatrixRow: NO_COLOR_MATRIX_ROW,
		blend: BlendMode.Alpha,
		smooth: Smooth.Inherit,
		tileWrap: false,
	};
}

function defaultContent(): Content2D {
	return {
		w: 0.0, h: 0.0, tile: whiteTile(0.0, 0.0), borderL: 0.0, borderT: 0.0, borderR: 0.0,
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

export function newRow(this s: Scene2D, kind: DrawKind, payload: int32): int32 {
	s.requireOpen("creating a node");
	const noBounds: Bounds2D = { xMin: 0.0, yMin: 0.0, xMax: 0.0, yMax: 0.0 };
	const order: Order2D = { zIndex: 0, visible: true, name: "", noOverlap: false };
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
		s.parents[i] = NO_NODE_2D;
		s.localMatrices[i] = identity2d();
		s.worlds[i] = identity2d();
		s.bounds[i] = noBounds;
		s.culls[i] = emptyBounds();
		s.slots[i] = NO_SLOT;
		s.alphas[i] = 1.0;
		s.moved[i] = false;
		s.queued[i] = 0;
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
	s.parents.push(NO_NODE_2D);
	s.children.push(new Array(0));
	s.localMatrices.push(identity2d());
	s.worlds.push(identity2d());
	s.bounds.push(noBounds);
	s.culls.push(emptyBounds());
	s.slots.push(NO_SLOT);
	s.alphas.push(1.0);
	s.moved.push(false);
	s.queued.push(0);
	return i;
}

export function refOf(this s: Scene2D, i: int32): NodeRef {
	return { scene: s, id: { index: i, generation: s.generations[i] } };
}

export function requireOpen(this s: Scene2D, call: string): void {
	if (!s.closed) { return; }
	console.log(`void2d: ${call} on a closed scene`);
	unreachable;
}

export function nodeCount(this s: Scene2D): int32 {
	return (s.kinds.length as int32) - (s.free.length as int32) - s.retired;
}

export function isLive(this n: NodeRef): boolean {
	if (n.scene.closed) { return false; }
	const i: int32 = n.id.index;
	if (i < 0 || i >= (n.scene.generations.length as int32)) { return false; }
	return n.scene.generations[i] == n.id.generation;
}

export function liveRow(this n: NodeRef, call: string): int32 {
	if (n.isLive()) { return n.id.index; }
	if (n.scene.closed) {
		console.log(`void2d: ${call} on node ${n.id.index} of a closed scene`);
		unreachable;
	}
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

export function markChanged(this s: Scene2D, i: int32, what: Changed): void {
	const bits: BitSet<Changed> = s.changed[i];
	if (bits.has(what)) { return; }
	if (bits.isEmpty()) { s.dirty.push(i); }
	s.changed[i] = bits.incl(what);
}

export function retryRefused(this s: Scene2D): void {
	while ((s.retry.length as int32) > 0) { s.markChanged(s.retry.pop(), Changed.Text); }
}

export function refreshOrder(this s: Scene2D): void {
	if (!s.structureChanged) { return; }
	for (let p: int32 = 0; p < (s.order.length as int32); p++) {
		s.slots[s.order[p]] = NO_SLOT;
	}
	while ((s.order.length as int32) > 0) { s.order.pop(); }
	while ((s.orderEnd.length as int32) > 0) { s.orderEnd.pop(); }
	s.stack.push(s.root);
	while ((s.stack.length as int32) > 0) {
		const i: int32 = s.stack.pop();
		s.slots[i] = s.order.length as int32;
		s.order.push(i);
		s.orderEnd.push(0);
		for (let k: int32 = (s.children[i].length as int32) - 1; k >= 0; k--) {
			s.stack.push(s.children[i][k]);
		}
	}
	for (let p: int32 = (s.order.length as int32) - 1; p >= 0; p--) {
		const i: int32 = s.order[p];
		const count: int32 = s.children[i].length as int32;
		s.orderEnd[p] = count > 0 ? s.orderEnd[s.slots[s.children[i][count - 1]]] : p + 1;
	}
	s.orderBuilds = s.orderBuilds + 1;
}

export function clearChanges(this s: Scene2D): void {
	while ((s.dirty.length as int32) > 0) {
		const i: int32 = s.dirty.pop();
		s.changed[i] = 0 as BitSet<Changed>;
		if (s.kinds[i] === DrawKind.TileGroup) { s.settleTiles(i); }
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

function putLocal(this s: Scene2D, i: int32, l: Local2D): void {
	if (s.locals[i] == l) { return; }
	s.locals[i] = l;
	s.localMatrices[i] = localMatrix(l);
	s.markChanged(i, Changed.Local);
}

export function setLocal(this n: NodeRef, l: Local2D): NodeRef {
	n.scene.putLocal(n.liveRow("setLocal"), l);
	return n;
}

function stopOnMovedColorMatrix(): void {
	console.log("void2d: setPaint cannot move a node's color matrix row; " +
		"setColorMatrix sets the matrix");
	unreachable;
}

function putPaint(this s: Scene2D, i: int32, p: Paint2D): void {
	if (s.paints[i] == p) { return; }
	if (p.colorMatrixRow != s.paints[i].colorMatrixRow) { stopOnMovedColorMatrix(); }
	s.paints[i] = p;
	s.markChanged(i, Changed.Paint);
}

export function setPaint(this n: NodeRef, p: Paint2D): NodeRef {
	n.scene.putPaint(n.liveRow("setPaint"), p);
	return n;
}

function putContent(this s: Scene2D, i: int32, c: Content2D): void {
	if (s.contents[i] == c) { return; }
	s.contents[i] = c;
	s.markChanged(i, Changed.Content);
}

export function setContent(this n: NodeRef, c: Content2D): NodeRef {
	n.scene.putContent(n.liveRow("setContent"), c);
	return n;
}

function putFilter(this s: Scene2D, i: int32, f: Filter): void {
	if (s.filters[i] == f) { return; }
	s.filters[i] = f;
	s.markChanged(i, Changed.Filter);
}

export function setFilter(this n: NodeRef, f: Filter): NodeRef {
	n.scene.putFilter(n.liveRow("setFilter"), f);
	return n;
}

function putOrder(this s: Scene2D, i: int32, o: Order2D): void {
	if (s.orders[i] == o) { return; }
	const restack: boolean = s.orders[i].zIndex != o.zIndex;
	s.orders[i] = o;
	s.markChanged(i, Changed.Order);
	const parent: int32 = s.parents[i];
	if (restack && parent != NO_NODE_2D) {
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

function claimColorMatrix(this s: Scene2D, m: Mat4): int32 {
	const free: int32 = s.freeColorMatrices.length as int32;
	if (free > 0) {
		const row: int32 = s.freeColorMatrices[free - 1];
		s.freeColorMatrices.pop();
		s.colorMatrices[row] = m;
		return row;
	}
	s.colorMatrices.push(m);
	return (s.colorMatrices.length as int32) - 1;
}

export function setColorMatrix(this n: NodeRef, m: Mat4): NodeRef {
	const i: int32 = n.liveRow("setColorMatrix");
	const s: Scene2D = n.scene;
	const row: int32 = s.paints[i].colorMatrixRow;
	if (m == NO_COLOR_MATRIX) {
		if (row == NO_COLOR_MATRIX_ROW) { return n; }
		s.freeColorMatrices.push(row);
		s.paints[i] = { ...s.paints[i], colorMatrixRow: NO_COLOR_MATRIX_ROW };
	} else if (row == NO_COLOR_MATRIX_ROW) {
		s.paints[i] = { ...s.paints[i], colorMatrixRow: s.claimColorMatrix(m) };
	} else {
		if (s.colorMatrices[row] == m) { return n; }
		s.colorMatrices[row] = m;
	}
	s.markChanged(i, Changed.Paint);
	return n;
}

export function colorMatrix(this n: NodeRef): Mat4 {
	return n.scene.colorMatrixOf(n.liveRow("colorMatrix"));
}

export function colorMatrixOf(this s: Scene2D, i: int32): Mat4 {
	const row: int32 = s.paints[i].colorMatrixRow;
	return row == NO_COLOR_MATRIX_ROW ? NO_COLOR_MATRIX : s.colorMatrices[row];
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

export function setNoOverlap(this n: NodeRef, promise: boolean): NodeRef {
	const i: int32 = n.liveRow("setNoOverlap");
	n.scene.putOrder(i, { ...n.scene.orders[i], noOverlap: promise });
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

export function layoutGetChildren(this n: NodeRef): NodeRef[] {
	const i: int32 = n.liveRow("layoutGetChildren");
	const out: NodeRef[] = [];
	for (let k: int32 = 0; k < (n.scene.children[i].length as int32); k++) {
		out.push(n.scene.refOf(n.scene.children[i][k]));
	}
	return out;
}

export function layoutGetStyle(this n: NodeRef): FlexStyle | null {
	return n.scene.layouts[n.liveRow("layoutGetStyle")].style;
}

export function layoutGetLastStyle(this n: NodeRef): FlexStyle | null {
	return n.scene.layouts[n.liveRow("layoutGetLastStyle")].lastStyle;
}

export function layoutSetLastStyle(this n: NodeRef, s: FlexStyle | null): void {
	const i: int32 = n.liveRow("layoutSetLastStyle");
	n.scene.layouts[i] = { ...n.scene.layouts[i], lastStyle: s };
}

export function layoutGetYg(this n: NodeRef): Ptr<YGNode> | null {
	return n.scene.layouts[n.liveRow("layoutGetYg")].yg;
}

export function layoutSetYg(this n: NodeRef, yg: Ptr<YGNode> | null): void {
	const i: int32 = n.liveRow("layoutSetYg");
	n.scene.layouts[i] = { ...n.scene.layouts[i], yg: yg };
}

export function layoutSetFrame(
	this n: NodeRef,
	x: float32,
	y: float32,
	w: float32,
	h: float32,
): void {
	n.setPosition(x, y).setSize(w, h);
}

export function group(this s: Scene2D): NodeRef {
	return s.refOf(s.newRow(DrawKind.Group, NO_PAYLOAD));
}

function sized(this s: Scene2D, kind: DrawKind, payload: int32, w: float32, h: float32): int32 {
	const i: int32 = s.newRow(kind, payload);
	s.contents[i] = { ...s.contents[i], w: w, h: h };
	return i;
}

export function rect(this s: Scene2D, w: float32, h: float32, color: Color): NodeRef {
	const i: int32 = s.sized(DrawKind.Rect, NO_BOX_STYLE, w, h);
	s.paints[i] = { ...s.paints[i], color: color };
	return s.refOf(i);
}

export function sprite(this s: Scene2D, t: Tile): NodeRef {
	const i: int32 = s.sized(DrawKind.Sprite, NO_IMAGE_STYLE, t.w, t.h);
	s.contents[i] = { ...s.contents[i], tile: t };
	return s.refOf(i);
}

export function label(this s: Scene2D, text: string, size: float32, color: Color): NodeRef {
	const payload: int32 = allocateLabelText();
	labelTexts[payload].text = text;
	labelTexts[payload].style = { ...labelTexts[payload].style, size: size };
	const i: int32 = s.newRow(DrawKind.Label, payload);
	s.paints[i] = { ...s.paints[i], color: color };
	return s.refOf(i);
}

export function anim(this s: Scene2D, frames: Tile[], fps: float32): NodeRef {
	const row: AnimFrames = {
		frames: frames, fps: fps, clock: 0.0, imageStyle: NO_IMAGE_STYLE,
		delaysMs: [], speed: 1.0, looping: true, paused: false, current: 0, carryMs: 0.0,
	};
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

export function graphics(this s: Scene2D): NodeRef {
	const row: GraphicsMesh = {
		mesh: [], edges: [], antialias: true, fringed: false, vertexCount: 0, records: [],
		source: WHITE_SOURCE, alphaPremultiplied: false, stale: true,
	};
	let payload: int32 = s.meshes.length as int32;
	if ((s.freeMeshes.length as int32) > 0) {
		payload = s.freeMeshes.pop();
		s.meshes[payload] = row;
	} else {
		s.meshes.push(row);
	}
	return s.refOf(s.newRow(DrawKind.Graphics, payload));
}

export function mask(this s: Scene2D, w: float32, h: float32): NodeRef {
	return s.refOf(s.sized(DrawKind.Mask, NO_PAYLOAD, w, h));
}

export function tileGroup(this s: Scene2D): NodeRef {
	const row: TileGroupRow = {
		first: 0, count: ALL_TILES, boundsStale: false, reshaped: true, retileSerial: -1,
	};
	let payload: int32 = s.tileGroups.length as int32;
	if ((s.freeTileGroups.length as int32) > 0) {
		payload = s.freeTileGroups.pop();
		s.tileGroups[payload] = row;
	} else {
		s.tileGroups.push(row);
		s.tileCells.push(new Array(0));
		s.tileEdits.push(new Array(0));
	}
	return s.refOf(s.newRow(DrawKind.TileGroup, payload));
}

function reshape(this s: Scene2D, i: int32): void {
	const p: int32 = s.payloads[i];
	s.tileGroups[p].boundsStale = true;
	s.tileGroups[p].reshaped = true;
	s.markChanged(i, Changed.Content);
}

function sameShape(a: TileCell, b: TileCell): boolean {
	return a.x == b.x && a.y == b.y && a.scaleX == b.scaleX && a.scaleY == b.scaleY &&
		a.rotation == b.rotation && a.tile.source.sameAs(b.tile.source) && a.tile.w == b.tile.w &&
		a.tile.h == b.tile.h && a.tile.dx == b.tile.dx && a.tile.dy == b.tile.dy;
}

export function settleTiles(this s: Scene2D, i: int32): void {
	const p: int32 = s.payloads[i];
	s.tileGroups[p].reshaped = false;
	while ((s.tileEdits[p].length as int32) > 0) { s.tileEdits[p].pop(); }
}

function tileGroupRow(n: NodeRef, call: string): int32 {
	const i: int32 = n.liveRow(call);
	requireKind(n, i, DrawKind.TileGroup, call, "tiles");
	return i;
}

function putTiles(this s: Scene2D, i: int32, cells: TileCell[]): void {
	const p: int32 = s.payloads[i];
	const have: int32 = s.tileCells[p].length as int32;
	const want: int32 = cells.length as int32;
	let same: boolean = have == want;
	for (let k: int32 = 0; k < want && same; k++) { same = s.tileCells[p][k] == cells[k]; }
	if (same) { return; }
	for (let k: int32 = 0; k < want; k++) {
		if (k < have) {
			s.tileCells[p][k] = cells[k];
		} else {
			s.tileCells[p].push(cells[k]);
		}
	}
	while ((s.tileCells[p].length as int32) > want) { s.tileCells[p].pop(); }
	s.reshape(i);
}

export function setTiles(this n: NodeRef, cells: TileCell[]): NodeRef {
	n.scene.putTiles(tileGroupRow(n, "setTiles"), cells);
	return n;
}

function pushTiles(this s: Scene2D, i: int32, cells: TileCell[]): void {
	if ((cells.length as int32) == 0) { return; }
	const p: int32 = s.payloads[i];
	for (let k: int32 = 0; k < (cells.length as int32); k++) { s.tileCells[p].push(cells[k]); }
	s.reshape(i);
}

export function appendTiles(this n: NodeRef, cells: TileCell[]): NodeRef {
	n.scene.pushTiles(tileGroupRow(n, "appendTiles"), cells);
	return n;
}

function putTile(this s: Scene2D, i: int32, index: int32, cell: TileCell): void {
	const p: int32 = s.payloads[i];
	const count: int32 = s.tileCells[p].length as int32;
	if (index < 0 || index >= count) {
		console.log(`void2d: setTile(${index}) on tile group ${i}, which holds ${count} tiles`);
		unreachable;
	}
	if (s.tileCells[p][index] == cell) { return; }
	const kept: boolean = sameShape(s.tileCells[p][index], cell);
	s.tileCells[p][index] = cell;
	const edits: int32 = s.tileEdits[p].length as int32;
	if (!kept || s.tileGroups[p].reshaped || edits >= Math.max(16, count / 8)) {
		s.reshape(i);
		return;
	}
	s.tileEdits[p].push(index);
	s.markChanged(i, Changed.Content);
}

export function setTile(this n: NodeRef, index: int32, cell: TileCell): NodeRef {
	n.scene.putTile(tileGroupRow(n, "setTile"), index, cell);
	return n;
}

export function setRange(this n: NodeRef, first: int32, count: int32): NodeRef {
	const i: int32 = tileGroupRow(n, "setRange");
	if (first < 0 || count < 0) {
		console.log(
			`void2d: setRange(${first}, ${count}) on tile group ${i}: a range starts at tile 0 ` +
			"or later and holds 0 tiles or more",
		);
		unreachable;
	}
	const s: Scene2D = n.scene;
	const p: int32 = s.payloads[i];
	const row: TileGroupRow = s.tileGroups[p];
	if (row.first == first && row.count == count) { return n; }
	s.tileGroups[p] = { ...row, first: first, count: count, reshaped: true };
	s.markChanged(i, Changed.Content);
	return n;
}

export function count(this n: NodeRef): int32 {
	const i: int32 = tileGroupRow(n, "count");
	return n.scene.tileCells[n.scene.payloads[i]].length as int32;
}

export function clear(this n: NodeRef): NodeRef {
	const i: int32 = n.liveRow("clear");
	const s: Scene2D = n.scene;
	const kind: DrawKind = s.kinds[i];
	if (kind !== DrawKind.Graphics && kind !== DrawKind.TileGroup) {
		console.log(
			`void2d: clear asked of a ${kind.toString()} node; only a Graphics or a TileGroup ` +
			"can be cleared",
		);
		unreachable;
	}
	const p: int32 = s.payloads[i];
	if (kind === DrawKind.TileGroup) {
		if ((s.tileCells[p].length as int32) == 0) { return n; }
		s.tileCells[p] = new Array(0);
		s.reshape(i);
		return n;
	}
	s.meshes[p].mesh = [];
	s.meshes[p].edges = [];
	s.meshes[p].fringed = false;
	s.meshes[p].records = [];
	s.meshes[p].source = WHITE_SOURCE;
	s.meshes[p].alphaPremultiplied = false;
	s.meshes[p].stale = true;
	s.markChanged(i, Changed.Content);
	return n;
}

export function scaleGrid(
	this s: Scene2D,
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
	this s: Scene2D,
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
	this s: Scene2D,
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

export function scroll(this n: NodeRef): Scroll2D {
	const i: int32 = n.liveRow("scroll");
	requireKind(n, i, DrawKind.Mask, "scroll", "a scroll");
	const payload: int32 = n.scene.payloads[i];
	return payload == NO_PAYLOAD ? NO_SCROLL : n.scene.scrolls[payload];
}

function scrollRow(s: Scene2D, i: int32): int32 {
	if (s.payloads[i] != NO_PAYLOAD) { return s.payloads[i]; }
	let row: int32 = s.scrolls.length as int32;
	if ((s.freeScrolls.length as int32) > 0) {
		row = s.freeScrolls.pop();
		s.scrolls[row] = NO_SCROLL;
	} else {
		s.scrolls.push(NO_SCROLL);
	}
	s.payloads[i] = row;
	return row;
}

function clampScroll(v: float32, min: float32, max: float32): float32 {
	if (v < min) { return min; }
	if (v > max) { return max; }
	return v;
}

function putScroll(n: NodeRef, call: string, x: float32, y: float32): void {
	const i: int32 = n.liveRow(call);
	requireKind(n, i, DrawKind.Mask, call, "a scroll");
	const s: Scene2D = n.scene;
	const fresh: boolean = s.payloads[i] == NO_PAYLOAD;
	const row: int32 = scrollRow(s, i);
	if (fresh) { s.markChanged(i, Changed.Local); }
	const now: Scroll2D = s.scrolls[row];
	let nx: float32 = x;
	let ny: float32 = y;
	if (now.bounded) {
		nx = clampScroll(x, now.bounds.xMin, now.bounds.xMax - s.contents[i].w);
		ny = clampScroll(y, now.bounds.yMin, now.bounds.yMax - s.contents[i].h);
	}
	if (nx == now.x && ny == now.y) { return; }
	s.scrolls[row] = { ...now, x: nx, y: ny };
	s.markChanged(i, s.scrollScope(i) ? Changed.Scroll : Changed.Local);
}

export function scrollScope(this s: Scene2D, i: int32): boolean {
	if (s.kinds[i] !== DrawKind.Mask || s.payloads[i] == NO_PAYLOAD) { return false; }
	let up: int32 = i;
	while (up != NO_NODE_2D) {
		if (s.kinds[up] === DrawKind.Mask && (s.worlds[up].b != 0.0 || s.worlds[up].c != 0.0)) {
			return false;
		}
		up = s.parents[up];
	}
	return true;
}

export function setScrollX(this n: NodeRef, x: float32): NodeRef {
	putScroll(n, "setScrollX", x, n.scroll().y);
	return n;
}

export function setScrollY(this n: NodeRef, y: float32): NodeRef {
	putScroll(n, "setScrollY", n.scroll().x, y);
	return n;
}

export function scrollTo(this n: NodeRef, x: float32, y: float32): NodeRef {
	putScroll(n, "scrollTo", x, y);
	return n;
}

export function scrollBy(this n: NodeRef, dx: float32, dy: float32): NodeRef {
	const now: Scroll2D = n.scroll();
	putScroll(n, "scrollBy", now.x + dx, now.y + dy);
	return n;
}

export function setScrollBounds(this n: NodeRef, bounds: Bounds2D | null): NodeRef {
	const i: int32 = n.liveRow("setScrollBounds");
	requireKind(n, i, DrawKind.Mask, "setScrollBounds", "a scroll");
	const fresh: boolean = n.scene.payloads[i] == NO_PAYLOAD;
	const row: int32 = scrollRow(n.scene, i);
	if (fresh) { n.scene.markChanged(i, Changed.Local); }
	const now: Scroll2D = n.scene.scrolls[row];
	if (bounds === null) {
		n.scene.scrolls[row] = { ...now, bounded: false };
	} else {
		n.scene.scrolls[row] = { ...now, bounded: true, bounds: bounds as Bounds2D };
	}
	return n;
}

export function childWorld(this s: Scene2D, up: int32): Transform2D {
	if (s.kinds[up] !== DrawKind.Mask || s.payloads[up] == NO_PAYLOAD) { return s.worlds[up]; }
	if (s.scrollScope(up)) { return s.worlds[up]; }
	const sc: Scroll2D = s.scrolls[s.payloads[up]];
	return s.worlds[up] * trs2d(-sc.x, -sc.y, 0.0, 1.0, 1.0);
}

export function animFrames(this n: NodeRef): AnimFrames {
	const i: int32 = n.liveRow("animFrames");
	requireKind(n, i, DrawKind.Anim, "animFrames", "frames");
	return n.scene.anims[n.scene.payloads[i]];
}

export function setFrame(this n: NodeRef, index: int32): NodeRef {
	const i: int32 = n.liveRow("setFrame");
	requireKind(n, i, DrawKind.Anim, "setFrame", "frames");
	const s: Scene2D = n.scene;
	const row: AnimFrames = s.anims[s.payloads[i]];
	const len: int32 = row.frames.length as int32;
	if (index < 0 || index >= len) {
		console.log(`void2d: setFrame(${index}) on an Anim of ${len} frames`);
		unreachable;
	}
	const shown: int32 = row.frameIndex();
	s.anims[s.payloads[i]] = { ...row, current: index, carryMs: 0.0 };
	if (index != shown) { s.markChanged(i, Changed.Content); }
	return n;
}

export function setFrameDelays(this n: NodeRef, delaysMs: Vec<int32>): NodeRef {
	const i: int32 = n.liveRow("setFrameDelays");
	requireKind(n, i, DrawKind.Anim, "setFrameDelays", "frames");
	const s: Scene2D = n.scene;
	const row: AnimFrames = s.anims[s.payloads[i]];
	const count: int32 = delaysMs.length as int32;
	const len: int32 = row.frames.length as int32;
	if (count != 0 && count != len) {
		console.log(`void2d: setFrameDelays got ${count} delays for an Anim of ${len} frames`);
		unreachable;
	}
	for (let k: int32 = 0; k < count; k++) {
		if (delaysMs[k] <= 0) {
			console.log(`void2d: setFrameDelays frame ${k} has a delay of ${delaysMs[k]} ms`);
			unreachable;
		}
	}
	s.anims[s.payloads[i]] = { ...row, delaysMs: delaysMs, carryMs: 0.0 };
	return n;
}

export function setSpeed(this n: NodeRef, speed: float32): NodeRef {
	const i: int32 = n.liveRow("setSpeed");
	requireKind(n, i, DrawKind.Anim, "setSpeed", "frames");
	if (speed < 0.0) {
		console.log(`void2d: setSpeed(${speed}) on an Anim; a speed is 0 or more`);
		unreachable;
	}
	const s: Scene2D = n.scene;
	s.anims[s.payloads[i]] = { ...s.anims[s.payloads[i]], speed: speed };
	return n;
}

export function setLooping(this n: NodeRef, looping: boolean): NodeRef {
	const i: int32 = n.liveRow("setLooping");
	requireKind(n, i, DrawKind.Anim, "setLooping", "frames");
	const s: Scene2D = n.scene;
	s.anims[s.payloads[i]] = { ...s.anims[s.payloads[i]], looping: looping };
	return n;
}

export function setPaused(this n: NodeRef, paused: boolean): NodeRef {
	const i: int32 = n.liveRow("setPaused");
	requireKind(n, i, DrawKind.Anim, "setPaused", "frames");
	const s: Scene2D = n.scene;
	s.anims[s.payloads[i]] = { ...s.anims[s.payloads[i]], paused: paused };
	return n;
}

export function setBoxStyle(this n: NodeRef, style: BoxStyle): NodeRef {
	const i: int32 = n.liveRow("setBoxStyle");
	takePaintable(n, i, "setBoxStyle");
	const s: Scene2D = n.scene;
	if (s.payloads[i] == NO_BOX_STYLE) {
		s.payloads[i] = allocateBoxStyle(style);
	} else {
		updateBoxStyle(s.payloads[i], style);
	}
	s.markChanged(i, Changed.Content);
	return n;
}

function stopOnUnpaintable(call: string, actual: DrawKind): void {
	console.log(`void2d: ${call} asked of a ${actual.toString()} node; ` +
		"only a Group or a Rect can take a background");
	unreachable;
}

function takePaintable(n: NodeRef, i: int32, call: string): void {
	const actual: DrawKind = n.scene.kinds[i];
	if (actual === DrawKind.Rect) { return; }
	if (actual !== DrawKind.Group) { stopOnUnpaintable(call, actual); }
	n.scene.kinds[i] = DrawKind.Rect;
	n.scene.putPaint(i, { ...n.scene.paints[i], color: rgba(0.0, 0.0, 0.0, 0.0) });
	n.scene.markChanged(i, Changed.Content);
}

export function setBackground(this n: NodeRef, c: Color): NodeRef {
	const i: int32 = n.liveRow("setBackground");
	takePaintable(n, i, "setBackground");
	n.scene.putPaint(i, { ...n.scene.paints[i], color: c });
	return n;
}

export function clearBackground(this n: NodeRef): NodeRef {
	const i: int32 = n.liveRow("clearBackground");
	const s: Scene2D = n.scene;
	const actual: DrawKind = s.kinds[i];
	if (actual !== DrawKind.Rect && actual !== DrawKind.Group) {
		stopOnUnpaintable("clearBackground", actual);
	}
	if (actual === DrawKind.Rect) {
		const payload: int32 = s.payloads[i];
		if (payload != NO_BOX_STYLE) {
			releaseBoxStyle(payload);
			s.payloads[i] = NO_PAYLOAD;
		}
		s.kinds[i] = DrawKind.Group;
		s.putPaint(i, { ...s.paints[i], color: rgba(0.0, 0.0, 0.0, 0.0) });
	}
	s.markChanged(i, Changed.Content);
	return n;
}

export function setImageStyle(this n: NodeRef, style: ImageStyle): NodeRef {
	const i: int32 = n.liveRow("setImageStyle");
	const s: Scene2D = n.scene;
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

export function imageStyleOf(this s: Scene2D, i: int32): int32 {
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

export function setTextRuns(this n: NodeRef, runs: Readonly<Span<TextRun>>): NodeRef {
	setLabelRuns(textChanged(n, "setTextRuns"), runs);
	return n;
}

export function setShapingBreaks(this n: NodeRef, breaks: Readonly<Span<int32>>): NodeRef {
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

function settle(this s: Scene2D, parent: int32, at: int32): void {
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

function detach(this s: Scene2D, child: int32): void {
	const parent: int32 = s.parents[child];
	if (parent == NO_NODE_2D) { return; }
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
	s.parents[child] = NO_NODE_2D;
	s.markChanged(parent, Changed.Tree);
	s.structureChanged = true;
}

function releaseGlyphs(this s: Scene2D, top: int32): void {
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
	const s: Scene2D = n.scene;
	if (c.scene !== s) {
		console.log(`void2d: addChild of node ${child} from another scene under node ${parent}`);
		unreachable;
	}
	if (child == s.root) {
		console.log(`void2d: addChild of the scene root under node ${parent}`);
		unreachable;
	}
	let up: int32 = parent;
	while (up != NO_NODE_2D) {
		if (up == child) {
			console.log(
				`void2d: addChild would put node ${child} under node ${parent}, which is inside it`,
			);
			unreachable;
		}
		up = s.parents[up];
	}
	const from: int32 = s.parents[child];
	if (from != NO_NODE_2D && from != parent) { s.releaseLayout(child); }
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

function releaseLayout(this s: Scene2D, top: int32): void {
	if (s.layouts[top].yg === null) { return; }
	freeLayoutTree(s.refOf(top));
}

export function removeChild(this n: NodeRef, c: NodeRef): void {
	const parent: int32 = n.liveRow("removeChild");
	const child: int32 = c.liveRow("removeChild");
	if (c.scene !== n.scene || n.scene.parents[child] != parent) { return; }
	n.scene.detach(child);
	n.scene.releaseGlyphs(child);
	n.scene.releaseLayout(child);
}

export function removeChildren(this n: NodeRef): void {
	const parent: int32 = n.liveRow("removeChildren");
	const s: Scene2D = n.scene;
	const count: int32 = s.children[parent].length as int32;
	if (count == 0) { return; }
	for (let k: int32 = 0; k < count; k++) {
		const child: int32 = s.children[parent][k];
		s.parents[child] = NO_NODE_2D;
		s.releaseGlyphs(child);
		s.releaseLayout(child);
	}
	s.children[parent] = new Array(0);
	s.markChanged(parent, Changed.Tree);
	s.structureChanged = true;
}

export function remove(this n: NodeRef): void {
	const i: int32 = n.liveRow("remove");
	const parent: int32 = n.scene.parents[i];
	if (parent == NO_NODE_2D) { return; }
	n.scene.refOf(parent).removeChild(n);
}

export function parent(this n: NodeRef): NodeRef | null {
	const up: int32 = n.scene.parents[n.liveRow("parent")];
	if (up == NO_NODE_2D) { return null; }
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

export function ownScroll(this s: Scene2D, i: int32): Vec2 {
	if (s.kinds[i] !== DrawKind.Mask || s.payloads[i] == NO_PAYLOAD) { return vec2(0.0, 0.0); }
	const sc: Scroll2D = s.scrolls[s.payloads[i]];
	return vec2(sc.x, sc.y);
}

function scrolledLocal(s: Scene2D, i: int32): Transform2D {
	const by: Vec2 = s.ownScroll(i);
	if (by.x == 0.0 && by.y == 0.0) { return s.localMatrices[i]; }
	return s.localMatrices[i] * trs2d(-by.x, -by.y, 0.0, 1.0, 1.0);
}

function absoluteMatrix(s: Scene2D, i: int32): Transform2D {
	let m: Transform2D = scrolledLocal(s, i);
	let top: int32 = i;
	while (s.parents[top] != NO_NODE_2D) {
		top = s.parents[top];
		m = scrolledLocal(s, top) * m;
	}
	if (top != s.root) { return m; }
	const view: Transform2D = { ...s.viewMat, tx: s.viewShift.x, ty: s.viewShift.y };
	return view * m;
}

export function localToGlobal(this n: NodeRef, p: Vec2): Vec2 {
	return p * absoluteMatrix(n.scene, n.liveRow("localToGlobal"));
}

export function globalToLocal(this n: NodeRef, p: Vec2): Vec2 {
	return p * inverse2d(absoluteMatrix(n.scene, n.liveRow("globalToLocal")));
}

function releasePayload(this s: Scene2D, i: int32): void {
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
			s.anims[payload].delaysMs = [];
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
		DrawKind.Mask => {
			if (payload != NO_PAYLOAD) { s.freeScrolls.push(payload); }
		},
		DrawKind.TileGroup => {
			s.tileCells[payload] = new Array(0);
			s.tileEdits[payload] = new Array(0);
			s.freeTileGroups.push(payload);
		},
		DrawKind.Group | DrawKind.ScaleGrid => {},
		DrawKind.Underline | DrawKind.Selection => {},
	}
	s.payloads[i] = NO_PAYLOAD;
}

function freeRow(this s: Scene2D, i: int32): void {
	s.releasePayload(i);
	const matrixRow: int32 = s.paints[i].colorMatrixRow;
	if (matrixRow != NO_COLOR_MATRIX_ROW) { s.freeColorMatrices.push(matrixRow); }
	s.kinds[i] = DrawKind.Group;
	s.parents[i] = NO_NODE_2D;
	s.children[i] = new Array(0);
	s.paints[i] = defaultPaint();
	s.orders[i] = { zIndex: 0, visible: true, name: "", noOverlap: false };
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
	const s: Scene2D = n.scene;
	if (top == s.root) {
		console.log("void2d: dispose asked of the scene root");
		unreachable;
	}
	s.freeSubtree(top);
}

function freeSubtree(this s: Scene2D, top: int32): void {
	s.detach(top);
	s.stack.push(top);
	while ((s.stack.length as int32) > 0) {
		const i: int32 = s.stack.pop();
		for (let k: int32 = 0; k < (s.children[i].length as int32); k++) {
			s.stack.push(s.children[i][k]);
		}
		s.releaseLayout(i);
		s.freeRow(i);
	}
}

export function closeRows(this s: Scene2D): void {
	const rows: int32 = s.generations.length as int32;
	let freed: Vec<boolean> = new Array(0);
	for (let i: int32 = 0; i < rows; i++) { freed.push(s.generations[i] == 0); }
	for (const i of s.free) { freed[i] = true; }
	let tops: Vec<int32> = new Array(0);
	for (let i: int32 = 0; i < rows; i++) {
		if (!freed[i] && s.parents[i] == NO_NODE_2D) { tops.push(i); }
	}
	for (const top of tops) { s.freeSubtree(top); }
	s.closed = true;
}
