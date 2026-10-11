import {
	MeshLod,
	MeshLodProjectedSize,
	MeshLodRangeSource,
	MeshLodRanges,
	MeshLodError,
} from "../void3d/meshLod";

function sizeA(): MeshLodProjectedSize {
	return {
		localOriginRadius: 2.5,
		worldScaleX: 1.0,
		worldScaleY: 2.0,
		worldScaleZ: 3.0,
		worldMirrored: false,
		cameraDistanceFromWorldOrigin: 30.0,
		projectionDiagonalX: 1.0,
		projectionDiagonalY: 2.0,
		nearPlane: 0.25,
		meshLodScale: 0.8,
	};
}

function sizeB(): MeshLodProjectedSize {
	return {
		localOriginRadius: 1.25,
		worldScaleX: 4.0,
		worldScaleY: 0.5,
		worldScaleZ: 2.0,
		worldMirrored: false,
		cameraDistanceFromWorldOrigin: 10.0,
		projectionDiagonalX: 3.0,
		projectionDiagonalY: 1.5,
		nearPlane: 2.0,
		meshLodScale: 0.5,
	};
}

function rangesA(): Vec<MeshLodRangeSource> {
	return [
		{ base: 0, count: 24 }, { base: 24, count: 18 },
		{ base: 42, count: 12 }, { base: 54, count: 15 },
		{ base: 69, count: 6 }, { base: 75, count: 9 },
	];
}

function rangesB(): Vec<MeshLodRangeSource> {
	return [
		{ base: 0, count: 65538 }, { base: 65538, count: 9 }, { base: 65547, count: 12 },
		{ base: 65559, count: 9 }, { base: 131073, count: 12 }, { base: 131085, count: 3 },
		{ base: 131088, count: 6 }, { base: 196611, count: 18 }, { base: 196629, count: 6 },
		{ base: 196635, count: 3 }, { base: 196638, count: 6 }, { base: 196644, count: 6 },
	];
}

test "meshLod camera A selects LOD1 and its second material range" {
	const config = MeshLod.create(3, [0.6, 0.2], 0.05);
	const ratio = sizeA().referenceScreenRatioHeuristic();
	const ranges = MeshLodRanges.fromElementRanges(3, 2, 90, rangesA());
	assert config.ok && ratio.ok && ranges.ok;
	if (config.ok && ratio.ok && ranges.ok) {
		assert Math.abs(ratio.value - 0.4) < 1e-12;
		const selected = config.value.select(ratio.value);
		assert selected.ok;
		if (selected.ok) {
			assert !selected.value.culled;
			assert selected.value.lod == 1;
			const range = ranges.value.rangeAt(1, selected.value.lod);
			assert range.ok;
			if (range.ok) { assert range.value.base == 54 && range.value.count == 15; }
		}
	}
}

test "meshLod camera B selects LOD2 without narrowing material range upper bits" {
	const config = MeshLod.create(4, [1.2, 0.8, 0.3], 0.1);
	const ratio = sizeB().referenceScreenRatioHeuristic();
	const ranges = MeshLodRanges.fromElementRanges(4, 3, 196650, rangesB());
	assert config.ok && ratio.ok && ranges.ok;
	if (config.ok && ratio.ok && ranges.ok) {
		assert Math.abs(ratio.value - 0.75) < 1e-12;
		const selected = config.value.select(ratio.value);
		assert selected.ok;
		if (selected.ok) {
			assert !selected.value.culled && selected.value.lod == 2;
			const range = ranges.value.rangeAt(1, selected.value.lod);
			assert range.ok;
			if (range.ok) { assert range.value.base == 196611 && range.value.count == 18; }
		}
		const first = ranges.value.rangeAt(0, 0);
		assert first.ok;
		if (first.ok) { assert first.value.count == 65538; }
	}
}

test "meshLod strict thresholds retain equality and culling reports lodCount" {
	const made = MeshLod.create(3, [0.6, 0.2], 0.05);
	assert made.ok;
	if (made.ok) {
		const config = made.value;
		const atFirst = config.select(0.6);
		const atSecond = config.select(0.2);
		const belowSecond = config.select(0.199);
		const atCull = config.select(0.05);
		const belowCull = config.select(0.049);
		assert atFirst.ok && atSecond.ok && belowSecond.ok && atCull.ok && belowCull.ok;
		if (atFirst.ok) { assert atFirst.value.lod == 0 && !atFirst.value.culled; }
		if (atSecond.ok) { assert atSecond.value.lod == 1 && !atSecond.value.culled; }
		if (belowSecond.ok) { assert belowSecond.value.lod == 2 && !belowSecond.value.culled; }
		if (atCull.ok) { assert atCull.value.lod == 2 && !atCull.value.culled; }
		if (belowCull.ok) { assert belowCull.value.lod == 3 && belowCull.value.culled; }
	}
}

