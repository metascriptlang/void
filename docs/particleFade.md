# Particle lifetime fade — source built, GPU acceptance pending

The requested result is a particle that becomes smoothly transparent over its lifetime,
not one that disappears below half alpha. It is distinct from fading intersections
against opaque geometry. Bloom's GPU slot and acceptance come first; this row is built with light checks only.

## References read

- Heaps `b9aa6dcbb2307b03c1f435e87bdb036060100984`:
  `h3d/parts/Emitter.hx` `setState` (:40–46) selects Add, SoftAdd or Alpha;
  `h3d/parts/Particles.hx` `draw` (:161–169) selects the particle order;
  `h3d/mat/Material.hx` `set_blendMode` (:132–146) chooses phases and depth write.
  Alpha writes depth; Add/SoftAdd do not. No soft-intersection implementation was found
  by the `soft.?particle`/`SoftParticle` search of its Haxe sources; that search is not
  proof that an equivalent effect cannot be composed.
- Bevy `157e1ce6bc66fadca9f57260c18a16d743c11ed5`:
  `crates/bevy_pbr/src/render/mesh.rs` `MeshPipeline::specialize` (:3527–3540)
  uses alpha/premultiplied blending without depth writes. This is the core transparent
  mesh path, not evidence for a built-in particle soft-intersection effect.
- three.js `d4ea9b981603bc41e34983f998c52347e75b50bd`:
  `src/materials/SpriteMaterial.js` defaults to transparency; `Material.js` defaults
  `alphaTest` to zero. `examples/jsm/tsl/utils/SoftParticles.js` `softParticles`
  reads opaque scene depth, reconstructs scene view-Z and multiplies opacity by a
  contrast curve of the particle/scene gap. That is a separate, depth-based effect.
- URG `godot/packs/BinbunVFX/shared/shader/transparent.gdshader` (:62, :123):
  ordinary alpha is written independently of the optional `proximity_fade` branch.
  That branch samples `depth_texture` and reconstructs view position; the URG survey
  found it disabled in the surveyed content (VOID3D.md "Roadmap from M33").

## Recommended shape

Reuse the existing billboard cutout-versus-blended idiom, ProgramKey's cutout bit,
material phases, and the emitter's sorted instance path. No sampled-depth input or
new pass order is needed for lifetime alpha fade.

The current mechanisms to extend are `src/void3d/gpu3d.ms` `withCutout`,
`src/void3d/draw.ms` `addMaterial`'s fixed-cut test, and
`src/void3d/material.ms` `cutoutOf`. Extend their particle cases, retaining the
undeclared-key and non-fixed uniform-threshold checks for other programs.
Explicit particle cutout keys retain the existing half-alpha silhouette; the plain
particle keys carry continuous alpha. Existing cutout consumers must name their
intent, rather than silently retaining a cutoff on every particle material.

For translucent particles, test against depth but do not write it; draw after opaque
geometry, and sort instances back-to-front when the blend requires ordering.
This follows Bevy's transparent depth behavior, not Heaps' Alpha depth-write default.
`Material.ofKind(Program.Particle, MaterialKind.Alpha)` selects non-writing depth;
other programs keep generic `MaterialKind.Alpha`'s existing depth-write default.
The emitter's SortMode remains the author's choice.
Sorting within an emitter does not promise global interleaving of particles from
separate emitter draws; that limitation is not solved by this row.

PixelArtRenderer already draws translucent items into a color-only pass after the
opaque MRT pass (`pixelArtRenderer.ms` `drawScene`); particle fade must use that seam,
so opaque normal/depth metadata stays intact. Fade before palette quantization can
produce stepped palette colors; continuous alpha does not promise continuous output
colors under a deliberately quantized look. HDR and post-off variants need coverage.

Sampled depth is already supported by the GPU door and PixelArtRenderer's sampled
`PixelFormat.Depth` target; ForwardRenderer currently makes its depth target unsampled.
A future soft-intersection row would still have to establish sample-versus-attachment
hazards, opaque-depth availability, projection reconstruction and pass ordering.
None of that is requested or built for ordinary lifetime alpha fade.

## Acceptance to establish

- Alpha values on both sides of 0.5, including below it, affect the color predictably;
  zero contributes nothing, opaque depth occludes a particle behind it.
- Back-to-front ordering and non-writing depth are observed through overlapping particles,
  not inferred only from state values; document the per-emitter sorting boundary.
- Both presets, HDR, and pixel-art post on/off; translucent particles do not replace
  opaque normal/depth metadata. No new expectation of palette-continuous colors.
- Explicit cutout still cuts; existing campfire/capture consumers move to explicit
  cutout and retain their baseline bytes.
- Each GPU pin needs a red control of the old cutoff or wrong depth state, then green.

## Source-only evidence

On BUILD `5039c014`, implementation/test commit `84482cbc`, tree
`40d1497dfba5eff448699e0f3ed6324f0d9501f0`:
`msc test src/test/index.ms` 1480/1480, fixture `msc check` and native `msc build`
pass, and `msc check src/examples/campfireScene.ms` passes. The new headless pin was
red on the old key gate (`Core Particle has no cutout variant`), then green (two tests,
300 including std). That is an API pin, not an old-shader GPU red control.

Regenerated source-array comparison: all 14 vertex/fragment arrays in each preset
(seven backends) of the old Particle exactly equal the new ParticleCutout arrays.
Only the plain particle fragment arrays change. Campfire/card-table/churn consumers
name explicit cutout; source-array identity supports the baseline expectation but
is not a replacement for capture readback.

`tests/integration/particleFade.ms` is the real stream consumer, with a below-half
alpha readback, fixed cutout, opaque occlusion, and two differently colored particles
written by `writeSortedInstances`. Its gate stage runs native and GL core × LDR/HDR,
both presets, plus pixel-art post on and palette on. Its former-cutoff controls must
fail the continuous-alpha assertion. None of these GPU runs has been executed yet.

Opaque cutout preservation is checked positively in LDR; HDR reads the cut-away
quarter-alpha sample, while continuous alpha, ordering and opaque occlusion are
checked in both target formats. Do not claim a new HDR cutout behavior from this pin.

GPU work waits for the manager's named slot. No GPU acceptance is claimed.
