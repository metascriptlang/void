import { Mat4, Vec3, determinant3x3 } from "../math/math3d";

export enum MeshLodError {
	NonFiniteSize,
	InvalidSize,
	MirroredWorld,
	InvalidConfig,
	InvalidScreenRatio,
	InvalidForcedLod,
	InvalidRangeShape,
	RangeOverflow,
	InvalidRange,
	InvalidMaterial,
	InvalidLod,
}

// Use Bounds.getBoundingRadius (sphere radius + center offset), matrix translation distance,
// and projection-only _11/_22, as Heaps Mesh.hx:154-166; never substitute viewProj diagonals.
export struct MeshLodProjectedSize {
	localOriginRadius: float64;
	worldScaleX: float64;
	worldScaleY: float64;
	worldScaleZ: float64;
	worldMirrored: boolean;
	cameraDistanceFromWorldOrigin: float64;
	projectionDiagonalX: float64;
	projectionDiagonalY: float64;
	nearPlane: float64;
	meshLodScale: float64;
}

export struct MeshLodSelection {
	lod: int32;
	culled: boolean;
}

export struct MeshLod {
	lodCount: int32;
	thresholds: Vec<float64>;
	cullingScreenRatio: float64;
}

export struct MeshLodRangeSource {
	base: int64;
	count: int64;
}

export struct MeshLodRange {
	base: int32;
	count: int32;
}

export struct MeshLodRanges {
	lodCount: int32;
	materialCount: int32;
	elementCount: int32;
	ranges: Vec<MeshLodRange>;
}

const DRAW_ELEMENT_LIMIT: int64 = 2147483647;

// Retain Mesh.hx:154-166 distance division even for orthographic projections;
// this reference heuristic is not an exact orthographic projected diameter.
export function referenceScreenRatioHeuristic(
	this size: MeshLodProjectedSize,
): Result<float64, MeshLodError> {
	if (!Number.isFinite(size.localOriginRadius) ||
		!Number.isFinite(size.worldScaleX) || !Number.isFinite(size.worldScaleY) ||
		!Number.isFinite(size.worldScaleZ) ||
		!Number.isFinite(size.cameraDistanceFromWorldOrigin) ||
		!Number.isFinite(size.projectionDiagonalX) ||
		!Number.isFinite(size.projectionDiagonalY) ||
		!Number.isFinite(size.nearPlane) || !Number.isFinite(size.meshLodScale)) {
		return Result.err(MeshLodError.NonFiniteSize);
	}
	if (size.worldMirrored) { return Result.err(MeshLodError.MirroredWorld); }
	if (size.localOriginRadius < 0.0 || size.worldScaleX < 0.0 ||
		size.worldScaleY < 0.0 || size.worldScaleZ < 0.0 ||
		size.cameraDistanceFromWorldOrigin < 0.0 || size.meshLodScale < 0.0 ||
		size.projectionDiagonalX <= 0.0 || size.projectionDiagonalY <= 0.0) {
		return Result.err(MeshLodError.InvalidSize);
	}
	const denominator: float64 = Math.max(size.nearPlane, size.cameraDistanceFromWorldOrigin);
	if (denominator <= 0.0) { return Result.err(MeshLodError.InvalidSize); }
	const scale: float64 = Math.max(size.worldScaleX, Math.max(size.worldScaleY, size.worldScaleZ));
	const worldRadius: float64 = Math.abs(size.localOriginRadius * scale);
	const screenMultiple: float64 =
		Math.max(0.5 * size.projectionDiagonalX, 0.5 * size.projectionDiagonalY);
	const screenRadius: float64 = screenMultiple * worldRadius / denominator;
	const ratio: float64 = screenRadius * 2.0 * size.meshLodScale;
	if (!Number.isFinite(worldRadius) || !Number.isFinite(screenRadius) ||
		!Number.isFinite(ratio)) { return Result.err(MeshLodError.NonFiniteSize); }
	return Result.ok(ratio);
}

function checkConfig(
	lodCount: int32,
	thresholds: Readonly<Span<float64>>,
	cullingScreenRatio: float64,
): Result<void, MeshLodError> {
	if (lodCount < 1 || !Number.isFinite(cullingScreenRatio) || cullingScreenRatio < 0.0) {
		return Result.err(MeshLodError.InvalidConfig);
	}
	for (let i = 0; i < thresholds.length; i++) {
		if (!Number.isFinite(thresholds[i]) || thresholds[i] < 0.0 ||
			(i > 0 && thresholds[i] > thresholds[i - 1])) {
			return Result.err(MeshLodError.InvalidConfig);
		}
	}
	return Result.ok(null);
}

export function create(
	this typeof MeshLod,
	lodCount: int32,
	thresholds: Readonly<Span<float64>>,
	cullingScreenRatio: float64,
): Result<MeshLod, MeshLodError> {
	const checked = try checkConfig(lodCount, thresholds, cullingScreenRatio);
	let owned: Vec<float64> = [];
	for (const threshold of thresholds) { owned.push(threshold); }
	return Result.ok({
		lodCount: lodCount, thresholds: move owned, cullingScreenRatio: cullingScreenRatio,
	});
}

