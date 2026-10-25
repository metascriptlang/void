import {
	AllocationSizes,
	DEFAULT_MAX_ALLOCATIONS,
	MemoryAllocation,
	MemoryAllocator,
	MemoryDevice,
	MemoryError,
	MemoryKind,
	MemoryRequest,
	OffsetAllocation,
	OffsetAllocator,
	Tiling,
	memoryAllocate,
	memoryFree,
	memoryPropertiesOf,
	offsetAllocate,
	offsetFree,
} from "../webgpu/vulkan/memory";

const MB: uint64 = 1024 * 1024;
const GB: uint64 = 1024 * MB;
const ALL_TYPES: uint32 = 0xFFFFFFFF;

let nextBlock: uint32 = 0;
let openBlocks: int32 = 0;
let openedSizes: Vec<uint64> = [];

function deviceOf(
	flags: Readonly<Span<uint32>>,
	heaps: Readonly<Span<int32>>,
	heapSizes: Readonly<Span<uint64>>,
	cap: uint32,
): MemoryDevice {
	let device: MemoryDevice = {
		types: [],
		heapSizes: [],
		nonCoherentAtomSize: 64,
		maxAllocationCount: cap,
		openBlock: (typeIndex: int32, size: uint64): uint32 => {
			nextBlock += 1;
			openBlocks += 1;
			openedSizes.push(size);
			return nextBlock;
		},
		closeBlock: (block: uint32): void => {
			openBlocks -= 1;
		},
	};
	for (let i = 0; i < flags.length; i++) {
		device.types.push({ properties: memoryPropertiesOf(flags[i]), heap: heaps[i] });
	}
	for (const size of heapSizes) { device.heapSizes.push(size); }
	return device;
}

function nvidia(cap: uint32): MemoryDevice {
	const flags: Vec<uint32> = [0x0, 0x1, 0x6, 0xE, 0x7];
	const heaps: Vec<int32> = [1, 0, 1, 1, 2];
	const sizes: Vec<uint64> = [8 * GB, 16 * GB, 256 * MB];
	return deviceOf(flags, heaps, sizes, cap);
}

function amd(): MemoryDevice {
	const flags: Vec<uint32> = [0x1, 0x6, 0x7, 0xE, 0xC1, 0xC6, 0xC7, 0xCE];
	const heaps: Vec<int32> = [0, 1, 2, 1, 0, 1, 2, 1];
	const sizes: Vec<uint64> = [8 * GB, 16 * GB, 256 * MB];
	return deviceOf(flags, heaps, sizes, 4096);
}

function mali(): MemoryDevice {
	const flags: Vec<uint32> = [0x7, 0xF, 0x11];
	const heaps: Vec<int32> = [0, 0, 0];
	const sizes: Vec<uint64> = [4 * GB];
	return deviceOf(flags, heaps, sizes, 4096);
}

function lavapipe(): MemoryDevice {
	const flags: Vec<uint32> = [0xF];
	const heaps: Vec<int32> = [0];
	const sizes: Vec<uint64> = [2 * GB];
	return deviceOf(flags, heaps, sizes, 4096);
}

function nonCoherentHost(): MemoryDevice {
	const flags: Vec<uint32> = [0x1, 0xA];
	const heaps: Vec<int32> = [0, 1];
	const sizes: Vec<uint64> = [8 * GB, 16 * GB];
	return deviceOf(flags, heaps, sizes, 4096);
}

function request(size: uint64, alignment: uint64, kind: MemoryKind, tiling: Tiling): MemoryRequest {
	return { size: size, alignment: alignment, typeBits: ALL_TYPES, kind: kind, tiling: tiling };
}

function take(ref m: MemoryAllocator, r: MemoryRequest): MemoryAllocation {
	const result = memoryAllocate(m, r);
	if (!result.ok) {
		console.log(`memoryAllocate refused ${r.size} bytes: ${result.error.toString()}`);
		unreachable;
	}
	return result.value;
}

function give(ref m: MemoryAllocator, allocation: MemoryAllocation): void {
	const result = memoryFree(m, allocation);
	if (!result.ok) {
		console.log(`memoryFree refused block ${allocation.block}: ${result.error.toString()}`);
		unreachable;
	}
}

function offsetTake(ref a: OffsetAllocator, size: uint32): OffsetAllocation {
	const result = offsetAllocate(a, size);
	if (!result.ok) {
		console.log(`offsetAllocate refused ${size} bytes: ${result.error.toString()}`);
		unreachable;
	}
	return result.value;
}

