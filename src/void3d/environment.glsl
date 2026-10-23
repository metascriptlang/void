// The environment bake's programs, sokol-shdc dialect. Their stages are MetaScript shader
// functions in src/void3d/environmentShader.ms; scripts/regen-shaders.sh writes them to
// environmentGen.glsl.
@include environmentGen.glsl

@program environmentPanorama fullscreenVs environmentPanoramaFs
@program environmentResample fullscreenVs environmentResampleFs
@program environmentRadiance fullscreenVs environmentRadianceFs
@program environmentIrradiance fullscreenVs environmentIrradianceFs
