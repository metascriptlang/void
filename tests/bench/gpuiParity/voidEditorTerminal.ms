import { env } from "std/process";
import { gfxSetup, fbWidth, fbHeight, dpiScale } from "../../../src/host/gpu";
import {
	setup2d, preparePipelines, uploadBytes, drawCallCount, droppedFrames,
	recordedUiInstanceCount, glyphUploadBytes,
} from "../../../src/void2d/draw";
import { Scene2D, NodeRef } from "../../../src/void2d/node";
import { create, add, present, close } from "../../../src/void2d/scene";
import { rgba, Color } from "../../../src/void2d/types";
import { BlendMode } from "../../../src/gpu/state";
import { FontId, DEFAULT_FONT, addFont } from "../../../src/void2d/font";
import { TextRun, UnderlineStyle } from "../../../src/void2d/textLayout";
import { glyphRasterizations, glyphRefusals } from "../../../src/void2d/labelText";
import { processCpuNs } from "./cpuTime.h";

@include("../../../src/host/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, samples: int32, highDpi: int32, init: () => void, frame: () => void,
): void;

const WARMUP: int32 = 20;
const MEASURED: int32 = 120;
const LINE: string = "let total = compute(alpha, beta) + table[index] * 3; // editor 0123456789";
const INK: Color = rgba(0.9, 0.9, 0.95, 1.0);
let kind: string = "";
let fontName: string = "";
let benchFont: FontId = DEFAULT_FONT;
let phases: string[] = [];
let scene: Scene2D | null = null;
let rows: NodeRef[] = [];
let area: NodeRef | null = null;
let phase: int32 = 0;
let within: int32 = 0;
let step: int32 = 0;
let previousStart: float64 = 0.0;
let previousCpu: uint64 = 0;
let previousPhase: int32 = -1;
let previousSample: int32 = -1;

function fail(message: string): void {
	console.log(`FAIL editorTerminal: ${message}`);
	process.exit(1);
}

function run(len: int32, colour: Color): TextRun {
	const clear: Color = rgba(0.0, 0.0, 0.0, 0.0);
	return {
		len: len, font: benchFont, color: colour, background: clear,
		underline: clear, underlineStyle: UnderlineStyle.Solid, strikethrough: clear,
		overline: clear,
	};
}

function setRow(n: NodeRef, seed: int32, length: int32, dense: boolean = false): void {
	let text: string = "";
	for (let i: int32 = 0; i < length; i++) {
		text += String.fromCharCode(33 + ((seed * 7 + i * 13) % 90));
	}
	n.setFont(benchFont).setText(text);
	if (dense) {
		let runs: TextRun[] = [];
		for (let i: int32 = 0; i < length; i++) {
			runs.push(run(1, i % 2 == 0 ? rgba(0.5, 0.8, 0.4, 1.0) : INK));
		}
		n.setTextRuns(runs);
	} else {
		const first: int32 = length / 3;
		n.setTextRuns([
			run(first, rgba(0.5, 0.8, 0.4, 1.0)), run(first, INK),
			run(length - 2 * first, rgba(0.8, 0.5, 0.9, 1.0)),
		]);
	}
}

function editorText(splice: boolean, changed: boolean): void {
	let text: string = "";
	let runs: TextRun[] = [];
	for (let i: int32 = 0; i < 200; i++) {
		const line: string = i == 10 && changed
			? (splice ? "x" + LINE : "var " + LINE.substring(4, LINE.length as int32)) : LINE;
		text += line + (i == 199 ? "" : "\n");
		runs.push(run(4, rgba(0.8, 0.5, 0.9, 1.0)));
		runs.push(run((line.length as int32) - 4 + (i == 199 ? 0 : 1), INK));
	}
	rows[0].setText(text).setTextRuns(runs);
}

function init(): void {
	kind = env.get("VOID_BENCH_CASE");
	if (!kind.equals("editor") && !kind.equals("terminal")) { fail(`unsupported case ${kind}`); }
	fontName = env.get("VOID_BENCH_FONT");
	if (fontName.equals("")) { fontName = kind.equals("terminal") ? "cascadia" : "inter"; }
	if (!fontName.equals("inter") && !fontName.equals("cascadia")) {
		fail(`unsupported font ${fontName}`);
	}
	gfxSetup();
	setup2d();
	if (fontName.equals("cascadia")) {
		const loaded = addFont("tests/fonts/cascadiaSubset.ttf");
		if (loaded.ok) { benchFont = loaded.value; }
		else { fail("cannot load tests/fonts/cascadiaSubset.ttf"); }
	}
	preparePipelines([BlendMode.Alpha]);
	const s: Scene2D = Scene2D.create(rgba(0.04, 0.05, 0.07, 1.0));
	scene = s;
	if (kind.equals("editor")) {
		const label: NodeRef = s.label("", 13.0, INK).at(8.0, 8.0).setFont(benchFont);
		rows.push(label);
		editorText(false, false);
		label.setCursorBlinkTime(0.0).setCursorIndex(10, INK);
		s.add(label);
		phases = ["still", "caret", "selection", "editSame", "splice"];
	} else {
		const mask: NodeRef = s.mask(1264.0, 704.0).at(8.0, 8.0);
		for (let i: int32 = 0; i < 60; i++) {
			const row: NodeRef = s.label("", 13.0, INK)
				.at(0.0, (i as float32) * 15.0).setForceWidth(8.0);
			setRow(row, i, 150);
			mask.addChild(row);
			rows.push(row);
		}
		s.add(mask);
		area = mask;
		phases = ["still", "oneRow", "spliceRow", "scroll", "recycle", "rewrite", "perCellRuns"];
	}
	console.log(`INFO runtimeBase=gpuiParity-macos case=${kind} font=${fontName}` +
		" size=13 viewport=1280x720 dpi=1");
	console.log("CPU_NS_WITH_HARNESS: own process CPU time (user+system, all threads, CLOCK_PROCESS_CPUTIME_ID, ns NOT cycles)" +
		" across complete callbacks/host present; includes sample logging/other own threads; not GPU time or WindowServer CPU");
	const only: string = env.get("VOID_BENCH_PHASES");
	if (!only.equals("")) {
		const wanted: string[] = only.split(",");
		let kept: string[] = [];
		for (let i: int32 = 0; i < (phases.length as int32); i++) {
			for (let k: int32 = 0; k < (wanted.length as int32); k++) {
				if (phases[i].equals(wanted[k])) { kept.push(phases[i]); }
			}
		}
		phases = kept;
	}
	console.log("COLUMNS SAMPLE case 0 phase sample paintMs presentMs totalMs uploadBytes drawCalls" +
		" glyphRasterizations glyphUploadBytes uiInstances intervalMs; CPU_NS_WITH_HARNESS case phase sample ns");
}