function offsetGive(ref a: OffsetAllocator, allocation: OffsetAllocation): void {
	const result = offsetFree(a, allocation);
	if (!result.ok) {
		console.log(`offsetFree refused node ${allocation.node}: ${result.error.toString()}`);
		unreachable;
	}
}

function mach256(): OffsetAllocator {
	return OffsetAllocator.sized((256 * MB) as uint32, DEFAULT_MAX_ALLOCATIONS);
}

test "mach basic: the first allocation sits at offset 0" {
	let a = mach256();
	const first = offsetTake(a, 1337);
	assert first.offset == 0;
	offsetGive(a, first);
}

test "mach allocate: mixed sizes pack in order and coalesce back to one range" {
	let a = mach256();
	const zero = offsetTake(a, 0);
	assert zero.offset == 0;
	const one = offsetTake(a, 1);
	assert one.offset == 0;
	const small = offsetTake(a, 123);
	assert small.offset == 1;
	const large = offsetTake(a, 1234);
	assert large.offset == 124;
	offsetGive(a, zero);
	offsetGive(a, one);
	offsetGive(a, small);
	offsetGive(a, large);
	const whole = offsetTake(a, (256 * MB) as uint32);
	assert whole.offset == 0;
	offsetGive(a, whole);
	assert a.allocated() == 0;
}

test "mach allocate: a freed range is reused at its own offset" {
	let a = mach256();
	const first = offsetTake(a, 1024);
	assert first.offset == 0;
	const second = offsetTake(a, 3456);
	assert second.offset == 1024;
	offsetGive(a, first);
	const again = offsetTake(a, 1024);
	assert again.offset == 0;
	offsetGive(a, second);
	offsetGive(a, again);
	const whole = offsetTake(a, (256 * MB) as uint32);
	assert whole.offset == 0;
	offsetGive(a, whole);
}

test "mach allocate: a request too big for the hole goes past it, smaller ones fill it" {
	let a = mach256();
	const first = offsetTake(a, 1024);
	const second = offsetTake(a, 3456);
	assert second.offset == 1024;
	offsetGive(a, first);
	const third = offsetTake(a, 2345);
	assert third.offset == 1024 + 3456;
	const fourth = offsetTake(a, 456);
	assert fourth.offset == 0;
	const fifth = offsetTake(a, 512);
	assert fifth.offset == 456;
	offsetGive(a, second);
	offsetGive(a, third);
	offsetGive(a, fourth);
	offsetGive(a, fifth);
	const whole = offsetTake(a, (256 * MB) as uint32);
	assert whole.offset == 0;
	offsetGive(a, whole);
}

test "a double free and a full block are refused by name" {
	let a = OffsetAllocator.sized(1024, 16);
	const first = offsetTake(a, 1024);
	const full = offsetAllocate(a, 1);
	assert !full.ok;
	if (!full.ok) { assert full.error == MemoryError.OutOfMemory; }
	offsetGive(a, first);
	const twice = offsetFree(a, first);
	assert !twice.ok;
	if (!twice.ok) { assert twice.error == MemoryError.InvalidAllocation; }
}

test "block sizes clamp to 4..256 MB in 4 MB steps as Mach's AllocationSizes" {
	const sizes = AllocationSizes.clamped(1 * MB, 300 * MB);
	assert sizes.deviceBlockSize == 4 * MB;
	assert sizes.hostBlockSize == 256 * MB;
	assert AllocationSizes.clamped(5 * MB, 64 * MB).deviceBlockSize == 8 * MB;
}

test "flags read as Vulkan's VkMemoryPropertyFlagBits" {
	const bar = memoryPropertiesOf(0x7);
	assert bar.toString() == "{DeviceLocal, HostVisible, HostCoherent}";
	assert memoryPropertiesOf(0x11).toString() == "{DeviceLocal, LazilyAllocated}";
	const amdCoherent = memoryPropertiesOf(0xC1).toString();
	assert amdCoherent == "{DeviceLocal, DeviceCoherentAmd, DeviceUncachedAmd}";
}

test "memory types are chosen per kind on a discrete NVIDIA table" {
	const device = nvidia(4096);
	const local = device.selectMemoryType(ALL_TYPES, MemoryKind.DeviceLocal);
	assert local.ok;
	if (local.ok) { assert local.value == 1; }
	const upload = device.selectMemoryType(ALL_TYPES, MemoryKind.WriteMappable);
	assert upload.ok;
	if (upload.ok) { assert upload.value == 2; }
	const readback = device.selectMemoryType(ALL_TYPES, MemoryKind.ReadMappable);
	assert readback.ok;
	if (readback.ok) { assert readback.value == 3; }
	const transient = device.selectMemoryType(ALL_TYPES, MemoryKind.LazilyAllocated);
	assert transient.ok;
	if (transient.ok) { assert transient.value == 1; }
}

