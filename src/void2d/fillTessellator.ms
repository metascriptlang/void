import { Vec2, vec2 } from "./types";

export enum FillRule {
	EvenOdd,
	NonZero,
}

export const DEFAULT_FILL_RULE: FillRule = FillRule.EvenOdd;

const FILL_TOLERANCE: float32 = 0.1;
const NO_ID: int32 = -1;
const MIN_POSITIVE: float32 = 1.17549435e-38;
const COINCIDENT_SLOPE: float32 = 0.00005;
const NEAR_SQUARED: float64 = 0.000000001;

enum Side {
	Left,
	Right,
}

enum SweepFault {
	EdgeOrderLeftOfPoint,
	EdgeOrderEndsAtPoint,
	EdgeOrderCrossesPoint,
	EdgeOrderAboveConnection,
	EdgeOrderBeforeConnection,
	InsufficientNumberOfSpans,
	MergeVertexOutside,
}

function faultName(fault: SweepFault): string {
	return match (fault) {
		SweepFault.EdgeOrderLeftOfPoint => "incorrect active edge order (1)",
		SweepFault.EdgeOrderEndsAtPoint => "incorrect active edge order (2)",
		SweepFault.EdgeOrderCrossesPoint => "incorrect active edge order (3)",
		SweepFault.EdgeOrderAboveConnection => "incorrect active edge order (4)",
		SweepFault.EdgeOrderBeforeConnection => "incorrect active edge order (5)",
		SweepFault.InsufficientNumberOfSpans => "insufficient number of spans",
		SweepFault.MergeVertexOutside => "merge vertex outside",
	};
}

function refuse(message: string): never {
	console.log(`void2d: fill tessellation ${message}`);
	unreachable;
}

function isIn(rule: FillRule, windingNumber: int32): boolean {
	return match (rule) {
		FillRule.EvenOdd => windingNumber % 2 != 0,
		FillRule.NonZero => windingNumber != 0,
	};
}

function fmax(a: float32, b: float32): float32 { return a > b ? a : b; }
function fmin(a: float32, b: float32): float32 { return a < b ? a : b; }
function fabs(a: float32): float32 { return a < 0.0 ? -a : a; }

function slope(x: float32, y: float32): float32 { return x / fmax(y, MIN_POSITIVE); }

function samePoint(a: Vec2, b: Vec2): boolean { return a.x == b.x && a.y == b.y; }

function isAfter(a: Vec2, b: Vec2): boolean {
	return a.y > b.y || (a.y == b.y && a.x > b.x);
}

function comparePositions(a: Vec2, b: Vec2): int32 {
	if (a.y > b.y) { return 1; }
	if (a.y < b.y) { return -1; }
	if (a.x > b.x) { return 1; }
	if (a.x < b.x) { return -1; }
	return 0;
}

function isNear(a: Vec2, b: Vec2): boolean {
	const dx: float64 = (a.x as float64) - (b.x as float64);
	const dy: float64 = (a.y as float64) - (b.y as float64);
	return dx * dx + dy * dy < NEAR_SQUARED;
}

function solveTForY(from: Vec2, to: Vec2, y: float32): float32 {
	const dy: float32 = to.y - from.y;
	if (dy == 0.0) { return 0.0; }
	return (y - from.y) / dy;
}

function solveXForY(from: Vec2, to: Vec2, y: float32): float32 {
	const t: float32 = solveTForY(from, to, y);
	return from.x * (1.0 - t) + to.x * t;
}

function remapTInRange(value: float32, start: float32, end: float32): float32 {
	if (end > start) { return start + value * (end - start); }
	return end + (1.0 - value) * (start - end);
}

const SMALLEST_SUBNORMAL: float64 = 1.401298464324817e-45;
const SMALLEST_NORMAL: float64 = 1.1754943508222875e-38;
const ULP_OF_ONE: float64 = 1.1920928955078125e-7;

function nextUp(y: float32): float32 {
	if (y == 0.0) { return SMALLEST_SUBNORMAL as float32; }
	const value: float64 = y as float64;
	const size: float64 = value < 0.0 ? -value : value;
	let binade: float64 = 1.0;
	while (binade > size) { binade = binade / 2.0; }
	while (binade * 2.0 <= size) { binade = binade * 2.0; }
	let ulp: float64 = binade * ULP_OF_ONE;
	if (ulp < SMALLEST_SUBNORMAL) { ulp = SMALLEST_SUBNORMAL; }
	if (value < 0.0 && size == binade && binade > SMALLEST_NORMAL) { ulp = ulp / 2.0; }
	return (value + ulp) as float32;
}

struct Segment64 {
	fromX: float64;
	fromY: float64;
	toX: float64;
	toY: float64;
}

function segment64(from: Vec2, to: Vec2): Segment64 {
	return {
		fromX: from.x as float64, fromY: from.y as float64,
		toX: to.x as float64, toY: to.y as float64,
	};
}

struct IntersectionT {
	found: boolean;
	ta: float64;
	tb: float64;
}

const NO_INTERSECTION: IntersectionT = { found: false, ta: 0.0, tb: 0.0 };

function intersectionT(a: Segment64, b: Segment64): IntersectionT {
	if (
		(a.toX == b.toX && a.toY == b.toY) || (a.fromX == b.fromX && a.fromY == b.fromY) ||
		(a.fromX == b.toX && a.fromY == b.toY) || (a.toX == b.fromX && a.toY == b.fromY)
	) {
		return NO_INTERSECTION;
	}
	const v1x: float64 = a.toX - a.fromX;
	const v1y: float64 = a.toY - a.fromY;
	const v2x: float64 = b.toX - b.fromX;
	const v2y: float64 = b.toY - b.fromY;
	const cross: float64 = v1x * v2y - v1y * v2x;
	if (cross == 0.0) { return NO_INTERSECTION; }
	const sign: float64 = cross > 0.0 ? 1.0 : -1.0;
	const size: float64 = cross * sign;
	const v3x: float64 = b.fromX - a.fromX;
	const v3y: float64 = b.fromY - a.fromY;
	const t: float64 = (v3x * v2y - v3y * v2x) * sign;
	const u: float64 = (v3x * v1y - v3y * v1x) * sign;
	if (t < 0.0 || t > size || u < 0.0 || u > size) { return NO_INTERSECTION; }
	return { found: true, ta: t / size, tb: u / size };
}

