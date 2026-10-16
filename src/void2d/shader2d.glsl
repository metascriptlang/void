// Void 2D programs, sokol-shdc dialect. Their stages are MetaScript shader functions in
// src/void2d/shader2d.ms; scripts/regen-shaders.sh writes them to shader2dGen.glsl.
@include shader2dGen.glsl

@program void2d vs fs
@program sprite spriteVs spriteFs
@program ui uiVs uiFs
@program blur blurVs blurFs
