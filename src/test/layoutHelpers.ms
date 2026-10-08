import {
	ShapedText,
	TextError,
	TextLayout,
	TextRun,
	TextStyle,
	calcTextWidth,
	describe,
	layoutRuns,
	shapeText,
} from "../void2d/textLayout";
import { TextDirection } from "../void2d/textDirection";

function stopped(error: TextError): void {
	console.log(`layout helper: the text was refused: ${error.describe()}`);
	unreachable;
}

export function laid(text: string, style: TextStyle): TextLayout {
	const noRuns: Vec<TextRun> = new Array(0);
	return laidRuns(text, style, noRuns);
}

export function laidRuns(
	text: string, style: TextStyle, runs: Readonly<Span<TextRun>>,
): TextLayout {
	const l = layoutRuns(text, style, runs);
	if (l.ok) { return l.value; }
	stopped(l.error);
	unreachable;
}

export function shapedOf(
	text: string,
	style: TextStyle,
	runs: Readonly<Span<TextRun>>,
	breaks: Readonly<Span<int32>>,
): ShapedText {
	const shaped = shapeText(text, style, runs, breaks);
	if (shaped.ok) { return shaped.value; }
	stopped(shaped.error);
	unreachable;
}

export function shapedIn(
	text: string, style: TextStyle, direction: TextDirection,
): ShapedText {
	const noRuns: Vec<TextRun> = new Array(0);
	const noBreaks: Vec<int32> = new Array(0);
	const shaped = shapeText(text, style, noRuns, noBreaks, direction);
	if (shaped.ok) { return shaped.value; }
	stopped(shaped.error);
	unreachable;
}

export function widthOf(text: string, style: TextStyle): float32 {
	const width = calcTextWidth(text, style);
	if (width.ok) { return width.value; }
	stopped(width.error);
	unreachable;
}
