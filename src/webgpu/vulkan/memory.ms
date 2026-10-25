export enum MemoryProperty {
	DeviceLocal,
	HostVisible,
	HostCoherent,
	HostCached,
	LazilyAllocated,
	Protected,
	DeviceCoherentAmd,
	DeviceUncachedAmd,
	RdmaCapableNv,
}

export enum MemoryKind {
	DeviceLocal,
	WriteMappable,
	ReadMappable,
	LazilyAllocated,
}

export enum Tiling {
	Linear,
	Optimal,
}

export enum Dedication {
	None,
	Preferred,
	Required,
}

export enum MemoryError {
	OutOfMemory,
	InvalidAllocation,
	NoCompatibleMemory,
	AllocationCountExceeded,
	BlockAllocationFailed,
}

export const NO_NODE: uint32 = 0xFFFFFFFF;
export const DEFAULT_MAX_ALLOCATIONS: uint32 = 128 * 1024;

const NUM_TOP_BINS: int32 = 32;
const BINS_PER_LEAF: int32 = 8;
const TOP_BINS_INDEX_SHIFT: uint32 = 3;
const LEAF_BINS_INDEX_MASK: uint32 = 0x7;
const MANTISSA_BITS: uint32 = 3;
const MANTISSA_VALUE: uint32 = 8;
const MANTISSA_MASK: uint32 = 7;

const MEGABYTE: uint64 = 1024 * 1024;
const BLOCK_SIZE_STEP: uint64 = 4 * MEGABYTE;
const BLOCK_SIZE_MAX: uint64 = 256 * MEGABYTE;

struct OffsetNode {
	dataOffset: uint32;
	dataSize: uint32;
	binListPrev: uint32;
	binListNext: uint32;
	neighbourPrev: uint32;
	neighbourNext: uint32;
	used: boolean;
}

export struct OffsetAllocator {
	size: uint32;
	maxAllocations: uint32;
	freeStorage: uint32;
	usedBinsTop: uint32;
	usedBins: Vec<uint32>;
	binIndices: Vec<uint32>;
	nodes: Vec<OffsetNode>;
	freeNodes: Vec<uint32>;
	freeOffset: uint32;
}

export struct OffsetAllocation {
	offset: uint32;
	node: uint32;
}

export struct AllocationSizes {
	deviceBlockSize: uint64;
	hostBlockSize: uint64;
}

export struct DedicatedOwner {
	buffer: uint32;
	image: uint32;
}

export struct MemoryType {
	properties: BitSet<MemoryProperty>;
	heap: int32;
}

export struct MemoryDevice {
	types: Vec<MemoryType>;
	heapSizes: Vec<uint64>;
	nonCoherentAtomSize: uint64;
	maxAllocationCount: uint32;
	openBlock: (typeIndex: int32, size: uint64, owner: DedicatedOwner) => uint32;
	closeBlock: (block: uint32) => void;
}

struct MemoryBlock {
	id: uint32;
	size: uint64;
	dedicated: boolean;
	dedicatedAllocated: uint64;
	offsets: OffsetAllocator;
}

struct MemoryGroup {
	typeIndex: int32;
	tiling: Tiling;
	blocks: Vec<MemoryBlock>;
}

export struct MemoryAllocator {
	device: MemoryDevice;
	sizes: AllocationSizes;
	groups: Vec<MemoryGroup>;
	blockCount: uint32;
}

export struct MemoryRequest {
	size: uint64;
	alignment: uint64;
	typeBits: uint32;
	kind: MemoryKind;
	tiling: Tiling;
	dedication: Dedication;
	owner: DedicatedOwner;
}

export struct MemoryAllocation {
	block: uint32;
	offset: uint64;
	size: uint64;
	typeIndex: int32;
	group: int32;
	slot: int32;
	node: uint32;
}

@inline function bit(index: uint32): uint32 { return (1 as uint32) << index; }

function bitsFrom(v: uint32, start: uint32): uint32 {
	if (start >= 32) { return 0; }
	return v & ~(bit(start) - 1);
}