test "write-mappable takes BAR only when memoryTypeBits leaves nothing else" {
	const device = nvidia(4096);
	const upload = device.selectMemoryType(0x10, MemoryKind.WriteMappable);
	assert upload.ok;
	if (upload.ok) { assert upload.value == 4; }
	const none = device.selectMemoryType(0x01, MemoryKind.WriteMappable);
	assert !none.ok;
	if (!none.ok) { assert none.error == MemoryError.NoCompatibleMemory; }
}

test "write-mappable ranks coherence above heap size" {
	const flags: Vec<uint32> = [0xA, 0x6];
	const heaps: Vec<int32> = [1, 0];
	const sizes: Vec<uint64> = [8 * GB, 16 * GB];
	const device = deviceOf(flags, heaps, sizes, 4096);
	const upload = device.selectMemoryType(ALL_TYPES, MemoryKind.WriteMappable);
	assert upload.ok;
	if (upload.ok) { assert upload.value == 1; }
}

test "AMD device-coherent types are never chosen" {
	const device = amd();
	const local = device.selectMemoryType(0xF0, MemoryKind.DeviceLocal);
	assert !local.ok;
	const upload = device.selectMemoryType(ALL_TYPES, MemoryKind.WriteMappable);
	assert upload.ok;
	if (upload.ok) { assert upload.value == 1; }
}

test "transient attachments take lazily allocated memory on a tiler" {
	const device = mali();
	const transient = device.selectMemoryType(ALL_TYPES, MemoryKind.LazilyAllocated);
	assert transient.ok;
	if (transient.ok) { assert transient.value == 2; }
	const readback = device.selectMemoryType(ALL_TYPES, MemoryKind.ReadMappable);
	assert readback.ok;
	if (readback.ok) { assert readback.value == 1; }
	const plain = device.selectMemoryType(0x3, MemoryKind.LazilyAllocated);
	assert plain.ok;
	if (plain.ok) { assert plain.value == 0; }
}

test "allocations of mixed sizes free back to no open block" {
	openBlocks = 0;
	let m = MemoryAllocator.forDevice(lavapipe());
	const sizes: Vec<uint64> = [1337, 64 * 1024, 3, 5 * MB, 256, 1 * MB, 7777];
	let live: Vec<MemoryAllocation> = [];
	for (const size of sizes) {
		live.push(take(m, request(size, 1, MemoryKind.DeviceLocal, Tiling.Linear)));
	}
	assert m.blockCount == 1;
	assert openBlocks == 1;
	for (let i = 0; i < live.length; i += 2) { give(m, live[i]); }
	for (let i = 1; i < live.length; i += 2) { give(m, live[i]); }
	assert m.blockCount == 0;
	assert openBlocks == 0;
}

test "freed neighbours coalesce so the whole block fits again" {
	let m = MemoryAllocator.forDevice(lavapipe());
	const keep = take(m, request(1, 1, MemoryKind.DeviceLocal, Tiling.Linear));
	const first = take(m, request(10 * MB, 1, MemoryKind.DeviceLocal, Tiling.Linear));
	const second = take(m, request(20 * MB, 1, MemoryKind.DeviceLocal, Tiling.Linear));
	const third = take(m, request(30 * MB, 1, MemoryKind.DeviceLocal, Tiling.Linear));
	assert first.block == keep.block && second.block == keep.block && third.block == keep.block;
	give(m, second);
	give(m, first);
	give(m, third);
	assert m.groups[keep.group].blocks[keep.slot].offsets.allocated() == 1;
	const rest = take(m, request(48 * MB, 1, MemoryKind.DeviceLocal, Tiling.Linear));
	assert rest.block == keep.block;
	assert rest.offset == 1;
	give(m, keep);
	give(m, rest);
	assert m.blockCount == 0;
}

test "every offset honours the requested alignment" {
	let m = MemoryAllocator.forDevice(nvidia(4096));
	const odd = take(m, request(100, 1, MemoryKind.DeviceLocal, Tiling.Optimal));
	assert odd.offset == 0;
	const image = take(m, request(4096, 65536, MemoryKind.DeviceLocal, Tiling.Optimal));
	assert image.block == odd.block;
	assert image.offset % 65536 == 0;
	assert image.offset >= 100;
	const uniform = take(m, request(17, 256, MemoryKind.DeviceLocal, Tiling.Optimal));
	assert uniform.offset % 256 == 0;
	assert uniform.offset >= image.offset + 4096 || uniform.offset + 17 <= image.offset;
	give(m, odd);
	give(m, image);
	give(m, uniform);
}