test "meshLod forced level overrides threshold cull and excessive forced level culls" {
	const made = MeshLod.create(4, [1.2, 0.8, 0.3], 0.1);
	assert made.ok;
	if (made.ok) {
		const forced = made.value.select(0.001, 2);
		const forcedZero = made.value.select(0.001, 0);
		const forcedCull = made.value.select(1.0, 7);
		assert forced.ok && forcedZero.ok && forcedCull.ok;
		if (forced.ok) { assert forced.value.lod == 2 && !forced.value.culled; }
		if (forcedZero.ok) { assert forcedZero.value.lod == 0 && !forcedZero.value.culled; }
		if (forcedCull.ok) { assert forcedCull.value.lod == 7 && forcedCull.value.culled; }
		assert !made.value.select(0.5, -2).ok;
	}
}

test "meshLod zero threshold stops selection and missing thresholds retain LOD0" {
	const stopped = MeshLod.create(4, [0.8, 0.0, 0.0], 0.0);
	const missing = MeshLod.create(4, [], 0.0);
	const single = MeshLod.create(1, [0.5, 0.2, 0.01], 0.1);
	const defaults = MeshLod.create(2, [0.5, 0.2, 0.01], 0.0);
	assert stopped.ok && missing.ok && single.ok && defaults.ok;
	if (defaults.ok) {
		const selected = defaults.value.select(0.001);
		assert selected.ok;
		if (selected.ok) { assert selected.value.lod == 1 && !selected.value.culled; }
	}
	if (stopped.ok) {
		const selected = stopped.value.select(0.0);
		assert selected.ok;
		if (selected.ok) { assert selected.value.lod == 1 && !selected.value.culled; }
	}
	if (missing.ok) {
		const selected = missing.value.select(0.0);
		assert selected.ok;
		if (selected.ok) { assert selected.value.lod == 0; }
	}
	if (single.ok) {
		const selected = single.value.select(0.09);
		assert selected.ok;
		if (selected.ok) { assert selected.value.culled && selected.value.lod == 1; }
	}
}

test "meshLod both camera variants clamp distance to near before projection" {
	const a: MeshLodProjectedSize = { ...sizeA(), cameraDistanceFromWorldOrigin: 0.0 };
	const b: MeshLodProjectedSize = { ...sizeB(), cameraDistanceFromWorldOrigin: 1.0 };
	const ratioA = a.referenceScreenRatioHeuristic();
	const ratioB = b.referenceScreenRatioHeuristic();
	assert ratioA.ok && ratioB.ok;
	if (ratioA.ok) { assert Math.abs(ratioA.value - 48.0) < 1e-12; }
	if (ratioB.ok) { assert Math.abs(ratioB.value - 3.75) < 1e-12; }
	const ortho: MeshLodProjectedSize = {
		...sizeA(), projectionDiagonalX: 0.5, projectionDiagonalY: 0.25, nearPlane: -50.0,
	};
	const heuristic = ortho.referenceScreenRatioHeuristic();
	assert heuristic.ok;
	if (heuristic.ok) { assert Math.abs(heuristic.value - 0.1) < 1e-12; }
}

