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

@vs particleVisualVs
layout(binding=0) uniform vertexParams {
    mat4 viewProj;
    vec4 cameraRight;
    vec4 cameraUp;
};
in vec4 root;
in vec4 shape;
in vec4 tile;
in vec4 color;
out vec3 worldPosition;
out vec3 towardCamera;
out vec2 uv;
out vec4 instanceColor;
const vec2[6] PARTICLE_CORNERS = vec2[6](vec2(-0.5, -0.5), vec2(0.5, -0.5), vec2(0.5, 0.5), vec2(-0.5, -0.5), vec2(0.5, 0.5), vec2(-0.5, 0.5));
vec3 particleVisualPoint(vec4 root_1, vec4 shape_1, vec2 corner, vec3 right, vec3 up) {
    float x = (corner.x - shape_1.y) * root_1.w;
    float y = (corner.y - shape_1.z) * shape_1.x;
    float c = cos(shape_1.w);
    float s = sin(shape_1.w);
    return (root_1.xyz + (right * ((x * c) + (y * s)))) + (up * ((y * c) - (x * s)));
}
void main() {
    vec2 corner = PARTICLE_CORNERS[uint(gl_VertexIndex) % 6];
    vec3 world = particleVisualPoint(root, shape, corner, cameraRight.xyz, cameraUp.xyz);
    worldPosition = world;
    towardCamera = cross(cameraRight.xyz, cameraUp.xyz);
    uv = vec2(((corner.x > 0.0) ? tile.z : tile.x), ((corner.y > 0.0) ? tile.y : tile.w));
    instanceColor = color;
    gl_Position = (viewProj * vec4(world, 1.0));
    return;
}
@end

@vs particleVisualPixelArtVs
layout(binding=0) uniform vertexParams {
    mat4 viewProj;
    vec4 cameraRight;
    vec4 cameraUp;
};
in vec4 root;
in vec4 shape;
in vec4 tile;
in vec4 color;
out vec2 uv;
out vec3 rootPosition;
out vec4 instanceColor;
out float depth01;
const vec2[6] PARTICLE_CORNERS = vec2[6](vec2(-0.5, -0.5), vec2(0.5, -0.5), vec2(0.5, 0.5), vec2(-0.5, -0.5), vec2(0.5, 0.5), vec2(-0.5, 0.5));
vec3 particleVisualPoint(vec4 root_1, vec4 shape_1, vec2 corner, vec3 right, vec3 up) {
    float x = (corner.x - shape_1.y) * root_1.w;
    float y = (corner.y - shape_1.z) * shape_1.x;
    float c = cos(shape_1.w);
    float s = sin(shape_1.w);
    return (root_1.xyz + (right * ((x * c) + (y * s)))) + (up * ((y * c) - (x * s)));
}
void main() {
    vec2 corner = PARTICLE_CORNERS[uint(gl_VertexIndex) % 6];
    vec3 world = particleVisualPoint(root, shape, corner, cameraRight.xyz, cameraUp.xyz);
    vec4 clip = viewProj * vec4(world, 1.0);
    uv = vec2(((corner.x > 0.0) ? tile.z : tile.x), ((corner.y > 0.0) ? tile.y : tile.w));
    rootPosition = root.xyz;
    instanceColor = color;
    depth01 = clip.z;
    gl_Position = clip;
    return;
}
@end

