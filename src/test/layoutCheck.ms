import { NodeRef, Scene2D } from "../void2d/node";
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
