@fs copyFs
layout(binding=0) uniform texture2D sourceTexture;
layout(binding=0) uniform sampler pointSampler;
layout(location=0) out vec4 fragColor;
void main() {
    ivec2 size = textureSize(sampler2D(sourceTexture, pointSampler), 0);
    ivec2 p = clamp(ivec2(gl_FragCoord.xy), ivec2(0, 0), (size - ivec2(1, 1)));
    fragColor = texelFetch(sampler2D(sourceTexture, pointSampler), p, 0);
    return;
}
@end

@vs litVs
layout(binding=0) uniform vertexParams {
    mat4 viewProj;
    vec4 cameraRight;
    vec4 cameraUp;
};
layout(binding=4) uniform modelParams {
    mat4 model;
    mat4 normalModel;
};
in vec3 position;
in vec3 normal;
in vec4 color;
out vec3 worldPosition;
out vec3 worldNormal;
out vec4 baseColor;
void main() {
    vec4 world = model * vec4(position, 1.0);
    worldPosition = world.xyz;
    worldNormal = (mat3(normalModel) * normal);
    baseColor = color;
    gl_Position = (viewProj * world);
    return;
}
@end

@fs litFs
#if (!((defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE))) && !defined(EMISSIVE)
layout(binding=3) uniform materialParams {
    vec4 material;
};
#endif
#if ((defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE)) && !defined(EMISSIVE)
layout(binding=3) uniform movingMaterialParams {
    vec4 material;
    vec4 uvMatrix;
    vec4 uvMotion;
    vec4 backUvMatrix;
    vec4 backUvOffset;
    vec4 dissolve;
    vec4 dissolveEdge;
};
#endif
#if (!((defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE))) && defined(EMISSIVE)
layout(binding=3) uniform emissiveMaterialParams {
    vec4 material;
    vec4 emissive;
};
#endif
#if ((defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE)) && defined(EMISSIVE)
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
#endif
layout(binding=1) uniform lightParams {
    vec4 ambient;
    vec4 dirLight;
    vec4 dirColor;
    vec4 pointLight[4];
    vec4 pointColor[4];
};
layout(binding=6) uniform frameParams {
    vec4 frame;
};
#ifdef SHADOWED
layout(binding=5) uniform shadowParams {
    mat4 shadowMatrix;
    vec4 shadow;
};
#endif
#ifdef SHADOWED
@image_sample_type shadowMap unfilterable_float
layout(binding=4) uniform texture2D shadowMap;
#endif
#ifdef SHADOWED
@sampler_type shadowSampler nonfiltering
layout(binding=2) uniform sampler shadowSampler;
#endif
in vec3 worldPosition;
in vec3 worldNormal;
in vec4 baseColor;
layout(location=0) out vec4 color;
#ifdef NORMAL_MRT
layout(location=1) out vec4 normal;
#endif
vec4 materialOf() {
#if (defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE)
#ifdef EMISSIVE
    return material;
#else
    return material;
#endif
#else
#ifdef EMISSIVE
    return material;
#else
    return material;
#endif
#endif
}
vec3 facingNormal(vec3 normal_1, float doubleSided, bool frontFacing) {
    return ((doubleSided > 0.5) && (!frontFacing)) ? (-normal_1) : normal_1;
}
#ifdef SHADOWED
float dirShadowAt(vec3 position) {
    vec3 p = (shadowMatrix * vec4(position, 1.0)).xyz;
    if ((((p.x <= 0.0) || (p.x >= 1.0)) || (p.y <= 0.0)) || (p.y >= 1.0)) {
        return 1.0;
    }
    ivec2 size = textureSize(sampler2D(shadowMap, shadowSampler), 0);
    ivec2 texel = clamp(ivec2((p.xy * vec2(size))), ivec2(0, 0), (size - ivec2(1, 1)));
    float depth = texelFetch(sampler2D(shadowMap, shadowSampler), texel, 0).x;
    float lit = ((clamp(p.z, 0.0, 1.0) - shadow.x) > depth) ? 0.0 : 1.0;
    return mix(1.0, lit, shadow.y);
}
#endif
vec3 srgbToLinear(vec3 srgb) {
    vec3 low = srgb * 0.0773993808;
    vec3 high = pow(max(((srgb * 0.9478672986) + vec3(0.0521327014)), vec3(0.0)), vec3(2.4));
    return vec3(((srgb.x <= 0.04045) ? low.x : high.x), ((srgb.y <= 0.04045) ? low.y : high.y), ((srgb.z <= 0.04045) ? low.z : high.z));
}
vec3 pointLightAt(vec3 position, vec3 normal_1, vec4 at, vec4 tint) {
    vec3 toLight = at.xyz - position;
    float distance_1 = length(toLight);
    float falloff = clamp((1.0 - (distance_1 / tint.a)), 0.0, 1.0);
    float facing = max(dot(normal_1, (toLight / max(distance_1, 0.0001))), 0.0);
    return srgbToLinear(tint.rgb) * (((falloff * falloff) * facing) * at.w);
}
vec3 saturated(vec3 rgb, float amount) {
    if (amount == 0.0) {
        return rgb;
    }
    float luma = dot(rgb, vec3(0.212671, 0.71516, 0.072169));
    float keep = amount + 1.0;
    return (rgb * keep) + vec3((luma * (1.0 - keep)));
}
vec3 linearToSrgb(vec3 rgb) {
    vec3 low = rgb * 12.92;
    vec3 high = (vec3(1.055) * pow(max(rgb, vec3(0.0)), vec3(0.41666))) - vec3(0.055);
    return vec3(((rgb.x <= 0.0031308) ? low.x : high.x), ((rgb.y <= 0.0031308) ? low.y : high.y), ((rgb.z <= 0.0031308) ? low.z : high.z));
}
vec4 litShade(vec3 n, vec3 position, vec4 surfaceColor) {
    vec4 dir = dirLight;
    float lambert = max(dot(n, dir.xyz), 0.0) * dir.w;
#ifdef SHADOWED
    lambert = lambert * dirShadowAt(position);
#endif
    vec3 ambient_1 = srgbToLinear(ambient.rgb);
    vec3 light = ambient_1 + (srgbToLinear(dirColor.rgb) * lambert);
    for (int i = 0; i < int(ambient.a + 0.5); i++) {
        vec4 at = pointLight[i];
        light = light + pointLightAt(position, n, at, pointColor[i]);
    }
    vec3 surface = srgbToLinear(saturated(surfaceColor.rgb, materialOf().y));
    return vec4(linearToSrgb((surface * light)), surfaceColor.a);
}
vec3 toneCurved(vec3 exposed, float mode) {
    if (mode == 1.0) {
        return exposed / (exposed + vec3(1.0));
    }
    if (mode == 2.0) {
        vec3 a = exposed * ((2.51 * exposed) + 0.03);
        vec3 b = (exposed * ((2.43 * exposed) + 0.59)) + 0.14;
        return clamp((a / b), vec3(0.0), vec3(1.0));
    }
    if (mode == 3.0) {
        float startCompression = 0.76;
        float desaturation = 0.15;
        float x = min(exposed.x, min(exposed.y, exposed.z));
        float offset = (x < 0.08) ? (x - ((6.25 * x) * x)) : 0.04;
        vec3 color_1 = exposed - offset;
        float peak = max(color_1.x, max(color_1.y, color_1.z));
        if (peak >= startCompression) {
            float d = 1.0 - startCompression;
            float newPeak = 1.0 - ((d * d) / ((peak + d) - startCompression));
            color_1 = color_1 * (newPeak / peak);
            float g = 1.0 - (1.0 / ((desaturation * (peak - newPeak)) + 1.0));
            color_1 = mix(color_1, vec3(newPeak), g);
        }
        return color_1;
    }
    return clamp(exposed, vec3(0.0), vec3(1.0));
}
vec3 toneMapped(vec3 rgb, vec4 tone) {
    if (tone.z == 1.0) {
        return srgbToLinear(rgb);
    }
    if ((tone.y == 1.0) && (tone.w == 0.0)) {
        return rgb;
    }
    return linearToSrgb(toneCurved((srgbToLinear(rgb) * tone.y), tone.w));
}
void main() {
    vec4 params = materialOf();
    vec3 n = facingNormal(normalize(worldNormal), params.z, gl_FrontFacing);
    vec4 shaded = litShade(n, worldPosition, baseColor);
#ifdef CUTOUT
    if (shaded.a < params.w) {
        discard;
    }
#endif
    color = vec4(toneMapped(shaded.rgb, frame), shaded.a);
#ifdef NORMAL_MRT
    normal = vec4(((n * 0.5) + 0.5), 1.0);
#endif
    return;
}
@end