function highestSetBit(v: uint32): uint32 {
	let index: uint32 = 31;
	while ((v & bit(index)) == 0) { index -= 1; }
	return index;
}

function lowestSetBit(v: uint32): uint32 {
	let index: uint32 = 0;
	while ((v & bit(index)) == 0) { index += 1; }
	return index;
}

export function toFloatRoundUp(size: uint32): uint32 {
	if (size < MANTISSA_VALUE) { return size; }
	const mantissaStartBit = highestSetBit(size) - MANTISSA_BITS;
	const exponent = mantissaStartBit + 1;
	let mantissa = (size >> mantissaStartBit) & MANTISSA_MASK;
	if ((size & (bit(mantissaStartBit) - 1)) != 0) { mantissa += 1; }
	return (exponent << MANTISSA_BITS) + mantissa;
}

export function toFloatRoundDown(size: uint32): uint32 {
	if (size < MANTISSA_VALUE) { return size; }
	const mantissaStartBit = highestSetBit(size) - MANTISSA_BITS;
	const exponent = mantissaStartBit + 1;
	const mantissa = (size >> mantissaStartBit) & MANTISSA_MASK;
	return (exponent << MANTISSA_BITS) | mantissa;
}

function freeNode(dataOffset: uint32, dataSize: uint32, binListNext: uint32): OffsetNode {
	return {
		dataOffset: dataOffset,
		dataSize: dataSize,
		binListPrev: NO_NODE,
		binListNext: binListNext,
		neighbourPrev: NO_NODE,
		neighbourNext: NO_NODE,
		used: false,
	};
}

function emptyOffsets(): OffsetAllocator {
	return {
		size: 0,
		maxAllocations: 0,
		freeStorage: 0,
		usedBinsTop: 0,
		usedBins: [],
		binIndices: [],
		nodes: [],
		freeNodes: [],
		freeOffset: 0,
	};
}

export function sized(
	this typeof OffsetAllocator,
	size: uint32,
	maxAllocations: uint32,
): OffsetAllocator {
	let allocator = emptyOffsets();
	allocator.size = size;
	allocator.maxAllocations = maxAllocations;
	resetOffsets(allocator);
	return allocator;
}

export function resetOffsets(ref a: OffsetAllocator): void {
	a.freeStorage = 0;
	a.usedBinsTop = 0;
	a.freeOffset = a.maxAllocations - 1;
	a.usedBins = [];
	for (let i = 0; i < NUM_TOP_BINS; i++) { a.usedBins.push(0); }
	a.binIndices = [];
	for (let i = 0; i < NUM_TOP_BINS * BINS_PER_LEAF; i++) { a.binIndices.push(NO_NODE); }
	a.nodes = [];
	a.freeNodes = [];
	for (let i: uint32 = 0; i < a.maxAllocations; i++) {
		a.nodes.push(freeNode(0, 0, NO_NODE));
		a.freeNodes.push(a.maxAllocations - i - 1);
	}
	insertNodeIntoBin(a, a.size, 0);
}

function insertNodeIntoBin(ref a: OffsetAllocator, size: uint32, dataOffset: uint32): uint32 {
	const binIndex = toFloatRoundDown(size);
	const topBinIndex = binIndex >> TOP_BINS_INDEX_SHIFT;
	const leafBinIndex = binIndex & LEAF_BINS_INDEX_MASK;
	if (a.binIndices[binIndex] == NO_NODE) {
		a.usedBins[topBinIndex] |= bit(leafBinIndex);
		a.usedBinsTop |= bit(topBinIndex);
	}
	const topNodeIndex = a.binIndices[binIndex];
	const nodeIndex = a.freeNodes[a.freeOffset];
	a.freeOffset -= 1;
	a.nodes[nodeIndex] = freeNode(dataOffset, size, topNodeIndex);
	if (topNodeIndex != NO_NODE) { a.nodes[topNodeIndex].binListPrev = nodeIndex; }
	a.binIndices[binIndex] = nodeIndex;
	a.freeStorage += size;
	return nodeIndex;
}

