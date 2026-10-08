// Run in a process of its own (scripts/gate.sh): it reads the process heap, which every other
// test in src/test/index.ms would move.

import { Scene2D, NodeRef } from "../../src/void2d/node";
import "../../src/void2d/scene";
import { layoutPass, freeLayout } from "../../src/void2d/layout";
import { rgba } from "../../src/void2d/types";

@compile("./heapBlocks.c");
@include("./heapBlocks.h");
extern function heapBlocksInUse(): int64;

const WINDOW: int32 = 50;
const WINDOWS: int32 = 8;
const WARMUP: int32 = 8;
const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));

enum Drop {
	DisposeAttached,
	RemoveThenDispose,
	RemoveChildrenThenDispose,
	DisposeLaidOutRoot,
}

function column(): NodeRef {
	const n = s.group();
	n.setLayoutStyle({ flexDirection: "column", width: 100.0, height: 100.0 });
	return n;
}

function cycle(drop: Drop): void {
	const root = column();
	const branch = column();
	const leaf = column();
	branch.addChild(leaf);
	root.addChild(branch);
	layoutPass(root, 100.0, 100.0);
	match (drop) {
		Drop.DisposeAttached => {
			branch.dispose();
			layoutPass(root, 100.0, 100.0);
			freeLayout(root);
			root.dispose();
		},
		Drop.RemoveThenDispose => {
			root.removeChild(branch);
			layoutPass(root, 100.0, 100.0);
			branch.dispose();
			freeLayout(root);
			root.dispose();
		},
		Drop.RemoveChildrenThenDispose => {
			root.removeChildren();
			layoutPass(root, 100.0, 100.0);
			branch.dispose();
			freeLayout(root);
			root.dispose();
		},
		Drop.DisposeLaidOutRoot => {
			root.dispose();
		},
	}
}

function leaksNothing(drop: Drop): boolean {
	if (heapBlocksInUse() < 0) {
		console.log("SKIP yogaLeak: no allocator statistics on this platform");
		return true;
	}
	for (let i: int32 = 0; i < WARMUP; i++) { cycle(drop); }
	let quietest: int64 = 1000000;
	for (let w: int32 = 0; w < WINDOWS; w++) {
		const before: int64 = heapBlocksInUse();
		for (let i: int32 = 0; i < WINDOW; i++) { cycle(drop); }
		quietest = Math.min(quietest, heapBlocksInUse() - before);
	}
	console.log(`yogaLeak: ${drop.toString()} grew the heap by ${quietest} blocks in its quietest ` +
		`window of ${WINDOW} cycles`);
	return quietest < (WINDOW as int64);
}

test "a laid-out node disposed while attached leaves no Yoga node behind" {
	assert leaksNothing(Drop.DisposeAttached);
}

test "a laid-out node removed and then disposed leaves no Yoga node behind" {
	assert leaksNothing(Drop.RemoveThenDispose);
}

test "removeChildren then dispose leaves no Yoga node behind" {
	assert leaksNothing(Drop.RemoveChildrenThenDispose);
}

test "a laid-out root disposed without freeLayout leaves no Yoga node behind" {
	assert leaksNothing(Drop.DisposeLaidOutRoot);
}
