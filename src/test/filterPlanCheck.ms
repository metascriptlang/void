import { Scene2D } from "../void2d/node";
import "../void2d/scene";
import {
	Bounds2D, Filter, rgba, vec2, blurFilter, glowFilter, dropShadowFilter,
	outlineFilter, withResolutionScale, FilterKind,
} from "../void2d/types";
import { FilterPlan, planFilter, paddedBounds } from "../void2d/filterPlan";
import { approx } from "./helpers";

const subject: Bounds2D = { xMin: 0.0, yMin: 0.0, xMax: 100.0, yMax: 50.0 };
const placed: Bounds2D = { xMin: 50.0, yMin: 50.0, xMax: 150.0, yMax: 100.0 };
const viewport: float32 = 1000.0;

function planOf(steps: Filter[], dpi: float32): FilterPlan {
	let chain: Vec<Filter> = [];
	for (const f of steps) { chain.push(f); }
	return planFilter(placed, { steps: chain }, vec2(0.0, 0.0), viewport, viewport, dpi, false);
}

test "a filter at scale 1 asks for the node's device size plus its reach" {
	const p = planOf([blurFilter(8.0)], 1.0);
	assert p.width == 116;
	assert p.height == 66;
	assert approx(p.scale, 1.0);
}

test "a filter at scale 0.5 asks for a quarter of the pixels" {
	const p = planOf([blurFilter(8.0).withResolutionScale(0.5)], 1.0);
	assert p.width == 58;
	assert p.height == 33;
	assert approx(p.scale, 0.5);
}

test "the resolution scale multiplies the device pixel ratio" {
	const full = planOf([glowFilter(rgba(1.0, 1.0, 1.0, 1.0), 8.0, 1.0)], 2.0);
	const half = planOf(
		[glowFilter(rgba(1.0, 1.0, 1.0, 1.0), 8.0, 1.0).withResolutionScale(0.5)], 2.0);
	assert full.width == 232;
	assert half.width == 116;
	assert half.height == 66;
	assert approx(half.scale, 1.0);
}

test "a chain pads by the sum of its steps and a drop shadow reaches toward its offset" {
	const padded = paddedBounds(subject, {
		steps: [blurFilter(4.0), dropShadowFilter(rgba(0.0, 0.0, 0.0, 1.0), 2.0, 3.0, -5.0)],
	});
	assert approx(padded.xMin, -6.0);
	assert approx(padded.xMax, 109.0);
	assert approx(padded.yMin, -11.0);
	assert approx(padded.yMax, 56.0);
}

test "an outline reaches by its size on every side" {
	const padded = paddedBounds(subject, { steps: [outlineFilter(rgba(1.0, 0.0, 0.0, 1.0), 3.0, 0.3)] });
	assert approx(padded.xMin, -3.0);
	assert approx(padded.yMax, 53.0);
}

test "outline quality is the tap count, at least one" {
	assert outlineFilter(rgba(1.0, 0.0, 0.0, 1.0), 3.0, 0.3).samples == 30;
	assert outlineFilter(rgba(1.0, 0.0, 0.0, 1.0), 3.0, 0.0).samples == 1;
	assert outlineFilter(rgba(1.0, 0.0, 0.0, 1.0), 3.0, 0.3).kind === FilterKind.Outline;
}

test "a node keeps its chain in order and setFilter is a chain of one" {
	const n = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0)).group();
	n.setFilters([blurFilter(2.0), outlineFilter(rgba(1.0, 0.0, 0.0, 1.0), 1.0, 0.1)]);
	assert n.filterChain().steps.length == 2;
	assert n.filterChain().steps[0].kind === FilterKind.Blur;
	assert n.filterChain().steps[1].kind === FilterKind.Outline;
	n.setFilter(blurFilter(2.0));
	assert n.filterChain().steps.length == 1;
	n.setFilter({ ...blurFilter(2.0), kind: FilterKind.None });
	assert n.filterChain().steps.length == 0;
}