function sample32(s: Segment64, t: float64): Vec2 {
	const keep: float64 = 1.0 - t;
	return vec2(
		(keep * s.fromX + t * s.toX) as float32,
		(keep * s.fromY + t * s.toY) as float32,
	);
}

// ===== event queue (event_queue.rs) =====

struct TessEvent {
	nextSibling: int32;
	nextEvent: int32;
	position: Vec2;
}

struct EdgeData {
	to: Vec2;
	rangeStart: float32;
	rangeEnd: float32;
	winding: int32;
	isEdge: boolean;
	fromId: int32;
	toId: int32;
}

class EventQueue {
	events: TessEvent[] = [];
	edgeData: EdgeData[] = [];
	first: int32 = NO_ID;
	current: Vec2 = vec2(0.0, 0.0);
	prev: Vec2 = vec2(0.0, 0.0);
	second: Vec2 = vec2(0.0, 0.0);
	nth: int32 = 0;
	prevEndpointId: int32 = NO_ID;

	pushUnsorted(position: Vec2): void {
		this.events.push({ nextSibling: NO_ID, nextEvent: NO_ID, position: position });
	}

	insertSorted(position: Vec2, data: EdgeData, after: int32): int32 {
		const idx: int32 = this.events.length as int32;
		this.pushUnsorted(position);
		this.edgeData.push(data);
		this.insertIntoSortedList(idx, position, after);
		return idx;
	}

	insertSibling(sibling: int32, position: Vec2, data: EdgeData): void {
		const idx: int32 = this.events.length as int32;
		this.events.push({
			nextSibling: this.events[sibling].nextSibling, nextEvent: NO_ID, position: position,
		});
		this.edgeData.push(data);
		this.events[sibling].nextSibling = idx;
	}

	vertexEventSorted(position: Vec2, endpointId: int32, after: int32): void {
		const idx: int32 = this.events.length as int32;
		this.pushUnsorted(position);
		this.edgeData.push(vertexData(endpointId));
		this.insertIntoSortedList(idx, position, after);
	}

	insertIntoSortedList(idx: int32, position: Vec2, after: int32): void {
		let prev: int32 = after;
		let current: int32 = after;
		while (current != NO_ID) {
			const pos: Vec2 = this.events[current].position;
			if (samePoint(pos, position)) {
				this.events[idx].nextSibling = this.events[current].nextSibling;
				this.events[current].nextSibling = idx;
				return;
			}
			if (isAfter(pos, position)) {
				this.events[prev].nextEvent = idx;
				this.events[idx].nextEvent = current;
				return;
			}
			prev = current;
			current = this.events[current].nextEvent;
		}
		this.events[prev].nextEvent = idx;
	}

	sort(): void {
		const n: int32 = this.events.length as int32;
		if (n == 0) { return; }
		const keys: int32[] = [];
		for (let i: int32 = 0; i < n; i++) { keys.push(i); }
		keys.sort((a, b) => {
			const order: int32 =
				comparePositions(this.events[a].position, this.events[b].position);
			return order != 0 ? order : a - b;
		});
		this.first = keys[0];
		let groupStart: int32 = 0;
		while (groupStart < n) {
			const head: int32 = keys[groupStart];
			const at: Vec2 = this.events[head].position;
			let prev: int32 = head;
			let i: int32 = groupStart + 1;
			while (i < n && samePoint(this.events[keys[i]].position, at)) {
				this.events[prev].nextSibling = keys[i];
				prev = keys[i];
				i++;
			}
			this.events[prev].nextSibling = NO_ID;
			this.events[head].nextEvent = i < n ? keys[i] : NO_ID;
			groupStart = i;
		}
	}

	vertexEvent(at: Vec2, endpointId: int32): void {
		this.pushUnsorted(at);
		this.edgeData.push(vertexData(endpointId));
	}

	begin(to: Vec2, toId: int32): void {
		this.nth = 0;
		this.current = to;
		this.prevEndpointId = toId;
	}

	end(first: Vec2, firstEndpointId: int32): void {
		if (this.nth == 0) { return; }
		this.lineSegment(first, firstEndpointId);
		if (isAfter(first, this.prev) && isAfter(first, this.second)) {
			this.vertexEvent(first, firstEndpointId);
		}
		this.prevEndpointId = firstEndpointId;
		this.nth = 0;
	}

	addEdge(from: Vec2, to: Vec2, fromId: int32, toId: int32): void {
		if (samePoint(from, to)) { return; }
		let position: Vec2 = from;
		let end: Vec2 = to;
		let t0: float32 = 0.0;
		let t1: float32 = 1.0;
		let winding: int32 = 1;
		if (isAfter(position, to)) {
			end = position;
			position = to;
			t0 = 1.0;
			t1 = 0.0;
			winding = -1;
		}
		this.pushUnsorted(position);
		this.edgeData.push({
			to: end, rangeStart: t0, rangeEnd: t1, winding: winding, isEdge: true,
			fromId: fromId, toId: toId,
		});
		this.nth++;
	}

	lineSegment(to: Vec2, toId: int32): void {
		const from: Vec2 = this.current;
		if (samePoint(from, to)) { return; }
		if (isAfter(from, to) && this.nth > 0 && isAfter(from, this.prev)) {
			this.vertexEvent(from, this.prevEndpointId);
		}
		if (this.nth == 0) { this.second = to; }
		this.addEdge(from, to, this.prevEndpointId, toId);
		this.prev = this.current;
		this.prevEndpointId = toId;
		this.current = to;
	}
}

function vertexData(endpointId: int32): EdgeData {
	return {
		to: vec2(0.0, 0.0), rangeStart: 0.0, rangeEnd: 0.0, winding: 0, isEdge: false,
		fromId: endpointId, toId: endpointId,
	};
}

