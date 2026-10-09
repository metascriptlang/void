@block pointLight
vec3 pointLightAt(int i, vec3 position, vec3 normal) {
    vec3 toLight = pointLight[i].xyz - position;
    float distance = length(toLight);
    float falloff = clamp(1.0 - distance / pointColor[i].a, 0.0, 1.0);
    float facing = max(dot(normal, toLight / max(distance, 0.0001)), 0.0);
    return srgbToLinear(pointColor[i].rgb) * (falloff * falloff * facing * pointLight[i].w);
}
@end

@vs litVs
@include_block vertexUniforms
@include_block modelUniforms
in vec3 position;
in vec3 normal;
in vec4 color;
out vec3 worldPosition;
out vec3 worldNormal;
out vec4 baseColor;
void main() {
    vec4 world = model * vec4(position, 1.0);
    worldPosition = world.xyz;
    worldNormal = mat3(normalModel) * normal;
    baseColor = color;
    gl_Position = viewProj * world;
}
@end

@block litShade
vec4 litShade(vec3 n) {
    float lambert = max(dot(n, dirLight.xyz), 0.0) * dirLight.w;
#ifdef SHADOWED
    lambert *= dirShadowAt(worldPosition);
#endif
    vec3 light = srgbToLinear(ambient.rgb) + srgbToLinear(dirColor.rgb) * lambert;
    for (int i = 0; i < int(ambient.a + 0.5); i++) {
        light += pointLightAt(i, worldPosition, n);
    }
    vec3 surface = srgbToLinear(saturated(baseColor.rgb, material.y));
    return vec4(linearToSrgb(surface * light), baseColor.a);
}
@end

@fs litFs
// PENDING3D: material-saturation-only
@include_block materialUniforms
@include_block lightUniforms
@include_block colorSpace
@include_block frameUniforms
@include_block toneMap
@include_block pointLight
@include_block saturation
@include_block facingNormal
#ifdef SHADOWED
@include_block dirShadow
#endif
in vec3 worldPosition;
in vec3 worldNormal;
in vec4 baseColor;
out vec4 fragColor;
@include_block litShade
void main() {
    vec3 n = facingNormal(normalize(worldNormal), material.z);
    fragColor = litShade(n);
#ifdef CUTOUT
    if (fragColor.a < material.w) {
        discard;
    }
#endif
    fragColor.rgb = toneMapped(fragColor.rgb);
}
@end

@vs litTexturedVs
@include_block vertexUniforms
@include_block modelUniforms
in vec3 position;
in vec3 normal;
in vec2 uv;
in vec4 color;
#ifdef NORMAL_MAP
in vec4 tangent;
out vec4 worldTangent;
#endif
out vec3 worldPosition;
out vec3 worldNormal;
out vec2 surfaceUv;
out vec4 baseColor;
void main() {
    vec4 world = model * vec4(position, 1.0);
    worldPosition = world.xyz;
    worldNormal = mat3(normalModel) * normal;
#ifdef NORMAL_MAP
    worldTangent = vec4(mat3(model) * tangent.xyz, tangent.w);
#endif
    surfaceUv = uv;
    baseColor = color;
    gl_Position = viewProj * world;
}
@end

@block litTexturedShade
vec4 litTexturedShade(vec4 texel, vec3 n) {
    float lambert = max(dot(n, dirLight.xyz), 0.0) * dirLight.w;
#ifdef SHADOWED
    lambert *= dirShadowAt(worldPosition);
#endif
    vec3 light = srgbToLinear(ambient.rgb) + srgbToLinear(dirColor.rgb) * lambert;
    for (int i = 0; i < int(ambient.a + 0.5); i++) {
        light += pointLightAt(i, worldPosition, n);
    }
    vec3 surface = srgbToLinear(saturated(baseColor.rgb * texel.rgb, material.y));
    return vec4(linearToSrgb(surface * light), baseColor.a * texel.a);
}
@end

