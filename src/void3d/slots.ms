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

// Generation 0 is never handed out, so a retired slot matches no id at all.
export function vacate(ref slots: Slots, index: int32): void {
	const generation: int32 = slots.generations[index];
	if (generation == LAST_GENERATION) {
		slots.retired[index] = true;
		slots.generations[index] = 0;
		return;
	}
	slots.generations[index] = generation + 1;
	slots.free.push(index);
}
