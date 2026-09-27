import "../../src/sokol/gpu";
import { NodeRef, Scene, NO_SLOT, NO_NODE } from "../../src/void2d/node";
import { scene, add } from "../../src/void2d/scene";
import { syncOrder } from "../../src/void2d/render";
import { rgba, identity2d, Transform2D } from "../../src/void2d/types";

const COLUMNS: int32 = 250;
const ROWS: int32 = 200;
const CELL_W: float32 = 5.12;
const CELL_H: float32 = 3.6;
const PASSES: int32 = 20;

struct Built {
	s: Scene;
	columns: NodeRef[];
	cards: NodeRef[];
}

function build(): Built {
	const s = scene(rgba(0.0, 0.0, 0.0, 1.0));
	const columns: NodeRef[] = [];
	const cards: NodeRef[] = [];
	for (let column: int32 = 0; column < COLUMNS; column++) {
		const group = s.group().at((column as float32) * CELL_W, 0.0);
		for (let row: int32 = 0; row < ROWS; row++) {
			const card = s.rect(CELL_W - 1.0, CELL_H - 1.0, rgba(0.2, 0.3, 0.5, 1.0))
				.at(0.0, (row as float32) * CELL_H);
			card.addChild(s.label(String((row * COLUMNS + column) % 100), 6.0, rgba(1.0, 1.0, 1.0, 1.0)));
			group.addChild(card);
			cards.push(card);
		}
		s.add(group);
		columns.push(group);
	}
	s.refreshOrder();
	s.syncOrder(identity2d(), true);
	s.clearChanges();
	return { s: s, columns: columns, cards: cards };
}

function descent(s: Scene): int32 {
	let visited: int32 = 0;
	for (let k: int32 = 0; k < (s.dirty.length as int32); k++) {
		const top: int32 = s.slots[s.dirty[k]];
		if (top == NO_SLOT) { continue; }
		const end: int32 = s.orderEnd[top];
		let p: int32 = top;
		while (p < end) {
			const i: int32 = s.order[p];
			const up: int32 = s.parents[i];
			const world: Transform2D = (p == 0 ? identity2d() : s.worlds[up]) * s.localMatrices[i];
			const alpha: float32 = (p == 0 ? 1.0 : s.alphas[up]) * s.paints[i].alpha;
			if (p > top && world == s.worlds[i] && alpha == s.alphas[i] && s.changed[i].isEmpty()) {
				p = s.orderEnd[p];
			} else {
				s.worlds[i] = world;
				s.alphas[i] = alpha;
				visited = visited + 1;
				p = p + 1;
			}
		}
	}
	return visited;
}

let marks: Vec<int32> = [];
let movedAt: Vec<int32> = [];
let serial: int32 = 0;

function upward(s: Scene): int32 {
	serial = serial + 1;
	while ((marks.length as int32) < (s.kinds.length as int32)) { marks.push(0); movedAt.push(0); }
	for (let k: int32 = 0; k < (s.dirty.length as int32); k++) {
		let up: int32 = s.dirty[k];
		if (s.slots[up] == NO_SLOT) { continue; }
		while (up != NO_NODE && marks[up] != serial) {
			marks[up] = serial;
			up = s.parents[up];
		}
	}
	let visited: int32 = 0;
	const n: int32 = s.order.length as int32;
	let p: int32 = 0;
	while (p < n) {
		const i: int32 = s.order[p];
		const up: int32 = s.parents[i];
		const parentMoved: boolean = p > 0 && movedAt[up] == serial;
		if (marks[i] != serial && !parentMoved) {
			p = s.orderEnd[p];
		} else {
			const world: Transform2D = (p == 0 ? identity2d() : s.worlds[up]) * s.localMatrices[i];
			const alpha: float32 = (p == 0 ? 1.0 : s.alphas[up]) * s.paints[i].alpha;
			if (world != s.worlds[i] || alpha != s.alphas[i]) { movedAt[i] = serial; }
			s.worlds[i] = world;
			s.alphas[i] = alpha;
			visited = visited + 1;
			p = p + 1;
		}
	}
	return visited;
}

function checksum(s: Scene): float64 {
	let sum: float64 = 0.0;
	for (let p: int32 = 0; p < (s.order.length as int32); p++) {
		sum = sum + (s.worlds[s.order[p]].tx as float64) + (s.worlds[s.order[p]].ty as float64);
	}
	return sum;
}

function writeSet(b: Built, which: int32, pass: int32): void {
	const x: float32 = (pass % 2) as float32;
	match (which) {
		0 => { b.cards[(b.cards.length as int32) / 2].setY(x + 3.0); },
		1 => {
			for (let k: int32 = 0; k < (b.cards.length as int32); k = k + 50) { b.cards[k].setY(x + 3.0); }
		},
		2 => { b.columns[COLUMNS / 2].setY(x); },
		3 => { for (const card of b.cards) { card.setY(x + 3.0); } },
		_ => { b.s.refOf(b.s.root).setY(x); },
	}
}

function run(name: string, which: int32, useUpward: boolean): float64 {
	const b: Built = build();
	let visited: int32 = 0;
	let ms: float64 = 0.0;
	for (let pass: int32 = 0; pass < PASSES; pass++) {
		writeSet(b, which, pass);
		const started: float64 = performance.now();
		visited = useUpward ? upward(b.s) : descent(b.s);
		ms = ms + (performance.now() - started);
		b.s.clearChanges();
	}
	const sum: float64 = checksum(b.s);
	console.log(
		`propagate ${name} ${useUpward ? "upward" : "descent"} visited ${visited} ` +
		`pass.ms ${ms / (PASSES as float64)} checksum ${sum}`,
	);
	return sum;
}

function main(): void {
	const names: string[] = ["oneCard", "every50th", "oneColumn", "allCards", "root"];
	for (let round: int32 = 0; round < 3; round++) {
		for (let which: int32 = 0; which < 5; which++) {
			const a: float64 = run(names[which], which, false);
			const b: float64 = run(names[which], which, true);
			if (a != b) { console.log(`propagate ${names[which]} the two disagree`); }
		}
	}
}

main();
