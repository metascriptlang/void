@vs fullscreenVs
in vec2 position;
void main() {
    gl_Position = vec4(position, 0.5, 1.0);
    return;
}
@end

@fs environmentPanoramaFs
layout(binding=0) uniform texture2D panorama;
layout(binding=0) uniform sampler environmentSampler;
layout(binding=0) uniform environmentParams {
    vec4 envFaceX;
    vec4 envFaceY;
    vec4 envFaceZ;
    vec4 envBake;
    vec4 envSource;
};
layout(location=0) out vec4 fragColor;
vec3 faceDirection(vec4 position, float size, vec4 faceX, vec4 faceY, vec4 faceZ) {
    vec2 d = ((position.xy / size) * 2.0) - 1.0;
    return normalize((((faceX.xyz * d.x) + (faceY.xyz * d.y)) + faceZ.xyz));
}
vec3 panoramaDirection() {
    return faceDirection(gl_FragCoord, envBake.w, envFaceX, envFaceY, envFaceZ);
}
vec3 srgbToLinear(vec3 srgb) {
    vec3 low = srgb * 0.0773993808;
    vec3 high = pow(max(((srgb * 0.9478672986) + vec3(0.0521327014)), vec3(0.0)), vec3(2.4));
    return vec3(((srgb.x <= 0.04045) ? low.x : high.x), ((srgb.y <= 0.04045) ? low.y : high.y), ((srgb.z <= 0.04045) ? low.z : high.z));
}
void main() {
    vec3 n = panoramaDirection();
    vec2 uv = (vec2(atan(n.z, n.x), asin((-n.y))) * vec2(0.1591, 0.3183)) + 0.5;
    vec4 texel = textureLod(sampler2D(panorama, environmentSampler), uv, 0.0);
    if (max(max(texel.r, texel.g), texel.b) > envSource.x) {
        texel = texel * envSource.y;
    }
    vec3 color = texel.rgb;
    if (envSource.w > 0.5) {
        color = srgbToLinear(color);
    }
    fragColor = vec4(color, 1.0);
    return;
}
@end

@fs environmentResampleFs
layout(binding=0) uniform textureCube sourceCube;
layout(binding=0) uniform sampler environmentSampler;
layout(binding=0) uniform environmentParams {
    vec4 envFaceX;
    vec4 envFaceY;
    vec4 envFaceZ;
    vec4 envBake;
    vec4 envSource;
};
layout(location=0) out vec4 fragColor;
vec3 faceDirection(vec4 position, float size, vec4 faceX, vec4 faceY, vec4 faceZ) {
    vec2 d = ((position.xy / size) * 2.0) - 1.0;
    return normalize((((faceX.xyz * d.x) + (faceY.xyz * d.y)) + faceZ.xyz));
}
vec3 cubeDirection() {
    return faceDirection(gl_FragCoord, envBake.w, envFaceX, envFaceY, envFaceZ);
}
void main() {
    vec3 n = cubeDirection();
    vec4 texel = textureLod(samplerCube(sourceCube, environmentSampler), n, envBake.x);
    fragColor = vec4(texel.rgb, 1.0);
    return;
}
@end

@fs environmentRadianceFs
layout(binding=0) uniform textureCube sourceCube;
layout(binding=0) uniform sampler environmentSampler;
layout(binding=0) uniform environmentParams {
    vec4 envFaceX;
    vec4 envFaceY;
    vec4 envFaceZ;
    vec4 envBake;
    vec4 envSource;
};
layout(location=0) out vec4 fragColor;
vec3 faceDirection(vec4 position, float size, vec4 faceX, vec4 faceY, vec4 faceZ) {
    vec2 d = ((position.xy / size) * 2.0) - 1.0;
    return normalize((((faceX.xyz * d.x) + (faceY.xyz * d.y)) + faceZ.xyz));
}
vec3 cubeDirection() {
    return faceDirection(gl_FragCoord, envBake.w, envFaceX, envFaceY, envFaceZ);
}
uint sampleCount() {
    return uvec2(ivec2(int(envBake.y + 0.5), 0)).x;
}
const float PI = 3.14159265358979;
vec3 inFrame(vec3 n, vec3 local) {
    vec3 up = vec3(1.0, 0.0, 0.0);
    if (abs(n.z) < 0.999) {
        up = vec3(0.0, 0.0, 1.0);
    }
    vec3 tanX = normalize(cross(up, n));
    vec3 tanY = normalize(cross(n, tanX));
    return normalize((((tanX * local.x) + (tanY * local.y)) + (n * local.z)));
}
vec3 importanceSampleGgx(float roughness, vec2 p, vec3 n) {
    float a = roughness * roughness;
    float phi = (2.0 * PI) * p.x;
    float cosT = min(sqrt(((1.0 - p.y) / (1.0 + (((a * a) - 1.0) * p.y)))), 1.0);
    float sinT = sqrt((1.0 - (cosT * cosT)));
    return inFrame(n, vec3((sinT * cos(phi)), (sinT * sin(phi)), cosT));
}
vec2 hammersley(uint i, uint count) {
    uint bits = i;
    float weight = 0.5;
    float inverse_1 = 0.0;
    while (bits > 0u) {
        inverse_1 = inverse_1 + (weight * float(bits % 2u));
        bits = bits / 2u;
        weight = weight * 0.5;
    }
    return vec2((float(i) / float(count)), inverse_1);
}
float sampleLod(float pdf, float sourceWidth, float count) {
    float sample_1 = 1.0 / (count * pdf);
    float texel = (4.0 * PI) / ((6.0 * sourceWidth) * sourceWidth);
    return max((0.5 * log2((sample_1 / texel))), 0.0);
}
vec3 clampedSource(vec3 l, float lod) {
    vec3 texel = textureLod(samplerCube(sourceCube, environmentSampler), l, lod).rgb;
    return min(texel, vec3(envSource.z));
}
void main() {
    vec3 n = cubeDirection();
    float roughness = envBake.x;
    uint count = sampleCount();
    float a = roughness * roughness;
    float a2 = a * a;
    vec3 color = vec3(0.0);
    float total = 0.0;
    for (uint i = 0u; i < count; i++) {
        vec3 h = importanceSampleGgx(roughness, hammersley(i, count), n);
        float vh = dot(n, h);
        vec3 l = normalize(((h * (2.0 * vh)) - n));
        float nl = dot(n, l);
        if (nl > 0.0) {
            float denominator = ((vh * vh) * (a2 - 1.0)) + 1.0;
            float pdf = (a2 / ((PI * denominator) * denominator)) / 4.0;
            float lod = sampleLod(pdf, envBake.z, envBake.y);
            color = color + (clampedSource(l, lod) * nl);
            total = total + nl;
        }
    }
    fragColor = vec4((color / max(total, 1e-10)), 1.0);
    return;
}
@end

