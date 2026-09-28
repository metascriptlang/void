import { Slots, LAST_GENERATION, claim, vacate } from "../void3d/slots";

test "a new slot is the next index at generation 1" {
	let slots: Slots = Slots.empty();
	assert claim(slots) == 0;
	assert claim(slots) == 1;
	assert slots.generations[0] == 1;
	assert slots.generations[1] == 1;
	assert slots.liveCount() == 2;
	assert slots.isCurrent(1, 1);
}

test "a vacated slot comes back last freed first, a generation later" {
	let slots: Slots = Slots.empty();
	const first: int32 = claim(slots);
	const second: int32 = claim(slots);
	vacate(slots, first);
	vacate(slots, second);
	assert !slots.isCurrent(second, 1);
	assert slots.liveCount() == 0;
	assert claim(slots) == second;
	assert slots.generations[second] == 2;
	assert claim(slots) == first;
	assert claim(slots) == 2;
}

test "an id from before the slot was vacated names nothing" {
	let slots: Slots = Slots.empty();
	const index: int32 = claim(slots);
	vacate(slots, index);
	assert claim(slots) == index;
	assert !slots.isCurrent(index, 1);
	assert slots.isCurrent(index, 2);
}

test "an index outside the table is never current" {
	let slots: Slots = Slots.empty();
	const _index: int32 = claim(slots);
	assert !slots.isCurrent(-1, 1);
	assert !slots.isCurrent(1, 1);
}

test "a slot whose generation would wrap is retired and matches no id" {
	let slots: Slots = Slots.empty();
	const index: int32 = claim(slots);
	slots.generations[index] = LAST_GENERATION;
	vacate(slots, index);
	assert !slots.isCurrent(index, LAST_GENERATION);
	assert !slots.isCurrent(index, 1);
	assert slots.generations[index] == 0;
	assert slots.liveCount() == 0;
	assert claim(slots) == 1;
}
