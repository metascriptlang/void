@vs fullscreenVs
in vec2 position;
void main() {
    gl_Position = vec4(position, 0.5, 1.0);
    return;
}
@end

@fs postFs
layout(binding=0) uniform postParams {
    vec4 edge;
    vec4 fog;
    vec4 fogColor;
    vec4 features;
    vec4 depthUnpack;
    vec4 colorAdjust;
};
layout(binding=0) uniform texture2D colorTexture;
layout(binding=1) uniform texture2D normalTexture;
@image_sample_type depthTexture unfilterable_float
layout(binding=2) uniform texture2D depthTexture;
layout(binding=3) uniform texture2D paletteTexture;
layout(binding=0) uniform sampler pointSampler;
@sampler_type depthSampler nonfiltering
layout(binding=1) uniform sampler depthSampler;
layout(location=0) out vec4 fragColor;
vec4 postNormalAt(ivec2 p, ivec2 size) {
    return texelFetch(sampler2D(normalTexture, pointSampler), clamp(p, ivec2(0, 0), (size - ivec2(1, 1))), 0);
}
float postDepthAt(vec4 normal, ivec2 p, ivec2 size) {
    float depth = normal.w;
    if (features.z > 0.5) {
        ivec2 q = clamp(p, ivec2(0, 0), (size - ivec2(1, 1)));
        float stored = texelFetch(sampler2D(depthTexture, depthSampler), q, 0).x;
        depth = (stored * depthUnpack.x) + depthUnpack.y;
    }
    return depth;
}
const ivec2[4] OUTLINE_OFFSETS = ivec2[4](ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1));
vec3 saturated(vec3 rgb, float amount) {
    if (amount == 0.0) {
        return rgb;
    }
    float luma = dot(rgb, vec3(0.212671, 0.71516, 0.072169));
    float keep = amount + 1.0;
    return (rgb * keep) + vec3((luma * (1.0 - keep)));
}
vec3 paletteColor(vec3 rgb) {
    int levels = int(features.w);
    ivec3 q = ivec3(((clamp(rgb, vec3(0.0), vec3(1.0)) * float(levels - 1)) + 0.5));
    return texelFetch(sampler2D(paletteTexture, pointSampler), ivec2((q.x + (q.z * levels)), q.y), 0).rgb;
}
void main() {
    ivec2 size = textureSize(sampler2D(colorTexture, pointSampler), 0);
    ivec2 p = ivec2(gl_FragCoord.xy);
    vec4 color = texelFetch(sampler2D(colorTexture, pointSampler), p, 0);
    vec4 center = postNormalAt(p, size);
    float centerDepth = postDepthAt(center, p, size);
    vec4 edge_1 = edge;
    vec3 rgb = color.rgb;
    if (features.x > 0.5) {
        vec3 n = (center.xyz * 2.0) - 1.0;
        float depthEdge = 0.0;
        float normalEdge = 0.0;
        for (int i = 0; i < 4; i++) {
            vec4 neighbor = postNormalAt((p + OUTLINE_OFFSETS[i]), size);
            float depthDelta = postDepthAt(neighbor, (p + OUTLINE_OFFSETS[i]), size) - centerDepth;
            if (depthDelta > edge_1.x) {
                depthEdge = 1.0;
            }
            vec3 nq = (neighbor.xyz * 2.0) - 1.0;
            if (((abs(depthDelta) < edge_1.x) && (dot(n, nq) < edge_1.y)) && (n.y > (nq.y + 0.1))) {
                normalEdge = 1.0;
            }
        }
        rgb = mix(rgb, (rgb * edge_1.z), (depthEdge * color.a));
        rgb = mix(rgb, ((rgb * edge_1.w) + vec3(0.02)), ((normalEdge * color.a) * (1.0 - depthEdge)));
    }
    vec4 fog_1 = fog;
    float haze = smoothstep(fog_1.x, fog_1.y, centerDepth) * fog_1.z;
    rgb = mix(rgb, fogColor.rgb, haze);
    rgb = saturated(rgb, colorAdjust.x);
    if (features.y > 0.5) {
        rgb = paletteColor(rgb);
    }
    fragColor = vec4(rgb, 1.0);
    return;
}
@end