@fs litTexturedFs
// PENDING3D: material-saturation-only
#if defined(UV_TRANSFORM) || defined(BACK_TEXTURE) || defined(DISSOLVE)
#ifdef EMISSIVE
@include_block movingEmissiveMaterialUniforms
#else
@include_block movingMaterialUniforms
#endif
#elif defined(EMISSIVE)
@include_block emissiveMaterialUniforms
#else
@include_block materialUniforms
#endif
@include_block lightUniforms
@include_block colorSpace
@include_block frameUniforms
@include_block toneMap
@include_block pointLight
@include_block saturation
@include_block facingNormal
#ifdef SHADOWED
@include_block dirShadow
#endif
#ifdef PREMULTIPLIED
@include_block straightTexel
#endif
#ifdef UV_TRANSFORM
@include_block movedUv
#endif
#ifdef BACK_TEXTURE
@include_block backTexture
#endif
#ifdef DISSOLVE
@include_block dissolveTexture
#endif
#ifdef EMISSIVE
@include_block emissiveTexture
#endif
#ifdef NORMAL_MAP
@include_block normalMap
in vec4 worldTangent;
#endif
layout(binding=0) uniform texture2D baseTexture;
layout(binding=0) uniform sampler baseSampler;
in vec3 worldPosition;
in vec3 worldNormal;
in vec2 surfaceUv;
in vec4 baseColor;
out vec4 fragColor;
@include_block litTexturedShade
void main() {
#ifdef UV_TRANSFORM
    vec2 uv = movedUv(surfaceUv);
#else
    vec2 uv = surfaceUv;
#endif
    vec4 texel = texture(sampler2D(baseTexture, baseSampler), uv);
#ifdef BACK_TEXTURE
    // Both read, then one kept: WGSL refuses a sample under non-uniform control flow.
    vec4 backTexel = texture(sampler2D(backTexture, baseSampler), backUv(surfaceUv));
    texel = gl_FrontFacing ? texel : backTexel;
#endif
#ifdef DISSOLVE
    float noise = texture(sampler2D(dissolveTexture, dissolveSampler), surfaceUv).r;
    if (noise < dissolve.x) {
        discard;
    }
#endif
#ifdef PREMULTIPLIED
    texel = straightTexel(texel);
#endif
#ifdef NORMAL_MAP
    vec3 normalTexel = texture(sampler2D(normalTexture, baseSampler), uv).rgb;
    vec3 n = mappedNormal(normalize(worldNormal), worldTangent, faceOf(material.z), normalTexel);
#else
    vec3 n = facingNormal(normalize(worldNormal), material.z);
#endif
    fragColor = litTexturedShade(texel, n);
#ifdef EMISSIVE
    fragColor = emittedOver(fragColor, texture(sampler2D(emissiveTexture, baseSampler), uv).rgb);
#endif
#ifdef DISSOLVE
    fragColor = dissolveEdgeOver(fragColor, noise);
#endif
#ifdef CUTOUT
    if (fragColor.a < material.w) {
        discard;
    }
#endif
    fragColor.rgb = toneMapped(fragColor.rgb);
#ifdef PREMULTIPLIED
    fragColor = vec4(fragColor.rgb * fragColor.a, fragColor.a);
#endif
}
@end

@vs unlitTexturedVs
@include_block vertexUniforms
@include_block modelTransformUniforms
in vec3 position;
in vec3 normal;
in vec2 uv;
in vec4 color;
out vec2 surfaceUv;
out vec4 baseColor;
void main() {
    gl_Position = viewProj * model * vec4(position, 1.0);
    surfaceUv = uv;
    baseColor = color;
}
@end