// ===== monotone polygons (monotone.rs) =====

struct MonotoneVertex {
	pos: Vec2;
	id: int32;
	side: Side;
}

function cross(ax: float32, ay: float32, bx: float32, by: float32): float32 {
	return ax * by - ay * bx;
}

class BasicMonotoneTessellator {
	stack: MonotoneVertex[] = [];
	previous: MonotoneVertex = { pos: vec2(0.0, 0.0), id: 0, side: Side.Left };
	triangles: int32[] = [];

	begin(pos: Vec2, id: int32): void {
		const first: MonotoneVertex = { pos: pos, id: id, side: Side.Left };
		this.previous = first;
		this.triangles = [];
		this.stack = [first];
	}

	monotoneVertex(current: MonotoneVertex): void {
		if (current.side != this.previous.side) {
			const count: int32 = this.stack.length as int32;
			for (let i: int32 = 0; i < count - 1; i++) {
				let a: MonotoneVertex = this.stack[i];
				let b: MonotoneVertex = this.stack[i + 1];
				const winding: boolean = cross(
					a.pos.x - b.pos.x, a.pos.y - b.pos.y,
					current.pos.x - b.pos.x, current.pos.y - b.pos.y,
				) >= 0.0;
				if (!winding) {
					const swap: MonotoneVertex = a;
					a = b;
					b = swap;
				}
				this.pushTriangle(a.id, b.id, current.id);
			}
			this.stack = [this.previous];
		} else {
			let lastPopped: MonotoneVertex = this.stack.pop();
			while ((this.stack.length as int32) > 0) {
				let a: MonotoneVertex = lastPopped;
				let b: MonotoneVertex = this.stack[(this.stack.length as int32) - 1];
				if (current.side == Side.Right) {
					const swap: MonotoneVertex = a;
					a = b;
					b = swap;
				}
				const turn: float32 = cross(
					current.pos.x - b.pos.x, current.pos.y - b.pos.y,
					a.pos.x - b.pos.x, a.pos.y - b.pos.y,
				);
				if (turn >= 0.0) {
					this.pushTriangle(b.id, a.id, current.id);
					lastPopped = this.stack.pop();
				} else {
					break;
				}
			}
			this.stack.push(lastPopped);
		}
		this.stack.push(current);
		this.previous = current;
	}

	end(pos: Vec2, id: int32): void {
		const side: Side = this.previous.side == Side.Left ? Side.Right : Side.Left;
		this.monotoneVertex({ pos: pos, id: id, side: side });
		this.stack = [];
	}

	pushTriangle(a: int32, b: int32, c: int32): void {
		this.triangles.push(a);
		this.triangles.push(b);
		this.triangles.push(c);
	}

	flush(output: int32[]): void {
		for (const index of this.triangles) { output.push(index); }
		this.triangles = [];
	}
}

class SideEvents {
	referencePoint: Vec2 = vec2(0.0, 0.0);
	conservativeReferenceX: float32 = 0.0;
	events: int32[] = [];
	prev: Vec2 = vec2(0.0, 0.0);
	last: MonotoneVertex = { pos: vec2(0.0, 0.0), id: 0, side: Side.Left };

	push(vertex: MonotoneVertex): void {
		this.events.push(vertex.id);
		this.prev = this.last.pos;
		this.last = vertex;
	}
}

function flushSide(side: SideEvents, s: Side, tess: BasicMonotoneTessellator): boolean {
	const len: int32 = side.events.length as int32;
	if (len < 2) { return false; }
	let step: int32 = 1;
	while (step * 2 < len) {
		let lastIndex: int32 = 0;
		const imax: int32 = (len - 1) / (2 * step);
		for (let i: int32 = 0; i < imax; i++) {
			let a: int32 = i * 2 * step;
			let b: int32 = a + step;
			lastIndex = b + step;
			if (s == Side.Right) {
				const swap: int32 = a;
				a = b;
				b = swap;
			}
			tess.pushTriangle(side.events[a], side.events[b], side.events[lastIndex]);
		}
		if (lastIndex + step < len) {
			let b: int32 = lastIndex;
			let c: int32 = lastIndex + step;
			if (s == Side.Right) {
				const swap: int32 = b;
				b = c;
				c = swap;
			}
			tess.pushTriangle(side.events[0], side.events[b], side.events[c]);
		}
		step = step * 2;
	}
	side.events = [];
	side.push(side.last);
	side.referencePoint = side.last.pos;
	return true;
}

class MonotoneTessellator {
	tess: BasicMonotoneTessellator = new BasicMonotoneTessellator();
	left: SideEvents = new SideEvents();
	right: SideEvents = new SideEvents();

	begin(pos: Vec2, id: int32): void {
		this.tess.begin(pos, id);
		this.left.referencePoint = pos;
		this.left.conservativeReferenceX = pos.x;
		this.right.referencePoint = pos;
		this.right.conservativeReferenceX = pos.x;
		this.left.prev = pos;
		this.right.prev = pos;
		this.left.events = [];
		this.right.events = [];
		this.left.push({ pos: pos, id: id, side: Side.Left });
		this.right.push({ pos: pos, id: id, side: Side.Right });
	}

