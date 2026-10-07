export enum ShapeDirection {
	Unknown,
	Ltr,
	Rtl,
}

export struct ShapedGlyph {
	glyph: int32;
	advanceX: int32;
	advanceY: int32;
	offsetX: int32;
	offsetY: int32;
	index: int32;
	codepoint: int32;
	direction: ShapeDirection;
	run: int32;
}

when (voidShaper) {
	import {
		void2dShapeBegin,
		void2dShapeFeature,
		void2dShapeCodepoint,
		void2dShapeBreak,
		void2dShapeEnd,
		void2dShapeCount,
		void2dShapeGlyph,
	} from "./shaper.h";

	function shapeStatus(code: int32, what: string): int32 {
		if (code >= 0) { return code; }
		const reason: string = match (code) {
			-1 => "the face is not loaded",
			-2 => "the shaper refused the font",
			-3 => "out of memory",
			-4 => "the shaper reported an error",
			-5 => "no shaping pass is open",
			-6 => "a shaping pass is already open",
			-7 => "a feature tag is four printable ASCII characters",
			-8 => "more than 32 feature overrides in one pass",
			_ => "unknown status",
		};
		console.log(`void2d shaper: ${what}: ${reason} (${code})`);
		unreachable;
	}

	export function shaperCompiled(): boolean { return true; }

	export function shaperBegin(face: int32, direction: ShapeDirection): void {
		shapeStatus(void2dShapeBegin(face, direction as int32), "begin");
	}

	export function shaperTryBegin(face: int32, direction: ShapeDirection): boolean {
		const status: int32 = void2dShapeBegin(face, direction as int32);
		if (status == -1 || status == -2) { return false; }
		shapeStatus(status, "begin");
		return true;
	}

	export function shaperFeature(tag: string, value: int32): void {
		shapeStatus(void2dShapeFeature(tag, value), `feature ${tag}`);
	}

	export function shaperCodepoint(codepoint: int32): void {
		shapeStatus(void2dShapeCodepoint(codepoint), "codepoint");
	}

	export function shaperBreak(): void {
		shapeStatus(void2dShapeBreak(), "break");
	}

	export function shaperEnd(): int32 {
		return shapeStatus(void2dShapeEnd(), "end");
	}

	export function shaperGlyph(index: int32): ShapedGlyph {
		const count: int32 = void2dShapeCount();
		if (index < 0 || index >= count) {
			console.log(`void2d shaper: glyph ${index} is outside the ${count} of the last pass`);
			unreachable;
		}
		const g: Ptr<int32> = void2dShapeGlyph(index);
		return {
			glyph: g[0],
			advanceX: g[1],
			advanceY: g[2],
			offsetX: g[3],
			offsetY: g[4],
			index: g[5],
			codepoint: g[6],
			direction: g[7] as ShapeDirection,
			run: g[8],
		};
	}
} else {
	function shaperOff(what: string): void {
		console.log(`void2d shaper: ${what} needs the shaper module; build with -d:voidShaper`);
		unreachable;
	}

	export function shaperCompiled(): boolean { return false; }

	export function shaperBegin(face: int32, direction: ShapeDirection): void {
		shaperOff("shaperBegin");
	}

	export function shaperTryBegin(face: int32, direction: ShapeDirection): boolean {
		shaperOff("shaperTryBegin");
		return false;
	}

	export function shaperFeature(tag: string, value: int32): void {
		shaperOff("shaperFeature");
	}

	export function shaperCodepoint(codepoint: int32): void {
		shaperOff("shaperCodepoint");
	}

	export function shaperBreak(): void {
		shaperOff("shaperBreak");
	}

	export function shaperEnd(): int32 {
		shaperOff("shaperEnd");
		return 0;
	}

	export function shaperGlyph(index: int32): ShapedGlyph {
		shaperOff("shaperGlyph");
		unreachable;
	}
}