function removeNodeFromBin(ref a: OffsetAllocator, nodeIndex: uint32): void {
	const prev = a.nodes[nodeIndex].binListPrev;
	const next = a.nodes[nodeIndex].binListNext;
	if (prev != NO_NODE) {
		a.nodes[prev].binListNext = next;
		if (next != NO_NODE) { a.nodes[next].binListPrev = prev; }
	} else {
		const binIndex = toFloatRoundDown(a.nodes[nodeIndex].dataSize);
		const topBinIndex = binIndex >> TOP_BINS_INDEX_SHIFT;
		const leafBinIndex = binIndex & LEAF_BINS_INDEX_MASK;
		a.binIndices[binIndex] = next;
		if (next != NO_NODE) { a.nodes[next].binListPrev = NO_NODE; }
		if (a.binIndices[binIndex] == NO_NODE) {
			a.usedBins[topBinIndex] &= ~bit(leafBinIndex);
			if (a.usedBins[topBinIndex] == 0) { a.usedBinsTop &= ~bit(topBinIndex); }
		}
	}
	a.freeOffset += 1;
	a.freeNodes[a.freeOffset] = nodeIndex;
	a.freeStorage -= a.nodes[nodeIndex].dataSize;
}

export function offsetAllocate(
	ref a: OffsetAllocator,
	size: uint32,
): Result<OffsetAllocation, MemoryError> {
	if (a.freeOffset == 0) { return Result.err(MemoryError.OutOfMemory); }
	const minBinIndex = toFloatRoundUp(size);
	const minTopBinIndex = minBinIndex >> TOP_BINS_INDEX_SHIFT;
	const minLeafBinIndex = minBinIndex & LEAF_BINS_INDEX_MASK;
	let topBinIndex = minTopBinIndex;
	let leafBits: uint32 = 0;
	if ((a.usedBinsTop & bit(topBinIndex)) != 0) {
		leafBits = bitsFrom(a.usedBins[topBinIndex], minLeafBinIndex);
	}
	let leafBinIndex: uint32 = 0;
	if (leafBits != 0) {
		leafBinIndex = lowestSetBit(leafBits);
	} else {
		const topBits = bitsFrom(a.usedBinsTop, minTopBinIndex + 1);
		if (topBits == 0) { return Result.err(MemoryError.OutOfMemory); }
		topBinIndex = lowestSetBit(topBits);
		leafBinIndex = lowestSetBit(a.usedBins[topBinIndex]);
	}
	const binIndex = (topBinIndex << TOP_BINS_INDEX_SHIFT) | leafBinIndex;

	const nodeIndex = a.binIndices[binIndex];
	const nodeTotalSize = a.nodes[nodeIndex].dataSize;
	const binListNext = a.nodes[nodeIndex].binListNext;
	a.nodes[nodeIndex].dataSize = size;
	a.nodes[nodeIndex].used = true;
	a.binIndices[binIndex] = binListNext;
	if (binListNext != NO_NODE) { a.nodes[binListNext].binListPrev = NO_NODE; }
	a.freeStorage -= nodeTotalSize;
	if (a.binIndices[binIndex] == NO_NODE) {
		a.usedBins[topBinIndex] &= ~bit(leafBinIndex);
		if (a.usedBins[topBinIndex] == 0) { a.usedBinsTop &= ~bit(topBinIndex); }
	}

	const remainderSize = nodeTotalSize - size;
	if (remainderSize > 0) {
		const dataOffset = a.nodes[nodeIndex].dataOffset;
		const newNodeIndex = insertNodeIntoBin(a, remainderSize, dataOffset + size);
		const neighbourNext = a.nodes[nodeIndex].neighbourNext;
		if (neighbourNext != NO_NODE) { a.nodes[neighbourNext].neighbourPrev = newNodeIndex; }
		a.nodes[newNodeIndex].neighbourPrev = nodeIndex;
		a.nodes[newNodeIndex].neighbourNext = neighbourNext;
		a.nodes[nodeIndex].neighbourNext = newNodeIndex;
	}
	return Result.ok({ offset: a.nodes[nodeIndex].dataOffset, node: nodeIndex });
}

