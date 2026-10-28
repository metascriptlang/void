@vs fullscreenVs
in vec2 position;
void main() {
    gl_Position = vec4(position, 0.5, 1.0);
    return;
}
@end

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

@fs toneMapFs
layout(binding=0) uniform texture2D hdrTexture;
layout(binding=0) uniform sampler pointSampler;
layout(binding=0) uniform toneMapParams {
    vec4 toneMap;
};
layout(location=0) out vec4 fragColor;
vec3 linearToSrgb(vec3 rgb) {
    vec3 low = rgb * 12.92;
    vec3 high = (vec3(1.055) * pow(max(rgb, vec3(0.0)), vec3(0.41666))) - vec3(0.055);
    return vec3(((rgb.x <= 0.0031308) ? low.x : high.x), ((rgb.y <= 0.0031308) ? low.y : high.y), ((rgb.z <= 0.0031308) ? low.z : high.z));
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
        vec3 color = exposed - offset;
        float peak = max(color.x, max(color.y, color.z));
        if (peak >= startCompression) {
            float d = 1.0 - startCompression;
            float newPeak = 1.0 - ((d * d) / ((peak + d) - startCompression));
            color = color * (newPeak / peak);
            float g = 1.0 - (1.0 / ((desaturation * (peak - newPeak)) + 1.0));
            color = mix(color, vec3(newPeak), g);
        }
        return color;
    }
    return clamp(exposed, vec3(0.0), vec3(1.0));
}
void main() {
    ivec2 size = textureSize(sampler2D(hdrTexture, pointSampler), 0);
    ivec2 p = clamp(ivec2(gl_FragCoord.xy), ivec2(0, 0), (size - ivec2(1, 1)));
    vec4 texel = texelFetch(sampler2D(hdrTexture, pointSampler), p, 0);
    float alpha = clamp(texel.w, 0.0, 1.0);
    if (alpha <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }
    vec3 straight = texel.xyz / alpha;
    vec4 tone = toneMap;
    fragColor = vec4((linearToSrgb(toneCurved((straight * tone.x), tone.y)) * alpha), alpha);
    return;
}
@end

@fs bloomDownsampleFirstFs
layout(binding=0) uniform texture2D bloomSource;
layout(binding=0) uniform sampler bloomSampler;
layout(binding=0) uniform bloomParams {
    vec4 bloomTexel;
    vec4 bloomBlend;
    vec4 bloomThreshold;
};
layout(location=0) out vec4 fragColor;
vec3 bloomTap(vec2 uv, vec2 offset) {
    vec2 at = uv + (offset * bloomTexel.xy);
    return texture(sampler2D(bloomSource, bloomSampler), at).xyz;
}
float bloomKaris(vec3 color) {
    float luma = dot(color, vec3(0.2126, 0.7152, 0.0722)) / 4.0;
    return 1.0 / (1.0 + luma);
}
vec3 bloom13(vec2 uv, bool karis) {
    vec3 a = bloomTap(uv, vec2(-2.0, 2.0));
    vec3 bb = bloomTap(uv, vec2(0.0, 2.0));
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
        vec3 group0 = (((a + bb) + d) + e) * (0.125 / 4.0);
        vec3 group1 = (((bb + c) + e) + f) * (0.125 / 4.0);
        vec3 group2 = (((d + e) + g) + h) * (0.125 / 4.0);
        vec3 group3 = (((e + f) + h) + i) * (0.125 / 4.0);
        vec3 group4 = (((j + k) + l) + m) * (0.5 / 4.0);
        group0 = group0 * bloomKaris(group0);
        group1 = group1 * bloomKaris(group1);
        group2 = group2 * bloomKaris(group2);
        group3 = group3 * bloomKaris(group3);
        group4 = group4 * bloomKaris(group4);
        return (((group0 + group1) + group2) + group3) + group4;
    }
    vec3 sum = (((a + c) + g) + i) * 0.03125;
    sum = sum + ((((bb + d) + f) + h) * 0.0625);
    sum = sum + (((((e + j) + k) + l) + m) * 0.125);
    return sum;
}
vec3 softThreshold(vec3 color) {
    vec4 threshold = bloomThreshold;
    float brightness = max(color.x, max(color.y, color.z));
    float softness = clamp((brightness - threshold.y), 0.0, threshold.z);
    softness = (softness * softness) * threshold.w;
    float contribution = max((brightness - threshold.x), softness);
    return color * (contribution / max(brightness, 0.00001));
}
void main() {
    vec2 uv = gl_FragCoord.xy * bloomTexel.zw;
    vec3 sum = clamp(bloom13(uv, true), vec3(0.0001), vec3(3.40282347e+37));
    if (bloomThreshold.x > 0.0) {
        sum = softThreshold(sum);
    }
    fragColor = vec4(sum, 1.0);
    return;
}
@end

@fs bloomDownsampleFs
layout(binding=0) uniform texture2D bloomSource;
layout(binding=0) uniform sampler bloomSampler;
layout(binding=0) uniform bloomParams {
    vec4 bloomTexel;
    vec4 bloomBlend;
    vec4 bloomThreshold;
};
layout(location=0) out vec4 fragColor;
vec3 bloomTap(vec2 uv, vec2 offset) {
    vec2 at = uv + (offset * bloomTexel.xy);
    return texture(sampler2D(bloomSource, bloomSampler), at).xyz;
}
float bloomKaris(vec3 color) {
    float luma = dot(color, vec3(0.2126, 0.7152, 0.0722)) / 4.0;
    return 1.0 / (1.0 + luma);
}
vec3 bloom13(vec2 uv, bool karis) {
    vec3 a = bloomTap(uv, vec2(-2.0, 2.0));
    vec3 bb = bloomTap(uv, vec2(0.0, 2.0));
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
        vec3 group0 = (((a + bb) + d) + e) * (0.125 / 4.0);
        vec3 group1 = (((bb + c) + e) + f) * (0.125 / 4.0);
        vec3 group2 = (((d + e) + g) + h) * (0.125 / 4.0);
        vec3 group3 = (((e + f) + h) + i) * (0.125 / 4.0);
        vec3 group4 = (((j + k) + l) + m) * (0.5 / 4.0);
        group0 = group0 * bloomKaris(group0);
        group1 = group1 * bloomKaris(group1);
        group2 = group2 * bloomKaris(group2);
        group3 = group3 * bloomKaris(group3);
        group4 = group4 * bloomKaris(group4);
        return (((group0 + group1) + group2) + group3) + group4;
    }
    vec3 sum = (((a + c) + g) + i) * 0.03125;
    sum = sum + ((((bb + d) + f) + h) * 0.0625);
    sum = sum + (((((e + j) + k) + l) + m) * 0.125);
    return sum;
}
void main() {
    fragColor = vec4(bloom13((gl_FragCoord.xy * bloomTexel.zw), false), 1.0);
    return;
}
@end

@fs bloomUpsampleFs
layout(binding=0) uniform texture2D bloomSource;
layout(binding=0) uniform sampler bloomSampler;
layout(binding=0) uniform bloomParams {
    vec4 bloomTexel;
    vec4 bloomBlend;
    vec4 bloomThreshold;
};
layout(location=0) out vec4 fragColor;
vec3 bloomTap(vec2 uv, vec2 offset) {
    vec2 at = uv + (offset * bloomTexel.xy);
    return texture(sampler2D(bloomSource, bloomSampler), at).xyz;
}
void main() {
    vec2 uv = gl_FragCoord.xy * bloomTexel.zw;
    vec3 sum = bloomTap(uv, vec2(0.0, 0.0)) * 0.25;
    sum = sum + ((((bloomTap(uv, vec2(0.0, 1.0)) + bloomTap(uv, vec2(-1.0, 0.0))) + bloomTap(uv, vec2(1.0, 0.0))) + bloomTap(uv, vec2(0.0, -1.0))) * 0.125);
    sum = sum + ((((bloomTap(uv, vec2(-1.0, 1.0)) + bloomTap(uv, vec2(1.0, 1.0))) + bloomTap(uv, vec2(-1.0, -1.0))) + bloomTap(uv, vec2(1.0, -1.0))) * 0.0625);
    float factor = bloomBlend.x;
    fragColor = vec4((sum * factor), factor);
    return;
}
@end

@fs outlineMaskFs
layout(binding=0) uniform texture2D outlineNormal;
@image_sample_type outlineDepth unfilterable_float
layout(binding=1) uniform texture2D outlineDepth;
layout(binding=0) uniform sampler outlinePointSampler;
@sampler_type outlineDepthSampler nonfiltering
layout(binding=1) uniform sampler outlineDepthSampler;
layout(binding=0) uniform outlineMaskParams {
    vec4 outlineEdge;
    vec4 outlineDepthMap;
};
layout(location=0) out vec4 fragColor;
vec4 outlineNormalAt(ivec2 p) {
    return texelFetch(sampler2D(outlineNormal, outlinePointSampler), p, 0);
}
ivec2 outlinePixel(ivec2 p, ivec2 size) {
    return clamp(p, ivec2(0, 0), (size - ivec2(1, 1)));
}
float outlineDepthAt(ivec2 p, ivec2 size) {
    return (texelFetch(sampler2D(outlineDepth, outlineDepthSampler), outlinePixel(p, size), 0).x * outlineEdge.w) + outlineDepthMap.x;
}
const ivec2[4] OUTLINE_OFFSETS = ivec2[4](ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1));
void main() {
    vec4 edge = outlineEdge;
    ivec2 size = textureSize(sampler2D(outlineNormal, outlinePointSampler), 0);
    ivec2 p = ivec2(gl_FragCoord.xy);
    vec4 center = outlineNormalAt(p);
    float coverage = 0.0;
    vec3 n = (center.w > 0.5) ? normalize(((center.xyz * 2.0) - 1.0)) : vec3(0.0);
    float depth = outlineDepthAt(p, size);
    for (int i = 0; i < 4; i++) {
        ivec2 silhouette = p + ivec2(roundEven((vec2(OUTLINE_OFFSETS[i]) * edge.x)));
        float silhouetteDelta = outlineDepthAt(silhouette, size) - depth;
        vec4 silhouetteNormal = outlineNormalAt(outlinePixel(silhouette, size));
        ivec2 crease = p + ivec2(roundEven((vec2(OUTLINE_OFFSETS[i]) * max(1.0, (edge.x * 0.5)))));
        vec4 neighbor = outlineNormalAt(outlinePixel(crease, size));
        float creaseDelta = outlineDepthAt(crease, size) - depth;
        vec3 nq = (neighbor.w > 0.5) ? normalize(((neighbor.xyz * 2.0) - 1.0)) : vec3(0.0);
        bool distinctNormal = ((center.x != neighbor.x) || (center.y != neighbor.y)) || (center.z != neighbor.z);
        if ((center.w > 0.5) && (((silhouetteNormal.w < 0.5) || (silhouetteDelta > edge.y)) || ((((neighbor.w > 0.5) && (abs(creaseDelta) < edge.y)) && distinctNormal) && (dot(n, nq) < edge.z)))) {
            coverage = 1.0;
        }
    }
    fragColor = vec4(coverage);
    return;
}
@end

@fs outlineMixFs
layout(binding=0) uniform texture2D outlineLit;
layout(binding=1) uniform texture2D outlineMask;
layout(binding=0) uniform sampler outlineLitSampler;
layout(binding=1) uniform sampler outlineLinearSampler;
layout(binding=0) uniform outlineMixParams {
    vec4 outlineColor;
    vec4 outlineMix;
};
layout(location=0) out vec4 fragColor;
vec3 maskTap(vec2 uv) {
    return texture(sampler2D(outlineMask, outlineLinearSampler), uv).xyz;
}
void main() {
    ivec2 size = textureSize(sampler2D(outlineMask, outlineLinearSampler), 0);
    vec2 delta = 1.0 / vec2(size);
    vec2 tuv = gl_FragCoord.xy * delta;
    vec3 nw = maskTap((tuv + (vec2(-1.0, -1.0) * delta)));
    vec3 ne = maskTap((tuv + (vec2(1.0, -1.0) * delta)));
    vec3 sw = maskTap((tuv + (vec2(-1.0, 1.0) * delta)));
    vec3 se = maskTap((tuv + (vec2(1.0, 1.0) * delta)));
    vec3 mid = maskTap(tuv);
    vec3 lumA = vec3(0.299, 0.587, 0.114);
    float lumNW = dot(nw, lumA);
    float lumNE = dot(ne, lumA);
    float lumSW = dot(sw, lumA);
    float lumSE = dot(se, lumA);
    float lumMid = dot(mid, lumA);
    float lumMin = min(lumMid, min(min(lumNW, lumNE), min(lumSW, lumSE)));
    float lumMax = max(lumMid, max(max(lumNW, lumNE), max(lumSW, lumSE)));
    vec2 dir = vec2((-((lumNW + lumNE) - (lumSW + lumSE))), ((lumNW + lumSW) - (lumNE + lumSE)));
    float dirReduce = max(((((lumNW + lumNE) + lumSW) + lumSE) * 0.001953125), 0.125);
    float rcpDirMin = 1.0 / (min(abs(dir.x), abs(dir.y)) + dirReduce);
    dir = min(vec2(8.0), max(vec2(-8.0), (dir * rcpDirMin))) * delta;
    vec3 rgbA = (maskTap((tuv + (dir * ((1.0 / 3.0) - 0.5)))) + maskTap((tuv + (dir * ((2.0 / 3.0) - 0.5))))) * 0.5;
    vec3 rgbB = (rgbA * 0.5) + ((maskTap((tuv + (dir * -0.5))) + maskTap((tuv + (dir * 0.5)))) * 0.25);
    float lumB = dot(rgbB, lumA);
    float inRange = ((lumB > lumMin) && ((-lumB) > (-lumMax))) ? 1.0 : 0.0;
    vec3 filtered = mix(rgbA, rgbB, inRange);
    vec4 lit = texelFetch(sampler2D(outlineLit, outlineLitSampler), ivec2(gl_FragCoord.xy), 0);
    fragColor = mix(lit, (outlineColor * filtered.x), outlineMix.x);
    return;
}
@end

@fs outlineWidthFs
layout(binding=0) uniform texture2D outlineWidthMask;
layout(binding=0) uniform sampler outlineWidthSampler;
layout(binding=0) uniform outlineWidthParams {
    vec4 outlineWidth;
};
layout(location=0) out vec4 fragColor;
void main() {
    vec4 width = outlineWidth;
    vec2 delta = 1.0 / vec2(textureSize(sampler2D(outlineWidthMask, outlineWidthSampler), 0));
    vec2 uv = gl_FragCoord.xy * delta;
    float own = texture(sampler2D(outlineWidthMask, outlineWidthSampler), uv).x;
    float maximum = (width.y > 0.5) ? (1.0 - own) : own;
    float angle = 0.0;
    for (int i = 0; i < 48; i++) {
        angle += 0.1308996938995747;
        vec2 displacement = (vec2(cos(angle), sin(angle)) * width.x) * delta;
        float current = texture(sampler2D(outlineWidthMask, outlineWidthSampler), (uv + displacement)).x;
        maximum = max(maximum, ((width.y > 0.5) ? (1.0 - current) : current));
    }
    float coverage = (width.y > 0.5) ? (1.0 - maximum) : maximum;
    fragColor = vec4(coverage);
    return;
}
@end

@vs saoVs
in vec2 position;
out vec4 ndc;
void main() {
    ndc = vec4(position, 0.0, 0.0);
    gl_Position = vec4(position, 0.5, 1.0);
    return;
}
@end

@fs saoFs
@image_sample_type saoDepth unfilterable_float
layout(binding=0) uniform texture2D saoDepth;
layout(binding=1) uniform texture2D saoNormal;
layout(binding=2) uniform texture2D saoNoiseTexture;
@sampler_type saoPointSampler nonfiltering
layout(binding=0) uniform sampler saoPointSampler;
layout(binding=1) uniform sampler saoNoiseSampler;
layout(binding=0) uniform saoParams {
    mat4 saoInverseViewProj;
    vec4 saoViewDepth;
    vec4 saoRadius;
    vec4 saoTaps;
    vec4 saoNoise;
    vec4 saoEye;
    vec4 saoFade;
};
in vec4 ndc;
layout(location=0) out vec4 fragColor;
float ndcDepthOf(float stored, float zeroToOne) {
    return (zeroToOne == 1.0) ? stored : ((stored * 2.0) - 1.0);
}
vec3 saoPositionAt(ivec2 pixel, vec2 ndc_1) {
    float stored = texelFetch(sampler2D(saoDepth, saoPointSampler), pixel, 0).x;
    float depth = ndcDepthOf(stored, saoNoise.z);
    vec4 world = saoInverseViewProj * vec4(ndc_1.x, ndc_1.y, depth, 1.0);
    return world.xyz / world.w;
}
float saoScreenRadius(float sampleRadius, float fovTan, float viewDepth) {
    return (sampleRadius * fovTan) / viewDepth;
}
float saoViewDepthOf(vec3 at) {
    return dot(saoViewDepth, vec4(at, 1.0));
}
vec2 saoTapOffset(int tap, int samples, int spiralTurns, float rotation) {
    float alpha = (float(tap) + 0.5) / float(samples);
    float angle = (alpha * (float(spiralTurns) * 6.28)) + rotation;
    return vec2(cos(angle), sin(angle)) * alpha;
}
float saoScalableRadius(float sampleRadius, float viewDepth) {
    return sampleRadius * (max(0.0, log((1.0 + viewDepth))) + 1.0);
}
float saoTap(vec3 offset, vec3 normal, float radius, float bias) {
    float vv = dot(offset, offset);
    float vn = dot(offset, normal) - (bias * radius);
    float radius2 = radius * radius;
    float f = max((radius2 - vv), 0.0) / radius2;
    return ((f * f) * f) * max((vn / (0.01 + vv)), 0.0);
}
float saoFaded(float occlusion, float distance_1, float startFadeStart, float startFadeEnd, float fadeStart, float fadeEnd) {
    float started = mix(1.0, occlusion, clamp(((distance_1 - startFadeStart) / (startFadeEnd - startFadeStart)), 0.0, 1.0));
    return mix(started, 1.0, clamp(((distance_1 - fadeStart) / (fadeEnd - fadeStart)), 0.0, 1.0));
}
float saoOcclusion(float sum, int samples, float intensity) {
    return pow(clamp((1.0 - (sum / float(samples))), 0.0, 1.0), (1.0 + intensity));
}
void main() {
    ivec2 size = textureSize(sampler2D(saoDepth, saoPointSampler), 0);
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    vec2 ndc_1 = ndc.xy;
    vec2 ndcDx = dFdx(ndc_1);
    vec2 ndcDy = dFdy(ndc_1);
    vec3 origin = saoPositionAt(pixel, ndc_1);
    vec3 normal = (texelFetch(sampler2D(saoNormal, saoPointSampler), pixel, 0).xyz * 2.0) - vec3(1.0);
    float height = float(size.y);
    vec2 noiseUv = (gl_FragCoord.xy / height) * saoNoise.xy;
    float noise = texture(sampler2D(saoNoiseTexture, saoNoiseSampler), noiseUv).x;
    float rotation = 6.28318530717958 * noise;
    vec4 radius = saoRadius;
    vec4 taps = saoTaps;
    float radiusSS = (taps.z == 1.0) ? (radius.x * radius.w) : saoScreenRadius(radius.x, radius.w, saoViewDepthOf(origin));
    int samples = int(taps.x);
    int turns = int(taps.y);
    float sum = 0.0;
    for (int tap = 0; tap < samples; tap++) {
        vec2 offset = roundEven((saoTapOffset(tap, samples, turns, rotation) * (radiusSS * height)));
        ivec2 at = clamp((pixel + ivec2(offset)), ivec2(0, 0), (size - ivec2(1, 1)));
        vec3 q = saoPositionAt(at, ((ndc_1 + (ndcDx * offset.x)) + (ndcDy * offset.y)));
        float tapRadius = (taps.w == 1.0) ? saoScalableRadius(radius.x, saoViewDepthOf(q)) : radius.x;
        sum = sum + saoTap((q - origin), normal, tapRadius, radius.z);
    }
    vec4 fade = saoFade;
    float occlusion = saoFaded(saoOcclusion(sum, samples, radius.y), distance(origin, saoEye.xyz), fade.x, fade.y, fade.z, fade.w);
    fragColor = vec4(occlusion, occlusion, occlusion, 1.0);
    return;
}
@end

