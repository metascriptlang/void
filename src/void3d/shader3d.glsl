@block vertexUniforms
layout(binding=0) uniform vertexParams {
    mat4 viewProj;
    vec4 cameraRight;
    vec4 cameraUp;
};
@end

@block modelUniforms
layout(binding=2) uniform modelParams {
    mat4 model;
    mat4 normalModel;
};
@end

@block materialUniforms
layout(binding=3) uniform toonParams {
    vec4 toon;
};
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

@block spriteUniforms
layout(binding=2) uniform spriteParams {
    vec4 grassColor;
    vec4 toon;
};
@end

@block lightUniforms
layout(binding=1) uniform lightParams {
    vec4 ambient;
    vec4 dirLight;
    vec4 dirColor;
    vec4 pointLight[4];
    vec4 pointColor[4];
};

vec3 pointLightAt(int i, vec3 position, vec3 normal, float normalWeight) {
    vec3 toLight = pointLight[i].xyz - position;
    float distance = length(toLight);
    float falloff = clamp(1.0 - distance / pointColor[i].a, 0.0, 1.0);
    float facing = mix(1.0, max(dot(normal, toLight / max(distance, 0.0001)), 0.0), normalWeight);
    float energy = falloff * falloff * facing * pointLight[i].w;
    float level = floor(energy * toon.x + 0.35) / toon.x;
    return pointColor[i].rgb * level;
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
    depth01 = gl_Position.z;
}
@end

@fs litFs
// PENDING3D: material-saturation-only
// PENDING3D: dir-light-stepped
@include_block materialUniforms
@include_block lightUniforms
@include_block saturation
in vec3 worldPosition;
in vec3 worldNormal;
in vec4 baseColor;
in float depth01;
layout(location=0) out vec4 fragColor;
layout(location=1) out vec4 fragNormal;
void main() {
    vec3 n = normalize(worldNormal);
    float lambert = step(0.35, dot(n, dirLight.xyz)) * dirLight.w;
    vec3 shaded = saturated(baseColor.rgb, toon.y) * (ambient.rgb + dirColor.rgb * vec3(lambert));
    vec3 points = vec3(0.0);
    for (int i = 0; i < int(ambient.a + 0.5); i++) {
        points += pointLightAt(i, worldPosition, n, 1.0);
    }
    fragColor = vec4(shaded + points, baseColor.a);
    fragNormal = vec4(n * 0.5 + 0.5, depth01);
}
@end

@vs billboardVs
@include_block vertexUniforms
in vec2 corner;
in vec4 root;
in vec4 shape;
out vec2 uv;
out vec3 rootPosition;
out float tint;
out float emissive;
out float depth01;
void main() {
    vec3 p = root.xyz + cameraRight.xyz * (corner.x * shape.x) + cameraUp.xyz * (corner.y * shape.y);
    gl_Position = viewProj * vec4(p, 1.0);
    depth01 = gl_Position.z;
    uv = vec2((corner.x + 0.5 + root.w) * 0.25, 1.0 - corner.y);
    rootPosition = root.xyz;
    tint = shape.z;
    emissive = shape.w;
}
@end

@fs billboardFs
@include_block spriteUniforms
@include_block lightUniforms
layout(binding=0) uniform texture2D spriteTexture;
layout(binding=0) uniform sampler spriteSampler;
in vec2 uv;
in vec3 rootPosition;
in float tint;
in float emissive;
in float depth01;
layout(location=0) out vec4 fragColor;
layout(location=1) out vec4 fragNormal;
void main() {
    vec4 texel = texture(sampler2D(spriteTexture, spriteSampler), uv);
    if (texel.a < 0.5) {
        discard;
    }
    vec3 points = vec3(0.0);
    for (int i = 0; i < int(ambient.a + 0.5); i++) {
        points += pointLightAt(i, rootPosition + vec3(0.0, 0.25, 0.0), vec3(0.0, 1.0, 0.0), 0.0);
    }
    vec3 grass = grassColor.rgb * texel.r * tint + points;
    fragColor = vec4(mix(grass, texel.rgb, emissive), 0.0);
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
in vec2 corner;
in vec4 root;
in vec4 color;
out vec4 particleColor;
out float depth01;
void main() {
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

@program lit litVs litFs
@program billboard billboardVs billboardFs
@program post fullscreenVs postFs
@program blit fullscreenVs blitFs
@program particle particleVs particleFs
