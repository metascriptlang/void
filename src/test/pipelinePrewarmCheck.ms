// Prewarm: the keys a run built are read back (keysOf), kept as text, and built again before the
// first draw that needs them (prewarm), through the path a cache miss takes.

import { RenderState, BlendMode, Compare, Stencil, StencilOp } from "../gpu/state";
import { SWAPCHAIN_LAYOUT } from "../gpu/target";
import { layoutBase, programBase } from "../void2d/programs.ms";
import {
	PipelineCache,
	PipelineKey,
	IndexType,
	pipelineKey,
	record,
	keysOf,
	keyText,
	parseKey,
	keyFromText,
	keysText,
	parseKeys,
	keysFromText,
	prewarmRefusal,
} from "../gpu/pipeline";

when (voidDummy || (windows && !voidVulkan)) {
	import { doorSetup, doorShutdown } from "../gpu/doorGpu.ms";
	import { livePipelines } from "../gpu/door";
	import { pipelineFor, prewarm, closePipelines } from "../gpu/pipeline";
}
when (windows && !voidDummy && !voidVulkan) {
	import { warpDevice, warpContext } from "./d3d11Warp.h";
	@passL("-ld3d11");
}

const RGBA8 = 2;
const NO_DEPTH = 0;
const GOOD = "program=1 layout=2 indexType=1 state=3 targets=4 stencilOps=0 stencilMasks=0";

function maskWriter(): Stencil {
	return Stencil.defaults().withFunc(Compare.Always, 0xF0, 0x0F).withOps(
		StencilOp.Keep,
		StencilOp.Zero,
		StencilOp.IncrementClamp,
	);
}

function sampleKey(n: int32): PipelineKey {
	return {
		program: n,
		layout: n + 1,
		indexType: n % 2 == 0 ? IndexType.Uint16 : IndexType.Uint32,
		state: (n * 7919) as uint32,
		targets: (n * 104729) as uint32,
		stencilOps: 0,
		stencilMasks: 0,
	};
}

test "a key's text names its seven fields and reads back the same key" {
	const key: PipelineKey = {
		program: 12,
		layout: 3,
		indexType: IndexType.Uint32,
		state: 4294967295,
		targets: 65537,
		stencilOps: 0,
		stencilMasks: 255,
	};
	assert keyText(key) ==
		"program=12 layout=3 indexType=2 state=4294967295 targets=65537 stencilOps=0 stencilMasks=255";
	assert keyFromText(keyText(key)) == key;
	for (let n = 0; n < 40; n++) { assert keyFromText(keyText(sampleKey(n))) == sampleKey(n); }
}

test "the stencil words of a real render state survive the text" {
	const state: RenderState = RenderState.defaults().withStencil(maskWriter());
	const key: PipelineKey = pipelineKey(4, 2, true, state, SWAPCHAIN_LAYOUT);
	assert key.stencilOps != 0 && key.stencilMasks != 0;
	const back: PipelineKey = keyFromText(keyText(key));
	assert back == key;
	assert back.renderState().stencilOps() == state.stencilOps();
	assert back.renderState().stencilMasks() == state.stencilMasks();
}

function refusal(text: string): string {
	const parsed = parseKey(text);
	return parsed.ok ? "" : parsed.error;
}

function mutated(from: string, to: string): string {
	return GOOD.replace(from, to);
}

function badNumber(text: string, name: string, digits: string, limit: string): string {
	return `pipeline key text "${text}": ${name} holds "${digits}", not a number from 0 to ${limit}`;
}

test "text that is not a key is refused naming the field and the text" {
	assert refusal(GOOD) == "";
	assert refusal("") == "pipeline key text \"\" has 1 fields, a key has 7";
	assert refusal("program=1 layout=2") ==
		"pipeline key text \"program=1 layout=2\" has 2 fields, a key has 7";
	assert refusal(GOOD + " extra=1") ==
		`pipeline key text "${GOOD} extra=1" has 8 fields, a key has 7`;
	assert refusal(mutated(" layout", "  layout")) ==
		`pipeline key text "${mutated(" layout", "  layout")}" has 8 fields, a key has 7`;
	assert refusal(mutated("layout=2", "layer=2")) ==
		`pipeline key text "${mutated("layout=2", "layer=2")}": field 2 is "layer=2", expected layout=<number>`;
	assert refusal(mutated("state=3", "state=")) ==
		badNumber(mutated("state=3", "state="), "state", "", "4294967295");
	assert refusal(mutated("state=3", "state=-3")) ==
		badNumber(mutated("state=3", "state=-3"), "state", "-3", "4294967295");
	assert refusal(mutated("state=3", "state=0x3")) ==
		badNumber(mutated("state=3", "state=0x3"), "state", "0x3", "4294967295");
	assert refusal(mutated("state=3", "state=4294967296")) ==
		badNumber(mutated("state=3", "state=4294967296"), "state", "4294967296", "4294967295");
	assert refusal(mutated("indexType=1", "indexType=3")) ==
		badNumber(mutated("indexType=1", "indexType=3"), "indexType", "3", "2");
	assert refusal(mutated("program=1", "program=2147483648")) ==
		badNumber(mutated("program=1", "program=2147483648"), "program", "2147483648", "2147483647");
}

test "a set of keys is a magic line then one key per line, and reads back in order" {
	const keys: PipelineKey[] = [sampleKey(1), sampleKey(2), sampleKey(3)];
	const text = keysText(keys);
	assert text == `pipelines-1\n${keyText(sampleKey(1))}\n${keyText(sampleKey(2))}\n${keyText(sampleKey(3))}\n`;
	const back = keysFromText(text);
	assert back.length == 3;
	for (let i = 0; i < 3; i++) { assert back[i] == keys[i]; }
	assert keysFromText(keysText([])).length == 0;
}