	vertex(pos: Vec2, id: int32, side: Side): void {
		if (side == Side.Left) {
			this.left.referencePoint = vec2(fmax(this.left.referencePoint.x, pos.x),
				this.left.referencePoint.y);
			this.left.conservativeReferenceX =
				fmax(this.left.conservativeReferenceX, this.left.referencePoint.x);
		} else {
			this.right.referencePoint = vec2(fmin(this.right.referencePoint.x, pos.x),
				this.right.referencePoint.y);
			this.right.conservativeReferenceX =
				fmin(this.right.conservativeReferenceX, this.right.referencePoint.x);
		}
		const dx: float32 = this.right.conservativeReferenceX - this.left.conservativeReferenceX;
		const sideEvents: SideEvents = side == Side.Left ? this.left : this.right;
		const opposite: SideEvents = side == Side.Left ? this.right : this.left;
		const dy: float32 = pos.y - sideEvents.referencePoint.y;
		const sidesAreClose: boolean = dx < dy * 0.1;
		let outwardTurn: boolean = false;
		if (!sidesAreClose && (sideEvents.events.length as int32) >= 2) {
			const sign: float32 = side == Side.Left ? 1.0 : -1.0;
			const prev: Vec2 = sideEvents.prev;
			const last: Vec2 = sideEvents.last.pos;
			outwardTurn =
				cross(prev.x - last.x, prev.y - last.y, pos.x - last.x, pos.y - last.y) * sign <
					0.0;
		}
		if (outwardTurn || sidesAreClose) {
			if (isAfter(sideEvents.last.pos, opposite.last.pos)) {
				const otherSide: Side = side == Side.Left ? Side.Right : Side.Left;
				if (flushSide(opposite, otherSide, this.tess)) {
					this.tess.monotoneVertex(opposite.last);
					sideEvents.conservativeReferenceX = sideEvents.referencePoint.x;
				}
			}
			if (flushSide(sideEvents, side, this.tess)) {
				this.tess.monotoneVertex(sideEvents.last);
				opposite.conservativeReferenceX = opposite.referencePoint.x;
			}
		}
		sideEvents.push({ pos: pos, id: id, side: side });
	}

	end(pos: Vec2, id: int32): void {
		const a: boolean = flushSide(this.left, Side.Left, this.tess);
		const b: boolean = flushSide(this.right, Side.Right, this.tess);
		if (a && b) {
			let v1: MonotoneVertex = this.left.last;
			let v2: MonotoneVertex = this.right.last;
			if (isAfter(v1.pos, v2.pos)) {
				const swap: MonotoneVertex = v1;
				v1 = v2;
				v2 = swap;
			}
			this.tess.monotoneVertex(v1);
			this.tess.monotoneVertex(v2);
		} else if (a) {
			this.tess.monotoneVertex(this.left.last);
		} else if (b) {
			this.tess.monotoneVertex(this.right.last);
		}
		this.tess.end(pos, id);
	}
}

// ===== the sweep line (fill.rs) =====

struct WindingState {
	spanIndex: int32;
	number: int32;
	isIn: boolean;
}

const WINDING_START: WindingState = { spanIndex: -1, number: 0, isIn: false };

function update(this ref w: WindingState, rule: FillRule, edgeWinding: int32): void {
	w.number = w.number + edgeWinding;
	w.isIn = isIn(rule, w.number);
	if (w.isIn) { w.spanIndex = w.spanIndex + 1; }
}

struct ActiveEdge {
	from: Vec2;
	to: Vec2;
	winding: int32;
	isMerge: boolean;
	fromId: int32;
	srcEdge: int32;
	rangeEnd: float32;
}

function minX(this e: ActiveEdge): float32 { return fmin(e.from.x, e.to.x); }
function maxX(this e: ActiveEdge): float32 { return fmax(e.from.x, e.to.x); }

function solveX(this e: ActiveEdge, y: float32): float32 {
	return fmin(fmax(solveXForY(e.from, e.to, y), e.minX()), e.maxX());
}

struct PendingEdge {
	to: Vec2;
	sortKey: float32;
	srcEdge: int32;
	winding: int32;
	rangeEnd: float32;
}

struct VertexEvent {
	span: int32;
	side: Side;
}

class ActiveEdgeScan {
	vertexEvents: VertexEvent[] = [];
	edgesToSplit: int32[] = [];
	spansToEnd: int32[] = [];
	mergeEvent: boolean = false;
	splitEvent: boolean = false;
	mergeSplitEvent: boolean = false;
	aboveStart: int32 = 0;
	aboveEnd: int32 = 0;
	windingBeforePoint: WindingState = WINDING_START;

	reset(): void {
		this.vertexEvents = [];
		this.edgesToSplit = [];
		this.spansToEnd = [];
		this.mergeEvent = false;
		this.splitEvent = false;
		this.mergeSplitEvent = false;
		this.aboveStart = 0;
		this.aboveEnd = 0;
		this.windingBeforePoint = WINDING_START;
	}
}

export struct FillTessellation {
	positions: Vec2[];
	endpoints: int32[];
	triangles: int32[];
}

function removeAt<T>(items: T[], at: int32): void {
	const n: int32 = items.length as int32;
	for (let i: int32 = at; i + 1 < n; i++) { items[i] = items[i + 1]; }
	items.pop();
}

function insertAt<T>(items: T[], at: int32, item: T): void {
	items.push(item);
	for (let i: int32 = (items.length as int32) - 1; i > at; i--) { items[i] = items[i - 1]; }
	items[at] = item;
}

class FillTessellator {
	rule: FillRule;
	tolerance: float32 = FILL_TOLERANCE * 0.5;
	currentPosition: Vec2 = vec2(0.0, 0.0);
	currentVertex: int32 = NO_ID;
	currentEventId: int32 = NO_ID;
	active: ActiveEdge[] = [];
	edgesBelow: PendingEdge[] = [];
	spans: MonotoneTessellator[] = [];
	live: boolean[] = [];
	scan: ActiveEdgeScan = new ActiveEdgeScan();
	events: EventQueue = new EventQueue();
	positions: Vec2[] = [];
	endpoints: int32[] = [];
	triangles: int32[] = [];

	constructor(rule: FillRule) { this.rule = rule; }

	beginSpan(spanIdx: int32, position: Vec2, vertex: int32): void {
		const tess: MonotoneTessellator = new MonotoneTessellator();
		tess.begin(position, vertex);
		insertAt(this.spans, spanIdx, tess);
		insertAt(this.live, spanIdx, true);
	}

	span(spanIdx: int32): MonotoneTessellator {
		if (!this.live[spanIdx]) { refuse(`reached span ${spanIdx} after it ended`); }
		return this.spans[spanIdx];
	}

