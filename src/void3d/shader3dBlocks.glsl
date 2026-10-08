@block vertexUniforms
layout(binding=0) uniform vertexParams {
    mat4 viewProj;
    vec4 cameraRight;
    vec4 cameraUp;
};
@end

@block modelUniforms
layout(binding=4) uniform modelParams {
    mat4 model;
    mat4 normalModel;
};
@end

@block modelTransformUniforms
layout(binding=4) uniform modelTransformParams {
    mat4 model;
};
@end

@block quadCorner
// h3d.parts.Particles' quad, ±0.5 around the instance, two triangles, read by the vertex index
// with no buffer behind it; Bevy's sprite.wgsl makes its four corners from the index's bits.
const vec2 QUAD_CORNERS[6] = vec2[6](
    vec2(-0.5, -0.5), vec2(0.5, -0.5), vec2(0.5, 0.5),
    vec2(-0.5, -0.5), vec2(0.5, 0.5), vec2(-0.5, 0.5));
@end

@block billboardPoint
vec3 billboardPoint(vec3 position, vec2 size, vec2 anchor, vec2 corner) {
    vec2 offset = corner - anchor;
    return position + cameraRight.xyz * (offset.x * size.x) + cameraUp.xyz * (offset.y * size.y);
}
@end

@block billboardUniforms
layout(binding=2) uniform billboardParams {
    vec4 billboardColor;
    vec4 billboard;
};
@end

@block materialUniforms
layout(binding=3) uniform materialParams {
    vec4 material;
};
@end

@block unlitMaterialUniforms
layout(binding=3) uniform unlitMaterialParams {
    vec4 material;
    vec4 materialColor;
};
@end

@block movingMaterialUniforms
// gpu3d.ms MOVING_*: materialParams, then what a key with a UV transform, a back texture or a
// dissolve reads.
layout(binding=3) uniform movingMaterialParams {
    vec4 material;
    vec4 uvMatrix;
    vec4 uvMotion;
    vec4 backUvMatrix;
    vec4 backUvOffset;
    vec4 dissolve;
    vec4 dissolveEdge;
};
@end

@block movingUnlitMaterialUniforms
layout(binding=3) uniform movingUnlitMaterialParams {
    vec4 material;
    vec4 materialColor;
    vec4 uvMatrix;
    vec4 uvMotion;
    vec4 backUvMatrix;
    vec4 backUvOffset;
    vec4 dissolve;
    vec4 dissolveEdge;
};
@end

@block emissiveMaterialUniforms
layout(binding=3) uniform emissiveMaterialParams {
    vec4 material;
    vec4 emissive;
};
@end

@block movingEmissiveMaterialUniforms
// movingMaterialParams, then the emissive vec4 (gpu3d.ms emissiveBase).
layout(binding=3) uniform movingEmissiveMaterialParams {
    vec4 material;
    vec4 uvMatrix;
    vec4 uvMotion;
    vec4 backUvMatrix;
    vec4 backUvOffset;
    vec4 dissolve;
    vec4 dissolveEdge;
    vec4 emissive;
};
@end

@block emissiveTexture
// three d4ea9b9 meshphong.glsl.js:94 and emissivemap_fragment: the emissive colour times the
// decoded map, added to the lit colour in linear light.
layout(binding=3) uniform texture2D emissiveTexture;

vec4 emittedOver(vec4 color, vec3 texel) {
    vec3 emitted = srgbToLinear(emissive.rgb) * srgbToLinear(texel) * emissive.a;
    return vec4(linearToSrgb(srgbToLinear(color.rgb) + emitted), color.a);
}
@end

@block normalMap
// three d4ea9b9 normal_vertex.glsl.js:9 and normal_fragment_begin/maps: glTF's tangent, w the
// bitangent's sign, and on a flipped back face the whole frame turns with the normal.
layout(binding=5) uniform texture2D normalTexture;

vec3 mappedNormal(vec3 normal, vec4 tangent, float face, vec3 texel) {
    vec3 t = normalize(tangent.xyz);
    vec3 b = normalize(cross(normal, t)) * (tangent.w < 0.0 ? -1.0 : 1.0);
    vec3 mapped = texel * 2.0 - 1.0;
    return normalize(mapped.x * t + mapped.y * b + mapped.z * normal) * face;
}
@end

@block frameUniforms
// h3d.scene.RenderContext's `global.time`: frame.x, seconds (renderer.ms setElapsedTime).
layout(binding=6) uniform frameParams {
    vec4 frame;
};
@end

@block toneMap
// h3d.shader.pbr.ToneMapping mode 0 (linear), per fragment: the decoded colour times frame.y,
// saturated, encoded again. frame.y is exactly 1 at exposure 0, and the colour is left alone.
vec3 toneMapped(vec3 rgb) {
    if (frame.y == 1.0) {
        return rgb;
    }
    return linearToSrgb(clamp(srgbToLinear(rgb) * frame.y, 0.0, 1.0));
}
@end

@block movedUv
// h3d.shader.UVDelta's transform as Bevy's uv_transform (an Affine2), then UVScroll's
// `uvSpeed * global.time`.
vec2 movedUv(vec2 uv) {
    return mat2(uvMatrix.xy, uvMatrix.zw) * uv + uvMotion.xy + uvMotion.zw * frame.x;
}
@end

@block backTexture
// Read on back faces through its own transform, with the base texture's sampler.
layout(binding=1) uniform texture2D backTexture;

