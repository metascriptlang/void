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
@include_block frameUniforms
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
#ifdef PREMULTIPLIED
@include_block straightTexel
#endif
#ifdef UV_TRANSFORM
@include_block frameUniforms
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
in vec4 particleColor;
out vec4 fragColor;
void main() {
    if (particleColor.a < 0.5) {
        discard;
    }
    fragColor = particleColor;
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
// PENDING3D: particle-alpha-tested
@include_block billboardUniforms
@include_block lightUniforms
@include_block colorSpace
@include_block pointLight
layout(binding=0) uniform texture2D billboardTexture;
layout(binding=0) uniform sampler billboardSampler;
in vec3 worldPosition;
in vec3 towardCamera;
in vec2 uv;
in vec4 instanceColor;
out vec4 fragColor;
void main() {
    vec4 texel = texture(sampler2D(billboardTexture, billboardSampler), uv);
    vec4 pixel = billboardColor * texel * instanceColor;
    if (pixel.a < 0.5) {
        discard;
    }
    if (billboard.y != 0.0) {
        vec3 n = normalize(towardCamera);
        float lambert = max(dot(n, dirLight.xyz), 0.0) * dirLight.w;
        vec3 light = srgbToLinear(ambient.rgb) + srgbToLinear(dirColor.rgb) * lambert;
        for (int i = 0; i < int(ambient.a + 0.5); i++) {
            light += pointLightAt(i, worldPosition, n);
        }
        pixel.rgb = linearToSrgb(srgbToLinear(pixel.rgb) * light);
    }
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
