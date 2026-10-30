import { Pool, SLOT_MASK, SLOT_SHIFT, newPool, allocate, store, release, alive, slotIndex, live, liveIds, reset, slotOf } from "../webgpu/pool";

struct Slot { id: uint32; }

function fresh(): Pool<Slot> {
	return newPool<Slot>("test", "GPUThing", "thing", { id: 0 });
}

function make(ref pool: Pool<Slot>): uint32 {
	const id = allocate(pool);
	store(pool, { id: id });
	return id;
}

function destroy(ref pool: Pool<Slot>, id: uint32): void {
	store(pool, { id: 0 });
	release(pool, id);
}

test "a new handle is the next index at generation 1" {
	let pool = fresh();
	const first = make(pool);
	const second = make(pool);
	assert first == (((1 as uint32) << SLOT_SHIFT) | 1);
	assert slotOf(second) == 2;
	assert pool.alive(first) && pool.alive(second);
	assert pool.slotIndex(second) == 2;
	assert pool.live() == 2;
	assert pool.liveIds().length == 2;
	assert !pool.alive(0);
}

test "a released slot comes back last freed first, a generation later" {
	let pool = fresh();
	const first = make(pool);
	const second = make(pool);
	pool.slots[slotOf(first)] = { id: 0 };
	release(pool, first);
	pool.slots[slotOf(second)] = { id: 0 };
	release(pool, second);
	assert !pool.alive(first) && !pool.alive(second);
	const again = make(pool);
	assert slotOf(again) == slotOf(second);
	assert again != second;
	assert pool.alive(again) && !pool.alive(second);
	assert slotOf(make(pool)) == slotOf(first);
}

test "a slot at its last generation is retired and never handed out again" {
	let pool = fresh();
	const id = make(pool);
	const index = slotOf(id);
	pool.core.generations[index] = SLOT_MASK;
	destroy(pool, id);
	assert pool.core.free.length == 0;
	assert slotOf(make(pool)) != index;
}

test "reset empties the pool and refuses every id from before it" {
	let pool = fresh();
	const first = make(pool);
	make(pool);
	reset(pool);
	assert pool.live() == 0;
	assert !pool.alive(first);
	const after = make(pool);
	assert after != first;
	assert slotOf(after) == slotOf(first);
	assert pool.alive(after) && !pool.alive(first);
}

test "reset refuses stale ids over several slots, a released slot and a retired slot" {
	let pool = fresh();
	let before: Vec<uint32> = [];
	for (let i = 0; i < 5; i++) { before.push(make(pool)); }
	destroy(pool, before[1]);
	const retired = make(pool);
	pool.core.generations[slotOf(retired)] = SLOT_MASK;
	destroy(pool, retired);
	reset(pool);
	for (let i = 0; i < before.length; i++) { assert !pool.alive(before[i]); }
	assert !pool.alive(retired);
	let seen: Vec<int32> = [];
	for (let i = 0; i < 6; i++) {
		const id = make(pool);
		assert pool.alive(id);
		assert slotOf(id) != slotOf(retired);
		for (let j = 0; j < before.length; j++) { assert id != before[j]; }
		seen.push(slotOf(id));
	}
	assert seen[0] == 1 && seen[1] == 3;
	assert pool.live() == 6;
}

test "reset twice keeps counting generations" {
	let pool = fresh();
	const first = make(pool);
	reset(pool);
	const second = make(pool);
	reset(pool);
	const third = make(pool);
	assert first != second && second != third && first != third;
	assert !pool.alive(first) && !pool.alive(second) && pool.alive(third);
}
