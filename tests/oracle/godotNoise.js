// An independent float32 transcription of the GLSL ParticleProcessMaterial writes for turbulence
// (godotengine/godot 4.5-stable, 876b290332ec, scene/resources/particle_process_material.cpp:405-481),
// with set_turbulence_noise_scale (1812-1819). Run with `node tests/oracle/godotNoise.js`: it prints
// the numbers src/test/particlesCheck.ms holds src/void3d/particleNoise.ms to. It is a second
// transcription of the shader text, not Godot's own output: no Godot build ran.
const f = Math.fround;
const fract = (x) => f(x - Math.floor(x));
const dot4 = (a, b) => f(f(f(f(a[0] * b[0]) + f(a[1] * b[1])) + f(a[2] * b[2])) + f(a[3] * b[3]));
function grad(p) {
  const q = [
    dot4(p, [0.143081, 0.001724, 0.280166, 0.262771].map(f)),
    dot4(p, [0.645401, -0.047791, -0.146698, 0.595016].map(f)),
    dot4(p, [-0.499665, -0.095734, 0.425674, -0.207367].map(f)),
    dot4(p, [-0.013596, -0.848588, 0.423736, 0.17044].map(f)),
  ].map(fract);
  const k = f(2365.952041);
  const r = [f(q[0] * q[1]), f(q[1] * q[2]), f(q[2] * q[3]), f(q[3] * q[0])];
  return r.map((v) => f(f(fract(f(v * k))) * 2 - 1));
}
const fade = (d) => f(f(f(d * d) * d) * f(10 + f(d * f(-15 + f(d * 6)))));
function noise(c) {
  const s = dot4(c, [-0.1666667, -0.1666667, -0.1666667, -0.5].map(f));
  const w = dot4(c, [0.5, 0.5, 0.5, 0.5]);
  const co = [f(c[0] + s), f(c[1] + s), f(c[2] + s), w];
  const base = co.map(Math.floor);
  const delta = co.map((v, i) => f(v - base[i]));
  const fd = delta.map(fade);
  let acc = 0;
  for (let i = 0; i < 16; i++) {
    const o = [i & 1, (i >> 1) & 1, (i >> 2) & 1, (i >> 3) & 1];
    const g = grad(base.map((b, j) => f(b + o[j])));
    const v = dot4(delta.map((d, j) => f(d - o[j])), g);
    let wgt = 1;
    for (let j = 0; j < 4; j++) wgt = f(wgt * (o[j] ? fd[j] : f(1 - fd[j])));
    acc = f(acc + f(v * wgt));
  }
  return acc;
}
const OFF = f(1.7320508 * 2048.333333);
const noise3x = (p) => [noise(p), noise([p[0], p[1], p[2], f(p[3] + OFF)]), noise([p[0], p[1], p[2], f(p[3] - OFF)])];
function curl(p, c) {
  const e = f(0.001 + c);
  const at = (i, s) => noise3x(p.map((v, j) => (j === i ? f(v + s * e) : v)));
  const x0 = at(0, -1), x1 = at(0, 1), y0 = at(1, -1), y1 = at(1, 1), z0 = at(2, -1), z1 = at(2, 1);
  const x = f(f(y1[2] - y0[2]) - f(z1[1] - z0[1]));
  const y = f(f(z1[0] - z0[0]) - f(x1[2] - x0[2]));
  const z = f(f(x1[1] - x0[1]) - f(y1[0] - y0[0]));
  const l = Math.sqrt(x * x + y * y + z * z);
  return [f(x / l), f(y / l), f(z / l)];
}
function noiseDirection(pos, time, strength, scale, speed, speedRandom) {
  const c = f(Math.max(strength - 1, 0) * 70);
  const p = [f(pos[0] * scale), f(pos[1] * scale), f(pos[2] * scale), 0];
  const t = [f(time * speed[0]), f(time * speed[1]), f(time * speed[2]), f(time * speedRandom)];
  return curl(p.map((v, i) => f(v + t[i])), c);
}
const cases = [
  [[0.3, -0.7, 1.1], 0.0, 1, 4, [0, 0, 0], 0],
  [[0.3, -0.7, 1.1], 0.5, 1, 4, [1, 0.5, 0.25], 0.2],
  [[-2.5, 3.1, 0.4], 1.25, 1, -0.104, [0, 0, 0], 0.2],
  [[1.9, 0.2, -3.3], 2.0, 3, 6, [0.5, 0.5, 0.5], 0.2],
];
for (const [pos, time, s, sc, sp, sr] of cases) {
  console.log(JSON.stringify([pos, time, s, sc, sp, sr]), noiseDirection(pos, time, s, sc, sp, sr).join(", "));
}
// The emitter case: velocity (0.2, 0, 0), influence 0.5, at the origin at t = 0.1.
const base = 4, rescale = f(4 / Math.pow(10, 0.25));
const shaderScale = f(f(Math.pow(9, 0.25)) * rescale - base);
console.log("shaderScale(9)", shaderScale, "shaderScale(10)", f(f(Math.pow(10, 0.25)) * rescale - base), "shaderScale(0)", f(0 * rescale - base));
const n = noiseDirection([0, 0, 0], 0.1, 1, shaderScale, [1, 0.5, 0.25], 0.2);
console.log("emitter dir", n.join(", "));
const v = [0.2, 0, 0], mag = 0.2, infl = 0.5;
const t = n.map((x) => f(x * mag * f(1 + f(1 - infl) * 0.2)));
console.log("mixed", v.map((a, i) => f(f(a * (1 - infl)) + f(t[i] * infl))).join(", "));
