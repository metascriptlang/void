import { RenderState, Compare, Stencil, StencilOp } from "../gpu/state";
import { SWAPCHAIN_LAYOUT } from "../gpu/target";
import { PipelineCache, PipelineKey, IndexType, pipelineKey, keyHash, record } from "../gpu/pipeline";

function keyFor(state: RenderState): PipelineKey {
	return pipelineKey(3, 2, true, state, SWAPCHAIN_LAYOUT);
}

function stenciled(stencil: Stencil): PipelineKey {
	return keyFor(RenderState.defaults().withStencil(stencil));
}

function maskWriter(): Stencil {
	return Stencil.defaults().withFunc(Compare.Always, 0xFF, 0xFF).withOps(
		StencilOp.Keep,
		StencilOp.Keep,
		StencilOp.Replace,
	);
}

test "a state without a stencil keys as the key built before stencil existed" {
	const state: RenderState = RenderState.defaults();
	const expected: PipelineKey = {
		program: 3,
		layout: 2,
		indexType: IndexType.Uint16,
		state: state.bits(),
		targets: SWAPCHAIN_LAYOUT.formatBits(),
		stencilOps: 0,
		stencilMasks: 0,
	};
	assert keyFor(state) == expected;
	assert keyFor(state.withStencil(null)) == expected;
}

test "a stencil changes the key words only and leaves the packed state alone" {
	const plain: PipelineKey = keyFor(RenderState.defaults());
	const key: PipelineKey = stenciled(maskWriter());
	assert key.state == plain.state && key.targets == plain.targets;
	assert key != plain;
}

test "keys differing only in stencil ops or masks hash and compare different" {
	const base: Stencil = maskWriter();
	const variants: Vec<Stencil> = [
		base,
		base.withOps(StencilOp.Keep, StencilOp.Keep, StencilOp.IncrementWrap),
		base.withOps(StencilOp.Zero, StencilOp.Keep, StencilOp.Replace),
		base.withOps(StencilOp.Keep, StencilOp.Invert, StencilOp.Replace),
		base.withFunc(Compare.Equal, 0xFF, 0xFF),
		base.withFunc(Compare.Always, 0x0F, 0xFF),
		base.withFunc(Compare.Always, 0xFF, 0x0F),
		{ ...base, back: { ...base.back, passOp: StencilOp.DecrementClamp } },
	];
	const cache: PipelineCache = PipelineCache.empty();
	for (let i = 0; i < (variants.length as int32); i++) {
		const key: PipelineKey = stenciled(variants[i]);
		for (let j = 0; j < i; j++) {
			assert key != stenciled(variants[j]);
			assert keyHash(key) != keyHash(stenciled(variants[j]));
		}
		assert key == stenciled(variants[i]);
		record(cache, key, (i + 1) as uint32);
	}
	assert cache.entries.length == variants.length;
	for (let i = 0; i < (variants.length as int32); i++) {
		assert cache.indexOf(stenciled(variants[i])) == i;
	}
	assert cache.indexOf(keyFor(RenderState.defaults())) == -1;
}

test "a write mask of zero is a stencil, distinct from no stencil" {
	const frozen: Stencil = maskWriter().withFunc(Compare.Always, 0, 0);
	const absent: PipelineKey = keyFor(RenderState.defaults());
	const zero: PipelineKey = stenciled(frozen);
	assert zero.stencilMasks == 0 && zero.stencilOps != 0;
	assert zero != absent && keyHash(zero) != keyHash(absent);
	assert zero.renderState().stencil == frozen;
	assert absent.renderState().stencil == null;
	const bare: PipelineKey = stenciled(Stencil.defaults().withFunc(Compare.Always, 0, 0));
	assert bare != absent;
}

test "a stencil reads back from its key words" {
	const both: Stencil = {
		front: {
			compare: Compare.NotEqual,
			failOp: StencilOp.Zero,
			depthFailOp: StencilOp.DecrementWrap,
			passOp: StencilOp.IncrementClamp,
		},
		back: {
			compare: Compare.LessEqual,
			failOp: StencilOp.Invert,
			depthFailOp: StencilOp.Replace,
			passOp: StencilOp.Keep,
		},
		readMask: 0xA5,
		writeMask: 0x5A,
	};
	assert stenciled(both).renderState().stencil == both;
	assert stenciled(maskWriter()).renderState().stencil == maskWriter();
	assert stenciled(Stencil.defaults()).renderState().stencil == Stencil.defaults();
}