vec2 backUv(vec2 uv) {
    return mat2(backUvMatrix.xy, backUvMatrix.zw) * uv + backUvOffset.xy;
}
@end

@block dissolveTexture
// Heaps' AlphaMap read as KillAlpha reads its threshold: a pixel whose noise is below
// dissolve.x is discarded; above it, a band dissolve.y wide takes dissolveEdge, mixed by its
// alpha, while the threshold is above 0.
layout(binding=2) uniform texture2D dissolveTexture;
layout(binding=1) uniform sampler dissolveSampler;

vec4 dissolveEdgeOver(vec4 color, float noise) {
    bool edge = dissolve.x > 0.0 && noise < dissolve.x + dissolve.y;
    return edge ? vec4(mix(color.rgb, dissolveEdge.rgb, dissolveEdge.a), color.a) : color;
}
@end

@block saturation
// h3d.Matrix.colorSaturate in scalar form; campfireGreyCpuCapture holds it to colorSaturated.
vec3 saturated(vec3 rgb, float amount) {
    if (amount == 0.0) {
        return rgb;
    }
    float luma = dot(rgb, vec3(0.212671, 0.71516, 0.072169));
    float keep = amount + 1.0;
    return rgb * keep + vec3(luma * (1.0 - keep));
}
@end

@block colorSpace
// h3d.shader.ColorSpaces' exact pair (ColorSpaces.hx:56-76); bevy_color's gamma_function
// carries the same constants. Colour inputs and stored targets stay gamma-encoded. The pow
// operands clamp at 0 only to keep fxc's X3571 out of consumer stdout: output-neutral, the
// selects route every input a matrix can make negative to the linear branch.
vec3 srgbToLinear(vec3 srgb) {
    vec3 low = srgb * 0.0773993808;
    vec3 high = pow(max(srgb * 0.9478672986 + vec3(0.0521327014), vec3(0.0)), vec3(2.4));
    return vec3(
        srgb.x <= 0.04045 ? low.x : high.x,
        srgb.y <= 0.04045 ? low.y : high.y,
        srgb.z <= 0.04045 ? low.z : high.z);
}

vec3 linearToSrgb(vec3 rgb) {
    vec3 low = rgb * 12.92;
    vec3 high = vec3(1.055) * pow(max(rgb, vec3(0.0)), vec3(0.41666)) - vec3(0.055);
    return vec3(
        rgb.x <= 0.0031308 ? low.x : high.x,
        rgb.y <= 0.0031308 ? low.y : high.y,
        rgb.z <= 0.0031308 ? low.z : high.z);
}
@end

@block unlitTexturedShade
vec4 unlitTexturedShade(vec4 texel) {
    vec3 surface = srgbToLinear(baseColor.rgb) * srgbToLinear(materialColor.rgb);
    surface *= srgbToLinear(texel.rgb);
    return vec4(linearToSrgb(surface), baseColor.a * materialColor.a * texel.a);
}
@end

@block straightTexel
// Unpremultiply before srgbToLinear, never after: three d4ea9b9 RenderOutputNode.js:115-137.
vec4 straightTexel(vec4 texel) {
    return texel.a > 0.0 ? vec4(texel.rgb / texel.a, texel.a) : vec4(0.0);
}
@end

@block facingNormal
// h3d.shader.FlipBackFaceNormal, on when the material says so (glTF doubleSided).
vec3 facingNormal(vec3 normal, float doubleSided) {
    return (doubleSided > 0.5 && !gl_FrontFacing) ? -normal : normal;
}

float faceOf(float doubleSided) {
    return (doubleSided > 0.5 && !gl_FrontFacing) ? -1.0 : 1.0;
}
@end

@block lightUniforms
layout(binding=1) uniform lightParams {
    vec4 ambient;
    vec4 dirLight;
    vec4 dirColor;
    vec4 pointLight[4];
    vec4 pointColor[4];
};

@end

@block dirShadow
// h3d.shader.ShadowSampling.sampleShadow with SAMPLING_NONE, on the map dirShadowMap.ms draws.
// shadowMatrix takes a world position to the map's texel space and to the depth the backend
// stores, so the compare reads the attachment as written; shadow.x is the bias in that depth,
// shadow.y the opacity (1 a full shadow).
layout(binding=5) uniform shadowParams {
    mat4 shadowMatrix;
    vec4 shadow;
};
@image_sample_type shadowMap unfilterable_float
@sampler_type shadowSampler nonfiltering
layout(binding=4) uniform texture2D shadowMap;
layout(binding=2) uniform sampler shadowSampler;

float dirShadowAt(vec3 position) {
    vec3 p = (shadowMatrix * vec4(position, 1.0)).xyz;
    if (p.x <= 0.0 || p.x >= 1.0 || p.y <= 0.0 || p.y >= 1.0) {
        return 1.0;
    }
    ivec2 size = textureSize(sampler2D(shadowMap, shadowSampler), 0);
    ivec2 texel = clamp(ivec2(p.xy * vec2(size)), ivec2(0, 0), size - ivec2(1, 1));
    float depth = texelFetch(sampler2D(shadowMap, shadowSampler), texel, 0).r;
    float lit = (clamp(p.z, 0.0, 1.0) - shadow.x > depth) ? 0.0 : 1.0;
    return mix(1.0, lit, shadow.y);
}

@end
