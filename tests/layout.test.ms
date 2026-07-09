// Headless test for the Node2D flexbox layout pass (no GPU calls executed —
// sokol is linked but never initialized). Build from the void repo root:
//   msc build tests/layout.test.ms && ./out/debug/layout.test

import { Node2D, group, rect } from "../src/void2d/node";
import { layoutPass, freeLayout } from "../src/void2d/layout";
import { rgba } from "../src/void2d/types";
import { exit } from "std/process";

let checks: int32 = 0;
let failures: int32 = 0;

function expectEq(label: string, actual: float32, expected: float32): void {
	checks += 1;
	const d = actual - expected;
	const ok = d < 0.01 && d > -0.01;
	if (!ok) {
		failures += 1;
		console.log("FAIL " + label + ": expected " + expected.toString() + " got " + actual.toString());
	}
}

function white(): Node2D { return rect(10.0, 10.0, rgba(1.0, 1.0, 1.0, 1.0)); }

function sidebarLayout(): void {
	const sidebar = white();
	sidebar.layoutStyle = { width: 80.0 };
	const content = white();
	content.layoutStyle = { flexGrow: 1.0 };
	const root = group();
	root.layoutStyle = { flexDirection: "row" };
	root.addChild(sidebar);
	root.addChild(content);

	layoutPass(root, 320.0, 200.0);
	expectEq("sidebar.w", sidebar.w, 80.0);
	expectEq("content.x", content.x, 80.0);
	expectEq("content.w", content.w, 240.0);
	expectEq("content.h", content.h, 200.0);
	freeLayout(root);
}

function manualNodesStayManual(): void {
	const flexChild = white();
	flexChild.layoutStyle = { flexGrow: 1.0 };
	const manual = white();
	manual.x = 33.0; manual.y = 44.0;
	const root = group();
	root.layoutStyle = { flexDirection: "column", padding: 5.0 };
	root.addChild(flexChild);
	root.addChild(manual);

	layoutPass(root, 100.0, 100.0);
	expectEq("manual.x untouched", manual.x, 33.0);
	expectEq("manual.y untouched", manual.y, 44.0);
	expectEq("flexChild.x", flexChild.x, 5.0);
	expectEq("flexChild.h", flexChild.h, 90.0);
	freeLayout(root);
}

function restyleByFreshObject(): void {
	const a = white();
	a.layoutStyle = { height: 40.0 };
	const root = group();
	root.layoutStyle = { flexDirection: "column", width: 100.0, height: 200.0 };
	root.addChild(a);

	layoutPass(root, 100.0, 200.0);
	expectEq("restyle h0", a.h, 40.0);
	a.layoutStyle = { height: 70.0 };
	layoutPass(root, 100.0, 200.0);
	expectEq("restyle h1", a.h, 70.0);
	freeLayout(root);
}

function addChildBetweenPasses(): void {
	const a = white();
	a.layoutStyle = { flexGrow: 1.0 };
	const root = group();
	root.layoutStyle = { flexDirection: "column", width: 100.0, height: 100.0 };
	root.addChild(a);

	layoutPass(root, 100.0, 100.0);
	expectEq("grow-alone", a.h, 100.0);

	const b = white();
	b.layoutStyle = { flexGrow: 1.0 };
	root.addChild(b);
	layoutPass(root, 100.0, 100.0);
	expectEq("grow-split a.h", a.h, 50.0);
	expectEq("grow-split b.y", b.y, 50.0);
	expectEq("grow-split b.h", b.h, 50.0);
	freeLayout(root);
}

function stablePassIsNoop(): void {
	const a = white();
	a.layoutStyle = { flexGrow: 1.0 };
	const root = group();
	root.layoutStyle = { width: 50.0, height: 50.0 };
	root.addChild(a);
	layoutPass(root, 50.0, 50.0);
	a.x = 999.0;
	layoutPass(root, 50.0, 50.0);
	expectEq("stable pass leaves manual overwrite", a.x, 999.0);
	freeLayout(root);
}

function main(): void {
	sidebarLayout();
	manualNodesStayManual();
	restyleByFreshObject();
	addChildBetweenPasses();
	stablePassIsNoop();
	if (failures === 0) {
		console.log("void-layout PASS (" + checks.toString() + " checks)");
	} else {
		console.log("void-layout FAIL: " + failures.toString() + "/" + checks.toString());
		exit(1);
	}
}

main();
