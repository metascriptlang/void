export const PAINT_UNDEF: int32 = -1;
export const PAINT_NONE: int32 = 0;
export const PAINT_COLOR: int32 = 1;
export const PAINT_LINEAR_GRADIENT: int32 = 2;
export const PAINT_RADIAL_GRADIENT: int32 = 3;

export const JOIN_MITER: int32 = 0;
export const JOIN_ROUND: int32 = 1;
export const JOIN_BEVEL: int32 = 2;

export const CAP_BUTT: int32 = 0;
export const CAP_ROUND: int32 = 1;
export const CAP_SQUARE: int32 = 2;

export const FILLRULE_NONZERO: int32 = 0;
export const FILLRULE_EVENODD: int32 = 1;

export const PAINT_ORDER_FILL: int32 = 0;
export const PAINT_ORDER_MARKERS: int32 = 1;
export const PAINT_ORDER_STROKE: int32 = 2;

export const MAX_DASHES: int32 = 8;

export class GradientStop {
	alpha: int32 = 0;
	offset: float32 = 0.0;
}

export class Gradient {
	xform: float32[] = [1, 0, 0, 1, 0, 0];
	stops: GradientStop[] = [];
}

// The rasterizer reads a colour paint's alpha only: the mask is the alpha channel.
export class Paint {
	kind: int32 = PAINT_NONE;
	alpha: int32 = 0;
	gradient: Gradient | null = null;
}

export class Path {
	pts: float32[] = [];
	npts: int32 = 0;
	closed: boolean = false;
	bounds: float32[] = [0, 0, 0, 0];
}

export class Shape {
	fill: Paint = new Paint();
	stroke: Paint = new Paint();
	opacity: float32 = 1.0;
	strokeWidth: float32 = 0.0;
	strokeDashOffset: float32 = 0.0;
	strokeDashArray: float32[] = [0, 0, 0, 0, 0, 0, 0, 0];
	strokeDashCount: int32 = 0;
	strokeLineJoin: int32 = 0;
	strokeLineCap: int32 = 0;
	miterLimit: float32 = 0.0;
	fillRule: int32 = 0;
	paintOrder: int32 = 0;
	visible: boolean = true;
	bounds: float32[] = [0, 0, 0, 0];
	fillGradient: uint8[] = [];
	strokeGradient: uint8[] = [];
	xform: float32[] = [1, 0, 0, 1, 0, 0];
	paths: Path[] = [];
}

export class SvgImage {
	width: float32 = 0.0;
	height: float32 = 0.0;
	shapes: Shape[] = [];
}
