export const SLOT_SHIFT = 16;
export const SLOT_MASK = 0xFFFF;

export struct Pool<T> {
	slots: Vec<T>;
	free: Vec<int32>;
	generations: Vec<uint32>;
	backend: string;
	kind: string;
	what: string;
}

export function newPool<T>(backend: string, kind: string, what: string, zero: T): Pool<T> {
	return { slots: [zero], free: [], generations: [], backend: backend, kind: kind, what: what };
}

function stopOnPool(backend: string, message: string): never {
	console.log(`webgpu ${backend}: ${message}`);
	unreachable;
}

@inline export function slotOf(id: uint32): int32 { return (id & SLOT_MASK) as int32; }

export function allocate<T>(ref pool: Pool<T>): uint32 {
	let index: int32 = 0;
	if (pool.free.length > 0) {
		index = pool.free[pool.free.length - 1];
		pool.free.pop();
	} else {
		if (pool.generations.length == 0) { pool.generations.push(0); }
		index = pool.generations.length as int32;
		if (index > SLOT_MASK) {
			stopOnPool(pool.backend, `${pool.what} pool exhausted: all ${SLOT_MASK} slots are live or retired`);
		}
		pool.generations.push(0);
	}
	pool.generations[index] += 1;
	return (pool.generations[index] << SLOT_SHIFT) | (index as uint32);
}

export function store<T>(ref pool: Pool<T>, slot: T): void {
	const index = slotOf(slot.id);
	if (index < pool.slots.length) { pool.slots[index] = slot; } else { pool.slots.push(slot); }
}

export function release<T>(ref pool: Pool<T>, id: uint32): void {
	const index = slotOf(id);
	if (pool.generations[index] < SLOT_MASK) { pool.free.push(index); }
}

export function reset<T>(ref pool: Pool<T>): void {
	while (pool.slots.length > 1) { pool.slots.pop(); }
	pool.free = [];
	pool.generations = [];
}

export function alive<T>(this pool: Pool<T>, id: uint32): boolean {
	const index = slotOf(id);
	return id != 0 && index < pool.slots.length && pool.slots[index].id == id;
}

export function slotIndex<T>(this pool: Pool<T>, id: uint32): int32 {
	if (!pool.alive(id)) {
		stopOnPool(pool.backend, `${pool.kind} ${id} is not a live handle`);
	}
	return slotOf(id);
}

export function live<T>(this pool: Pool<T>): int32 {
	let count: int32 = 0;
	for (let i: int32 = 1; i < pool.slots.length; i++) { if (pool.slots[i].id != 0) { count += 1; } }
	return count;
}

export function liveIds<T>(this pool: Pool<T>): Vec<uint32> {
	let ids: Vec<uint32> = [];
	for (let i: int32 = 1; i < pool.slots.length; i++) { if (pool.slots[i].id != 0) { ids.push(pool.slots[i].id); } }
	return ids;
}
