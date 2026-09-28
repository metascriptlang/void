// A table of reusable slots, each addressed by its index and the generation it had when it was
// handed out: M6's node ids, read out of Bevy at `2bddbdfd7` (`entity/mod.rs:710-755`,
// `:885-892`). A freed slot is handed out again last-freed first, with its generation bumped, so
// an id kept from before names nothing; a slot whose generation would wrap is retired instead.

export const LAST_GENERATION: int32 = 2147483647;

export struct Slots {
	generations: Vec<int32>;
	retired: Vec<boolean>;
	free: Vec<int32>;
}

export function empty(this typeof Slots): Slots {
	return { generations: [], retired: [], free: [] };
}

export function slotCount(this slots: Slots): int32 {
	return slots.generations.length as int32;
}

export function liveCount(this slots: Slots): int32 {
	let retired: int32 = 0;
	for (const gone of slots.retired) {
		if (gone) { retired = retired + 1; }
	}
	return slots.slotCount() - (slots.free.length as int32) - retired;
}

export function isCurrent(this slots: Slots, index: int32, generation: int32): boolean {
	if (index < 0 || index >= slots.slotCount()) { return false; }
	return slots.generations[index] == generation;
}

// The slot's index; its generation is `generations[index]`. An index equal to the slot count
// before the call is a new slot, which the caller's own tables have to grow into.
export function claim(ref slots: Slots): int32 {
	const reusable: int32 = slots.free.length as int32;
	if (reusable > 0) {
		const index: int32 = slots.free[reusable - 1];
		slots.free.pop();
		return index;
	}
	slots.generations.push(1);
	slots.retired.push(false);
	return slots.slotCount() - 1;
}

// The generation a freed slot takes; 0, which is never handed out and so matches no id, when
// `generation` would wrap and the slot has to be retired instead.
export function nextGeneration(generation: int32): int32 {
	return generation == LAST_GENERATION ? 0 : generation + 1;
}

export function vacate(ref slots: Slots, index: int32): void {
	const next: int32 = nextGeneration(slots.generations[index]);
	slots.generations[index] = next;
	if (next == 0) {
		slots.retired[index] = true;
		return;
	}
	slots.free.push(index);
}
