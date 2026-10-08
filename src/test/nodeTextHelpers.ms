import { NodeRef } from "../void2d/node";
import { calcTextWidth, splitText } from "../void2d/render";
import { describe } from "../void2d/textLayout";

export function nodeWidth(n: NodeRef, text: string): float32 {
	const width = n.calcTextWidth(text);
	if (width.ok) { return width.value; }
	console.log(`node text helper: the text was refused: ${width.error.describe()}`);
	unreachable;
}

export function nodeSplit(n: NodeRef, text: string): string {
	const split = n.splitText(text);
	if (split.ok) { return split.value; }
	console.log(`node text helper: the text was refused: ${split.error.describe()}`);
	unreachable;
}