	endSpan(spanIdx: int32, position: Vec2, id: int32): void {
		const tess: MonotoneTessellator = this.span(spanIdx);
		tess.end(position, id);
		tess.tess.flush(this.triangles);
		this.live[spanIdx] = false;
	}

	cleanupSpans(): void {
		const spans: MonotoneTessellator[] = [];
		const live: boolean[] = [];
		for (let i: int32 = 0; i < (this.spans.length as int32); i++) {
			if (!this.live[i]) { continue; }
			spans.push(this.spans[i]);
			live.push(true);
		}
		this.spans = spans;
		this.live = live;
	}

	run(): void {
		this.currentEventId = this.events.first;
		while (this.currentEventId != NO_ID) {
			this.initializeEvents();
			const first: Result<void, SweepFault> = this.processEvents();
			if (!first.ok) {
				this.recoverFromError();
				const second: Result<void, SweepFault> = this.processEvents();
				if (!second.ok) {
					const at: Vec2 = this.currentPosition;
					refuse(`failed at (${at.x}, ${at.y}): ${faultName(second.error)}`);
				}
			}
			this.currentEventId = this.events.events[this.currentEventId].nextEvent;
		}
		if ((this.active.length as int32) != 0 || (this.spans.length as int32) != 0) {
			refuse(`ended with ${this.active.length} active edges and ${this.spans.length} open spans`);
		}
	}

	endpointOf(event: int32): int32 {
		let current: int32 = event;
		while (current != NO_ID) {
			const edge: EdgeData = this.events.edgeData[current];
			if (edge.rangeStart == 0.0) { return edge.fromId; }
			if (edge.rangeStart == 1.0) { return edge.toId; }
			current = this.events.events[current].nextSibling;
		}
		return NO_ID;
	}

	initializeEvents(): void {
		const currentEvent: int32 = this.currentEventId;
		this.currentPosition = this.events.events[currentEvent].position;
		this.currentVertex = this.positions.length as int32;
		this.positions.push(this.currentPosition);
		this.endpoints.push(this.endpointOf(currentEvent));
		let sibling: int32 = currentEvent;
		while (sibling != NO_ID) {
			const edge: EdgeData = this.events.edgeData[sibling];
			if (edge.isEdge) {
				this.edgesBelow.push({
					to: edge.to, sortKey: 0.0, srcEdge: sibling, winding: edge.winding,
					rangeEnd: edge.rangeEnd,
				});
			}
			sibling = this.events.events[sibling].nextSibling;
		}
	}

	processEvents(): Result<void, SweepFault> {
		try this.scanActiveEdges();
		this.processEdgesAbove();
		this.processEdgesBelow();
		this.updateActiveEdges();
		return Result.ok(null);
	}

	scanActiveEdges(): Result<void, SweepFault> {
		const scan: ActiveEdgeScan = this.scan;
		scan.reset();
		const position: Vec2 = this.currentPosition;
		const currentX: float32 = position.x;
		const count: int32 = this.active.length as int32;
		let connectingEdges: boolean = false;
		let idx: int32 = 0;
		let winding: WindingState = WINDING_START;
		let previousWasMerge: boolean = false;
		while (idx < count) {
			const edge: ActiveEdge = this.active[idx];
			if (edge.isMerge) {
				winding.spanIndex = winding.spanIndex + 1;
				idx++;
				previousWasMerge = true;
				continue;
			}
			let before: boolean = true;
			if (edge.maxX() < currentX) {
				before = true;
			} else if (samePoint(position, edge.to)) {
				connectingEdges = true;
				before = false;
			} else if (edge.minX() > currentX) {
				before = false;
			} else if (edge.from.y == edge.to.y) {
				connectingEdges = true;
				before = false;
			} else {
				const ex: float32 = edge.solveX(position.y);
				if (fabs(ex - currentX) <= this.tolerance) {
					connectingEdges = true;
					before = false;
				} else {
					before = !(ex > currentX);
				}
			}
			if (!before) { break; }
			winding.update(this.rule, edge.winding);
			previousWasMerge = false;
			idx++;
		}
		scan.aboveStart = idx;
		scan.windingBeforePoint = winding;
		if (previousWasMerge) {
			scan.windingBeforePoint.spanIndex = scan.windingBeforePoint.spanIndex - 1;
			scan.aboveStart = scan.aboveStart - 1;
			if (!connectingEdges) {
				scan.vertexEvents.push({ span: winding.spanIndex - 1, side: Side.Right });
				scan.vertexEvents.push({ span: winding.spanIndex, side: Side.Left });
				scan.mergeSplitEvent = true;
			}
		}
		scan.splitEvent = !connectingEdges && winding.isIn && !scan.mergeSplitEvent;
		if (connectingEdges) {
			const inBeforeVertex: boolean = winding.isIn;
			let firstConnectingEdge: boolean = !previousWasMerge;
			while (idx < count) {
				const edge: ActiveEdge = this.active[idx];
				if (edge.isMerge) {
					if (!winding.isIn) { return Result.err(SweepFault.MergeVertexOutside); }
					scan.spansToEnd.push(winding.spanIndex);
					winding.spanIndex = winding.spanIndex + 1;
					idx++;
					firstConnectingEdge = false;
					continue;
				}
				const connects: boolean = try this.isEdgeConnecting(edge, idx);
				if (!connects) { break; }
				if (!firstConnectingEdge && winding.isIn) { scan.spansToEnd.push(winding.spanIndex); }
				winding.update(this.rule, edge.winding);
				if (winding.isIn && winding.spanIndex >= (this.spans.length as int32)) {
					return Result.err(SweepFault.InsufficientNumberOfSpans);
				}
				idx++;
				firstConnectingEdge = false;
			}
			const inAfterVertex: boolean = winding.isIn;
			if (
				inBeforeVertex && inAfterVertex && (this.edgesBelow.length as int32) == 0 &&
				(scan.edgesToSplit.length as int32) == 0
			) {
				scan.mergeEvent = true;
			}
			if (inBeforeVertex) {
				scan.vertexEvents.push({ span: scan.windingBeforePoint.spanIndex, side: Side.Right });
			}
			if (inAfterVertex) {
				scan.vertexEvents.push({ span: winding.spanIndex, side: Side.Left });
			}
		}
		scan.aboveEnd = idx;
		return this.checkRemainingEdges(idx, currentX);
	}

