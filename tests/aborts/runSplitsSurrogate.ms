// expect: text run 1 starts inside the surrogate pair at 1
import "../../src/sokol/gpu";
import { label } from "../../src/void2d/node";
import { sync } from "../../src/void2d/render";
import { DEFAULT_FONT } from "../../src/void2d/font";
import { TextRun } from "../../src/void2d/textLayout";
import { rgba, identity2d } from "../../src/void2d/types";

const clear = rgba(0.0, 0.0, 0.0, 0.0);
const white = rgba(1.0, 1.0, 1.0, 1.0);
const runs: TextRun[] = [
	{
		len: 2, font: DEFAULT_FONT, color: white, background: clear, underline: clear,
		wavy: false, strikethrough: clear,
	},
	{
		len: 2, font: DEFAULT_FONT, color: white, background: clear, underline: clear,
		wavy: false, strikethrough: clear,
	},
];
const n = label("a😀b", 13.0, white);
n.setTextRuns(runs);
n.sync(identity2d(), false);
console.log(`a label whose second run starts inside a surrogate pair measured ${n.textWidth()}`);
