@include shader3dBlocks.glsl

@block pointLight
vec3 pointLightAt(int i, vec3 position, vec3 normal) {
    vec3 toLight = pointLight[i].xyz - position;
    float distance = length(toLight);
    float falloff = clamp(1.0 - distance / pointColor[i].a, 0.0, 1.0);
    float facing = max(dot(normal, toLight / max(distance, 0.0001)), 0.0);
    return pointColor[i].rgb * (falloff * falloff * facing * pointLight[i].w);
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

@fs litFs
// PENDING3D: material-saturation-only
@include_block materialUniforms
@include_block lightUniforms
@include_block pointLight
@include_block saturation
in vec3 worldPosition;
in vec3 worldNormal;
in vec4 baseColor;
out vec4 fragColor;
void main() {
    vec3 n = normalize(worldNormal);
    float lambert = max(dot(n, dirLight.xyz), 0.0) * dirLight.w;
    vec3 light = ambient.rgb + dirColor.rgb * lambert;
    for (int i = 0; i < int(ambient.a + 0.5); i++) {
        light += pointLightAt(i, worldPosition, n);
    }
    fragColor = vec4(saturated(baseColor.rgb, material.y) * light, baseColor.a);
}
@end

@vs particleVs
@include_block vertexUniforms
in vec2 corner;
in vec4 root;
in vec4 color;
out vec4 particleColor;
void main() {
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
in vec2 corner;
in vec3 position;
in vec2 size;
in vec4 tile;
in vec4 color;
out vec3 worldPosition;
out vec3 towardCamera;
out vec2 uv;
out vec4 instanceColor;
void main() {
    // PENDING3D: particle-size-world-units
    vec3 p = position + cameraRight.xyz * (corner.x * size.x) + cameraUp.xyz * (corner.y * size.y);
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
    if (texel.a < 0.5) {
        discard;
    }
    vec4 pixel = billboardColor * texel * instanceColor;
    if (billboard.y != 0.0) {
        vec3 n = normalize(towardCamera);
        float lambert = max(dot(n, dirLight.xyz), 0.0) * dirLight.w;
        vec3 light = ambient.rgb + dirColor.rgb * lambert;
        for (int i = 0; i < int(ambient.a + 0.5); i++) {
            light += pointLightAt(i, worldPosition, n);
        }
        pixel.rgb *= light;
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

@program lit litVs litFs
@program particle particleVs particleFs
@program billboard billboardVs billboardFs
@program copy fullscreenVs copyFs