export function offsetFree(
	ref a: OffsetAllocator,
	allocation: OffsetAllocation,
): Result<void, MemoryError> {
	const nodeIndex = allocation.node;
	if (nodeIndex >= a.maxAllocations || !a.nodes[nodeIndex].used) {
		return Result.err(MemoryError.InvalidAllocation);
	}
	let offset = a.nodes[nodeIndex].dataOffset;
	let size = a.nodes[nodeIndex].dataSize;

	const prev = a.nodes[nodeIndex].neighbourPrev;
	if (prev != NO_NODE && !a.nodes[prev].used) {
		offset = a.nodes[prev].dataOffset;
		size += a.nodes[prev].dataSize;
		removeNodeFromBin(a, prev);
		a.nodes[nodeIndex].neighbourPrev = a.nodes[prev].neighbourPrev;
	}
	const next = a.nodes[nodeIndex].neighbourNext;
	if (next != NO_NODE && !a.nodes[next].used) {
		size += a.nodes[next].dataSize;
		removeNodeFromBin(a, next);
		a.nodes[nodeIndex].neighbourNext = a.nodes[next].neighbourNext;
	}

	const neighbourPrev = a.nodes[nodeIndex].neighbourPrev;
	const neighbourNext = a.nodes[nodeIndex].neighbourNext;
	a.freeOffset += 1;
	a.freeNodes[a.freeOffset] = nodeIndex;
	const combined = insertNodeIntoBin(a, size, offset);
	if (neighbourNext != NO_NODE) {
		a.nodes[combined].neighbourNext = neighbourNext;
		a.nodes[neighbourNext].neighbourPrev = combined;
	}
	if (neighbourPrev != NO_NODE) {
		a.nodes[combined].neighbourPrev = neighbourPrev;
		a.nodes[neighbourPrev].neighbourNext = combined;
	}
	return Result.ok(null);
}

export function allocated(this a: OffsetAllocator): uint32 { return a.size - a.freeStorage; }

function clampBlockSize(size: uint64): uint64 {
	const clamped = Math.min(Math.max(size, BLOCK_SIZE_STEP), BLOCK_SIZE_MAX);
	if (clamped % BLOCK_SIZE_STEP == 0) { return clamped; }
	return BLOCK_SIZE_STEP * (clamped / BLOCK_SIZE_STEP + 1);
}

export function clamped(
	this typeof AllocationSizes,
	device: uint64,
	host: uint64,
): AllocationSizes {
	return { deviceBlockSize: clampBlockSize(device), hostBlockSize: clampBlockSize(host) };
}

export function memoryPropertiesOf(flags: uint32): BitSet<MemoryProperty> {
	return ((flags & 0x1FF) as uint16) as BitSet<MemoryProperty>;
}

function usable(properties: BitSet<MemoryProperty>): boolean {
	return !properties.has(MemoryProperty.DeviceCoherentAmd) &&
		!properties.has(MemoryProperty.Protected);
}

function required(kind: MemoryKind): BitSet<MemoryProperty> {
	const none = 0 as BitSet<MemoryProperty>;
	return match (kind) {
		MemoryKind.DeviceLocal => none.incl(MemoryProperty.DeviceLocal),
		MemoryKind.WriteMappable => none.incl(MemoryProperty.HostVisible),
		MemoryKind.ReadMappable => none.incl(MemoryProperty.HostVisible),
		MemoryKind.LazilyAllocated => none,
	};
}

function preferred(kind: MemoryKind): Vec<MemoryProperty> {
	return match (kind) {
		MemoryKind.DeviceLocal => [MemoryProperty.DeviceLocal],
		MemoryKind.WriteMappable => [MemoryProperty.HostCoherent],
		MemoryKind.ReadMappable => [MemoryProperty.HostCached],
		MemoryKind.LazilyAllocated => [MemoryProperty.LazilyAllocated, MemoryProperty.DeviceLocal],
	};
}

