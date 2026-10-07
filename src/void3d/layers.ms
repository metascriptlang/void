// three.js `Layers` (`src/core/Layers.js:13-100` at `d4ea9b9`) as plain 32-bit masks: a node and a
// camera each own one, and the node is drawn for the camera when the two share a layer. Heaps has
// no such mask (its `Object.visible` is the only switch, per object and per subtree), so this is
// the three.js mechanism and nothing of Heaps' is diverged from.
//
// A mask is a `uint32` and not a struct: three's own `Layers` is one number, and a node row stores
// one inline.

export const LAYER_COUNT: int32 = 32;

// `this.mask = 1 | 0` in three's constructor: layer 0 alone, for a node and for a camera.
export const DEFAULT_LAYERS: uint32 = 1;

// `enableAll`: `0xffffffff | 0`.
export const ALL_LAYERS: uint32 = 0xFFFFFFFF;

// three leaves `1 << layer` with a layer outside 0 to 31 to JavaScript's shift-count wrap
// (layer 32 is layer 0). Here the same shift in C is undefined, so the layer is checked.
export function layerBit(layer: int32): uint32 {
	if (layer < 0 || layer >= LAYER_COUNT) { stopOnLayer(layer); }
	return (1 as uint32) << (layer as uint32);
}

function stopOnLayer(layer: int32): void {
	console.log(`void3d: layer ${layer} is outside 0 to 31`);
	unreachable;
}

export function layersEnable(mask: uint32, layer: int32): uint32 {
	return mask | layerBit(layer);
}

export function layersDisable(mask: uint32, layer: int32): uint32 {
	return mask & ~layerBit(layer);
}

export function layersToggle(mask: uint32, layer: int32): uint32 {
	return mask ^ layerBit(layer);
}

// `Layers.isEnabled`.
export function layersHas(mask: uint32, layer: int32): boolean {
	return (mask & layerBit(layer)) != 0;
}

// `Layers.test`: at least one layer in common.
export function layersTest(a: uint32, b: uint32): boolean {
	return (a & b) != 0;
}
