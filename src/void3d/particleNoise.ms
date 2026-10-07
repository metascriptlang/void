// Godot 4.5's particle turbulence field, transcribed from the GLSL ParticleProcessMaterial writes
// (scene/resources/particle_process_material.cpp at 4.5-stable: `grad` 405-412, `noise` 414-445,
// `noise_3x` 449-455, `curl_3d` 457-472, `get_noise_direction` 474-481). Godot is Y up and right
// handed as this port is, so its axes are used as they stand.

import { Vec3, vec3 } from "../math/math3d";

const HASH_SCALE: float32 = 2365.952041 as float32;
const SHEET_OFFSET: float32 = (1.7320508 * 2048.333333) as float32;

function fract(x: float32): float32 {
	return x - (Math.floor(x as float64) as float32);
}

function gradX(px: float32, py: float32, pz: float32, pw: float32): float32 {
	return fract(px * 0.143081 + py * 0.001724 + pz * 0.280166 + pw * 0.262771);
}

function gradY(px: float32, py: float32, pz: float32, pw: float32): float32 {
	return fract(px * 0.645401 + py * -0.047791 + pz * -0.146698 + pw * 0.595016);
}

function gradZ(px: float32, py: float32, pz: float32, pw: float32): float32 {
	return fract(px * -0.499665 + py * -0.095734 + pz * 0.425674 + pw * -0.207367);
}

function gradW(px: float32, py: float32, pz: float32, pw: float32): float32 {
	return fract(px * -0.013596 + py * -0.848588 + pz * 0.423736 + pw * 0.17044);
}

function fade(d: float32): float32 {
	const inner: float32 = d * 6.0 - 15.0;
	const middle: float32 = d * inner + 10.0;
	return d * d * d * middle;
}

// The gradient of lattice corner (bx, by, bz, bw) dotted with the offset (dx, dy, dz, dw) to it.
function cornerValue(
	bx: float32, by: float32, bz: float32, bw: float32,
	dx: float32, dy: float32, dz: float32, dw: float32,
): float32 {
	const qx: float32 = gradX(bx, by, bz, bw);
	const qy: float32 = gradY(bx, by, bz, bw);
	const qz: float32 = gradZ(bx, by, bz, bw);
	const qw: float32 = gradW(bx, by, bz, bw);
	const gx: float32 = fract(qx * qy * HASH_SCALE) * 2.0 - 1.0;
	const gy: float32 = fract(qy * qz * HASH_SCALE) * 2.0 - 1.0;
	const gz: float32 = fract(qz * qw * HASH_SCALE) * 2.0 - 1.0;
	const gw: float32 = fract(qw * qx * HASH_SCALE) * 2.0 - 1.0;
	return dx * gx + dy * gy + dz * gz + dw * gw;
}

// `noise(vec4)`: gradient noise on the 16 corners of a 4D cell, with the quintic fade. The four
// nested mixes of the GLSL are summed here as the one multilinear weight each corner has.
export function noise4(cx: float32, cy: float32, cz: float32, cw: float32): float32 {
	const skew: float32 = cx * -0.1666667 + cy * -0.1666667 + cz * -0.1666667 + cw * -0.5;
	const wx: float32 = cx + skew;
	const wy: float32 = cy + skew;
	const wz: float32 = cz + skew;
	const ww: float32 = cx * 0.5 + cy * 0.5 + cz * 0.5 + cw * 0.5;
	const bx: float32 = Math.floor(wx as float64) as float32;
	const by: float32 = Math.floor(wy as float64) as float32;
	const bz: float32 = Math.floor(wz as float64) as float32;
	const bw: float32 = Math.floor(ww as float64) as float32;
	const dx: float32 = wx - bx;
	const dy: float32 = wy - by;
	const dz: float32 = wz - bz;
	const dw: float32 = ww - bw;
	const fx: float32 = fade(dx);
	const fy: float32 = fade(dy);
	const fz: float32 = fade(dz);
	const fw: float32 = fade(dw);
	let sum: float32 = 0.0;
	for (let i = 0; i < 16; i++) {
		const ox: float32 = (i & 1) as float32;
		const oy: float32 = ((i >> 1) & 1) as float32;
		const oz: float32 = ((i >> 2) & 1) as float32;
		const ow: float32 = ((i >> 3) & 1) as float32;
		const corner: float32 = cornerValue(bx + ox, by + oy, bz + oz, bw + ow, dx - ox, dy - oy, dz - oz, dw - ow);
		let weight: float32 = (i & 1) != 0 ? fx : 1.0 - fx;
		weight = weight * (((i >> 1) & 1) != 0 ? fy : 1.0 - fy);
		weight = weight * (((i >> 2) & 1) != 0 ? fz : 1.0 - fz);
		weight = weight * (((i >> 3) & 1) != 0 ? fw : 1.0 - fw);
		sum = sum + corner * weight;
	}
	return sum;
}

// `noise_3x`: three decorrelated samples, the second and third a fixed step along w.
function noise3(px: float32, py: float32, pz: float32, pw: float32): Vec3 {
	return vec3(
		noise4(px, py, pz, pw),
		noise4(px, py, pz, pw + SHEET_OFFSET),
		noise4(px, py, pz, pw - SHEET_OFFSET),
	);
}

// `curl_3d`: the normalized curl of that vector field by central differences of step 0.001 + c.
// Zero where the curl is zero, where GLSL's normalize gives NaN.
export function curl3(px: float32, py: float32, pz: float32, pw: float32, c: float32): Vec3 {
	const e: float32 = 0.001 + c;
	const x0: Vec3 = noise3(px - e, py, pz, pw);
	const x1: Vec3 = noise3(px + e, py, pz, pw);
	const y0: Vec3 = noise3(px, py - e, pz, pw);
	const y1: Vec3 = noise3(px, py + e, pz, pw);
	const z0: Vec3 = noise3(px, py, pz - e, pw);
	const z1: Vec3 = noise3(px, py, pz + e, pw);
	const x: float32 = (y1.z - y0.z) - (z1.y - z0.y);
	const y: float32 = (z1.x - z0.x) - (x1.z - x0.z);
	const z: float32 = (x1.y - x0.y) - (y1.x - y0.x);
	const length: float32 = Math.sqrt((x * x + y * y + z * z) as float64) as float32;
	if (!(length > 0.0)) { return vec3(0.0, 0.0, 0.0); }
	return vec3(x / length, y / length, z / length);
}

// `get_noise_direction`: the unit direction turbulence pushes a particle at `position` toward.
// `scale` is the shader's value (`shaderNoiseScale` turns the property into it), `speed` and
// `speedRandom` the drift of the field along x, y, z and w per second of `time`.
export function noiseDirection(
	position: Vec3,
	time: float32,
	strength: float32,
	scale: float32,
	speed: Vec3,
	speedRandom: float32,
): Vec3 {
	let excess: float32 = 0.0;
	if (strength > 1.0) { excess = strength - 1.0; }
	const contrast: float32 = excess * 70.0;
	return curl3(
		position.x * scale + time * speed.x,
		position.y * scale + time * speed.y,
		position.z * scale + time * speed.z,
		time * speedRandom,
		contrast,
	);
}

// set_turbulence_noise_scale (cpp:1812-1819): the property the author sets, 0 to 10, becomes the
// frequency the shader multiplies positions by.
export function shaderNoiseScale(property: float32): float32 {
	const base: float32 = 4.0;
	const rescale: float32 = base / (Math.pow(10.0, 0.25) as float32);
	return (Math.pow(property as float64, 0.25) as float32) * rescale - base;
}
