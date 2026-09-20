package com.sidequest.pixellight

internal const val VERT = """#version 300 es
in vec2 aPos;

void main() {
    gl_Position = vec4(aPos, 0.0, 1.0);
}
"""

internal const val COMMON = """#version 300 es
precision mediump float;

uniform highp sampler2D uParams;

float prmTick()   { return texelFetch(uParams, ivec2(0), 0).x; }
vec2  prmStar()   { return texelFetch(uParams, ivec2(0), 0).yz; }
float prmStarR()  { return texelFetch(uParams, ivec2(0), 0).w; }
float prmStarI()  { return texelFetch(uParams, ivec2(1), 0).x; }
vec2  prmRes()    { return texelFetch(uParams, ivec2(1), 0).yz; }

const float BAYER[16] = float[16](
    0.0, 8.0, 2.0, 10.0,
    12.0, 4.0, 14.0, 6.0,
    3.0, 11.0, 1.0, 9.0,
    15.0, 7.0, 13.0, 5.0
);

float bayer4(vec2 px) {
    int x = int(px.x) & 3;
    int y = int(px.y) & 3;
    return BAYER[x + y * 4] / 16.0;
}

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

float vnoise(float x) {
    float i = floor(x);
    float f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    return mix(hash12(vec2(i, 0.0)), hash12(vec2(i + 1.0, 0.0)), f);
}

float fbm(float x) {
    return vnoise(x) * 0.55 + vnoise(x * 2.13 + 7.0) * 0.3 + vnoise(x * 4.71 + 13.0) * 0.15;
}

float rockH(float x) {
    float bowl = 0.16 + 0.20 * (1.0 - smoothstep(0.0, 0.85, x));
    float jag = fbm(x * 4.3) * 0.5 + fbm(x * 9.1 + 5.0) * 0.5;
    return bowl * (0.72 + 0.62 * jag);
}

vec3 SKY_RAMP(int lvl) {
    if (lvl <= 0) return vec3(0.020, 0.008, 0.039);
    if (lvl == 1) return vec3(0.051, 0.024, 0.125);
    if (lvl == 2) return vec3(0.106, 0.055, 0.188);
    return vec3(0.176, 0.094, 0.251);
}
"""

