// Void audio — native Linux shim. sokol_audio auto-selects the ALSA backend here, so link
// libasound (+ pthread for its mixer thread). This file is *only* the OS link flags; the whole
// audio engine (decode/voices/fades) is OS-agnostic MetaScript in audioCore.ms, which this
// re-exports. Same split as sokol/gpu.linux.ms wrapping the shared renderer.
// Selected by the compiler's OS-keyed module resolution for --os=linux.
@passL("-lasound");
@passL("-lpthread");

// The whole public API is defined once in audioCore.ms; this shim only adds the OS link flags.
export * from "./audioCore";
