@module pixelArt
@include shader3dBlocks.glsl

@block toonPointLight
vec3 pointLightAt(int i, vec3 position, vec3 normal, float normalWeight, float levels) {
    vec3 toLight = pointLight[i].xyz - position;
    float distance = length(toLight);
    float falloff = clamp(1.0 - distance / pointColor[i].a, 0.0, 1.0);
    float facing = mix(1.0, max(dot(normal, toLight / max(distance, 0.0001)), 0.0), normalWeight);
    float energy = falloff * falloff * facing * pointLight[i].w;
    float level = floor(energy * levels + 0.35) / levels;
    return srgbToLinear(pointColor[i].rgb) * level;
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
out float depth01;
void main() {
    vec4 world = model * vec4(position, 1.0);
    worldPosition = world.xyz;
    worldNormal = mat3(normalModel) * normal;
    baseColor = color;
    gl_Position = viewProj * world;
    // PENDING3D: pixel-art-depth-orthographic
    depth01 = gl_Position.z;
}
@end

@block litShade
vec4 litShade(vec3 n) {
    float lambert = max(dot(n, dirLight.xyz), 0.0) * dirLight.w;
    vec3 light = srgbToLinear(ambient.rgb) + srgbToLinear(dirColor.rgb) * lambert;
    for (int i = 0; i < int(ambient.a + 0.5); i++) {
        light += pointLightAt(i, worldPosition, n, 1.0, material.x);
    }
    vec3 surface = srgbToLinear(saturated(baseColor.rgb, material.y));
    return vec4(linearToSrgb(surface * light), baseColor.a);
}
@end

@fs litFs
@include_block materialUniforms
@include_block lightUniforms
@include_block colorSpace
@include_block toonPointLight
@include_block saturation
@include_block facingNormal
in vec3 worldPosition;
in vec3 worldNormal;
in vec4 baseColor;
in float depth01;
layout(location=0) out vec4 fragColor;
layout(location=1) out vec4 fragNormal;
@include_block litShade
void main() {
    vec3 n = facingNormal(normalize(worldNormal), material.z);
    fragColor = litShade(n);
    fragNormal = vec4(n * 0.5 + 0.5, depth01);
}
@end

@vs litTexturedVs
@include_block vertexUniforms
@include_block modelUniforms
in vec3 position;
in vec3 normal;
in vec2 uv;
in vec4 color;
out vec3 worldPosition;
out vec3 worldNormal;
out vec2 surfaceUv;
out vec4 baseColor;
out float depth01;
void main() {
    vec4 world = model * vec4(position, 1.0);
    worldPosition = world.xyz;
    worldNormal = mat3(normalModel) * normal;
    surfaceUv = uv;
    baseColor = color;
    gl_Position = viewProj * world;
    depth01 = gl_Position.z;
}
@end

@block litTexturedShade
vec4 litTexturedShade(vec4 texel, vec3 n) {
    float lambert = max(dot(n, dirLight.xyz), 0.0) * dirLight.w;
    vec3 light = srgbToLinear(ambient.rgb) + srgbToLinear(dirColor.rgb) * lambert;
    for (int i = 0; i < int(ambient.a + 0.5); i++) {
        light += pointLightAt(i, worldPosition, n, 1.0, material.x);
    }
    vec3 surface = srgbToLinear(saturated(baseColor.rgb * texel.rgb, material.y));
    return vec4(linearToSrgb(surface * light), baseColor.a * texel.a);
}
@end

@fs litTexturedFs
@include_block materialUniforms
@include_block lightUniforms
@include_block colorSpace
@include_block toonPointLight
@include_block saturation
@include_block facingNormal
layout(binding=0) uniform texture2D baseTexture;
layout(binding=0) uniform sampler baseSampler;
in vec3 worldPosition;
in vec3 worldNormal;
in vec2 surfaceUv;
in vec4 baseColor;
in float depth01;
layout(location=0) out vec4 fragColor;
layout(location=1) out vec4 fragNormal;
@include_block litTexturedShade
void main() {
    vec4 texel = texture(sampler2D(baseTexture, baseSampler), surfaceUv);
    vec3 n = facingNormal(normalize(worldNormal), material.z);
    fragColor = litTexturedShade(texel, n);
    fragNormal = vec4(n * 0.5 + 0.5, depth01);
}
@end

@vs unlitTexturedVs
@include_block vertexUniforms
@include_block modelUniforms
in vec3 position;
in vec3 normal;
in vec2 uv;
in vec4 color;
out vec3 worldNormal;
out vec2 surfaceUv;
out vec4 baseColor;
out float depth01;
void main() {
    gl_Position = viewProj * model * vec4(position, 1.0);
    worldNormal = mat3(normalModel) * normal;
    surfaceUv = uv;
    baseColor = color;
    depth01 = gl_Position.z;
}
@end

@fs unlitTexturedFs
@include_block unlitMaterialUniforms
@include_block colorSpace
@include_block facingNormal
layout(binding=0) uniform texture2D baseTexture;
layout(binding=0) uniform sampler baseSampler;
in vec3 worldNormal;
in vec2 surfaceUv;
in vec4 baseColor;
in float depth01;
layout(location=0) out vec4 fragColor;
layout(location=1) out vec4 fragNormal;
@include_block unlitTexturedShade
void main() {
    vec4 texel = texture(sampler2D(baseTexture, baseSampler), surfaceUv);
    vec3 n = facingNormal(normalize(worldNormal), material.z);
    fragColor = unlitTexturedShade(texel);
    fragNormal = vec4(n * 0.5 + 0.5, depth01);
}
@end

@fs litTexturedPremultipliedFs
@include_block materialUniforms
@include_block lightUniforms
@include_block colorSpace
@include_block toonPointLight
@include_block saturation
@include_block facingNormal
@include_block straightTexel
layout(binding=0) uniform texture2D baseTexture;
layout(binding=0) uniform sampler baseSampler;
in vec3 worldPosition;
in vec3 worldNormal;
in vec2 surfaceUv;
in vec4 baseColor;
in float depth01;
layout(location=0) out vec4 fragColor;
layout(location=1) out vec4 fragNormal;
@include_block litTexturedShade
void main() {
    vec4 texel = straightTexel(texture(sampler2D(baseTexture, baseSampler), surfaceUv));
    vec3 n = facingNormal(normalize(worldNormal), material.z);
    vec4 color = litTexturedShade(texel, n);
    fragColor = vec4(color.rgb * color.a, color.a);
    fragNormal = vec4(n * 0.5 + 0.5, depth01);
}
@end

@fs unlitTexturedPremultipliedFs
@include_block unlitMaterialUniforms
@include_block colorSpace
@include_block facingNormal
@include_block straightTexel
layout(binding=0) uniform texture2D baseTexture;
layout(binding=0) uniform sampler baseSampler;
in vec3 worldNormal;
in vec2 surfaceUv;
in vec4 baseColor;
in float depth01;
layout(location=0) out vec4 fragColor;
layout(location=1) out vec4 fragNormal;
@include_block unlitTexturedShade
void main() {
    vec4 texel = straightTexel(texture(sampler2D(baseTexture, baseSampler), surfaceUv));
    vec3 n = facingNormal(normalize(worldNormal), material.z);
    vec4 color = unlitTexturedShade(texel);
    fragColor = vec4(color.rgb * color.a, color.a);
    fragNormal = vec4(n * 0.5 + 0.5, depth01);
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
out vec2 uv;
out vec3 rootPosition;
out vec4 instanceColor;
out float depth01;
void main() {
    vec2 corner = QUAD_CORNERS[gl_VertexIndex];
    vec3 p = billboardPoint(position, size, anchor, corner);
    gl_Position = viewProj * vec4(p, 1.0);
    depth01 = gl_Position.z;
    uv = vec2(corner.x > 0.0 ? tile.z : tile.x, corner.y > 0.0 ? tile.y : tile.w);
    rootPosition = position;
    instanceColor = color;
}
@end

@fs billboardFs
@include_block billboardUniforms
@include_block lightUniforms
@include_block colorSpace
@include_block toonPointLight
layout(binding=0) uniform texture2D billboardTexture;
layout(binding=0) uniform sampler billboardSampler;
in vec2 uv;
in vec3 rootPosition;
in vec4 instanceColor;
in float depth01;
layout(location=0) out vec4 fragColor;
layout(location=1) out vec4 fragNormal;
void main() {
    vec4 texel = texture(sampler2D(billboardTexture, billboardSampler), uv);
    if (billboardColor.a * texel.a * instanceColor.a < 0.5) {
        discard;
    }
    vec3 rgb = billboardColor.rgb * texel.rgb * instanceColor.rgb;
    if (billboard.y != 0.0) {
        vec3 lightPoint = rootPosition + vec3(0.0, billboard.z, 0.0);
        vec3 points = vec3(0.0);
        for (int i = 0; i < int(ambient.a + 0.5); i++) {
            points += pointLightAt(i, lightPoint, vec3(0.0, 1.0, 0.0), 0.0, billboard.x);
        }
        rgb = linearToSrgb(srgbToLinear(rgb) + points);
    }
    fragColor = vec4(rgb, 0.0);
    fragNormal = vec4(0.5, 1.0, 0.5, depth01);
}
@end

@vs fullscreenVs
in vec2 position;
void main() {
    gl_Position = vec4(position, 0.5, 1.0);
}
@end

@fs postFs
// Outline from depth + normal edges, fog by depth, then palette quantization through a LUT:
// one pass, because the palette only needs this pixel's outlined color (docs/VOID3D.md, M3).
@image_sample_type depthTexture unfilterable_float
@sampler_type depthSampler nonfiltering
layout(binding=0) uniform texture2D colorTexture;
layout(binding=1) uniform texture2D normalTexture;
layout(binding=2) uniform texture2D depthTexture;
layout(binding=3) uniform texture2D paletteTexture;
layout(binding=0) uniform sampler pointSampler;
layout(binding=1) uniform sampler depthSampler;
@include_block saturation
layout(binding=0) uniform postParams {
    vec4 edge;
    vec4 fog;
    vec4 fogColor;
    vec4 features;
    vec4 depthUnpack;
    vec4 colorAdjust;
};
out vec4 fragColor;

vec4 fetchNormal(ivec2 p, ivec2 size) {
    return texelFetch(sampler2D(normalTexture, pointSampler), clamp(p, ivec2(0, 0), size - ivec2(1, 1)), 0);
}

// features.z picks the depth: the scene's depth attachment, unpacked to the depth the scene
// shaders write, or the 8-bit copy they pack into the normal target's alpha.
float depthAt(vec4 normal, ivec2 p, ivec2 size) {
    float depth = normal.w;
    if (features.z > 0.5) {
        ivec2 q = clamp(p, ivec2(0, 0), size - ivec2(1, 1));
        float stored = texelFetch(sampler2D(depthTexture, depthSampler), q, 0).r;
        depth = stored * depthUnpack.x + depthUnpack.y;
    }
    return depth;
}

// features.w levels per channel; the LUT is levels * levels wide, red + blue * levels across,
// green down (palette.ms).
vec3 paletteColor(vec3 rgb) {
    int levels = int(features.w);
    ivec3 q = ivec3(clamp(rgb, 0.0, 1.0) * float(levels - 1) + 0.5);
    ivec2 cell = ivec2(q.r + q.b * levels, q.g);
    return texelFetch(sampler2D(paletteTexture, pointSampler), cell, 0).rgb;
}

void main() {
    ivec2 size = textureSize(sampler2D(colorTexture, pointSampler), 0);
    ivec2 p = ivec2(gl_FragCoord.xy);
    vec4 color = texelFetch(sampler2D(colorTexture, pointSampler), p, 0);
    vec4 center = fetchNormal(p, size);
    float centerDepth = depthAt(center, p, size);
    vec3 rgb = color.rgb;
    if (features.x > 0.5) {
        vec3 n = center.xyz * 2.0 - 1.0;
        float depthEdge = 0.0;
        float normalEdge = 0.0;
        ivec2 offsets[4] = ivec2[4](ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1));
        for (int i = 0; i < 4; i++) {
            vec4 neighbor = fetchNormal(p + offsets[i], size);
            float depthDelta = depthAt(neighbor, p + offsets[i], size) - centerDepth;
            if (depthDelta > edge.x) {
                depthEdge = 1.0;
            }
            vec3 nq = neighbor.xyz * 2.0 - 1.0;
            if (abs(depthDelta) < edge.x && dot(n, nq) < edge.y && n.y > nq.y + 0.1) {
                normalEdge = 1.0;
            }
        }
        rgb = mix(rgb, rgb * edge.z, depthEdge * color.a);
        rgb = mix(rgb, rgb * edge.w + vec3(0.02), normalEdge * color.a * (1.0 - depthEdge));
    }
    float haze = smoothstep(fog.x, fog.y, centerDepth) * fog.z;
    rgb = mix(rgb, fogColor.rgb, haze);
    rgb = saturated(rgb, colorAdjust.x);
    if (features.y > 0.5) {
        rgb = paletteColor(rgb);
    }
    fragColor = vec4(rgb, 1.0);
}
@end

@fs blitFs
layout(binding=0) uniform texture2D sceneTexture;
layout(binding=0) uniform sampler pointSampler;
layout(binding=0) uniform blitParams {
    vec4 pixel;
};
out vec4 fragColor;
// pixel = (scale, scale, offset x, offset y) in framebuffer pixels (blit.ms). Alpha is 1 so
// that blitting the scene color directly (no post stage) never shows through the surface.
void main() {
    ivec2 size = textureSize(sampler2D(sceneTexture, pointSampler), 0);
    ivec2 p = ivec2(floor((gl_FragCoord.xy + pixel.zw) / pixel.x));
    vec4 texel = texelFetch(sampler2D(sceneTexture, pointSampler), clamp(p, ivec2(0, 0), size - ivec2(1, 1)), 0);
    fragColor = vec4(texel.rgb, 1.0);
}
@end

@vs particleVs
@include_block vertexUniforms
@include_block quadCorner
in vec4 root;
in vec4 color;
out vec4 particleColor;
out float depth01;
void main() {
    vec2 corner = QUAD_CORNERS[gl_VertexIndex];
    vec3 p = root.xyz + cameraRight.xyz * (corner.x * root.w) + cameraUp.xyz * (corner.y * root.w);
    gl_Position = viewProj * vec4(p, 1.0);
    depth01 = gl_Position.z;
    particleColor = color;
}
@end

@fs particleFs
// PENDING3D: particle-alpha-tested
in vec4 particleColor;
in float depth01;
layout(location=0) out vec4 fragColor;
layout(location=1) out vec4 fragNormal;
void main() {
    if (particleColor.a < 0.5) {
        discard;
    }
    fragColor = vec4(particleColor.rgb, 0.0);
    fragNormal = vec4(0.5, 1.0, 0.5, depth01);
}
@end

@fs litCutoutFs
@include_block materialUniforms
@include_block lightUniforms
@include_block colorSpace
@include_block toonPointLight
@include_block saturation
@include_block facingNormal
in vec3 worldPosition;
in vec3 worldNormal;
in vec4 baseColor;
in float depth01;
layout(location=0) out vec4 fragColor;
layout(location=1) out vec4 fragNormal;
@include_block litShade
void main() {
    vec3 n = facingNormal(normalize(worldNormal), material.z);
    fragColor = litShade(n);
    if (fragColor.a < material.w) {
        discard;
    }
    fragNormal = vec4(n * 0.5 + 0.5, depth01);
}
@end

@fs litTexturedCutoutFs
@include_block materialUniforms
@include_block lightUniforms
@include_block colorSpace
@include_block toonPointLight
@include_block saturation
@include_block facingNormal
layout(binding=0) uniform texture2D baseTexture;
layout(binding=0) uniform sampler baseSampler;
in vec3 worldPosition;
in vec3 worldNormal;
in vec2 surfaceUv;
in vec4 baseColor;
in float depth01;
layout(location=0) out vec4 fragColor;
layout(location=1) out vec4 fragNormal;
@include_block litTexturedShade
void main() {
    vec4 texel = texture(sampler2D(baseTexture, baseSampler), surfaceUv);
    vec3 n = facingNormal(normalize(worldNormal), material.z);
    fragColor = litTexturedShade(texel, n);
    if (fragColor.a < material.w) {
        discard;
    }
    fragNormal = vec4(n * 0.5 + 0.5, depth01);
}
@end

@fs unlitTexturedCutoutFs
@include_block unlitMaterialUniforms
@include_block colorSpace
@include_block facingNormal
layout(binding=0) uniform texture2D baseTexture;
layout(binding=0) uniform sampler baseSampler;
in vec3 worldNormal;
in vec2 surfaceUv;
in vec4 baseColor;
in float depth01;
layout(location=0) out vec4 fragColor;
layout(location=1) out vec4 fragNormal;
@include_block unlitTexturedShade
void main() {
    vec4 texel = texture(sampler2D(baseTexture, baseSampler), surfaceUv);
    vec3 n = facingNormal(normalize(worldNormal), material.z);
    fragColor = unlitTexturedShade(texel);
    if (fragColor.a < material.w) {
        discard;
    }
    fragNormal = vec4(n * 0.5 + 0.5, depth01);
}
@end

@program lit litVs litFs
@program billboard billboardVs billboardFs
@program post fullscreenVs postFs
@program blit fullscreenVs blitFs
@program particle particleVs particleFs
@program litTextured litTexturedVs litTexturedFs
@program unlitTextured unlitTexturedVs unlitTexturedFs
@program litTexturedPremultiplied litTexturedVs litTexturedPremultipliedFs
@program unlitTexturedPremultiplied unlitTexturedVs unlitTexturedPremultipliedFs
@program litCutout litVs litCutoutFs
@program litTexturedCutout litTexturedVs litTexturedCutoutFs
@program unlitTexturedCutout unlitTexturedVs unlitTexturedCutoutFs
