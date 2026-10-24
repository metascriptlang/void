import { env } from "std/process";

const HEADLINE_COUNT: int32 = 100000;
export const WARM_STEPS: int32 = 90;
export const STEP: float64 = 1.0 / 60.0;
const STEPS_AT_10K: int32 = 600;
const FEWEST_STEPS: int32 = 4;

export function benchCounts(): Vec<int32> {
	const wanted: string = env.get("BENCH_PARTICLES");
	if (wanted == "") { return [10000, 100000, 1000000]; }
	const count: int32 = parseInt(wanted) as int32;
	if (count <= 0) { console.log(`BENCH_PARTICLES must be a positive count, got ${wanted}`); unreachable; }
	return [count];
}

export function stepsFor(count: int32): int32 {
	const steps: int32 = STEPS_AT_10K * 10000 / count;
	return steps < FEWEST_STEPS ? FEWEST_STEPS : (steps > STEPS_AT_10K ? STEPS_AT_10K : steps);
}

export function millisecondsSince(started: float64, steps: int32): float64 {
	return (performance.now() - started) / (steps as float64);
}

export function row(name: string, value: float64): void {
	console.log(`particles.${name} ${value}`);
}

export function isHeadline(counts: Vec<int32>, at: int32): boolean {
	return counts.length == 1 || counts[at] == HEADLINE_COUNT;
}
