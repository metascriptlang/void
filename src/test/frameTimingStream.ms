// The delta streams frameTimingCheck.ms feeds the frame timing: five shapes, one per way a
// delta can leave the 4 ms band or the clamp, drawn from a generator whose integers stay inside
// 2^31 so the native and js targets draw the same numbers.

export const STREAM_KINDS: int32 = 5;
export const STREAM_STEPS: int32 = 400;

export class DeltaStream {
	kind: int32;
	seed: int32;

	constructor(kind: int32) {
		this.kind = kind;
		this.seed = 1000 + kind * 7919;
	}

	draw(): float64 {
		this.seed = (this.seed * 75 + 74) % 65537;
		return this.seed as float64 / 65537.0;
	}

	next(): float64 {
		const r = this.draw();
		if (this.kind == 0) { return 1.0 / 60.0 + (r - 0.5) * 0.002; }
		if (this.kind == 1) { return 1.0 / 60.0 + (r - 0.5) * 0.012; }
		if (this.kind == 2) { return r * 0.5; }
		if (this.kind == 3) { return r < 0.3 ? -r : r < 0.6 ? 0.0 : 5.0 * r; }
		if (this.kind == 4) { return 0.004 + (r - 0.5) * 1e-9; }
		throw new Error(`DeltaStream: no stream kind ${this.kind}`);
	}
}
