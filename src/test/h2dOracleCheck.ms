import { readFile } from "std/fs";
import { JsonValue } from "std/serialize/json/types";
import { scene, add, paint, setScaleMode, sceneViewMatrix } from "../void2d/scene";
import { Scene, NodeRef } from "../void2d/node";
import { getBounds } from "../void2d/render";
import { frameEnd } from "../void2d/draw";
import { Bounds, Vec2, Transform2D, ScaleMode, vec2, tile, emptyBounds } from "../void2d/types";

const ORACLE_PATH: string = "tests/oracle/h2d.json";
const PENDING_PATH: string = "tests/PENDING.md";
const TOLERANCE: float64 = 0.001;
const VIEW_W: float32 = 256.0;
const VIEW_H: float32 = 256.0;

function field(spec: JsonValue, name: string, fallback: float32): float32 {
	return spec.getDynamicField(name).asNumber(fallback as float64) as float32;
}

function build(s: Scene, spec: JsonValue, parent: NodeRef | null, ref nodes: Vec<NodeRef>): void {
	const kind: string = spec.getDynamicField("kind").asString();
	const w: float32 = field(spec, "w", 0.0);
	const h: float32 = field(spec, "h", 0.0);
	let n: NodeRef = s.group();
	if (kind.equals("bitmap")) {
		n.remove();
		n = s.sprite({ ...tile(0, w, h), dx: field(spec, "dx", 0.0), dy: field(spec, "dy", 0.0) });
	} else if (kind.equals("mask")) {
		n.remove();
		n = s.mask(w, h);
	}
	n.setX(field(spec, "x", 0.0)).setY(field(spec, "y", 0.0));
	n.setScaleX(field(spec, "scaleX", 1.0)).setScaleY(field(spec, "scaleY", 1.0));
	n.setRotation(field(spec, "rotation", 0.0));
	n.setVisible(spec.getDynamicField("visible").asBoolean(true));
	if (parent === null) { s.add(n); } else { (parent as NodeRef).addChild(n); }
	nodes.push(n);
	if (kind.equals("mask")) {
		const b = spec.getDynamicField("scrollBounds");
		if ((b.length() as int32) == 4) {
			n.setScrollBounds({
				xMin: b.at(0).asNumber() as float32, yMin: b.at(1).asNumber() as float32,
				xMax: b.at(2).asNumber() as float32, yMax: b.at(3).asNumber() as float32,
			});
		}
		n.scrollTo(field(spec, "scrollX", 0.0), field(spec, "scrollY", 0.0));
	}
	const children = spec.getDynamicField("children");
	for (let k: int32 = 0; k < (children.length() as int32); k++) {
		build(s, children.at(k), n, nodes);
	}
}

let compared: int32 = 0;
let differing: Vec<string> = [];

function agree(where: string, oracle: JsonValue, index: int32, actual: float32): boolean {
	compared = compared + 1;
	const expected: float64 = oracle.at(index).asNumber();
	if (Math.abs(expected - (actual as float64)) <= TOLERANCE) { return true; }
	console.log(`h2d oracle: ${where}[${index}]: h2d ${expected}, void2d ${actual}`);
	return false;
}

function agreePoint(where: string, oracle: JsonValue, p: Vec2): boolean {
	const x: boolean = agree(where, oracle, 0, p.x);
	const y: boolean = agree(where, oracle, 1, p.y);
	return x && y;
}

function pendingIds(): string {
	const text = readFile(PENDING_PATH);
	return text.ok ? text.value : "";
}