test "meshLod refuses invalid size and holds mirrored world integration" {
	const nan: float64 = 0.0 / 0.0;
	const infinite: float64 = 1.0 / 0.0;
	const badScale: MeshLodProjectedSize = { ...sizeA(), worldScaleY: -1.0 };
	const badRadius: MeshLodProjectedSize = { ...sizeA(), localOriginRadius: -1.0 };
	const badDistance: MeshLodProjectedSize = { ...sizeA(), cameraDistanceFromWorldOrigin: -1.0 };
	const badProjection: MeshLodProjectedSize = { ...sizeA(), projectionDiagonalX: 0.0 };
	const badNear: MeshLodProjectedSize = { ...sizeA(), nearPlane: nan };
	const zeroDenominator: MeshLodProjectedSize = {
		...sizeA(), nearPlane: -1.0, cameraDistanceFromWorldOrigin: 0.0,
	};
	const overflow: MeshLodProjectedSize = {
		...sizeA(), localOriginRadius: 1e308, worldScaleZ: 1e308,
	};
	const nonfinite: MeshLodProjectedSize = { ...sizeA(), meshLodScale: infinite };
	const mirrored: MeshLodProjectedSize = {
		...sizeA(), worldMirrored: true, worldScaleX: 10.0, worldScaleY: 1.0, worldScaleZ: 1.0,
	};
	assert !badScale.referenceScreenRatioHeuristic().ok;
	assert !badRadius.referenceScreenRatioHeuristic().ok;
	assert !badDistance.referenceScreenRatioHeuristic().ok;
	assert !badProjection.referenceScreenRatioHeuristic().ok;
	assert !badNear.referenceScreenRatioHeuristic().ok;
	assert !zeroDenominator.referenceScreenRatioHeuristic().ok;
	assert !overflow.referenceScreenRatioHeuristic().ok;
	assert !nonfinite.referenceScreenRatioHeuristic().ok;
	const refused = mirrored.referenceScreenRatioHeuristic();
	assert !refused.ok;
	if (!refused.ok) { assert refused.error == MeshLodError.MirroredWorld; }
}

test "meshLod validates finite nonnegative ordered thresholds and owned copies" {
	const nan: float64 = 0.0 / 0.0;
	assert !MeshLod.create(0, [], 0.0).ok;
	assert !MeshLod.create(2, [0.5], nan).ok;
	assert !MeshLod.create(3, [0.2, 0.5], 0.0).ok;
	assert !MeshLod.create(3, [0.0, 0.2], 0.0).ok;
	assert !MeshLod.create(2, [-0.1], 0.0).ok;
	assert !MeshLod.create(2, [nan], 0.0).ok;
	assert !MeshLod.create(2, [0.5], -0.1).ok;
	let thresholds: Vec<float64> = [0.6, 0.2];
	const made = MeshLod.create(3, thresholds, 0.05);
	thresholds[0] = 0.1;
	assert made.ok;
	if (made.ok) {
		const selected = made.value.select(0.4);
		assert selected.ok;
		if (selected.ok) { assert selected.value.lod == 1; }
		assert !made.value.select(nan).ok;
		assert !made.value.select(-0.1).ok;
		let corrupted = made.value;
		corrupted.thresholds[1] = 0.9;
		assert !corrupted.select(0.4).ok;
	}
}

test "meshLod ranges own lod-major rows and distinguish every material" {
	let source = rangesA();
	const made = MeshLodRanges.fromElementRanges(3, 2, 90, source);
	source[3].base = 0;
	assert made.ok;
	if (made.ok) {
		for (let lod = 0; lod < 3; lod++) {
			for (let material = 0; material < 2; material++) {
				const expected = rangesA()[lod * 2 + material];
				const range = made.value.rangeAt(material, lod);
				assert range.ok;
				if (range.ok) {
					assert (range.value.base as int64) == expected.base;
					assert (range.value.count as int64) == expected.count;
				}
			}
		}
		assert !made.value.rangeAt(-1, 0).ok;
		assert !made.value.rangeAt(2, 0).ok;
		assert !made.value.rangeAt(0, -1).ok;
		assert !made.value.rangeAt(0, 3).ok;
		let corrupted = made.value;
		corrupted.ranges[3].count = 90;
		assert !corrupted.rangeAt(1, 1).ok;
	}
}

