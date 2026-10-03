import { NodeRef, Scene2D, layoutGetYg } from "../void2d/node";
import "../void2d/scene";
import { layoutPass, freeLayout } from "../void2d/layout";
import { rgba } from "../void2d/types";
import { approx } from "./helpers";

const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));

function white(): NodeRef { return s.rect(10.0, 10.0, rgba(1.0, 1.0, 1.0, 1.0)); }

test "a fixed sidebar and a growing content split a row" {
	const sidebar = white();
	sidebar.setLayoutStyle({ width: 80.0 });
	const content = white();
	content.setLayoutStyle({ flexGrow: 1.0 });
	const root = s.group();
	root.setLayoutStyle({ flexDirection: "row" });
	root.addChild(sidebar);
	root.addChild(content);

	layoutPass(root, 320.0, 200.0);
	assert approx(sidebar.content().w, 80.0);
	assert approx(content.local().x, 80.0);
	assert approx(content.content().w, 240.0);
	assert approx(content.content().h, 200.0);
	freeLayout(root);
}

test "a node without a layout style keeps its manual position" {
	const flexChild = white();
	flexChild.setLayoutStyle({ flexGrow: 1.0 });
	const manual = white();
	manual.at(33.0, 44.0);
	const root = s.group();
	root.setLayoutStyle({ flexDirection: "column", padding: 5.0 });
	root.addChild(flexChild);
	root.addChild(manual);

	layoutPass(root, 100.0, 100.0);
	assert approx(manual.local().x, 33.0);
	assert approx(manual.local().y, 44.0);
	assert approx(flexChild.local().x, 5.0);
	assert approx(flexChild.content().h, 90.0);
	freeLayout(root);
}

test "a fresh style object restyles the node on the next pass" {
	const a = white();
	a.setLayoutStyle({ height: 40.0 });
	const root = s.group();
	root.setLayoutStyle({ flexDirection: "column", width: 100.0, height: 200.0 });
	root.addChild(a);

	layoutPass(root, 100.0, 200.0);
	assert approx(a.content().h, 40.0);
	a.setLayoutStyle({ height: 70.0 });
	layoutPass(root, 100.0, 200.0);
	assert approx(a.content().h, 70.0);
	freeLayout(root);
}

test "a child added between passes takes its share of the growth" {
	const a = white();
	a.setLayoutStyle({ flexGrow: 1.0 });
	const root = s.group();
	root.setLayoutStyle({ flexDirection: "column", width: 100.0, height: 100.0 });
	root.addChild(a);

	layoutPass(root, 100.0, 100.0);
	assert approx(a.content().h, 100.0);

	const b = white();
	b.setLayoutStyle({ flexGrow: 1.0 });
	root.addChild(b);
	layoutPass(root, 100.0, 100.0);
	assert approx(a.content().h, 50.0);
	assert approx(b.local().y, 50.0);
	assert approx(b.content().h, 50.0);
	freeLayout(root);
}

test "a pass over an unchanged tree leaves a manual overwrite alone" {
	const a = white();
	a.setLayoutStyle({ flexGrow: 1.0 });
	const root = s.group();
	root.setLayoutStyle({ width: 50.0, height: 50.0 });
	root.addChild(a);
	layoutPass(root, 50.0, 50.0);
	a.setX(999.0);
	layoutPass(root, 50.0, 50.0);
	assert approx(a.local().x, 999.0);
	freeLayout(root);
}

test "a removed node gives up its Yoga node and takes a fresh one when added back" {
	const a = white();
	a.setLayoutStyle({ height: 40.0 });
	const b = white();
	b.setLayoutStyle({ height: 60.0 });
	const root = s.group();
	root.setLayoutStyle({ flexDirection: "column", width: 100.0, height: 200.0 });
	root.addChild(a);
	root.addChild(b);
	layoutPass(root, 100.0, 200.0);
	assert a.layoutGetYg() !== null;

	root.removeChild(a);
	assert a.layoutGetYg() === null;
	layoutPass(root, 100.0, 200.0);
	assert approx(b.local().y, 0.0);

	root.addChild(a);
	layoutPass(root, 100.0, 200.0);
	assert a.layoutGetYg() !== null;
	assert approx(a.local().y, 60.0);
	freeLayout(root);
}

test "removeChildren and remove give up the Yoga nodes of every laid-out descendant" {
	const leaf = white();
	leaf.setLayoutStyle({ height: 10.0 });
	const branch = s.group();
	branch.setLayoutStyle({ flexDirection: "column" });
	branch.addChild(leaf);
	const sibling = white();
	sibling.setLayoutStyle({ height: 10.0 });
	const root = s.group();
	root.setLayoutStyle({ flexDirection: "column", width: 100.0, height: 100.0 });
	root.addChild(branch);
	root.addChild(sibling);
	layoutPass(root, 100.0, 100.0);
	assert leaf.layoutGetYg() !== null;

	branch.remove();
	assert branch.layoutGetYg() === null;
	assert leaf.layoutGetYg() === null;
	assert sibling.layoutGetYg() !== null;

	root.removeChildren();
	assert sibling.layoutGetYg() === null;
	assert root.layoutGetYg() !== null;
	layoutPass(root, 100.0, 100.0);
	freeLayout(root);
}

test "a node moved to another laid-out parent in one frame does not trip Yoga's single owner" {
	const x = white();
	x.setLayoutStyle({ height: 20.0 });
	const from = s.group();
	from.setLayoutStyle({ height: 100.0 });
	from.addChild(x);
	const to = s.group();
	to.setLayoutStyle({ height: 100.0 });
	const root = s.group();
	root.setLayoutStyle({ flexDirection: "column", width: 100.0, height: 200.0 });
	root.addChild(to);
	root.addChild(from);
	layoutPass(root, 100.0, 200.0);
	assert approx(x.content().h, 20.0);

	to.addChild(x);
	layoutPass(root, 100.0, 200.0);
	assert from.numChildren() == 0;
	assert to.numChildren() == 1;
	assert approx(x.content().h, 20.0);
	assert approx(x.local().y, 0.0);
	freeLayout(root);
}

test "adding a child again under its own parent keeps its Yoga node" {
	const a = white();
	a.setLayoutStyle({ height: 30.0 });
	const b = white();
	b.setLayoutStyle({ height: 30.0 });
	const root = s.group();
	root.setLayoutStyle({ flexDirection: "column", width: 100.0, height: 100.0 });
	root.addChild(a);
	root.addChild(b);
	layoutPass(root, 100.0, 100.0);
	const before = a.layoutGetYg();
	assert before !== null;

	root.addChild(a);
	layoutPass(root, 100.0, 100.0);
	assert a.layoutGetYg() === before;
	assert approx(b.local().y, 0.0);
	assert approx(a.local().y, 30.0);
	freeLayout(root);
}

test "a disposed laid-out child leaves its siblings laid out" {
	const a = white();
	a.setLayoutStyle({ height: 40.0 });
	const b = white();
	b.setLayoutStyle({ height: 60.0 });
	const root = s.group();
	root.setLayoutStyle({ flexDirection: "column", width: 100.0, height: 200.0 });
	root.addChild(a);
	root.addChild(b);
	layoutPass(root, 100.0, 200.0);
	a.dispose();
	layoutPass(root, 100.0, 200.0);
	assert approx(b.local().y, 0.0);
	assert approx(b.content().h, 60.0);
	freeLayout(root);
}
