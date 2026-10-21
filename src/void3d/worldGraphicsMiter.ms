import { Vec3, vec3 } from "../math/math3d";

export enum WorldMiterError { NonFinite, Width, Degenerate, OutOfRange }

export function worldGraphicsMiter(
	previous: Vec3, current: Vec3, next: Vec3, width: float32,
): Result<Vec3, WorldMiterError> {
	if (!Number.isFinite(previous.x) || !Number.isFinite(previous.y) ||
		!Number.isFinite(previous.z) || !Number.isFinite(current.x) ||
		!Number.isFinite(current.y) || !Number.isFinite(current.z) ||
		!Number.isFinite(next.x) || !Number.isFinite(next.y) || !Number.isFinite(next.z)) {
		return Result.err(WorldMiterError.NonFinite);
	}
	if (!Number.isFinite(width) || width < 0) { return Result.err(WorldMiterError.Width); }
	const nx1: float64 = (previous.z as float64) - current.z;
	const nz1: float64 = (current.x as float64) - previous.x;
	const nx2: float64 = (current.z as float64) - next.z;
	const nz2: float64 = (next.x as float64) - current.x;
	const length1: float64 = Math.sqrt(nx1 * nx1 + nz1 * nz1);
	const length2: float64 = Math.sqrt(nx2 * nx2 + nz2 * nz2);
	if (length1 == 0 || length2 == 0) { return Result.err(WorldMiterError.Degenerate); }
	const sumX: float64 = nx1 / length1 + nx2 / length2;
	const sumZ: float64 = nz1 / length1 + nz2 / length2;
	const sumLength: float64 = Math.sqrt(sumX * sumX + sumZ * sumZ);
	if (sumLength == 0) { return Result.err(WorldMiterError.Degenerate); }
	const nx: float64 = sumX / sumLength;
	const nz: float64 = sumZ / sumLength;
	const facing: float64 = nx * nx1 / length1 + nz * nz1 / length1;
	if (facing == 0) { return Result.err(WorldMiterError.Degenerate); }
	const scale: float64 = (width as float64) * 0.5 / facing;
	const x: float64 = nx * scale;
	const z: float64 = nz * scale;
	const float32Max: float64 = 3.4028234663852886e38;
	if (Math.abs(x) > float32Max || Math.abs(z) > float32Max) {
		return Result.err(WorldMiterError.OutOfRange);
	}
	return Result.ok(vec3(x as float32, 0, z as float32));
}