@fs unlitTexturedFs
#if defined(UV_TRANSFORM) || defined(BACK_TEXTURE) || defined(DISSOLVE)
@include_block movingUnlitMaterialUniforms
#else
@include_block unlitMaterialUniforms
#endif
@include_block colorSpace
@include_block frameUniforms
@include_block toneMap
#ifdef PREMULTIPLIED
@include_block straightTexel
#endif
#ifdef UV_TRANSFORM
@include_block movedUv
#endif
#ifdef BACK_TEXTURE
@include_block backTexture
#endif
#ifdef DISSOLVE
@include_block dissolveTexture
#endif
layout(binding=0) uniform texture2D baseTexture;
layout(binding=0) uniform sampler baseSampler;
in vec2 surfaceUv;
in vec4 baseColor;
out vec4 fragColor;
@include_block unlitTexturedShade
void main() {
#ifdef UV_TRANSFORM
    vec2 uv = movedUv(surfaceUv);
#else
    vec2 uv = surfaceUv;
#endif
    vec4 texel = texture(sampler2D(baseTexture, baseSampler), uv);
#ifdef BACK_TEXTURE
    // Both read, then one kept: WGSL refuses a sample under non-uniform control flow.
    vec4 backTexel = texture(sampler2D(backTexture, baseSampler), backUv(surfaceUv));
    texel = gl_FrontFacing ? texel : backTexel;
#endif
#ifdef DISSOLVE
    float noise = texture(sampler2D(dissolveTexture, dissolveSampler), surfaceUv).r;
    if (noise < dissolve.x) {
        discard;
    }
#endif
#ifdef PREMULTIPLIED
    texel = straightTexel(texel);
#endif
    fragColor = unlitTexturedShade(texel);
#ifdef DISSOLVE
    fragColor = dissolveEdgeOver(fragColor, noise);
#endif
#ifdef CUTOUT
    if (fragColor.a < material.w) {
        discard;
    }
#endif
    fragColor.rgb = toneMapped(fragColor.rgb);
#ifdef PREMULTIPLIED
    fragColor = vec4(fragColor.rgb * fragColor.a, fragColor.a);
#endif
}
@end

// h3d.pass.Shadows writes depth only; a cutout caster discards at its colour program's alpha.
@fs shadowLitFs
#ifdef CUTOUT
@include_block materialUniforms
#endif
in vec3 worldPosition;
in vec3 worldNormal;
in vec4 baseColor;
void main() {
#ifdef CUTOUT
    if (baseColor.a < material.w) {
        discard;
    }
#endif
}
@end

@fs shadowLitTexturedFs
#ifdef DISSOLVE
@include_block movingMaterialUniforms
@include_block dissolveTexture
#elif defined(CUTOUT)
@include_block materialUniforms
#endif
#ifdef CUTOUT
layout(binding=0) uniform texture2D baseTexture;
layout(binding=0) uniform sampler baseSampler;
#endif
#ifdef NORMAL_MAP
in vec4 worldTangent;
#endif
in vec3 worldPosition;
in vec3 worldNormal;
in vec2 surfaceUv;
in vec4 baseColor;
void main() {
#ifdef DISSOLVE
    if (texture(sampler2D(dissolveTexture, dissolveSampler), surfaceUv).r < dissolve.x) {
        discard;
    }
#endif
#ifdef CUTOUT
    vec4 texel = texture(sampler2D(baseTexture, baseSampler), surfaceUv);
    if (baseColor.a * texel.a < material.w) {
        discard;
    }
#endif
}
@end

@fs shadowUnlitTexturedFs
#ifdef DISSOLVE
@include_block movingUnlitMaterialUniforms
@include_block dissolveTexture
#elif defined(CUTOUT)
@include_block unlitMaterialUniforms
#endif
#ifdef CUTOUT
layout(binding=0) uniform texture2D baseTexture;
layout(binding=0) uniform sampler baseSampler;
#endif
in vec2 surfaceUv;
in vec4 baseColor;
void main() {
#ifdef DISSOLVE
    if (texture(sampler2D(dissolveTexture, dissolveSampler), surfaceUv).r < dissolve.x) {
        discard;
    }
#endif
#ifdef CUTOUT
    vec4 texel = texture(sampler2D(baseTexture, baseSampler), surfaceUv);
    if (baseColor.a * materialColor.a * texel.a < material.w) {
        discard;
    }
#endif
}
@end