@fs shadowLitFs
#if defined(CUTOUT) && (!((defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE))) && !defined(EMISSIVE)
layout(binding=3) uniform materialParams {
    vec4 material;
};
#endif
#if defined(CUTOUT) && ((defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE)) && !defined(EMISSIVE)
layout(binding=3) uniform movingMaterialParams {
    vec4 material;
    vec4 uvMatrix;
    vec4 uvMotion;
    vec4 backUvMatrix;
    vec4 backUvOffset;
    vec4 dissolve;
    vec4 dissolveEdge;
};
#endif
#if defined(CUTOUT) && (!((defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE))) && defined(EMISSIVE)
layout(binding=3) uniform emissiveMaterialParams {
    vec4 material;
    vec4 emissive;
};
#endif
#if defined(CUTOUT) && ((defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE)) && defined(EMISSIVE)
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
#endif
in vec3 worldPosition;
in vec3 worldNormal;
in vec4 baseColor;
#ifdef CUTOUT
vec4 materialOf() {
#if (defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE)
#ifdef EMISSIVE
    return material;
#else
    return material;
#endif
#else
#ifdef EMISSIVE
    return material;
#else
    return material;
#endif
#endif
}
#endif
void main() {
#ifdef CUTOUT
    if (baseColor.a < materialOf().w) {
        discard;
    }
#endif
}
@end

