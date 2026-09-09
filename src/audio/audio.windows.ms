// Void audio — native Windows shim. sokol_audio auto-selects the WASAPI backend here, so link
// ole32. Only the OS link flag lives here; the audio engine (decode/voices/fades) is OS-agnostic
// MetaScript in audioCore.ms, re-exported below. Selected by OS-keyed resolution for --os=windows.
@passL("-lole32");

// The whole public API is defined once in audioCore.ms; this shim only adds the OS link flag.
export * from "./audioCore";