	checkRemainingEdges(from: int32, currentX: float32): Result<void, SweepFault> {
		for (let i: int32 = from; i < (this.active.length as int32); i++) {
			const edge: ActiveEdge = this.active[i];
			if (edge.isMerge) { continue; }
			const lowX: float32 = edge.minX();
			if (lowX > currentX) { continue; }
			if (edge.maxX() < currentX) { return Result.err(SweepFault.EdgeOrderLeftOfPoint); }
			if (samePoint(this.currentPosition, edge.to)) {
				return Result.err(SweepFault.EdgeOrderEndsAtPoint);
			}
			if (lowX < currentX && edge.solveX(this.currentPosition.y) < currentX) {
				return Result.err(SweepFault.EdgeOrderCrossesPoint);
			}
		}
		return Result.ok(null);
	}

	isEdgeConnecting(edge: ActiveEdge, idx: int32): Result<boolean, SweepFault> {
		const currentX: float32 = this.currentPosition.x;
		const threshold: float32 = this.tolerance;
		const lowX: float32 = edge.minX();
		const highX: float32 = edge.maxX();
		if (highX + threshold < currentX || edge.to.y < this.currentPosition.y) {
			return Result.err(SweepFault.EdgeOrderAboveConnection);
		}
		if (lowX > currentX) { return Result.ok(false); }
		if (samePoint(this.currentPosition, edge.to)) { return Result.ok(true); }
		let ex: float32 = edge.to.x;
		if (edge.from.y != edge.to.y) {
			ex = edge.solveX(this.currentPosition.y);
		} else if (highX >= currentX && lowX <= currentX) {
			ex = currentX;
		}
		if (fabs(ex - currentX) <= threshold) {
			this.scan.edgesToSplit.push(idx);
			return Result.ok(true);
		}
		if (ex < currentX) { return Result.err(SweepFault.EdgeOrderBeforeConnection); }
		return Result.ok(false);
	}

	processEdgesAbove(): void {
		const scan: ActiveEdgeScan = this.scan;
		for (const event of scan.vertexEvents) {
			this.span(event.span).vertex(this.currentPosition, this.currentVertex, event.side);
		}
		for (const spanIdx of scan.spansToEnd) {
			this.endSpan(spanIdx, this.currentPosition, this.currentVertex);
		}
		if ((scan.spansToEnd.length as int32) > 0) { this.cleanupSpans(); }
		for (const edgeIdx of scan.edgesToSplit) {
			const edge: ActiveEdge = this.active[edgeIdx];
			this.edgesBelow.push({
				to: edge.to, sortKey: 0.0, srcEdge: edge.srcEdge, winding: edge.winding,
				rangeEnd: edge.rangeEnd,
			});
			this.active[edgeIdx].to = this.currentPosition;
		}
		if (scan.mergeEvent) {
			const at: int32 = scan.aboveStart;
			this.active[at].isMerge = true;
			this.active[at].from = this.active[at].to;
			this.active[at].winding = 0;
			this.active[at].fromId = this.currentVertex;
			scan.aboveStart = scan.aboveStart + 1;
		}
	}

	processEdgesBelow(): void {
		const scan: ActiveEdgeScan = this.scan;
		let winding: WindingState = scan.windingBeforePoint;
		this.sortEdgesBelow();
		this.handleCoincidentEdgesBelow();
		if (scan.splitEvent) { this.splitEvent(scan.aboveStart - 1, winding.spanIndex); }
		let firstPendingEdge: boolean = true;
		for (const pending of this.edgesBelow) {
			if (!firstPendingEdge && winding.isIn) {
				this.beginSpan(winding.spanIndex, this.currentPosition, this.currentVertex);
			}
			winding.update(this.rule, pending.winding);
			firstPendingEdge = false;
		}
	}

	updateActiveEdges(): void {
		const start: int32 = this.scan.aboveStart;
		const end: int32 = this.scan.aboveEnd;
		this.handleIntersections(start, end);
		const next: ActiveEdge[] = [];
		for (let i: int32 = 0; i < start; i++) { next.push(this.active[i]); }
		for (const edge of this.edgesBelow) {
			next.push({
				from: this.currentPosition, to: edge.to, winding: edge.winding, isMerge: false,
				fromId: this.currentVertex, srcEdge: edge.srcEdge, rangeEnd: edge.rangeEnd,
			});
		}
		for (let i: int32 = end; i < (this.active.length as int32); i++) {
			next.push(this.active[i]);
		}
		this.active = next;
		this.edgesBelow = [];
	}

	splitEvent(leftEnclosingEdgeIdx: int32, leftSpanIdx: int32): void {
		const left: ActiveEdge = this.active[leftEnclosingEdgeIdx];
		const right: ActiveEdge = this.active[leftEnclosingEdgeIdx + 1];
		const rightSpanIdx: int32 = leftSpanIdx + 1;
		if (isAfter(left.from, right.from)) {
			this.beginSpan(leftSpanIdx, left.from, left.fromId);
		} else {
			this.beginSpan(rightSpanIdx, right.from, right.fromId);
		}
		this.span(leftSpanIdx).vertex(this.currentPosition, this.currentVertex, Side.Right);
		this.span(rightSpanIdx).vertex(this.currentPosition, this.currentVertex, Side.Left);
	}