@vs particleVs
@include_block vertexUniforms
@include_block quadCorner
in vec4 root;
in vec4 color;
out vec4 particleColor;
void main() {
    vec2 corner = QUAD_CORNERS[gl_VertexIndex];
    vec3 p = root.xyz + cameraRight.xyz * (corner.x * root.w) + cameraUp.xyz * (corner.y * root.w);
    gl_Position = viewProj * vec4(p, 1.0);
    particleColor = color;
}
@end

@fs particleFs
// PENDING3D: particle-alpha-tested
@include_block colorSpace
@include_block frameUniforms
@include_block toneMap
in vec4 particleColor;
out vec4 fragColor;
void main() {
    if (particleColor.a < 0.5) {
        discard;
    }
    fragColor = particleColor;
    fragColor.rgb = toneMapped(fragColor.rgb);
}
@end

@vs billboardVs
@include_block vertexUniforms
@include_block quadCorner
@include_block billboardPoint
in vec3 position;
in vec2 size;
in vec2 anchor;
in vec4 tile;
in vec4 color;
out vec3 worldPosition;
out vec3 towardCamera;
out vec2 uv;
out vec4 instanceColor;
void main() {
    vec2 corner = QUAD_CORNERS[gl_VertexIndex];
    // PENDING3D: particle-size-world-units
    vec3 p = billboardPoint(position, size, anchor, corner);
    worldPosition = p;
    // PENDING3D: billboard-normal-toward-camera
    towardCamera = cross(cameraRight.xyz, cameraUp.xyz);
    gl_Position = viewProj * vec4(p, 1.0);
    uv = vec2(corner.x > 0.0 ? tile.z : tile.x, corner.y > 0.0 ? tile.y : tile.w);
    instanceColor = color;
}
@end

@fs billboardFs
@include_block billboardUniforms
@include_block lightUniforms
@include_block colorSpace
@include_block frameUniforms
@include_block toneMap
@include_block pointLight
#ifdef PREMULTIPLIED
@include_block straightTexel
#endif
layout(binding=0) uniform texture2D billboardTexture;
layout(binding=0) uniform sampler billboardSampler;
in vec3 worldPosition;
in vec3 towardCamera;
in vec2 uv;
in vec4 instanceColor;
out vec4 fragColor;
void main() {
    vec4 texel = texture(sampler2D(billboardTexture, billboardSampler), uv);
#ifdef PREMULTIPLIED
    texel = straightTexel(texel);
#endif
    vec4 pixel = billboardColor * texel * instanceColor;
#ifdef CUTOUT
    if (pixel.a < 0.5) {
        discard;
    }
#endif
    if (billboard.y != 0.0) {
        vec3 n = normalize(towardCamera);
        float lambert = max(dot(n, dirLight.xyz), 0.0) * dirLight.w;
        vec3 light = srgbToLinear(ambient.rgb) + srgbToLinear(dirColor.rgb) * lambert;
        for (int i = 0; i < int(ambient.a + 0.5); i++) {
            light += pointLightAt(i, worldPosition, n);
        }
        pixel.rgb = linearToSrgb(srgbToLinear(pixel.rgb) * light);
    }
    pixel.rgb = toneMapped(pixel.rgb);
#ifdef PREMULTIPLIED
    pixel = vec4(pixel.rgb * pixel.a, pixel.a);
#endif
    fragColor = pixel;
}
@end

@vs fullscreenVs
in vec2 position;
void main() {
    gl_Position = vec4(position, 0.5, 1.0);
}
@end

