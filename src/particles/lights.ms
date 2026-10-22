// The Lights module: which particles carry a point light and what light, for the renderer to
// place (docs/PARTICLES.md: capped by void3d's four forward point lights, which the scene enforces).

import { Vec3, vec3 } from "../math/math3d";
import { SimulationSpace } from "./asset";
import { ParticleColor, unitDraw } from "./curve";
import {
	ParticleSystem, POS_X, POS_Y, POS_Z, AGE, LIFETIME, SIZE_X, COLOR_R, COLOR_G, COLOR_B, COLOR_A,
	DRAW_LIGHT,
} from "./system";

export struct ParticleLight {
	position: Vec3;
	color: ParticleColor;
	range: float32;
	intensity: float32;
}

// Fills `out` with the lights of `sys`'s particles, in world space, at most `maxLights`.
// `ratio` picks a share of the particles: at random per particle, or every 1/ratio-th in order.
export function particleLights(sys: ParticleSystem, ref out: Vec<ParticleLight>): void {
	out.length = 0;
	const lights = sys.asset.lights;
	if (!lights.enabled || lights.ratio <= 0.0) { return; }
	const cap: int32 = sys.capacity;
	const local: boolean = sys.asset.main.simulationSpace == SimulationSpace.Local;
	for (let i = 0; i < sys.count && (out.length as int32) < lights.maxLights; i++) {
		const seed: uint32 = sys.seeds[i];
		const chosen: boolean = lights.useRandomDistribution
			? unitDraw(seed, DRAW_LIGHT) < lights.ratio
			: Math.floor(((i + 1) as float32 * lights.ratio) as float64) > Math.floor(((i as float32) * lights.ratio) as float64);
		if (!chosen) { continue; }
		const tN: float32 = sys.data[AGE * cap + i] / sys.data[LIFETIME * cap + i];
		const r: float32 = unitDraw(seed, DRAW_LIGHT + 1);
		const particle: ParticleColor = {
			r: sys.data[COLOR_R * cap + i], g: sys.data[COLOR_G * cap + i],
			b: sys.data[COLOR_B * cap + i], a: sys.data[COLOR_A * cap + i],
		};
		let color: ParticleColor = lights.color;
		if (lights.useParticleColor) {
			color = { r: color.r * particle.r, g: color.g * particle.g, b: color.b * particle.b, a: color.a * particle.a };
		}
		let range: float32 = sys.curves.lightRange.evaluate(tN, r) * lights.rangeMultiplier;
		if (lights.sizeAffectsRange) { range = range * sys.data[SIZE_X * cap + i]; }
		let intensity: float32 = sys.curves.lightIntensity.evaluate(tN, r) * lights.intensityMultiplier;
		if (lights.alphaAffectsIntensity) { intensity = intensity * particle.a; }
		const p: Vec3 = vec3(sys.data[POS_X * cap + i], sys.data[POS_Y * cap + i], sys.data[POS_Z * cap + i]);
		out.push({ position: local ? p * sys.world : p, color: color, range: range, intensity: intensity });
	}
}