@vs litTexturedVs
layout(binding=0) uniform vertexParams {
    mat4 viewProj;
    vec4 cameraRight;
    vec4 cameraUp;
};
layout(binding=4) uniform modelParams {
    mat4 model;
    mat4 normalModel;
};
in vec3 position;
in vec3 normal;
in vec2 uv;
in vec4 color;
#ifdef NORMAL_MAP
in vec4 tangent;
#endif
#ifdef NORMAL_MAP
out vec4 worldTangent;
#endif
out vec3 worldPosition;
out vec3 worldNormal;
out vec2 surfaceUv;
out vec4 baseColor;
void main() {
    vec4 world = model * vec4(position, 1.0);
    worldPosition = world.xyz;
    worldNormal = (mat3(normalModel) * normal);
#ifdef NORMAL_MAP
    worldTangent = vec4((mat3(model) * tangent.xyz), tangent.w);
#endif
    surfaceUv = uv;
    baseColor = color;
    gl_Position = (viewProj * world);
    return;
}
@end

@fs litTexturedFs
#if (!((defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE))) && !defined(EMISSIVE)
layout(binding=3) uniform materialParams {
    vec4 material;
};
#endif
#if (((defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE)) && !defined(EMISSIVE)) || (defined(UV_TRANSFORM) && !defined(EMISSIVE)) || (defined(BACK_TEXTURE) && !defined(EMISSIVE)) || (defined(DISSOLVE) && !defined(EMISSIVE))
layout(binding=3) uniform movingMaterialParams {
    vec4 material;
    vec4 uvMatrix;
    vec4 uvMotion;
    vec4 backUvMatrix;
    vec4 backUvOffset;
    vec4 dissolve;
    vec4 dissolveEdge;
};
#endif
#if ((!((defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE))) && defined(EMISSIVE)) || (defined(EMISSIVE) && (!((defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE))))
layout(binding=3) uniform emissiveMaterialParams {
    vec4 material;
    vec4 emissive;
};
#endif
#if (((defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE)) && defined(EMISSIVE)) || (defined(UV_TRANSFORM) && defined(EMISSIVE)) || (defined(BACK_TEXTURE) && defined(EMISSIVE)) || (defined(DISSOLVE) && defined(EMISSIVE)) || (defined(EMISSIVE) && ((defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE)))
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
#endif
layout(binding=1) uniform lightParams {
    vec4 ambient;
    vec4 dirLight;
    vec4 dirColor;
    vec4 pointLight[4];
    vec4 pointColor[4];
};
layout(binding=6) uniform frameParams {
    vec4 frame;
};
#ifdef SHADOWED
layout(binding=5) uniform shadowParams {
    mat4 shadowMatrix;
    vec4 shadow;
};
#endif
#ifdef SHADOWED
@image_sample_type shadowMap unfilterable_float
layout(binding=4) uniform texture2D shadowMap;
#endif
#ifdef SHADOWED
@sampler_type shadowSampler nonfiltering
layout(binding=2) uniform sampler shadowSampler;
#endif
layout(binding=0) uniform texture2D baseTexture;
layout(binding=0) uniform sampler baseSampler;
#ifdef BACK_TEXTURE
layout(binding=1) uniform texture2D backTexture;
#endif
#ifdef DISSOLVE
layout(binding=2) uniform texture2D dissolveTexture;
#endif
#ifdef DISSOLVE
layout(binding=1) uniform sampler dissolveSampler;
#endif
#ifdef EMISSIVE
layout(binding=3) uniform texture2D emissiveTexture;
#endif
#ifdef NORMAL_MAP
layout(binding=5) uniform texture2D normalTexture;
#endif
#ifdef NORMAL_MAP
in vec4 worldTangent;
#endif
in vec3 worldPosition;
in vec3 worldNormal;
in vec2 surfaceUv;
in vec4 baseColor;
layout(location=0) out vec4 color;
#ifdef NORMAL_MRT
layout(location=1) out vec4 normal;
#endif
vec4 materialOf() {
#if (defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE)
#ifdef EMISSIVE
    return material;
#else
    return material;
#endif
#else
#ifdef EMISSIVE
    return material;
#else
    return material;
#endif
#endif
}
#ifdef UV_TRANSFORM
vec2 movedUv(vec2 uv, vec4 matrix, vec4 motion, float time) {
    return ((mat2(matrix.xy, matrix.zw) * uv) + motion.xy) + (motion.zw * time);
}
#endif
#ifdef UV_TRANSFORM
vec4 uvMatrixOf() {
#ifdef EMISSIVE
    return uvMatrix;
#else
    return uvMatrix;
#endif
}
#endif
#ifdef UV_TRANSFORM
vec4 uvMotionOf() {
#ifdef EMISSIVE
    return uvMotion;
#else
    return uvMotion;
#endif
}
#endif
#ifdef BACK_TEXTURE
vec2 backUv(vec2 uv, vec4 matrix, vec4 offset) {
    return (mat2(matrix.xy, matrix.zw) * uv) + offset.xy;
}
#endif
#ifdef BACK_TEXTURE
vec4 backUvMatrixOf() {
#ifdef EMISSIVE
    return backUvMatrix;
#else
    return backUvMatrix;
#endif
}
#endif
#ifdef BACK_TEXTURE
vec4 backUvOffsetOf() {
#ifdef EMISSIVE
    return backUvOffset;
#else
    return backUvOffset;
#endif
}
#endif
#ifdef DISSOLVE
vec4 dissolveOf() {
#ifdef EMISSIVE
    return dissolve;
#else
    return dissolve;
#endif
}
#endif
#ifdef PREMULTIPLIED
vec4 straightTexel(vec4 texel) {
    return (texel.a > 0.0) ? vec4((texel.rgb / texel.a), texel.a) : vec4(0.0);
}
#endif
vec3 facingNormal(vec3 normal_1, float doubleSided, bool frontFacing) {
    return ((doubleSided > 0.5) && (!frontFacing)) ? (-normal_1) : normal_1;
}
#ifdef NORMAL_MAP
float faceOf(float doubleSided, bool frontFacing) {
    return ((doubleSided > 0.5) && (!frontFacing)) ? (-1.0) : 1.0;
}
#endif
#ifdef NORMAL_MAP
vec3 mappedNormal(vec3 normal_1, vec4 tangent, float face, vec3 texel) {
    vec3 t = normalize(tangent.xyz);
    float sign_1 = (tangent.w < 0.0) ? (-1.0) : 1.0;
    vec3 bitangent = normalize(cross(normal_1, t)) * sign_1;
    vec3 mapped = (texel * 2.0) - 1.0;
    return normalize((((mapped.x * t) + (mapped.y * bitangent)) + (mapped.z * normal_1))) * face;
}
#endif
#ifdef SHADOWED
float dirShadowAt(vec3 position) {
    vec3 p = (shadowMatrix * vec4(position, 1.0)).xyz;
    if ((((p.x <= 0.0) || (p.x >= 1.0)) || (p.y <= 0.0)) || (p.y >= 1.0)) {
        return 1.0;
    }
    ivec2 size = textureSize(sampler2D(shadowMap, shadowSampler), 0);
    ivec2 texel = clamp(ivec2((p.xy * vec2(size))), ivec2(0, 0), (size - ivec2(1, 1)));
    float depth = texelFetch(sampler2D(shadowMap, shadowSampler), texel, 0).x;
    float lit = ((clamp(p.z, 0.0, 1.0) - shadow.x) > depth) ? 0.0 : 1.0;
    return mix(1.0, lit, shadow.y);
}
#endif
vec3 srgbToLinear(vec3 srgb) {
    vec3 low = srgb * 0.0773993808;
    vec3 high = pow(max(((srgb * 0.9478672986) + vec3(0.0521327014)), vec3(0.0)), vec3(2.4));
    return vec3(((srgb.x <= 0.04045) ? low.x : high.x), ((srgb.y <= 0.04045) ? low.y : high.y), ((srgb.z <= 0.04045) ? low.z : high.z));
}
vec3 pointLightAt(vec3 position, vec3 normal_1, vec4 at, vec4 tint) {
    vec3 toLight = at.xyz - position;
    float distance_1 = length(toLight);
    float falloff = clamp((1.0 - (distance_1 / tint.a)), 0.0, 1.0);
    float facing = max(dot(normal_1, (toLight / max(distance_1, 0.0001))), 0.0);
    return srgbToLinear(tint.rgb) * (((falloff * falloff) * facing) * at.w);
}
vec3 saturated(vec3 rgb, float amount) {
    if (amount == 0.0) {
        return rgb;
    }
    float luma = dot(rgb, vec3(0.212671, 0.71516, 0.072169));
    float keep = amount + 1.0;
    return (rgb * keep) + vec3((luma * (1.0 - keep)));
}
vec3 linearToSrgb(vec3 rgb) {
    vec3 low = rgb * 12.92;
    vec3 high = (vec3(1.055) * pow(max(rgb, vec3(0.0)), vec3(0.41666))) - vec3(0.055);
    return vec3(((rgb.x <= 0.0031308) ? low.x : high.x), ((rgb.y <= 0.0031308) ? low.y : high.y), ((rgb.z <= 0.0031308) ? low.z : high.z));
}
vec4 litShade(vec3 n, vec3 position, vec4 surfaceColor) {
    vec4 dir = dirLight;
    float lambert = max(dot(n, dir.xyz), 0.0) * dir.w;
#ifdef SHADOWED
    lambert = lambert * dirShadowAt(position);
#endif
    vec3 ambient_1 = srgbToLinear(ambient.rgb);
    vec3 light = ambient_1 + (srgbToLinear(dirColor.rgb) * lambert);
    for (int i = 0; i < int(ambient.a + 0.5); i++) {
        vec4 at = pointLight[i];
        light = light + pointLightAt(position, n, at, pointColor[i]);
    }
    vec3 surface = srgbToLinear(saturated(surfaceColor.rgb, materialOf().y));
    return vec4(linearToSrgb((surface * light)), surfaceColor.a);
}
#ifdef EMISSIVE
vec4 emittedOver(vec4 color_1, vec3 texel, vec4 emissive_1) {
    vec3 emitted = (srgbToLinear(emissive_1.rgb) * srgbToLinear(texel)) * emissive_1.a;
    return vec4(linearToSrgb((srgbToLinear(color_1.rgb) + emitted)), color_1.a);
}
#endif
#ifdef EMISSIVE
vec4 emissiveOf() {
#if (defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE)
    return emissive;
#else
    return emissive;
#endif
}
#endif
#ifdef DISSOLVE
vec4 dissolveEdgeOver(vec4 color_1, float noise, vec4 dissolve_1, vec4 edge) {
    bool onEdge = (dissolve_1.x > 0.0) && (noise < (dissolve_1.x + dissolve_1.y));
    return onEdge ? vec4(mix(color_1.rgb, edge.rgb, edge.a), color_1.a) : color_1;
}
#endif
#ifdef DISSOLVE
vec4 dissolveEdgeOf() {
#ifdef EMISSIVE
    return dissolveEdge;
#else
    return dissolveEdge;
#endif
}
#endif
vec3 toneCurved(vec3 exposed, float mode) {
    if (mode == 1.0) {
        return exposed / (exposed + vec3(1.0));
    }
    if (mode == 2.0) {
        vec3 a = exposed * ((2.51 * exposed) + 0.03);
        vec3 b = (exposed * ((2.43 * exposed) + 0.59)) + 0.14;
        return clamp((a / b), vec3(0.0), vec3(1.0));
    }
    if (mode == 3.0) {
        float startCompression = 0.76;
        float desaturation = 0.15;
        float x = min(exposed.x, min(exposed.y, exposed.z));
        float offset = (x < 0.08) ? (x - ((6.25 * x) * x)) : 0.04;
        vec3 color_1 = exposed - offset;
        float peak = max(color_1.x, max(color_1.y, color_1.z));
        if (peak >= startCompression) {
            float d = 1.0 - startCompression;
            float newPeak = 1.0 - ((d * d) / ((peak + d) - startCompression));
            color_1 = color_1 * (newPeak / peak);
            float g = 1.0 - (1.0 / ((desaturation * (peak - newPeak)) + 1.0));
            color_1 = mix(color_1, vec3(newPeak), g);
        }
        return color_1;
    }
    return clamp(exposed, vec3(0.0), vec3(1.0));
}
vec3 toneMapped(vec3 rgb, vec4 tone) {
    if (tone.z == 1.0) {
        return srgbToLinear(rgb);
    }
    if ((tone.y == 1.0) && (tone.w == 0.0)) {
        return rgb;
    }
    return linearToSrgb(toneCurved((srgbToLinear(rgb) * tone.y), tone.w));
}
void main() {
    vec4 params = materialOf();
    vec2 uv = surfaceUv;
#ifdef UV_TRANSFORM
    float time = frame.x;
    uv = movedUv(surfaceUv, uvMatrixOf(), uvMotionOf(), time);
#endif
    vec4 texel = texture(sampler2D(baseTexture, baseSampler), uv);
#ifdef BACK_TEXTURE
    vec2 backAt = backUv(surfaceUv, backUvMatrixOf(), backUvOffsetOf());
    vec4 backTexel = texture(sampler2D(backTexture, baseSampler), backAt);
    texel = gl_FrontFacing ? texel : backTexel;
#endif
    float noise = 0.0;
#ifdef DISSOLVE
    noise = texture(sampler2D(dissolveTexture, dissolveSampler), surfaceUv).x;
    if (noise < dissolveOf().x) {
        discard;
    }
#endif
#ifdef PREMULTIPLIED
    texel = straightTexel(texel);
#endif
    vec3 n = facingNormal(normalize(worldNormal), params.z, gl_FrontFacing);
#ifdef NORMAL_MAP
    vec3 normalTexel = texture(sampler2D(normalTexture, baseSampler), uv).rgb;
    float face = faceOf(params.z, gl_FrontFacing);
    n = mappedNormal(normalize(worldNormal), worldTangent, face, normalTexel);
#endif
    vec4 surfaceColor = vec4((baseColor.rgb * texel.rgb), (baseColor.a * texel.a));
    vec4 shaded = litShade(n, worldPosition, surfaceColor);
#ifdef EMISSIVE
    vec3 glow = texture(sampler2D(emissiveTexture, baseSampler), uv).rgb;
    shaded = emittedOver(shaded, glow, emissiveOf());
#endif
#ifdef DISSOLVE
    shaded = dissolveEdgeOver(shaded, noise, dissolveOf(), dissolveEdgeOf());
#endif
#ifdef CUTOUT
    if (shaded.a < params.w) {
        discard;
    }
#endif
    vec4 color_1 = vec4(toneMapped(shaded.rgb, frame), shaded.a);
#ifdef PREMULTIPLIED
    color_1 = vec4((color_1.rgb * color_1.a), color_1.a);
#endif
    color = color_1;
#ifdef NORMAL_MRT
    normal = vec4(((n * 0.5) + 0.5), 1.0);
#endif
    return;
}
@end