@vs litVs
#if defined(SKINNED) || !defined(SKINNED)
layout(binding=0) uniform vertexParams {
    mat4 viewProj;
    vec4 cameraRight;
    vec4 cameraUp;
};
#endif
#ifndef SKINNED
layout(binding=4) uniform modelParams {
    mat4 model;
    mat4 normalModel;
};
#endif
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
#ifdef SKINNED
vec3 skinNormal(mat4 world, vec3 normal_1) {
    mat3 linear = mat3(world);
    vec3 a = cross(linear[1], linear[2]);
    vec3 b = cross(linear[2], linear[0]);
    vec3 c = cross(linear[0], linear[1]);
    float direction = (dot(linear[0], a) < 0.0) ? -1.0 : 1.0;
    return (((a * normal_1.x) + (b * normal_1.y)) + (c * normal_1.z)) * direction;
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
    vec4 world_1 = model * vec4(position, 1.0);
    worldPosition = world_1.xyz;
    worldNormal = (mat3(normalModel) * normal);
    baseColor = color;
    gl_Position = (viewProj * world_1);
    return;
#endif
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
#if defined(SKINNED) || !defined(SKINNED)
layout(binding=0) uniform vertexParams {
    mat4 viewProj;
    vec4 cameraRight;
    vec4 cameraUp;
};
#endif
#if !defined(SKINNED) || (!defined(SKINNED) && defined(NORMAL_MAP))
layout(binding=4) uniform modelParams {
    mat4 model;
    mat4 normalModel;
};
#endif
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
#ifdef SKINNED
in vec4 skinJoints;
#endif
#ifdef SKINNED
in vec4 skinWeights;
#endif
#ifdef NORMAL_MAP
out vec4 worldTangent;
#endif
out vec3 worldPosition;
out vec3 worldNormal;
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
#ifdef SKINNED
vec3 skinNormal(mat4 world, vec3 normal_1) {
    mat3 linear = mat3(world);
    vec3 a = cross(linear[1], linear[2]);
    vec3 b = cross(linear[2], linear[0]);
    vec3 c = cross(linear[0], linear[1]);
    float direction = (dot(linear[0], a) < 0.0) ? -1.0 : 1.0;
    return (((a * normal_1.x) + (b * normal_1.y)) + (c * normal_1.z)) * direction;
}
#endif
void main() {
#ifdef SKINNED
    mat4 matrix = skinWorld(skinJoints, skinWeights);
    vec4 world = matrix * vec4(position, 1.0);
    float handedness = (determinant(mat3(matrix)) < 0.0) ? -1.0 : 1.0;
    worldPosition = world.xyz;
    worldNormal = skinNormal(matrix, normal);
#ifdef NORMAL_MAP
    worldTangent = vec4((mat3(matrix) * tangent.xyz), (tangent.w * handedness));
#endif
    surfaceUv = uv;
    baseColor = color;
    gl_Position = (viewProj * world);
    return;
#else
    vec4 world_1 = model * vec4(position, 1.0);
    worldPosition = world_1.xyz;
    worldNormal = (mat3(normalModel) * normal);
#ifdef NORMAL_MAP
    worldTangent = vec4((mat3(model) * tangent.xyz), tangent.w);
#endif
    surfaceUv = uv;
    baseColor = color;
    gl_Position = (viewProj * world_1);
    return;
#endif
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
#if defined(SKINNED) || !defined(SKINNED)
layout(binding=0) uniform vertexParams {
    mat4 viewProj;
    vec4 cameraRight;
    vec4 cameraUp;
};
#endif
#if !defined(SKINNED) && defined(NORMAL_MRT)
layout(binding=4) uniform modelParams {
    mat4 model;
    mat4 normalModel;
};
#endif
#if !defined(SKINNED) && !defined(NORMAL_MRT)
layout(binding=4) uniform modelTransformParams {
    mat4 model;
};
#endif
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
#ifdef SKINNED
in vec4 skinJoints;
#endif
#ifdef SKINNED
in vec4 skinWeights;
#endif
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
#if defined(SKINNED) && defined(NORMAL_MRT)
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
mat4 unlitModel() {
#ifdef NORMAL_MRT
    return model;
#else
    return model;
#endif
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
    gl_Position = ((viewProj * unlitModel()) * vec4(position, 1.0));
#ifdef NORMAL_MRT
    worldNormal = (mat3(normalModel) * normal);
#endif
    surfaceUv = uv;
    baseColor = color;
    return;
#endif
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