function betterType(
	this device: MemoryDevice,
	candidate: int32,
	best: int32,
	ranking: Readonly<Span<MemoryProperty>>,
): boolean {
	const has = device.types[candidate].properties;
	const bestHas = device.types[best].properties;
	for (const property of ranking) {
		if (has.has(property) != bestHas.has(property)) { return has.has(property); }
	}
	const heapSize = device.heapSizes[device.types[candidate].heap];
	return heapSize > device.heapSizes[device.types[best].heap];
}

export function selectMemoryType(
	this device: MemoryDevice,
	typeBits: uint32,
	kind: MemoryKind,
): Result<int32, MemoryError> {
	const needs = required(kind);
	const ranking = preferred(kind);
	let best: int32 = -1;
	for (let i: int32 = 0; i < device.types.length; i++) {
		if ((typeBits & bit(i as uint32)) == 0) { continue; }
		const properties = device.types[i].properties;
		if (!needs.isSubsetOf(properties) || !usable(properties)) { continue; }
		if (best < 0 || device.betterType(i, best, ranking)) { best = i; }
	}
	if (best < 0) { return Result.err(MemoryError.NoCompatibleMemory); }
	return Result.ok(best);
}

export function forDevice(this typeof MemoryAllocator, device: MemoryDevice): MemoryAllocator {
	let groups: Vec<MemoryGroup> = [];
	for (let i: int32 = 0; i < device.types.length; i++) {
		groups.push({ typeIndex: i, tiling: Tiling.Linear, blocks: [] });
		groups.push({ typeIndex: i, tiling: Tiling.Optimal, blocks: [] });
	}
	return {
		device: device,
		sizes: AllocationSizes.clamped(256 * MEGABYTE, 64 * MEGABYTE),
		groups: groups,
		blockCount: 0,
	};
}

function blockSizeOf(this m: MemoryAllocator, typeIndex: int32): uint64 {
	const memoryType = m.device.types[typeIndex];
	const size = memoryType.properties.has(MemoryProperty.HostVisible)
		? m.sizes.hostBlockSize
		: m.sizes.deviceBlockSize;
	return Math.min(size, m.device.heapSizes[memoryType.heap]);
}

function emptyBlock(): MemoryBlock {
	return { id: 0, size: 0, dedicated: false, dedicatedAllocated: 0, offsets: emptyOffsets() };
}

function addBlock(
	ref m: MemoryAllocator,
	group: int32,
	size: uint64,
	owner: DedicatedOwner,
	dedicated: boolean,
	replace: int32,
): Result<int32, MemoryError> {
	if (m.blockCount >= m.device.maxAllocationCount) {
		return Result.err(MemoryError.AllocationCountExceeded);
	}
	const id = m.device.openBlock(m.groups[group].typeIndex, size, owner);
	if (id == 0) { return Result.err(MemoryError.BlockAllocationFailed); }
	m.blockCount += 1;
	const block: MemoryBlock = {
		id: id,
		size: size,
		dedicated: dedicated,
		dedicatedAllocated: 0,
		offsets: dedicated
			? emptyOffsets()
			: OffsetAllocator.sized(size as uint32, DEFAULT_MAX_ALLOCATIONS),
	};
	if (replace >= 0) {
		m.groups[group].blocks[replace] = block;
		return Result.ok(replace);
	}
	m.groups[group].blocks.push(block);
	return Result.ok(m.groups[group].blocks.length as int32 - 1);
}

function blockAllocate(
	ref block: MemoryBlock,
	size: uint64,
): Result<OffsetAllocation, MemoryError> {
	if (!block.dedicated) { return offsetAllocate(block.offsets, size as uint32); }
	if (block.dedicatedAllocated != 0 || block.size != size) {
		return Result.err(MemoryError.OutOfMemory);
	}
	block.dedicatedAllocated = size;
	return Result.ok({ offset: 0, node: NO_NODE });
}

function alignUp(value: uint64, alignment: uint64): uint64 {
	return (value + alignment - 1) / alignment * alignment;
}

