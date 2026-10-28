export enum SvgMaskError {
	Unparsable,
	Unsupported,
	NoSize,
	BadSize,
	TooLarge,
	OutOfMemory,
}

export struct SvgMaskRefusal {
	error: SvgMaskError;
	what: string;
}

export struct SvgMaskSource {
	handle: int32;
	width: float32;
	height: float32;
}

export const MAX_SVG_MASK_SIDE: int32 = 8192;

when (voidSvg) {
	import {
		maskFree,
		maskImageOf,
		maskLive,
		maskParse,
		maskParsed,
		maskRasterize,
		maskReason,
		maskReleased,
	} from "./svg/mask";

	function refusalOf(code: int32): SvgMaskRefusal {
		const what: string = maskReason();
		const error: SvgMaskError = match (code) {
			-1 => SvgMaskError.Unparsable,
			-2 => SvgMaskError.Unsupported,
			-3 => SvgMaskError.NoSize,
			-4 => SvgMaskError.OutOfMemory,
			-6 => SvgMaskError.BadSize,
			-7 => SvgMaskError.TooLarge,
			_ => SvgMaskError.Unparsable,
		};
		if (code == -5 || code < -7 || code >= 0) {
			console.log(`void2d svg: unexpected status ${code}`);
			unreachable;
		}
		return { error: error, what: what };
	}

	function staleHandle(what: string, handle: int32): void {
		console.log(`void2d svg: ${what}: handle ${handle} is not a live SVG`);
		unreachable;
	}

	export function svgMaskCompiled(): boolean { return true; }

	export function svgMaskParse(source: string): Result<SvgMaskSource, SvgMaskRefusal> {
		const code: int32 = maskParse(source);
		if (code < 0) { return Result.err(refusalOf(code)); }
		const image = maskImageOf(code);
		if (image == null) {
			staleHandle("svgMaskParse", code);
			unreachable;
		}
		return Result.ok({ handle: code, width: image.width, height: image.height });
	}

	export function svgMaskRasterize(
		source: SvgMaskSource, width: int32, height: int32,
	): Result<Vec<uint8>, SvgMaskRefusal> {
		if (width < 1 || height < 1 || width > MAX_SVG_MASK_SIDE || height > MAX_SVG_MASK_SIDE) {
			return Result.err({
				error: SvgMaskError.BadSize,
				what: `mask size ${width}x${height}, sides run 1 to ${MAX_SVG_MASK_SIDE}`,
			});
		}
		const image = maskImageOf(source.handle);
		if (image == null) {
			staleHandle("svgMaskRasterize", source.handle);
			unreachable;
		}
		return Result.ok(maskRasterize(image, width, height));
	}

	export function svgMaskFree(source: SvgMaskSource): void {
		if (maskFree(source.handle) < 0) { staleHandle("svgMaskFree", source.handle); }
	}

	export function svgMaskLive(): int32 { return maskLive(); }

	export function svgMaskParsed(): int32 { return maskParsed(); }

	export function svgMaskReleased(): int32 { return maskReleased(); }
} else {
	function svgMaskOff(what: string): void {
		console.log(`void2d svg: ${what} needs the SVG module; build with -d:voidSvg`);
		unreachable;
	}

	export function svgMaskCompiled(): boolean { return false; }

	export function svgMaskParse(source: string): Result<SvgMaskSource, SvgMaskRefusal> {
		svgMaskOff("svgMaskParse");
		unreachable;
	}

	export function svgMaskRasterize(
		source: SvgMaskSource, width: int32, height: int32,
	): Result<Vec<uint8>, SvgMaskRefusal> {
		svgMaskOff("svgMaskRasterize");
		unreachable;
	}

	export function svgMaskFree(source: SvgMaskSource): void {
		svgMaskOff("svgMaskFree");
	}

	export function svgMaskLive(): int32 {
		svgMaskOff("svgMaskLive");
		return 0;
	}

	export function svgMaskParsed(): int32 {
		svgMaskOff("svgMaskParsed");
		return 0;
	}

	export function svgMaskReleased(): int32 {
		svgMaskOff("svgMaskReleased");
		return 0;
	}
}
