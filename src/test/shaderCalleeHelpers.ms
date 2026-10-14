// Shader helpers that the probes of shaderCalleeCheck.ms reach in another module.

export const GAIN: float32 = 2.0;

export function scale(x: float32): float32 { return x * GAIN; }