@fs shadowLitTexturedFs
#if defined(CUTOUT) && (!((defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE))) && !defined(EMISSIVE)
layout(binding=3) uniform materialParams {
    vec4 material;
};
#endif
#if (defined(DISSOLVE) && !defined(EMISSIVE)) || (defined(CUTOUT) && ((defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE)) && !defined(EMISSIVE))
layout(binding=3) uniform movingMaterialParams {
    vec4 material;
    vec4 uvMatrix;
    vec4 uvMotion;
    vec4 backUvMatrix;
    vec4 backUvOffset;
    vec4 dissolve;
    vec4 dissolveEdge;
};
#endif
#if defined(CUTOUT) && (!((defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE))) && defined(EMISSIVE)
layout(binding=3) uniform emissiveMaterialParams {
    vec4 material;
    vec4 emissive;
};
#endif
#if (defined(DISSOLVE) && defined(EMISSIVE)) || (defined(CUTOUT) && ((defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE)) && defined(EMISSIVE))
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
#endif
#ifdef CUTOUT
layout(binding=0) uniform texture2D baseTexture;
#endif
#ifdef CUTOUT
layout(binding=0) uniform sampler baseSampler;
#endif
#ifdef DISSOLVE
layout(binding=2) uniform texture2D dissolveTexture;
#endif
#ifdef DISSOLVE
layout(binding=1) uniform sampler dissolveSampler;
#endif
#ifdef NORMAL_MAP
in vec4 worldTangent;
#endif
in vec3 worldPosition;
in vec3 worldNormal;
in vec2 surfaceUv;
in vec4 baseColor;
#ifdef DISSOLVE
vec4 dissolveOf() {
#ifdef EMISSIVE
    return dissolve;
#else
    return dissolve;
#endif
}
#endif
#ifdef CUTOUT
vec4 materialOf() {
#if (defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE)
#ifdef EMISSIVE
    return material;
#else
    return material;
#endif
#else
#ifdef EMISSIVE
    return material;
#else
    return material;
#endif
#endif
}
#endif
void main() {
#ifdef DISSOLVE
    float noise = texture(sampler2D(dissolveTexture, dissolveSampler), surfaceUv).x;
    if (noise < dissolveOf().x) {
        discard;
    }
#endif
#ifdef CUTOUT
    vec4 texel = texture(sampler2D(baseTexture, baseSampler), surfaceUv);
    if ((baseColor.a * texel.a) < materialOf().w) {
        discard;
    }
#endif
}
@end