@fs environmentIrradianceFs
layout(binding=0) uniform textureCube sourceCube;
layout(binding=0) uniform sampler environmentSampler;
layout(binding=0) uniform environmentParams {
    vec4 envFaceX;
    vec4 envFaceY;
    vec4 envFaceZ;
    vec4 envBake;
    vec4 envSource;
};
layout(location=0) out vec4 fragColor;
vec3 faceDirection(vec4 position, float size, vec4 faceX, vec4 faceY, vec4 faceZ) {
    vec2 d = ((position.xy / size) * 2.0) - 1.0;
    return normalize((((faceX.xyz * d.x) + (faceY.xyz * d.y)) + faceZ.xyz));
}
vec3 cubeDirection() {
    return faceDirection(gl_FragCoord, envBake.w, envFaceX, envFaceY, envFaceZ);
}
uint sampleCount() {
    return uvec2(ivec2(int(envBake.y + 0.5), 0)).x;
}
const float PI = 3.14159265358979;
vec3 inFrame(vec3 n, vec3 local) {
    vec3 up = vec3(1.0, 0.0, 0.0);
    if (abs(n.z) < 0.999) {
        up = vec3(0.0, 0.0, 1.0);
    }
    vec3 tanX = normalize(cross(up, n));
    vec3 tanY = normalize(cross(n, tanX));
    return normalize((((tanX * local.x) + (tanY * local.y)) + (n * local.z)));
}
vec3 cosineWeightedSample(vec2 p, vec3 n) {
    float sq = sqrt((1.0 - p.x));
    float alpha = (2.0 * PI) * p.y;
    return inFrame(n, vec3((sq * cos(alpha)), (sq * sin(alpha)), sqrt(p.x)));
}
vec2 hammersley(uint i, uint count) {
    uint bits = i;
    float weight = 0.5;
    float inverse_1 = 0.0;
    while (bits > 0u) {
        inverse_1 = inverse_1 + (weight * float(bits % 2u));
        bits = bits / 2u;
        weight = weight * 0.5;
    }
    return vec2((float(i) / float(count)), inverse_1);
}
float sampleLod(float pdf, float sourceWidth, float count) {
    float sample_1 = 1.0 / (count * pdf);
    float texel = (4.0 * PI) / ((6.0 * sourceWidth) * sourceWidth);
    return max((0.5 * log2((sample_1 / texel))), 0.0);
}
vec3 clampedSource(vec3 l, float lod) {
    vec3 texel = textureLod(samplerCube(sourceCube, environmentSampler), l, lod).rgb;
    return min(texel, vec3(envSource.z));
}
void main() {
    vec3 n = cubeDirection();
    uint count = sampleCount();
    vec3 color = vec3(0.0);
    float total = 1e-10;
    for (uint i = 0u; i < count; i++) {
        vec3 l = cosineWeightedSample(hammersley(i, count), n);
        float nl = dot(n, l);
        if (nl > 0.0) {
            float lod = sampleLod((nl / PI), envBake.z, envBake.y);
            color = color + clampedSource(l, lod);
            total = total + 1.0;
        }
    }
    fragColor = vec4((color / total), 1.0);
    return;
}
@end