internal const val SCENE_FRAG = COMMON + """
out vec4 outColor;

void main() {
    vec2 px = gl_FragCoord.xy;
    vec2 p = px / prmRes();
    float aspect = prmRes().x / prmRes().y;
    vec2 star = prmStar();

    // --- sky: 4-level ramp, Bayer-dithered, haze leaning to the upper right
    float h = p.y + 0.12 * smoothstep(0.3, 1.0, p.x);
    int lvl = int(clamp(floor(h * 3.999 + (bayer4(px) - 0.5) * 0.9), 0.0, 3.0));
    vec3 col = SKY_RAMP(lvl);

    // --- starfield: one candidate per 4px cell, 3 brightness levels, twinkle at 2Hz
    vec2 cell = floor(px / 4.0);
    vec2 rnd = hash22(cell);
    if (rnd.x < 0.09) {
        vec2 sp = (cell + rnd) * 4.0;
        float d = length(px - sp);
        if (d < 1.5) {
            float hb = hash12(cell + 17.0);
            float b = (floor(hb * 3.0) + 1.0) / 3.0;
            float tw = step(0.78, hash12(cell + floor(prmTick() * 2.0)));
            b *= mix(0.55, 1.0, tw);
            float coronaFade = smoothstep(0.13, 0.22, length((p - star) * vec2(aspect, 1.0)));
            col = mix(col, mix(vec3(0.75, 0.8, 1.0), vec3(1.0), hb), b * coronaFade);
        }
    }

    // --- ringed gas giant, upper right, tilted 20deg
    vec2 gc = vec2(0.74, 0.72);
    float gr = 0.17;
    vec2 g = (p - gc) * vec2(aspect, 1.0);
    float ca = cos(0.35), sa = sin(0.35);
    vec2 rt = vec2(g.x * ca + g.y * sa, -g.x * sa + g.y * ca);
    float rn = rt.x / gr;
    float rs = rt.y / (gr * 0.30);
    bool inRingBand = abs(rs) < 1.0 && abs(rn) > 1.25 && abs(rn) < 2.1;
    vec3 ringCol = vec3(0.839, 0.808, 0.722);
    float ringA = 0.15 + 0.18 * mod(floor(abs(rn) * 3.0), 2.0);
    if (inRingBand && rs <= 0.0) col = mix(col, ringCol, ringA);
    if (length(g) < gr) {
        float band = rt.y / gr + 0.6 * (fbm(rt.x * 3.0 + 40.0) - 0.5);
        float k = mod(floor(band * 5.0), 3.0);
        vec3 planet = k < 0.5 ? vec3(0.902, 0.875, 0.816)
                   : k < 1.5 ? vec3(0.549, 0.522, 0.459)
                             : vec3(0.839, 0.808, 0.722);
        col = planet;
    }
    if (inRingBand && rs > 0.0) col = mix(col, ringCol, ringA);

    // --- two moonlets near the giant
    vec2 m1c = (p - vec2(0.615, 0.575)) * vec2(aspect, 1.0);
    if (length(m1c) < 0.030) col = dot(m1c, vec2(-1.0, 0.3)) > 0.0 ? vec3(0.902, 0.875, 0.816) : vec3(0.549, 0.522, 0.459);
    vec2 m2c = (p - vec2(0.885, 0.615)) * vec2(aspect, 1.0);
    if (length(m2c) < 0.019) col = dot(m2c, vec2(-1.0, 0.3)) > 0.0 ? vec3(0.902, 0.875, 0.816) : vec3(0.549, 0.522, 0.459);

    // --- rock silhouette, bottom-left, jagged
    float rh = rockH(p.x);
    if (p.y < rh) {
        float tex = step(0.62, fbm(p.x * 12.0) * 0.6 + bayer4(px) * 0.8);
        col = tex > 0.5 ? vec3(0.086, 0.024, 0.125) : vec3(0.031, 0.016, 0.051);
        float slope = (rockH(p.x + 0.004) - rockH(p.x - 0.004)) / 0.008;
        float facing = clamp(0.55 - slope * 1.1, 0.0, 1.0);
        float ed = rh - p.y;
        float rim = step(ed, 0.016 + (bayer4(px) - 0.5) * 0.004) * step(0.3, facing);
        col = mix(col, vec3(0.290, 0.145, 0.310), rim);
    }

    outColor = vec4(col, 1.0);
}
"""

internal const val LIGHT_FRAG = COMMON + """
out vec4 outColor;

void main() {
    vec2 px = gl_FragCoord.xy;
    vec2 p = px / prmRes();
    float aspect = prmRes().x / prmRes().y;
    vec2 star = prmStar();
    float starR = prmStarR();
    float starI = prmStarI();
    vec3 add = vec3(0.0);

    float d = length((p - star) * vec2(aspect, 1.0)) / starR;
    float rh = rockH(p.x);
    bool inRock = p.y < rh;

    if (!inRock) {
        float q = floor((1.0 - d) * 6.0 + (bayer4(px) - 0.5) * 0.9);
        vec3 c = q >= 5.0 ? vec3(1.0, 1.0, 1.0) * 1.35
               : q == 4.0 ? vec3(1.0, 0.918, 0.0)
               : q == 3.0 ? vec3(1.0, 0.4, 0.0)
               : q == 2.0 ? vec3(0.8, 0.067, 0.0)
               : q == 1.0 ? vec3(0.478, 0.051, 0.0)
                          : vec3(0.0);
        add += c * starI;

        float glow = floor(exp(-max(d, 0.0) * 2.2) * 3.0);
        add += vec3(0.8, 0.067, 0.0) * (glow / 3.0) * 0.30 * starI;
    } else {
        float slope = (rockH(p.x + 0.004) - rockH(p.x - 0.004)) / 0.008;
        float facing = clamp(0.55 - slope * 1.1, 0.0, 1.0);
        float ed = rh - p.y;
        float wl = floor(clamp(facing * 2.2 - 0.6, 0.0, 2.0) + (bayer4(px) - 0.5) * 0.8);
        add += vec3(1.0, 0.4, 0.0) * (wl / 2.0) * 0.55 * starI * step(ed, 0.05);
    }

    outColor = vec4(add, 1.0);
}
"""

internal const val BLIT_FRAG = """#version 300 es
precision mediump float;
uniform sampler2D uTex;
uniform vec2 uRes;
out vec4 outColor;
void main() {
    vec2 uv = gl_FragCoord.xy / uRes;
    outColor = texture(uTex, uv);
}
"""
