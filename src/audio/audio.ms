// Void audio — macOS default shim. sokol_audio auto-selects the CoreAudio backend here, so link
// AudioToolbox. Only the OS link flag lives here; the audio engine (decode/voices/fades) is
// OS-agnostic MetaScript in audioCore.ms, re-exported below. Chosen by the compiler's OS-keyed
// module resolution when no OS-specific variant matches (macOS).
@passL("-framework AudioToolbox");

// The whole public API is defined once in audioCore.ms; this shim only adds the OS link flag.
export * from "./audioCore";