@fs copyFs
layout(binding=0) uniform texture2D sourceTexture;
layout(binding=0) uniform sampler pointSampler;
out vec4 fragColor;
void main() {
    ivec2 size = textureSize(sampler2D(sourceTexture, pointSampler), 0);
    ivec2 p = clamp(ivec2(gl_FragCoord.xy), ivec2(0, 0), size - ivec2(1, 1));
    vec4 texel = texelFetch(sampler2D(sourceTexture, pointSampler), p, 0);
    fragColor = vec4(texel.rgb, 1.0);
}
@end

@fs toneMapFs
// h3d.shader.pbr.ToneMapping over the HDR target: the linear colour times the exposure multiplier
// (toneMap.x), through the curve toneMap.y names, then encoded as the LDR target stores it. The
// target holds colour premultiplied by its alpha (a blend over a transparent clear), so the curve
// and the encode run on the straight colour and the result is premultiplied again, as the LDR
// presets store it; the alpha passes through for a caller compositing the target.
@include_block colorSpace
@include_block toneCurve
layout(binding=0) uniform texture2D hdrTexture;
layout(binding=0) uniform sampler pointSampler;
layout(binding=0) uniform toneMapParams {
    vec4 toneMap;
};
out vec4 fragColor;
void main() {
    ivec2 size = textureSize(sampler2D(hdrTexture, pointSampler), 0);
    ivec2 p = clamp(ivec2(gl_FragCoord.xy), ivec2(0, 0), size - ivec2(1, 1));
    vec4 texel = texelFetch(sampler2D(hdrTexture, pointSampler), p, 0);
    // An Rgba8 target saturates alpha at 1 (an additive layer adds to it); the HDR one does not.
    float alpha = clamp(texel.a, 0.0, 1.0);
    if (alpha <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }
    vec3 straight = texel.rgb / alpha;
    fragColor = vec4(linearToSrgb(toneCurved(straight * toneMap.x, toneMap.y)) * alpha, alpha);
}
@end

@block bloomUniforms
// Bevy 157e1ce6 bevy_post_process bloom.wesl BloomUniforms, for a fullscreen pass of one mip:
// bloomTexel.xy one texel of the source, .zw one texel of the target; bloomBlend.x the upsample's
// blend factor (mod.rs compute_blend_factor); bloomThreshold the soft threshold's precomputations
// (settings.rs), x above 0 when the prefilter is on.
layout(binding=0) uniform texture2D bloomSource;
layout(binding=0) uniform sampler bloomSampler;
layout(binding=0) uniform bloomParams {
    vec4 bloomTexel;
    vec4 bloomBlend;
    vec4 bloomThreshold;
};

vec3 bloomTap(vec2 uv, vec2 offset) {
    return texture(sampler2D(bloomSource, bloomSampler), uv + offset * bloomTexel.xy).rgb;
}
@end

@block bloomDownsampling
// bloom.wesl karis_average, Rec. 709 luminance.
float bloomKaris(vec3 color) {
    float luma = dot(color, vec3(0.2126, 0.7152, 0.0722)) / 4.0;
    return 1.0 / (1.0 + luma);
}