@fs blurFs
layout(binding=0) uniform texture2D blurSource;
layout(binding=0) uniform sampler blurSampler;
layout(binding=0) uniform blurParams {
    vec4 blurPixel;
    vec4 blurTaps[16];
};
layout(location=0) out vec4 fragColor;
void main() {
    ivec2 size = textureSize(sampler2D(blurSource, blurSampler), 0);
    vec2 uv = gl_FragCoord.xy / vec2(float(size.x), float(size.y));
    int count = int(blurPixel.z);
    vec4 color = vec4(0.0, 0.0, 0.0, 0.0);
    for (int i = 1 - count; i < count; i++) {
        vec4 tap = blurTaps[(i < 0) ? (-i) : i];
        vec2 at = uv + (blurPixel.xy * (tap.y * float(i)));
        color = color + (texture(sampler2D(blurSource, blurSampler), at) * tap.x);
    }
    fragColor = color;
    return;
}
@end

@vs particleVisualVs
layout(binding=0) uniform vertexParams {
    mat4 viewProj;
    vec4 cameraRight;
    vec4 cameraUp;
    vec4 cameraPosition;
};
in vec4 root;
in vec4 shape;
in vec4 tile;
in vec4 color;
in vec3 velocity;
in vec4 look;
in vec4 scale;
in vec3 pull;
in vec3 emitterRight;
in vec3 emitterUp;
out vec3 worldPosition;
out vec3 towardCamera;
out vec2 uv;
out vec4 instanceColor;
const vec2[6] PARTICLE_CORNERS = vec2[6](vec2(-0.5, -0.5), vec2(0.5, -0.5), vec2(0.5, 0.5), vec2(-0.5, -0.5), vec2(0.5, 0.5), vec2(-0.5, 0.5));
vec3 particleVisualPoint(vec2 corner) {
    vec4 root_1 = root;
    vec4 shape_1 = shape;
    vec3 velocity_1 = velocity;
    vec3 pos = root_1.xyz;
    vec3 eye = cameraPosition.xyz;
    vec3 camRight = cameraRight.xyz;
    vec3 camUp = cameraUp.xyz;
    vec3 camToward = cross(camRight, camUp);
    vec4 kind = look;
    vec4 scale_1 = scale;
    vec3 emitterRight_1 = emitterRight;
    vec3 emitterUp_1 = emitterUp;
    float flags = kind.w;
    bool rotateWith = flags >= 3.5;
    if (rotateWith) {
        flags = flags - 4.0;
    }
    bool freeform = flags >= 1.5;
    if (freeform) {
        flags = flags - 2.0;
    }
    bool noRoll = flags >= 0.5;
    bool stretch = kind.x == 1.0;
    float pivotX = -shape_1.y;
    float pivotY = -shape_1.z;
    float pivotZ = kind.z;
    float theta = shape_1.w;
    float c = cos(theta);
    float s = sin(theta);
    float root2 = 0.70710678;
    float w = root_1.w;
    float h = shape_1.x;
    vec4 clipCentre = viewProj * vec4(pos, 1.0);
    vec4 clipRight = viewProj * vec4((pos + camRight), 1.0);
    float viewportWidth = (2.0 * clipCentre.w) / (clipRight.x - clipCentre.x);
    float big = max(w, h);
    float fit = 1.0;
    if ((scale_1.w > 0.0) && (big > (scale_1.w * viewportWidth))) {
        fit = (scale_1.w * viewportWidth) / big;
    }
    if (((scale_1.z > 0.0) && (big > 0.0)) && (big < (scale_1.z * viewportWidth))) {
        fit = (scale_1.z * viewportWidth) / big;
    }
    float speed = length(velocity_1);
    vec3 along = velocity_1 / max(speed, 0.000001);
    vec3 toParticle = pos - eye;
    if (stretch) {
        if (freeform) {
            vec3 f = normalize(toParticle);
            vec3 right = normalize(cross(f, camUp));
            vec3 up = cross(right, f);
            float angle = theta;
            if (rotateWith && (speed > 0.000001)) {
                angle = angle + atan(dot(along, up), (-dot(along, right)));
            }
            float ca = cos(angle);
            float sa = sin(angle);
            float fw = w * fit;
            float fh = h * fit;
            vec3 o = ((((right * ca) - (up * sa)) * ((corner.x + pivotX) * fw)) + (((up * ca) + (right * sa)) * ((corner.y + pivotY) * fh))) + (f * (pivotZ * fw));
            float grow = (scale_1.x + ((speed * scale_1.y) / max(fh, 0.000001))) - 1.0;
            o = o + (along * (grow * dot(o, along)));
            return pos + o;
        }
        if (speed < 0.000001) {
            return pos;
        }
        vec3 pull_1 = ((along * (h * scale_1.x)) + (velocity_1 * scale_1.y)) - pull;
        float length3 = length(pull_1);
        vec3 axis = pull_1 / max(length3, 0.000001);
        vec3 forward = -camToward;
        vec3 across = cross(toParticle, axis);
        vec3 flat_1 = across - (forward * dot(across, forward));
        vec3 width = flat_1 / max(length(flat_1), 0.000001);
        float fw_1 = w * fit;
        vec3 head = (pos + (width * (pivotX * fw_1))) + (axis * ((2.0 * pivotY) * h));
        return (head + (width * (corner.y * fw_1))) - (axis * ((corner.x + 0.5) * length3));
    }
    w = w * fit;
    h = h * fit;
    if ((kind.x == 2.0) || (kind.x == 3.0)) {
        vec3 right_1 = vec3(1.0, 0.0, 0.0);
        vec3 up_1 = vec3(0.0, 0.0, -1.0);
        vec3 normal = vec3(0.0, 1.0, 0.0);
        if (kind.x == 3.0) {
            right_1 = normalize(vec3(camToward.z, 0.0, camRight.z));
            up_1 = vec3(0.0, 1.0, 0.0);
            normal = cross(right_1, up_1);
        }
        float x = 2.0 * corner.x;
        float y = 2.0 * corner.y;
        float ox = (((0.5 * w) * ((x * c) + (y * s))) * root2) + (((pivotX * w) * (c - s)) * root2);
        float oy = (((0.5 * h) * ((y * c) - (x * s))) * root2) + (((pivotY * h) * (c + s)) * root2);
        return ((pos + (right_1 * ox)) + (up_1 * oy)) + (normal * (pivotZ * w));
    }
    vec3 right_2 = camRight;
    vec3 up_2 = camUp;
    vec3 normal_1 = camToward;
    if ((kind.y == 0.0) && noRoll) {
        right_2 = normalize(cross((-camToward), vec3(0.0, 1.0, 0.0)));
        up_2 = cross(right_2, (-camToward));
    }
    if (kind.y == 1.0) {
        right_2 = vec3(1.0, 0.0, 0.0);
        up_2 = vec3(0.0, 1.0, 0.0);
        normal_1 = vec3(0.0, 0.0, -1.0);
    }
    if (kind.y == 2.0) {
        right_2 = emitterRight_1;
        up_2 = emitterUp_1;
        normal_1 = -cross(right_2, up_2);
    }
    if (kind.y == 3.0) {
        normal_1 = normalize(toParticle);
        right_2 = normalize(cross(normal_1, camUp));
        up_2 = cross(right_2, normal_1);
    }
    if (kind.y == 4.0) {
        normal_1 = along;
        right_2 = normalize(cross(vec3(0.0, 0.0, 1.0), normal_1));
        up_2 = cross(right_2, normal_1);
    }
    float x_1 = (corner.x + pivotX) * w;
    float y_1 = (corner.y + pivotY) * h;
    return ((pos + (((right_2 * c) - (up_2 * s)) * x_1)) + (((up_2 * c) + (right_2 * s)) * y_1)) + (normal_1 * (pivotZ * w));
}
void main() {
    vec2 corner = PARTICLE_CORNERS[uint(gl_VertexIndex) % 6];
    vec3 world = particleVisualPoint(corner);
    worldPosition = world;
    towardCamera = cross(cameraRight.xyz, cameraUp.xyz);
    uv = vec2(((corner.x > 0.0) ? tile.z : tile.x), ((corner.y > 0.0) ? tile.y : tile.w));
    instanceColor = color;
    gl_Position = (viewProj * vec4(world, 1.0));
    return;
}
@end

@vs particleVs
layout(binding=0) uniform vertexParams {
    mat4 viewProj;
    vec4 cameraRight;
    vec4 cameraUp;
    vec4 cameraPosition;
};
in vec4 root;
in vec4 color;
out vec4 particleColor;
const vec2[6] PARTICLE_CORNERS = vec2[6](vec2(-0.5, -0.5), vec2(0.5, -0.5), vec2(0.5, 0.5), vec2(-0.5, -0.5), vec2(0.5, 0.5), vec2(-0.5, 0.5));
void main() {
    vec2 corner = PARTICLE_CORNERS[uint(gl_VertexIndex) % 6];
    vec3 right = cameraRight.xyz;
    vec3 up = cameraUp.xyz;
    vec3 world = (root.xyz + (right * (corner.x * root.w))) + (up * (corner.y * root.w));
    particleColor = color;
    gl_Position = (viewProj * vec4(world, 1.0));
    return;
}
@end

@fs particleFs
layout(binding=6) uniform frameParams {
    vec4 frame;
    vec4 cameraPosition;
    vec4 envParams;
};
in vec4 particleColor;
layout(location=0) out vec4 fragColor;
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
        vec3 color = exposed - offset;
        float peak = max(color.x, max(color.y, color.z));
        if (peak >= startCompression) {
            float d = 1.0 - startCompression;
            float newPeak = 1.0 - ((d * d) / ((peak + d) - startCompression));
            color = color * (newPeak / peak);
            float g = 1.0 - (1.0 / ((desaturation * (peak - newPeak)) + 1.0));
            color = mix(color, vec3(newPeak), g);
        }
        return color;
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
    vec4 color = particleColor;
#ifdef CUTOUT
    if (color.a < 0.5) {
        discard;
    }
#endif
    fragColor = vec4(toneMapped(color.rgb, frame), color.a);
    return;
}
@end

@vs billboardVs
layout(binding=0) uniform vertexParams {
    mat4 viewProj;
    vec4 cameraRight;
    vec4 cameraUp;
    vec4 cameraPosition;
};
in vec3 position;
in vec2 size;
in vec2 anchor;
in vec4 tile;
in vec4 color;
out vec3 worldPosition;
out vec3 towardCamera;
out vec2 uv;
out vec4 instanceColor;
const vec2[6] PARTICLE_CORNERS = vec2[6](vec2(-0.5, -0.5), vec2(0.5, -0.5), vec2(0.5, 0.5), vec2(-0.5, -0.5), vec2(0.5, 0.5), vec2(-0.5, 0.5));
vec3 billboardPoint(vec3 position_1, vec2 size_1, vec2 anchor_1, vec2 corner, vec3 right, vec3 up) {
    vec2 offset = corner - anchor_1;
    return (position_1 + (right * (offset.x * size_1.x))) + (up * (offset.y * size_1.y));
}
void main() {
    vec2 corner = PARTICLE_CORNERS[uint(gl_VertexIndex) % 6];
    vec3 right = cameraRight.xyz;
    vec3 up = cameraUp.xyz;
    vec3 world = billboardPoint(position, size, anchor, corner, right, up);
    worldPosition = world;
    towardCamera = cross(right, up);
    uv = vec2(((corner.x > 0.0) ? tile.z : tile.x), ((corner.y > 0.0) ? tile.y : tile.w));
    instanceColor = color;
    gl_Position = (viewProj * vec4(world, 1.0));
    return;
}
@end

@fs billboardFs
layout(binding=2) uniform billboardParams {
    vec4 billboardColor;
    vec4 billboard;
};
layout(binding=1) uniform lightParams {
    vec4 ambient;
    vec4 dirLight;
    vec4 dirColor;
    vec4 clusterGrid;
    vec4 clusterFactors;
    vec4 clusterView;
    vec4 clusterScreen;
    vec4 cookie;
    mat4 cookieMatrix;
};
layout(binding=6) uniform frameParams {
    vec4 frame;
    vec4 cameraPosition;
    vec4 envParams;
};
layout(binding=0) uniform texture2D billboardTexture;
layout(binding=0) uniform sampler billboardSampler;
@image_sample_type lightRecords unfilterable_float
layout(binding=9) uniform texture2D lightRecords;
@image_sample_type clusterRecords uint
layout(binding=10) uniform utexture2D clusterRecords;
@image_sample_type clusterIndices uint
layout(binding=11) uniform utexture2D clusterIndices;
@sampler_type clusterSampler nonfiltering
layout(binding=5) uniform sampler clusterSampler;
in vec3 worldPosition;
in vec3 towardCamera;
in vec2 uv;
in vec4 instanceColor;
layout(location=0) out vec4 fragColor;
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
int cellOf(float position, int cells) {
    if (!(position > 0.0)) {
        return 0;
    }
    if (position >= float(cells)) {
        return cells - 1;
    }
    return int(position);
}
int clusterSliceOf(float depth, vec4 grid, vec4 factors) {
    int slices = int(grid.z + 0.5);
    if (grid.w > 0.5) {
        return cellOf(floor(((depth - factors.z) * factors.w)), slices);
    }
    return cellOf((((log(depth) * factors.z) - factors.w) + 1.0), slices);
}
int clusterAtCell(vec2 cell, float depth, vec4 grid, vec4 factors) {
    int columns = int(grid.x + 0.5);
    int x = cellOf(cell.x, columns);
    int y = cellOf(cell.y, int(grid.y + 0.5));
    return (((y * columns) + x) * int(grid.z + 0.5)) + clusterSliceOf(depth, grid, factors);
}
int clusterIndexOf(vec2 frag, float depth, vec4 grid, vec4 factors) {
    return clusterAtCell((frag * factors.xy), depth, grid, factors);
}
float clusterDepthOf(vec3 position, vec4 view) {
    return dot(position, view.xyz) + view.w;
}
int fragmentClusterOf(vec2 frag, vec3 position, vec4 grid, vec4 factors, vec4 view, vec4 screen) {
    float row = (screen.x > 0.5) ? (screen.y - frag.y) : frag.y;
    return clusterIndexOf(vec2(frag.x, row), clusterDepthOf(position, view), grid, factors);
}
const uint DATA_ROW = 256;
ivec2 dataTexelOf(int i) {
    uint at = uvec2(ivec2(i, 0)).x;
    return ivec2(uvec2((at % DATA_ROW), (at / DATA_ROW)));
}
ivec4 billboardClusterOf(vec2 frag, vec3 position) {
    int cluster = fragmentClusterOf(frag, position, clusterGrid, clusterFactors, clusterView, clusterScreen);
    return ivec4(texelFetch(usampler2D(clusterRecords, clusterSampler), dataTexelOf(cluster), 0));
}
int indexOfWord(uvec4 texel, int j) {
    ivec4 words = ivec4(texel);
    uint channel = uvec2(ivec2(j, 0)).x % 4;
    if (channel == 0) {
        return words.x;
    }
    if (channel == 1) {
        return words.y;
    }
    if (channel == 2) {
        return words.z;
    }
    return words.w;
}
ivec2 indexTexelOf(int j) {
    return dataTexelOf(ivec2(uvec2((uvec2(ivec2(j, 0)).x / 4), 0)).x);
}
int billboardLightOf(ivec4 cluster, int k) {
    int j = cluster.x + k;
    return indexOfWord(texelFetch(usampler2D(clusterIndices, clusterSampler), indexTexelOf(j), 0), j);
}
vec3 pointLightAt(vec3 position, vec3 normal, vec4 at, vec4 tint) {
    vec3 toLight = at.xyz - position;
    float distance_1 = length(toLight);
    float falloff = clamp((1.0 - (distance_1 / tint.a)), 0.0, 1.0);
    float facing = max(dot(normal, (toLight / max(distance_1, 0.0001))), 0.0);
    return srgbToLinear(tint.rgb) * (((falloff * falloff) * facing) * at.w);
}
float lightWindow(float distance_1, float range) {
    float window = clamp((1.0 - (distance_1 / range)), 0.0, 1.0);
    return window * window;
}
vec4 capsuleSample(vec3 position, vec4 at, vec4 tint, vec4 a, vec4 b) {
    vec3 start = at.xyz - (a.xyz * b.x);
    vec3 segment = a.xyz * (2.0 * b.x);
    float along = clamp((dot((position - start), segment) / dot(segment, segment)), 0.0, 1.0);
    vec3 delta = (start + (segment * along)) - position;
    float distance_1 = length(delta);
    if (distance_1 < 0.0001) {
        return vec4(0.0);
    }
    return vec4((delta / distance_1), lightWindow(distance_1, tint.a));
}
vec3 rectanglePoint(vec3 position, vec3 ray, vec4 at, vec4 a, vec4 b, vec4 c) {
    float along = dot(a.xyz, (at.xyz - position)) / dot(a.xyz, ray);
    vec3 offset = (position + (ray * along)) - at.xyz;
    return (at.xyz + (b.xyz * clamp(dot(offset, b.xyz), (-b.w), b.w))) + (c.xyz * clamp(dot(offset, c.xyz), (-c.w), c.w));
}
float rectangleAxisCone(vec3 delta, vec3 forward, vec3 excluded, float outer, float inner) {
    vec3 projectedDelta = delta - (excluded * dot(delta, excluded));
    vec3 projectedLight = (-forward) - (excluded * dot((-forward), excluded));
    float deltaLength = length(projectedDelta);
    float lightLength = length(projectedLight);
    if ((deltaLength < 0.0001) || (lightLength < 0.0001)) {
        return 0.0;
    }
    float theta = dot(projectedDelta, projectedLight) / (deltaLength * lightLength);
    return clamp(((theta - outer) / ((inner - outer) + 0.00001)), 0.0, 1.0);
}
vec4 rectangleSample(vec3 position, vec3 normal, vec4 at, vec4 tint, vec4 a, vec4 b, vec4 c, vec4 d) {
    if (abs(dot(a.xyz, normal)) < 0.000001) {
        return vec4(0.0);
    }
    vec3 delta = rectanglePoint(position, normal, at, a, b, c) - position;
    float distance_1 = length(delta);
    if (distance_1 < 0.0001) {
        return vec4(0.0);
    }
    float cone = rectangleAxisCone(delta, a.xyz, c.xyz, d.x, d.y) * rectangleAxisCone(delta, a.xyz, b.xyz, d.z, d.w);
    return vec4((delta / distance_1), (lightWindow(distance_1, tint.a) * cone));
}
vec4 spotSample(vec3 position, vec4 at, vec4 tint, vec4 a, vec4 b) {
    vec3 delta = at.xyz - position;
    float distance_1 = length(delta);
    if (distance_1 < 0.0001) {
        return vec4(0.0);
    }
    vec3 toLight = delta / distance_1;
    float cone = clamp(((dot(toLight, (-a.xyz)) - b.x) / (b.y - b.x)), 0.0, 1.0);
    return vec4(toLight, (lightWindow(distance_1, tint.a) * cone));
}
vec4 shapedSample(vec3 position, vec3 normal, vec4 at, vec4 tint, vec4 a, vec4 b, vec4 c, vec4 d) {
    if (a.w > 2.5) {
        return capsuleSample(position, at, tint, a, b);
    }
    if (a.w > 1.5) {
        return rectangleSample(position, normal, at, tint, a, b, c, d);
    }
    return spotSample(position, at, tint, a, b);
}
vec3 lightAt(vec3 position, vec3 normal, vec4 at, vec4 tint, vec4 a, vec4 b, vec4 c, vec4 d) {
    vec3 lit = vec3(0.0);
    if (a.w < 0.5) {
        lit = pointLightAt(position, normal, at, tint);
    } else {
        vec4 sample_1 = shapedSample(position, normal, at, tint, a, b, c, d);
        lit = srgbToLinear(tint.rgb) * ((sample_1.w * max(dot(normal, sample_1.xyz), 0.0)) * at.w);
    }
    return lit;
}
const int RECORD_TEXELS = 6;
ivec2 recordTexelOf(int light, int texel) {
    return dataTexelOf(((light * RECORD_TEXELS) + texel));
}
vec4 billboardTexelOf(int light, int texel) {
    return texelFetch(sampler2D(lightRecords, clusterSampler), recordTexelOf(light, texel), 0);
}
vec3 linearToSrgb(vec3 rgb) {
    vec3 low = rgb * 12.92;
    vec3 high = (vec3(1.055) * pow(max(rgb, vec3(0.0)), vec3(0.41666))) - vec3(0.055);
    return vec3(((rgb.x <= 0.0031308) ? low.x : high.x), ((rgb.y <= 0.0031308) ? low.y : high.y), ((rgb.z <= 0.0031308) ? low.z : high.z));
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
        vec3 color = exposed - offset;
        float peak = max(color.x, max(color.y, color.z));
        if (peak >= startCompression) {
            float d = 1.0 - startCompression;
            float newPeak = 1.0 - ((d * d) / ((peak + d) - startCompression));
            color = color * (newPeak / peak);
            float g = 1.0 - (1.0 / ((desaturation * (peak - newPeak)) + 1.0));
            color = mix(color, vec3(newPeak), g);
        }
        return color;
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
    vec4 texel = texture(sampler2D(billboardTexture, billboardSampler), uv);
#ifdef PREMULTIPLIED
    texel = straightTexel(texel);
#endif
    vec4 pixel = (billboardColor * texel) * instanceColor;
#ifdef CUTOUT
    if (pixel.a < 0.5) {
        discard;
    }
#endif
    if (billboard.y != 0.0) {
        vec3 n = normalize(towardCamera);
        vec4 dir = dirLight;
        float lambert = max(dot(n, dir.xyz), 0.0) * dir.w;
        vec3 light = srgbToLinear(ambient.rgb) + (srgbToLinear(dirColor.rgb) * lambert);
        ivec4 cluster = billboardClusterOf(gl_FragCoord.xy, worldPosition);
        for (int k = 0; k < (cluster.y + cluster.z); k++) {
            int i = billboardLightOf(cluster, k);
            light = light + lightAt(worldPosition, n, billboardTexelOf(i, 0), billboardTexelOf(i, 1), billboardTexelOf(i, 2), billboardTexelOf(i, 3), billboardTexelOf(i, 4), billboardTexelOf(i, 5));
        }
        pixel = vec4(linearToSrgb((srgbToLinear(pixel.rgb) * light)), pixel.a);
    }
    pixel = vec4(toneMapped(pixel.rgb, frame), pixel.a);
#ifdef PREMULTIPLIED
    pixel = vec4((pixel.rgb * pixel.a), pixel.a);
#endif
    fragColor = pixel;
    return;
}
@end