@fs blitFs
layout(binding=0) uniform blitParams {
    vec4 pixel;
};
layout(binding=0) uniform texture2D sceneTexture;
layout(binding=0) uniform sampler pointSampler;
layout(location=0) out vec4 fragColor;
void main() {
    ivec2 size = textureSize(sampler2D(sceneTexture, pointSampler), 0);
    ivec2 p = ivec2(floor(((gl_FragCoord.xy + pixel.zw) / pixel.x)));
    vec4 texel = texelFetch(sampler2D(sceneTexture, pointSampler), clamp(p, ivec2(0, 0), (size - ivec2(1, 1))), 0);
    fragColor = vec4(texel.rgb, 1.0);
    return;
}
@end

@vs particleVisualPixelArtVs
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
out vec2 uv;
out vec3 rootPosition;
out vec4 instanceColor;
out float depth01;
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
    vec4 clip = viewProj * vec4(world, 1.0);
    uv = vec2(((corner.x > 0.0) ? tile.z : tile.x), ((corner.y > 0.0) ? tile.y : tile.w));
    rootPosition = root.xyz;
    instanceColor = color;
    depth01 = clip.z;
    gl_Position = clip;
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
out vec2 uv;
out vec3 rootPosition;
out vec4 instanceColor;
out float depth01;
const vec2[6] PARTICLE_CORNERS = vec2[6](vec2(-0.5, -0.5), vec2(0.5, -0.5), vec2(0.5, 0.5), vec2(-0.5, -0.5), vec2(0.5, 0.5), vec2(-0.5, 0.5));
vec3 billboardPoint(vec3 position_1, vec2 size_1, vec2 anchor_1, vec2 corner, vec3 right, vec3 up) {
    vec2 offset = corner - anchor_1;
    return (position_1 + (right * (offset.x * size_1.x))) + (up * (offset.y * size_1.y));
}
void main() {
    vec2 corner = PARTICLE_CORNERS[uint(gl_VertexIndex) % 6];
    vec3 world = billboardPoint(position, size, anchor, corner, cameraRight.xyz, cameraUp.xyz);
    vec4 clip = viewProj * vec4(world, 1.0);
    uv = vec2(((corner.x > 0.0) ? tile.z : tile.x), ((corner.y > 0.0) ? tile.y : tile.w));
    rootPosition = position;
    instanceColor = color;
    depth01 = clip.z;
    gl_Position = clip;
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
@sampler_type clusterSampler nonfiltering
layout(binding=5) uniform sampler clusterSampler;
in vec2 uv;
in vec3 rootPosition;
in vec4 instanceColor;
in float depth01;
layout(location=0) out vec4 color;
layout(location=1) out vec4 normal;
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
vec3 toonPointLightAt(vec3 position, vec3 normal_1, vec4 at, vec4 tint, float normalWeight, float levels) {
    vec3 toLight = at.xyz - position;
    float distance_1 = length(toLight);
    float falloff = clamp((1.0 - (distance_1 / tint.a)), 0.0, 1.0);
    float facing = mix(1.0, max(dot(normal_1, (toLight / max(distance_1, 0.0001))), 0.0), normalWeight);
    float energy = ((falloff * falloff) * facing) * at.w;
    float level = floor(((energy * levels) + 0.35)) / levels;
    return srgbToLinear(tint.rgb) * level;
}
const uint DATA_ROW = 256;
ivec2 dataTexelOf(int i) {
    uint at = uvec2(ivec2(i, 0)).x;
    return ivec2(uvec2((at % DATA_ROW), (at / DATA_ROW)));
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
    vec4 texel = texture(sampler2D(billboardTexture, billboardSampler), uv);
#ifdef PREMULTIPLIED
    texel = straightTexel(texel);
#endif
    vec4 tint = billboardColor;
    float alpha = (tint.a * texel.a) * instanceColor.a;
#ifdef CUTOUT
    if (alpha < 0.5) {
        discard;
    }
#endif
    vec3 rgb = (tint.rgb * texel.rgb) * instanceColor.rgb;
    vec4 shape = billboard;
    if (shape.y != 0.0) {
        vec3 lightPoint = rootPosition + vec3(0.0, shape.z, 0.0);
        vec3 points = vec3(0.0);
        for (int i = 0; i < int(clusterScreen.z + 0.5); i++) {
            vec3 up = vec3(0.0, 1.0, 0.0);
            points = points + toonPointLightAt(lightPoint, up, billboardTexelOf(i, 0), billboardTexelOf(i, 1), 0.0, shape.x);
        }
        rgb = linearToSrgb((srgbToLinear(rgb) + points));
    }
    rgb = toneMapped(rgb, frame);
    vec4 color_1 = vec4(rgb, alpha);
#ifdef CUTOUT
    color_1 = vec4(rgb, 0.0);
#endif
#ifdef PREMULTIPLIED
    color_1 = vec4((rgb * alpha), alpha);
#endif
    color = color_1;
    normal = vec4(0.5, 1.0, 0.5, depth01);
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
out float depth01;
const vec2[6] PARTICLE_CORNERS = vec2[6](vec2(-0.5, -0.5), vec2(0.5, -0.5), vec2(0.5, 0.5), vec2(-0.5, -0.5), vec2(0.5, 0.5), vec2(-0.5, 0.5));
void main() {
    vec2 corner = PARTICLE_CORNERS[uint(gl_VertexIndex) % 6];
    vec3 right = cameraRight.xyz;
    vec3 up = cameraUp.xyz;
    vec3 world = (root.xyz + (right * (corner.x * root.w))) + (up * (corner.y * root.w));
    vec4 clip = viewProj * vec4(world, 1.0);
    particleColor = color;
    depth01 = clip.z;
    gl_Position = clip;
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
in float depth01;
layout(location=0) out vec4 color;
layout(location=1) out vec4 normal;
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
    vec4 color_1 = particleColor;
#ifdef CUTOUT
    if (color_1.a < 0.5) {
        discard;
    }
    color_1 = vec4(color_1.rgb, 0.0);
#endif
    color = vec4(toneMapped(color_1.rgb, frame), color_1.a);
    normal = vec4(0.5, 1.0, 0.5, depth01);
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
out float depth01;
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
    vec4 clip = viewProj * world;
    worldPosition = world.xyz;
    worldNormal = skinNormal(matrix, normal);
    baseColor = color;
    depth01 = clip.z;
    gl_Position = clip;
    return;
#else
    mat4 matrix_1 = instanceWorld(instanceRow0, instanceRow1, instanceRow2);
    vec4 world_1 = matrix_1 * vec4(position, 1.0);
    vec4 clip_1 = viewProj * world_1;
    worldPosition = world_1.xyz;
    worldNormal = skinNormal(matrix_1, normal);
    baseColor = (color * instanceColor);
    depth01 = clip_1.z;
    gl_Position = clip_1;
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
};
#endif
#if defined(PBR) && defined(EMISSIVE)
layout(binding=3) uniform pbrEmissiveMaterialParams {
    vec4 material;
    vec4 materialColor;
    vec4 pbr;
    vec4 uvMatrix;
    vec4 uvMotion;
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
in float depth01;
layout(location=0) out vec4 color;
layout(location=1) out vec4 normal;
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
vec3 toonPointLightAt(vec3 position, vec3 normal_1, vec4 at, vec4 tint, float normalWeight, float levels) {
    vec3 toLight = at.xyz - position;
    float distance_1 = length(toLight);
    float falloff = clamp((1.0 - (distance_1 / tint.a)), 0.0, 1.0);
    float facing = mix(1.0, max(dot(normal_1, (toLight / max(distance_1, 0.0001))), 0.0), normalWeight);
    float energy = ((falloff * falloff) * facing) * at.w;
    float level = floor(((energy * levels) + 0.35)) / levels;
    return srgbToLinear(tint.rgb) * level;
}
const int RECORD_TEXELS = 6;
ivec2 recordTexelOf(int light, int texel) {
    return dataTexelOf(((light * RECORD_TEXELS) + texel));
}
vec4 litTexelOf(int light, int texel) {
    return texelFetch(sampler2D(lightRecords, clusterSampler), recordTexelOf(light, texel), 0);
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
vec4 toonShade(vec3 n, vec3 surfaceNormal, vec3 position, vec2 frag, vec4 surfaceColor) {
    vec4 params = materialOf();
    vec4 dir = dirLight;
    float lambert = max(dot(n, dir.xyz), 0.0) * dir.w;
#ifdef SHADOWED
    lambert = lambert * dirShadowAt(position, surfaceNormal);
#endif
    vec3 light = srgbToLinear(ambient.rgb) + (srgbToLinear(dirColor.rgb) * lambert);
    ivec4 cluster = litClusterOf(frag, position);
    for (int k = 0; k < (cluster.y + cluster.z); k++) {
        int i = litLightOf(cluster, k);
        light = light + toonPointLightAt(position, n, litTexelOf(i, 0), litTexelOf(i, 1), 1.0, params.x);
    }
    vec3 surface = srgbToLinear(saturated(surfaceColor.rgb, params.y));
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
    vec4 surfaceColor = tintedSurface(baseColor);
    vec4 shaded = toonShade(n, n, worldPosition, gl_FragCoord.xy, surfaceColor);
#ifdef CUTOUT
    if (shaded.a < params.w) {
        discard;
    }
#endif
    color = vec4(toneMapped(shaded.rgb, frame), shaded.a);
    normal = vec4(((n * 0.5) + 0.5), depth01);
    return;
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
out vec4 baseColor;
out float depth01;
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
    vec4 clip = viewProj * world;
    worldPosition = world.xyz;
    worldNormal = skinNormal(matrix, normal);
#ifdef NORMAL_MAP
    worldTangent = vec4((mat3(matrix) * tangent.xyz), (tangent.w * handednessOf(matrix)));
#endif
    surfaceUv = uv;
    baseColor = color;
    depth01 = clip.z;
    gl_Position = clip;
    return;
#else
    mat4 matrix_1 = instanceWorld(instanceRow0, instanceRow1, instanceRow2);
    vec4 world_1 = matrix_1 * vec4(position, 1.0);
    vec4 clip_1 = viewProj * world_1;
    worldPosition = world_1.xyz;
    worldNormal = skinNormal(matrix_1, normal);
#ifdef NORMAL_MAP
    worldTangent = vec4((mat3(matrix_1) * tangent.xyz), (tangent.w * handednessOf(matrix_1)));
#endif
    surfaceUv = uv;
    baseColor = (color * instanceColor);
    depth01 = clip_1.z;
    gl_Position = clip_1;
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
#if (!defined(PBR) && ((defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE)) && !defined(EMISSIVE)) || (defined(BACK_TEXTURE) && !defined(EMISSIVE)) || (defined(DISSOLVE) && !defined(EMISSIVE))
layout(binding=3) uniform movingMaterialParams {
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
#if !defined(PBR) && !((defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE)) && defined(EMISSIVE)
layout(binding=3) uniform emissiveMaterialParams {
    vec4 material;
    vec4 materialColor;
    vec4 emissive;
};
#endif
#if (!defined(PBR) && ((defined(UV_TRANSFORM) || defined(BACK_TEXTURE)) || defined(DISSOLVE)) && defined(EMISSIVE)) || (defined(BACK_TEXTURE) && defined(EMISSIVE)) || (defined(DISSOLVE) && defined(EMISSIVE))
layout(binding=3) uniform movingEmissiveMaterialParams {
    vec4 material;
    vec4 materialColor;
    vec4 uvMatrix;
    vec4 uvMotion;
    vec4 backUvMatrix;
    vec4 backUvOffset;
    vec4 dissolve;
    vec4 dissolveEdge;
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
};
#endif
#if defined(PBR) && defined(EMISSIVE)
layout(binding=3) uniform pbrEmissiveMaterialParams {
    vec4 material;
    vec4 materialColor;
    vec4 pbr;
    vec4 uvMatrix;
    vec4 uvMotion;
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
in vec4 baseColor;
in float depth01;
layout(location=0) out vec4 color;
layout(location=1) out vec4 normal;
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
#ifdef UV_TRANSFORM
vec2 movedUv(vec2 uv, vec4 matrix, vec4 motion, float time) {
    return ((mat2(matrix.xy, matrix.zw) * uv) + motion.xy) + (motion.zw * time);
}
#endif
#ifdef UV_TRANSFORM
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
#ifdef UV_TRANSFORM
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
vec3 toonPointLightAt(vec3 position, vec3 normal_1, vec4 at, vec4 tint, float normalWeight, float levels) {
    vec3 toLight = at.xyz - position;
    float distance_1 = length(toLight);
    float falloff = clamp((1.0 - (distance_1 / tint.a)), 0.0, 1.0);
    float facing = mix(1.0, max(dot(normal_1, (toLight / max(distance_1, 0.0001))), 0.0), normalWeight);
    float energy = ((falloff * falloff) * facing) * at.w;
    float level = floor(((energy * levels) + 0.35)) / levels;
    return srgbToLinear(tint.rgb) * level;
}
const int RECORD_TEXELS = 6;
ivec2 recordTexelOf(int light, int texel) {
    return dataTexelOf(((light * RECORD_TEXELS) + texel));
}
vec4 litTexelOf(int light, int texel) {
    return texelFetch(sampler2D(lightRecords, clusterSampler), recordTexelOf(light, texel), 0);
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
vec4 toonShade(vec3 n, vec3 surfaceNormal, vec3 position, vec2 frag, vec4 surfaceColor) {
    vec4 params = materialOf();
    vec4 dir = dirLight;
    float lambert = max(dot(n, dir.xyz), 0.0) * dir.w;
#ifdef SHADOWED
    lambert = lambert * dirShadowAt(position, surfaceNormal);
#endif
    vec3 light = srgbToLinear(ambient.rgb) + (srgbToLinear(dirColor.rgb) * lambert);
    ivec4 cluster = litClusterOf(frag, position);
    for (int k = 0; k < (cluster.y + cluster.z); k++) {
        int i = litLightOf(cluster, k);
        light = light + toonPointLightAt(position, n, litTexelOf(i, 0), litTexelOf(i, 1), 1.0, params.x);
    }
    vec3 surface = srgbToLinear(saturated(surfaceColor.rgb, params.y));
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
    vec3 surfaceNormal = facingNormal(normalize(worldNormal), params.z, gl_FrontFacing);
    vec3 n = surfaceNormal;
#ifdef NORMAL_MAP
    vec3 normalTexel = texture(sampler2D(normalTexture, baseSampler), uv).rgb;
    float face = faceOf(params.z, gl_FrontFacing);
    n = mappedNormal(normalize(worldNormal), worldTangent, face, normalTexel);
#endif
    vec4 surfaceColor = tintedSurface(vec4((baseColor.rgb * texel.rgb), (baseColor.a * texel.a)));
    vec4 shaded = toonShade(n, surfaceNormal, worldPosition, gl_FragCoord.xy, surfaceColor);
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
    normal = vec4(((n * 0.5) + 0.5), depth01);
    return;
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
out vec3 worldNormal;
out vec2 surfaceUv;
out vec4 baseColor;
out float depth01;
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
    vec4 clip = (viewProj * matrix) * vec4(position, 1.0);
    worldNormal = skinNormal(matrix, normal);
    surfaceUv = uv;
    baseColor = color;
    depth01 = clip.z;
    gl_Position = clip;
    return;
#else
    mat4 matrix_1 = instanceWorld(instanceRow0, instanceRow1, instanceRow2);
    vec4 clip_1 = (viewProj * matrix_1) * vec4(position, 1.0);
    worldNormal = skinNormal(matrix_1, normal);
    surfaceUv = uv;
    baseColor = (color * instanceColor);
    depth01 = clip_1.z;
    gl_Position = clip_1;
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
in vec3 worldNormal;
in vec2 surfaceUv;
in vec4 baseColor;
in float depth01;
layout(location=0) out vec4 color;
layout(location=1) out vec4 normal;
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
vec3 facingNormal(vec3 normal_1, float doubleSided, bool frontFacing) {
    return ((doubleSided > 0.5) && (!frontFacing)) ? (-normal_1) : normal_1;
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
    vec3 n = facingNormal(normalize(worldNormal), params.z, gl_FrontFacing);
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
    normal = vec4(((n * 0.5) + 0.5), depth01);
    return;
}
@end