// bloom.wesl sample_input_13_tap ([COD] slide 153), the uniform-scale offsets.
vec3 bloom13(vec2 uv, bool karis) {
    vec3 a = bloomTap(uv, vec2(-2.0, 2.0));
    vec3 b = bloomTap(uv, vec2(0.0, 2.0));
    vec3 c = bloomTap(uv, vec2(2.0, 2.0));
    vec3 d = bloomTap(uv, vec2(-2.0, 0.0));
    vec3 e = bloomTap(uv, vec2(0.0, 0.0));
    vec3 f = bloomTap(uv, vec2(2.0, 0.0));
    vec3 g = bloomTap(uv, vec2(-2.0, -2.0));
    vec3 h = bloomTap(uv, vec2(0.0, -2.0));
    vec3 i = bloomTap(uv, vec2(2.0, -2.0));
    vec3 j = bloomTap(uv, vec2(-1.0, 1.0));
    vec3 k = bloomTap(uv, vec2(1.0, 1.0));
    vec3 l = bloomTap(uv, vec2(-1.0, -1.0));
    vec3 m = bloomTap(uv, vec2(1.0, -1.0));
    if (karis) {
        // [COD] slide 168: Karis' firefly reduction, per group, in linear light.
        vec3 group0 = (a + b + d + e) * (0.125 / 4.0);
        vec3 group1 = (b + c + e + f) * (0.125 / 4.0);
        vec3 group2 = (d + e + g + h) * (0.125 / 4.0);
        vec3 group3 = (e + f + h + i) * (0.125 / 4.0);
        vec3 group4 = (j + k + l + m) * (0.5 / 4.0);
        group0 *= bloomKaris(group0);
        group1 *= bloomKaris(group1);
        group2 *= bloomKaris(group2);
        group3 *= bloomKaris(group3);
        group4 *= bloomKaris(group4);
        return group0 + group1 + group2 + group3 + group4;
    }
    vec3 sum = (a + c + g + i) * 0.03125;
    sum += (b + d + f + h) * 0.0625;
    sum += (e + j + k + l + m) * 0.125;
    return sum;
}
@end

@fs bloomDownsampleFirstFs
// bloom.wesl downsample_first: the HDR target into mip 0, fireflies averaged out, floored at
// 0.0001 so a black region does not stay black through the chain, then the soft threshold.
@include_block bloomUniforms
@include_block bloomDownsampling
out vec4 fragColor;

vec3 softThreshold(vec3 color) {
    float brightness = max(color.r, max(color.g, color.b));
    float softness = clamp(brightness - bloomThreshold.y, 0.0, bloomThreshold.z);
    softness = softness * softness * bloomThreshold.w;
    float contribution = max(brightness - bloomThreshold.x, softness);
    return color * (contribution / max(brightness, 0.00001));
}

void main() {
    vec2 uv = gl_FragCoord.xy * bloomTexel.zw;
    vec3 sum = clamp(bloom13(uv, true), vec3(0.0001), vec3(3.40282347e37));
    if (bloomThreshold.x > 0.0) {
        sum = softThreshold(sum);
    }
    fragColor = vec4(sum, 1.0);
}
@end

@fs bloomDownsampleFs
// bloom.wesl downsample: mip i-1 into mip i.
@include_block bloomUniforms
@include_block bloomDownsampling
out vec4 fragColor;
void main() {
    fragColor = vec4(bloom13(gl_FragCoord.xy * bloomTexel.zw, false), 1.0);
}
@end

@fs bloomUpsampleFs
// bloom.wesl upsample ([COD] slide 162, the 3x3 tent), mip i onto mip i-1 or the HDR target. The
// blend factor rides in alpha in place of Bevy's blend constant (upsampling_pipeline.rs TODO):
// the pipeline blends One / OneMinusSrcAlpha (energy conserving) or One / One (additive) on
// colour, and leaves the target's alpha as it is.
@include_block bloomUniforms
out vec4 fragColor;
void main() {
    vec2 uv = gl_FragCoord.xy * bloomTexel.zw;
    vec3 sum = bloomTap(uv, vec2(0.0, 0.0)) * 0.25;
    sum += (bloomTap(uv, vec2(0.0, 1.0)) + bloomTap(uv, vec2(-1.0, 0.0)) +
        bloomTap(uv, vec2(1.0, 0.0)) + bloomTap(uv, vec2(0.0, -1.0))) * 0.125;
    sum += (bloomTap(uv, vec2(-1.0, 1.0)) + bloomTap(uv, vec2(1.0, 1.0)) +
        bloomTap(uv, vec2(-1.0, -1.0)) + bloomTap(uv, vec2(1.0, -1.0))) * 0.0625;
    float factor = bloomBlend.x;
    fragColor = vec4(sum * factor, factor);
}
@end
