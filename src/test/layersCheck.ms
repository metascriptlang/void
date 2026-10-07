import {
	DEFAULT_LAYERS,
	ALL_LAYERS,
	layerBit,
	layersEnable,
	layersDisable,
	layersToggle,
	layersTest,
	layersHas,
} from "../void3d/layers";

test "a new mask is layer 0 alone, as three's Layers constructor sets it" {
	assert DEFAULT_LAYERS == 1;
	assert layersHas(DEFAULT_LAYERS, 0);
	assert !layersHas(DEFAULT_LAYERS, 1);
	assert ALL_LAYERS == 0xFFFFFFFF;
}

test "layer 31 is a bit of the mask and not a sign" {
	assert layerBit(0) == 1;
	assert layerBit(31) == 0x80000000;
	assert layersHas(layerBit(31), 31);
	assert !layersHas(layerBit(31), 30);
}

test "enable adds a layer, disable removes it, toggle flips it" {
	let mask: uint32 = DEFAULT_LAYERS;
	mask = layersEnable(mask, 3);
	assert mask == 9;
	mask = layersEnable(mask, 3);
	assert mask == 9;
	mask = layersDisable(mask, 0);
	assert mask == 8;
	mask = layersDisable(mask, 0);
	assert mask == 8;
	mask = layersToggle(mask, 3);
	assert mask == 0;
	mask = layersToggle(mask, 31);
	assert mask == 0x80000000;
	mask = layersDisable(mask, 31);
	assert mask == 0;
}

test "two masks see each other when they share at least one layer" {
	assert layersTest(layerBit(2) | layerBit(5), layerBit(5));
	assert !layersTest(layerBit(2), layerBit(5));
	assert !layersTest(0, ALL_LAYERS);
	assert layersTest(ALL_LAYERS, layerBit(31));
}
