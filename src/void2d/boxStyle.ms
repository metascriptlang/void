import { Color, rgba } from "./types";

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
	// The analytic shadow (GPUI's erf integral, no render target). A zero-alpha shadowColor
	// is no shadow; blur is the Gaussian sigma in local units; inset keeps it inside the box.
	shadowColor: Color;
	shadowBlur: float32;
	shadowOffsetX: float32;
	shadowOffsetY: float32;
	shadowInset: boolean;
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
	return {
		radii: radii,
		borders: borders,
		borderColor: borderColor,
		shadowColor: rgba(0.0, 0.0, 0.0, 0.0),
		shadowBlur: 0.0,
		shadowOffsetX: 0.0,
		shadowOffsetY: 0.0,
		shadowInset: false,
	};
}

// A drop shadow cast by the box: offset in local units, positive down-right. The colour's
// alpha is the strength.
export function castShadow(
	s: BoxStyle,
	color: Color,
	blur: float32,
	offsetX: float32,
	offsetY: float32,
): BoxStyle {
	const o: BoxStyle = s;
	o.shadowColor = color;
	o.shadowBlur = blur;
	o.shadowOffsetX = offsetX;
	o.shadowOffsetY = offsetY;
	o.shadowInset = false;
	return o;
}

// An inset shadow: the blurred hole's complement, clipped to the element.
export function castInsetShadow(s: BoxStyle, color: Color, blur: float32): BoxStyle {
	const o: BoxStyle = s;
	o.shadowColor = color;
	o.shadowBlur = blur;
	o.shadowOffsetX = 0.0;
	o.shadowOffsetY = 0.0;
	o.shadowInset = true;
	return o;
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