test "h2d's getBounds, localToGlobal and globalToLocal, over Heaps compiled to JS" {
	const text = readFile(ORACLE_PATH);
	assert text.ok;
	const parsed = JSON.parseValue(text.value);
	assert parsed.ok;
	const cases = parsed.value.getDynamicField("cases");
	const pending: string = pendingIds();
	compared = 0;
	let unlisted: int32 = 0;
	let graduated: int32 = 0;
	let agreeing: int32 = 0;
	for (let c: int32 = 0; c < (cases.length() as int32); c++) {
		const row = cases.at(c);
		const name: string = row.getDynamicField("name").asString();
		const s = scene({ r: 0.0, g: 0.0, b: 0.0, a: 1.0 });
		let nodes: Vec<NodeRef> = [];
		build(s, row.getDynamicField("tree"), null, nodes);
		let same: boolean = true;
		const results = row.getDynamicField("results");
		for (let k: int32 = 0; k < (nodes.length as int32); k++) {
			const r = results.at(k);
			const where: string = `${name} node ${k}`;
			if (!agreePoint(`${where} localToGlobal(0,0)`, r.getDynamicField("origin"),
				nodes[k].localToGlobal(vec2(0.0, 0.0)))) { same = false; }
			if (!agreePoint(`${where} localToGlobal(3,7)`, r.getDynamicField("corner"),
				nodes[k].localToGlobal(vec2(3.0, 7.0)))) { same = false; }
			if (!agreePoint(`${where} globalToLocal(20,30)`, r.getDynamicField("local"),
				nodes[k].globalToLocal(vec2(20.0, 30.0)))) { same = false; }
		}
		s.paint(VIEW_W, VIEW_H, 1.0);
		frameEnd();
		s.clearChanges();
		for (let k: int32 = 0; k < (nodes.length as int32); k++) {
			let b: Bounds = emptyBounds();
			nodes[k].getBounds(b);
			const oracle = results.at(k).getDynamicField("bounds");
			const where: string = `${name} node ${k} getBounds`;
			const x0: boolean = agree(where, oracle, 0, b.xMin);
			const y0: boolean = agree(where, oracle, 1, b.yMin);
			const x1: boolean = agree(where, oracle, 2, b.xMax);
			const y1: boolean = agree(where, oracle, 3, b.yMax);
			if (!(x0 && y0 && x1 && y1)) { same = false; }
		}
		const listed: boolean = pending.includes(`| h2d:${name} |`);
		if (same) { agreeing = agreeing + 1; }
		if (same && listed) {
			graduated = graduated + 1;
			console.log(`h2d oracle: ${name} agrees and is still listed in ${PENDING_PATH}`);
		}
		if (!same && !listed) {
			unlisted = unlisted + 1;
			console.log(`h2d oracle: ${name} differs and has no ${PENDING_PATH} entry h2d:${name}`);
		}
	}
	console.log(`h2d oracle: ${agreeing}/${cases.length()} cases agree, ${compared} values compared`);
	assert (cases.length() as int32) > 0;
	assert unlisted == 0;
	assert graduated == 0;
}

function scaleModeNamed(name: string): ScaleMode {
	if (name.equals("Stretch")) { return ScaleMode.Stretch; }
	if (name.equals("LetterBox")) { return ScaleMode.LetterBox; }
	if (name.equals("Fixed")) { return ScaleMode.Fixed; }
	if (name.equals("Zoom")) { return ScaleMode.Zoom; }
	if (name.equals("AutoZoom")) { return ScaleMode.AutoZoom; }
	return ScaleMode.Resize;
}

test "h2d's scale modes map the scene onto the window as checkResize does" {
	const text = readFile(ORACLE_PATH);
	assert text.ok;
	const parsed = JSON.parseValue(text.value);
	assert parsed.ok;
	const rows = parsed.value.getDynamicField("scaleModes");
	const pending: string = pendingIds();
	const names: string[] = ["Resize", "Stretch", "LetterBox", "Fixed", "Zoom", "AutoZoom"];
	compared = 0;
	let unlisted: int32 = 0;
	let graduated: int32 = 0;
	let agreeing: int32 = 0;
	for (const name of names) {
		let same: boolean = true;
		for (let r: int32 = 0; r < (rows.length() as int32); r++) {
			const row = rows.at(r);
			if (!row.getDynamicField("name").asString().equals(name)) { continue; }
			const design = row.getDynamicField("design");
			const window = row.getDynamicField("window");
			const w: float32 = window.at(0).asNumber() as float32;
			const h: float32 = window.at(1).asNumber() as float32;
			const s = scene({ r: 0.0, g: 0.0, b: 0.0, a: 1.0 });
			s.setScaleMode(scaleModeNamed(name), design.at(0).asNumber() as float32,
				design.at(1).asNumber() as float32);
			const m: Transform2D = sceneViewMatrix(s, w, h);
			const where: string = `scale mode ${name} at ${w}x${h}`;
			const scale = row.getDynamicField("scale");
			const offset = row.getDynamicField("offset");
			const sx: boolean = agree(`${where} scale`, scale, 0, m.a);
			const sy: boolean = agree(`${where} scale`, scale, 1, m.d);
			const ox: boolean = agree(`${where} offset`, offset, 0, m.tx);
			const oy: boolean = agree(`${where} offset`, offset, 1, m.ty);
			if (!(sx && sy && ox && oy)) { same = false; }
		}
		const listed: boolean = pending.includes(`| h2d:scale-${name} |`);
		if (same) { agreeing = agreeing + 1; }
		if (same && listed) {
			graduated = graduated + 1;
			console.log(`h2d oracle: scale mode ${name} agrees and is still listed in ${PENDING_PATH}`);
		}
		if (!same && !listed) {
			unlisted = unlisted + 1;
			console.log(`h2d oracle: scale mode ${name} differs and has no ${PENDING_PATH} entry h2d:scale-${name}`);
		}
	}
	console.log(`h2d oracle: ${agreeing}/${names.length} scale modes agree, ${compared} values compared`);
	assert unlisted == 0;
	assert graduated == 0;
}