function keysRefusal(text: string): string {
	const parsed = parseKeys(text);
	return parsed.ok ? "" : parsed.error;
}

test "a set of keys that is not one is refused naming the line" {
	const one = `pipelines-1\n${GOOD}\n`;
	assert keysRefusal(one) == "";
	assert keysRefusal("") == "pipeline keys text starts with \"\", expected \"pipelines-1\"";
	assert keysRefusal(`pipelines-2\n${GOOD}\n`) ==
		"pipeline keys text starts with \"pipelines-2\", expected \"pipelines-1\"";
	assert keysRefusal(`pipelines-1\n${GOOD}`) == "pipeline keys text does not end with a newline";
	assert keysRefusal(`pipelines-1\n${GOOD}\n\n${GOOD}\n`) ==
		`line 3: pipeline key text "" has 1 fields, a key has 7`;
	assert keysRefusal(`pipelines-1\n${GOOD}\nprogram=1\n`) ==
		"line 3: pipeline key text \"program=1\" has 1 fields, a key has 7";
}

test "keysOf answers the keys the cache holds, in the order they were recorded" {
	const cache: PipelineCache = PipelineCache.empty();
	assert cache.keysOf().length == 0;
	record(cache, sampleKey(5), 1);
	record(cache, sampleKey(2), 2);
	record(cache, sampleKey(5), 3);
	record(cache, sampleKey(9), 0);
	const keys = cache.keysOf();
	assert keys.length == 3;
	assert keys[0] == sampleKey(5) && keys[1] == sampleKey(2) && keys[2] == sampleKey(9);
}

test "a key whose program, layout, index type or targets cannot be built is refused naming the key" {
	const key: PipelineKey = { ...sampleKey(0), program: 2000000000, layout: 0 };
	assert prewarmRefusal(key) ==
		`prewarm of ${keyText(key)}: program 2000000000 was never registered`;
	assert prewarmRefusal({ ...sampleKey(0), program: -1 }) ==
		`prewarm of ${keyText({ ...sampleKey(0), program: -1 })}: program -1 was never registered`;
	const named: PipelineKey = pipelineKey(programBase, layoutBase, false, RenderState.defaults(), SWAPCHAIN_LAYOUT);
	assert prewarmRefusal(named) ==
		`prewarm of ${keyText(named)}: its targets name the environment; key a prewarm with resolved targets`;
}

when (voidDummy || (windows && !voidVulkan)) {
	function openDoor(): void {
		when (voidDummy) {
			doorSetup(null, null, RGBA8, NO_DEPTH, 1);
		} else {
			doorSetup(warpDevice(), warpContext(), RGBA8, NO_DEPTH, 1);
		}
	}

	function states(): RenderState[] {
		return [
			RenderState.defaults(),
			RenderState.defaults().withBlendMode(BlendMode.Alpha),
			RenderState.defaults().withStencil(maskWriter()),
		];
	}

	// Three pipelines of one program and layout that differ in state, as a scene's passes do.
	function lookUp(cache: PipelineCache): uint32[] {
		const found: uint32[] = [];
		for (const state of states()) {
			found.push(pipelineFor(cache, programBase, layoutBase, false, state, SWAPCHAIN_LAYOUT));
		}
		return found;
	}

	test "keysOf after a few lookups returns exactly the keys those lookups made" {
		openDoor();
		const cache: PipelineCache = PipelineCache.empty();
		const first = lookUp(cache);
		lookUp(cache);
		const keys = cache.keysOf();
		assert keys.length == 3;
		for (let i = 0; i < 3; i++) {
			assert keys[i] == pipelineKey(programBase, layoutBase, false, states()[i], SWAPCHAIN_LAYOUT.resolved());
			assert cache.entries[i].pipeline == first[i];
		}
		closePipelines(cache);
		doorShutdown();
	}

	test "prewarm on a fresh cache builds each key once and the lookup that follows builds nothing" {
		openDoor();
		const warmed: PipelineCache = PipelineCache.empty();
		const ran: PipelineCache = PipelineCache.empty();
		lookUp(ran);
		const keys = ran.keysOf();
		const before = livePipelines();
		assert prewarm(warmed, keys) == 3;
		assert livePipelines() == before + 3;
		const afterWarm = livePipelines();
		const handles = lookUp(warmed);
		assert livePipelines() == afterWarm;
		for (let i = 0; i < 3; i++) {
			assert handles[i] == warmed.entries[i].pipeline && handles[i] != 0;
			assert warmed.entries[i].key == keys[i];
		}
		assert prewarm(warmed, keys) == 0;
		assert livePipelines() == afterWarm;
		closePipelines(ran);
		closePipelines(warmed);
		doorShutdown();
	}

	test "prewarm from the text a run kept builds the keys that run built" {
		openDoor();
		const ran: PipelineCache = PipelineCache.empty();
		lookUp(ran);
		const text = keysText(ran.keysOf());
		const warmed: PipelineCache = PipelineCache.empty();
		assert prewarm(warmed, keysFromText(text)) == 3;
		assert keysText(warmed.keysOf()) == text;
		closePipelines(ran);
		closePipelines(warmed);
		doorShutdown();
	}

	test "after a new context prewarm builds the keys the cache kept and drops no key" {
		openDoor();
		const cache: PipelineCache = PipelineCache.empty();
		lookUp(cache);
		const keys = cache.keysOf();
		openDoor();
		assert cache.keysOf().length == 3;
		assert prewarm(cache, keys) == 3;
		assert livePipelines() == 3;
		for (let i = 0; i < 3; i++) { assert cache.entries[i].pipeline != 0; }
		assert cache.keysOf().length == 3;
		closePipelines(cache);
		doorShutdown();
	}
}
