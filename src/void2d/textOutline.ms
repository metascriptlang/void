import { AtlasError, OUTLINE_LANE_MAX } from "./glyphAtlas";
import { snapStroke } from "./snap";

export function outlineLane(width: float32, perUnit: float32): Result<int32, AtlasError> {
	if (!(width > 0.0)) { return Result.ok(0); }
	const exact: float32 = width * perUnit;
	if (!(exact < (OUTLINE_LANE_MAX as float32) + 0.5)) {
		return Result.err(AtlasError.OutlineTooWide);
	}
	const lane: int32 = Math.floor(exact + 0.5) as int32;
	return Result.ok(lane < 1 ? 1 : lane);
}

export function deviceOutlineWidth(
	widthLocal: float32,
	devicePerLocal: float32,
	pixelExact: boolean,
): float32 {
	const device: float32 = widthLocal * devicePerLocal;
	return pixelExact ? snapStroke(device) : device;
}
