let flowingNetShaderSource = #"""
#include <metal_stdlib>
using namespace metal;

struct NetUniforms {
    float2 res;
    float  px;
    float  t;
    float  fade;
    float4 rip[5];
};

struct NetOut { float4 position [[position]]; };

vertex NetOut flowingNetVertex(uint vid [[vertex_id]]) {
    float2 pos[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    NetOut o;
    o.position = float4(pos[vid], 0, 1);
    return o;
}

constant float CELL = 10.0;
constant float W1_SCALE = 620.0, W1_AMP = 150.0;
constant float W2_SCALE = 300.0, W2_AMP = 30.0;
constant float W3_SCALE = 70.0,  W3_AMP = 2.2;
constant float BREATH_DEPTH = 0.08;
constant float BREATH_W = 0.57120;
constant float SIGMA = 0.80686;
constant float SIGMA_MIN = 0.44590;
constant float TONE_STEP = 0.05;
constant float TONE_TOP = 0.3;
constant float DITHER = 0.2;
constant float STRETCH_DIM = 0.7;
constant float GATHER = 0.5;
constant float GATHER_REACH = 0.5;
constant float GLASS_R = 12.0, GLASS_RIM = 7.0, GLASS_DIM = 0.45;
constant float EXPOSURE = 0.55;
constant float EVENNESS = 0.0;
constant float EVEN_MIN = 0.12, EVEN_MAX = 1.8;
constant float2 BIAS_DIR = float2(0.469472, 0.882948);
constant float BIAS_PITCH = 1.18;
constant float BIAS_INK = 0.55;
constant float2 DRIFT = float2(4.0, -2.5);
constant float SEG = 12.0;
constant float P_GREEN = 0.82, P_TEAL = 0.91;
constant float3 GROUND = float3(4, 13, 9) / 255.0;
constant float3 GREEN  = float3(56, 112, 74) / 255.0;
constant float3 TEAL   = float3(41, 91, 92) / 255.0;
constant float3 AMBER  = float3(98, 96, 42) / 255.0;
constant float3 HAZE   = float3(9, 14, 9) / 255.0;
constant float INK = 0.5;
constant float RIP_SPEED = 620.0;
constant float RIP_AMP = 30.0;
constant float RIP_WIDTH = 150.0;
constant float RIP_TAU = 0.7;
constant float RIP_REACH = 820.0;

static inline float  gmod(float x, float y)  { return x - y * floor(x / y); }
static inline float2 gmod(float2 x, float y) { return x - y * floor(x / y); }

// Ashima / McEwan 3-D simplex noise, MIT.
static inline float3 mod289(float3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
static inline float4 mod289(float4 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
static inline float4 permute(float4 x) { return mod289(((x * 34.0) + 1.0) * x); }
static inline float4 taylorInvSqrt(float4 r) { return 1.79284291400159 - 0.85373472095314 * r; }

static float snoise(float3 v) {
    const float2 C = float2(1.0 / 6.0, 1.0 / 3.0);
    const float4 D = float4(0.0, 0.5, 1.0, 2.0);
    float3 i  = floor(v + dot(v, C.yyy));
    float3 x0 = v - i + dot(i, C.xxx);
    float3 g = step(x0.yzx, x0.xyz);
    float3 l = 1.0 - g;
    float3 i1 = min(g.xyz, l.zxy);
    float3 i2 = max(g.xyz, l.zxy);
    float3 x1 = x0 - i1 + C.xxx;
    float3 x2 = x0 - i2 + C.yyy;
    float3 x3 = x0 - D.yyy;
    i = mod289(i);
    float4 p = permute(permute(permute(
                i.z + float4(0.0, i1.z, i2.z, 1.0))
              + i.y + float4(0.0, i1.y, i2.y, 1.0))
              + i.x + float4(0.0, i1.x, i2.x, 1.0));
    float n_ = 0.142857142857;
    float3 ns = n_ * D.wyz - D.xzx;
    float4 j = p - 49.0 * floor(p * ns.z * ns.z);
    float4 x_ = floor(j * ns.z);
    float4 y_ = floor(j - 7.0 * x_);
    float4 x = x_ * ns.x + ns.yyyy;
    float4 y = y_ * ns.x + ns.yyyy;
    float4 h = 1.0 - abs(x) - abs(y);
    float4 b0 = float4(x.xy, y.xy);
    float4 b1 = float4(x.zw, y.zw);
    float4 s0 = floor(b0) * 2.0 + 1.0;
    float4 s1 = floor(b1) * 2.0 + 1.0;
    float4 sh = -step(h, float4(0.0));
    float4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
    float4 a1 = b1.xzyw + s1.xzyw * sh.zzww;
    float3 p0 = float3(a0.xy, h.x);
    float3 p1 = float3(a0.zw, h.y);
    float3 p2 = float3(a1.xy, h.z);
    float3 p3 = float3(a1.zw, h.w);
    float4 norm = taylorInvSqrt(float4(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)));
    p0 *= norm.x; p1 *= norm.y; p2 *= norm.z; p3 *= norm.w;
    float4 m = max(0.6 - float4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), 0.0);
    m = m * m;
    return 42.0 * dot(m * m, float4(dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3)));
}

