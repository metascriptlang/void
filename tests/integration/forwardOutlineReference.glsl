@vs outlineReferenceVs
in vec2 position;
void main() {
    gl_Position = vec4(position, 0.5, 1.0);
}
@end

@fs outlineReferenceFs
layout(binding=0) uniform texture2D referenceImage;
layout(binding=0) uniform sampler referenceSampler;
layout(binding=0) uniform referenceParameters {
    vec4 referenceSize;
};
out vec4 fragColor;
float referenceCoverage(vec2 coordinate) {
    float coverage = texture(sampler2D(referenceImage, referenceSampler), coordinate).r;
    return referenceSize.z > 0.5 ? 1.0 - coverage : coverage;
}
void main() {
    vec2 inputUv = gl_FragCoord.xy / vec2(textureSize(sampler2D(referenceImage, referenceSampler), 0));
    float ownColor = referenceCoverage(inputUv);
    float maxAlpha = 0.0;
    float angle = 0.0;
    float doublePi = 6.28318530717958647692528;
    float step = doublePi / 48.0;
    for (int i = 0; i < 48; i++) {
        angle += step;
        vec2 displaced;
        displaced.x = inputUv.x + referenceSize.x * cos(angle);
        displaced.y = inputUv.y + referenceSize.y * sin(angle);
        float curColor = referenceCoverage(displaced);
        maxAlpha = max(maxAlpha, curColor);
    }
    float resultAlpha = max(maxAlpha, ownColor);
    float coverage = referenceSize.z > 0.5 ? 1.0 - resultAlpha : resultAlpha;
    fragColor = vec4(coverage);
}
@end

@program outlineReference outlineReferenceVs outlineReferenceFs
