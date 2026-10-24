import {
	AnimationCurve, CurveKey, CompiledCurve, CompiledMinMaxCurve, MinMaxCurve, WeightedMode,
	Gradient, GradientMode, GradientKind, ParticleColorSpace, MinMaxGradient, CurveError,
	key, linearCurve, constantCurve, twoConstants, curveOf, twoCurves, rgbaColor, unitDraw, pcgHash,
} from "../particles/curve";

function near(a: float32, b: float32, tol: float32): boolean {
	const d: float32 = a - b;
	return d < tol && d > -tol;
}

function compiled(curve: AnimationCurve): CompiledCurve {
	const made = curve.compile();
	if (!made.ok) { unreachable; }
	return made.value;
}

function compiledValue(value: MinMaxCurve): CompiledMinMaxCurve {
	const made = value.compile();
	if (!made.ok) { unreachable; }
	return made.value;
}

test "a linear curve is exact between its keys and clamps outside them" {
	const c = compiled(linearCurve([key(0.0, 1.0), key(1.0, 3.0)]));
	assert near(c.evaluate(0.25), 1.5, 1e-6);
	assert c.evaluate(-1.0) == 1.0;
	assert c.evaluate(2.0) == 3.0;
}

test "Hermite keys with flat slopes ease in and out: smoothstep" {
	const c = compiled({ keys: [key(0.0, 0.0), key(2.0, 1.0)] });
	assert near(c.evaluate(1.0), 0.5, 1e-6);
	assert near(c.evaluate(0.5), 0.15625, 1e-6);
}

test "an infinite slope holds the left value to the next key" {
	let k0: CurveKey = key(0.0, 2.0);
	k0.outSlope = (1.0 / 0.0) as float32;
	const c = compiled({ keys: [k0, key(1.0, 5.0)] });
	assert c.evaluate(0.99) == 2.0;
	assert c.evaluate(1.0) == 5.0;
}

test "default weights of one third give the unweighted Hermite curve" {
	let a: CurveKey = { ...key(0.0, 0.0), outSlope: 2.0, weightedMode: WeightedMode.Out };
	let b: CurveKey = { ...key(1.0, 1.0), inSlope: -1.0, weightedMode: WeightedMode.In };
	const weighted = compiled({ keys: [a, b] });
	const plain = compiled({ keys: [{ ...a, weightedMode: WeightedMode.None },
		{ ...b, weightedMode: WeightedMode.None }] });
	for (let i = 1; i < 10; i++) {
		const t: float32 = (i as float32) / 10.0;
		assert near(weighted.evaluate(t), plain.evaluate(t), 1e-5);
	}
}

test "unordered keys are refused" {
	const made = ({ keys: [key(1.0, 0.0), key(0.5, 1.0)] } as AnimationCurve).compile();
	assert !made.ok;
	if (!made.ok) { assert made.error == CurveError.UnorderedKeys; }
}

test "MinMaxCurve modes follow PSS:520-533" {
	assert compiledValue(constantCurve(4.0)).evaluate(0.3, 0.9) == 4.0;
	assert near(compiledValue(twoConstants(2.0, 6.0)).evaluate(0.3, 0.25), 3.0, 1e-6);
	const up = linearCurve([key(0.0, 0.0), key(1.0, 1.0)]);
	const flat = linearCurve([key(0.0, 0.5), key(1.0, 0.5)]);
	assert near(compiledValue(curveOf(10.0, up)).evaluate(0.4, 0.0), 4.0, 1e-5);
	assert near(compiledValue(twoCurves(2.0, flat, up)).evaluate(1.0, 0.5), 1.5, 1e-5);
	assert compiledValue(twoConstants(1.0, 2.0)).isConstantOverTime();
	assert !compiledValue(curveOf(1.0, up)).isConstantOverTime();
}

function twoKeyGradient(space: ParticleColorSpace, mode: GradientMode): Gradient {
	return {
		colorKeys: [{ color: rgbaColor(1.0, 0.0, 0.0, 1.0), time: 0.0 },
			{ color: rgbaColor(0.0, 1.0, 0.0, 1.0), time: 1.0 }],
		alphaKeys: [{ alpha: 1.0, time: 0.0 }, { alpha: 0.0, time: 0.5 }],
		mode: mode,
		colorSpace: space,
	};
}

test "a gradient blends in its colour space, with alpha on its own track" {
	const gamma = twoKeyGradient(ParticleColorSpace.Gamma, GradientMode.Blend).evaluate(0.5);
	assert near(gamma.r, 0.5, 1e-6) && near(gamma.g, 0.5, 1e-6) && gamma.a == 0.0;
	const linear = twoKeyGradient(ParticleColorSpace.Linear, GradientMode.Blend).evaluate(0.5);
	assert near(linear.r, 0.7353, 2e-3) && near(linear.g, 0.7353, 2e-3);
	const quarter = twoKeyGradient(ParticleColorSpace.Gamma, GradientMode.Blend).evaluate(0.25);
	assert near(quarter.a, 0.5, 1e-6);
}

test "a fixed gradient steps to the right key" {
	const c = twoKeyGradient(ParticleColorSpace.Gamma, GradientMode.Fixed).evaluate(0.5);
	assert c.r == 0.0 && c.g == 1.0;
}

test "a perceptual blend stays inside the sRGB cube and differs from gamma" {
	const c = twoKeyGradient(ParticleColorSpace.Gamma, GradientMode.PerceptualBlend).evaluate(0.5);
	assert c.r >= 0.0 && c.r <= 1.0 && c.g >= 0.0 && c.g <= 1.0;
	assert !near(c.r, 0.5, 1e-2);
}

test "RandomColor samples the gradient at the particle's draw" {
	const g: MinMaxGradient = {
		mode: GradientKind.RandomColor, minColor: rgbaColor(0.0, 0.0, 0.0, 1.0),
		maxColor: rgbaColor(1.0, 1.0, 1.0, 1.0),
		maxGradient: twoKeyGradient(ParticleColorSpace.Gamma, GradientMode.Blend),
		minGradient: twoKeyGradient(ParticleColorSpace.Gamma, GradientMode.Blend),
	};
	assert near(g.evaluate(0.9, 0.0).r, 1.0, 1e-6);
	assert near(g.evaluate(0.0, 1.0).g, 1.0, 1e-6);
}

test "too many gradient keys are refused" {
	let g = twoKeyGradient(ParticleColorSpace.Gamma, GradientMode.Blend);
	for (let i = 0; i < 8; i++) { g.alphaKeys.push({ alpha: 1.0, time: 1.0 }); }
	assert !g.validate().ok;
}

test "stable draws are in [0, 1), repeat for a seed and differ across streams" {
	let sum: float64 = 0.0;
	for (let s: uint32 = 0; s < 4096; s++) {
		const u: float32 = unitDraw(s, 3);
		assert u >= 0.0 && u < 1.0;
		sum = sum + (u as float64);
	}
	assert sum / 4096.0 > 0.48 && sum / 4096.0 < 0.52;
	assert unitDraw(77, 1) == unitDraw(77, 1);
	assert unitDraw(77, 1) != unitDraw(77, 2);
	assert pcgHash(0) != pcgHash(1);
}
