// expect: text runs cover 2 UTF-16 units of a text of 3
import "../../src/sokol/gpu";
import { label } from "../../src/void2d/node";
import { sync } from "../../src/void2d/render";
import { DEFAULT_FONT } from "../../src/void2d/font";
import { TextRun } from "../../src/void2d/textLayout";
import { rgba, identity2d } from "../../src/void2d/types";

const clear = rgba(0.0, 0.0, 0.0, 0.0);
const runs: TextRun[] = [{
	len: 2, font: DEFAULT_FONT, color: rgba(1.0, 1.0, 1.0, 1.0), background: clear,
	underline: clear, wavy: false, strikethrough: clear,
}];
const n = label("abc", 13.0, rgba(1.0, 1.0, 1.0, 1.0));
n.setTextRuns(runs);
n.sync(identity2d(), false);
console.log(`a label whose runs miss a unit measured ${n.textWidth()}`);
