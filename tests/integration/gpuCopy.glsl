// The foreign program of gpuRegistrationFixture.ms, sokol-shdc dialect. Its stages are MetaScript
// shader functions in gpuCopyShader.ms; scripts/regen-shaders.sh writes them to gpuCopyGen.glsl.
@include gpuCopyGen.glsl

@program gpuCopy gpuCopyVs gpuCopyFs