test "meshLod range validation rejects shape negative escaped and nontriangle ranges" {
	assert !MeshLodRanges.fromElementRanges(3, 2, 90, []).ok;
	assert !MeshLodRanges.fromElementRanges(0, 2, 90, rangesA()).ok;
	assert !MeshLodRanges.fromElementRanges(3, 0, 90, rangesA()).ok;
	assert !MeshLodRanges.fromElementRanges(2147483647, 2147483647, 90, []).ok;
	assert !MeshLodRanges.fromElementRanges(1, 1, -3, [{ base: 0, count: 0 }]).ok;
	assert !MeshLodRanges.fromElementRanges(1, 1, 9, [{ base: -3, count: 3 }]).ok;
	assert !MeshLodRanges.fromElementRanges(1, 1, 9, [{ base: 6, count: 6 }]).ok;
	assert !MeshLodRanges.fromElementRanges(1, 1, 9, [{ base: 12, count: 0 }]).ok;
	assert !MeshLodRanges.fromElementRanges(1, 1, 9, [{ base: 0, count: -3 }]).ok;
	assert !MeshLodRanges.fromElementRanges(1, 1, 9, [{ base: 1, count: 3 }]).ok;
	assert !MeshLodRanges.fromElementRanges(1, 1, 9, [{ base: 0, count: 4 }]).ok;
	const empty = MeshLodRanges.fromElementRanges(1, 1, 9, [{ base: 9, count: 0 }]);
	assert empty.ok;
	if (empty.ok) {
		const range = empty.value.rangeAt(0, 0);
		assert range.ok;
		if (range.ok) { assert range.value.base == 9 && range.value.count == 0; }
	}
}

test "meshLod wide source range overflow is refused before any narrowing or sum" {
	const tooWide: int64 = 4294967298;
	const huge: int64 = 9223372036854775807;
	const base = MeshLodRanges.fromElementRanges(1, 1, 90, [{ base: tooWide, count: 3 }]);
	const count = MeshLodRanges.fromElementRanges(1, 1, 90, [{ base: 0, count: tooWide }]);
	const sum = MeshLodRanges.fromElementRanges(1, 1, 90, [{ base: huge, count: huge }]);
	const total = MeshLodRanges.fromElementRanges(1, 1, tooWide, [{ base: 0, count: 3 }]);
	assert !base.ok && !count.ok && !sum.ok && !total.ok;
	if (!base.ok) { assert base.error == MeshLodError.RangeOverflow; }
	if (!count.ok) { assert count.error == MeshLodError.RangeOverflow; }
	if (!sum.ok) { assert sum.error == MeshLodError.RangeOverflow; }
	if (!total.ok) { assert total.error == MeshLodError.RangeOverflow; }
}


test "meshLod camera distances cross ordered levels then cull in both variants" {
	const configA = MeshLod.create(3, [0.6, 0.2], 0.05);
	const configB = MeshLod.create(4, [1.2, 0.8, 0.3], 0.1);
	const farA: MeshLodProjectedSize = { ...sizeA(), cameraDistanceFromWorldOrigin: 90.0 };
	const cullA: MeshLodProjectedSize = { ...sizeA(), cameraDistanceFromWorldOrigin: 300.0 };
	const farB: MeshLodProjectedSize = { ...sizeB(), cameraDistanceFromWorldOrigin: 50.0 };
	const cullB: MeshLodProjectedSize = { ...sizeB(), cameraDistanceFromWorldOrigin: 100.0 };
	const ratioFarA = farA.referenceScreenRatioHeuristic();
	const ratioCullA = cullA.referenceScreenRatioHeuristic();
	const ratioFarB = farB.referenceScreenRatioHeuristic();
	const ratioCullB = cullB.referenceScreenRatioHeuristic();
	assert configA.ok && configB.ok;
	assert ratioFarA.ok && ratioCullA.ok && ratioFarB.ok && ratioCullB.ok;
	if (configA.ok && ratioFarA.ok && ratioCullA.ok) {
		const far = configA.value.select(ratioFarA.value);
		const culled = configA.value.select(ratioCullA.value);
		assert far.ok && culled.ok;
		if (far.ok) { assert far.value.lod == 2 && !far.value.culled; }
		if (culled.ok) { assert culled.value.lod == 3 && culled.value.culled; }
	}
	if (configB.ok && ratioFarB.ok && ratioCullB.ok) {
		const far = configB.value.select(ratioFarB.value);
		const culled = configB.value.select(ratioCullB.value);
		assert far.ok && culled.ok;
		if (far.ok) { assert far.value.lod == 3 && !far.value.culled; }
		if (culled.ok) { assert culled.value.lod == 4 && culled.value.culled; }
	}
}

test "meshLod element offsets reach int32 ceiling independently of u16 index values" {
	const made = MeshLodRanges.fromElementRanges(
		1, 1, 2147483646, [{ base: 2147483643, count: 3 }],
	);
	assert made.ok;
	if (made.ok) {
		const range = made.value.rangeAt(0, 0);
		assert range.ok;
		if (range.ok) { assert range.value.base == 2147483643 && range.value.count == 3; }
	}
}
