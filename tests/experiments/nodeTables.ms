import "../../src/sokol/gpu";
import { NodeRef, Scene } from "../../src/void2d/node";
import { scene, add } from "../../src/void2d/scene";
import { rgba } from "../../src/void2d/types";

const COLUMNS: int32 = 250;
const ROWS: int32 = 200;
const CELL_W: float32 = 5.12;
const CELL_H: float32 = 3.6;
const ROUNDS: int32 = 5;
const WRITE_PASSES: int32 = 4;

function build(s: Scene, cards: NodeRef[]): void {
	for (let row: int32 = 0; row < ROWS; row++) {
		for (let column: int32 = 0; column < COLUMNS; column++) {
			const card = s.rect(CELL_W - 1.0, CELL_H - 1.0, rgba(0.2, 0.3, 0.5, 1.0))
				.at((column as float32) * CELL_W, (row as float32) * CELL_H);
			const name: string = String((row * COLUMNS + column) % 100);
			card.addChild(s.label(name, 6.0, rgba(1.0, 1.0, 1.0, 1.0)));
			s.add(card);
			cards.push(card);
		}
	}
}

function writes(cards: NodeRef[], pass: int32): void {
	const x: float32 = (pass % 2) as float32;
	for (const card of cards) { card.setX(x); }
}

function visit(cards: NodeRef[]): int32 {
	let sum: int32 = 0;
	for (const card of cards) { sum = sum + card.id.index; }
	return sum;
}

function main(): void {
	for (let round: int32 = 0; round < ROUNDS; round++) {
		const s = scene(rgba(0.0, 0.0, 0.0, 1.0));
		const cards: NodeRef[] = [];
		const built: float64 = performance.now();
		build(s, cards);
		const buildMs: float64 = performance.now() - built;
		s.clearChanges();
		const written: float64 = performance.now();
		for (let pass: int32 = 0; pass < WRITE_PASSES; pass++) { writes(cards, pass); }
		const writeMs: float64 = performance.now() - written;
		const visited: float64 = performance.now();
		let checksum: int32 = 0;
		for (let pass: int32 = 0; pass < WRITE_PASSES; pass++) {
			checksum = checksum + visit(cards);
		}
		const visitMs: float64 = performance.now() - visited;
		const equal: float64 = performance.now();
		writes(cards, WRITE_PASSES - 1);
		const equalMs: float64 = performance.now() - equal;
		const torn: float64 = performance.now();
		s.refOf(s.root).removeChildren();
		for (const card of cards) { card.dispose(); }
		const teardownMs: float64 = performance.now() - torn;
		const count: float64 = cards.length as float64;
		console.log(
			`nodeTables round ${round} nodes ${s.kinds.length - 1} build.ms ${buildMs} ` +
			`write.ns ${writeMs * 1000000.0 / (count * (WRITE_PASSES as float64))} ` +
			`visit.ns ${visitMs * 1000000.0 / (count * (WRITE_PASSES as float64))} ` +
			`checksum ${checksum} ` +
			`equalWrite.ns ${equalMs * 1000000.0 / count} teardown.ms ${teardownMs} ` +
			`live ${s.nodeCount()}`,
		);
	}
}

main();
