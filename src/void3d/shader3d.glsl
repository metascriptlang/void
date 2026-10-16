@block pointLight
vec3 pointLightAt(int i, vec3 position, vec3 normal) {
    vec3 toLight = pointLight[i].xyz - position;
    float distance = length(toLight);
    float falloff = clamp(1.0 - distance / pointColor[i].a, 0.0, 1.0);
    float facing = max(dot(normal, toLight / max(distance, 0.0001)), 0.0);
    return srgbToLinear(pointColor[i].rgb) * (falloff * falloff * facing * pointLight[i].w);
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

// h3d.pass.Shadows writes depth only; a cutout caster discards at its colour program's alpha.
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
@include_block colorSpace
@include_block frameUniforms
@include_block toneMap
in vec4 particleColor;
out vec4 fragColor;
void main() {
#ifdef CUTOUT
    if (particleColor.a < 0.5) {
        discard;
    }
#endif
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
