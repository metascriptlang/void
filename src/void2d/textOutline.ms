import { AtlasError, OUTLINE_LANE_MAX } from "./glyphAtlas";
import { snapStroke } from "./snap";

export const COVERAGE_OUTLINE_PER_PX: float32 = 4.0;
export const SDF_OUTLINE_PER_TEXEL: float32 = 8.0;

export function outlineLane(width: float32, perUnit: float32): Result<int32, AtlasError> {
	if (!(width > 0.0)) { return Result.ok(0); }
	const exact: float32 = width * perUnit;
	if (!(exact < (OUTLINE_LANE_MAX as float32) + 0.5)) {
		return Result.err(AtlasError.OutlineTooWide);
	}
	const lane: int32 = Math.floor(exact + 0.5) as int32;
	return Result.ok(lane < 1 ? 1 : lane);
}

export function laneWidth(lane: int32, perUnit: float32): float32 {
	return (lane as float32) / perUnit;
}

export function deviceOutlineWidth(
	widthLocal: float32,
	devicePerLocal: float32,
	pixelExact: boolean,
): float32 {
	const device: float32 = widthLocal * devicePerLocal;
	return pixelExact ? snapStroke(device) : device;
}

export function outlineCoverage(inside: float32, width: float32): float32 {
	const covered: float32 = 0.5 + inside + width;
	if (covered <= 0.0) { return 0.0; }
	return covered >= 1.0 ? 1.0 : covered;
}