export function select(
	this config: Readonly<MeshLod>,
	screenRatio: float64,
	forcedLod: int32 = -1,
): Result<MeshLodSelection, MeshLodError> {
	const checked = try checkConfig(config.lodCount, config.thresholds, config.cullingScreenRatio);
	if (forcedLod < -1) { return Result.err(MeshLodError.InvalidForcedLod); }
	if (forcedLod >= 0) {
		return Result.ok({ lod: forcedLod, culled: forcedLod >= config.lodCount });
	}
	if (!Number.isFinite(screenRatio) || screenRatio < 0.0) {
		return Result.err(MeshLodError.InvalidScreenRatio);
	}
	if (screenRatio < config.cullingScreenRatio) {
		return Result.ok({ lod: config.lodCount, culled: true });
	}
	let lod: int32 = 0;
	for (let i = 0; i < config.lodCount - 1 && i < config.thresholds.length; i++) {
		const threshold: float64 = config.thresholds[i];
		if (threshold == 0.0 || threshold <= screenRatio) { break; }
		lod++;
	}
	return Result.ok({ lod: lod, culled: false });
}

function checkRange(base: int64, count: int64, total: int64): Result<void, MeshLodError> {
	if (base < 0 || count < 0) { return Result.err(MeshLodError.InvalidRange); }
	if (base > DRAW_ELEMENT_LIMIT || count > DRAW_ELEMENT_LIMIT) {
		return Result.err(MeshLodError.RangeOverflow);
	}
	if (base > total || count > total - base || base % 3 != 0 || count % 3 != 0) {
		return Result.err(MeshLodError.InvalidRange);
	}
	return Result.ok(null);
}

export function fromElementRanges(
	this typeof MeshLodRanges,
	lodCount: int32,
	materialCount: int32,
	elementCount: int64,
	lodMajorRanges: Readonly<Span<MeshLodRangeSource>>,
): Result<MeshLodRanges, MeshLodError> {
	if (lodCount < 1 || materialCount < 1 ||
		(lodCount as int64) * (materialCount as int64) != (lodMajorRanges.length as int64)) {
		return Result.err(MeshLodError.InvalidRangeShape);
	}
	if (elementCount > DRAW_ELEMENT_LIMIT) { return Result.err(MeshLodError.RangeOverflow); }
	if (elementCount < 0 || elementCount % 3 != 0) {
		return Result.err(MeshLodError.InvalidRange);
	}
	let owned: Vec<MeshLodRange> = [];
	for (const range of lodMajorRanges) {
		const checked = try checkRange(range.base, range.count, elementCount);
		owned.push({ base: range.base as int32, count: range.count as int32 });
	}
	return Result.ok({
		lodCount: lodCount,
		materialCount: materialCount,
		elementCount: elementCount as int32,
		ranges: move owned,
	});
}

export function rangeAt(
	this table: Readonly<MeshLodRanges>,
	material: int32,
	lod: int32,
): Result<MeshLodRange, MeshLodError> {
	if (table.lodCount < 1 || table.materialCount < 1 ||
		(table.lodCount as int64) * (table.materialCount as int64) !=
		(table.ranges.length as int64)) { return Result.err(MeshLodError.InvalidRangeShape); }
	if (material < 0 || material >= table.materialCount) {
		return Result.err(MeshLodError.InvalidMaterial);
	}
	if (lod < 0 || lod >= table.lodCount) { return Result.err(MeshLodError.InvalidLod); }
	if (table.elementCount < 0 || table.elementCount % 3 != 0) {
		return Result.err(MeshLodError.InvalidRange);
	}
	const index: int64 = (lod as int64) * (table.materialCount as int64) + (material as int64);
	const range = table.ranges[index];
	const checked = try checkRange(
		range.base as int64, range.count as int64, table.elementCount as int64,
	);
	return Result.ok({ base: range.base, count: range.count });
}

export interface MeshLodPick {
	config: MeshLod;
	ranges: MeshLodRanges;
	material: int32;
	localOriginRadius: float64;
	forcedLod: int32;
	range: MeshLodRange;
	culled: boolean;
}

function rowLength(x: float32, y: float32, z: float32): float64 {
	return Math.sqrt((x * x + y * y + z * z) as float64);
}

export function pickFor(
	this pick: MeshLodPick,
	world: Mat4,
	eye: Vec3,
	projectionX: float32,
	projectionY: float32,
	nearPlane: float32,
	meshLodScale: float64,
): Result<void, MeshLodError> {
	const dx: float64 = (world.m41 - eye.x) as float64;
	const dy: float64 = (world.m42 - eye.y) as float64;
	const dz: float64 = (world.m43 - eye.z) as float64;
	const size: MeshLodProjectedSize = {
		localOriginRadius: pick.localOriginRadius,
		worldScaleX: rowLength(world.m11, world.m12, world.m13),
		worldScaleY: rowLength(world.m21, world.m22, world.m23),
		worldScaleZ: rowLength(world.m31, world.m32, world.m33),
		worldMirrored: world.determinant3x3() < 0.0,
		cameraDistanceFromWorldOrigin: Math.sqrt(dx * dx + dy * dy + dz * dz),
		projectionDiagonalX: projectionX as float64,
		projectionDiagonalY: projectionY as float64,
		nearPlane: nearPlane as float64,
		meshLodScale: meshLodScale,
	};
	const ratio: float64 = try size.referenceScreenRatioHeuristic();
	const chosen = try pick.config.select(ratio, pick.forcedLod);
	pick.culled = chosen.culled;
	if (!chosen.culled) { pick.range = try pick.ranges.rangeAt(pick.material, chosen.lod); }
	return Result.ok(null);
}
