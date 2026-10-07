export const LAYER_COUNT: int32 = 32;

export const DEFAULT_LAYERS: uint32 = 1;

export const ALL_LAYERS: uint32 = 0xFFFFFFFF;

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

export function layersHas(mask: uint32, layer: int32): boolean {
	return (mask & layerBit(layer)) != 0;
}

export function layersTest(a: uint32, b: uint32): boolean {
	return (a & b) != 0;
}