function mutate(): void {
	const name: string = phases[phase];
	if (name.equals("caret")) {
		if (within == 0) { rows[0].setCursorBlinkTime(0.01); }
		(scene as Scene2D).tick(0.01);
	} else if (name.equals("selection")) {
		rows[0].setSelectionRange({ start: 10, length: 200 + step % 20 }, rgba(0.3, 0.5, 0.9, 0.5));
	} else if (name.equals("editSame") || name.equals("splice")) {
		editorText(name.equals("splice"), step % 2 == 1);
	} else if (name.equals("oneRow") || name.equals("spliceRow")) {
		setRow(rows[step % 60], step + 1000, name.equals("spliceRow") && step % 2 == 1 ? 151 : 150);
	} else if (name.equals("scroll")) {
		(area as NodeRef).scrollTo(0.0, ((step * 37) % 200) as float32);
	} else if (name.equals("recycle")) {
		const mask: NodeRef = area as NodeRef;
		rows[0].dispose();
		rows.shift();
		const row: NodeRef = (scene as Scene2D).label("", 13.0, INK)
			.at(0.0, 59.0 * 15.0).setForceWidth(8.0);
		setRow(row, step + 1000, 150);
		mask.addChild(row);
		rows.push(row);
		for (let i: int32 = 0; i < 59; i++) { rows[i].at(0.0, (i as float32) * 15.0); }
	} else if (name.equals("rewrite") || name.equals("perCellRuns")) {
		for (let i: int32 = 0; i < 60; i++) {
			setRow(rows[i], step + i + 2000, 150, name.equals("perCellRuns"));
		}
	} else if (!name.equals("still")) { fail(`unsupported phase ${name}`); }
}

function frame(): void {
	const cpu: uint64 = processCpuNs();
	if (previousPhase >= 0) {
		if (cpu < previousCpu) { fail("process cpu counter moved backwards"); }
		console.log(`CPU_NS_WITH_HARNESS ${kind} ${phases[previousPhase]}` +
			` ${previousSample} ${cpu - previousCpu}`);
		previousPhase = -1;
	}
	if (scene === null) { fail("missing scene"); return; }
	if (phase >= (phases.length as int32)) {
		(scene as Scene2D).close();
		scene = null;
		rows = [];
		area = null;
		console.log("DONE finite benchmark");
		process.exit(0);
	}
	const beforeRaster: int32 = glyphRasterizations();
	const cpuStart: uint64 = processCpuNs();
	if (within >= WARMUP) {
		previousCpu = cpuStart;
		previousPhase = phase;
		previousSample = within - WARMUP;
	}
	if (previousStart == 0.0) { console.log(`FRAMEBUFFER ${fbWidth()}x${fbHeight()} dpiScale=${dpiScale()}`); }
	const started: float64 = performance.now();
	const interval: float64 = previousStart == 0.0 ? 0.0 : started - previousStart;
	previousStart = started;
	mutate();
	const painted: float64 = performance.now();
	(scene as Scene2D).present();
	const ended: float64 = performance.now();
	if (droppedFrames() != 0) { fail("renderer dropped a frame"); }
	if (glyphRefusals() != 0) { fail("glyph placement refused benchmark content"); }
	if (within >= WARMUP) {
		console.log(`SAMPLE ${kind} 0 ${phases[phase]} ${within - WARMUP} ${painted - started}` +
			` ${ended - painted} ${ended - started} ${uploadBytes()} ${drawCallCount()}` +
			` ${glyphRasterizations() - beforeRaster} ${glyphUploadBytes()}` +
			` ${recordedUiInstanceCount()} ${interval}`);
	}
	if (within == WARMUP + MEASURED - 1) {
		console.log(`PHASE_DONE ${kind} ${phases[phase]}`);
		phase += 1;
		within = 0;
	} else { within += 1; }
	step += 1;
}

voidRunConfigured(1280, 720, 1, 0, init, frame);