	handleIntersections(skipStart: int32, skipEnd: int32): void {
		for (let b: int32 = 0; b < (this.edgesBelow.length as int32); b++) {
			const below: PendingEdge = this.edgesBelow[b];
			const belowMinX: float32 = fmin(this.currentPosition.x, below.to.x);
			const belowMaxX: float32 = fmax(this.currentPosition.x, below.to.x);
			const belowSegment: Segment64 = segment64(this.currentPosition, below.to);
			let tbMin: float64 = 1.0;
			let best: IntersectionT = NO_INTERSECTION;
			let bestEdge: int32 = NO_ID;
			for (let i: int32 = 0; i < (this.active.length as int32); i++) {
				if (i >= skipStart && i < skipEnd) { continue; }
				const edge: ActiveEdge = this.active[i];
				if (edge.isMerge || belowMinX > edge.maxX()) { continue; }
				if (belowMaxX < edge.minX()) { continue; }
				const hit: IntersectionT = intersectionT(segment64(edge.from, edge.to), belowSegment);
				if (hit.found && hit.tb < tbMin && hit.tb > 0.0 && hit.ta > 0.0 && hit.ta <= 1.0) {
					tbMin = hit.tb;
					best = hit;
					bestEdge = i;
				}
			}
			if (bestEdge != NO_ID) {
				this.processIntersection(best.ta, best.tb, bestEdge, b, belowSegment);
			}
		}
	}

	processIntersection(
		ta: float64,
		tb: float64,
		activeIdx: int32,
		belowIdx: int32,
		belowSegment: Segment64,
	): void {
		let position: Vec2 = sample32(belowSegment, tb);
		const active: ActiveEdge = this.active[activeIdx];
		if (samePoint(this.currentPosition, position)) {
			this.active[activeIdx].from = position;
			const src: EdgeData = this.events.edgeData[active.srcEdge];
			this.events.edgeData[active.srcEdge].rangeStart =
				remapTInRange(ta as float32, src.rangeStart, active.rangeEnd);
			return;
		}
		if (!isAfter(position, this.currentPosition)) {
			position = vec2(position.x, nextUp(this.currentPosition.y));
		}
		if (!isAfter(position, this.currentPosition)) {
			const sweep: Vec2 = this.currentPosition;
			refuse(
				`placed an intersection at (${position.x}, ${position.y}), ` +
					`not after the sweep at (${sweep.x}, ${sweep.y})`,
			);
		}
		const below: PendingEdge = this.edgesBelow[belowIdx];
		if (isNear(position, below.to)) {
			position = below.to;
		} else if (isNear(position, active.to)) {
			position = active.to;
		}
		const aData: EdgeData = this.events.edgeData[active.srcEdge];
		const bData: EdgeData = this.events.edgeData[below.srcEdge];
		let insertedEvent: int32 = NO_ID;
		let flippedActive: boolean = false;
		if (!samePoint(active.to, position) && !samePoint(active.from, position)) {
			const remappedTa: float32 =
				remapTInRange(ta as float32, aData.rangeStart, active.rangeEnd);
			if (isAfter(active.to, position)) {
				insertedEvent = this.events.insertSorted(position, {
					...aData, rangeStart: remappedTa, rangeEnd: active.rangeEnd,
					winding: active.winding, to: active.to, isEdge: true,
				}, this.currentEventId);
			} else {
				flippedActive = true;
				this.events.insertSorted(active.to, {
					...aData, rangeStart: active.rangeEnd, rangeEnd: remappedTa,
					winding: -active.winding, to: position, isEdge: true,
				}, this.currentEventId);
			}
			this.active[activeIdx].to = position;
			this.active[activeIdx].rangeEnd = remappedTa;
		}
		if (!samePoint(below.to, position) && !samePoint(this.currentPosition, position)) {
			const remappedTb: float32 =
				remapTInRange(tb as float32, bData.rangeStart, below.rangeEnd);
			if (isAfter(below.to, position)) {
				const data: EdgeData = {
					...bData, rangeStart: remappedTb, rangeEnd: below.rangeEnd,
					winding: below.winding, to: below.to, isEdge: true,
				};
				if (insertedEvent != NO_ID) {
					this.events.insertSibling(insertedEvent, position, data);
				} else {
					this.events.insertSorted(position, data, this.currentEventId);
				}
			} else {
				this.events.insertSorted(below.to, {
					...bData, rangeStart: below.rangeEnd, rangeEnd: remappedTb,
					winding: -below.winding, to: position, isEdge: true,
				}, this.currentEventId);
				if (flippedActive) {
					this.events.vertexEventSorted(position, bData.toId, this.currentEventId);
				}
			}
			this.edgesBelow[belowIdx].to = position;
			this.edgesBelow[belowIdx].rangeEnd = remappedTb;
		}
	}

	sortActiveEdges(): void {
		const y: float32 = this.currentPosition.y;
		const count: int32 = this.active.length as int32;
		const keys: float32[] = [];
		const order: int32[] = [];
		let hasMergeVertex: boolean = false;
		let prevX: float32 = 0.0;
		for (let i: int32 = 0; i < count; i++) {
			const edge: ActiveEdge = this.active[i];
			order.push(i);
			if (edge.isMerge) {
				hasMergeVertex = true;
				keys.push(prevX);
				continue;
			}
			const eqTo: boolean = edge.to.y == y;
			const eqFrom: boolean = edge.from.y == y;
			let x: float32 = 0.0;
			if (eqTo && eqFrom) {
				const currentX: float32 = this.currentPosition.x;
				x = edge.maxX() >= currentX && edge.minX() <= currentX ? currentX : edge.minX();
			} else if (eqFrom) {
				x = edge.from.x;
			} else if (eqTo) {
				x = edge.to.x;
			} else {
				x = edge.solveX(y);
			}
			keys.push(fmax(x, edge.minX()));
			prevX = x;
		}
		order.sort((a, b) => {
			if (keys[a] < keys[b]) { return -1; }
			if (keys[a] > keys[b]) { return 1; }
			const ea: ActiveEdge = this.active[a];
			const eb: ActiveEdge = this.active[b];
			if (!ea.isMerge && !eb.isMerge) {
				const slopeA: float32 = slope(ea.to.x - ea.from.x, ea.to.y - ea.from.y);
				const slopeB: float32 = slope(eb.to.x - eb.from.x, eb.to.y - eb.from.y);
				if (slopeB < slopeA) { return -1; }
				if (slopeB > slopeA) { return 1; }
			} else if (ea.isMerge && !eb.isMerge) {
				return 1;
			} else if (!ea.isMerge && eb.isMerge) {
				return -1;
			}
			return a - b;
		});
		const sorted: ActiveEdge[] = [];
		for (const i of order) { sorted.push(this.active[i]); }
		this.active = sorted;
		if (!hasMergeVertex) { return; }
		let windingNumber: int32 = 0;
		let i: int32 = 0;
		while (i < count) {
			if (!this.active[i].isMerge) {
				windingNumber = windingNumber + this.active[i].winding;
				i++;
				continue;
			}
			if (isIn(this.rule, windingNumber)) {
				i++;
				continue;
			}
			let target: int32 = NO_ID;
			let w: int32 = windingNumber;
			for (let idx: int32 = i - 1; idx >= 1; idx--) {
				w = w - this.active[idx].winding;
				if (isIn(this.rule, w)) {
					target = idx;
					break;
				}
			}
			if (target != NO_ID) {
				const merge: ActiveEdge = this.active[i];
				for (let k: int32 = i; k > target; k--) { this.active[k] = this.active[k - 1]; }
				this.active[target] = merge;
				i++;
				continue;
			}
			w = windingNumber;
			for (let idx: int32 = i + 1; idx < count; idx++) {
				w = w + this.active[idx].winding;
				if (isIn(this.rule, w)) {
					target = idx;
					break;
				}
			}
			if (target != NO_ID) {
				const merge: ActiveEdge = this.active[i];
				for (let k: int32 = i; k < target; k++) { this.active[k] = this.active[k + 1]; }
				this.active[target] = merge;
			} else {
				i++;
			}
		}
	}