@vs unlitTexturedVs
layout(binding=0) uniform vertexParams {
    mat4 viewProj;
    vec4 cameraRight;
    vec4 cameraUp;
};
#ifdef NORMAL_MRT
layout(binding=4) uniform modelParams {
    mat4 model;
    mat4 normalModel;
};
#endif
#ifndef NORMAL_MRT
layout(binding=4) uniform modelTransformParams {
    mat4 model;
};
#endif
in vec3 position;
in vec3 normal;
in vec2 uv;
in vec4 color;
#ifdef NORMAL_MAP
in vec4 tangent;
#endif
#ifdef NORMAL_MRT
out vec3 worldNormal;
#endif
out vec2 surfaceUv;
out vec4 baseColor;
mat4 unlitModel() {
#ifdef NORMAL_MRT
    return model;
#else
    return model;
#endif
}
void main() {
    gl_Position = ((viewProj * unlitModel()) * vec4(position, 1.0));
#ifdef NORMAL_MRT
    worldNormal = (mat3(normalModel) * normal);
#endif
    surfaceUv = uv;
    baseColor = color;
    return;
}
@end

@fs unlitTexturedFs
#if (!((defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE)))
layout(binding=3) uniform unlitMaterialParams {
    vec4 material;
    vec4 materialColor;
};
#endif
#if (((defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE))) || defined(UV_TRANSFORM) || defined(BACK_TEXTURE) || defined(DISSOLVE)
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
#endif
layout(binding=6) uniform frameParams {
    vec4 frame;
};
layout(binding=0) uniform texture2D baseTexture;
layout(binding=0) uniform sampler baseSampler;
#ifdef BACK_TEXTURE
layout(binding=1) uniform texture2D backTexture;
#endif
#ifdef DISSOLVE
layout(binding=2) uniform texture2D dissolveTexture;
#endif
#ifdef DISSOLVE
layout(binding=1) uniform sampler dissolveSampler;
#endif
#ifdef NORMAL_MRT
in vec3 worldNormal;
#endif
in vec2 surfaceUv;
in vec4 baseColor;
layout(location=0) out vec4 color;
#ifdef NORMAL_MRT
layout(location=1) out vec4 normal;
#endif
vec4 materialOf() {
#if (defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE)
    return material;
#else
    return material;
#endif
}
#ifdef UV_TRANSFORM
vec2 movedUv(vec2 uv, vec4 matrix, vec4 motion, float time) {
    return ((mat2(matrix.xy, matrix.zw) * uv) + motion.xy) + (motion.zw * time);
}
#endif
#ifdef BACK_TEXTURE
vec2 backUv(vec2 uv, vec4 matrix, vec4 offset) {
    return (mat2(matrix.xy, matrix.zw) * uv) + offset.xy;
}
#endif
#ifdef PREMULTIPLIED
vec4 straightTexel(vec4 texel) {
    return (texel.a > 0.0) ? vec4((texel.rgb / texel.a), texel.a) : vec4(0.0);
}
#endif
vec3 srgbToLinear(vec3 srgb) {
    vec3 low = srgb * 0.0773993808;
    vec3 high = pow(max(((srgb * 0.9478672986) + vec3(0.0521327014)), vec3(0.0)), vec3(2.4));
    return vec3(((srgb.x <= 0.04045) ? low.x : high.x), ((srgb.y <= 0.04045) ? low.y : high.y), ((srgb.z <= 0.04045) ? low.z : high.z));
}
vec3 linearToSrgb(vec3 rgb) {
    vec3 low = rgb * 12.92;
    vec3 high = (vec3(1.055) * pow(max(rgb, vec3(0.0)), vec3(0.41666))) - vec3(0.055);
    return vec3(((rgb.x <= 0.0031308) ? low.x : high.x), ((rgb.y <= 0.0031308) ? low.y : high.y), ((rgb.z <= 0.0031308) ? low.z : high.z));
}
vec4 unlitShade(vec4 texel, vec4 baseColor_1, vec4 materialColor_1) {
    vec3 surface = srgbToLinear(baseColor_1.rgb) * srgbToLinear(materialColor_1.rgb);
    surface = surface * srgbToLinear(texel.rgb);
    return vec4(linearToSrgb(surface), ((baseColor_1.a * materialColor_1.a) * texel.a));
}
vec4 materialColorOf() {
#if (defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE)
    return materialColor;
#else
    return materialColor;
#endif
}
#ifdef DISSOLVE
vec4 dissolveEdgeOver(vec4 color_1, float noise, vec4 dissolve_1, vec4 edge) {
    bool onEdge = (dissolve_1.x > 0.0) && (noise < (dissolve_1.x + dissolve_1.y));
    return onEdge ? vec4(mix(color_1.rgb, edge.rgb, edge.a), color_1.a) : color_1;
}
#endif
vec3 toneCurved(vec3 exposed, float mode) {
    if (mode == 1.0) {
        return exposed / (exposed + vec3(1.0));
    }
    if (mode == 2.0) {
        vec3 a = exposed * ((2.51 * exposed) + 0.03);
        vec3 b = (exposed * ((2.43 * exposed) + 0.59)) + 0.14;
        return clamp((a / b), vec3(0.0), vec3(1.0));
    }
    if (mode == 3.0) {
        float startCompression = 0.76;
        float desaturation = 0.15;
        float x = min(exposed.x, min(exposed.y, exposed.z));
        float offset = (x < 0.08) ? (x - ((6.25 * x) * x)) : 0.04;
        vec3 color_1 = exposed - offset;
        float peak = max(color_1.x, max(color_1.y, color_1.z));
        if (peak >= startCompression) {
            float d = 1.0 - startCompression;
            float newPeak = 1.0 - ((d * d) / ((peak + d) - startCompression));
            color_1 = color_1 * (newPeak / peak);
            float g = 1.0 - (1.0 / ((desaturation * (peak - newPeak)) + 1.0));
            color_1 = mix(color_1, vec3(newPeak), g);
        }
        return color_1;
    }
    return clamp(exposed, vec3(0.0), vec3(1.0));
}
vec3 toneMapped(vec3 rgb, vec4 tone) {
    if (tone.z == 1.0) {
        return srgbToLinear(rgb);
    }
    if ((tone.y == 1.0) && (tone.w == 0.0)) {
        return rgb;
    }
    return linearToSrgb(toneCurved((srgbToLinear(rgb) * tone.y), tone.w));
}
#ifdef NORMAL_MRT
vec3 facingNormal(vec3 normal_1, float doubleSided, bool frontFacing) {
    return ((doubleSided > 0.5) && (!frontFacing)) ? (-normal_1) : normal_1;
}
#endif
#ifdef NORMAL_MRT
vec3 unlitNormal(vec4 params) {
    return facingNormal(normalize(worldNormal), params.z, gl_FrontFacing);
}
#endif
void main() {
    vec4 params = materialOf();
    vec2 uv = surfaceUv;
#ifdef UV_TRANSFORM
    vec4 matrix = uvMatrix;
    vec4 motion = uvMotion;
    uv = movedUv(surfaceUv, matrix, motion, frame.x);
#endif
    vec4 texel = texture(sampler2D(baseTexture, baseSampler), uv);
#ifdef BACK_TEXTURE
    vec4 backMatrix = backUvMatrix;
    vec4 backOffset = backUvOffset;
    vec2 backAt = backUv(surfaceUv, backMatrix, backOffset);
    vec4 backTexel = texture(sampler2D(backTexture, baseSampler), backAt);
    texel = gl_FrontFacing ? texel : backTexel;
#endif
    float noise = 0.0;
#ifdef DISSOLVE
    noise = texture(sampler2D(dissolveTexture, dissolveSampler), surfaceUv).x;
    if (noise < dissolve.x) {
        discard;
    }
#endif
#ifdef PREMULTIPLIED
    texel = straightTexel(texel);
#endif
    vec4 shaded = unlitShade(texel, baseColor, materialColorOf());
#ifdef DISSOLVE
    vec4 edge = dissolveEdge;
    shaded = dissolveEdgeOver(shaded, noise, dissolve, edge);
#endif
#ifdef CUTOUT
    if (shaded.a < params.w) {
        discard;
    }
#endif
    vec4 color_1 = vec4(toneMapped(shaded.rgb, frame), shaded.a);
#ifdef PREMULTIPLIED
    color_1 = vec4((color_1.rgb * color_1.a), color_1.a);
#endif
    color = color_1;
#ifdef NORMAL_MRT
    normal = vec4(((unlitNormal(params) * 0.5) + 0.5), 1.0);
#endif
    return;
}
@end