@vs litVs
layout(binding=0) uniform vertexParams {
    mat4 viewProj;
    vec4 cameraRight;
    vec4 cameraUp;
    vec4 cameraPosition;
};
#ifdef SKINNED
layout(binding=7) uniform skinParams {
    vec4 skinRows[192];
};
#endif
in vec3 position;
in vec3 normal;
in vec4 color;
#ifdef SKINNED
in vec4 skinJoints;
#endif
#ifdef SKINNED
in vec4 skinWeights;
#endif
in vec4 instanceRow0;
in vec4 instanceRow1;
in vec4 instanceRow2;
in vec4 instanceColor;
out vec3 worldPosition;
out vec3 worldNormal;
out vec4 baseColor;
#ifdef SKINNED
vec4 skinRow(vec4 joints, vec4 weights, int column) {
    return (((skinRows[(int(joints.x) * 3) + column] * weights.x) + (skinRows[(int(joints.y) * 3) + column] * weights.y)) + (skinRows[(int(joints.z) * 3) + column] * weights.z)) + (skinRows[(int(joints.w) * 3) + column] * weights.w);
}
#endif
#ifdef SKINNED
mat4 skinWorld(vec4 joints, vec4 weights) {
    return transpose(mat4(skinRow(joints, weights, 0), skinRow(joints, weights, 1), skinRow(joints, weights, 2), vec4(0.0, 0.0, 0.0, 1.0)));
}
#endif
vec3 skinNormal(mat4 world, vec3 normal_1) {
    mat3 linear = mat3(world);
    vec3 a = cross(linear[1], linear[2]);
    vec3 b = cross(linear[2], linear[0]);
    vec3 c = cross(linear[0], linear[1]);
    float direction = (dot(linear[0], a) < 0.0) ? -1.0 : 1.0;
    return (((a * normal_1.x) + (b * normal_1.y)) + (c * normal_1.z)) * direction;
}
#ifndef SKINNED
mat4 instanceWorld(vec4 row0, vec4 row1, vec4 row2) {
    return transpose(mat4(row0, row1, row2, vec4(0.0, 0.0, 0.0, 1.0)));
}
#endif
void main() {
#ifdef SKINNED
    mat4 matrix = skinWorld(skinJoints, skinWeights);
    vec4 world = matrix * vec4(position, 1.0);
    worldPosition = world.xyz;
    worldNormal = skinNormal(matrix, normal);
    baseColor = color;
    gl_Position = (viewProj * world);
    return;
#else
    mat4 matrix_1 = instanceWorld(instanceRow0, instanceRow1, instanceRow2);
    vec4 world_1 = matrix_1 * vec4(position, 1.0);
    worldPosition = world_1.xyz;
    worldNormal = skinNormal(matrix_1, normal);
    baseColor = (color * instanceColor);
    gl_Position = (viewProj * world_1);
    return;
#endif
}
@end