	recoverFromError(): void {
		this.sortActiveEdges();
		const len: int32 = this.active.length as int32;
		if (len > 1 && this.active[len - 1].isMerge) {
			const last: ActiveEdge = this.active[len - 1];
			this.active[len - 1] = this.active[len - 2];
			this.active[len - 2] = last;
		}
		let winding: WindingState = WINDING_START;
		for (const edge of this.active) {
			if (edge.isMerge) {
				winding.spanIndex = winding.spanIndex + 1;
			} else {
				winding.update(this.rule, edge.winding);
			}
			if (winding.spanIndex >= (this.spans.length as int32)) {
				this.beginSpan(winding.spanIndex, edge.from, edge.fromId);
			}
		}
		while ((this.spans.length as int32) > winding.spanIndex + 1) {
			const last: int32 = (this.spans.length as int32) - 1;
			this.span(last).tess.flush(this.triangles);
			this.spans.pop();
			this.live.pop();
		}
	}

	sortEdgesBelow(): void {
		if ((this.edgesBelow.length as int32) < 2) { return; }
		const origin: Vec2 = this.currentPosition;
		for (let i: int32 = 0; i < (this.edgesBelow.length as int32); i++) {
			const to: Vec2 = this.edgesBelow[i].to;
			this.edgesBelow[i].sortKey = slope(to.x - origin.x, to.y - origin.y);
		}
		this.edgesBelow.sort((a, b) => a.sortKey < b.sortKey ? -1 : (a.sortKey > b.sortKey ? 1 : 0));
	}

	handleCoincidentEdgesBelow(): void {
		const count: int32 = this.edgesBelow.length as int32;
		if (count < 2) { return; }
		for (let idx: int32 = count - 2; idx >= 0; idx--) {
			const aSlope: float32 = this.edgesBelow[idx].sortKey;
			const bSlope: float32 = this.edgesBelow[idx + 1].sortKey;
			const angleIsClose: boolean = fabs(aSlope) <= 1.0
				? fabs(aSlope - bSlope) < COINCIDENT_SLOPE
				: fabs(1.0 / aSlope - 1.0 / bSlope) < COINCIDENT_SLOPE;
			if (angleIsClose) { this.mergeCoincidentEdges(idx, idx + 1); }
		}
	}

	mergeCoincidentEdges(aIdx: int32, bIdx: int32): void {
		const aTo: Vec2 = this.edgesBelow[aIdx].to;
		const bTo: Vec2 = this.edgesBelow[bIdx].to;
		const order: int32 = comparePositions(aTo, bTo);
		const lowerIdx: int32 = order < 0 ? bIdx : aIdx;
		const upperIdx: int32 = order < 0 ? aIdx : bIdx;
		const split: boolean = order != 0;
		this.edgesBelow[upperIdx].winding =
			this.edgesBelow[upperIdx].winding + this.edgesBelow[lowerIdx].winding;
		const splitPoint: Vec2 = this.edgesBelow[upperIdx].to;
		const edge: PendingEdge = this.edgesBelow[lowerIdx];
		removeAt(this.edgesBelow, lowerIdx);
		if (!split) { return; }
		const src: EdgeData = this.events.edgeData[edge.srcEdge];
		const t: float32 = solveTForY(this.currentPosition, edge.to, splitPoint.y);
		const remapped: float32 = remapTInRange(t, src.rangeStart, edge.rangeEnd);
		this.events.insertSorted(splitPoint, {
			...src, rangeStart: remapped, rangeEnd: edge.rangeEnd, winding: edge.winding,
			to: edge.to, isEdge: true,
		}, this.currentEventId);
	}
}

export function tessellateFill(
	points: Readonly<Span<Vec2>>,
	loopEnds: Readonly<Span<int32>>,
	rule: FillRule,
): FillTessellation {
	for (const p of points) {
		if (p.x != p.x || p.y != p.y) { refuse("got a NaN position"); }
	}
	const tess: FillTessellator = new FillTessellator(rule);
	const queue: EventQueue = tess.events;
	let start: int32 = 0;
	for (const end of loopEnds) {
		if (end > start) {
			queue.begin(points[start], start);
			for (let i: int32 = start + 1; i < end; i++) { queue.lineSegment(points[i], i); }
			queue.end(points[start], start);
		}
		start = end;
	}
	queue.sort();
	tess.run();
	return { positions: tess.positions, endpoints: tess.endpoints, triangles: tess.triangles };
}
