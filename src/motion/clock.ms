import { Clock, ManualClock } from "pulse/src/clock";

export class VoidClock {
	private manual: ManualClock = new ManualClock();

	get clock(): Clock {
		return this.manual.clock;
	}

	tick(dt: float32): void {
		this.manual.advance((dt as float64) * 1000);
	}

	pending(): int32 {
		return this.manual.pending();
	}
}