@fs litFs
#if !defined(PBR) && !((defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE)) && !defined(EMISSIVE)
layout(binding=3) uniform materialParams {
    vec4 material;
    vec4 materialColor;
};
#endif
#if !defined(PBR) && ((defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE)) && !defined(EMISSIVE)
layout(binding=3) uniform movingMaterialParams {
    vec4 material;
    vec4 materialColor;
    vec4 uvMatrix;
    vec4 uvMotion;
    vec4 backUvMatrix;
    vec4 backUvOffset;
    vec4 dissolve;
    vec4 dissolveEdge;
    vec4 flipbookGrid;
    vec4 flipbookPlay;
};
#endif
#if !defined(PBR) && !((defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE)) && defined(EMISSIVE)
layout(binding=3) uniform emissiveMaterialParams {
    vec4 material;
    vec4 materialColor;
    vec4 emissive;
};
#endif
#if !defined(PBR) && ((defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE)) && defined(EMISSIVE)
layout(binding=3) uniform movingEmissiveMaterialParams {
    vec4 material;
    vec4 materialColor;
    vec4 uvMatrix;
    vec4 uvMotion;
    vec4 backUvMatrix;
    vec4 backUvOffset;
    vec4 dissolve;
    vec4 dissolveEdge;
    vec4 flipbookGrid;
    vec4 flipbookPlay;
    vec4 emissive;
};
#endif
#if defined(PBR) && !defined(EMISSIVE)
layout(binding=3) uniform pbrMaterialParams {
    vec4 material;
    vec4 materialColor;
    vec4 pbr;
    vec4 uvMatrix;
    vec4 uvMotion;
    vec4 parallax;
};
#endif
#if defined(PBR) && defined(EMISSIVE)
layout(binding=3) uniform pbrEmissiveMaterialParams {
    vec4 material;
    vec4 materialColor;
    vec4 pbr;
    vec4 uvMatrix;
    vec4 uvMotion;
    vec4 parallax;
    vec4 emissive;
};
#endif
layout(binding=1) uniform lightParams {
    vec4 ambient;
    vec4 dirLight;
    vec4 dirColor;
    vec4 clusterGrid;
    vec4 clusterFactors;
    vec4 clusterView;
    vec4 clusterScreen;
    vec4 cookie;
    mat4 cookieMatrix;
};
layout(binding=6) uniform frameParams {
    vec4 frame;
    vec4 cameraPosition;
    vec4 envParams;
};
#ifdef SHADOWED
layout(binding=5) uniform shadowParams {
    mat4 cascadeMatrices[4];
    vec4 cascadeFar;
    vec4 cascadeInfo;
    vec4 cascadeView;
    vec4 cascadeFilter;
    mat4 spotMatrix;
    vec4 spotShadow;
    vec4 spotReceiver;
    mat4 cubeMatrices[6];
    vec4 cubeShadow;
    vec4 cubeLight;
    vec4 cubeRange;
};
#endif
#ifdef SHADOWED
@image_sample_type shadowMap unfilterable_float
layout(binding=4) uniform texture2DArray shadowMap;
#endif
#ifdef SHADOWED
@sampler_type shadowSampler nonfiltering
layout(binding=2) uniform sampler shadowSampler;
#endif
#ifdef SHADOWED
@image_sample_type spotShadowMap unfilterable_float
layout(binding=6) uniform texture2DArray spotShadowMap;
#endif
#ifdef SHADOWED
@sampler_type spotShadowSampler nonfiltering
layout(binding=3) uniform sampler spotShadowSampler;
#endif
#ifdef SHADOWED
@image_sample_type cubeShadowMap unfilterable_float
layout(binding=12) uniform texture2DArray cubeShadowMap;
#endif
layout(binding=13) uniform texture2D cookieTexture;
layout(binding=6) uniform sampler cookieSampler;
#ifdef PBR
layout(binding=7) uniform textureCube envDiffuse;
#endif
#ifdef PBR
layout(binding=8) uniform textureCube envSpecular;
#endif
#ifdef PBR
layout(binding=4) uniform sampler envSampler;
#endif
@image_sample_type lightRecords unfilterable_float
layout(binding=9) uniform texture2D lightRecords;
@image_sample_type clusterRecords uint
layout(binding=10) uniform utexture2D clusterRecords;
@image_sample_type clusterIndices uint
layout(binding=11) uniform utexture2D clusterIndices;
@sampler_type clusterSampler nonfiltering
layout(binding=5) uniform sampler clusterSampler;
in vec3 worldPosition;
in vec3 worldNormal;
in vec4 baseColor;
layout(location=0) out vec4 color;
#ifdef NORMAL_MRT
layout(location=1) out vec4 normal;
#endif
vec4 materialOf() {
#ifdef PBR
#ifdef EMISSIVE
    return material;
#else
    return material;
#endif
#else
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
#endif
}
vec3 facingNormal(vec3 normal_1, float doubleSided, bool frontFacing) {
    return ((doubleSided > 0.5) && (!frontFacing)) ? (-normal_1) : normal_1;
}
vec4 materialColorOf() {
#ifdef PBR
#ifdef EMISSIVE
    return materialColor;
#else
    return materialColor;
#endif
#else
#if (defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE)
#ifdef EMISSIVE
    return materialColor;
#else
    return materialColor;
#endif
#else
#ifdef EMISSIVE
    return materialColor;
#else
    return materialColor;
#endif
#endif
#endif
}
vec4 tintedSurface(vec4 color_1) {
    return color_1 * materialColorOf();
}
#ifdef PBR
vec4 pbrOf() {
#ifdef EMISSIVE
    return pbr;
#else
    return pbr;
#endif
}
#endif
vec3 srgbToLinear(vec3 srgb) {
    vec3 low = srgb * 0.0773993808;
    vec3 high = pow(max(((srgb * 0.9478672986) + vec3(0.0521327014)), vec3(0.0)), vec3(2.4));
    return vec3(((srgb.x <= 0.04045) ? low.x : high.x), ((srgb.y <= 0.04045) ? low.y : high.y), ((srgb.z <= 0.04045) ? low.z : high.z));
}
vec3 saturated(vec3 rgb, float amount) {
    if (amount == 0.0) {
        return rgb;
    }
    float luma = dot(rgb, vec3(0.212671, 0.71516, 0.072169));
    float keep = amount + 1.0;
    return (rgb * keep) + vec3((luma * (1.0 - keep)));
}
#ifdef SHADOWED
float cascadeDepthOf(vec3 position, vec3 eye, vec4 view) {
    return dot((position - eye), view.xyz);
}
#endif
#ifdef SHADOWED
int cascadeCountOf(vec4 info) {
    return int(info.x + 0.5);
}
#endif
#ifdef SHADOWED
float farOf(vec4 far, int cascade) {
    if (cascade == 0) {
        return far.x;
    }
    if (cascade == 1) {
        return far.y;
    }
    if (cascade == 2) {
        return far.z;
    }
    return far.w;
}
#endif
#ifdef SHADOWED
int cascadeIndexOf(float depth, vec4 far, vec4 info) {
    int count = cascadeCountOf(info);
    for (int i = 0; i < count; i++) {
        if (depth < farOf(far, i)) {
            return i;
        }
    }
    return count;
}
#endif
#ifdef SHADOWED
vec3 cascadeReceiverOf(vec3 position, vec3 normal_1, mat4 matrix, vec4 view, float normalBias) {
    vec3 at = position;
    if (normalBias > 0.0) {
        vec3 across = vec3((matrix * vec4(1.0, 0.0, 0.0, 0.0)).x, (matrix * vec4(0.0, 1.0, 0.0, 0.0)).x, (matrix * vec4(0.0, 0.0, 1.0, 0.0)).x);
        at = position + (normal_1 * (normalBias / (length(across) * view.w)));
    }
    return at;
}
#endif
#ifdef SHADOWED
vec4 mapCoord(vec3 position, mat4 matrix) {
    vec4 q = matrix * vec4(position, 1.0);
    if (q.w <= 0.0) {
        return vec4(0.0, 0.0, 0.0, 0.0);
    }
    vec3 p = q.xyz / q.w;
    if ((((p.x <= 0.0) || (p.x >= 1.0)) || (p.y <= 0.0)) || (p.y >= 1.0)) {
        return vec4(0.0, 0.0, 0.0, 0.0);
    }
    return vec4(p, 1.0);
}
#endif
#ifdef SHADOWED
vec4 cascadeTexelOf(vec3 position, mat4 matrix, vec4 view) {
    vec4 at = mapCoord(position, matrix);
    if (at.w < 0.5) {
        return vec4(0.0, 0.0, 0.0, 0.0);
    }
    int size = int(view.w + 0.5);
    ivec2 texel = clamp(ivec2((at.xy * vec2(float(size)))), ivec2(0, 0), ivec2((size - 1), (size - 1)));
    return vec4(float(texel.x), float(texel.y), at.z, 1.0);
}
#endif
#ifdef SHADOWED
float mapLit(float z, float depth, float bias, float opacity) {
    float lit = ((clamp(z, 0.0, 1.0) - bias) > depth) ? 0.0 : 1.0;
    return mix(1.0, lit, opacity);
}
#endif
#ifdef SHADOWED
float cascadeLitOf(vec4 texel, float stored, vec4 info) {
    if (texel.w < 0.5) {
        return 1.0;
    }
    return mapLit(texel.z, stored, info.z, info.w);
}
#endif
#ifdef SHADOWED
vec2 poissonRotation(vec3 position) {
    float dp = dot(vec4(((position.x + position.y) + position.z)), vec4(12.9898, 78.233, 45.164, 94.673));
    float rotation = (fract((sin(dp) * 43758.5453)) * 3.14) * 2.0;
    return vec2(cos(rotation), sin(rotation));
}
#endif
const int PCF_SAMPLES = 16;
#ifdef SHADOWED
ivec2 pcfTexelOf(vec4 uv, int size, vec2 offset) {
    return clamp(ivec2(((uv.xy * vec2(float(size))) + offset)), ivec2(0, 0), ivec2((size - 1), (size - 1)));
}
#endif
const vec2[16] POISSON_DISK = vec2[16](vec2(-0.94201624, -0.39906216), vec2(0.94558609, -0.76890725), vec2(-0.0941841, -0.9293887), vec2(0.34495938, 0.2938776), vec2(-0.91588581, 0.45771432), vec2(-0.81544232, -0.87912464), vec2(-0.38277543, 0.27676845), vec2(0.97484398, 0.75648379), vec2(0.44323325, -0.97511554), vec2(0.53742981, -0.4737342), vec2(-0.26496911, -0.41893023), vec2(0.79197514, 0.19090188), vec2(-0.2418884, 0.99706507), vec2(-0.81409955, 0.9143759), vec2(0.19984126, 0.78641367), vec2(0.14383161, -0.1410079));
#ifdef SHADOWED
vec2 poissonOffset(int tap, vec2 rotation, float scale) {
    vec2 o = POISSON_DISK[tap] * scale;
    return vec2(((rotation.x * o.x) - (rotation.y * o.y)), ((rotation.x * o.y) + (rotation.y * o.x)));
}
#endif
#ifdef SHADOWED
float cascadeShadowAt(vec3 position, vec3 normal_1, int cascade) {
    vec3 at = cascadeReceiverOf(position, normal_1, cascadeMatrices[cascade], cascadeView, cascadeFilter.y);
    vec4 texel = cascadeTexelOf(at, cascadeMatrices[cascade], cascadeView);
    float scale = cascadeFilter.x;
    float lit = 0.0;
    if ((texel.w < 0.5) || (scale <= 0.0)) {
        float stored = texelFetch(sampler2DArray(shadowMap, shadowSampler), ivec3(ivec2(texel.xy), cascade), 0).x;
        lit = cascadeLitOf(texel, stored, cascadeInfo);
    } else {
        vec4 uv = mapCoord(at, cascadeMatrices[cascade]);
        int size = int(cascadeView.w + 0.5);
        vec2 rotation = poissonRotation(at);
        for (int tap = 0; tap < PCF_SAMPLES; tap++) {
            ivec2 at_1 = pcfTexelOf(uv, size, poissonOffset(tap, rotation, scale));
            float stored_1 = texelFetch(sampler2DArray(shadowMap, shadowSampler), ivec3(at_1, cascade), 0).x;
            lit = lit + cascadeLitOf(texel, stored_1, cascadeInfo);
        }
        lit = lit / float(PCF_SAMPLES);
    }
    return lit;
}
#endif
#ifdef SHADOWED
float cascadeBlendOf(float depth, int cascade, vec4 far, vec4 info) {
    if ((cascade + 1) >= cascadeCountOf(info)) {
        return 0.0;
    }
    float bound = farOf(far, cascade);
    float nextNear = (1.0 - info.y) * bound;
    if (depth < nextNear) {
        return 0.0;
    }
    return (depth - nextNear) / (bound - nextNear);
}
#endif
#ifdef SHADOWED
float dirShadowAt(vec3 position, vec3 normal_1) {
    float depth = cascadeDepthOf(position, cameraPosition.xyz, cascadeView);
    int cascade = cascadeIndexOf(depth, cascadeFar, cascadeInfo);
    if (cascade >= cascadeCountOf(cascadeInfo)) {
        return 1.0;
    }
    float lit = cascadeShadowAt(position, normal_1, cascade);
    float blend = cascadeBlendOf(depth, cascade, cascadeFar, cascadeInfo);
    if (blend > 0.0) {
        return mix(lit, cascadeShadowAt(position, normal_1, (cascade + 1)), blend);
    }
    return lit;
}
#endif
#ifdef PBR
vec3 envTurned(vec3 d, vec4 turn) {
    return vec3(((d.x * turn.z) - (d.z * turn.w)), d.y, ((d.x * turn.w) + (d.z * turn.z)));
}
#endif
#ifdef PBR
vec2 splitSum(float roughness, float nv) {
    float rx = 1.0 - roughness;
    float ry = 0.0425 - (0.0275 * roughness);
    float a004 = (min((rx * rx), exp2((-9.28 * nv))) * rx) + ry;
    return max(vec2((((-1.04 * a004) + 1.04) - (0.572 * roughness)), (((1.04 * a004) - 0.04) + (0.022 * roughness))), vec2(0.00005));
}
#endif
#ifdef PBR
vec3 pbrEnvironmentLight(vec3 albedo, float metalness, float roughness, vec3 normal_1, vec3 view, float occlusion) {
    vec3 n = normalize(normal_1);
    vec3 v = normalize(view);
    float nv = max(dot(n, v), 0.0);
    vec3 f0 = mix(vec3(0.04), albedo, metalness);
    vec3 fresnel = f0 + ((max(vec3((1.0 - roughness)), f0) - f0) * exp2((((-5.55473 * nv) - 6.98316) * nv)));
    vec4 turn = envParams;
    vec3 irradiance = textureLod(samplerCube(envDiffuse, envSampler), envTurned(n, turn), 0.0).rgb;
    vec3 radiance = textureLod(samplerCube(envSpecular, envSampler), envTurned(reflect((-v), n), turn), (roughness * turn.y)).rgb;
    vec2 lut = splitSum(roughness, nv);
    vec3 specular = radiance * ((fresnel * lut.x) + lut.y);
    return ((((irradiance * albedo) * (1.0 - metalness)) * (1.0 - fresnel)) + specular) * (turn.x * occlusion);
}
#endif
#ifdef PBR
vec3 pbrAmbient(vec3 albedo, float metalness, float roughness, vec3 normal_1, vec3 view, vec3 ambient_1, float occlusion) {
    float nv = max(dot(normalize(normal_1), normalize(view)), 0.0);
    vec3 f0 = mix(vec3(0.04), albedo, metalness);
    vec3 fresnel = f0 + ((max(vec3((1.0 - roughness)), f0) - f0) * exp2((((-5.55473 * nv) - 6.98316) * nv)));
    return (((ambient_1 * albedo) * (1.0 - metalness)) * (1.0 - fresnel)) * occlusion;
}
#endif
#ifdef PBR
vec3 pbrDirectSpecular(vec3 albedo, float metalness, float roughness, vec3 normal_1, vec3 view, vec3 light, vec3 specularLight, vec3 radiance, float shadow, float occlusionFactor, float occlusion) {
    if (dot(radiance, radiance) <= 0.0001) {
        return vec3(0.0);
    }
    vec3 n = normalize(normal_1);
    vec3 v = normalize(view);
    vec3 l = normalize(light);
    float nl = clamp(dot(n, l), 0.0, 1.0);
    if (nl <= 0.0) {
        return vec3(0.0);
    }
    vec3 h = normalize((normalize(specularLight) + v));
    float nh = clamp(dot(n, h), 0.0, 1.0);
    float vh = clamp(dot(v, h), 0.0, 1.0);
    float nv = clamp(dot(n, v), 0.0, 1.0);
    float alpha = roughness * roughness;
    float alpha2 = alpha * alpha;
    float denominator = ((nh * nh) * (alpha2 - 1.0)) + 1.0;
    float distribution = alpha2 / ((3.14159265358979 * denominator) * denominator);
    float remapped = roughness + 1.0;
    float k = (remapped * remapped) * 0.125;
    float visibility = ((1.0 / ((nv * (1.0 - k)) + k)) * (1.0 / ((nl * (1.0 - k)) + k))) * 0.25;
    vec3 f0 = mix(vec3(0.04), albedo, metalness);
    vec3 fresnel = f0 + ((1.0 - f0) * exp2((((-5.55473 * vh) - 6.98316) * vh)));
    vec3 specular = max((fresnel * (distribution * visibility)), vec3(0.0));
    vec3 diffuse = ((albedo * (1.0 / 3.14159265358979)) * (1.0 - metalness)) * (1.0 - fresnel);
    float reach = (nl * shadow) * mix(1.0, occlusion, occlusionFactor);
    return ((diffuse + specular) * radiance) * reach;
}
#endif
#ifdef PBR
vec3 pbrDirect(vec3 albedo, float metalness, float roughness, vec3 normal_1, vec3 view, vec3 light, vec3 radiance, float shadow, float occlusionFactor, float occlusion) {
    return pbrDirectSpecular(albedo, metalness, roughness, normal_1, view, light, light, radiance, shadow, occlusionFactor, occlusion);
}
#endif
int cellOf(float position, int cells) {
    if (!(position > 0.0)) {
        return 0;
    }
    if (position >= float(cells)) {
        return cells - 1;
    }
    return int(position);
}
int clusterSliceOf(float depth, vec4 grid, vec4 factors) {
    int slices = int(grid.z + 0.5);
    if (grid.w > 0.5) {
        return cellOf(floor(((depth - factors.z) * factors.w)), slices);
    }
    return cellOf((((log(depth) * factors.z) - factors.w) + 1.0), slices);
}
int clusterAtCell(vec2 cell, float depth, vec4 grid, vec4 factors) {
    int columns = int(grid.x + 0.5);
    int x = cellOf(cell.x, columns);
    int y = cellOf(cell.y, int(grid.y + 0.5));
    return (((y * columns) + x) * int(grid.z + 0.5)) + clusterSliceOf(depth, grid, factors);
}
int clusterIndexOf(vec2 frag, float depth, vec4 grid, vec4 factors) {
    return clusterAtCell((frag * factors.xy), depth, grid, factors);
}
float clusterDepthOf(vec3 position, vec4 view) {
    return dot(position, view.xyz) + view.w;
}
int fragmentClusterOf(vec2 frag, vec3 position, vec4 grid, vec4 factors, vec4 view, vec4 screen) {
    float row = (screen.x > 0.5) ? (screen.y - frag.y) : frag.y;
    return clusterIndexOf(vec2(frag.x, row), clusterDepthOf(position, view), grid, factors);
}
const uint DATA_ROW = 256;
ivec2 dataTexelOf(int i) {
    uint at = uvec2(ivec2(i, 0)).x;
    return ivec2(uvec2((at % DATA_ROW), (at / DATA_ROW)));
}
ivec4 litClusterOf(vec2 frag, vec3 position) {
    int cluster = fragmentClusterOf(frag, position, clusterGrid, clusterFactors, clusterView, clusterScreen);
    return ivec4(texelFetch(usampler2D(clusterRecords, clusterSampler), dataTexelOf(cluster), 0));
}
int indexOfWord(uvec4 texel, int j) {
    ivec4 words = ivec4(texel);
    uint channel = uvec2(ivec2(j, 0)).x % 4;
    if (channel == 0) {
        return words.x;
    }
    if (channel == 1) {
        return words.y;
    }
    if (channel == 2) {
        return words.z;
    }
    return words.w;
}
ivec2 indexTexelOf(int j) {
    return dataTexelOf(ivec2(uvec2((uvec2(ivec2(j, 0)).x / 4), 0)).x);
}
int litLightOf(ivec4 cluster, int k) {
    int j = cluster.x + k;
    return indexOfWord(texelFetch(usampler2D(clusterIndices, clusterSampler), indexTexelOf(j), 0), j);
}
const int RECORD_TEXELS = 6;
ivec2 recordTexelOf(int light, int texel) {
    return dataTexelOf(((light * RECORD_TEXELS) + texel));
}
vec4 litTexelOf(int light, int texel) {
    return texelFetch(sampler2D(lightRecords, clusterSampler), recordTexelOf(light, texel), 0);
}
vec3 cookieAt(vec3 position) {
    vec4 q = cookieMatrix * vec4(position, 1.0);
    if (q.w <= 0.0) {
        return vec3(0.0);
    }
    vec2 uv = q.xy / q.w;
    if ((((uv.x < 0.0) || (uv.x > 1.0)) || (uv.y < 0.0)) || (uv.y > 1.0)) {
        return vec3(0.0);
    }
    vec4 texel = textureLod(sampler2D(cookieTexture, cookieSampler), uv, 0.0);
    return texel.rgb * texel.a;
}
vec4 recordCookieAt(vec3 position, int i) {
    float named = float(i + 1);
    if (cookie.x == named) {
        return vec4(cookieAt(position), 1.0);
    }
    return vec4(1.0, 1.0, 1.0, 0.0);
}
float lightWindow(float distance_1, float range) {
    float window = clamp((1.0 - (distance_1 / range)), 0.0, 1.0);
    return window * window;
}
vec4 cookieSpotSample(vec3 position, vec4 at, vec4 tint) {
    vec3 delta = at.xyz - position;
    float distance_1 = length(delta);
    if (distance_1 < 0.0001) {
        return vec4(0.0);
    }
    return vec4((delta / distance_1), lightWindow(distance_1, tint.a));
}
#ifdef SHADOWED
float spotShadowAt(vec3 position, vec3 normal_1) {
    vec4 receiver = spotReceiver;
    vec3 biased = position + (normal_1 * (receiver.x * length((position - receiver.yzw))));
    vec4 p = mapCoord(biased, spotMatrix);
    if (p.w < 0.5) {
        return 1.0;
    }
    int size = int(spotShadow.z + 0.5);
    float scale = spotShadow.w;
    if (scale <= 0.0) {
        float depth = texelFetch(sampler2DArray(spotShadowMap, spotShadowSampler), ivec3(pcfTexelOf(p, size, vec2(0.0)), 0), 0).x;
        return mapLit(p.z, depth, spotShadow.x, spotShadow.y);
    }
    vec2 rotation = poissonRotation(biased);
    float lit = 0.0;
    for (int tap = 0; tap < PCF_SAMPLES; tap++) {
        ivec2 at = pcfTexelOf(p, size, poissonOffset(tap, rotation, scale));
        float depth_1 = texelFetch(sampler2DArray(spotShadowMap, spotShadowSampler), ivec3(at, 0), 0).x;
        lit = lit + mapLit(p.z, depth_1, spotShadow.x, spotShadow.y);
    }
    return lit / float(PCF_SAMPLES);
}
#endif
#ifdef SHADOWED
int cubeFaceOf(vec3 toPosition) {
    vec3 axes = abs(toPosition);
    if ((axes.x >= axes.y) && (axes.x >= axes.z)) {
        return (toPosition.x > 0.0) ? 0 : 1;
    }
    if (axes.y >= axes.z) {
        return (toPosition.y > 0.0) ? 2 : 3;
    }
    return (toPosition.z > 0.0) ? 4 : 5;
}
#endif
#ifdef SHADOWED
float cubeTapAt(vec3 position) {
    vec3 toPosition = position - cubeLight.xyz;
    int face = cubeFaceOf(toPosition);
    vec4 p = mapCoord(position, cubeMatrices[face]);
    if (p.w < 0.5) {
        return 1.0;
    }
    int size = int(cubeShadow.z + 0.5);
    float depth = texelFetch(sampler2DArray(cubeShadowMap, spotShadowSampler), ivec3(pcfTexelOf(p, size, vec2(0.0)), face), 0).x;
    float near = cubeRange.x;
    float far = cubeRange.y;
    vec3 axes = abs(toPosition);
    float axis = max(axes.x, max(axes.y, axes.z));
    float distance_1 = length(toPosition);
    float stored = ((near * far) / (far - (depth * (far - near)))) * (distance_1 / axis);
    return mapLit((distance_1 / far), (stored / far), (cubeShadow.x / far), cubeShadow.y);
}
#endif
const int CUBE_PCF_SAMPLES = 20;
const vec3[20] CUBE_PCF_OFFSETS = vec3[20](vec3(1.0, 1.0, 1.0), vec3(1.0, -1.0, 1.0), vec3(-1.0, -1.0, 1.0), vec3(-1.0, 1.0, 1.0), vec3(1.0, 1.0, -1.0), vec3(1.0, -1.0, -1.0), vec3(-1.0, -1.0, -1.0), vec3(-1.0, 1.0, -1.0), vec3(1.0, 1.0, 0.0), vec3(1.0, -1.0, 0.0), vec3(-1.0, -1.0, 0.0), vec3(-1.0, 1.0, 0.0), vec3(1.0, 0.0, 1.0), vec3(-1.0, 0.0, 1.0), vec3(1.0, 0.0, -1.0), vec3(-1.0, 0.0, -1.0), vec3(0.0, 1.0, 1.0), vec3(0.0, -1.0, 1.0), vec3(0.0, -1.0, -1.0), vec3(0.0, 1.0, -1.0));
#ifdef SHADOWED
float cubeShadowAt(vec3 position, vec3 normal_1) {
    float scale = cubeShadow.w / cubeShadow.z;
    vec3 light = cubeLight.xyz;
    vec3 at = position + (normal_1 * (cubeRange.z * length((position - light))));
    vec3 toPosition = at - light;
    float distance_1 = length(toPosition);
    float lit = 0.0;
    if ((!(scale > 0.0)) || (!(distance_1 > 0.0))) {
        lit = cubeTapAt(at);
    } else {
        vec3 direction = toPosition / distance_1;
        for (int tap = 0; tap < CUBE_PCF_SAMPLES; tap++) {
            vec3 turned = normalize((direction + (CUBE_PCF_OFFSETS[tap] * scale)));
            lit = lit + cubeTapAt((light + (turned * distance_1)));
        }
        lit = lit / float(CUBE_PCF_SAMPLES);
    }
    return lit;
}
#endif
float recordShadowAt(vec3 position, vec3 normal_1, int i) {
    float lit = 1.0;
#ifdef SHADOWED
    float named = float(i + 1);
    if (ambient.w == named) {
        lit = spotShadowAt(position, normal_1);
    } else if (dirColor.w == named) {
        lit = cubeShadowAt(position, normal_1);
    }
#endif
    return lit;
}
vec4 capsuleSample(vec3 position, vec4 at, vec4 tint, vec4 a, vec4 b) {
    vec3 start = at.xyz - (a.xyz * b.x);
    vec3 segment = a.xyz * (2.0 * b.x);
    float along = clamp((dot((position - start), segment) / dot(segment, segment)), 0.0, 1.0);
    vec3 delta = (start + (segment * along)) - position;
    float distance_1 = length(delta);
    if (distance_1 < 0.0001) {
        return vec4(0.0);
    }
    return vec4((delta / distance_1), lightWindow(distance_1, tint.a));
}
vec3 rectanglePoint(vec3 position, vec3 ray, vec4 at, vec4 a, vec4 b, vec4 c) {
    float along = dot(a.xyz, (at.xyz - position)) / dot(a.xyz, ray);
    vec3 offset = (position + (ray * along)) - at.xyz;
    return (at.xyz + (b.xyz * clamp(dot(offset, b.xyz), (-b.w), b.w))) + (c.xyz * clamp(dot(offset, c.xyz), (-c.w), c.w));
}
float rectangleAxisCone(vec3 delta, vec3 forward, vec3 excluded, float outer, float inner) {
    vec3 projectedDelta = delta - (excluded * dot(delta, excluded));
    vec3 projectedLight = (-forward) - (excluded * dot((-forward), excluded));
    float deltaLength = length(projectedDelta);
    float lightLength = length(projectedLight);
    if ((deltaLength < 0.0001) || (lightLength < 0.0001)) {
        return 0.0;
    }
    float theta = dot(projectedDelta, projectedLight) / (deltaLength * lightLength);
    return clamp(((theta - outer) / ((inner - outer) + 0.00001)), 0.0, 1.0);
}
vec4 rectangleSample(vec3 position, vec3 normal_1, vec4 at, vec4 tint, vec4 a, vec4 b, vec4 c, vec4 d) {
    if (abs(dot(a.xyz, normal_1)) < 0.000001) {
        return vec4(0.0);
    }
    vec3 delta = rectanglePoint(position, normal_1, at, a, b, c) - position;
    float distance_1 = length(delta);
    if (distance_1 < 0.0001) {
        return vec4(0.0);
    }
    float cone = rectangleAxisCone(delta, a.xyz, c.xyz, d.x, d.y) * rectangleAxisCone(delta, a.xyz, b.xyz, d.z, d.w);
    return vec4((delta / distance_1), (lightWindow(distance_1, tint.a) * cone));
}
vec4 spotSample(vec3 position, vec4 at, vec4 tint, vec4 a, vec4 b) {
    vec3 delta = at.xyz - position;
    float distance_1 = length(delta);
    if (distance_1 < 0.0001) {
        return vec4(0.0);
    }
    vec3 toLight = delta / distance_1;
    float cone = clamp(((dot(toLight, (-a.xyz)) - b.x) / (b.y - b.x)), 0.0, 1.0);
    return vec4(toLight, (lightWindow(distance_1, tint.a) * cone));
}
vec4 shapedSample(vec3 position, vec3 normal_1, vec4 at, vec4 tint, vec4 a, vec4 b, vec4 c, vec4 d) {
    if (a.w > 2.5) {
        return capsuleSample(position, at, tint, a, b);
    }
    if (a.w > 1.5) {
        return rectangleSample(position, normal_1, at, tint, a, b, c, d);
    }
    return spotSample(position, at, tint, a, b);
}
#ifdef PBR
vec3 capsuleSpecularDir(vec3 position, vec3 reflected, vec3 diffuse, vec4 at, vec4 a, vec4 b) {
    vec3 l0 = (at.xyz - (a.xyz * b.x)) - position;
    vec3 l01 = a.xyz * (2.0 * b.x);
    float squared = dot(l01, l01);
    float alongRay = dot(reflected, l01);
    float denominator = squared - (alongRay * alongRay);
    if (denominator <= 0.000001) {
        return diffuse;
    }
    vec3 closest = l0 + (l01 * clamp((dot(l0, ((reflected * alongRay) - l01)) / denominator), 0.0, 1.0));
    vec3 centerToRay = (reflected * dot(closest, reflected)) - closest;
    float offset = length(centerToRay);
    if (offset < 0.000001) {
        return normalize(closest);
    }
    return normalize((closest + (centerToRay * clamp((b.y / offset), 0.0, 1.0))));
}
#endif
#ifdef PBR
vec3 rectangleSpecularDir(vec3 position, vec3 reflected, vec3 diffuse, vec4 at, vec4 a, vec4 b, vec4 c) {
    if (abs(dot(a.xyz, reflected)) < 0.000001) {
        return diffuse;
    }
    return normalize((rectanglePoint(position, reflected, at, a, b, c) - position));
}
#endif
#ifdef PBR
vec3 shapedSpecularDir(vec3 position, vec3 reflected, vec3 diffuse, vec4 at, vec4 a, vec4 b, vec4 c) {
    if (a.w > 2.5) {
        return capsuleSpecularDir(position, reflected, diffuse, at, a, b);
    }
    if (a.w > 1.5) {
        return rectangleSpecularDir(position, reflected, diffuse, at, a, b, c);
    }
    return diffuse;
}
#endif
vec3 linearToSrgb(vec3 rgb) {
    vec3 low = rgb * 12.92;
    vec3 high = (vec3(1.055) * pow(max(rgb, vec3(0.0)), vec3(0.41666))) - vec3(0.055);
    return vec3(((rgb.x <= 0.0031308) ? low.x : high.x), ((rgb.y <= 0.0031308) ? low.y : high.y), ((rgb.z <= 0.0031308) ? low.z : high.z));
}
#ifdef PBR
vec4 pbrShade(vec3 n, vec3 surfaceNormal, vec3 position, vec2 frag, vec4 surfaceColor, vec3 values) {
    vec3 albedo = srgbToLinear(saturated(surfaceColor.rgb, materialOf().y));
    vec3 view = cameraPosition.xyz - position;
    vec4 dir = dirLight;
    float shadow = 1.0;
#ifdef SHADOWED
    shadow = dirShadowAt(position, surfaceNormal);
#endif
    vec3 sun = srgbToLinear(dirColor.rgb) * dir.w;
    vec3 light = vec3(0.0);
    if (envParams.x > 0.0) {
        light = pbrEnvironmentLight(albedo, values.x, values.y, n, view, values.z);
    } else {
        light = pbrAmbient(albedo, values.x, values.y, n, view, srgbToLinear(ambient.rgb), values.z);
    }
    light = light + pbrDirect(albedo, values.x, values.y, n, view, dir.xyz, sun, shadow, 0.0, values.z);
    vec3 eye = normalize(view);
    vec3 reflected = (-eye) - (n * (2.0 * dot((-eye), n)));
    ivec4 cluster = litClusterOf(frag, position);
    for (int k = 0; k < (cluster.y + cluster.z); k++) {
        int i = litLightOf(cluster, k);
        vec4 at = litTexelOf(i, 0);
        vec4 tint = litTexelOf(i, 1);
        vec4 a = litTexelOf(i, 2);
        vec4 bb = litTexelOf(i, 3);
        vec4 cookie_1 = recordCookieAt(position, i);
        if (cookie_1.w > 0.5) {
            vec4 sample_1 = cookieSpotSample(position, at, tint);
            vec3 radiance = (srgbToLinear(tint.rgb) * cookie_1.rgb) * (sample_1.w * at.w);
            light = light + pbrDirectSpecular(albedo, values.x, values.y, n, view, sample_1.xyz, sample_1.xyz, radiance, recordShadowAt(position, surfaceNormal, i), 0.0, values.z);
        } else if (a.w < 0.5) {
            vec3 toLight = at.xyz - position;
            float falloff = clamp((1.0 - (length(toLight) / tint.a)), 0.0, 1.0);
            vec3 radiance_1 = srgbToLinear(tint.rgb) * ((falloff * falloff) * at.w);
            light = light + pbrDirect(albedo, values.x, values.y, n, view, toLight, radiance_1, recordShadowAt(position, surfaceNormal, i), 0.0, values.z);
        } else {
            vec4 cc = litTexelOf(i, 4);
            vec4 sample_2 = shapedSample(position, n, at, tint, a, bb, cc, litTexelOf(i, 5));
            vec3 radiance_2 = srgbToLinear(tint.rgb) * (sample_2.w * at.w);
            vec3 specular = shapedSpecularDir(position, reflected, sample_2.xyz, at, a, bb, cc);
            light = light + pbrDirectSpecular(albedo, values.x, values.y, n, view, sample_2.xyz, specular, radiance_2, recordShadowAt(position, surfaceNormal, i), 0.0, values.z);
        }
    }
    return vec4(linearToSrgb(light), surfaceColor.a);
}
#endif
#ifndef PBR
vec3 pointLightAt(vec3 position, vec3 normal_1, vec4 at, vec4 tint) {
    vec3 toLight = at.xyz - position;
    float distance_1 = length(toLight);
    float falloff = clamp((1.0 - (distance_1 / tint.a)), 0.0, 1.0);
    float facing = max(dot(normal_1, (toLight / max(distance_1, 0.0001))), 0.0);
    return srgbToLinear(tint.rgb) * (((falloff * falloff) * facing) * at.w);
}
#endif
#ifndef PBR
vec3 lightAt(vec3 position, vec3 normal_1, vec4 at, vec4 tint, vec4 a, vec4 b, vec4 c, vec4 d) {
    vec3 lit = vec3(0.0);
    if (a.w < 0.5) {
        lit = pointLightAt(position, normal_1, at, tint);
    } else {
        vec4 sample_1 = shapedSample(position, normal_1, at, tint, a, b, c, d);
        lit = srgbToLinear(tint.rgb) * ((sample_1.w * max(dot(normal_1, sample_1.xyz), 0.0)) * at.w);
    }
    return lit;
}
#endif
#ifndef PBR
vec4 litShade(vec3 n, vec3 surfaceNormal, vec3 position, vec2 frag, vec4 surfaceColor) {
    vec4 dir = dirLight;
    float lambert = max(dot(n, dir.xyz), 0.0) * dir.w;
#ifdef SHADOWED
    lambert = lambert * dirShadowAt(position, surfaceNormal);
#endif
    vec3 ambient_1 = srgbToLinear(ambient.rgb);
    vec3 light = ambient_1 + (srgbToLinear(dirColor.rgb) * lambert);
    ivec4 cluster = litClusterOf(frag, position);
    for (int k = 0; k < (cluster.y + cluster.z); k++) {
        int i = litLightOf(cluster, k);
        vec4 at = litTexelOf(i, 0);
        vec4 tint = litTexelOf(i, 1);
        vec4 cookie_1 = recordCookieAt(position, i);
        vec3 lit = vec3(0.0);
        if (cookie_1.w > 0.5) {
            vec4 sample_1 = cookieSpotSample(position, at, tint);
            lit = (srgbToLinear(tint.rgb) * cookie_1.rgb) * ((sample_1.w * max(dot(n, sample_1.xyz), 0.0)) * at.w);
        } else {
            lit = lightAt(position, n, at, tint, litTexelOf(i, 2), litTexelOf(i, 3), litTexelOf(i, 4), litTexelOf(i, 5));
        }
        light = light + (lit * recordShadowAt(position, surfaceNormal, i));
    }
    vec3 surface = srgbToLinear(saturated(surfaceColor.rgb, materialOf().y));
    return vec4(linearToSrgb((surface * light)), surfaceColor.a);
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
    vec3 n = facingNormal(normalize(worldNormal), params.z, gl_FrontFacing);
    vec3 surfaceNormal = n;
    vec4 surfaceColor = tintedSurface(baseColor);
    vec4 shaded = vec4(0.0);
#ifdef PBR
    vec3 pbrValues = pbrOf().xyz;
    shaded = pbrShade(n, surfaceNormal, worldPosition, gl_FragCoord.xy, surfaceColor, pbrValues);
#else
    shaded = litShade(n, surfaceNormal, worldPosition, gl_FragCoord.xy, surfaceColor);
#endif
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
#if defined(CUTOUT) && !defined(PBR) && !((defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE)) && !defined(EMISSIVE)
layout(binding=3) uniform materialParams {
    vec4 material;
    vec4 materialColor;
};
#endif
#if defined(CUTOUT) && !defined(PBR) && ((defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE)) && !defined(EMISSIVE)
layout(binding=3) uniform movingMaterialParams {
    vec4 material;
    vec4 materialColor;
    vec4 uvMatrix;
    vec4 uvMotion;
    vec4 backUvMatrix;
    vec4 backUvOffset;
    vec4 dissolve;
    vec4 dissolveEdge;
    vec4 flipbookGrid;
    vec4 flipbookPlay;
};
#endif
#if defined(CUTOUT) && !defined(PBR) && !((defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE)) && defined(EMISSIVE)
layout(binding=3) uniform emissiveMaterialParams {
    vec4 material;
    vec4 materialColor;
    vec4 emissive;
};
#endif
#if defined(CUTOUT) && !defined(PBR) && ((defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE)) && defined(EMISSIVE)
layout(binding=3) uniform movingEmissiveMaterialParams {
    vec4 material;
    vec4 materialColor;
    vec4 uvMatrix;
    vec4 uvMotion;
    vec4 backUvMatrix;
    vec4 backUvOffset;
    vec4 dissolve;
    vec4 dissolveEdge;
    vec4 flipbookGrid;
    vec4 flipbookPlay;
    vec4 emissive;
};
#endif
#if defined(CUTOUT) && defined(PBR) && !defined(EMISSIVE)
layout(binding=3) uniform pbrMaterialParams {
    vec4 material;
    vec4 materialColor;
    vec4 pbr;
    vec4 uvMatrix;
    vec4 uvMotion;
    vec4 parallax;
};
#endif
#if defined(CUTOUT) && defined(PBR) && defined(EMISSIVE)
layout(binding=3) uniform pbrEmissiveMaterialParams {
    vec4 material;
    vec4 materialColor;
    vec4 pbr;
    vec4 uvMatrix;
    vec4 uvMotion;
    vec4 parallax;
    vec4 emissive;
};
#endif
in vec3 worldPosition;
in vec3 worldNormal;
in vec4 baseColor;
#ifdef CUTOUT
vec4 materialColorOf() {
#ifdef PBR
#ifdef EMISSIVE
    return materialColor;
#else
    return materialColor;
#endif
#else
#if (defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE)
#ifdef EMISSIVE
    return materialColor;
#else
    return materialColor;
#endif
#else
#ifdef EMISSIVE
    return materialColor;
#else
    return materialColor;
#endif
#endif
#endif
}
#endif
#ifdef CUTOUT
vec4 materialOf() {
#ifdef PBR
#ifdef EMISSIVE
    return material;
#else
    return material;
#endif
#else
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
#endif
}
#endif
void main() {
#ifdef CUTOUT
    if ((baseColor.a * materialColorOf().a) < materialOf().w) {
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
    vec4 cameraPosition;
};
#ifdef SKINNED
layout(binding=7) uniform skinParams {
    vec4 skinRows[192];
};
#endif
in vec3 position;
in vec3 normal;
in vec2 uv;
in vec4 color;
#ifdef NORMAL_MAP
in vec4 tangent;
#endif
#ifdef OCCLUSION_UV_B
in vec2 uvB;
#endif
#ifdef SKINNED
in vec4 skinJoints;
#endif
#ifdef SKINNED
in vec4 skinWeights;
#endif
in vec4 instanceRow0;
in vec4 instanceRow1;
in vec4 instanceRow2;
in vec4 instanceColor;
#ifdef NORMAL_MAP
out vec4 worldTangent;
#endif
out vec3 worldPosition;
out vec3 worldNormal;
out vec2 surfaceUv;
#ifdef OCCLUSION_UV_B
out vec2 surfaceUvB;
#endif
out vec4 baseColor;
#ifdef SKINNED
vec4 skinRow(vec4 joints, vec4 weights, int column) {
    return (((skinRows[(int(joints.x) * 3) + column] * weights.x) + (skinRows[(int(joints.y) * 3) + column] * weights.y)) + (skinRows[(int(joints.z) * 3) + column] * weights.z)) + (skinRows[(int(joints.w) * 3) + column] * weights.w);
}
#endif
#ifdef SKINNED
mat4 skinWorld(vec4 joints, vec4 weights) {
    return transpose(mat4(skinRow(joints, weights, 0), skinRow(joints, weights, 1), skinRow(joints, weights, 2), vec4(0.0, 0.0, 0.0, 1.0)));
}
#endif
vec3 skinNormal(mat4 world, vec3 normal_1) {
    mat3 linear = mat3(world);
    vec3 a = cross(linear[1], linear[2]);
    vec3 b = cross(linear[2], linear[0]);
    vec3 c = cross(linear[0], linear[1]);
    float direction = (dot(linear[0], a) < 0.0) ? -1.0 : 1.0;
    return (((a * normal_1.x) + (b * normal_1.y)) + (c * normal_1.z)) * direction;
}
#ifdef NORMAL_MAP
float handednessOf(mat4 matrix) {
    return (determinant(mat3(matrix)) < 0.0) ? -1.0 : 1.0;
}
#endif
#ifndef SKINNED
mat4 instanceWorld(vec4 row0, vec4 row1, vec4 row2) {
    return transpose(mat4(row0, row1, row2, vec4(0.0, 0.0, 0.0, 1.0)));
}
#endif
void main() {
#ifdef SKINNED
    mat4 matrix = skinWorld(skinJoints, skinWeights);
    vec4 world = matrix * vec4(position, 1.0);
    worldPosition = world.xyz;
    worldNormal = skinNormal(matrix, normal);
#ifdef NORMAL_MAP
    worldTangent = vec4((mat3(matrix) * tangent.xyz), (tangent.w * handednessOf(matrix)));
#endif
    surfaceUv = uv;
#ifdef OCCLUSION_UV_B
    surfaceUvB = uvB;
#endif
    baseColor = color;
    gl_Position = (viewProj * world);
    return;
#else
    mat4 matrix_1 = instanceWorld(instanceRow0, instanceRow1, instanceRow2);
    vec4 world_1 = matrix_1 * vec4(position, 1.0);
    worldPosition = world_1.xyz;
    worldNormal = skinNormal(matrix_1, normal);
#ifdef NORMAL_MAP
    worldTangent = vec4((mat3(matrix_1) * tangent.xyz), (tangent.w * handednessOf(matrix_1)));
#endif
    surfaceUv = uv;
#ifdef OCCLUSION_UV_B
    surfaceUvB = uvB;
#endif
    baseColor = (color * instanceColor);
    gl_Position = (viewProj * world_1);
    return;
#endif
}
@end

@fs litTexturedFs
#if !defined(PBR) && !((defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE)) && !defined(EMISSIVE)
layout(binding=3) uniform materialParams {
    vec4 material;
    vec4 materialColor;
};
#endif
#if (defined(UV_TRANSFORM) && !defined(EMISSIVE)) || (defined(BACK_TEXTURE) && !defined(EMISSIVE)) || (defined(DISSOLVE) && !defined(EMISSIVE))
layout(binding=3) uniform movingMaterialParams {
    vec4 material;
    vec4 materialColor;
    vec4 uvMatrix;
    vec4 uvMotion;
    vec4 backUvMatrix;
    vec4 backUvOffset;
    vec4 dissolve;
    vec4 dissolveEdge;
    vec4 flipbookGrid;
    vec4 flipbookPlay;
};
#endif
#if !defined(PBR) && !((defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE)) && defined(EMISSIVE)
layout(binding=3) uniform emissiveMaterialParams {
    vec4 material;
    vec4 materialColor;
    vec4 emissive;
};
#endif
#if (defined(UV_TRANSFORM) && defined(EMISSIVE)) || (defined(BACK_TEXTURE) && defined(EMISSIVE)) || (defined(DISSOLVE) && defined(EMISSIVE))
layout(binding=3) uniform movingEmissiveMaterialParams {
    vec4 material;
    vec4 materialColor;
    vec4 uvMatrix;
    vec4 uvMotion;
    vec4 backUvMatrix;
    vec4 backUvOffset;
    vec4 dissolve;
    vec4 dissolveEdge;
    vec4 flipbookGrid;
    vec4 flipbookPlay;
    vec4 emissive;
};
#endif
#if (defined(PBR) && !defined(EMISSIVE)) || ((defined(NORMAL_MAP) && defined(PARALLAX)) && !defined(EMISSIVE))
layout(binding=3) uniform pbrMaterialParams {
    vec4 material;
    vec4 materialColor;
    vec4 pbr;
    vec4 uvMatrix;
    vec4 uvMotion;
    vec4 parallax;
};
#endif
#if (defined(PBR) && defined(EMISSIVE)) || ((defined(NORMAL_MAP) && defined(PARALLAX)) && defined(EMISSIVE))
layout(binding=3) uniform pbrEmissiveMaterialParams {
    vec4 material;
    vec4 materialColor;
    vec4 pbr;
    vec4 uvMatrix;
    vec4 uvMotion;
    vec4 parallax;
    vec4 emissive;
};
#endif
layout(binding=1) uniform lightParams {
    vec4 ambient;
    vec4 dirLight;
    vec4 dirColor;
    vec4 clusterGrid;
    vec4 clusterFactors;
    vec4 clusterView;
    vec4 clusterScreen;
    vec4 cookie;
    mat4 cookieMatrix;
};
layout(binding=6) uniform frameParams {
    vec4 frame;
    vec4 cameraPosition;
    vec4 envParams;
};
#ifdef SHADOWED
layout(binding=5) uniform shadowParams {
    mat4 cascadeMatrices[4];
    vec4 cascadeFar;
    vec4 cascadeInfo;
    vec4 cascadeView;
    vec4 cascadeFilter;
    mat4 spotMatrix;
    vec4 spotShadow;
    vec4 spotReceiver;
    mat4 cubeMatrices[6];
    vec4 cubeShadow;
    vec4 cubeLight;
    vec4 cubeRange;
};
#endif
#ifdef SHADOWED
@image_sample_type shadowMap unfilterable_float
layout(binding=4) uniform texture2DArray shadowMap;
#endif
#ifdef SHADOWED
@sampler_type shadowSampler nonfiltering
layout(binding=2) uniform sampler shadowSampler;
#endif
#ifdef SHADOWED
@image_sample_type spotShadowMap unfilterable_float
layout(binding=6) uniform texture2DArray spotShadowMap;
#endif
#ifdef SHADOWED
@sampler_type spotShadowSampler nonfiltering
layout(binding=3) uniform sampler spotShadowSampler;
#endif
#ifdef SHADOWED
@image_sample_type cubeShadowMap unfilterable_float
layout(binding=12) uniform texture2DArray cubeShadowMap;
#endif
layout(binding=13) uniform texture2D cookieTexture;
layout(binding=6) uniform sampler cookieSampler;
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
#if (defined(NORMAL_MAP) && defined(PARALLAX)) || (defined(PBR) && defined(PBR_MAPS))
layout(binding=1) uniform texture2D metalRoughTexture;
#endif
#if defined(PBR) && defined(PBR_MAPS)
layout(binding=2) uniform texture2D occlusionTexture;
#endif
#ifdef PBR
layout(binding=7) uniform textureCube envDiffuse;
#endif
#ifdef PBR
layout(binding=8) uniform textureCube envSpecular;
#endif
#ifdef PBR
layout(binding=4) uniform sampler envSampler;
#endif
@image_sample_type lightRecords unfilterable_float
layout(binding=9) uniform texture2D lightRecords;
@image_sample_type clusterRecords uint
layout(binding=10) uniform utexture2D clusterRecords;
@image_sample_type clusterIndices uint
layout(binding=11) uniform utexture2D clusterIndices;
@sampler_type clusterSampler nonfiltering
layout(binding=5) uniform sampler clusterSampler;
#ifdef NORMAL_MAP
in vec4 worldTangent;
#endif
in vec3 worldPosition;
in vec3 worldNormal;
in vec2 surfaceUv;
#ifdef OCCLUSION_UV_B
in vec2 surfaceUvB;
#endif
in vec4 baseColor;
layout(location=0) out vec4 color;
#ifdef NORMAL_MRT
layout(location=1) out vec4 normal;
#endif
vec4 materialOf() {
#ifdef PBR
#ifdef EMISSIVE
    return material;
#else
    return material;
#endif
#else
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
#endif
}
#if defined(UV_TRANSFORM) || defined(PBR)
vec2 movedUv(vec2 uv, vec4 matrix, vec4 motion, float time) {
    return ((mat2(matrix.xy, matrix.zw) * uv) + motion.xy) + (motion.zw * time);
}
#endif
#if defined(UV_TRANSFORM) || defined(PBR)
vec4 uvMatrixOf() {
#ifdef PBR
#ifdef EMISSIVE
    return uvMatrix;
#else
    return uvMatrix;
#endif
#else
#ifdef EMISSIVE
    return uvMatrix;
#else
    return uvMatrix;
#endif
#endif
}
#endif
#if defined(UV_TRANSFORM) || defined(PBR)
vec4 uvMotionOf() {
#ifdef PBR
#ifdef EMISSIVE
    return uvMotion;
#else
    return uvMotion;
#endif
#else
#ifdef EMISSIVE
    return uvMotion;
#else
    return uvMotion;
#endif
#endif
}
#endif
#if defined(NORMAL_MAP) && defined(PARALLAX)
float parallaxLayers(float viewZ, float steps) {
    float most = (steps > 0.0) ? steps : 24.0;
    return mix(most, 6.0, clamp(abs(viewZ), 0.0, 1.0));
}
#endif
#if defined(NORMAL_MAP) && defined(PARALLAX)
vec2 parallaxUv(vec2 uv, vec3 view, vec3 normal_1, vec4 tangent, float amount, float steps) {
    vec3 t = normalize(tangent.xyz);
    float sign_1 = (tangent.w < 0.0) ? -1.0 : 1.0;
    vec3 bitangent = normalize(cross(normal_1, t)) * (-sign_1);
    vec3 viewNs = normalize(vec3(dot(view, t), dot(view, bitangent), dot(view, normal_1)));
    float layers = parallaxLayers(viewNs.z, steps);
    float layerDepth = 1.0 / layers;
    vec2 delta = viewNs.xy * ((-amount) / (viewNs.z * layers));
    vec2 at = uv;
    float depth = 1.0 - textureLod(sampler2D(metalRoughTexture, baseSampler), at, 0.0).a;
    float layer = 0.0;
    while (layer < depth) {
        at = at + delta;
        depth = 1.0 - textureLod(sampler2D(metalRoughTexture, baseSampler), at, 0.0).a;
        layer = layer + layerDepth;
    }
    vec2 previous = at - delta;
    float after = depth - layer;
    float before = ((1.0 - texture(sampler2D(metalRoughTexture, baseSampler), previous).a) - layer) + layerDepth;
    return mix(at, previous, (after / (after - before)));
}
#endif
#if defined(NORMAL_MAP) && defined(PARALLAX)
float parallaxStepsOf() {
#ifdef EMISSIVE
    return parallax.x;
#else
    return parallax.x;
#endif
}
#endif
#ifdef UV_TRANSFORM
vec4 flipbookGridOf() {
#ifdef EMISSIVE
    return flipbookGrid;
#else
    return flipbookGrid;
#endif
}
#endif
#ifdef UV_TRANSFORM
vec4 flipbookPlayOf() {
#ifdef EMISSIVE
    return flipbookPlay;
#else
    return flipbookPlay;
#endif
}
#endif
#ifdef UV_TRANSFORM
vec4 flipbookUvs(vec2 uv, vec4 grid, vec4 play, float time) {
    float frame_1 = floor((((time - play.x) * grid.w) + trunc(play.y)));
    float looped = frame_1 - (grid.z * floor((frame_1 / grid.z)));
    float nextLooped = (looped + 1.0) - (grid.z * floor(((looped + 1.0) / grid.z)));
    float at = (play.z == 1.0) ? looped : min(frame_1, (grid.z - 1.0));
    float next = (play.z == 1.0) ? nextLooped : min((frame_1 + 1.0), (grid.z - 1.0));
    vec2 cell = uv / grid.xy;
    vec2 atCell = vec2((at - (grid.x * floor((at / grid.x)))), trunc((at / grid.x))) / grid.xy;
    vec2 nextCell = vec2((next - (grid.x * floor((next / grid.x)))), trunc((next / grid.x))) / grid.xy;
    return vec4((cell + atCell), (cell + nextCell));
}
#endif
#ifdef UV_TRANSFORM
float flipbookBlend(vec4 grid, vec4 play, float time) {
    return (play.w == 1.0) ? fract((((time - play.x) * grid.w) + trunc(play.y))) : 0.0;
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
    return ((doubleSided > 0.5) && (!frontFacing)) ? -1.0 : 1.0;
}
#endif
#ifdef NORMAL_MAP
vec3 mappedNormal(vec3 normal_1, vec4 tangent, float face, vec3 texel) {
    vec3 t = normalize(tangent.xyz);
    float sign_1 = (tangent.w < 0.0) ? -1.0 : 1.0;
    vec3 bitangent = normalize(cross(normal_1, t)) * sign_1;
    vec3 mapped = (texel * 2.0) - 1.0;
    return normalize((((mapped.x * t) + (mapped.y * bitangent)) + (mapped.z * normal_1))) * face;
}
#endif
vec4 materialColorOf() {
#ifdef PBR
#ifdef EMISSIVE
    return materialColor;
#else
    return materialColor;
#endif
#else
#if (defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE)
#ifdef EMISSIVE
    return materialColor;
#else
    return materialColor;
#endif
#else
#ifdef EMISSIVE
    return materialColor;
#else
    return materialColor;
#endif
#endif
#endif
}
vec4 tintedSurface(vec4 color_1) {
    return color_1 * materialColorOf();
}
#ifdef PBR
vec4 pbrOf() {
#ifdef EMISSIVE
    return pbr;
#else
    return pbr;
#endif
}
#endif
#if defined(PBR) && defined(PBR_MAPS)
vec3 pbrMapped(vec2 uv, vec2 occlusionUv) {
    vec4 metalRoughTexel = texture(sampler2D(metalRoughTexture, baseSampler), uv);
    float occluded = texture(sampler2D(occlusionTexture, baseSampler), occlusionUv).r;
    vec4 values = pbrOf();
    return vec3((values.x * metalRoughTexel.b), max((values.y * metalRoughTexel.g), 0.089), (values.z * (1.0 + (values.w * (occluded - 1.0)))));
}
#endif
vec3 srgbToLinear(vec3 srgb) {
    vec3 low = srgb * 0.0773993808;
    vec3 high = pow(max(((srgb * 0.9478672986) + vec3(0.0521327014)), vec3(0.0)), vec3(2.4));
    return vec3(((srgb.x <= 0.04045) ? low.x : high.x), ((srgb.y <= 0.04045) ? low.y : high.y), ((srgb.z <= 0.04045) ? low.z : high.z));
}
vec3 saturated(vec3 rgb, float amount) {
    if (amount == 0.0) {
        return rgb;
    }
    float luma = dot(rgb, vec3(0.212671, 0.71516, 0.072169));
    float keep = amount + 1.0;
    return (rgb * keep) + vec3((luma * (1.0 - keep)));
}
#ifdef SHADOWED
float cascadeDepthOf(vec3 position, vec3 eye, vec4 view) {
    return dot((position - eye), view.xyz);
}
#endif
#ifdef SHADOWED
int cascadeCountOf(vec4 info) {
    return int(info.x + 0.5);
}
#endif
#ifdef SHADOWED
float farOf(vec4 far, int cascade) {
    if (cascade == 0) {
        return far.x;
    }
    if (cascade == 1) {
        return far.y;
    }
    if (cascade == 2) {
        return far.z;
    }
    return far.w;
}
#endif
#ifdef SHADOWED
int cascadeIndexOf(float depth, vec4 far, vec4 info) {
    int count = cascadeCountOf(info);
    for (int i = 0; i < count; i++) {
        if (depth < farOf(far, i)) {
            return i;
        }
    }
    return count;
}
#endif
#ifdef SHADOWED
vec3 cascadeReceiverOf(vec3 position, vec3 normal_1, mat4 matrix, vec4 view, float normalBias) {
    vec3 at = position;
    if (normalBias > 0.0) {
        vec3 across = vec3((matrix * vec4(1.0, 0.0, 0.0, 0.0)).x, (matrix * vec4(0.0, 1.0, 0.0, 0.0)).x, (matrix * vec4(0.0, 0.0, 1.0, 0.0)).x);
        at = position + (normal_1 * (normalBias / (length(across) * view.w)));
    }
    return at;
}
#endif
#ifdef SHADOWED
vec4 mapCoord(vec3 position, mat4 matrix) {
    vec4 q = matrix * vec4(position, 1.0);
    if (q.w <= 0.0) {
        return vec4(0.0, 0.0, 0.0, 0.0);
    }
    vec3 p = q.xyz / q.w;
    if ((((p.x <= 0.0) || (p.x >= 1.0)) || (p.y <= 0.0)) || (p.y >= 1.0)) {
        return vec4(0.0, 0.0, 0.0, 0.0);
    }
    return vec4(p, 1.0);
}
#endif
#ifdef SHADOWED
vec4 cascadeTexelOf(vec3 position, mat4 matrix, vec4 view) {
    vec4 at = mapCoord(position, matrix);
    if (at.w < 0.5) {
        return vec4(0.0, 0.0, 0.0, 0.0);
    }
    int size = int(view.w + 0.5);
    ivec2 texel = clamp(ivec2((at.xy * vec2(float(size)))), ivec2(0, 0), ivec2((size - 1), (size - 1)));
    return vec4(float(texel.x), float(texel.y), at.z, 1.0);
}
#endif
#ifdef SHADOWED
float mapLit(float z, float depth, float bias, float opacity) {
    float lit = ((clamp(z, 0.0, 1.0) - bias) > depth) ? 0.0 : 1.0;
    return mix(1.0, lit, opacity);
}
#endif
#ifdef SHADOWED
float cascadeLitOf(vec4 texel, float stored, vec4 info) {
    if (texel.w < 0.5) {
        return 1.0;
    }
    return mapLit(texel.z, stored, info.z, info.w);
}
#endif
#ifdef SHADOWED
vec2 poissonRotation(vec3 position) {
    float dp = dot(vec4(((position.x + position.y) + position.z)), vec4(12.9898, 78.233, 45.164, 94.673));
    float rotation = (fract((sin(dp) * 43758.5453)) * 3.14) * 2.0;
    return vec2(cos(rotation), sin(rotation));
}
#endif
const int PCF_SAMPLES = 16;
#ifdef SHADOWED
ivec2 pcfTexelOf(vec4 uv, int size, vec2 offset) {
    return clamp(ivec2(((uv.xy * vec2(float(size))) + offset)), ivec2(0, 0), ivec2((size - 1), (size - 1)));
}
#endif
const vec2[16] POISSON_DISK = vec2[16](vec2(-0.94201624, -0.39906216), vec2(0.94558609, -0.76890725), vec2(-0.0941841, -0.9293887), vec2(0.34495938, 0.2938776), vec2(-0.91588581, 0.45771432), vec2(-0.81544232, -0.87912464), vec2(-0.38277543, 0.27676845), vec2(0.97484398, 0.75648379), vec2(0.44323325, -0.97511554), vec2(0.53742981, -0.4737342), vec2(-0.26496911, -0.41893023), vec2(0.79197514, 0.19090188), vec2(-0.2418884, 0.99706507), vec2(-0.81409955, 0.9143759), vec2(0.19984126, 0.78641367), vec2(0.14383161, -0.1410079));
#ifdef SHADOWED
vec2 poissonOffset(int tap, vec2 rotation, float scale) {
    vec2 o = POISSON_DISK[tap] * scale;
    return vec2(((rotation.x * o.x) - (rotation.y * o.y)), ((rotation.x * o.y) + (rotation.y * o.x)));
}
#endif
#ifdef SHADOWED
float cascadeShadowAt(vec3 position, vec3 normal_1, int cascade) {
    vec3 at = cascadeReceiverOf(position, normal_1, cascadeMatrices[cascade], cascadeView, cascadeFilter.y);
    vec4 texel = cascadeTexelOf(at, cascadeMatrices[cascade], cascadeView);
    float scale = cascadeFilter.x;
    float lit = 0.0;
    if ((texel.w < 0.5) || (scale <= 0.0)) {
        float stored = texelFetch(sampler2DArray(shadowMap, shadowSampler), ivec3(ivec2(texel.xy), cascade), 0).x;
        lit = cascadeLitOf(texel, stored, cascadeInfo);
    } else {
        vec4 uv = mapCoord(at, cascadeMatrices[cascade]);
        int size = int(cascadeView.w + 0.5);
        vec2 rotation = poissonRotation(at);
        for (int tap = 0; tap < PCF_SAMPLES; tap++) {
            ivec2 at_1 = pcfTexelOf(uv, size, poissonOffset(tap, rotation, scale));
            float stored_1 = texelFetch(sampler2DArray(shadowMap, shadowSampler), ivec3(at_1, cascade), 0).x;
            lit = lit + cascadeLitOf(texel, stored_1, cascadeInfo);
        }
        lit = lit / float(PCF_SAMPLES);
    }
    return lit;
}
#endif
#ifdef SHADOWED
float cascadeBlendOf(float depth, int cascade, vec4 far, vec4 info) {
    if ((cascade + 1) >= cascadeCountOf(info)) {
        return 0.0;
    }
    float bound = farOf(far, cascade);
    float nextNear = (1.0 - info.y) * bound;
    if (depth < nextNear) {
        return 0.0;
    }
    return (depth - nextNear) / (bound - nextNear);
}
#endif
#ifdef SHADOWED
float dirShadowAt(vec3 position, vec3 normal_1) {
    float depth = cascadeDepthOf(position, cameraPosition.xyz, cascadeView);
    int cascade = cascadeIndexOf(depth, cascadeFar, cascadeInfo);
    if (cascade >= cascadeCountOf(cascadeInfo)) {
        return 1.0;
    }
    float lit = cascadeShadowAt(position, normal_1, cascade);
    float blend = cascadeBlendOf(depth, cascade, cascadeFar, cascadeInfo);
    if (blend > 0.0) {
        return mix(lit, cascadeShadowAt(position, normal_1, (cascade + 1)), blend);
    }
    return lit;
}
#endif
#ifdef PBR
vec3 envTurned(vec3 d, vec4 turn) {
    return vec3(((d.x * turn.z) - (d.z * turn.w)), d.y, ((d.x * turn.w) + (d.z * turn.z)));
}
#endif
#ifdef PBR
vec2 splitSum(float roughness, float nv) {
    float rx = 1.0 - roughness;
    float ry = 0.0425 - (0.0275 * roughness);
    float a004 = (min((rx * rx), exp2((-9.28 * nv))) * rx) + ry;
    return max(vec2((((-1.04 * a004) + 1.04) - (0.572 * roughness)), (((1.04 * a004) - 0.04) + (0.022 * roughness))), vec2(0.00005));
}
#endif
#ifdef PBR
vec3 pbrEnvironmentLight(vec3 albedo, float metalness, float roughness, vec3 normal_1, vec3 view, float occlusion) {
    vec3 n = normalize(normal_1);
    vec3 v = normalize(view);
    float nv = max(dot(n, v), 0.0);
    vec3 f0 = mix(vec3(0.04), albedo, metalness);
    vec3 fresnel = f0 + ((max(vec3((1.0 - roughness)), f0) - f0) * exp2((((-5.55473 * nv) - 6.98316) * nv)));
    vec4 turn = envParams;
    vec3 irradiance = textureLod(samplerCube(envDiffuse, envSampler), envTurned(n, turn), 0.0).rgb;
    vec3 radiance = textureLod(samplerCube(envSpecular, envSampler), envTurned(reflect((-v), n), turn), (roughness * turn.y)).rgb;
    vec2 lut = splitSum(roughness, nv);
    vec3 specular = radiance * ((fresnel * lut.x) + lut.y);
    return ((((irradiance * albedo) * (1.0 - metalness)) * (1.0 - fresnel)) + specular) * (turn.x * occlusion);
}
#endif
#ifdef PBR
vec3 pbrAmbient(vec3 albedo, float metalness, float roughness, vec3 normal_1, vec3 view, vec3 ambient_1, float occlusion) {
    float nv = max(dot(normalize(normal_1), normalize(view)), 0.0);
    vec3 f0 = mix(vec3(0.04), albedo, metalness);
    vec3 fresnel = f0 + ((max(vec3((1.0 - roughness)), f0) - f0) * exp2((((-5.55473 * nv) - 6.98316) * nv)));
    return (((ambient_1 * albedo) * (1.0 - metalness)) * (1.0 - fresnel)) * occlusion;
}
#endif
#ifdef PBR
vec3 pbrDirectSpecular(vec3 albedo, float metalness, float roughness, vec3 normal_1, vec3 view, vec3 light, vec3 specularLight, vec3 radiance, float shadow, float occlusionFactor, float occlusion) {
    if (dot(radiance, radiance) <= 0.0001) {
        return vec3(0.0);
    }
    vec3 n = normalize(normal_1);
    vec3 v = normalize(view);
    vec3 l = normalize(light);
    float nl = clamp(dot(n, l), 0.0, 1.0);
    if (nl <= 0.0) {
        return vec3(0.0);
    }
    vec3 h = normalize((normalize(specularLight) + v));
    float nh = clamp(dot(n, h), 0.0, 1.0);
    float vh = clamp(dot(v, h), 0.0, 1.0);
    float nv = clamp(dot(n, v), 0.0, 1.0);
    float alpha = roughness * roughness;
    float alpha2 = alpha * alpha;
    float denominator = ((nh * nh) * (alpha2 - 1.0)) + 1.0;
    float distribution = alpha2 / ((3.14159265358979 * denominator) * denominator);
    float remapped = roughness + 1.0;
    float k = (remapped * remapped) * 0.125;
    float visibility = ((1.0 / ((nv * (1.0 - k)) + k)) * (1.0 / ((nl * (1.0 - k)) + k))) * 0.25;
    vec3 f0 = mix(vec3(0.04), albedo, metalness);
    vec3 fresnel = f0 + ((1.0 - f0) * exp2((((-5.55473 * vh) - 6.98316) * vh)));
    vec3 specular = max((fresnel * (distribution * visibility)), vec3(0.0));
    vec3 diffuse = ((albedo * (1.0 / 3.14159265358979)) * (1.0 - metalness)) * (1.0 - fresnel);
    float reach = (nl * shadow) * mix(1.0, occlusion, occlusionFactor);
    return ((diffuse + specular) * radiance) * reach;
}
#endif
#ifdef PBR
vec3 pbrDirect(vec3 albedo, float metalness, float roughness, vec3 normal_1, vec3 view, vec3 light, vec3 radiance, float shadow, float occlusionFactor, float occlusion) {
    return pbrDirectSpecular(albedo, metalness, roughness, normal_1, view, light, light, radiance, shadow, occlusionFactor, occlusion);
}
#endif
int cellOf(float position, int cells) {
    if (!(position > 0.0)) {
        return 0;
    }
    if (position >= float(cells)) {
        return cells - 1;
    }
    return int(position);
}
int clusterSliceOf(float depth, vec4 grid, vec4 factors) {
    int slices = int(grid.z + 0.5);
    if (grid.w > 0.5) {
        return cellOf(floor(((depth - factors.z) * factors.w)), slices);
    }
    return cellOf((((log(depth) * factors.z) - factors.w) + 1.0), slices);
}
int clusterAtCell(vec2 cell, float depth, vec4 grid, vec4 factors) {
    int columns = int(grid.x + 0.5);
    int x = cellOf(cell.x, columns);
    int y = cellOf(cell.y, int(grid.y + 0.5));
    return (((y * columns) + x) * int(grid.z + 0.5)) + clusterSliceOf(depth, grid, factors);
}
int clusterIndexOf(vec2 frag, float depth, vec4 grid, vec4 factors) {
    return clusterAtCell((frag * factors.xy), depth, grid, factors);
}
float clusterDepthOf(vec3 position, vec4 view) {
    return dot(position, view.xyz) + view.w;
}
int fragmentClusterOf(vec2 frag, vec3 position, vec4 grid, vec4 factors, vec4 view, vec4 screen) {
    float row = (screen.x > 0.5) ? (screen.y - frag.y) : frag.y;
    return clusterIndexOf(vec2(frag.x, row), clusterDepthOf(position, view), grid, factors);
}
const uint DATA_ROW = 256;
ivec2 dataTexelOf(int i) {
    uint at = uvec2(ivec2(i, 0)).x;
    return ivec2(uvec2((at % DATA_ROW), (at / DATA_ROW)));
}
ivec4 litClusterOf(vec2 frag, vec3 position) {
    int cluster = fragmentClusterOf(frag, position, clusterGrid, clusterFactors, clusterView, clusterScreen);
    return ivec4(texelFetch(usampler2D(clusterRecords, clusterSampler), dataTexelOf(cluster), 0));
}
int indexOfWord(uvec4 texel, int j) {
    ivec4 words = ivec4(texel);
    uint channel = uvec2(ivec2(j, 0)).x % 4;
    if (channel == 0) {
        return words.x;
    }
    if (channel == 1) {
        return words.y;
    }
    if (channel == 2) {
        return words.z;
    }
    return words.w;
}
ivec2 indexTexelOf(int j) {
    return dataTexelOf(ivec2(uvec2((uvec2(ivec2(j, 0)).x / 4), 0)).x);
}
int litLightOf(ivec4 cluster, int k) {
    int j = cluster.x + k;
    return indexOfWord(texelFetch(usampler2D(clusterIndices, clusterSampler), indexTexelOf(j), 0), j);
}
const int RECORD_TEXELS = 6;
ivec2 recordTexelOf(int light, int texel) {
    return dataTexelOf(((light * RECORD_TEXELS) + texel));
}
vec4 litTexelOf(int light, int texel) {
    return texelFetch(sampler2D(lightRecords, clusterSampler), recordTexelOf(light, texel), 0);
}
vec3 cookieAt(vec3 position) {
    vec4 q = cookieMatrix * vec4(position, 1.0);
    if (q.w <= 0.0) {
        return vec3(0.0);
    }
    vec2 uv = q.xy / q.w;
    if ((((uv.x < 0.0) || (uv.x > 1.0)) || (uv.y < 0.0)) || (uv.y > 1.0)) {
        return vec3(0.0);
    }
    vec4 texel = textureLod(sampler2D(cookieTexture, cookieSampler), uv, 0.0);
    return texel.rgb * texel.a;
}
vec4 recordCookieAt(vec3 position, int i) {
    float named = float(i + 1);
    if (cookie.x == named) {
        return vec4(cookieAt(position), 1.0);
    }
    return vec4(1.0, 1.0, 1.0, 0.0);
}
float lightWindow(float distance_1, float range) {
    float window = clamp((1.0 - (distance_1 / range)), 0.0, 1.0);
    return window * window;
}
vec4 cookieSpotSample(vec3 position, vec4 at, vec4 tint) {
    vec3 delta = at.xyz - position;
    float distance_1 = length(delta);
    if (distance_1 < 0.0001) {
        return vec4(0.0);
    }
    return vec4((delta / distance_1), lightWindow(distance_1, tint.a));
}
#ifdef SHADOWED
float spotShadowAt(vec3 position, vec3 normal_1) {
    vec4 receiver = spotReceiver;
    vec3 biased = position + (normal_1 * (receiver.x * length((position - receiver.yzw))));
    vec4 p = mapCoord(biased, spotMatrix);
    if (p.w < 0.5) {
        return 1.0;
    }
    int size = int(spotShadow.z + 0.5);
    float scale = spotShadow.w;
    if (scale <= 0.0) {
        float depth = texelFetch(sampler2DArray(spotShadowMap, spotShadowSampler), ivec3(pcfTexelOf(p, size, vec2(0.0)), 0), 0).x;
        return mapLit(p.z, depth, spotShadow.x, spotShadow.y);
    }
    vec2 rotation = poissonRotation(biased);
    float lit = 0.0;
    for (int tap = 0; tap < PCF_SAMPLES; tap++) {
        ivec2 at = pcfTexelOf(p, size, poissonOffset(tap, rotation, scale));
        float depth_1 = texelFetch(sampler2DArray(spotShadowMap, spotShadowSampler), ivec3(at, 0), 0).x;
        lit = lit + mapLit(p.z, depth_1, spotShadow.x, spotShadow.y);
    }
    return lit / float(PCF_SAMPLES);
}
#endif
#ifdef SHADOWED
int cubeFaceOf(vec3 toPosition) {
    vec3 axes = abs(toPosition);
    if ((axes.x >= axes.y) && (axes.x >= axes.z)) {
        return (toPosition.x > 0.0) ? 0 : 1;
    }
    if (axes.y >= axes.z) {
        return (toPosition.y > 0.0) ? 2 : 3;
    }
    return (toPosition.z > 0.0) ? 4 : 5;
}
#endif
#ifdef SHADOWED
float cubeTapAt(vec3 position) {
    vec3 toPosition = position - cubeLight.xyz;
    int face = cubeFaceOf(toPosition);
    vec4 p = mapCoord(position, cubeMatrices[face]);
    if (p.w < 0.5) {
        return 1.0;
    }
    int size = int(cubeShadow.z + 0.5);
    float depth = texelFetch(sampler2DArray(cubeShadowMap, spotShadowSampler), ivec3(pcfTexelOf(p, size, vec2(0.0)), face), 0).x;
    float near = cubeRange.x;
    float far = cubeRange.y;
    vec3 axes = abs(toPosition);
    float axis = max(axes.x, max(axes.y, axes.z));
    float distance_1 = length(toPosition);
    float stored = ((near * far) / (far - (depth * (far - near)))) * (distance_1 / axis);
    return mapLit((distance_1 / far), (stored / far), (cubeShadow.x / far), cubeShadow.y);
}
#endif
const int CUBE_PCF_SAMPLES = 20;
const vec3[20] CUBE_PCF_OFFSETS = vec3[20](vec3(1.0, 1.0, 1.0), vec3(1.0, -1.0, 1.0), vec3(-1.0, -1.0, 1.0), vec3(-1.0, 1.0, 1.0), vec3(1.0, 1.0, -1.0), vec3(1.0, -1.0, -1.0), vec3(-1.0, -1.0, -1.0), vec3(-1.0, 1.0, -1.0), vec3(1.0, 1.0, 0.0), vec3(1.0, -1.0, 0.0), vec3(-1.0, -1.0, 0.0), vec3(-1.0, 1.0, 0.0), vec3(1.0, 0.0, 1.0), vec3(-1.0, 0.0, 1.0), vec3(1.0, 0.0, -1.0), vec3(-1.0, 0.0, -1.0), vec3(0.0, 1.0, 1.0), vec3(0.0, -1.0, 1.0), vec3(0.0, -1.0, -1.0), vec3(0.0, 1.0, -1.0));
#ifdef SHADOWED
float cubeShadowAt(vec3 position, vec3 normal_1) {
    float scale = cubeShadow.w / cubeShadow.z;
    vec3 light = cubeLight.xyz;
    vec3 at = position + (normal_1 * (cubeRange.z * length((position - light))));
    vec3 toPosition = at - light;
    float distance_1 = length(toPosition);
    float lit = 0.0;
    if ((!(scale > 0.0)) || (!(distance_1 > 0.0))) {
        lit = cubeTapAt(at);
    } else {
        vec3 direction = toPosition / distance_1;
        for (int tap = 0; tap < CUBE_PCF_SAMPLES; tap++) {
            vec3 turned = normalize((direction + (CUBE_PCF_OFFSETS[tap] * scale)));
            lit = lit + cubeTapAt((light + (turned * distance_1)));
        }
        lit = lit / float(CUBE_PCF_SAMPLES);
    }
    return lit;
}
#endif
float recordShadowAt(vec3 position, vec3 normal_1, int i) {
    float lit = 1.0;
#ifdef SHADOWED
    float named = float(i + 1);
    if (ambient.w == named) {
        lit = spotShadowAt(position, normal_1);
    } else if (dirColor.w == named) {
        lit = cubeShadowAt(position, normal_1);
    }
#endif
    return lit;
}
vec4 capsuleSample(vec3 position, vec4 at, vec4 tint, vec4 a, vec4 b) {
    vec3 start = at.xyz - (a.xyz * b.x);
    vec3 segment = a.xyz * (2.0 * b.x);
    float along = clamp((dot((position - start), segment) / dot(segment, segment)), 0.0, 1.0);
    vec3 delta = (start + (segment * along)) - position;
    float distance_1 = length(delta);
    if (distance_1 < 0.0001) {
        return vec4(0.0);
    }
    return vec4((delta / distance_1), lightWindow(distance_1, tint.a));
}
vec3 rectanglePoint(vec3 position, vec3 ray, vec4 at, vec4 a, vec4 b, vec4 c) {
    float along = dot(a.xyz, (at.xyz - position)) / dot(a.xyz, ray);
    vec3 offset = (position + (ray * along)) - at.xyz;
    return (at.xyz + (b.xyz * clamp(dot(offset, b.xyz), (-b.w), b.w))) + (c.xyz * clamp(dot(offset, c.xyz), (-c.w), c.w));
}
float rectangleAxisCone(vec3 delta, vec3 forward, vec3 excluded, float outer, float inner) {
    vec3 projectedDelta = delta - (excluded * dot(delta, excluded));
    vec3 projectedLight = (-forward) - (excluded * dot((-forward), excluded));
    float deltaLength = length(projectedDelta);
    float lightLength = length(projectedLight);
    if ((deltaLength < 0.0001) || (lightLength < 0.0001)) {
        return 0.0;
    }
    float theta = dot(projectedDelta, projectedLight) / (deltaLength * lightLength);
    return clamp(((theta - outer) / ((inner - outer) + 0.00001)), 0.0, 1.0);
}
vec4 rectangleSample(vec3 position, vec3 normal_1, vec4 at, vec4 tint, vec4 a, vec4 b, vec4 c, vec4 d) {
    if (abs(dot(a.xyz, normal_1)) < 0.000001) {
        return vec4(0.0);
    }
    vec3 delta = rectanglePoint(position, normal_1, at, a, b, c) - position;
    float distance_1 = length(delta);
    if (distance_1 < 0.0001) {
        return vec4(0.0);
    }
    float cone = rectangleAxisCone(delta, a.xyz, c.xyz, d.x, d.y) * rectangleAxisCone(delta, a.xyz, b.xyz, d.z, d.w);
    return vec4((delta / distance_1), (lightWindow(distance_1, tint.a) * cone));
}
vec4 spotSample(vec3 position, vec4 at, vec4 tint, vec4 a, vec4 b) {
    vec3 delta = at.xyz - position;
    float distance_1 = length(delta);
    if (distance_1 < 0.0001) {
        return vec4(0.0);
    }
    vec3 toLight = delta / distance_1;
    float cone = clamp(((dot(toLight, (-a.xyz)) - b.x) / (b.y - b.x)), 0.0, 1.0);
    return vec4(toLight, (lightWindow(distance_1, tint.a) * cone));
}
vec4 shapedSample(vec3 position, vec3 normal_1, vec4 at, vec4 tint, vec4 a, vec4 b, vec4 c, vec4 d) {
    if (a.w > 2.5) {
        return capsuleSample(position, at, tint, a, b);
    }
    if (a.w > 1.5) {
        return rectangleSample(position, normal_1, at, tint, a, b, c, d);
    }
    return spotSample(position, at, tint, a, b);
}
#ifdef PBR
vec3 capsuleSpecularDir(vec3 position, vec3 reflected, vec3 diffuse, vec4 at, vec4 a, vec4 b) {
    vec3 l0 = (at.xyz - (a.xyz * b.x)) - position;
    vec3 l01 = a.xyz * (2.0 * b.x);
    float squared = dot(l01, l01);
    float alongRay = dot(reflected, l01);
    float denominator = squared - (alongRay * alongRay);
    if (denominator <= 0.000001) {
        return diffuse;
    }
    vec3 closest = l0 + (l01 * clamp((dot(l0, ((reflected * alongRay) - l01)) / denominator), 0.0, 1.0));
    vec3 centerToRay = (reflected * dot(closest, reflected)) - closest;
    float offset = length(centerToRay);
    if (offset < 0.000001) {
        return normalize(closest);
    }
    return normalize((closest + (centerToRay * clamp((b.y / offset), 0.0, 1.0))));
}
#endif
#ifdef PBR
vec3 rectangleSpecularDir(vec3 position, vec3 reflected, vec3 diffuse, vec4 at, vec4 a, vec4 b, vec4 c) {
    if (abs(dot(a.xyz, reflected)) < 0.000001) {
        return diffuse;
    }
    return normalize((rectanglePoint(position, reflected, at, a, b, c) - position));
}
#endif
#ifdef PBR
vec3 shapedSpecularDir(vec3 position, vec3 reflected, vec3 diffuse, vec4 at, vec4 a, vec4 b, vec4 c) {
    if (a.w > 2.5) {
        return capsuleSpecularDir(position, reflected, diffuse, at, a, b);
    }
    if (a.w > 1.5) {
        return rectangleSpecularDir(position, reflected, diffuse, at, a, b, c);
    }
    return diffuse;
}
#endif
vec3 linearToSrgb(vec3 rgb) {
    vec3 low = rgb * 12.92;
    vec3 high = (vec3(1.055) * pow(max(rgb, vec3(0.0)), vec3(0.41666))) - vec3(0.055);
    return vec3(((rgb.x <= 0.0031308) ? low.x : high.x), ((rgb.y <= 0.0031308) ? low.y : high.y), ((rgb.z <= 0.0031308) ? low.z : high.z));
}
#ifdef PBR
vec4 pbrShade(vec3 n, vec3 surfaceNormal, vec3 position, vec2 frag, vec4 surfaceColor, vec3 values) {
    vec3 albedo = srgbToLinear(saturated(surfaceColor.rgb, materialOf().y));
    vec3 view = cameraPosition.xyz - position;
    vec4 dir = dirLight;
    float shadow = 1.0;
#ifdef SHADOWED
    shadow = dirShadowAt(position, surfaceNormal);
#endif
    vec3 sun = srgbToLinear(dirColor.rgb) * dir.w;
    vec3 light = vec3(0.0);
    if (envParams.x > 0.0) {
        light = pbrEnvironmentLight(albedo, values.x, values.y, n, view, values.z);
    } else {
        light = pbrAmbient(albedo, values.x, values.y, n, view, srgbToLinear(ambient.rgb), values.z);
    }
    light = light + pbrDirect(albedo, values.x, values.y, n, view, dir.xyz, sun, shadow, 0.0, values.z);
    vec3 eye = normalize(view);
    vec3 reflected = (-eye) - (n * (2.0 * dot((-eye), n)));
    ivec4 cluster = litClusterOf(frag, position);
    for (int k = 0; k < (cluster.y + cluster.z); k++) {
        int i = litLightOf(cluster, k);
        vec4 at = litTexelOf(i, 0);
        vec4 tint = litTexelOf(i, 1);
        vec4 a = litTexelOf(i, 2);
        vec4 bb = litTexelOf(i, 3);
        vec4 cookie_1 = recordCookieAt(position, i);
        if (cookie_1.w > 0.5) {
            vec4 sample_1 = cookieSpotSample(position, at, tint);
            vec3 radiance = (srgbToLinear(tint.rgb) * cookie_1.rgb) * (sample_1.w * at.w);
            light = light + pbrDirectSpecular(albedo, values.x, values.y, n, view, sample_1.xyz, sample_1.xyz, radiance, recordShadowAt(position, surfaceNormal, i), 0.0, values.z);
        } else if (a.w < 0.5) {
            vec3 toLight = at.xyz - position;
            float falloff = clamp((1.0 - (length(toLight) / tint.a)), 0.0, 1.0);
            vec3 radiance_1 = srgbToLinear(tint.rgb) * ((falloff * falloff) * at.w);
            light = light + pbrDirect(albedo, values.x, values.y, n, view, toLight, radiance_1, recordShadowAt(position, surfaceNormal, i), 0.0, values.z);
        } else {
            vec4 cc = litTexelOf(i, 4);
            vec4 sample_2 = shapedSample(position, n, at, tint, a, bb, cc, litTexelOf(i, 5));
            vec3 radiance_2 = srgbToLinear(tint.rgb) * (sample_2.w * at.w);
            vec3 specular = shapedSpecularDir(position, reflected, sample_2.xyz, at, a, bb, cc);
            light = light + pbrDirectSpecular(albedo, values.x, values.y, n, view, sample_2.xyz, specular, radiance_2, recordShadowAt(position, surfaceNormal, i), 0.0, values.z);
        }
    }
    return vec4(linearToSrgb(light), surfaceColor.a);
}
#endif
#ifndef PBR
vec3 pointLightAt(vec3 position, vec3 normal_1, vec4 at, vec4 tint) {
    vec3 toLight = at.xyz - position;
    float distance_1 = length(toLight);
    float falloff = clamp((1.0 - (distance_1 / tint.a)), 0.0, 1.0);
    float facing = max(dot(normal_1, (toLight / max(distance_1, 0.0001))), 0.0);
    return srgbToLinear(tint.rgb) * (((falloff * falloff) * facing) * at.w);
}
#endif
#ifndef PBR
vec3 lightAt(vec3 position, vec3 normal_1, vec4 at, vec4 tint, vec4 a, vec4 b, vec4 c, vec4 d) {
    vec3 lit = vec3(0.0);
    if (a.w < 0.5) {
        lit = pointLightAt(position, normal_1, at, tint);
    } else {
        vec4 sample_1 = shapedSample(position, normal_1, at, tint, a, b, c, d);
        lit = srgbToLinear(tint.rgb) * ((sample_1.w * max(dot(normal_1, sample_1.xyz), 0.0)) * at.w);
    }
    return lit;
}
#endif
#ifndef PBR
vec4 litShade(vec3 n, vec3 surfaceNormal, vec3 position, vec2 frag, vec4 surfaceColor) {
    vec4 dir = dirLight;
    float lambert = max(dot(n, dir.xyz), 0.0) * dir.w;
#ifdef SHADOWED
    lambert = lambert * dirShadowAt(position, surfaceNormal);
#endif
    vec3 ambient_1 = srgbToLinear(ambient.rgb);
    vec3 light = ambient_1 + (srgbToLinear(dirColor.rgb) * lambert);
    ivec4 cluster = litClusterOf(frag, position);
    for (int k = 0; k < (cluster.y + cluster.z); k++) {
        int i = litLightOf(cluster, k);
        vec4 at = litTexelOf(i, 0);
        vec4 tint = litTexelOf(i, 1);
        vec4 cookie_1 = recordCookieAt(position, i);
        vec3 lit = vec3(0.0);
        if (cookie_1.w > 0.5) {
            vec4 sample_1 = cookieSpotSample(position, at, tint);
            lit = (srgbToLinear(tint.rgb) * cookie_1.rgb) * ((sample_1.w * max(dot(n, sample_1.xyz), 0.0)) * at.w);
        } else {
            lit = lightAt(position, n, at, tint, litTexelOf(i, 2), litTexelOf(i, 3), litTexelOf(i, 4), litTexelOf(i, 5));
        }
        light = light + (lit * recordShadowAt(position, surfaceNormal, i));
    }
    vec3 surface = srgbToLinear(saturated(surfaceColor.rgb, materialOf().y));
    return vec4(linearToSrgb((surface * light)), surfaceColor.a);
}
#endif
#ifdef EMISSIVE
vec4 emittedOver(vec4 color_1, vec3 texel, vec4 emissive_1) {
    vec3 emitted = (srgbToLinear(emissive_1.rgb) * srgbToLinear(texel)) * emissive_1.a;
    return vec4(linearToSrgb((srgbToLinear(color_1.rgb) + emitted)), color_1.a);
}
#endif
#ifdef EMISSIVE
vec4 emissiveOf() {
#ifdef PBR
    return emissive;
#else
#if (defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE)
    return emissive;
#else
    return emissive;
#endif
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
#if defined(UV_TRANSFORM) || defined(PBR)
    float time = frame.x;
    uv = movedUv(surfaceUv, uvMatrixOf(), uvMotionOf(), time);
#endif
#if defined(NORMAL_MAP) && defined(PARALLAX)
    vec3 view = normalize((cameraPosition.xyz - worldPosition));
    uv = parallaxUv(uv, view, normalize(worldNormal), worldTangent, materialOf().x, parallaxStepsOf());
#endif
    vec2 baseUv = uv;
    vec2 nextUv = uv;
    float blend = 0.0;
#ifdef UV_TRANSFORM
    vec4 grid = flipbookGridOf();
    vec4 play = flipbookPlayOf();
    if (grid.z > 0.0) {
        float time_1 = frame.x;
        vec4 frames = flipbookUvs(uv, grid, play, time_1);
        baseUv = frames.xy;
        nextUv = frames.zw;
        blend = flipbookBlend(grid, play, time_1);
    }
#endif
    vec4 texel = texture(sampler2D(baseTexture, baseSampler), baseUv);
    if (blend > 0.0) {
        texel = mix(texel, texture(sampler2D(baseTexture, baseSampler), nextUv), blend);
    }
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
    vec3 surfaceNormal = facingNormal(normalize(worldNormal), params.z, gl_FrontFacing);
    vec3 n = surfaceNormal;
#ifdef NORMAL_MAP
    vec3 normalTexel = texture(sampler2D(normalTexture, baseSampler), uv).rgb;
    float face = faceOf(params.z, gl_FrontFacing);
    n = mappedNormal(normalize(worldNormal), worldTangent, face, normalTexel);
#endif
    vec4 surfaceColor = tintedSurface(vec4((baseColor.rgb * texel.rgb), (baseColor.a * texel.a)));
    vec4 shaded = vec4(0.0);
#ifdef PBR
    vec3 pbrValues = pbrOf().xyz;
#ifdef PBR_MAPS
    vec2 occlusionUv = uv;
#ifdef OCCLUSION_UV_B
    occlusionUv = movedUv(surfaceUvB, uvMatrixOf(), uvMotionOf(), frame.x);
#endif
    pbrValues = pbrMapped(uv, occlusionUv);
#endif
    shaded = pbrShade(n, surfaceNormal, worldPosition, gl_FragCoord.xy, surfaceColor, pbrValues);
#else
    shaded = litShade(n, surfaceNormal, worldPosition, gl_FragCoord.xy, surfaceColor);
#endif
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
#if defined(CUTOUT) && !defined(PBR) && !((defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE)) && !defined(EMISSIVE)
layout(binding=3) uniform materialParams {
    vec4 material;
    vec4 materialColor;
};
#endif
#if (defined(DISSOLVE) && !defined(EMISSIVE)) || (defined(CUTOUT) && !defined(PBR) && ((defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE)) && !defined(EMISSIVE))
layout(binding=3) uniform movingMaterialParams {
    vec4 material;
    vec4 materialColor;
    vec4 uvMatrix;
    vec4 uvMotion;
    vec4 backUvMatrix;
    vec4 backUvOffset;
    vec4 dissolve;
    vec4 dissolveEdge;
    vec4 flipbookGrid;
    vec4 flipbookPlay;
};
#endif
#if defined(CUTOUT) && !defined(PBR) && !((defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE)) && defined(EMISSIVE)
layout(binding=3) uniform emissiveMaterialParams {
    vec4 material;
    vec4 materialColor;
    vec4 emissive;
};
#endif
#if (defined(DISSOLVE) && defined(EMISSIVE)) || (defined(CUTOUT) && !defined(PBR) && ((defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE)) && defined(EMISSIVE))
layout(binding=3) uniform movingEmissiveMaterialParams {
    vec4 material;
    vec4 materialColor;
    vec4 uvMatrix;
    vec4 uvMotion;
    vec4 backUvMatrix;
    vec4 backUvOffset;
    vec4 dissolve;
    vec4 dissolveEdge;
    vec4 flipbookGrid;
    vec4 flipbookPlay;
    vec4 emissive;
};
#endif
#if defined(CUTOUT) && defined(PBR) && !defined(EMISSIVE)
layout(binding=3) uniform pbrMaterialParams {
    vec4 material;
    vec4 materialColor;
    vec4 pbr;
    vec4 uvMatrix;
    vec4 uvMotion;
    vec4 parallax;
};
#endif
#if defined(CUTOUT) && defined(PBR) && defined(EMISSIVE)
layout(binding=3) uniform pbrEmissiveMaterialParams {
    vec4 material;
    vec4 materialColor;
    vec4 pbr;
    vec4 uvMatrix;
    vec4 uvMotion;
    vec4 parallax;
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
#ifdef OCCLUSION_UV_B
in vec2 surfaceUvB;
#endif
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
vec4 materialColorOf() {
#ifdef PBR
#ifdef EMISSIVE
    return materialColor;
#else
    return materialColor;
#endif
#else
#if (defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE)
#ifdef EMISSIVE
    return materialColor;
#else
    return materialColor;
#endif
#else
#ifdef EMISSIVE
    return materialColor;
#else
    return materialColor;
#endif
#endif
#endif
}
#endif
#ifdef CUTOUT
vec4 materialOf() {
#ifdef PBR
#ifdef EMISSIVE
    return material;
#else
    return material;
#endif
#else
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
    vec4 tint = materialColorOf();
    if (((baseColor.a * tint.a) * texel.a) < materialOf().w) {
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
    vec4 cameraPosition;
};
#ifdef SKINNED
layout(binding=7) uniform skinParams {
    vec4 skinRows[192];
};
#endif
in vec3 position;
in vec3 normal;
in vec2 uv;
in vec4 color;
#ifdef NORMAL_MAP
in vec4 tangent;
#endif
#ifdef OCCLUSION_UV_B
in vec2 uvB;
#endif
#ifdef SKINNED
in vec4 skinJoints;
#endif
#ifdef SKINNED
in vec4 skinWeights;
#endif
in vec4 instanceRow0;
in vec4 instanceRow1;
in vec4 instanceRow2;
in vec4 instanceColor;
#ifdef NORMAL_MRT
out vec3 worldNormal;
#endif
out vec2 surfaceUv;
out vec4 baseColor;
#ifdef SKINNED
vec4 skinRow(vec4 joints, vec4 weights, int column) {
    return (((skinRows[(int(joints.x) * 3) + column] * weights.x) + (skinRows[(int(joints.y) * 3) + column] * weights.y)) + (skinRows[(int(joints.z) * 3) + column] * weights.z)) + (skinRows[(int(joints.w) * 3) + column] * weights.w);
}
#endif
#ifdef SKINNED
mat4 skinWorld(vec4 joints, vec4 weights) {
    return transpose(mat4(skinRow(joints, weights, 0), skinRow(joints, weights, 1), skinRow(joints, weights, 2), vec4(0.0, 0.0, 0.0, 1.0)));
}
#endif
#ifdef NORMAL_MRT
vec3 skinNormal(mat4 world, vec3 normal_1) {
    mat3 linear = mat3(world);
    vec3 a = cross(linear[1], linear[2]);
    vec3 b = cross(linear[2], linear[0]);
    vec3 c = cross(linear[0], linear[1]);
    float direction = (dot(linear[0], a) < 0.0) ? -1.0 : 1.0;
    return (((a * normal_1.x) + (b * normal_1.y)) + (c * normal_1.z)) * direction;
}
#endif
#ifndef SKINNED
mat4 instanceWorld(vec4 row0, vec4 row1, vec4 row2) {
    return transpose(mat4(row0, row1, row2, vec4(0.0, 0.0, 0.0, 1.0)));
}
#endif
void main() {
#ifdef SKINNED
    mat4 matrix = skinWorld(skinJoints, skinWeights);
    gl_Position = ((viewProj * matrix) * vec4(position, 1.0));
#ifdef NORMAL_MRT
    worldNormal = skinNormal(matrix, normal);
#endif
    surfaceUv = uv;
    baseColor = color;
    return;
#else
    mat4 matrix_1 = instanceWorld(instanceRow0, instanceRow1, instanceRow2);
    gl_Position = ((viewProj * matrix_1) * vec4(position, 1.0));
#ifdef NORMAL_MRT
    worldNormal = skinNormal(matrix_1, normal);
#endif
    surfaceUv = uv;
    baseColor = (color * instanceColor);
    return;
#endif
}
@end

@fs unlitTexturedFs
#if !((defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE))
layout(binding=3) uniform unlitMaterialParams {
    vec4 material;
    vec4 materialColor;
};
#endif
#if (defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE)
layout(binding=3) uniform movingUnlitMaterialParams {
    vec4 material;
    vec4 materialColor;
    vec4 uvMatrix;
    vec4 uvMotion;
    vec4 backUvMatrix;
    vec4 backUvOffset;
    vec4 dissolve;
    vec4 dissolveEdge;
    vec4 flipbookGrid;
    vec4 flipbookPlay;
};
#endif
layout(binding=6) uniform frameParams {
    vec4 frame;
    vec4 cameraPosition;
    vec4 envParams;
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
#ifdef UV_TRANSFORM
vec4 flipbookUvs(vec2 uv, vec4 grid, vec4 play, float time) {
    float frame_1 = floor((((time - play.x) * grid.w) + trunc(play.y)));
    float looped = frame_1 - (grid.z * floor((frame_1 / grid.z)));
    float nextLooped = (looped + 1.0) - (grid.z * floor(((looped + 1.0) / grid.z)));
    float at = (play.z == 1.0) ? looped : min(frame_1, (grid.z - 1.0));
    float next = (play.z == 1.0) ? nextLooped : min((frame_1 + 1.0), (grid.z - 1.0));
    vec2 cell = uv / grid.xy;
    vec2 atCell = vec2((at - (grid.x * floor((at / grid.x)))), trunc((at / grid.x))) / grid.xy;
    vec2 nextCell = vec2((next - (grid.x * floor((next / grid.x)))), trunc((next / grid.x))) / grid.xy;
    return vec4((cell + atCell), (cell + nextCell));
}
#endif
#ifdef UV_TRANSFORM
float flipbookBlend(vec4 grid, vec4 play, float time) {
    return (play.w == 1.0) ? fract((((time - play.x) * grid.w) + trunc(play.y))) : 0.0;
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
    vec2 baseUv = uv;
    vec2 nextUv = uv;
    float blend = 0.0;
#ifdef UV_TRANSFORM
    vec4 grid = flipbookGrid;
    vec4 play = flipbookPlay;
    if (grid.z > 0.0) {
        float time = frame.x;
        vec4 frames = flipbookUvs(uv, grid, play, time);
        baseUv = frames.xy;
        nextUv = frames.zw;
        blend = flipbookBlend(grid, play, time);
    }
#endif
    vec4 texel = texture(sampler2D(baseTexture, baseSampler), baseUv);
    if (blend > 0.0) {
        texel = mix(texel, texture(sampler2D(baseTexture, baseSampler), nextUv), blend);
    }
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
#if defined(CUTOUT) && !((defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE))
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
    vec4 flipbookGrid;
    vec4 flipbookPlay;
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

@vs decalVs
layout(binding=0) uniform vertexParams {
    mat4 viewProj;
    vec4 cameraRight;
    vec4 cameraUp;
    vec4 cameraPosition;
};
in vec3 position;
in vec3 normal;
in vec4 color;
#ifdef SKINNED
in vec4 skinJoints;
#endif
#ifdef SKINNED
in vec4 skinWeights;
#endif
in vec4 instanceRow0;
in vec4 instanceRow1;
in vec4 instanceRow2;
in vec4 instanceColor;
out vec4 screenToLocal0;
out vec4 screenToLocal1;
out vec4 screenToLocal2;
out vec4 screenToLocal3;
out vec4 boxWorld0;
out vec4 boxWorld1;
out vec4 boxWorld2;
out vec4 boxWorld3;
out vec4 baseColor;
out vec4 screen;
mat4 instanceWorld(vec4 row0, vec4 row1, vec4 row2) {
    return transpose(mat4(row0, row1, row2, vec4(0.0, 0.0, 0.0, 1.0)));
}
void main() {
    mat4 world = instanceWorld(instanceRow0, instanceRow1, instanceRow2);
    vec4 clip = (viewProj * world) * vec4(position, 1.0);
    mat4 toLocal = inverse(world) * inverse(viewProj);
    screenToLocal0 = toLocal[0];
    screenToLocal1 = toLocal[1];
    screenToLocal2 = toLocal[2];
    screenToLocal3 = toLocal[3];
    boxWorld0 = world[0];
    boxWorld1 = world[1];
    boxWorld2 = world[2];
    boxWorld3 = world[3];
    baseColor = (color * instanceColor);
    screen = clip;
    gl_Position = clip;
    return;
}
@end

@fs decalFs
layout(binding=3) uniform decalParams {
    vec4 decalColor;
    vec4 decalFade;
    vec4 decalMode;
    vec4 decalNormalFade;
};
layout(binding=6) uniform frameParams {
    vec4 frame;
    vec4 cameraPosition;
    vec4 envParams;
};
layout(binding=0) uniform texture2D decalTexture;
layout(binding=0) uniform sampler decalSampler;
@image_sample_type sceneDepth unfilterable_float
layout(binding=14) uniform texture2D sceneDepth;
@sampler_type sceneDepthSampler nonfiltering
layout(binding=7) uniform sampler sceneDepthSampler;
in vec4 screenToLocal0;
in vec4 screenToLocal1;
in vec4 screenToLocal2;
in vec4 screenToLocal3;
in vec4 boxWorld0;
in vec4 boxWorld1;
in vec4 boxWorld2;
in vec4 boxWorld3;
in vec4 baseColor;
in vec4 screen;
layout(location=0) out vec4 fragColor;
vec3 decalLocalAt(vec2 screen_1, float depth, mat4 screenToLocal) {
    vec4 local = screenToLocal * vec4(screen_1.x, screen_1.y, depth, 1.0);
    return local.xyz / local.w;
}
float ndcDepthOf(float stored, float zeroToOne) {
    return (zeroToOne == 1.0) ? stored : ((stored * 2.0) - 1.0);
}
vec3 decalLocalAtPixel(ivec2 pixel, vec2 ndc, mat4 toLocal) {
    float stored = texelFetch(sampler2D(sceneDepth, sceneDepthSampler), pixel, 0).x;
    return decalLocalAt(ndc, ndcDepthOf(stored, cameraPosition.w), toLocal);
}
bool outsideDecal(vec3 local) {
    return ((abs(local.x) > 0.5) || (abs(local.y) > 0.5)) || (abs(local.z) > 0.5);
}
float decalFade_1(float z, float start, float end, float power) {
    return 1.0 - clamp(pow((max(0.0, (abs((z * 2.0)) - start)) / (end - start)), power), 0.0, 1.0);
}
vec3 decalSurfaceNormal(vec3 at, vec3 alongX, vec3 alongY, vec3 eye) {
    vec3 n = normalize(cross((alongY - at), (alongX - at)));
    return (dot(n, (eye - at)) < 0.0) ? (n * -1.0) : n;
}
float decalNormalFade_1(vec3 boxZ, vec3 normal, float start, float end) {
    float angle = 1.0 - (abs(acos(clamp(dot(boxZ, normal), -1.0, 1.0))) / 3.14159265358979);
    return clamp(((angle - start) / (end - start)), 0.0, 1.0);
}
vec4 decalOverlayColor(vec4 tint, vec4 texel, float emissive, bool gammaCorrect, bool autoAlpha, float fade) {
    vec3 rgb = tint.rgb * texel.rgb;
    if (gammaCorrect) {
        rgb = rgb * rgb;
    }
    rgb = rgb + (rgb * emissive);
    float alpha = autoAlpha ? clamp(max(max(rgb.r, rgb.g), rgb.b), 0.0, 1.0) : texel.a;
    return vec4(rgb, (alpha * fade));
}
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
        vec3 color = exposed - offset;
        float peak = max(color.x, max(color.y, color.z));
        if (peak >= startCompression) {
            float d = 1.0 - startCompression;
            float newPeak = 1.0 - ((d * d) / ((peak + d) - startCompression));
            color = color * (newPeak / peak);
            float g = 1.0 - (1.0 / ((desaturation * (peak - newPeak)) + 1.0));
            color = mix(color, vec3(newPeak), g);
        }
        return color;
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
    vec2 ndc = screen.xy / screen.w;
    vec2 ndcDx = dFdx(ndc);
    vec2 ndcDy = dFdy(ndc);
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    mat4 toLocal = mat4(screenToLocal0, screenToLocal1, screenToLocal2, screenToLocal3);
    vec3 local = decalLocalAtPixel(pixel, ndc, toLocal);
    if (outsideDecal(local)) {
        discard;
    }
    vec4 fade = decalFade;
    vec4 mode = decalMode;
    float faded = decalFade_1(local.z, fade.x, fade.y, fade.z);
    vec4 normalFade = decalNormalFade;
    if (normalFade.z == 1.0) {
        mat4 world = mat4(boxWorld0, boxWorld1, boxWorld2, boxWorld3);
        ivec2 last = textureSize(sampler2D(sceneDepth, sceneDepthSampler), 0) - ivec2(1, 1);
        ivec2 right = clamp((pixel + ivec2(1, 0)), ivec2(0, 0), last);
        ivec2 below = clamp((pixel + ivec2(0, 1)), ivec2(0, 0), last);
        vec3 alongX = decalLocalAtPixel(right, (ndc + ndcDx), toLocal);
        vec3 alongY = decalLocalAtPixel(below, (ndc + ndcDy), toLocal);
        vec3 normal = decalSurfaceNormal((world * vec4(local, 1.0)).xyz, (world * vec4(alongX, 1.0)).xyz, (world * vec4(alongY, 1.0)).xyz, cameraPosition.xyz);
        faded = faded * decalNormalFade_1(normalize(world[2].xyz), normal, normalFade.x, normalFade.y);
    }
    vec2 uv = (mode.x == 1.0) ? (local.xy + vec2(0.5, 0.5)) : local.xy;
    vec4 texel = texture(sampler2D(decalTexture, decalSampler), uv);
    vec4 tint = decalColor * baseColor;
    vec4 shaded = decalOverlayColor(tint, texel, fade.w, (mode.y == 1.0), (mode.z == 1.0), faded);
    vec3 rgb = (mode.w == 1.0) ? toneMapped(shaded.rgb, frame) : shaded.rgb;
    fragColor = vec4(rgb, shaded.a);
    return;
}
@end

@vs lineVs
layout(binding=0) uniform vertexParams {
    mat4 viewProj;
    vec4 cameraRight;
    vec4 cameraUp;
    vec4 cameraPosition;
};
layout(binding=3) uniform lineParams {
    vec4 lineShape;
    vec4 lineDepth;
    vec4 lineColor;
};
in vec3 position;
in vec3 normal;
in vec2 uv;
in vec4 color;
#ifdef NORMAL_MAP
in vec4 tangent;
#endif
#ifdef OCCLUSION_UV_B
in vec2 uvB;
#endif
#ifdef SKINNED
in vec4 skinJoints;
#endif
#ifdef SKINNED
in vec4 skinWeights;
#endif
in vec4 instanceRow0;
in vec4 instanceRow1;
in vec4 instanceRow2;
in vec4 instanceColor;
out vec4 baseColor;
mat4 instanceWorld(vec4 row0, vec4 row1, vec4 row2) {
    return transpose(mat4(row0, row1, row2, vec4(0.0, 0.0, 0.0, 1.0)));
}
vec2 lineScreenDirection(vec3 direction, vec4 right, vec4 up) {
    vec2 projected = vec2((dot(direction, right.xyz) * right.w), (dot(direction, up.xyz) * up.w));
    return projected * (1.0 / length(projected));
}
float lineViewDepth(float depth, float zNear, float zFar) {
    return ((2.0 * zNear) * zFar) / ((zFar + zNear) - (((2.0 * depth) - 1.0) * (zFar - zNear)));
}
vec2 lineClipOffset(vec2 screenDirection, float side, float viewDepth, vec2 pixelSize, float width) {
    return (vec2(screenDirection.y, (-screenDirection.x)) * pixelSize) * (((side - 0.5) * viewDepth) * width);
}
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
vec4 unlitShade(vec4 texel, vec4 baseColor_1, vec4 materialColor) {
    vec3 surface = srgbToLinear(baseColor_1.rgb) * srgbToLinear(materialColor.rgb);
    surface = surface * srgbToLinear(texel.rgb);
    return vec4(linearToSrgb(surface), ((baseColor_1.a * materialColor.a) * texel.a));
}
void main() {
    mat4 matrix = instanceWorld(instanceRow0, instanceRow1, instanceRow2);
    vec4 shape = lineShape;
    vec4 depthRange = lineDepth;
    vec3 direction = mat3(matrix) * normal;
    vec4 root = matrix * vec4(position, 1.0);
    vec3 world = root.xyz + (direction * (uv.x * shape.y));
    vec4 clip = viewProj * vec4(world, 1.0);
    vec2 across = lineScreenDirection(direction, cameraRight, cameraUp);
    float depth = lineViewDepth((clip.z / clip.w), depthRange.x, depthRange.y);
    vec2 offset = lineClipOffset(across, uv.y, depth, shape.zw, shape.x);
    vec4 color_1 = color * instanceColor;
    baseColor = unlitShade(vec4(1.0, 1.0, 1.0, 1.0), color_1, lineColor);
    gl_Position = vec4((clip.xy + offset), clip.z, clip.w);
    return;
}
@end

@fs lineFs
layout(binding=6) uniform frameParams {
    vec4 frame;
    vec4 cameraPosition;
    vec4 envParams;
};
in vec4 baseColor;
layout(location=0) out vec4 fragColor;
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
        vec3 color = exposed - offset;
        float peak = max(color.x, max(color.y, color.z));
        if (peak >= startCompression) {
            float d = 1.0 - startCompression;
            float newPeak = 1.0 - ((d * d) / ((peak + d) - startCompression));
            color = color * (newPeak / peak);
            float g = 1.0 - (1.0 / ((desaturation * (peak - newPeak)) + 1.0));
            color = mix(color, vec3(newPeak), g);
        }
        return color;
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
    fragColor = vec4(toneMapped(baseColor.rgb, frame), baseColor.a);
    return;
}
@end

