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
layout(binding=3) uniform materialParams {
    vec4 material;
};
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
vec3 facingNormal(vec3 normal_1, float doubleSided) {
    return ((doubleSided > 0.5) && (!gl_FrontFacing)) ? (-normal_1) : normal_1;
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
vec3 pointLightAt(int i, vec3 position, vec3 normal_1) {
    vec4 at = pointLight[i];
    vec4 tint = pointColor[i];
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
vec4 litShade(vec3 n) {
    vec4 dir = dirLight;
    float lambert = max(dot(n, dir.xyz), 0.0) * dir.w;
#ifdef SHADOWED
    lambert = lambert * dirShadowAt(worldPosition);
#endif
    vec3 ambient_1 = srgbToLinear(ambient.rgb);
    vec3 light = ambient_1 + (srgbToLinear(dirColor.rgb) * lambert);
    for (int i = 0; i < int(ambient.a + 0.5); i++) {
        light = light + pointLightAt(i, worldPosition, n);
    }
    vec3 surface = srgbToLinear(saturated(baseColor.rgb, material.y));
    return vec4(linearToSrgb((surface * light)), baseColor.a);
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
vec3 toneMapped(vec3 rgb) {
    vec4 tone = frame;
    if (tone.z == 1.0) {
        return srgbToLinear(rgb);
    }
    if ((tone.y == 1.0) && (tone.w == 0.0)) {
        return rgb;
    }
    return linearToSrgb(toneCurved((srgbToLinear(rgb) * tone.y), tone.w));
}
void main() {
    vec4 params = material;
    vec3 n = facingNormal(normalize(worldNormal), params.z);
    vec4 shaded = litShade(n);
#ifdef CUTOUT
    if (shaded.a < params.w) {
        discard;
    }
#endif
    color = vec4(toneMapped(shaded.rgb), shaded.a);
#ifdef NORMAL_MRT
    normal = vec4(((n * 0.5) + 0.5), 1.0);
#endif
    return;
}
@end

@fs shadowLitFs
#ifdef CUTOUT
layout(binding=3) uniform materialParams {
    vec4 material;
};
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

