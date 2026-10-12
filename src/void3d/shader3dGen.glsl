@fs copyFs
layout(binding=0) uniform texture2D sourceTexture;
layout(binding=0) uniform sampler pointSampler;
layout(location=0) out vec4 fragColor;
void main() {
    ivec2 size = ivec2(uvec2(textureSize(sampler2D(sourceTexture, pointSampler), 0)));
    ivec2 p = clamp(ivec2(gl_FragCoord.xy), ivec2(0, 0), (size - ivec2(1, 1)));
    fragColor = texelFetch(sampler2D(sourceTexture, pointSampler), p, 0);
    return;
}
@end