function placed(
	this m: MemoryAllocator,
	group: int32,
	slot: int32,
	inBlock: OffsetAllocation,
	request: MemoryRequest,
	alignment: uint64,
): MemoryAllocation {
	return {
		block: m.groups[group].blocks[slot].id,
		offset: alignUp(inBlock.offset as uint64, alignment),
		size: request.size,
		typeIndex: m.groups[group].typeIndex,
		group: group,
		slot: slot,
		node: inBlock.node,
	};
}

const NO_OWNER: DedicatedOwner = { buffer: 0, image: 0 };

function wantsDedicated(this m: MemoryAllocator, dedication: Dedication): boolean {
	return match (dedication) {
		Dedication.None => false,
		Dedication.Preferred => m.blockCount <= m.device.maxAllocationCount / 4 * 3,
		Dedication.Required => true,
	};
}

export function memoryAllocate(
	ref m: MemoryAllocator,
	request: MemoryRequest,
): Result<MemoryAllocation, MemoryError> {
	const typeIndex = try m.device.selectMemoryType(request.typeBits, request.kind);
	const group = typeIndex * 2 + (request.tiling as int32);
	const properties = m.device.types[typeIndex].properties;
	let alignment = Math.max(request.alignment, 1 as uint64);
	if (properties.has(MemoryProperty.HostVisible) &&
		!properties.has(MemoryProperty.HostCoherent)) {
		alignment = Math.max(alignment, m.device.nonCoherentAtomSize);
	}

	const blockSize = m.blockSizeOf(typeIndex);
	const padded = request.size + alignment - 1;
	if (padded > blockSize || m.wantsDedicated(request.dedication)) {
		let free: int32 = -1;
		for (let i: int32 = 0; i < m.groups[group].blocks.length && free < 0; i++) {
			if (m.groups[group].blocks[i].id == 0) { free = i; }
		}
		const slot = try addBlock(m, group, request.size, request.owner, true, free);
		const whole = try blockAllocate(m.groups[group].blocks[slot], request.size);
		return Result.ok(m.placed(group, slot, whole, request, 1));
	}

	let empty: int32 = -1;
	for (let i: int32 = 0; i < m.groups[group].blocks.length; i++) {
		if (m.groups[group].blocks[i].id == 0) {
			if (empty < 0) { empty = i; }
			continue;
		}
		const inBlock = blockAllocate(m.groups[group].blocks[i], padded);
		if (inBlock.ok) { return Result.ok(m.placed(group, i, inBlock.value, request, alignment)); }
	}
	const slot = try addBlock(m, group, blockSize, NO_OWNER, false, empty);
	const inBlock = try blockAllocate(m.groups[group].blocks[slot], padded);
	return Result.ok(m.placed(group, slot, inBlock, request, alignment));
}

export function memoryFree(
	ref m: MemoryAllocator,
	allocation: MemoryAllocation,
): Result<void, MemoryError> {
	const group = allocation.group;
	const slot = allocation.slot;
	if (group < 0 || group >= m.groups.length ||
		slot < 0 || slot >= m.groups[group].blocks.length) {
		return Result.err(MemoryError.InvalidAllocation);
	}
	if (m.groups[group].blocks[slot].id != allocation.block || allocation.block == 0) {
		return Result.err(MemoryError.InvalidAllocation);
	}
	if (m.groups[group].blocks[slot].dedicated) {
		m.groups[group].blocks[slot].dedicatedAllocated = 0;
	} else {
		const node: OffsetAllocation = { offset: 0, node: allocation.node };
		const freed = try offsetFree(m.groups[group].blocks[slot].offsets, node);
	}
	const emptied = m.groups[group].blocks[slot].dedicated
		? m.groups[group].blocks[slot].dedicatedAllocated == 0
		: m.groups[group].blocks[slot].offsets.allocated() == 0;
	if (emptied) {
		m.device.closeBlock(allocation.block);
		m.groups[group].blocks[slot] = emptyBlock();
		m.blockCount -= 1;
	}
	return Result.ok(null);
}