test "non-coherent host memory aligns to nonCoherentAtomSize as Dawn does" {
	let m = MemoryAllocator.forDevice(nonCoherentHost());
	const first = take(m, request(3, 1, MemoryKind.ReadMappable, Tiling.Linear));
	assert first.typeIndex == 1;
	const second = take(m, request(5, 4, MemoryKind.ReadMappable, Tiling.Linear));
	assert second.offset % 64 == 0;
	assert second.offset >= 3;
	give(m, first);
	give(m, second);
}

test "a request larger than a block gets a dedicated block of its own size" {
	openedSizes = [];
	let m = MemoryAllocator.forDevice(nvidia(4096));
	const small = take(m, request(1 * MB, 256, MemoryKind.DeviceLocal, Tiling.Linear));
	const huge = take(m, request(300 * MB, 256, MemoryKind.DeviceLocal, Tiling.Linear));
	assert huge.block != small.block;
	assert huge.offset == 0;
	assert openedSizes.length == 2;
	assert openedSizes[0] == 256 * MB;
	assert openedSizes[1] == 300 * MB;
	assert m.groups[huge.group].blocks[huge.slot].dedicated;
	const edge = take(m, request(256 * MB, 256, MemoryKind.DeviceLocal, Tiling.Linear));
	assert m.groups[edge.group].blocks[edge.slot].dedicated;
	give(m, huge);
	give(m, edge);
	give(m, small);
	assert m.blockCount == 0;
}

test "exhausting a block opens a new one and an emptied slot is reused" {
	openedSizes = [];
	let m = MemoryAllocator.forDevice(nvidia(4096));
	const first = take(m, request(40 * MB, 1, MemoryKind.WriteMappable, Tiling.Linear));
	const second = take(m, request(40 * MB, 1, MemoryKind.WriteMappable, Tiling.Linear));
	assert first.typeIndex == 2;
	assert second.block != first.block;
	assert second.slot == first.slot + 1;
	assert openedSizes[0] == 64 * MB && openedSizes[1] == 64 * MB;
	assert m.blockCount == 2;
	give(m, first);
	assert m.blockCount == 1;
	const third = take(m, request(40 * MB, 1, MemoryKind.WriteMappable, Tiling.Linear));
	assert third.slot == first.slot;
	assert third.block != first.block;
	give(m, second);
	give(m, third);
	assert m.blockCount == 0;
}

test "the allocation-count cap refuses the block past it by name" {
	let m = MemoryAllocator.forDevice(nvidia(2));
	const first = take(m, request(300 * MB, 1, MemoryKind.DeviceLocal, Tiling.Linear));
	const second = take(m, request(1 * MB, 1, MemoryKind.DeviceLocal, Tiling.Linear));
	const third = memoryAllocate(m, request(300 * MB, 1, MemoryKind.DeviceLocal, Tiling.Linear));
	assert !third.ok;
	if (!third.ok) { assert third.error == MemoryError.AllocationCountExceeded; }
	const fits = take(m, request(1 * MB, 1, MemoryKind.DeviceLocal, Tiling.Linear));
	assert fits.block == second.block;
	assert m.blockCount == 2;
	give(m, first);
	give(m, second);
	give(m, fits);
}

test "linear and optimal resources never share a block" {
	let m = MemoryAllocator.forDevice(nvidia(4096));
	const buffer = take(m, request(4096, 256, MemoryKind.DeviceLocal, Tiling.Linear));
	const image = take(m, request(4096, 65536, MemoryKind.DeviceLocal, Tiling.Optimal));
	const another = take(m, request(4096, 256, MemoryKind.DeviceLocal, Tiling.Linear));
	assert buffer.typeIndex == image.typeIndex;
	assert image.block != buffer.block;
	assert another.block == buffer.block;
	give(m, buffer);
	give(m, image);
	give(m, another);
	assert m.blockCount == 0;
}

test "a stale allocation is refused once its block is gone" {
	let m = MemoryAllocator.forDevice(lavapipe());
	const first = take(m, request(64, 1, MemoryKind.DeviceLocal, Tiling.Linear));
	give(m, first);
	const again = memoryFree(m, first);
	assert !again.ok;
	if (!again.ok) { assert again.error == MemoryError.InvalidAllocation; }
}
