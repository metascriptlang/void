import { Color } from "./types";

export const NO_BOX_STYLE: int32 = -1;

export struct CornerRadii {
	topLeft: float32;
	topRight: float32;
	bottomRight: float32;
	bottomLeft: float32;
}

export struct BorderWidths {
	left: float32;
	top: float32;
	right: float32;
	bottom: float32;
}

export struct BoxStyle {
	radii: CornerRadii;
	borders: BorderWidths;
	borderColor: Color;
}

export function cornerRadii(
	topLeft: float32,
	topRight: float32,
	bottomRight: float32,
	bottomLeft: float32,
): CornerRadii {
	return {
		topLeft: topLeft,
		topRight: topRight,
		bottomRight: bottomRight,
		bottomLeft: bottomLeft,
	};
}

export function uniformRadii(radius: float32): CornerRadii {
	return cornerRadii(radius, radius, radius, radius);
}

export function borderWidths(
	left: float32,
	top: float32,
	right: float32,
	bottom: float32,
): BorderWidths {
	return { left: left, top: top, right: right, bottom: bottom };
}

export function uniformBorders(width: float32): BorderWidths {
	return borderWidths(width, width, width, width);
}

export function boxStyle(
	radii: CornerRadii,
	borders: BorderWidths,
	borderColor: Color,
): BoxStyle {
	return { radii: radii, borders: borders, borderColor: borderColor };
}

export const boxStyles: Vec<BoxStyle> = [];
const freeBoxStyles: Vec<int32> = [];

export function allocateBoxStyle(style: BoxStyle): int32 {
	const freeCount: int32 = freeBoxStyles.length as int32;
	if (freeCount > 0) {
		const index: int32 = freeBoxStyles[freeCount - 1];
		freeBoxStyles.pop();
		boxStyles[index] = style;
		return index;
	}
	const index: int32 = boxStyles.length as int32;
	boxStyles.push(style);
	return index;
}

export function updateBoxStyle(index: int32, style: BoxStyle): void {
	boxStyles[index] = style;
}

export function releaseBoxStyle(index: int32): void {
	if (index == NO_BOX_STYLE) { return; }
	freeBoxStyles.push(index);
}
