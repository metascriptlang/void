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

test "reset empties the pool and starts handles over" {
	let pool = fresh();
	const first = make(pool);
	make(pool);
	reset(pool);
	assert pool.live() == 0;
	assert !pool.alive(first);
	assert make(pool) == first;
}