@fs shadowUnlitTexturedFs
#if defined(CUTOUT) && (!((defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE)))
layout(binding=3) uniform unlitMaterialParams {
    vec4 material;
    vec4 materialColor;
};
#endif
#if defined(DISSOLVE) || (defined(CUTOUT) && ((defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE)))
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
#endif
#ifdef CUTOUT
layout(binding=0) uniform texture2D baseTexture;
#endif
#ifdef CUTOUT
layout(binding=0) uniform sampler baseSampler;
#endif
#ifdef DISSOLVE
layout(binding=2) uniform texture2D dissolveTexture;
#endif
#ifdef DISSOLVE
layout(binding=1) uniform sampler dissolveSampler;
#endif
#ifdef NORMAL_MRT
in vec3 worldNormal;
#endif
in vec2 surfaceUv;
in vec4 baseColor;
#ifdef CUTOUT
vec4 materialColorOf() {
#if (defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE)
    return materialColor;
#else
    return materialColor;
#endif
}
#endif
#ifdef CUTOUT
vec4 materialOf() {
#if (defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE)
    return material;
#else
    return material;
#endif
}
#endif
void main() {
#ifdef DISSOLVE
    float noise = texture(sampler2D(dissolveTexture, dissolveSampler), surfaceUv).x;
    if (noise < dissolve.x) {
        discard;
    }
#endif
#ifdef CUTOUT
    vec4 texel = texture(sampler2D(baseTexture, baseSampler), surfaceUv);
    vec4 tint = materialColorOf();
    if (((baseColor.a * tint.a) * texel.a) < materialOf().w) {
        discard;
    }
#endif
}
@end