static inline float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static inline float bayer2(float2 p) { return gmod(2.0 * p.x + 3.0 * p.y, 4.0); }
static inline float bayer4(float2 px) {
    return 4.0 * bayer2(gmod(px, 2.0)) + bayer2(gmod(floor(px * 0.5), 2.0));
}

static float3 threadInk(float idx, float along, float salt) {
    float phase = hash21(float2(idx, salt + 7.0)) * SEG;
    float2 k = float2(idx, floor((along + phase) / SEG) + salt * 97.0);
    float h = hash21(k);
    float tone = 0.84 + 0.32 * hash21(k + 31.7);
    float3 c = h < P_GREEN ? GREEN : (h < P_TEAL ? TEAL : AMBER);
    return c * tone;
}

fragment float4 flowingNetFragment(NetOut in [[stage_in]], constant NetUniforms &u [[buffer(0)]]) {
    float2 frag = float2(in.position.x, u.res.y - in.position.y);
    float2 size = u.res / u.px;
    float2 p = frag / u.px;
    float m = min(size.x, size.y);

    float2 dEdge = min(p, size - p);
    float corner = smoothstep(0.0, 0.42 * m, length(dEdge));
    float edge = 0.35 + 0.65 * smoothstep(0.0, 0.14 * m, min(dEdge.x, dEdge.y));
    float amp = corner * edge;

    float t = u.t;
    float breath = 1.0 + BREATH_DEPTH * sin(t * BREATH_W);
    float2 drift = DRIFT * t;
    float3 n1 = float3((p + drift) / W1_SCALE, t * 0.035);
    float2 w1 = float2(snoise(n1), snoise(n1 + float3(17.3, 9.1, 4.7)));
    float2 q = p + w1 * W1_AMP * amp * breath;
    float3 n2 = float3((q - drift * 0.6) / W2_SCALE + 3.1, t * 0.05 + 11.0);
    float2 w2 = float2(snoise(n2), snoise(n2 + float3(5.9, 23.7, 2.2)));
    float2 r = q + w2 * W2_AMP * amp * breath;
    float3 n3 = float3((r + drift * 0.3) / W3_SCALE + 41.0, t * 0.12 + 5.0);
    r += float2(snoise(n3), snoise(n3 + float3(9.7, 3.3, 1.1))) * W3_AMP;

    for (int i = 0; i < 5; i++) {
        float4 rip = u.rip[i];
        float age = rip.z;
        float2 d = p - rip.xy;
        float dist = max(length(d), 1e-4);
        float radius = RIP_SPEED * age;
        float x = (dist - radius) / RIP_WIDTH;
        float packet = sin(x * 3.14159) * exp(-x * x * 2.2);
        float decay = exp(-age / RIP_TAU) * (1.0 - smoothstep(0.0, RIP_REACH, radius));
        float spread = 1.0 / sqrt(1.0 + dist / RIP_WIDTH);
        float live = step(0.0, age) * amp;
        r -= (d / dist) * (RIP_AMP * packet * decay * spread * live);
    }

    float gather = 0.0;
    float2 rg = r;
    for (int i = 0; i < 4; i++) {
        float2 c = float2((i == 1 || i == 3) ? size.x : 0.0, i >= 2 ? size.y : 0.0);
        float w = 1.0 - smoothstep(0.0, GATHER_REACH * m, length(p - c));
        rg += GATHER * w * (r - c);
        gather += w;
    }
    r = rg;

    float2 g = r / CELL;
    float2 fw = max(fwidth(g), float2(1e-5));
    float2 dist = (0.5 - abs(fract(g) - 0.5)) / fw;
    float sigma = max(SIGMA * u.px, SIGMA_MIN);
    float2 cov = exp(-0.5 * (dist * dist) / (sigma * sigma));

    float gb = dot(r, BIAS_DIR) / (CELL * BIAS_PITCH);
    float fwb = max(fwidth(gb), 1e-5);
    float distb = (0.5 - abs(fract(gb) - 0.5)) / fwb;
    float covb = exp(-0.5 * (distb * distb) / (sigma * sigma));

    float rest = (1.0 + GATHER * gather) / (CELL * u.px);
    float2 stack = fw / rest;
    float stackb = fwb / (rest / BIAS_PITCH);
    float fold = smoothstep(1.3, 3.5, max(max(stack.x, stack.y), stackb));
    float shade = mix(STRETCH_DIM, 1.0, smoothstep(0.55, 1.0, min(stack.x, stack.y)));

    float2 evenX = clamp(1.0 / stack, EVEN_MIN, EVEN_MAX);
    float evenB = clamp(1.0 / stackb, EVEN_MIN, EVEN_MAX);
    float seam = 1.0 - EVENNESS;
    cov = mix(cov, float2(0.6), smoothstep(float2(3.0), float2(6.0), stack) * seam) * INK * mix(float2(1.0), evenX, EVENNESS);
    covb = mix(covb, 0.6, smoothstep(3.0, 6.0, stackb) * seam) * INK * BIAS_INK * mix(1.0, evenB, EVENNESS);

    float2 idx = floor(g + 0.5);
    float3 cx = threadInk(idx.x, g.y, 0.0);
    float3 cy = threadInk(idx.y, g.x, 1.0);
    float3 cb = threadInk(floor(gb + 0.5), dot(r, float2(-BIAS_DIR.y, BIAS_DIR.x)) / CELL, 2.0);

    float3 col = GROUND + HAZE * fold * (1.0 - EVENNESS);
    col = mix(col, cb, covb);
    col = mix(col, cx, cov.x);
    col = mix(col, cy, cov.y);
    col *= mix(shade, 1.0, EVENNESS) * EXPOSURE;

    float2 uv = p / size;
    float d = length((uv - float2(0.5, 0.6)) * float2(1.0, 1.25));
    col *= 1.0 - u.fade * 0.3 * smoothstep(0.3, 0.85, d);

    float3 ground = GROUND * EXPOSURE;
    float3 lift = clamp(col - ground, 0.0, TONE_TOP);
    float dither = ((bayer4(floor(frag)) + 0.5) / 16.0 - 0.5) * DITHER;
    lift = floor(lift / TONE_STEP + 0.5 + dither) * TONE_STEP;
    col = ground + lift;

    float2 hs = size * 0.5;
    float2 cq = abs(p - hs) - (hs - GLASS_R);
    float sd = length(max(cq, 0.0)) + min(max(cq.x, cq.y), 0.0) - GLASS_R;
    float inside = -sd;
    col *= clamp(inside + 0.5, 0.0, 1.0) * mix(GLASS_DIM, 1.0, smoothstep(0.0, GLASS_RIM, inside));

    return float4(col, 1.0);
}
"""#
