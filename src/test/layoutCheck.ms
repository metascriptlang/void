import { Node2D, group, rect, addChild } from "../void2d/node";
import { layoutPass, freeLayout } from "../void2d/layout";
import { rgba } from "../void2d/types";
import { approx } from "./helpers";

function white(): Node2D { return rect(10.0, 10.0, rgba(1.0, 1.0, 1.0, 1.0)); }

test "a fixed sidebar and a growing content split a row" {
	const sidebar = white();
	sidebar.layoutStyle = { width: 80.0 };
	const content = white();
	content.layoutStyle = { flexGrow: 1.0 };
	const root = group();
	root.layoutStyle = { flexDirection: "row" };
	root.addChild(sidebar);
	root.addChild(content);

	layoutPass(root, 320.0, 200.0);
	assert approx(sidebar.w, 80.0);
	assert approx(content.x, 80.0);
	assert approx(content.w, 240.0);
	assert approx(content.h, 200.0);
	freeLayout(root);
}

test "a node without a layout style keeps its manual position" {
	const flexChild = white();
	flexChild.layoutStyle = { flexGrow: 1.0 };
	const manual = white();
	manual.x = 33.0;
	manual.y = 44.0;
	const root = group();
	root.layoutStyle = { flexDirection: "column", padding: 5.0 };
	root.addChild(flexChild);
	root.addChild(manual);

	layoutPass(root, 100.0, 100.0);
	assert approx(manual.x, 33.0);
	assert approx(manual.y, 44.0);
	assert approx(flexChild.x, 5.0);
	assert approx(flexChild.h, 90.0);
	freeLayout(root);
}

test "a fresh style object restyles the node on the next pass" {
	const a = white();
	a.layoutStyle = { height: 40.0 };
	const root = group();
	root.layoutStyle = { flexDirection: "column", width: 100.0, height: 200.0 };
	root.addChild(a);

	layoutPass(root, 100.0, 200.0);
	assert approx(a.h, 40.0);
	a.layoutStyle = { height: 70.0 };
	layoutPass(root, 100.0, 200.0);
	assert approx(a.h, 70.0);
	freeLayout(root);
}

test "a child added between passes takes its share of the growth" {
	const a = white();
	a.layoutStyle = { flexGrow: 1.0 };
	const root = group();
	root.layoutStyle = { flexDirection: "column", width: 100.0, height: 100.0 };
	root.addChild(a);

	layoutPass(root, 100.0, 100.0);
	assert approx(a.h, 100.0);

	const b = white();
	b.layoutStyle = { flexGrow: 1.0 };
	root.addChild(b);
	layoutPass(root, 100.0, 100.0);
	assert approx(a.h, 50.0);
	assert approx(b.y, 50.0);
	assert approx(b.h, 50.0);
	freeLayout(root);
}

test "a pass over an unchanged tree leaves a manual overwrite alone" {
	const a = white();
	a.layoutStyle = { flexGrow: 1.0 };
	const root = group();
	root.layoutStyle = { width: 50.0, height: 50.0 };
	root.addChild(a);
	layoutPass(root, 50.0, 50.0);
	a.x = 999.0;
	layoutPass(root, 50.0, 50.0);
	assert approx(a.x, 999.0);
	freeLayout(root);
}
