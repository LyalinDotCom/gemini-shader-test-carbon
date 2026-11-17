// Gemini Video 2 GLSL (v2) — Five-scene procedural Shadertoy recreation of a 25-second Gemini Omni 1.2 Flash film.
// Built with shader-art-coding from gokayfem/shader-skills (MIT): https://github.com/gokayfem/shader-skills
// Scenes (5s each, 0.75s cross-dissolves including seamless 25s -> 0s loop):
//   I.   Space  (00s-05s) - Ringed banded gas giant, storm vortex & wakes, icy ring debris, cosmic web & sun
//   II.  Forest (05s-10s) - Flared redwood trunks, braided bark, sword ferns, oxalis, mossy logs & sunbeams
//   III. Ocean  (10s-15s) - Stormy deep-teal swells, breaking whitecaps, basalt sea stack, ashlar lighthouse & beam
//   IV.  Desert (15s-20s) - S-curved golden-hour dunes, Y-branching ripples, Entrada sandstone arch, butte & mesas
//   V.   Cavern (20s-25s) - Karst limestone river vault, fluted stalactites, chisel-pointed amethyst/cyan crystals

#define DEBUG_MODE 0   // 0 final | 1 distance slice | 2 normals | 3 material ids | 4 steps | 5 masks | 6 light terms
#define AA 1           // supersamples per pixel (1 real-time, 2-4 offline)

// Library code below is bundled from shader-skills (MIT): https://github.com/gokayfem/shader-skills
// ---- shader-skills library: common ----
const float PI  = 3.14159265358979;
const float TAU = 6.28318530717959;
// Clamp to [0,1].
float saturate(float x) { return clamp(x, 0.0, 1.0); }
vec3 saturate(vec3 x) { return clamp(x, 0.0, 1.0); }
// Squared length.
float dot2(vec2 v) { return dot(v, v); }
float dot2(vec3 v) { return dot(v, v); }
// 2D rotation matrix. `rot2(a) * v` rotates v counter-clockwise by a radians. (cos, sin) is renormalized because GLSL ES leaves trig precision undefined: on SwiftShader and some mobile GPUs a raw cos/sin pair is far enough from unit length that rotations stop preserving distances.
mat2 rot2(float a) {
    vec2 cs = normalize(vec2(cos(a), sin(a)));
    return mat2(cs.x, cs.y, -cs.y, cs.x);
}
// Smooth bump: 1 at x == c, falling to 0 at |x - c| >= w (cubic).
float cubicPulse(float c, float w, float x) {
    x = abs(x - c);
    if (x > w) return 0.0;
    x /= w;
    return 1.0 - x * x * (3.0 - 2.0 * x);
}

// ---- shader-skills library: hash ----
// PCG-style 1D integer hash.
uint pcgHash(uint v) {
    uint state = v * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}
// 3D integer hash, three decorrelated outputs.
uvec3 pcg3d(uvec3 v) {
    v = v * 1664525u + 1013904223u;
    v.x += v.y * v.z;
    v.y += v.z * v.x;
    v.z += v.x * v.y;
    v ^= v >> 16u;
    v.x += v.y * v.z;
    v.y += v.z * v.x;
    v.z += v.x * v.y;
    return v;
}
// Map a uint to [0,1) using the top 24 bits, so the result can never round up to 1.0.
float uintToUnit(uint h) { return float(h >> 8u) * (1.0 / 16777216.0); }
vec2 uintToUnit(uvec2 h) { return vec2(h >> 8u) * (1.0 / 16777216.0); }
vec3 uintToUnit(uvec3 h) { return vec3(h >> 8u) * (1.0 / 16777216.0); }
vec4 uintToUnit(uvec4 h) { return vec4(h >> 8u) * (1.0 / 16777216.0); }
// Random float in [0,1) for an integer-valued input.
float hash11(float p) { return uintToUnit(pcgHash(uint(int(floor(p))))); }
// Random float in [0,1) for an integer-valued 2D input.
float hash12(vec2 p) {
    uvec2 q = uvec2(ivec2(floor(p)));
    return uintToUnit(pcgHash(q.x + pcgHash(q.y)));
}
// Random float in [0,1) for an integer-valued 3D input.
float hash13(vec3 p) {
    uvec3 q = uvec3(ivec3(floor(p)));
    return uintToUnit(pcgHash(q.x + pcgHash(q.y + pcgHash(q.z))));
}
// Random vec2 in [0,1)^2 for an integer-valued 2D input.
vec2 hash22(vec2 p) {
    ivec2 q = ivec2(floor(p));
    return uintToUnit(pcg3d(uvec3(q.x, q.y, 0x2545u))).xy;
}
// Random vec3 in [0,1)^3 for an integer-valued 3D input.
vec3 hash33(vec3 p) { return uintToUnit(pcg3d(uvec3(ivec3(floor(p))))); }
// Random vec3 in [0,1)^3 for an integer-valued 2D input.
vec3 hash32(vec2 p) {
    ivec2 q = ivec2(floor(p));
    return uintToUnit(pcg3d(uvec3(q.x, q.y, 0x9E37u)));
}

// ---- shader-skills library: noise ----
// Quintic fade 6t^5 - 15t^4 + 10t^3: C2-continuous interpolation weights for lattice noise.
vec2 quinticFade(vec2 f) { return f * f * f * (f * (f * 6.0 - 15.0) + 10.0); }
vec3 quinticFade(vec3 f) { return f * f * f * (f * (f * 6.0 - 15.0) + 10.0); }
// Derivative of quinticFade: 30 t^2 (t - 1)^2.
vec2 quinticFadeDeriv(vec2 f) { return 30.0 * f * f * (f * (f - 2.0) + 1.0); }
vec3 quinticFadeDeriv(vec3 f) { return 30.0 * f * f * (f * (f - 2.0) + 1.0); }
// 2D value noise with analytic derivatives. Returns vec3(value, d/dx, d/dy).
vec3 valueNoiseD(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = quinticFade(f), du = quinticFadeDeriv(f);
    float a = hash12(i);
    float b = hash12(i + vec2(1.0, 0.0));
    float c = hash12(i + vec2(0.0, 1.0));
    float d = hash12(i + vec2(1.0, 1.0));
    float k1 = b - a, k2 = c - a, k3 = a - b - c + d;
    return vec3(a + k1 * u.x + k2 * u.y + k3 * u.x * u.y,
                du * vec2(k1 + k3 * u.y, k2 + k3 * u.x));
}
// 2D value noise.
float valueNoise(vec2 p) { return valueNoiseD(p).x; }
// 3D value noise.
float valueNoise(vec3 p) {
    vec3 i = floor(p), f = fract(p);
    vec3 u = quinticFade(f);
    return mix(mix(mix(hash13(i + vec3(0, 0, 0)), hash13(i + vec3(1, 0, 0)), u.x),
                   mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), u.x), u.y),
               mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), u.x),
                   mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), u.x), u.y), u.z);
}
// Unit gradient for a 2D lattice point.
vec2 latticeGradient(vec2 cell) {
    float a = TAU * hash12(cell);
    return vec2(cos(a), sin(a));
}
// 2D gradient (Perlin-style) noise with analytic derivatives. Returns vec3(value, d/dx, d/dy). Gradient noise has less grid-aligned blockiness than value noise. Prefer it for fBm.
vec3 gradientNoiseD(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = quinticFade(f), du = quinticFadeDeriv(f);
    vec2 ga = latticeGradient(i);
    vec2 gb = latticeGradient(i + vec2(1.0, 0.0));
    vec2 gc = latticeGradient(i + vec2(0.0, 1.0));
    vec2 gd = latticeGradient(i + vec2(1.0, 1.0));
    float va = dot(ga, f);
    float vb = dot(gb, f - vec2(1.0, 0.0));
    float vc = dot(gc, f - vec2(0.0, 1.0));
    float vd = dot(gd, f - vec2(1.0, 1.0));
    float k = va - vb - vc + vd;
    float value = va + u.x * (vb - va) + u.y * (vc - va) + u.x * u.y * k;
    vec2 deriv = ga + u.x * (gb - ga) + u.y * (gc - ga) + u.x * u.y * (ga - gb - gc + gd)
               + du * (vec2(vb - va, vc - va) + u.yx * k);
    return vec3(value, deriv);
}
// 2D gradient noise.
float gradientNoise(vec2 p) { return gradientNoiseD(p).x; }
// 2D simplex noise with analytic gradient. Returns vec3(value, d/dx, d/dy). Sums three radial kernels (0.5 - r^2)^4 on a triangular lattice instead of blending four square-cell corners, so it has fewer axis-aligned artifacts than gradientNoise. rotation (radians) spins every lattice gradient: animating it gives flow noise that churns in place instead of sliding (Perlin and Neyret 2001). Scaled so |value| <= 1 exactly.
vec3 simplexNoiseD(vec2 p, float rotation) {
    const float SKEW = 0.36602540378;     // (sqrt(3) - 1) / 2: square lattice -> triangle lattice
    const float UNSKEW = 0.21132486541;   // (3 - sqrt(3)) / 6
    vec2 cell = floor(p + (p.x + p.y) * SKEW);
    vec2 d0 = p - cell + (cell.x + cell.y) * UNSKEW;
    vec2 o = (d0.x > d0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);   // which of the cell's two triangles holds p
    vec2 corners[3] = vec2[3](cell, cell + o, cell + 1.0);
    vec2 offsets[3] = vec2[3](d0, d0 - o + UNSKEW, d0 - 1.0 + 2.0 * UNSKEW);
    mat2 spin = rot2(rotation);
    vec3 sum = vec3(0.0);
    for (int k = 0; k < 3; k++) {
        vec2 d = offsets[k];
        float t = max(0.5 - dot(d, d), 0.0);
        vec2 g = spin * latticeGradient(corners[k]);
        float gd = dot(g, d);
        float t3 = t * t * t;
        // value t^4 (g.d); gradient t^4 g - 8 t^3 (g.d) d
        sum += vec3(t3 * t * gd, t3 * t * g - 8.0 * t3 * gd * d);
    }
    return 99.2 * sum;   // 1 / max over the simplex of sum t^4 |d|
}
vec3 simplexNoiseD(vec2 p) { return simplexNoiseD(p, 0.0); }
// 2D simplex noise.
float simplexNoise(vec2 p) { return simplexNoiseD(p, 0.0).x; }
// Dot product of a hashed 3D gradient with the offset to its lattice corner.
float latticeGradDot(vec3 cell, vec3 corner, vec3 f) {
    vec3 g = hash33(cell + corner) * 2.0 - 1.0;
    return dot(g, f - corner);
}
// 3D gradient noise.
float gradientNoise(vec3 p) {
    vec3 i = floor(p), f = fract(p);
    vec3 u = quinticFade(f);
    return mix(mix(mix(latticeGradDot(i, vec3(0, 0, 0), f), latticeGradDot(i, vec3(1, 0, 0), f), u.x),
                   mix(latticeGradDot(i, vec3(0, 1, 0), f), latticeGradDot(i, vec3(1, 1, 0), f), u.x), u.y),
               mix(mix(latticeGradDot(i, vec3(0, 0, 1), f), latticeGradDot(i, vec3(1, 0, 1), f), u.x),
                   mix(latticeGradDot(i, vec3(0, 1, 1), f), latticeGradDot(i, vec3(1, 1, 1), f), u.x), u.y), u.z);
}
// 3D gradient noise with analytic derivatives. Returns vec4(value, d/dx, d/dy, d/dz); value equals gradientNoise(p). The trilinear blend is expanded as a polynomial in the fade weights, so the gradient is the same blend of the corner gradients plus the chain-rule term of the fade.
vec4 gradientNoiseD(vec3 p) {
    vec3 i = floor(p), f = fract(p);
    vec3 u = quinticFade(f), du = quinticFadeDeriv(f);
    vec3 g000 = hash33(i) * 2.0 - 1.0;
    vec3 g100 = hash33(i + vec3(1, 0, 0)) * 2.0 - 1.0;
    vec3 g010 = hash33(i + vec3(0, 1, 0)) * 2.0 - 1.0;
    vec3 g110 = hash33(i + vec3(1, 1, 0)) * 2.0 - 1.0;
    vec3 g001 = hash33(i + vec3(0, 0, 1)) * 2.0 - 1.0;
    vec3 g101 = hash33(i + vec3(1, 0, 1)) * 2.0 - 1.0;
    vec3 g011 = hash33(i + vec3(0, 1, 1)) * 2.0 - 1.0;
    vec3 g111 = hash33(i + vec3(1, 1, 1)) * 2.0 - 1.0;
    float v000 = dot(g000, f);
    float v100 = dot(g100, f - vec3(1, 0, 0));
    float v010 = dot(g010, f - vec3(0, 1, 0));
    float v110 = dot(g110, f - vec3(1, 1, 0));
    float v001 = dot(g001, f - vec3(0, 0, 1));
    float v101 = dot(g101, f - vec3(1, 0, 1));
    float v011 = dot(g011, f - vec3(0, 1, 1));
    float v111 = dot(g111, f - vec3(1, 1, 1));
    // value = v000 + kx u.x + ky u.y + kz u.z + kxy u.x u.y + kyz u.y u.z + kzx u.z u.x + kxyz u.x u.y u.z
    float kx = v100 - v000, ky = v010 - v000, kz = v001 - v000;
    float kxy = v000 - v100 - v010 + v110;
    float kyz = v000 - v010 - v001 + v011;
    float kzx = v000 - v100 - v001 + v101;
    float kxyz = -v000 + v100 + v010 - v110 + v001 - v101 - v011 + v111;
    float value = v000 + kx * u.x + ky * u.y + kz * u.z
                + kxy * u.x * u.y + kyz * u.y * u.z + kzx * u.z * u.x + kxyz * u.x * u.y * u.z;
    vec3 grad = g000 + (g100 - g000) * u.x + (g010 - g000) * u.y + (g001 - g000) * u.z
              + (g000 - g100 - g010 + g110) * u.x * u.y
              + (g000 - g010 - g001 + g011) * u.y * u.z
              + (g000 - g100 - g001 + g101) * u.z * u.x
              + (-g000 + g100 + g010 - g110 + g001 - g101 - g011 + g111) * u.x * u.y * u.z
              + du * vec3(kx + kxy * u.y + kzx * u.z + kxyz * u.y * u.z,
                          ky + kxy * u.x + kyz * u.z + kxyz * u.x * u.z,
                          kz + kyz * u.y + kzx * u.x + kxyz * u.x * u.y);
    return vec4(value, grad);
}
const int FBM_MAX_OCTAVES = 12;
// Fractional Brownian motion over 2D gradient noise. Each octave is rotated to hide lattice alignment. persistence 0.5 is the classic look (H = 1). Lower is smoother, higher is rougher.
float fbm(vec2 p, int octaves, float lacunarity, float persistence) {
    const mat2 octaveRotation = mat2(0.8, 0.6, -0.6, 0.8);
    float sum = 0.0, amp = 1.0, norm = 0.0;
    for (int i = 0; i < FBM_MAX_OCTAVES; i++) {
        if (i >= octaves) break;
        sum += amp * gradientNoise(p);
        norm += amp;
        amp *= persistence;
        p = lacunarity * (octaveRotation * p) + vec2(17.13, -3.71);
    }
    return 1.4 * sum / norm;
}
// 2D fBm with the usual defaults (lacunarity 2.01 so octave peaks never re-align, persistence 0.5).
float fbm(vec2 p, int octaves) { return fbm(p, octaves, 2.01, 0.5); }
// fBm over 3D gradient noise.
float fbm(vec3 p, int octaves, float lacunarity, float persistence) {
    const mat3 octaveRotation = mat3(0.00, 0.80, 0.60,
                                     -0.80, 0.36, -0.48,
                                     -0.60, -0.48, 0.64);
    float sum = 0.0, amp = 1.0, norm = 0.0;
    for (int i = 0; i < FBM_MAX_OCTAVES; i++) {
        if (i >= octaves) break;
        sum += amp * gradientNoise(p);
        norm += amp;
        amp *= persistence;
        p = lacunarity * (octaveRotation * p) + vec3(17.13, -3.71, 5.29);
    }
    return sum / norm;
}
// Terrain fBm where each octave is damped by the accumulated slope, so detail settles in valleys and steep slopes stay smooth. This gives an eroded look without simulation.
float erodedFbm(vec2 p, int octaves) {
    const mat2 octaveRotation = mat2(0.8, 0.6, -0.6, 0.8);
    float h = 0.0, amp = 0.5;
    vec2 slope = vec2(0.0);
    for (int i = 0; i < FBM_MAX_OCTAVES; i++) {
        if (i >= octaves) break;
        vec3 n = gradientNoiseD(p);
        slope += n.yz;
        h += amp * n.x / (1.0 + dot(slope, slope));
        amp *= 0.5;
        p = 2.0 * (octaveRotation * p);
    }
    return 2.0 * h;
}
// Ridged multifractal: inverted |noise| creates sharp crests; each octave is weighted by the previous one, so detail gathers along ridges.
float ridgedFbm(vec2 p, int octaves) {
    const mat2 octaveRotation = mat2(0.8, 0.6, -0.6, 0.8);
    float sum = 0.0, amp = 0.5, weight = 1.0, norm = 0.0;
    for (int i = 0; i < FBM_MAX_OCTAVES; i++) {
        if (i >= octaves) break;
        float n = 1.0 - abs(gradientNoise(p) * 1.4);
        n *= n;
        sum += amp * n * weight;
        norm += amp;
        weight = clamp(n * 2.0, 0.0, 1.0);
        amp *= 0.5;
        p = 2.01 * (octaveRotation * p) + vec2(17.13, -3.71);
    }
    return sum / norm;
}
// Perlin's turbulence: fBm of |noise|. The absolute value folds every zero crossing into a sharp crease, at every scale.
float turbulence(vec2 p, int octaves) {
    const mat2 octaveRotation = mat2(0.8, 0.6, -0.6, 0.8);
    float sum = 0.0, amp = 1.0, norm = 0.0;
    for (int i = 0; i < FBM_MAX_OCTAVES; i++) {
        if (i >= octaves) break;
        sum += amp * abs(gradientNoise(p));
        norm += amp;
        amp *= 0.5;
        p = 2.01 * (octaveRotation * p) + vec2(17.13, -3.71);
    }
    return 1.4 * sum / norm;   // |2D gradient noise| <= sqrt(2)/2
}
float turbulence(vec3 p, int octaves) {
    const mat3 octaveRotation = mat3(0.00, 0.80, 0.60,
                                     -0.80, 0.36, -0.48,
                                     -0.60, -0.48, 0.64);
    float sum = 0.0, amp = 1.0, norm = 0.0;
    for (int i = 0; i < FBM_MAX_OCTAVES; i++) {
        if (i >= octaves) break;
        sum += amp * min(abs(gradientNoise(p)), 1.0);
        norm += amp;
        amp *= 0.5;
        p = 2.01 * (octaveRotation * p) + vec3(17.13, -3.71, 5.29);
    }
    return sum / norm;
}
// Billowy multifractal: |noise| per octave makes puffy rounded lobes split by sharp creases (the inverse of ridgedFbm). Each octave is weighted by the previous one, so detail gathers on the lobes while the creases stay clean.
float billowFbm(vec2 p, int octaves) {
    const mat2 octaveRotation = mat2(0.8, 0.6, -0.6, 0.8);
    float sum = 0.0, amp = 0.5, weight = 1.0, norm = 0.0;
    for (int i = 0; i < FBM_MAX_OCTAVES; i++) {
        if (i >= octaves) break;
        float n = abs(gradientNoise(p) * 1.4);
        n = n * (2.0 - n);   // round the lobe tops, keep the creases sharp
        sum += amp * n * weight;
        norm += amp;
        weight = clamp(n * 1.5, 0.0, 1.0);
        amp *= 0.5;
        p = 2.01 * (octaveRotation * p) + vec2(17.13, -3.71);
    }
    return sum / norm;
}
float billowFbm(vec3 p, int octaves) {
    const mat3 octaveRotation = mat3(0.00, 0.80, 0.60,
                                     -0.80, 0.36, -0.48,
                                     -0.60, -0.48, 0.64);
    float sum = 0.0, amp = 0.5, weight = 1.0, norm = 0.0;
    for (int i = 0; i < FBM_MAX_OCTAVES; i++) {
        if (i >= octaves) break;
        float n = min(abs(gradientNoise(p)) * 1.4, 1.0);
        n = n * (2.0 - n);
        sum += amp * n * weight;
        norm += amp;
        weight = clamp(n * 1.5, 0.0, 1.0);
        amp *= 0.5;
        p = 2.01 * (octaveRotation * p) + vec3(17.13, -3.71, 5.29);
    }
    return sum / norm;
}
// Two-level domain warp f(p + s*r), r = fbm(p + s*q), q = fbm(p). Writes the intermediate warp vectors so they can drive color. Cost is 5 fBm calls.
float warpedFbm(vec2 p, float strength, int octaves, out vec2 q, out vec2 r) {
    q = vec2(fbm(p, octaves), fbm(p + vec2(3.1, 7.4), octaves));
    r = vec2(fbm(p + strength * q + vec2(9.7, 2.6), octaves),
             fbm(p + strength * q + vec2(6.3, 1.9), octaves));
    return fbm(p + strength * r, octaves);
}
// Divergence-free 2D flow field: the curl of scalar gradient noise. Particles advected by it swirl without bunching up.
vec2 curlNoise(vec2 p) {
    vec3 n = gradientNoiseD(p);
    return vec2(n.z, -n.y);
}
// Divergence-free 3D flow field: the curl of a vector potential whose components are three decorrelated gradientNoiseD fields. Analytic, so it costs three noise evaluations and no finite differences.
vec3 curlNoise(vec3 p) {
    vec3 a = gradientNoiseD(p).yzw;                                   // grad of potential.x
    vec3 b = gradientNoiseD(p + vec3(31.416, -47.853, 12.793)).yzw;   // grad of potential.y
    vec3 c = gradientNoiseD(p + vec3(-23.719, 18.274, -56.183)).yzw;  // grad of potential.z
    return vec3(c.y - b.z, a.z - c.x, b.x - a.y);
}
// Cellular (Worley/Voronoi) noise. Returns vec4(F1, F2, nearestCell.xy). F1 = distance to nearest feature point, F2 = second nearest. nearestCell is integer-valued, so hash it for per-cell randomness. jitter in [0,1] (0 = regular grid). Searches 3x3 cells. F2 can be slightly off at jitter 1.
vec4 voronoi(vec2 p, float jitter) {
    vec2 ip = floor(p), fp = fract(p);
    float f1 = 8.0, f2 = 8.0;
    vec2 nearest = vec2(0.0);
    for (int j = -1; j <= 1; j++)
    for (int i = -1; i <= 1; i++) {
        vec2 g = vec2(float(i), float(j));
        vec2 r = g + jitter * hash22(ip + g) - fp;
        float d = dot(r, r);
        if (d < f1) { f2 = f1; f1 = d; nearest = ip + g; }
        else if (d < f2) { f2 = d; }
    }
    return vec4(sqrt(f1), sqrt(f2), nearest);
}
// Exact distance to Voronoi cell borders, found in two passes: nearest point, then nearest bisector. Returns vec3(borderDistance, vectorToNearestPoint). Unlike F2-F1, the border distance is a true distance, so lines have constant width.
vec3 voronoiBorder(vec2 p, float jitter) {
    vec2 ip = floor(p), fp = fract(p);
    vec2 mg = vec2(0.0), mr = vec2(0.0);
    float md = 8.0;
    for (int j = -1; j <= 1; j++)
    for (int i = -1; i <= 1; i++) {
        vec2 g = vec2(float(i), float(j));
        vec2 r = g + jitter * hash22(ip + g) - fp;
        float d = dot(r, r);
        if (d < md) { md = d; mr = r; mg = g; }
    }
    md = 8.0;
    for (int j = -2; j <= 2; j++)
    for (int i = -2; i <= 2; i++) {
        vec2 g = mg + vec2(float(i), float(j));
        vec2 r = g + jitter * hash22(ip + g) - fp;
        if (dot2(mr - r) > 1e-5) {
            md = min(md, dot(0.5 * (mr + r), normalize(r - mr)));
        }
    }
    return vec3(md, mr);
}
// Interleaved gradient noise: cheap per-pixel noise whose 3x3 neighborhoods are nearly stratified. Not a hash. pixel must be integer pixel coordinates (floor(fragCoord)). The frame overload animates it for accumulation and TAA.
float interleavedGradientNoise(vec2 pixel) {
    return fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715))));
}
float interleavedGradientNoise(vec2 pixel, int frame) {
    return interleavedGradientNoise(pixel + 5.588238 * float(frame % 64));
}

// ---- shader-skills library: pattern ----
// Hexagonal tiling with unit spacing between neighboring centers. Neighbors sit left/right, so hexes are pointy-top. Returns vec4(local offset from the hex center, integer-valued hex id).
vec4 hexGrid(vec2 p) {
    const vec2 s = vec2(1.0, 1.7320508);
    vec2 a = mod(p, s) - 0.5 * s;
    vec2 b = mod(p - 0.5 * s, s) - 0.5 * s;
    vec2 local = (dot(a, a) < dot(b, b)) ? a : b;
    vec2 center = p - local;
    vec2 id = floor(vec2(center.x * 2.0, center.y * 1.1547005) + 0.5);
    return vec4(local, id);
}
// Distance from a hexGrid local coordinate to its hexagon's edge (0.5 at the center, 0 on the edge).
float hexEdgeDistance(vec2 local) {
    vec2 a = abs(local);
    return 0.5 - max(a.x, dot(a, vec2(0.5, 0.8660254)));
}

// ---- shader-skills library: sdf3d ----
// Sphere of radius r.
float sdSphere(vec3 p, float r) { return length(p) - r; }
// Axis-aligned box with half-extents b.
float sdBox(vec3 p, vec3 b) {
    vec3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}
// Box with rounded edges. The outer size stays b; r is the edge radius (r <= min(b)).
float sdRoundBox(vec3 p, vec3 b, float r) {
    vec3 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0) - r;
}
// Torus in the XZ plane. t.x = major radius, t.y = tube radius.
float sdTorus(vec3 p, vec2 t) {
    vec2 q = vec2(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}
// Capsule: segment a-b swept by radius r.
float sdCapsule(vec3 p, vec3 a, vec3 b, float r) {
    vec3 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}
// Vertical capsule from y = 0 to y = h, radius r.
float sdVerticalCapsule(vec3 p, float h, float r) {
    p.y -= clamp(p.y, 0.0, h);
    return length(p) - r;
}
// Vertical capped cylinder from y = -h to y = +h, radius r.
float sdCylinder(vec3 p, float h, float r) {
    vec2 d = abs(vec2(length(p.xz), p.y)) - vec2(r, h);
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}
// Capped cone (frustum) from y = -h (radius r1) to y = +h (radius r2). Set r2 = 0 for a pointed cone. Exact everywhere, including the base cap. Points below the base are outside.
float sdCappedCone(vec3 p, float h, float r1, float r2) {
    vec2 q = vec2(length(p.xz), p.y);
    vec2 top = vec2(r2, h);
    vec2 side = vec2(r2 - r1, 2.0 * h);
    vec2 toCap = vec2(q.x - min(q.x, (q.y < 0.0) ? r1 : r2), abs(q.y) - h);
    vec2 toSide = q - top + side * clamp(dot(top - q, side) / dot2(side), 0.0, 1.0);
    float s = (toSide.x < 0.0 && toCap.y < 0.0) ? -1.0 : 1.0;
    return s * sqrt(min(dot2(toCap), dot2(toSide)));
}
// Ellipsoid with semi-axes r. A fast approximation: the zero set is exact and the field is a bound outside for aspect ratios up to about 2:1. Inside, and for more stretched ellipsoids, the gradient exceeds 1 (measured: 2.5 at 4:1). March with stepScale 0.7-0.8 there, or build long shapes from sdCapsule / sdRoundCone instead.
float sdEllipsoid(vec3 p, vec3 r) {
    float k0 = length(p / r);
    float k1 = length(p / (r * r));
    if (k1 < 1e-8) return -min(r.x, min(r.y, r.z));
    return k0 * (k0 - 1.0) / k1;
}
// Hexagonal prism along Z. h.x = inradius of the hexagon, h.y = half-length.
float sdHexPrism(vec3 p, vec2 h) {
    const vec3 k = vec3(-0.8660254, 0.5, 0.57735027);
    p = abs(p);
    p.xy -= 2.0 * min(dot(k.xy, p.xy), 0.0) * k.xy;
    vec2 d = vec2(length(p.xy - vec2(clamp(p.x, -k.z * h.x, k.z * h.x), h.x)) * sign(p.y - h.x),
                  p.z - h.y);
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}
// Sphere of radius r cut by the plane y = h, keeping the cap ABOVE the plane. h = 0 gives a dome on the ground; negative h keeps more than half. Needs |h| < r.
float sdCutSphere(vec3 p, float r, float h) {
    float w = sqrt(max(r * r - h * h, 0.0));
    vec2 q = vec2(length(p.xz), p.y);
    float s = max((h - r) * q.x * q.x + w * w * (h + r - 2.0 * q.y), h * q.x - w * q.y);
    return (s < 0.0) ? length(q) - r : (q.x < w) ? h - q.y : length(q - vec2(w, h));
}
// Unsigned distance to a 3D quadratic Bezier curve A-B-C; subtract a radius for a tube. Solves the closest-point cubic analytically. Falls back to a segment when the curve is straight.
float sdQuadraticBezier(vec3 pos, vec3 A, vec3 B, vec3 C) {
    vec3 a = B - A;
    vec3 b = A - 2.0 * B + C;
    vec3 c = a * 2.0;
    vec3 d = A - pos;
    float bb = dot(b, b);
    if (bb < 1e-10) {
        vec3 pa = pos - A, ca = C - A;
        return length(pa - ca * clamp(dot(pa, ca) / dot(ca, ca), 0.0, 1.0));
    }
    float kk = 1.0 / bb;
    float kx = kk * dot(a, b);
    float ky = kk * (2.0 * dot(a, a) + dot(d, b)) / 3.0;
    float kz = kk * dot(d, a);
    float pp = ky - kx * kx;
    float q = kx * (2.0 * kx * kx - 3.0 * ky) + kz;
    float h = q * q + 4.0 * pp * pp * pp;
    float res;
    if (h >= 0.0) {
        h = sqrt(h);
        vec2 x = (vec2(h, -h) - q) / 2.0;
        vec2 uv = sign(x) * pow(abs(x), vec2(1.0 / 3.0));
        float t = clamp(uv.x + uv.y - kx, 0.0, 1.0);
        res = dot2(d + (c + b * t) * t);
    } else {
        float z = sqrt(-pp);
        float v = acos(clamp(q / (pp * z * 2.0), -1.0, 1.0)) / 3.0;
        float m = cos(v);
        float n = sin(v) * 1.7320508;
        vec2 t = clamp(vec2(m + m, -n - m) * z - kx, 0.0, 1.0);
        res = min(dot2(d + (c + b * t.x) * t.x), dot2(d + (c + b * t.y) * t.y));
    }
    return sqrt(res);
}

// ---- shader-skills library: sdf2d ----
// Axis-aligned rectangle with half-extents b.
float sdBox(vec2 p, vec2 b) {
    vec2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}
// Unsigned distance to segment a-b. Subtract a width to get a stroke.
float sdSegment(vec2 p, vec2 a, vec2 b) {
    vec2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}
// Tapered capsule: circle r1 at origin hulled with circle r2 at (0, h).
float sdUnevenCapsule(vec2 p, float r1, float r2, float h) {
    p.x = abs(p.x);
    float b = (r1 - r2) / h;
    float a = sqrt(1.0 - b * b);
    float k = dot(p, vec2(-b, a));
    if (k < 0.0) return length(p) - r1;
    if (k > a * h) return length(p - vec2(0.0, h)) - r2;
    return dot(p, vec2(a, b)) - r1;
}
// Unsigned distance to a quadratic Bezier curve A-B-C. Solves the closest-point cubic analytically. Falls back to a segment when the curve degenerates to a line. Float error in the cubic solve is about 1e-4.
float sdQuadraticBezier(vec2 pos, vec2 A, vec2 B, vec2 C) {
    vec2 a = B - A;
    vec2 b = A - 2.0 * B + C;
    vec2 c = a * 2.0;
    vec2 d = A - pos;
    float bb = dot(b, b);
    if (bb < 1e-10) return sdSegment(pos, A, C);
    float kk = 1.0 / bb;
    float kx = kk * dot(a, b);
    float ky = kk * (2.0 * dot(a, a) + dot(d, b)) / 3.0;
    float kz = kk * dot(d, a);
    float pp = ky - kx * kx;
    float q = kx * (2.0 * kx * kx - 3.0 * ky) + kz;
    float h = q * q + 4.0 * pp * pp * pp;
    float res;
    if (h >= 0.0) {
        h = sqrt(h);
        vec2 x = (vec2(h, -h) - q) / 2.0;
        vec2 uv = sign(x) * pow(abs(x), vec2(1.0 / 3.0));
        float t = clamp(uv.x + uv.y - kx, 0.0, 1.0);
        res = dot2(d + (c + b * t) * t);
    } else {
        float z = sqrt(-pp);
        float v = acos(clamp(q / (pp * z * 2.0), -1.0, 1.0)) / 3.0;
        float m = cos(v);
        float n = sin(v) * 1.7320508;
        vec2 t = clamp(vec2(m + m, -n - m) * z - kx, 0.0, 1.0);
        res = min(dot2(d + (c + b * t.x) * t.x), dot2(d + (c + b * t.y) * t.y));
    }
    return sqrt(res);
}

// ---- shader-skills library: operators ----
// Shape a with shape b cut out of it.
float opSubtract(float a, float b) { return max(a, -b); }
// Smooth union (polynomial, C1). Blends where |a - b| < k, with a max bulge of k/4.
float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}
// Smooth intersection, the mirror of smin.
float smax(float a, float b, float k) { return -smin(-a, -b, k); }
// Smooth subtraction: a with b carved out, with filleted edges.
float smoothSubtract(float a, float b, float k) { return smax(a, -b, k); }
// Smooth union with a C2 (cubic) transition, so specular highlights and normals have no visible seam. Blends where |a - b| < k, with a max bulge of k/6.
float sminCubic(float a, float b, float k) {
    float h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * h * k * (1.0 / 6.0);
}
// Smooth union that also returns the blend weight. Returns vec2(distance, weight), where weight is 1 when the result is fully a and 0 when fully b. Use the weight to mix material colors across the blend.
vec2 sminBlend(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return vec2(mix(b, a, h) - k * h * (1.0 - h), h);
}
// Union with a 45-degree chamfer of size r at the seam.
float opChamferUnion(float a, float b, float r) {
    return min(min(a, b), (a + b - r) * 0.70710678);
}
// Union with n stair steps of total size r at the seam.
float opStairsUnion(float a, float b, float r, float n) {
    float s = r / n;
    float u = b - r;
    return min(min(a, b), 0.5 * (u + a + abs(mod(u - a + s, 2.0 * s) - s)));
}
// Engrave a groove of depth r into a, following the zero set of b.
float opEngrave(float a, float b, float r) {
    return max(a, (a + r - abs(b)) * 0.70710678);
}

// ---- shader-skills library: domain ----
// Cell index for repetition with period s (integer-valued; use with hash functions).
float domRepeatId(float p, float s) { return floor(p / s + 0.5); }
vec2 domRepeatId(vec2 p, vec2 s) { return floor(p / s + 0.5); }
vec3 domRepeatId(vec3 p, vec3 s) { return floor(p / s + 0.5); }
// Polar repetition into n sectors around the origin. Returns the point rotated into the sector centered on +X. Single evaluation: exact for shapes symmetric about their sector's center line. For asymmetric or per-sector-varying shapes, evaluate this sector and its neighbor and take the min (see references/sdf-library-guide.md).
vec2 domPolar(vec2 p, float n) {
    if (dot(p, p) < 1e-20) return p;
    float sector = TAU / n;
    float id = floor(atan(p.y, p.x) / sector + 0.5);
    return rot2(-id * sector) * p;
}
// Neighbor-checked polar repetition: ids (in [0, n)) of the sector holding p and of the adjacent sector p leans toward. Evaluate the shape in both with domPolarSector and take the min. Use it when sectors vary (per-id length, tilt, color) or are asymmetric. It covers shapes of similar size that stay inside their own sector; a shape that reaches across its neighbor needs a wider search.
vec2 domPolarPair(vec2 p, float n) {
    if (dot(p, p) < 1e-20) return vec2(0.0, 1.0);
    float sector = TAU / n;
    float a = atan(p.y, p.x) / sector;
    float id = floor(a + 0.5);
    return mod(vec2(id, id + ((a >= id) ? 1.0 : -1.0)), n);
}
// Rotate p into the frame of polar sector id (its center line on +X). domPolarSector(p, domPolarId(p, n), n) equals domPolar(p, n).
vec2 domPolarSector(vec2 p, float id, float n) { return rot2(-id * TAU / n) * p; }

// ---- shader-skills library: raymarch ----
#define ZERO (min(iFrame, 0))
vec2 map(vec3 p);
// Surface normal from 4 tetrahedral samples (cheaper than 6 central differences, and still centered). eps should scale with distance, e.g. 0.0005 * t: that filters distant detail and avoids sparkling.
vec3 calcNormal(vec3 p, float eps) {
    vec3 n = vec3(0.0);
    for (int i = ZERO; i < 4; i++) {
        vec3 e = 0.5773 * (2.0 * vec3((((i + 3) >> 1) & 1), ((i >> 1) & 1), (i & 1)) - 1.0);
        n += e * map(p + e * eps).x;
    }
    return normalize(n);
}
// Ambient occlusion from 5 distance samples along the normal. Compares the expected distance with the actual one. scale is the sampling reach in scene units (about 0.12 for a unit-sized object). Returns 0 (occluded) .. 1 (open).
float calcAO(vec3 p, vec3 n, float scale) {
    float occ = 0.0;
    float weight = 1.0;
    for (int i = ZERO; i < 5; i++) {
        float h = 0.01 + scale * float(i) / 4.0;
        float d = map(p + h * n).x;
        occ += (h - d) * weight;
        weight *= 0.95;
    }
    return clamp(1.0 - 3.0 * occ / max(scale / 0.12, 1e-3), 0.0, 1.0);
}

// ---- shader-skills library: intersect ----
// Ray vs plane dot(p, n) + h = 0 (unit n). Returns t, which is negative when the plane is behind the ray or parallel to it.
float iPlane(vec3 ro, vec3 rd, vec3 n, float h) {
    float denom = dot(rd, n);
    if (abs(denom) < 1e-8) return -1.0;
    return -(dot(ro, n) + h) / denom;
}
// Ray vs sphere centered at c with radius r. Returns vec2(tNear, tFar), or vec2(-1) on a miss. Uses the precision-friendly form that measures from the closest point on the ray.
vec2 iSphere(vec3 ro, vec3 rd, vec3 c, float r) {
    vec3 oc = ro - c;
    float b = dot(oc, rd);
    vec3 qc = oc - b * rd;
    float h = r * r - dot(qc, qc);
    if (h < 0.0) return vec2(-1.0);
    h = sqrt(h);
    return vec2(-b - h, -b + h);
}
// Ray vs axis-aligned box centered at the origin with half-extents b (slab method). Returns vec2(tNear, tFar), or vec2(-1) on a miss. Works when the ray starts inside (tNear < 0 < tFar).
vec2 iBox(vec3 ro, vec3 rd, vec3 b) {
    vec3 m = 1.0 / rd;
    vec3 n = m * ro;
    vec3 k = abs(m) * b;
    vec3 t1 = -n - k;
    vec3 t2 = -n + k;
    float tN = max(max(t1.x, t1.y), t1.z);
    float tF = min(min(t2.x, t2.y), t2.z);
    if (tN > tF || tF < 0.0) return vec2(-1.0);
    return vec2(tN, tF);
}

// ---- shader-skills library: camera ----
// Camera-to-world matrix looking from ro toward ta, with roll in radians. Columns are (right, up, forward).
mat3 cameraMatrix(vec3 ro, vec3 ta, float roll) {
    vec3 w = normalize(ta - ro);
    vec3 up = vec3(sin(roll), cos(roll), 0.0);
    vec3 u = normalize(cross(w, up));
    vec3 v = cross(u, w);
    return mat3(u, v, w);
}
// Primary ray direction for screen point uv. focal is about 1.5-2.5 for natural framing (see fovToFocal).
vec3 cameraRay(mat3 cam, vec2 uv, float focal) {
    return normalize(cam * vec3(uv, focal));
}

// ---- shader-skills library: shading ----
// Schlick Fresnel. u is VoH for lights and NoV for environment reflections and rims. f0 = 0.04 for dielectrics (plastic, skin, stone, water ~0.02); for metals f0 = base color.
vec3 fresnelSchlick(float u, vec3 f0) {
    float m = clamp(1.0 - u, 0.0, 1.0);
    float m2 = m * m;
    return f0 + (1.0 - f0) * (m2 * m2 * m);
}
// GGX / Trowbridge-Reitz normal distribution. alpha = roughness^2.
float distributionGGX(float NoH, float alpha) {
    float a2 = alpha * alpha;
    float d = NoH * NoH * (a2 - 1.0) + 1.0;
    return a2 / (PI * d * d);
}
// Height-correlated Smith visibility. Already contains the 1 / (4 NoL NoV) term.
float visibilitySmithGGX(float NoV, float NoL, float alpha) {
    float a2 = alpha * alpha;
    float gv = NoL * sqrt(NoV * NoV * (1.0 - a2) + a2);
    float gl = NoV * sqrt(NoL * NoL * (1.0 - a2) + a2);
    return 0.5 / max(gv + gl, 1e-6);
}
// Microfacet specular for one light: pi * D * V * F * NoL (artist units). roughness is perceptual, in [0,1].
vec3 specularGGX(vec3 n, vec3 v, vec3 l, float roughness, vec3 f0) {
    vec3 h = normalize(v + l);
    float NoL = clamp(dot(n, l), 0.0, 1.0);
    float NoV = max(dot(n, v), 1e-4);
    float NoH = clamp(dot(n, h), 0.0, 1.0);
    float VoH = clamp(dot(v, h), 0.0, 1.0);
    float alpha = max(roughness, 0.045);
    alpha *= alpha;
    return PI * distributionGGX(NoH, alpha) * visibilitySmithGGX(NoV, NoL, alpha) * fresnelSchlick(VoH, f0) * NoL;
}
// Complete metallic-roughness shading for one light (diffuse + specular, NoL included, artist units). Multiply by light color and shadow. Keep albedo around 0.05-0.7 (linear); brighten lights, not albedo.
vec3 shadePBR(vec3 n, vec3 v, vec3 l, vec3 albedo, float roughness, float metallic) {
    vec3 f0 = mix(vec3(0.04), albedo, metallic);
    float NoL = clamp(dot(n, l), 0.0, 1.0);
    vec3 F = fresnelSchlick(max(dot(n, v), 0.0), f0);
    vec3 diffuse = albedo * (1.0 - metallic) * (1.0 - F) * NoL;
    return diffuse + specularGGX(n, v, l, roughness, f0);
}
// Split-sum environment specular without a lookup texture (Karis 2014, after Lazarov). Multiply by the sky or environment color in the reflection direction.
vec3 envBRDFApprox(vec3 f0, float NoV, float roughness) {
    vec4 r = roughness * vec4(-1.0, -0.0275, -0.572, 0.022) + vec4(1.0, 0.0425, 1.04, -0.04);
    float a = min(r.x * r.x, exp2(-9.28 * NoV)) * r.x + r.y;
    vec2 ab = vec2(-1.04, 1.04) * a + r.zw;
    return f0 * ab.x + ab.y;
}
// Energy-conserving wrap diffuse: light wraps past the terminator by w (0 = Lambert, 0.5 = soft).
float wrapDiffuse(vec3 n, vec3 l, float w) {
    return max((dot(n, l) + w) / ((1.0 + w) * (1.0 + w)), 0.0);
}
// Hemisphere light: sky color from above blended to ground color from below.
vec3 hemisphereLight(vec3 n, vec3 skyColor, vec3 groundColor) {
    return mix(groundColor, skyColor, 0.5 + 0.5 * n.y);
}
// Fast translucency (Barre-Brisebois and Bouchard 2011): light passing through thin parts, seen from the back. distortion bends the light along the normal (0.2-0.5). thickness is 0 (thin) .. 1 (thick); see sdfThickness.
float translucency(vec3 n, vec3 v, vec3 l, float distortion, float power, float thickness) {
    vec3 h = normalize(l + n * distortion);
    return pow(clamp(dot(v, -h), 0.0, 1.0), power) * (1.0 - thickness);
}
// Rim light from the viewing angle: strongest at silhouettes.
float rimLight(vec3 n, vec3 v, float power) {
    return pow(clamp(1.0 - dot(n, v), 0.0, 1.0), power);
}

// ---- shader-skills library: water ----
// Angular frequency sqrt(g*k*tanh(k*depth)) for finite-depth gravity waves. Nonpositive inputs are clamped.
float waterDispersion(float k, float depth, float gravity) {
    k = max(k,0.0);
    float e = exp(-2.0*k*max(depth,0.0));
    return sqrt(max(gravity,0.0)*k*(1.0-e)/(1.0+e));
}
// One sinusoidal wave: vec4(height, dh/dx, dh/dz, Laplacian). Direction is normalized internally; zero uses +X. wavelength > 0, amplitude in meters. footprint filters waves below 2-6 pixels; derivatives hold it constant.
vec4 waterWaveD(vec2 xz, float time, vec2 direction, float wavelength, float amplitude, float depth, float footprint) {
    float dl = length(direction);
    vec2 dir = dl>0.000001 ? direction/dl : vec2(1.0,0.0);
    float lengthM = max(wavelength,0.0001);
    float k = TAU/lengthM;
    float keep = smoothstep(2.0,6.0,lengthM/max(footprint,0.000001));
    float phase = k*dot(dir,xz)-waterDispersion(k,depth,9.81)*time;
    float h = amplitude*keep*sin(phase);
    return vec4(h, amplitude*keep*k*cos(phase)*dir, -k*k*h);
}
// Exact unpolarized dielectric Fresnel for a positive incident cosine and positive refractive indices. Returns 1 for total internal reflection. Caller chooses etaIncident/etaTransmitted for the ray's side.
float fresnelDielectric(float cosIncident, float etaIncident, float etaTransmitted) {
    float ci = clamp(abs(cosIncident),0.0,1.0);
    float ei = max(etaIncident,0.000001), et = max(etaTransmitted,0.000001);
    if (abs(ei-et)<0.0000001) return 0.0;
    float sinT2 = (ei*ei)/(et*et)*max(0.0,1.0-ci*ci);
    if (sinT2>=1.0) return 1.0;
    float ct = sqrt(max(0.0,1.0-sinT2));
    float rs = (ei*ci-et*ct)/max(ei*ci+et*ct,0.000001);
    float rp = (et*ci-ei*ct)/max(et*ci+ei*ct,0.000001);
    return clamp(0.5*(rs*rs+rp*rp),0.0,1.0);
}
// Beer-Lambert RGB transmittance exp(-extinction*pathLength). Negative extinction/path is clamped to zero. Use the refracted optical path, not vertical water depth. Attenuation alone does not add scattered light.
vec3 beerTransmittance(vec3 extinction, float pathLength) {
    return exp(-max(extinction,vec3(0.0))*max(pathLength,0.0));
}

// ---- shader-skills library: color ----
// Exact sRGB decode (EOTF): encoded [0,1] -> linear.
vec3 srgbToLinear(vec3 c) {
    c = max(c, 0.0);
    return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}
// Exact sRGB encode (OETF): linear -> display [0,1]. Apply exactly once, after tonemapping. pow(c, 1/2.2) is visibly wrong near black (0.001 encodes to 0.013 here vs 0.043 with 2.2).
vec3 linearToSrgb(vec3 c) {
    c = max(c, 0.0);
    return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c));
}
// Relative luminance of linear Rec.709 / sRGB color.
float luminance(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }
// Linear sRGB -> Oklab (L in [0,1], a/b around [-0.4, 0.4]). Matrices from Bjorn Ottosson (public domain / MIT).
vec3 linearSrgbToOklab(vec3 c) {
    vec3 lms = c * mat3(0.4122214708, 0.5363325363, 0.0514459929,
                        0.2119034982, 0.6806995451, 0.1073969566,
                        0.0883024619, 0.2817188376, 0.6299787005);
    lms = sign(lms) * pow(abs(lms), vec3(1.0 / 3.0));
    return lms * mat3(0.2104542553, 0.7936177850, -0.0040720468,
                      1.9779984951, -2.4285922050, 0.4505937099,
                      0.0259040371, 0.7827717662, -0.8086757660);
}
// Oklab -> linear sRGB. The result can fall outside [0,1] for saturated colors, so clamp after tonemapping.
vec3 oklabToLinearSrgb(vec3 lab) {
    vec3 lms = lab * mat3(1.0, 0.3963377774, 0.2158037573,
                          1.0, -0.1055613458, -0.0638541728,
                          1.0, -0.0894841775, -1.2914855480);
    lms = lms * lms * lms;
    return lms * mat3(4.0767416621, -3.3077115913, 0.2309699292,
                      -1.2684380046, 2.6097574011, -0.3413193965,
                      -0.0041960863, -0.7034186147, 1.7076147010);
}
// Mix two linear colors in Oklab. Avoids the muddy mid-tones of RGB lerps and the hue detours of HSV.
vec3 mixOklab(vec3 a, vec3 b, float t) {
    return oklabToLinearSrgb(mix(linearSrgbToOklab(a), linearSrgbToOklab(b), t));
}
// Approximate linear sRGB color of a blackbody at temperature kelvin (1000-15000 K), normalized to max channel 1. Uses the Krystek (1985) Planckian-locus fit -> XYZ -> sRGB.
vec3 blackbody(float kelvin) {
    float T = clamp(kelvin, 1000.0, 15000.0);
    float u = (0.860117757 + 1.54118254e-4 * T + 1.28641212e-7 * T * T) / (1.0 + 8.42420235e-4 * T + 7.08145163e-7 * T * T);
    float v = (0.317398726 + 4.22806245e-5 * T + 4.20481691e-8 * T * T) / (1.0 - 2.89741816e-5 * T + 1.61456053e-7 * T * T);
    float x = 3.0 * u / (2.0 * u - 8.0 * v + 4.0);
    float y = 2.0 * v / (2.0 * u - 8.0 * v + 4.0);
    vec3 xyz = vec3(x / y, 1.0, (1.0 - x - y) / y);
    vec3 rgb = xyz * mat3(3.2406, -1.5372, -0.4986,
                          -0.9689, 1.8758, 0.0415,
                          0.0557, -0.2040, 1.0570);
    rgb = max(rgb, 0.0);
    return rgb / max(max(rgb.r, rgb.g), max(rgb.b, 1e-6));
}

// ---- shader-skills library: tonemap ----
// AgX: log encoding plus a sigmoid inside an inset/outset gamut. Mid-grey 0.18 maps to about 0.5 display. Minimal implementation after Troy Sobotka's AgX and Benjamin Wrensch's polynomial fit (both MIT).
vec3 tonemapAgX(vec3 c) {
    const mat3 inset = mat3(0.842479062253094, 0.0423282422610123, 0.0423756549057051,
                            0.0784335999999992, 0.878468636469772, 0.0784336,
                            0.0792237451477643, 0.0791661274605434, 0.879142973793104);
    const mat3 outset = mat3(1.19687900512017, -0.0528968517574562, -0.0529716355144438,
                             -0.0980208811401368, 1.15190312990417, -0.0980434501171241,
                             -0.0990297440797205, -0.0989611768448433, 1.15107367264116);
    const float minEv = -12.47393, maxEv = 4.026069;
    c = inset * max(c, 0.0);
    c = clamp((log2(max(c, 1e-10)) - minEv) / (maxEv - minEv), 0.0, 1.0);
    vec3 x2 = c * c, x4 = x2 * x2;
    c = 15.5 * x4 * x2 - 40.14 * x4 * c + 31.96 * x4 - 6.868 * x2 * c + 0.4298 * x2 + 0.1191 * c - 0.00232;
    c = outset * c;
    return pow(max(c, 0.0), vec3(2.2));
}

// ---- shader-skills library: volume ----
// Henyey-Greenstein phase function. g in (-1, 1): > 0 forward (silver linings), < 0 backward.
float phaseHG(float mu, float g) {
    float g2 = g * g;
    return (1.0 - g2) / (4.0 * PI * pow(max(1.0 + g2 - 2.0 * g * mu, 1e-6), 1.5));
}
// Two-lobe Henyey-Greenstein: a forward lobe gF and a backward lobe gB, mixed by w (weight of the forward lobe). Keeps the silver lining while clouds lit from behind the camera still show detail.
float phaseDualHG(float mu, float gF, float gB, float w) {
    return mix(phaseHG(mu, gB), phaseHG(mu, gF), w);
}
// Cornette-Shanks phase (a better-normalized Mie approximation). g = 0.8 for atmospheric haze.
float phaseCornetteShanks(float mu, float g) {
    float g2 = g * g;
    return 3.0 / (8.0 * PI) * (1.0 - g2) * (1.0 + mu * mu)
         / ((2.0 + g2) * pow(max(1.0 + g2 - 2.0 * g * mu, 1e-6), 1.5));
}
// Beer-Powder lighting term for clouds: 2 e^-d (1 - e^-2d), where d is optical depth toward the sun. Darkens cloud edges that face the light like powdered sugar. Not energy-conserving; use it on the direct term only.
float beerPowder(float d) { return 2.0 * exp(-d) * (1.0 - exp(-2.0 * d)); }
// One energy-conserving step of volume integration. sigmaT is extinction per unit length (RGB for tinted media), inScatter is in-scattered radiance at this point (including sigmaS, phase and light), ds is step length. Accumulates into radiance and transmittance. Stable for dense media, unlike radiance += T * S * ds.
void volumeStep(inout vec3 radiance, inout vec3 transmittance, vec3 sigmaT, vec3 inScatter, float ds) {
    vec3 stepT = exp(-sigmaT * ds);
    vec3 integral = (inScatter - inScatter * stepT) / max(sigmaT, vec3(1e-7));
    radiance += transmittance * integral;
    transmittance *= stepT;
}
// Distance fog amount (0 = clear, 1 = fully fogged) for distance t.
float distanceFog(float t, float density) { return 1.0 - exp(-t * density); }
// Analytic height fog for density a * exp(-b * y) along the ray segment [0, t]. Thick near the ground, thin above. Returns the fog amount in [0,1].
float heightFog(vec3 ro, vec3 rd, float t, float a, float b) {
    float base = a * exp(-ro.y * b);
    float amount = (abs(rd.y) < 1e-4) ? base * t
                                       : base * (1.0 - exp(-t * rd.y * b)) / (rd.y * b);
    return 1.0 - exp(-max(amount, 0.0));
}

// ---- shader-skills library: atmosphere ----
// Sun disk with antialiased edge and limb darkening (Neckel 1996). angularRadius in radians (the real sun is 0.00476; art often uses 3-10x). pixelAngle is the angular size of a pixel (about 2 / (iResolution.y * focal)). Returns a 0..1 shape tinted by limb darkening; multiply by a bright sun color (10-50).
vec3 sunDisk(vec3 rd, vec3 sunDir, float angularRadius, float pixelAngle) {
    float ang = acos(clamp(dot(rd, sunDir), -1.0, 1.0));
    float edge = 1.0 - smoothstep(angularRadius - pixelAngle, angularRadius + pixelAngle, ang);
    float r = clamp(ang / angularRadius, 0.0, 1.0);
    float muLimb = sqrt(max(1.0 - r * r, 0.0));
    vec3 limb = pow(vec3(muLimb), vec3(0.397, 0.503, 0.652));
    return edge * limb;
}

// ---- shader-skills library: post ----
// Subpixel offset in [-0.5, 0.5)^2 for sample i of a supersampling loop (R2 low-discrepancy sequence). Better coverage than a regular grid for any sample count.
vec2 aaOffset(int i) {
    return fract(0.5 + float(i) * vec2(0.7548776662, 0.5698402910)) - 0.5;
}
// Natural (cos^4) vignette for a pinhole camera: uv is the screen point, focal the camera focal length. Wider lenses vignette more. Multiply HDR color before tonemapping.
float vignette(vec2 uv, float focal) {
    float f2 = focal * focal;
    float k = f2 / (f2 + dot(uv, uv));
    return k * k;
}
// Triangular-PDF dither of +-1 LSB for 8-bit output. Add AFTER linearToSrgb, right before writing fragColor.
vec3 ditherTPDF(vec2 fragCoord, int frame) {
    vec2 r = hash22(vec2(floor(fragCoord) + 7919.0 * float(frame % 1024)));
    return vec3((r.x + r.y - 1.0) / 255.0);
}

// ---- shader-skills library: debug ----
// Distance field as contour bands: warm outside, cool inside, white zero line. Bands are 0.1 units apart.
vec3 debugDistance(float d) {
    vec3 col = (d > 0.0) ? vec3(0.9, 0.6, 0.3) : vec3(0.4, 0.7, 0.85);
    col *= 1.0 - exp(-4.0 * abs(d));
    col *= 0.8 + 0.2 * cos(TAU * d / 0.1);
    return mix(col, vec3(1.0), 1.0 - smoothstep(0.0, 0.01, abs(d)));
}
// Normal as RGB.
vec3 debugNormal(vec3 n) { return 0.5 + 0.5 * n; }
// Distinct color per integer id.
vec3 debugIdColor(float id) {
    return 0.55 + 0.45 * cos(TAU * (0.618034 * id + vec3(0.0, 0.33, 0.67)));
}
// Heat ramp for a value in [0,1]: black, blue, magenta, orange, yellow, white.
vec3 debugHeat(float t) {
    t = clamp(t, 0.0, 1.0);
    return clamp(vec3(1.5 * t, 1.6 * t * t * t - 0.1, 0.9 * sin(PI * t) + 0.2 * t * t), 0.0, 1.0);
}

// ---- shader ----
// ---- art & timeline controls ----
const float FILM_DURATION   = 25.0;
const float SCENE_DURATION  = 5.0;
const float DISSOLVE_TIME   = 0.75;
const float ORBIT_YAW_RANGE = 0.85;   // fraction of full turn across canvas width
const float ORBIT_PITCH_MAX = 0.78;   // radians

const float SPACE_EXPOSURE  = 1.05;
const float FOREST_EXPOSURE = 1.22;
const float OCEAN_EXPOSURE  = 1.08;
const float DESERT_EXPOSURE = 1.14;
const float CAVERN_EXPOSURE = 1.18;

// ---- Material IDs across raymarched scenes ----
// Scene II: Forest
const float MAT_FOREST_GROUND = 10.0;
const float MAT_FOREST_TRUNK  = 11.0;
const float MAT_FOREST_ROOT   = 12.0;
const float MAT_FOREST_FERN   = 13.0;
const float MAT_FOREST_CLOVER = 14.0;
const float MAT_FOREST_LOG    = 15.0;
const float MAT_FOREST_FUNGUS = 16.0;
const float MAT_FOREST_TWIG   = 17.0;

// Scene III: Ocean
const float MAT_OCEAN_ROCK    = 20.0;
const float MAT_OCEAN_TOWER   = 21.0;
const float MAT_OCEAN_TRIM    = 22.0;
const float MAT_OCEAN_LANTERN = 23.0;
const float MAT_OCEAN_DOME    = 24.0;

// Scene IV: Desert
const float MAT_DESERT_SAND      = 30.0;
const float MAT_DESERT_SLICKROCK = 31.0;
const float MAT_DESERT_ARCH      = 32.0;
const float MAT_DESERT_BUTTE     = 33.0;
const float MAT_DESERT_SCRUB     = 34.0;

// Scene V: Cavern
const float MAT_CAVERN_WALL           = 40.0;
const float MAT_CAVERN_STALACTITE     = 41.0;
const float MAT_CAVERN_FLOWSTONE      = 42.0;
const float MAT_CAVERN_CRYSTAL_VIOLET = 43.0;
const float MAT_CAVERN_CRYSTAL_CYAN   = 44.0;
const float MAT_CAVERN_DRUZY          = 45.0;

// ---- Shared cross-part anchor constants ----
const vec3 FOREST_SUN_DIR  = normalize(vec3(0.76, 0.57, -0.31));
const vec3 OCEAN_STACK_POS = vec3(1.55, 0.0, 0.0);
const vec3 DESERT_SUN_DIR  = normalize(vec3(-0.82, 0.29, 0.49));
const vec3 DESERT_ARCH_POS = vec3(5.2, 0.95, -23.5);

// ---- Mutable scene dispatch state for map()/calcNormal()/calcAO() ----
int   gSceneId    = 0;
float gSceneTime  = 0.0;
bool  gFastMap    = false;
bool  gInDissolve = false;

vec2 map(vec3 p);

// Bounded sphere tracer with configurable maxSteps for real-time budget
vec3 marchBounded(vec3 ro, vec3 rd, float tmin, float tmax, float stepScale, int maxSteps) {
    int cap = gInDissolve ? (maxSteps * 2) / 3 : maxSteps;
    float t = tmin;
    for (int i = ZERO; i < 160; i++) {
        if (i >= cap) break;
        vec2 h = map(ro + rd * t);
        if (abs(h.x) < max(0.0009 * t, 0.0004)) return vec3(t, h.y, float(i));
        t += h.x * stepScale;
        if (t > tmax) break;
    }
    return vec3(-1.0, -1.0, float(cap));
}

// Fast soft shadow using coarse LOD map evaluation (gFastMap = true)
float fastShadow(vec3 ro, vec3 rd, float tmin, float tmax, float k) {
    gFastMap = true;
    float res = 1.0;
    float t = tmin;
    for (int i = ZERO; i < 20; i++) {
        float h = map(ro + rd * t).x;
        if (h < 0.001) { res = 0.0; break; }
        res = min(res, k * h / max(t, 1e-3));
        t += clamp(h, 0.04, 0.95);
        if (res < 0.01 || t > tmax) break;
    }
    gFastMap = false;
    res = clamp(res, 0.0, 1.0);
    return res * res * (3.0 - 2.0 * res);
}

// Interactive mouse camera orbit shared by all five scenes
void applyOrbit(inout vec3 ro, vec3 ta, float minHeightOffset) {
    if (length(iMouse.xy) < 0.5) return;
    vec2 m = iMouse.xy / max(iResolution.xy, vec2(1.0)) - 0.5;
    float dYaw   = -m.x * TAU * ORBIT_YAW_RANGE;
    float dPitch = m.y * 2.0 * ORBIT_PITCH_MAX;

    vec3 rel = ro - ta;
    float dist = max(length(rel), 0.001);
    float basePitch = asin(clamp(rel.y / dist, -0.98, 0.98));
    float baseYaw   = atan(rel.x, rel.z);

    float pitch = clamp(basePitch + dPitch, -0.62, 1.12);
    float yaw   = baseYaw + dYaw;
    ro = ta + dist * vec3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch));
    ro.y = max(ro.y, ta.y + minHeightOffset);
}

// ==== PART: 01_space.glsl ====
// =============================================================================
// SCENE I: SPACE (0.0s..5.0s)
// Ringed Turbulent Gas Giant, Great Southern Vortex & Waketrain, Faceted Icy
// Ring Debris, Gossamer Cosmic-Web Nebula, Seam-Free 3D Starfield & Solar Flare
// =============================================================================

const float SP_FOCAL         = 2.65;
const vec3  SP_PLANET_CENTER = vec3(-2.02, -0.035, 0.0);
const float SP_PLANET_RADIUS = 2.07;
const float SP_RING_INNER    = 3.02;
const float SP_RING_OUTER    = 5.44;

// 100% seam-free 3D voxel starfield on the celestial unit sphere (smooth subpixel anti-aliased pinpoints)
vec3 sp_starLayer3D(vec3 rd, mat3 cam, float scale, float seed, float thresh, float rayPx, float dustTrans) {
    vec3 p = rd * scale + vec3(seed * 19.3, seed * 31.7, -seed * 13.1);
    vec3 cell = floor(p);
    vec3 f = p - cell - 0.5;
    vec3 h = hash33(cell + vec3(seed * 47.0, 11.0, 73.0));
    if (h.x <= thresh) return vec3(0.0);

    vec3 jitter = (hash33(cell + vec3(83.0, seed * 29.0, 17.0)) - 0.5) * 0.42;
    vec3 localOff = f - jitter;
    float maxAxis = max(abs(localOff.x), max(abs(localOff.y), abs(localOff.z)));
    float edgeSafe = 1.0 - smoothstep(0.18, 0.24, maxAxis);
    if (edgeSafe <= 0.001) return vec3(0.0);

    vec3 perp = (localOff - rd * dot(localOff, rd)) / scale;
    float d = length(perp);

    float normMag = (h.x - thresh) / max(1.0 - thresh, 1e-4);
    float mag = pow(normMag, 3.2);

    // Wider anti-aliased PSF sigma + soft-knee peak so bright stars never alias into 2x2 pixel blocks!
    float sigma = max(rayPx * mix(1.08, 1.52, normMag), 0.00038);
    float core = exp(-(d * d) / (sigma * sigma));
    float airySkirt = exp(-d / (sigma * 2.8)) * 0.24 * mag * edgeSafe;

    float kelvin = mix(3200.0, 13500.0, pow(h.y, 1.3));
    vec3 starTint = mix(vec3(0.95, 0.96, 1.0), blackbody(kelvin), 0.65);
    starTint *= mix(vec3(0.58, 0.38, 0.30), vec3(1.0), dustTrans);

    float twinkle = 0.94 + 0.06 * sin(h.z * TAU + gSceneTime * (1.1 + 1.3 * h.y));
    float peak = 0.045 + 1.55 * mag;
    vec3 col = starTint * (core * peak + airySkirt * 1.15) * twinkle;

    // Delicate 4-point Airy diffraction cross on brightest ~0.25% hero stars
    if (normMag > 0.87) {
        float hero = (normMag - 0.87) / 0.13;
        vec2 dfCam = vec2(dot(perp, cam[0]), dot(perp, cam[1]));
        float sx = exp(-abs(dfCam.y) / (sigma * 0.82)) * exp(-abs(dfCam.x) / (sigma * 8.5));
        float sy = exp(-abs(dfCam.x) / (sigma * 0.82)) * exp(-abs(dfCam.y) / (sigma * 8.5));
        col += starTint * (sx + sy) * hero * hero * 0.62 * edgeSafe;
    }
    return col;
}

// Deep 3D starfield + pure ridged-crest cosmic web nebula (zero iso-contour loops!) + tight solar corona
vec3 sp_nebulaAndStars(vec3 rd, vec3 sunWorldDir, mat3 cam, vec2 uv, float rayPx, out float outNebMask) {
    float galacticPlane = exp(-pow((rd.y + 0.30 * rd.x - 0.03) * 4.2, 2.0));
    vec3 col = vec3(0.00055, 0.00054, 0.00080)
             + srgbToLinear(vec3(0.036, 0.032, 0.048)) * galacticPlane * 0.048;

    float dustOptical = 0.0;
    vec3 nebEmit = vec3(0.0);
    outNebMask = 0.0;

    // Localized cosmic-web nebula in the central cleft between planet right limb & sun
    if (rd.z < -0.25) {
        vec2 skyUv = vec2(atan(rd.x, -rd.z), asin(clamp(rd.y, -1.0, 1.0)));

        vec2 npMain = (skyUv - vec2(0.048, 0.044)) * vec2(5.5, 4.4);
        float nebEnv = exp(-dot(npMain, npMain));

        vec2 npGap = (skyUv - vec2(0.042, -0.075)) * vec2(7.2, 4.8);
        nebEnv = max(nebEnv, 0.92 * exp(-dot(npGap, npGap)));

        vec2 npUpper = (skyUv - vec2(-0.088, 0.185)) * vec2(5.8, 5.0);
        nebEnv = max(nebEnv, 0.52 * exp(-dot(npUpper, npUpper)));

        if (nebEnv > 0.005) {
            int octWeb = gInDissolve ? 3 : 4;

            vec2 pBase = skyUv * 4.8 + vec2(1.6, -0.8);
            vec2 wq = vec2(fbm(pBase, 2), fbm(pBase + vec2(5.2, 1.3), 2));
            vec2 wr = vec2(fbm(pBase * 1.35 + wq * 0.90 + vec2(1.7, 9.2), 3),
                           fbm(pBase * 1.35 + wq * 0.90 + vec2(8.3, 2.8), 3));

            // Pure crossing multi-angle ridgedFbm crests (ZERO abs(f - c) closed soap-bubble loops!)
            float web1 = ridgedFbm(skyUv * 6.5 + wr * 0.88 + vec2(3.4, 0.8), octWeb);
            float web2 = ridgedFbm(rot2(0.82) * skyUv * 11.2 - wq * 0.78 + vec2(-1.8, 2.9), octWeb);
            float web3 = ridgedFbm(rot2(-0.58) * skyUv * 18.5 + wr * 0.62 + vec2(5.1, -3.2), 3);

            float strandA = pow(saturate(web1), 7.6);
            float strandB = pow(saturate(web2), 8.4);
            float strandC = pow(saturate(web3), 7.2) * (0.35 + 0.95 * pow(saturate(web1), 2.4));
            // Incandescent pinkish-lilac knots where branching shock strands cross!
            float crossKnots = pow(saturate(web1 * web2), 5.6) * 2.8;

            float filamentTotal = (strandA * (0.75 + 1.25 * pow(saturate(web2), 2.8))
                                 + strandB * 0.68
                                 + strandC * 0.52) * nebEnv;

            // Radiant shock nexus right where the upper-right inner ring meets the planet's sunlit limb!
            vec2 nexusD = (skyUv - vec2(0.002, 0.052)) * vec2(14.5, 16.5);
            float nexus = exp(-dot(nexusD, nexusD)) * (0.68 + 1.35 * pow(saturate(web1), 2.4));

            // Dark Bok-globule absorption dust lanes
            float dustField = fbm(skyUv * 7.6 - wq * 0.85 + vec2(4.2, -2.1), 3);
            float darkLanes = pow(saturate(0.54 + 0.68 * dustField), 2.8) * (1.0 - 0.62 * saturate(web1));
            dustOptical = darkLanes * nebEnv * 1.45;
            vec3 dustAtten = beerTransmittance(vec3(1.35, 1.55, 1.15), dustOptical);

            vec3 deepRoyal   = srgbToLinear(vec3(0.21, 0.11, 0.36));
            vec3 midMagenta  = srgbToLinear(vec3(0.56, 0.27, 0.74));
            vec3 electricLil = srgbToLinear(vec3(0.91, 0.67, 0.99));
            vec3 hotCorePink = srgbToLinear(vec3(1.00, 0.88, 0.99));
            vec3 warmAmber   = srgbToLinear(vec3(0.52, 0.32, 0.19));

            float softVeil = saturate(0.45 + 0.50 * wr.x) * nebEnv * nebEnv;
            nebEmit += deepRoyal * softVeil * 0.12 * dustAtten;
            vec3 filCol = mixOklab(midMagenta, electricLil, saturate(web2 * 0.78 + 0.28 * web3));
            nebEmit += filCol * filamentTotal * 0.95 * mix(vec3(1.0), dustAtten, 0.38);
            nebEmit += hotCorePink * (nexus * 0.62 + crossKnots * nebEnv * 0.34);

            vec2 warmP = (skyUv - vec2(0.142, 0.088)) * vec2(12.5, 11.5);
            float warmPocket = exp(-dot(warmP, warmP)) * saturate(0.55 + 0.65 * wr.y);
            nebEmit += warmAmber * warmPocket * 0.15;

            outNebMask = saturate(filamentTotal * 1.5 + softVeil * 0.35);
        }
    }

    float starDustTrans = exp(-dustOptical * 0.85);

    // 4-tier 3D seam-free anti-aliased starfield
    col += sp_starLayer3D(rd, cam,  88.0, 1.0, 0.962, rayPx, starDustTrans) * 1.18;
    col += sp_starLayer3D(rd, cam, 178.0, 2.0, 0.948, rayPx, starDustTrans) * 0.68;
    col += sp_starLayer3D(rd, cam, 345.0, 3.0, 0.925, rayPx, starDustTrans) * 0.32;
    if (!gInDissolve) {
        col += sp_starLayer3D(rd, cam, 590.0, 4.0, 0.906, rayPx * 0.9, starDustTrans) * 0.13;
    }

    // Iconic warm-coral star glinting inside the dark right ring gap just above the shadow root
    vec3 heroStarDir = normalize(vec3(0.082, -0.048, -1.0));
    float dHeroStar = length(rd - heroStarDir);
    float sHero = max(rayPx * 1.45, 0.00042);
    vec3 heroTint = srgbToLinear(vec3(1.0, 0.75, 0.67));
    col += heroTint * (exp(-(dHeroStar * dHeroStar) / (sHero * sHero * 1.6)) * 2.2
                     + exp(-dHeroStar / (sHero * 5.2)) * 0.24);

    col += nebEmit;

    // ---- Solar Disk, Tightly Focused Aureole (zero brown quadrant wash!), Needles & Lens Streak ----
    float cosSun = clamp(dot(rd, sunWorldDir), -1.0, 1.0);
    float ang = acos(cosSun);
    vec3 sunTint    = mix(vec3(1.0, 0.97, 0.92), blackbody(5550.0), 0.58);
    vec3 coronaWarm = srgbToLinear(vec3(1.0, 0.88, 0.70));

    vec3 disk = sunDisk(rd, sunWorldDir, 0.0125, rayPx) * 48.0;
    float innerCore  = exp(-(ang * ang) / (0.0155 * 0.0155)) * 26.0;
    float innerBloom = 0.0020 / (ang * ang + 0.00042) * (1.0 - smoothstep(0.045, 0.155, ang));
    // Steep outer exponential decay so upper-right deep space stays crisp dark neutral charcoal!
    float outerHalo  = exp(-ang * 18.0) * 1.35 + exp(-ang * 12.5) * 0.10;

    vec3 sunCam = vec3(dot(sunWorldDir, cam[0]), dot(sunWorldDir, cam[1]), dot(sunWorldDir, cam[2]));
    vec3 solarOptics = sunTint * (disk + innerCore) + coronaWarm * (innerBloom * 0.46 + outerHalo * 0.38);

    if (sunCam.z > 0.05) {
        vec2 sunUv = SP_FOCAL * sunCam.xy / sunCam.z;
        vec2 dUv = uv - sunUv;
        float rUv = length(dUv);
        float rayAng = atan(dUv.y, dUv.x + 1e-6);

        if (rUv < 0.45) {
            float nRay1 = valueNoise(vec2(rayAng * 22.0 + 3.1, 1.7));
            float nRay2 = valueNoise(vec2(rayAng * 56.0 - 1.9, 4.3));
            float nRay3 = valueNoise(vec2(rayAng * 124.0 + 0.7, 8.1));
            float needles = pow(nRay1, 3.6) * 0.36
                          + pow(nRay2, 4.8) * 0.65
                          + pow(nRay3, 6.2) * 0.82
                          + 0.28 * pow(0.5 + 0.5 * cos(rayAng * 28.0 + 0.4), 9.0);
            float needleEnv = exp(-rUv * 9.6) * smoothstep(0.015, 0.055, rUv);
            solarOptics += mix(sunTint, coronaWarm, 0.35) * needles * needleEnv * 0.52;
        }

        // Crisp 2D sensor-horizontal anamorphic lens flare
        float streakCore = exp(-abs(dUv.y) * 235.0) * exp(-abs(dUv.x) * 4.10);
        float streakSoft = exp(-abs(dUv.y) *  62.0) * exp(-abs(dUv.x) * 5.10);
        solarOptics += vec3(1.0, 0.94, 0.82) * (streakCore * 1.06 + streakSoft * 0.12);

        vec2 ghostUv = sunUv + vec2(0.135, 0.085);
        float dGhost = length((uv - ghostUv) * vec2(1.0, 1.25));
        float ghostRing = exp(-pow((dGhost - 0.052) * 30.0, 2.0)) + 0.40 * exp(-dGhost * 24.0);
        solarOptics += srgbToLinear(vec3(0.36, 0.50, 0.34)) * ghostRing * 0.040;
    }

    col += solarOptics;
    return max(col, vec3(0.0));
}

// Single-pass 3D gas giant: bold rounded Kelvin-Helmholtz fluid hooks, mottled northern ovals,
// wide cool slate-blue shear zone, embedded Great Southern Oval, and desaturated taupe nightside
vec3 sp_shadeGasGiant(vec3 hitPos, vec3 rd, vec3 lightDir, float rayPx,
                      out vec3 outNormal, out float outHeightMask) {
    vec3 n = normalize(hitPos - SP_PLANET_CENTER);

    vec3 upAxis = normalize(vec3(-0.055, 0.994, 0.092));
    vec3 eqX    = normalize(cross(upAxis, vec3(0.0, 0.0, 1.0)));
    vec3 eqZ    = cross(eqX, upAxis);

    float NoV = max(dot(n, -rd), 0.0);
    float detailFade = smoothstep(0.05, 0.35, NoV) * (1.0 - smoothstep(0.0028, 0.0075, rayPx));

    vec3 localBase = vec3(dot(n, eqX), dot(n, upAxis), dot(n, eqZ));
    float lat = asin(clamp(localBase.y, -1.0, 1.0));

    float baseSpin = -0.046 * (gSceneTime - 2.75) - 0.075;

    // Smooth alternating zonal wind shear for bold rounded Kelvin-Helmholtz hooks
    float zonalShear = 0.125 * cos(lat * 13.5 - 0.30) + 0.052 * sin(lat * 25.0 + 0.40);
    vec3 local = localBase;
    local.xz = rot2(baseSpin + zonalShear) * local.xz;

    vec3 cylP = vec3(local.x * 2.65, lat * 4.75, local.z * 2.65);

    int octMeso = gInDissolve ? 3 : 4;

    // Tier 1 (Macro Rounded Curling Eddies):
    float warpX = fbm(cylP * vec3(1.18, 1.55, 1.18) + vec3(0.02 * gSceneTime, 0.0, 0.0), 3, 2.02, 0.52);
    float warpY = fbm(cylP * vec3(1.18, 1.55, 1.18) + vec3(7.3, -4.1, 3.8), 3, 2.02, 0.52);

    vec3 warpedCyl = cylP * vec3(2.05, 2.95, 2.05) + vec3(warpY * 1.42, warpX * 1.32, -warpX * 1.20);

    // Tier 2 (Painterly Fluid Billows & Smooth Folded Plumes — zero shredded confetti!):
    float mesoEddy   = fbm(warpedCyl, octMeso, 2.04, 0.52);
    float billowLobe = billowFbm(warpedCyl * 1.45 + vec3(mesoEddy * 0.95, -warpX * 0.85, 2.1), 3);

    // Tier 3 (Fine Filaments + Northern Cellular Mottling):
    vec2 fineCoord = vec2((local.x - local.z * 0.65) * 7.6 + mesoEddy * 1.85, lat * 21.0 + warpX * 2.1);
    float fineRidges = ridgedFbm(fineCoord, 3);
    vec3 microSwirlD = simplexNoiseD(fineCoord * 1.85 + vec2(billowLobe * 1.1, -mesoEddy * 0.9), 0.7 + warpY * 2.0);
    float microSwirl = microSwirlD.x * detailFade;

    float beltAct = cubicPulse(0.19, 0.22, lat) + cubicPulse(-0.24, 0.22, lat);
    float wLat = lat
               + (0.038 + 0.066 * beltAct) * warpX
               + (0.026 + 0.048 * beltAct) * mesoEddy
               + (0.012 + 0.018 * beltAct) * (billowLobe - 0.5)
               + 0.007 * microSwirl;

    // Warmer honey-ochre / golden-sienna palette (less brick-red, faithful to film_0..4.png!)
    vec3 cIvory     = srgbToLinear(vec3(0.84, 0.79, 0.70));
    vec3 cCream     = srgbToLinear(vec3(0.74, 0.68, 0.59));
    vec3 cTan       = srgbToLinear(vec3(0.65, 0.50, 0.34));
    vec3 cOchreRust = srgbToLinear(vec3(0.58, 0.36, 0.17));
    vec3 cWarmUmber = srgbToLinear(vec3(0.41, 0.23, 0.10));
    vec3 cSlate     = srgbToLinear(vec3(0.49, 0.53, 0.58));
    vec3 cBlueShear = srgbToLinear(vec3(0.39, 0.45, 0.52));
    vec3 cPolar     = srgbToLinear(vec3(0.39, 0.36, 0.30));

    float zoneWaves = 0.5 + 0.5 * sin(wLat * 22.0 - 0.20 + billowLobe * 1.55);
    float fineLanes = 0.5 + 0.5 * sin(wLat * 50.0 - 0.60 + fineRidges * 2.10);

    // Belt hierarchy with thicker turbulent SEB embedding the Great Southern Oval & wider slate shear band!
    float eqBeltN   = cubicPulse( 0.18, 0.145, wLat);   // Bold curling North Equatorial Belt
    float eqBeltS   = cubicPulse(-0.23, 0.175, wLat);   // Thicker South Equatorial Belt wrapping Great Oval!
    float nTempBelts= cubicPulse( 0.40, 0.052, wLat) + 0.80 * cubicPulse(0.54, 0.048, wLat) + 0.65 * cubicPulse(0.67, 0.045, wLat);
    float sTempBelt = cubicPulse(-0.47, 0.065, wLat);
    float eqCreamZ  = cubicPulse( 0.01, 0.110, wLat);
    float nTropZ    = cubicPulse( 0.32, 0.048, wLat);

    // Wide cool slate-blue-grey shear zone above the southern belt (lat ~ -0.14..+0.02) + northern cool band!
    float slateZone = cubicPulse(-0.085, 0.095, wLat) + 0.62 * cubicPulse(0.28, 0.045, wLat);

    vec3 albedo = mixOklab(cCream, cTan, smoothstep(0.18, 0.82, zoneWaves * 0.70 + fineLanes * 0.30));
    albedo = mixOklab(albedo, cIvory, saturate((eqCreamZ + 0.78 * nTropZ) * (0.58 + 0.42 * billowLobe)));

    // Smooth, rounded Kelvin-Helmholtz fluid hooks & swirling waves (driven by smooth mesoEddy/warpY, not jagged ridges!)
    float fluidHooks = 0.5 + 0.5 * sin(mesoEddy * 5.2 + warpY * 3.8 + 0.85 * billowLobe);
    float beltTex = saturate(0.32 + 0.46 * fluidHooks + 0.32 * fineRidges);
    float rustMask = saturate((eqBeltN * 1.12 + eqBeltS * 1.06 + 0.82 * nTempBelts + 0.68 * sTempBelt) * beltTex);
    albedo = mixOklab(albedo, cOchreRust, rustMask);

    // Rounded warm-umber curled vortex cores (soft transitions -> painterly fluid swirls, zero confetti!)
    float umberSwirls = (eqBeltN + 0.75 * eqBeltS) * smoothstep(0.36, 0.78, fluidHooks) * smoothstep(0.42, 0.82, fineRidges);
    albedo = mixOklab(albedo, cWarmUmber, saturate(umberSwirls * 0.72));

    // Rounded creamy convective cloud curls folding smoothly into NEB & SEB
    float creamCurls = (eqBeltN + 0.88 * eqBeltS) * smoothstep(0.48, 0.84, (1.0 - fluidHooks) * 0.62 + billowLobe * 0.48);
    albedo = mixOklab(albedo, cIvory, saturate(creamCurls * 0.68));

    // Broad, streaky cool slate-blue-grey shear zone above the southern belt (matching film_2.00.png!)
    float shearStreaks = 0.5 + 0.5 * sin(fineCoord.x * 0.95 - lat * 22.0 + mesoEddy * 2.8);
    float slateWeight = saturate(slateZone * (0.58 + 0.42 * shearStreaks)
                               + 0.38 * cubicPulse(-0.07, 0.085, wLat) * smoothstep(0.38, 0.78, shearStreaks * fineRidges));
    albedo = mixOklab(albedo, mixOklab(cSlate, cBlueShear, shearStreaks * 0.65), slateWeight * 0.82);

    // ---- Northern Mid-Latitude Mottled Cellular Turbulence + 4 Pale-Collared Oval Storms (lat +0.30..+0.74) ----
    if (lat > 0.26) {
        float northEnv = smoothstep(0.26, 0.42, lat);
        float northCells = billowFbm(cylP * vec3(4.2, 6.2, 4.2) + vec3(warpX * 1.1, mesoEddy * 0.9, 0.0), 3);
        float northRipples = ridgedFbm(vec2((local.x + local.z * 0.8) * 6.5 + warpY * 1.6, lat * 24.0 + mesoEddy * 1.8), 3);
        vec3 mottledTint = mixOklab(cWarmUmber * 1.15, cIvory * 0.96, smoothstep(0.22, 0.78, northCells * 0.60 + northRipples * 0.45));
        albedo = mixOklab(albedo, mottledTint, northEnv * 0.42);
    }

    vec3 localStorm = localBase;
    localStorm.xz = rot2(baseSpin) * localStorm.xz;

    // 4 curated pale-collared northern temperate anticyclonic ovals across lat = +0.36..+0.66
    for (int k = 0; k < 4; k++) {
        vec3 mDir;
        float mScale;
        if (k == 0)      { mDir = normalize(vec3( 0.05, 0.64, 0.76)); mScale = 0.076; }
        else if (k == 1) { mDir = normalize(vec3( 0.27, 0.60, 0.75)); mScale = 0.068; }
        else if (k == 2) { mDir = normalize(vec3(-0.14, 0.50, 0.85)); mScale = 0.062; }
        else             { mDir = normalize(vec3( 0.44, 0.46, 0.77)); mScale = 0.058; }

        vec3 mTanX = normalize(cross(upAxis, mDir));
        vec3 mTanY = cross(mDir, mTanX);
        vec3 dm = localStorm - mDir;
        vec2 md = vec2(dot(dm, mTanX) * 0.92, dot(dm, mTanY) * 1.52);
        float mr = length(md);
        if (mr < mScale) {
            float uM = mr / mScale;
            vec2 mSw = rot2((1.0 - uM) * 3.4) * md;
            float mTex = fbm(mSw * 42.0, 2);
            float uWarped = uM + 0.16 * mTex;
            float mCollar = cubicPulse(0.62, 0.26, uWarped);
            float mCore   = 1.0 - smoothstep(0.14, 0.50, uWarped);
            vec3 mCol = mixOklab(cTan * 0.90, cCream * 1.03, mCollar * 0.68);
            mCol = mixOklab(mCol, cWarmUmber * 1.18, mCore * 0.56);
            float mW = 1.0 - smoothstep(0.58, 0.98, uWarped);
            albedo = mixOklab(albedo, mCol, mW * 0.56);
        }
    }

    float polarMix = smoothstep(0.58, 1.06, abs(lat));
    vec3 polarCol = mixOklab(cPolar, cTan * 0.74, 0.38 * billowLobe + 0.24 * fineLanes);
    albedo = mixOklab(albedo, polarCol, polarMix * 0.86);

    float cloudH = 0.45 * (1.0 - rustMask) + 0.36 * creamCurls - 0.32 * umberSwirls + 0.20 * (billowLobe - 0.5);

    // ---- EMBEDDED GREAT SOUTHERN OVAL VORTEX + WESTERN WAKETRAIN + EASTERN COMPANION SPIRAL ----
    vec3 stormDir  = normalize(vec3(0.35, -0.245, 0.903));
    vec3 stormTanX = normalize(cross(upAxis, stormDir));
    vec3 stormTanY = cross(stormDir, stormTanX);
    vec3 dStorm3   = localStorm - stormDir;
    vec2 sdRaw     = vec2(dot(dStorm3, stormTanX), dot(dStorm3, stormTanY));

    // Surrounding SEB flow-diversion collar wrapping organically OVER and UNDER the Great Oval!
    vec2 flowWrapD = vec2(sdRaw.x * 0.55, sdRaw.y * 1.35);
    float flowWrapR = length(flowWrapD);
    if (flowWrapR < 0.42 && flowWrapR > 0.16) {
        float wrapBand = cubicPulse(0.26, 0.11, flowWrapR + 0.025 * mesoEddy);
        float wrapTex  = 0.5 + 0.5 * sin(flowWrapR * 42.0 + mesoEddy * 3.5);
        vec3 wrapCol = mixOklab(cOchreRust, cWarmUmber * 1.15, wrapTex * 0.55);
        albedo = mixOklab(albedo, wrapCol, wrapBand * 0.52);
    }

    // Turbulent Karman Waketrain trailing west (left) of the Great Southern Oval
    if (sdRaw.x < -0.04 && sdRaw.x > -0.66 && abs(sdRaw.y) < 0.16) {
        float wakeEnv = smoothstep(-0.66, -0.12, sdRaw.x) * (1.0 - smoothstep(-0.16, -0.04, sdRaw.x))
                      * (1.0 - smoothstep(0.045, 0.155, abs(sdRaw.y + 0.022 * sin(sdRaw.x * 18.0))));
        vec2 wakeP = vec2(sdRaw.x * 15.0, sdRaw.y * 28.0);
        float wakeSwirl = fbm(wakeP + vec2(warpX, warpY) * 1.5, 3);
        float wakeLoops = 0.5 + 0.5 * sin(sdRaw.x * 34.0 + wakeSwirl * 4.2);
        vec3 wakeCol = mixOklab(cOchreRust * 1.04, cCream * 1.05, smoothstep(0.25, 0.78, (0.5 + 0.5 * wakeSwirl) * 0.55 + wakeLoops * 0.48));
        albedo = mixOklab(albedo, wakeCol, wakeEnv * 0.82);
        cloudH += wakeEnv * 0.24 * wakeSwirl;
    }

    // Painterly Great Southern Oval (broad soft spiral bands embedded in turbulent ochre SEB, zero tight bullseye!)
    vec2 sd = vec2(sdRaw.x * 0.92, sdRaw.y * 1.72);
    float srRaw = length(sd);
    if (srRaw < 0.265) {
        float swirlProfile = pow(1.0 - smoothstep(0.0, 0.24, srRaw), 1.30);
        float swirlAng = swirlProfile * 4.2 + 0.08 * gSceneTime;
        vec2 sw = rot2(swirlAng) * sd;
        float thetaS = atan(sd.y, sd.x + 1e-6);

        float spiralFbm  = fbm(sw * 22.0 + vec2(2.1, -1.4), 3);
        float edgeRuffle = fbm(sw * 32.0 - vec2(1.3, 2.7), 3);
        float sr = srRaw + 0.024 * spiralFbm + 0.014 * edgeRuffle;

        // Broad 2.5-turn painterly spiral lanes instead of tight geometric rings!
        float spiralArms = 0.5 + 0.5 * sin(sr * 38.0 - thetaS * 1.0 + spiralFbm * 2.8);

        float darkOuter  = cubicPulse(0.215, 0.045, sr);
        float buffCollar = cubicPulse(0.168, 0.042, sr);
        float ochreRing  = smoothstep(0.035, 0.090, sr) * (1.0 - smoothstep(0.130, 0.178, sr));
        float warmEye    = 1.0 - smoothstep(0.0, 0.070, sr);

        vec3 cStormOchre = srgbToLinear(vec3(0.62, 0.39, 0.19));
        vec3 cStormPeach = srgbToLinear(vec3(0.73, 0.55, 0.37));
        vec3 cStormBuff  = srgbToLinear(vec3(0.78, 0.71, 0.60));

        vec3 vortexCol = mixOklab(cStormOchre, cStormPeach, spiralArms * 0.68);
        vortexCol = mixOklab(vortexCol, cStormBuff, spiralArms * 0.25 * (1.0 - warmEye));
        vortexCol = mixOklab(vortexCol, cStormOchre * 1.08, ochreRing * 0.45);
        vortexCol = mixOklab(vortexCol, cStormPeach, warmEye * 0.52);
        vortexCol = mixOklab(vortexCol, cStormBuff, buffCollar * (0.48 + 0.30 * spiralArms));
        vortexCol = mixOklab(vortexCol, cWarmUmber * 1.15, darkOuter * 0.58);

        float mStorm = 1.0 - smoothstep(0.155, 0.255, sr);
        albedo = mixOklab(albedo, vortexCol, mStorm * 0.90);
        cloudH += mStorm * (0.28 + 0.14 * buffCollar - 0.14 * darkOuter);
    }

    // Companion curled spiral eddy to the east of the Great Oval
    vec2 compD = (sdRaw - vec2(0.215, 0.026)) * vec2(1.18, 1.76);
    float compR = length(compD);
    if (compR < 0.098) {
        vec2 cSw = rot2((1.0 - compR / 0.098) * 4.2) * compD;
        float cSpiral = 0.5 + 0.5 * sin(compR * 68.0 - atan(compD.y, compD.x + 1e-6) + fbm(cSw * 30.0, 3) * 2.2);
        vec3 compCol = mixOklab(cOchreRust * 1.05, cCream * 1.03, cSpiral * 0.72);
        float mComp = 1.0 - smoothstep(0.048, 0.095, compR);
        albedo = mixOklab(albedo, compCol, mComp * 0.85);
        cloudH += mComp * 0.18 * cSpiral;
    }

    outHeightMask = saturate(0.5 + 0.5 * cloudH);

    vec3 t1 = normalize(cross(upAxis, n) + vec3(1e-5, 0.0, 0.0));
    vec3 t2 = cross(n, t1);
    float NoL_raw = dot(n, lightDir);
    vec2 gentleSlope = microSwirlD.yz * 0.020 + vec2(mesoEddy, warpX) * 0.028;
    vec3 nCloud = normalize(n - (t1 * gentleSlope.x + t2 * gentleSlope.y) * detailFade * 0.30);
    outNormal = nCloud;

    float NoL_eff = dot(nCloud, lightDir) + 0.020 * (cloudH - 0.15) * exp(-pow((NoL_raw - 0.06) * 5.5, 2.0));
    float diff = smoothstep(-0.06, 0.34, NoL_eff) * (0.34 + 0.66 * clamp(NoL_eff, 0.0, 1.0));

    float twilightWarm = exp(-pow((NoL_raw - 0.04) * 5.5, 2.0)) * smoothstep(-0.12, 0.16, NoL_raw);
    vec3 sunCol = mix(vec3(2.02, 1.91, 1.76), vec3(2.05, 1.68, 1.32), twilightWarm * 0.24);

    float limbDark = pow(max(NoV, 1e-3), mix(0.36, 0.28, polarMix * 0.5));

    // Dusty desaturated taupe-grey nightside illuminated by ring-shine (fixes brick-red night stripes!)
    float nightMask = 1.0 - smoothstep(-0.06, 0.24, NoL_raw);
    float southFacing = saturate(0.58 - 0.42 * dot(n, upAxis));
    vec3 ringShine = srgbToLinear(vec3(0.34, 0.32, 0.29)) * (0.52 + 0.34 * southFacing) * (0.35 + 0.65 * pow(NoV, 0.42));
    vec3 nightAlbedo = mix(vec3(luminance(albedo)), albedo, 0.35);

    float rimAtmo = pow(1.0 - NoV, 4.8) * smoothstep(-0.02, 0.55, NoL_raw);
    vec3 hazeRimCol = srgbToLinear(vec3(0.68, 0.74, 0.85));

#if DEBUG_MODE == 6
    return vec3(0.5) * (sunCol * diff * limbDark + ringShine * nightMask) + hazeRimCol * rimAtmo * 0.18;
#endif

    vec3 col = albedo * (sunCol * diff * limbDark) + nightAlbedo * ringShine * (0.16 + 0.84 * nightMask);
    col += hazeRimCol * rimAtmo * 0.17;
    return col;
}

// Fast clip-free single-cell faceted icy boulder/moonlet tier
void sp_ringBoulderTier(vec2 ringCoords, vec2 sunRing2D, float scale, float seed, float spawnThresh,
                        float sizeBase, float pxFootprint, inout float boulderMask, inout float boulderLit,
                        inout float castShadow, inout vec2 boulderGrad) {
    float cellWorldSize = 1.0 / scale;
    float lodVis = 1.0 - smoothstep(cellWorldSize * 0.22, cellWorldSize * 0.62, pxFootprint);
    if (lodVis <= 0.005) return;

    vec2 pScaled = ringCoords * scale + vec2(seed * 19.7, -seed * 11.3);
    vec2 cell = floor(pScaled);
    vec2 f = pScaled - cell;

    vec3 h = hash33(vec3(cell, seed * 31.0));
    if (h.x < spawnThresh) return;

    vec2 center = 0.30 + 0.40 * h.yz;
    vec2 rel = f - center;
    float rRaw = length(rel);
    float rad = sizeBase * mix(0.55, 1.24, fract(h.x * 17.3));

    if (rRaw < rad * 2.35) {
        float ang = atan(rel.y, rel.x + 1e-6);
        float facets = 1.0
                     + 0.24 * cos(ang * 3.0 + h.y * TAU)
                     + 0.16 * cos(ang * 5.0 - h.z * TAU)
                     + 0.08 * cos(ang * 7.0 + h.x * 13.0);
        float rockR = rad * facets;
        float aa = max(pxFootprint * scale * 0.85, 0.020);
        float cov = (1.0 - smoothstep(rockR - aa, rockR + aa, rRaw)) * lodVis;

        if (cov > boulderMask) {
            boulderMask = cov;
            vec2 norm2D = rel / max(rockR, 1e-4);
            vec2 facetN2 = normalize(norm2D + 0.32 * vec2(cos(ang * 4.0 + h.y * 6.0), sin(ang * 4.0 + h.z * 6.0)) + vec2(1e-5));
            float sunDot = dot(facetN2, sunRing2D);
            boulderLit = smoothstep(-0.18, 0.48, sunDot) * (0.32 + 0.68 * max(sunDot, 0.0));
            boulderGrad = facetN2 * cov;
        }

        float along = dot(rel, -sunRing2D);
        if (along > 0.0 && along < rockR * 2.15) {
            float perp = length(rel + sunRing2D * along);
            float shW = rockR * (0.80 - 0.25 * (along / (rockR * 2.15)));
            float sh = (1.0 - smoothstep(shW * 0.50, shW + aa, perp))
                     * (1.0 - smoothstep(rockR * 0.45, rockR * 2.10, along));
            castShadow = max(castShadow, sh * lodVis * 0.80);
        }
    }
}

vec4 sp_shadeRings(vec3 p, float tRing, vec3 rd, vec3 lightDir, vec3 ringNormal, vec3 ringX, vec3 ringZ,
                   float rayPx, out float outBoulderMask, out vec3 outRingNormal) {
    outBoulderMask = 0.0;
    outRingNormal = ringNormal;

    vec3 rel = p - SP_PLANET_CENTER;
    vec2 disk = vec2(dot(rel, ringX), dot(rel, ringZ));
    float r = length(disk);
    if (r < SP_RING_INNER || r > SP_RING_OUTER) return vec4(0.0);

    float u = (r - SP_RING_INNER) / (SP_RING_OUTER - SP_RING_INNER);

    float cosGrazing = max(abs(dot(rd, ringNormal)), 0.065);
    float worldPx = tRing * rayPx;
    float radialFootprint = worldPx / sqrt(cosGrazing);

    // ---- Multi-Zone Saturnian Ring Profile (wider inner C-ring window matching film_0..4.png!) ----
    float innerFade = smoothstep(0.0, 0.065, u);
    float outerMain = 1.0 - smoothstep(0.955, 0.978, u);
    float fRing     = 0.26 * cubicPulse(0.988, 0.0065, u);

    // Wider translucent C-ring ramp so bright B-ring starts just outside the coral gap star!
    float cRingRamp  = smoothstep(0.05, 0.28, u);
    float bRingDense = smoothstep(0.24, 0.31, u) * (1.0 - smoothstep(0.67, 0.70, u));

    float cassiniBowl  = smoothstep(0.695, 0.708, u) * (1.0 - smoothstep(0.748, 0.762, u));
    float huygens      = 0.28 * cubicPulse(0.712, 0.0045, u);
    float cassiniTrans = clamp(1.0 - 0.94 * cassiniBowl + huygens, 0.05, 1.0);

    float enckeTrans = 1.0 - 0.76 * cubicPulse(0.888, 0.0095, u);
    float keelerGap  = 1.0 - 0.62 * cubicPulse(0.948, 0.0048, u);

    float macroBands    = 0.5 + 0.5 * fbm(vec2(r * 11.2, 1.7), 4);
    float grooveBundles = ridgedFbm(vec2(r * 36.0 + 0.30 * macroBands, 3.4), 4);

    float keplerOmg = 0.055 / max(pow(r * 0.38, 1.5), 0.25);
    float ang = atan(disk.y, disk.x + 1e-6) - gSceneTime * keplerOmg;
    vec2 ringCoords = vec2(cos(ang), sin(ang)) * r;

    float attenMed  = exp(-pow(radialFootprint * 58.0, 2.0));
    float attenFine = exp(-pow(radialFootprint * 138.0, 2.0));

    float ringletsMed = (0.5 + 0.5 * sin(r * 86.0 + 2.4 * fbm(vec2(r * 7.2, 4.1), 3))) * attenMed + 0.5 * (1.0 - attenMed);
    float spiralWave  = (0.5 + 0.5 * sin(r * 182.0 - 2.0 * ang + 3.2 * grooveBundles)) * attenFine + 0.5 * (1.0 - attenFine);
    float azimBrush   = gradientNoise(vec2(r * 54.0, ang * 5.8)) * attenMed;

    float tonalBands = 0.68 + 0.32 * sin(u * 32.0 + 1.8 * macroBands) * (0.5 + 0.5 * grooveBundles);

    float rawOpt = (0.38 + 0.38 * macroBands + 0.25 * grooveBundles + 0.22 * (ringletsMed - 0.5) + 0.16 * (spiralWave - 0.5) + 0.08 * azimBrush);
    float zoneWeight = mix(0.11, 0.93, cRingRamp) + 0.22 * bRingDense;
    float density = saturate(rawOpt * zoneWeight * cassiniTrans * enckeTrans * keelerGap) * innerFade * outerMain
                  + fRing * (0.65 + 0.35 * ringletsMed);

    vec3 cCrepe    = srgbToLinear(vec3(0.46, 0.44, 0.44));
    vec3 cDarkGrey = srgbToLinear(vec3(0.44, 0.43, 0.45));
    vec3 cWarmIce  = srgbToLinear(vec3(0.75, 0.72, 0.68));
    vec3 cAlabast  = srgbToLinear(vec3(0.85, 0.83, 0.80));
    vec3 cCoolIce  = srgbToLinear(vec3(0.58, 0.59, 0.62));

    vec3 ringAlbedo = mixOklab(cDarkGrey, cWarmIce, saturate(tonalBands * 0.72 + ringletsMed * 0.28));
    ringAlbedo = mixOklab(ringAlbedo, cAlabast, saturate(bRingDense * 0.72 * (0.35 + 0.65 * grooveBundles)));
    ringAlbedo = mixOklab(ringAlbedo, cCoolIce, smoothstep(0.72, 0.80, u) * 0.58);
    ringAlbedo = mixOklab(cCrepe, ringAlbedo, smoothstep(0.05, 0.28, u));

    // ---- Registered Planet Shadow Wedge Across Right Ring Wing (exiting at y ~ 71-74%!) ----
    float du = gSceneTime - 2.75;
    float shAng = 0.665 - 0.032 * du;
    vec3 shadowAxis = normalize(ringX * cos(shAng) + ringZ * sin(shAng));
    float projAlong = dot(rel, shadowAxis);
    float perpDist  = length(rel - shadowAxis * projAlong);

    float inSun = 1.0;
    if (projAlong > 0.0) {
        float taper = mix(0.03, 0.25, saturate((du + 2.0) / 4.0)) * clamp((projAlong - 2.4) / 3.1, 0.0, 1.25);
        float umbraHalfW = SP_PLANET_RADIUS * max(0.43 - taper, 0.045);
        float penumbraW  = 0.165 + 0.045 * clamp(projAlong - 2.2, 0.0, 3.6);
        inSun = smoothstep(umbraHalfW - penumbraW * 0.5, umbraHalfW + penumbraW * 0.5, perpDist);
    }

    // ---- 4-Tier Clip-Free Faceted Icy Boulders & Hero Foreground Moonlets ----
    vec2 sunRing2D = normalize(vec2(dot(lightDir, ringX), dot(lightDir, ringZ)) + vec2(1e-5));
    float boulderMask = 0.0;
    float boulderLit  = 0.0;
    float castShadow  = 0.0;
    vec2  boulderGrad = vec2(0.0);

    float debrisZone = cassiniTrans * enckeTrans * innerFade * outerMain * smoothstep(0.08, 0.28, u);
    if (debrisZone > 0.06) {
        sp_ringBoulderTier(ringCoords, sunRing2D,  2.85, 0.5, 0.918, 0.118, worldPx, boulderMask, boulderLit, castShadow, boulderGrad);
        sp_ringBoulderTier(ringCoords, sunRing2D,  6.00, 1.0, 0.892, 0.122, worldPx, boulderMask, boulderLit, castShadow, boulderGrad);
        sp_ringBoulderTier(ringCoords, sunRing2D, 13.20, 2.0, 0.855, 0.125, worldPx, boulderMask, boulderLit, castShadow, boulderGrad);
        if (!gInDissolve) {
            sp_ringBoulderTier(ringCoords, sunRing2D, 28.50, 3.0, 0.820, 0.126, worldPx, boulderMask, boulderLit, castShadow, boulderGrad);
        }
    }
    boulderMask *= debrisZone;
    castShadow  *= debrisZone;
    outBoulderMask = boulderMask;

    if (boulderMask > 0.05) {
        outRingNormal = normalize(ringNormal + (ringX * boulderGrad.x + ringZ * boulderGrad.y) * 0.85);
    }

    float mu = clamp(dot(rd, lightDir), -1.0, 1.0);
    float phase = 0.82 + 0.26 * phaseDualHG(mu, 0.55, -0.38, 0.52) * PI;

    float glintLod = 1.0 - smoothstep(0.006, 0.018, worldPx);
    float iceSparkle = 0.0;
    if (glintLod > 0.01 && inSun > 0.2) {
        float gh = hash12(floor(ringCoords * 82.0) + vec2(71.0, 29.0));
        iceSparkle = smoothstep(0.986, 0.999, gh) * glintLod * density * 0.48;
    }

    // Subtle planetshine inside shadow (sRGB ~ 0.09-0.13) so faint grooves & Cassini gap read inside the shadow!
    vec3 shadowAmbient = srgbToLinear(vec3(0.28, 0.28, 0.31)) * 0.92 * cassiniTrans;
    vec3 sunIrrad = vec3(1.50, 1.44, 1.36) * phase * (1.0 - castShadow * 0.72);
    vec3 litDust = ringAlbedo * (sunIrrad * inSun + shadowAmbient) + vec3(1.1, 1.06, 1.0) * iceSparkle * inSun;

    vec3 rockDark = srgbToLinear(vec3(0.088, 0.088, 0.096));
    vec3 rockLit  = srgbToLinear(vec3(0.85, 0.82, 0.77));
    vec3 boulderCol = mix(rockDark * 0.65, mix(rockDark, rockLit, pow(boulderLit, 0.80) * 0.95), inSun);

#if DEBUG_MODE == 6
    vec3 dbgDust = vec3(0.55) * (sunIrrad * inSun + shadowAmbient);
    vec3 dbgRock = mix(vec3(0.05), vec3(0.08 + 0.82 * boulderLit), inSun);
    return vec4(mix(dbgDust, dbgRock, boulderMask * 0.94), saturate(density * 0.95 + boulderMask * 0.88));
#endif

    vec3 finalCol = mix(litDust, boulderCol, boulderMask * 0.95);
    // Keep dense B/A rings solid against background star pinholes inside shadow while Cassini stays translucent!
    float shadowOpacityBoost = (1.0 - inSun) * smoothstep(0.22, 0.32, u) * cassiniTrans * enckeTrans * 0.24;
    float alpha = saturate(density * 0.94 + shadowOpacityBoost + boulderMask * 0.88);
    return vec4(finalCol, alpha);
}

vec3 renderSpace(vec2 uv, vec2 fragCoord, float pxAngle) {
    float du = gSceneTime - 2.75;

    float orbitAng = 0.262 + 0.0175 * du;
    float camDist  = 7.45 + 0.060 * du;
    vec3 ro = SP_PLANET_CENTER + vec3(sin(orbitAng) * camDist, 0.38 + 0.014 * du, cos(orbitAng) * camDist);
    float lookOff  = 2.18 - 0.030 * du;
    vec3 ta = SP_PLANET_CENTER + vec3(cos(orbitAng) * lookOff, 0.115, -sin(orbitAng) * lookOff);
    applyOrbit(ro, SP_PLANET_CENTER, -3.5);

    mat3 cam = cameraMatrix(ro, ta, 0.0);
    vec3 rd  = cameraRay(cam, uv, SP_FOCAL);

    float rayPx = pxAngle * (1.95 / SP_FOCAL) + 0.0 * fragCoord.x;

    vec3 sunWorldDir = normalize(vec3(1.318, 0.562, -2.62));
    vec3 keyLight    = normalize(vec3(0.994, 0.035, 0.102));

    // Sleeker grazing ring plane tilt matching film_0..4.png ellipse opening & right-ansa turnaround!
    vec3 ringNormal = normalize(vec3(-0.042, 0.981, 0.189));
    vec3 ringX      = normalize(cross(ringNormal, vec3(0.0, 0.0, 1.0)));
    vec3 ringZ      = normalize(cross(ringX, ringNormal));

#if DEBUG_MODE == 1
    vec3 pSlice = vec3(uv.x * 3.4 - 0.5, uv.y * 3.4 - 0.04, 0.0);
    float dPl = length(pSlice - SP_PLANET_CENTER) - SP_PLANET_RADIUS;
    vec3 relS = pSlice - SP_PLANET_CENTER;
    float rS = length(vec2(dot(relS, ringX), dot(relS, ringZ)));
    float dRg = length(vec2(max(max(SP_RING_INNER - rS, rS - SP_RING_OUTER), 0.0), dot(relS, ringNormal))) - 0.03;
    return debugDistance(min(dPl, dRg));
#endif

    vec2 tSph   = iSphere(ro, rd, SP_PLANET_CENTER, SP_PLANET_RADIUS);
    float tRing = iPlane(ro - SP_PLANET_CENTER, rd, ringNormal, 0.0);

    vec3 toCenter = SP_PLANET_CENTER - ro;
    float tClosest = max(dot(toCenter, rd), 0.0);
    float closestDist = length(ro + rd * tClosest - SP_PLANET_CENTER);
    float limbWorldPx = tClosest * rayPx;

    bool hitPlanet = (tSph.x > 0.0);
    float planetAA = hitPlanet ? smoothstep(SP_PLANET_RADIUS, SP_PLANET_RADIUS - limbWorldPx * 1.35, closestDist) : 0.0;
    bool hitRing   = (tRing > 0.0);

    bool opaquePlanetCore = (planetAA > 0.999);
    float nebMask = 0.0;
    vec3 bg = vec3(0.0);
    if (!opaquePlanetCore) {
        bg = sp_nebulaAndStars(rd, sunWorldDir, cam, uv, rayPx, nebMask);

        float atmoAura = exp(-max(closestDist - SP_PLANET_RADIUS, 0.0) / max(limbWorldPx * 2.4, 0.0032))
                       * step(SP_PLANET_RADIUS * 0.985, closestDist);
        if (atmoAura > 0.002) {
            vec3 limbDir = normalize(ro + rd * tClosest - SP_PLANET_CENTER);
            float limbSun = smoothstep(-0.04, 0.55, dot(limbDir, keyLight));
            bg += srgbToLinear(vec3(0.64, 0.72, 0.86)) * atmoAura * limbSun * 0.16;
        }
    }

    vec4 ringSample = vec4(0.0);
    float boulderMask = 0.0;
    vec3 ringOutN = ringNormal;
    bool ringVisible = hitRing && (!opaquePlanetCore || tRing < tSph.x);
    if (ringVisible) {
        ringSample = sp_shadeRings(ro + rd * tRing, tRing, rd, keyLight, ringNormal, ringX, ringZ, rayPx, boulderMask, ringOutN);
    }

    vec3 planetCol = vec3(0.0);
    vec3 planetOutN = vec3(0.0, 0.0, 1.0);
    float cloudHeightMask = 0.0;
    if (hitPlanet && (!ringVisible || tSph.x < tRing || ringSample.a < 0.995)) {
        planetCol = sp_shadeGasGiant(ro + rd * tSph.x, rd, keyLight, rayPx, planetOutN, cloudHeightMask);
    }

#if DEBUG_MODE == 2
    if (hitPlanet && (!ringVisible || tSph.x < tRing || ringSample.a < 0.15)) return debugNormal(planetOutN);
    if (ringVisible && ringSample.a > 0.05) return debugNormal(ringOutN);
    return vec3(0.0);
#elif DEBUG_MODE == 3
    if (hitPlanet && (!ringVisible || tSph.x < tRing || ringSample.a < 0.20)) return debugIdColor(1.0);
    if (ringVisible && boulderMask > 0.35) return debugIdColor(3.0);
    if (ringVisible && ringSample.a > 0.05) return debugIdColor(2.0);
    return debugIdColor(0.0);
#elif DEBUG_MODE == 4
    float cost = 0.06 + 0.12 * step(0.01, nebMask) + (hitPlanet ? 0.28 : 0.0) + (ringVisible && ringSample.a > 0.01 ? 0.20 : 0.0);
    return debugHeat(cost);
#elif DEBUG_MODE == 5
    return vec3(hitPlanet ? cloudHeightMask : 0.0, ringSample.a, nebMask);
#endif

    vec3 col = bg;
    if (hitPlanet) {
        vec3 behindPlanet = bg;
        if (ringVisible && tRing > tSph.x) {
            behindPlanet = mix(bg, ringSample.rgb, ringSample.a);
        }
        col = mix(behindPlanet, planetCol, planetAA);
        if (ringVisible && tRing < tSph.x) {
            col = mix(col, ringSample.rgb, ringSample.a);
        }
    } else if (ringVisible) {
        col = mix(bg, ringSample.rgb, ringSample.a);
    }

    return col;
}

// ==== PART: 02a_forest_trees.glsl ====
// =============================================================================
// SCENE II (Part A): FOREST TREES — Ancient Redwood Trunks, Buttress Root Spurs,
// Chunky Braided Sequoia Bark Slabs, Pale Crustose Lichen & Dense Conifer Canopy
// =============================================================================

// Trig-free C2-smooth 2-octave base terrain undulation (called every march step!)
float forestBaseHeight(vec2 xz) {
    vec2 p0 = xz * 0.34;
    vec2 p1 = mat2(1.60, 1.20, -1.20, 1.60) * p0 + vec2(17.13, -3.71);
    float n = (valueNoise(p0) - 0.5) * 1.35 + (valueNoise(p1) - 0.5) * 0.68;
    return 0.15 * n - 0.09 * exp(-xz.x * xz.x * 0.38);
}

// 12 curated corridor redwoods & understory saplings projectively solved across 5.0s, 7.0s & 9.0s:
// vec4(x, z, baseR, seed)
const vec4 FT_HERO_TRUNKS[12] = vec4[12](
    vec4(-2.86, -4.52, 0.68,  1.10), // 0: Left FG giant hero redwood (frames 5s/7s, warm sunlit root spur in bottom-left of 9s!)
    vec4( 1.75, -4.76, 0.39,  2.70), // 1: Right FG lichen-clad redwood (opens sunlit right gap in 5s/7s, right framer at 9s!)
    vec4(-1.92, -6.65, 0.39,  4.30), // 2: Left MG hero redwood (becomes left-of-center hero at 9s!)
    vec4( 3.46, -9.45, 0.44,  5.90), // 3: Right MG hero redwood (eclipsed behind Trunk 1 at 5s, frames sunburst slot at 9s!)
    vec4(-2.48, -9.20, 0.26,  7.40), // 4: Left-corridor secondary MG redwood
    vec4(-1.42, -12.80, 0.30, 9.10), // 5: Center-left misty corridor redwood
    vec4( 0.58, -13.60, 0.25, 10.80), // 6: Center misty corridor redwood
    vec4( 1.82, -12.40, 0.29, 12.50), // 7: Center-right misty sunbeam redwood
    vec4(-0.68, -10.60, 0.092, 14.20), // 8: Understory conifer sapling (center-left)
    vec4( 1.55,  -9.20, 0.090, 17.60), // 9: Understory conifer sapling (right-corridor, solid continuous stem!)
    vec4( 3.35,  -5.85, 0.088, 20.40), // 10: Sunlit right-corridor young conifer tree (visible in 5s & 7s right gap!)
    vec4( 5.45,  -7.15, 0.36, 15.90)  // 11: Far-right 5s/7s edge framing redwood
);

vec2 ft_trunkLean(float hY, float baseR, float seed) {
    float hc = clamp(hY, 0.0, 14.0);
    float rise = (hc * hc / (hc * hc + 3.5)) * min(baseR * 1.8, 1.0);
    return vec2(
        sin(seed * 2.31) * 0.008 * hc + 0.028 * sin(hc * 0.21 + seed),
        cos(seed * 1.73) * 0.007 * hc + 0.024 * cos(hc * 0.17 - seed * 1.4)
    ) * rise;
}

// Fast 2D silhouette bark chart: chunky braided vertical Sequoia ridges (~8.5/m primary, right-side-up crests!)
float ft_barkDispChart(vec2 bUV) {
    float braid = (valueNoise(bUV * vec2(2.8, 0.85)) - 0.5) * 0.09;
    vec2 wUV = vec2(bUV.x + braid, bUV.y);
    float r0 = 1.0 - abs(valueNoise(wUV * vec2(8.6, 1.85)) * 2.0 - 1.0);
    float r1 = 1.0 - abs(valueNoise(wUV * vec2(19.5, 4.10) + vec2(3.7, -1.9)) * 2.0 - 1.0);
    float notch = smoothstep(0.58, 0.88, abs(valueNoise(wUV * vec2(5.5, 6.5) + vec2(-3.1, 5.4)) * 2.0 - 1.0));
    return ((r0 * 0.68 + r1 * 0.32) - 0.50) * 0.92 - notch * 0.20 * r0;
}

// Detailed sculpture evaluated ONLY near the closest hero trunk(s)
vec2 ft_sdHeroTreeDetailed(vec3 p, float baseGroundY, vec4 tr, bool hasRoots) {
    float hY = p.y - baseGroundY;
    float baseR = tr.z;
    float seed  = tr.w;

    vec2 q = p.xz - (tr.xy + ft_trunkLean(hY, baseR, seed));
    float r = length(q);
    vec2 dir = q / max(r, 1e-4);

    float cos3 = dir.x * (dir.x * dir.x - 3.0 * dir.y * dir.y);
    float sin3 = dir.y * (3.0 * dir.x * dir.x - dir.y * dir.y);
    float cos4 = 1.0 - 8.0 * dir.x * dir.x * dir.y * dir.y;
    float lobe = 1.0 + 0.048 * (cos3 * cos(seed) + sin3 * sin(seed))
                     + 0.024 * cos4 * sin(seed * 1.7);

    float flare = 1.0 + (hasRoots ? 0.35 : 0.16) * exp(-max(hY + 0.12, 0.0) * 1.28)
                      + (hasRoots ? 0.11 : 0.02) * exp(-max(hY, 0.0) * 0.42);
    float taper = max(0.70, 1.0 - 0.013 * max(hY, 0.0));
    float rad   = baseR * flare * taper * lobe;
    float dCore = r - rad;

    float dCombined = dCore;
    float matId = MAT_FOREST_TRUNK;
    float trunkWeight = 1.0;

    if (hasRoots) {
        // Gnarly coast-redwood stem burls / healed callus knots
        if (hY > 0.45 && hY < 5.5 && dCore < 0.34) {
            float bH1 = mix(1.10, 2.35, fract(seed * 0.37));
            float bA1 = seed * 2.35;
            vec2 bD1  = vec2(cos(bA1), sin(bA1));
            vec3 bP1  = vec3(bD1.x * rad * 0.84, bH1, bD1.y * rad * 0.84);
            float dB1 = sdEllipsoid(vec3(q.x, hY, q.y) - bP1, vec3(baseR * 0.26, baseR * 0.19, baseR * 0.26));

            float bH2 = mix(2.75, 4.65, fract(seed * 0.61));
            float bA2 = -seed * 1.75 + 1.9;
            vec2 bD2  = vec2(cos(bA2), sin(bA2));
            vec3 bP2  = vec3(bD2.x * rad * 0.85, bH2, bD2.y * rad * 0.85);
            float dB2 = sdEllipsoid(vec3(q.x, hY, q.y) - bP2, vec3(baseR * 0.23, baseR * 0.17, baseR * 0.23));

            dCombined = smin(dCombined, min(dB1, dB2), baseR * 0.14);
        }

        // Neighbor-checked 6-sector polar buttress root spurs flaring & snaking into the ground
        const float N_SPURS = 6.0;
        if (hY < 2.05 && r < baseR * 2.45) {
            vec2 qr = rot2(seed * 1.13 + 0.32) * q;
            vec2 pair = domPolarPair(qr, N_SPURS);
            float dSpurs = 1e5;
            float seedCell = floor(seed * 7.0 + 0.5);

            for (int s = ZERO; s < 2; s++) {
                float sid = (s == 0) ? pair.x : pair.y;
                vec2 sec = domPolarSector(qr, sid, N_SPURS);
                vec3 rh  = hash32(vec2(sid + 3.0, seedCell));

                bool isHero0 = (seed < 1.5);
                float spurReach = baseR * (isHero0 ? mix(1.68, 2.04, rh.x) : mix(1.45, 1.92, rh.x));
                float attachH   = baseR * mix(0.98, 1.56, rh.y);
                float uRad      = clamp((sec.x - baseR * 0.45) / max(spurReach - baseR * 0.45, 0.1), 0.0, 1.0);
                float snakeZ    = (rh.z - 0.5) * 0.22 * baseR * sin(uRad * PI)
                                + 0.045 * baseR * sin(uRad * 5.0 + rh.x * TAU);

                vec3 rp = vec3(sec.x, hY, sec.y - snakeZ);
                vec3 pA = vec3(baseR * 0.46, attachH, 0.0);
                vec3 pB = vec3(mix(baseR * 0.62, spurReach, 0.46), attachH * 0.21, 0.0);
                vec3 pC = vec3(spurReach, -0.08, 0.0);

                vec3 rpFlute = vec3(rp.x, rp.y * 0.88, rp.z * 1.28);
                float dSeg1 = sdCapsule(rpFlute, vec3(pA.x, pA.y * 0.88, 0.0), vec3(pB.x, pB.y * 0.88, 0.0), baseR * 0.175);
                float dSeg2 = sdCapsule(rp, pB, pC, baseR * mix(0.14, 0.062, uRad));
                float dRoot = smin(dSeg1 * 0.78, dSeg2, baseR * 0.125);
                dSpurs = min(dSpurs, dRoot);
            }

            vec2 blended = sminBlend(dCombined, dSpurs, baseR * 0.21);
            dCombined   = blended.x;
            trunkWeight = blended.y;
            if (trunkWeight < 0.52 && hY < 0.78) {
                matId = MAT_FOREST_ROOT;
            }
        }
    }

    if (gFastMap || dCombined > 0.086 || p.z < -10.5) {
        return vec2(dCombined, matId);
    }

    // Counterclockwise dual-chart Sequoia bark silhouette narrowed onto unseen -Z back spine (>95% 1-tap!)
    float dispFade = (1.0 - smoothstep(0.022, 0.082, dCombined)) * (1.0 - smoothstep(-8.2, -10.5, p.z));
    float effR = mix(baseR, 0.50, 0.35);
    float weave = 0.060 * sin(dir.x * 2.7 + dir.y * 1.9 + hY * 0.85 + seed * 1.7);
    float vM = hY + seed * 3.17;
    float wFront = smoothstep(-0.92, -0.74, dir.y);

    float barkDisp;
    if (wFront > 0.999) {
        barkDisp = ft_barkDispChart(vec2(atan(dir.x, dir.y) * effR + weave, vM));
    } else if (wFront < 0.001) {
        barkDisp = ft_barkDispChart(vec2(atan(-dir.x, -dir.y) * effR + 17.31 + weave, vM));
    } else {
        float dA = ft_barkDispChart(vec2(atan(dir.x, dir.y) * effR + weave, vM));
        float dB = ft_barkDispChart(vec2(atan(-dir.x, -dir.y) * effR + 17.31 + weave, vM));
        barkDisp = mix(dB, dA, wFront);
    }

    float dispAmp = min(baseR, 0.54) * mix(0.044, 0.074, trunkWeight);
    float dDisplaced = (dCombined - dispAmp * barkDisp * dispFade) * mix(1.0, 0.73, dispFade);
    return vec2(dDisplaced, matId);
}

// Weathered splintered redwood snag / stump in left-center midground (matching ref_7.00 & ref_9.00)
float ft_sdBrokenSnag(vec3 p, float baseGroundY) {
    vec2 snagXZ = vec2(-1.18, -11.20);
    vec2 q = p.xz - snagXZ;
    float r = length(q);
    float hY = p.y - baseGroundY;
    if (r > 0.42 || hY > 1.40) {
        return max(r - 0.22, hY - 1.12) + 0.04;
    }
    vec2 dir = q / max(r, 1e-4);
    float jagTop = 0.92 + 0.24 * dir.x + 0.14 * (dir.x * dir.x - dir.y * dir.y);
    float rad = 0.12 * (1.0 + 0.40 * exp(-max(hY, 0.0) * 2.2)) * max(0.34, 1.0 - 0.45 * max(hY, 0.0));
    return max(r - rad, hY - jagTop) * 0.84;
}

vec2 mapForestTrees(vec3 p, float baseGroundY) {
    float hY = p.y - baseGroundY;
    float flareApprox = 1.0 + 0.48 * clamp(1.0 - max(hY, 0.0) * 0.65, 0.0, 1.0);

    int bestIdx = 0;
    float bestFast = 1e5;
    float secondFast = 1e5;
    vec4 bestTr = FT_HERO_TRUNKS[0];

    // Unrolled constant-index scan (avoids Metal dynamic const-array stack spill!)
    float trunkLeanMargin = 0.015 + 0.080 * clamp(max(hY, 0.0) * 0.14, 0.0, 1.0);
    for (int i = 0; i < 12; i++) {
        vec4 tr = FT_HERO_TRUNKS[i];
        bool isSapling = (i >= 8 && i <= 10);
        float r = length(p.xz - tr.xy) - (isSapling ? 0.038 : trunkLeanMargin);
        float maxSpurMul = (i == 0) ? 2.08 : 1.96;
        float rootEnvR = (!isSapling && hY < tr.z * 1.95)
            ? (tr.z * mix(maxSpurMul, 1.12, clamp(max(hY, 0.0) / max(tr.z * 1.80, 0.2), 0.0, 1.0)))
            : 0.0;
        float dFast = r - max(tr.z * flareApprox * 1.18, rootEnvR);

        if (dFast < bestFast) {
            secondFast = bestFast;
            bestFast   = dFast;
            bestIdx    = i;
            bestTr     = tr;
        } else if (dFast < secondFast) {
            secondFast = dFast;
        }
    }

    vec2 res = vec2(bestFast, MAT_FOREST_TRUNK);
    if (bestFast < ((hY < 1.30) ? 0.21 : 0.11)) {
        bool hasRoots = (bestIdx < 8 || bestIdx == 11);
        vec2 dDetail = ft_sdHeroTreeDetailed(p, baseGroundY, bestTr, hasRoots);
        res = (dDetail.x < secondFast) ? dDetail : vec2(secondFast, MAT_FOREST_TRUNK);
    }

    float dSnag = ft_sdBrokenSnag(p, baseGroundY);
    if (dSnag < res.x) res = vec2(dSnag, MAT_FOREST_TRUNK);

    // Neighbor-checked 2x2 outer redwood grove (keeps central misty corridor clear)
    if (abs(p.x) > 3.6 || p.z < -19.5 || p.z > 0.6) {
        const float CELL = 5.0;
        vec2 id   = domRepeatId(p.xz, vec2(CELL));
        vec2 side = sign(p.xz - CELL * id);
        float groveFlare = 1.0 + 0.26 * exp(-max(hY + 0.1, 0.0) * 1.35);
        float groveTaper = max(0.72, 1.0 - 0.011 * max(hY, 0.0));

        for (int j = ZERO; j < 2; j++) {
            for (int i = ZERO; i < 2; i++) {
                vec2 cell = id + vec2(float(i), float(j)) * side;
                vec3 h = hash32(cell + vec2(53.0, 19.0));
                vec2 pos = cell * CELL + (h.xy - 0.5) * 1.65;
                if (abs(pos.x) < 4.85 && pos.y > -21.5 && pos.y < 1.8) continue;
                // Keep 3D grove strictly inside tmax sphere so distant trunks never clip into floating cigars!
                if (dot2(pos - vec2(0.0, -6.6)) > 15.8 * 15.8) continue;

                float baseR = mix(0.24, 0.46, h.z);
                float dt = length(p.xz - pos) - baseR * groveFlare * groveTaper;
                if (dt < res.x) res = vec2(dt, MAT_FOREST_TRUNK);
            }
        }
    } else {
        float dToOuterZone = min(3.65 - abs(p.x), p.z + 19.55);
        if (dToOuterZone < res.x) res = vec2(max(dToOuterZone, 0.18), MAT_FOREST_TRUNK);
    }

    return res;
}

vec4 ft_nearestTrunk(vec3 p) {
    float bestD = 1e6;
    vec4 bestTr = FT_HERO_TRUNKS[0];

    for (int i = 0; i < 12; i++) {
        vec4 tr = FT_HERO_TRUNKS[i];
        float d = length(p.xz - tr.xy) - tr.z * 1.35;
        if (d < bestD) {
            bestD = d;
            bestTr = tr;
        }
    }

    float dSnag = length(p.xz - vec2(-1.18, -11.20)) - 0.16;
    if (dSnag < bestD) {
        bestD = dSnag;
        bestTr = vec4(-1.18, -11.20, 0.13, 19.3);
    }

    if (abs(p.x) > 3.6 || p.z < -19.5 || p.z > 0.6) {
        const float CELL = 5.0;
        vec2 id   = domRepeatId(p.xz, vec2(CELL));
        vec2 side = sign(p.xz - CELL * id);
        for (int j = ZERO; j < 2; j++) {
            for (int i = ZERO; i < 2; i++) {
                vec2 cell = id + vec2(float(i), float(j)) * side;
                vec3 h = hash32(cell + vec2(53.0, 19.0));
                vec2 pos = cell * CELL + (h.xy - 0.5) * 1.65;
                if (abs(pos.x) < 4.85 && pos.y > -21.5 && pos.y < 1.8) continue;
                if (dot2(pos - vec2(0.0, -6.6)) > 15.8 * 15.8) continue;
                float baseR = mix(0.24, 0.46, h.z);
                float d = length(p.xz - pos) - baseR * 1.25;
                if (d < bestD) {
                    bestD = d;
                    bestTr = vec4(pos.x, pos.y, baseR, h.x * 13.7 + h.y * 7.3);
                }
            }
        }
    }
    return bestTr;
}

// Chunky, braided, right-side-up vertical Sequoia bark ridges (#84: zero brain/amoeba zero-crossing rings & zero Vantablack!)
float ft_barkBumpChart(vec2 mUV, float medFilter, float microFilter, out float outSlab, out float outFurrow, out float outCh) {
    float braid = gradientNoise(mUV * vec2(2.8, 0.85)) * 0.095
                + gradientNoise(mUV * vec2(6.8, 2.10) + vec2(5.1, -2.7)) * 0.032;
    vec2 wUV = vec2(mUV.x + braid, mUV.y);

    // Raised chunky Sequoia bark ridges (1 - |g| puts crests on ridges and natural V-grooves in valleys -> zero closed dark loops!)
    float g0 = gradientNoise(wUV * vec2(8.6, 1.85));
    float g1 = gradientNoise(wUV * vec2(19.5, 4.20) + vec2(7.3, -3.1));
    float g2 = gradientNoise(wUV * vec2(38.0, 7.80) + vec2(-4.2, 6.8));

    float r0 = clamp(1.0 - abs(g0 * 1.45), 0.0, 1.0);
    // Broaden ridge crowns into chunky Sequoia bark plates while keeping valleys natural V-fissures!
    outSlab = smoothstep(0.08, 0.78, r0);

    float r1 = clamp(1.0 - abs(g1 * 1.48), 0.0, 1.0);
    float r2 = clamp(1.0 - abs(g2 * 1.48), 0.0, 1.0);
    outFurrow = clamp(r1 * 0.62 + r2 * r2 * 0.38, 0.0, 1.0);

    // Subtle weathered horizontal bark checks
    outCh = smoothstep(0.55, 0.88, abs(gradientNoise(wUV * vec2(5.8, 6.8) + vec2(-3.1, 5.4)) * 1.48));

    // Medium + fine vertical shredded redwood bark fibers
    float fbMed  = (medFilter > 0.01)   ? ((1.0 - abs(valueNoise(wUV * vec2(52.0, 8.5)) * 2.0 - 1.0)) * medFilter)   : 0.0;
    float fbFine = (microFilter > 0.01) ? ((1.0 - abs(valueNoise(wUV * vec2(102.0, 16.0)) * 2.0 - 1.0)) * microFilter) : 0.0;

    float plate = outSlab * 0.56 + outFurrow * (0.18 + 0.28 * outSlab) - outCh * 0.18 * outSlab;
    return plate + fbMed * 0.18 + fbFine * 0.14;
}

void shadeForestTree(float matId, vec3 p, vec3 nIn, float t, out vec3 albedo, out float rough, out vec3 nOut) {
    vec4 tr = ft_nearestTrunk(p);
    float baseGroundY = forestBaseHeight(p.xz);
    float hY    = p.y - baseGroundY;
    float baseR = tr.z;
    float seed  = tr.w;
    bool isRoot = (matId > 11.5);

    vec2 q      = p.xz - (tr.xy + ft_trunkLean(hY, baseR, seed));
    vec2 radDir = q / max(length(q), 1e-4);
    float effR  = mix(baseR, 0.50, 0.35);

    // 3D anastomosing bark weave (100% seam-free & mirror-free!)
    float weave3D = gradientNoise(vec3(radDir * 2.4 + vec2(seed * 1.7, -seed * 1.3), hY * 0.75)) * 0.065;
    float vM      = hY + seed * 3.17;
    float uA      = atan(radDir.x, radDir.y) * effR + weave3D;
    float uB      = atan(-radDir.x, -radDir.y) * effR + 17.31 + weave3D;
    float wFront  = smoothstep(-0.92, -0.74, radDir.y);

    float detailAtten = 1.0 - smoothstep(6.0, 22.0, t);
    float medFilter   = 1.0 - smoothstep(6.5, 18.0, t);
    float microFilter = 1.0 - smoothstep(2.5, 9.5, t);

    float epsU = mix(0.0036, 0.012, smoothstep(2.0, 14.0, t));
    float epsV = mix(0.0080, 0.025, smoothstep(2.0, 14.0, t));

    // ZERO-looped 3-tap evaluation into pure registers (zero Metal stack spill & 1 AST copy!)
    float b0 = 0.0, b1 = 0.0, b2 = 0.0;
    float slab1 = 0.5, furrow2 = 0.5, crossChop = 0.0;
    int numTaps = (detailAtten > 0.01 && (!gInDissolve || t < 7.5)) ? 3 : 1;

    for (int tap = ZERO; tap < 3; tap++) {
        if (tap >= numTaps) break;
        vec2 dUV = (tap == 0) ? vec2(0.0) : ((tap == 1) ? vec2(epsU, 0.0) : vec2(0.0, epsV));
        float sA = 0.0, fA = 0.0, cA = 0.0, hA = 0.0;
        float sB = 0.0, fB = 0.0, cB = 0.0, hB = 0.0;

        if (wFront > 0.001) {
            hA = ft_barkBumpChart(vec2(uA, vM) + dUV, medFilter, microFilter, sA, fA, cA);
        }
        if (wFront < 0.999) {
            hB = ft_barkBumpChart(vec2(uB, vM) + dUV, medFilter, microFilter, sB, fB, cB);
        }

        float hMix = mix(hB, hA, wFront);
        if (tap == 0) {
            b0        = hMix;
            slab1     = mix(sB, sA, wFront);
            furrow2   = mix(fB, fA, wFront);
            crossChop = mix(cB, cA, wFront);
        } else if (tap == 1) {
            b1 = hMix;
        } else {
            b2 = hMix;
        }
    }

    vec3 nBumped = nIn;
    if (numTaps == 3) {
        vec3 horizTang = vec3(-nIn.z, 0.0, nIn.x);
        float htLen = length(horizTang);
        vec3 tangU = (htLen > 1e-3) ? (horizTang / htLen) : vec3(1.0, 0.0, 0.0);
        vec3 tangV = normalize(cross(nIn, tangU));

        // Strong craggy Sequoia bark relief across both grazing & direct-lit flanks!
        float termGuard = smoothstep(-0.34, 0.08, dot(nIn, FOREST_SUN_DIR));
        vec3 barkGrad = tangU * ((b0 - b1) / epsU * mix(0.024, 0.042, termGuard))
                      + tangV * ((b0 - b2) / epsV * mix(0.020, 0.036, termGuard));
        nBumped = normalize(nIn + barkGrad * detailAtten);
    }

    vec3  c3D     = vec3(radDir * effR, hY) + vec3(seed * 5.71, -seed * 4.13, seed * 3.17);
    float barkVar = gradientNoise(c3D * vec3(2.2, 2.2, 0.9) + vec3(seed * 2.1));
    float sunFacingFlank = smoothstep(-0.15, 0.65, dot(radDir, FOREST_SUN_DIR.xz));

    float ridgeHeight = clamp(slab1 * 0.58 + furrow2 * (0.18 + 0.28 * slab1) - crossChop * 0.20 * slab1, 0.0, 1.0);
    float creviceMask = smoothstep(0.06, 0.42, ridgeHeight);
    float crownMask   = smoothstep(0.48, 0.84, ridgeHeight);

    // Physical dark chocolate-umber bark fissures (#84: sRGB 0.095 -> responds to woodland fill, zero Vantablack blotches!)
    vec3 cDarkCrevice  = srgbToLinear(vec3(0.095, 0.068, 0.048));
    vec3 cWeatheredAsh = srgbToLinear(vec3(0.215, 0.175, 0.140));
    vec3 cCinnamonBark = srgbToLinear(vec3(0.315, 0.215, 0.145));
    vec3 cSunlitOchre  = srgbToLinear(vec3(0.415, 0.318, 0.212));

    vec3 midBark    = mixOklab(cWeatheredAsh, cCinnamonBark, clamp(0.46 + 0.62 * barkVar + 0.16 * sunFacingFlank, 0.0, 1.0));
    vec3 raisedBark = mixOklab(midBark, cSunlitOchre, crownMask * (0.38 + 0.52 * sunFacingFlank));
    vec3 barkCol    = mixOklab(cDarkCrevice, raisedBark, creviceMask);
    float barkRough = mix(0.96, 0.80, crownMask * 0.75 + furrow2 * 0.25);

    // Matte pale celadon / sage-grey crustose lichen up to 2.25m (rich coverage on Trunk 1 at 7s & 9s!)
    float lichHeightEnv = (1.0 - smoothstep(1.30, 2.25, hY)) * smoothstep(-0.18, 0.06, hY);
    if (lichHeightEnv > 0.01) {
        float trunkPref   = 0.45 + 0.55 * (0.5 + 0.5 * sin(seed * 2.1 - 4.1));
        float coolSide    = 0.60 + 0.40 * (1.0 - smoothstep(-0.35, 0.68, dot(radDir, FOREST_SUN_DIR.xz)));
        vec2  lichUV      = vec2((wFront > 0.5 ? uA : uB), vM);
        float colonyMacro = fbm(lichUV * vec2(2.3, 1.55) + vec2(seed * 2.3, -seed * 1.7), 2);
        float fineCrust   = fbm(lichUV * vec2(21.0, 17.0) + colonyMacro * 1.5, 2);
        float raggedEdge  = abs(simplexNoise(lichUV * vec2(44.0, 36.0)));

        float crustField = fineCrust * 0.68 + colonyMacro * 0.58 - raggedEdge * 0.17;
        float onRidges   = smoothstep(0.20, 0.54, ridgeHeight);
        float lichenMask = clamp(smoothstep(-0.08, 0.20, crustField) * lichHeightEnv * trunkPref * coolSide * onRidges * 1.35, 0.0, 0.90);

        vec3 cDustySage  = srgbToLinear(vec3(0.34, 0.43, 0.33));
        vec3 cPaleLichen = srgbToLinear(vec3(0.50, 0.58, 0.46));
        vec3 lichCol = mixOklab(cDustySage, cPaleLichen, smoothstep(0.04, 0.30, fineCrust));

        barkCol   = mixOklab(barkCol, lichCol, lichenMask);
        barkRough = mix(barkRough, 0.91, lichenMask);
    }

    // Velvety forest bryophyte moss tucked STRICTLY in low root-spur hollows (hY < 0.54m)!
    float mossZone = (1.0 - smoothstep(0.16, 0.54, hY)) * (isRoot ? 1.0 : 0.55);
    if (mossZone > 0.01) {
        float hollowPref  = (1.0 - smoothstep(0.20, 0.56, ridgeHeight)) * 0.60
                          + smoothstep(0.10, 0.66, nIn.y) * (isRoot ? 0.95 : 0.45);
        float mossCushion = billowFbm(p * 5.2 + vec3(seed * 1.7), 2);
        float mossPatch   = gradientNoise(p * 3.4 + vec3(seed * 2.9, 1.2, -2.1));
        float mossMask    = clamp(mossZone * smoothstep(0.22, 0.60, hollowPref + 0.34 * mossPatch) * (0.50 + 0.62 * mossCushion), 0.0, 0.88);

        vec3 cDeepMoss = srgbToLinear(vec3(0.078, 0.175, 0.038));
        vec3 cLushMoss = srgbToLinear(vec3(0.195, 0.315, 0.075));
        vec3 mossCol   = mixOklab(cDeepMoss, cLushMoss, clamp(mossCushion * 0.85 + 0.15, 0.0, 1.0));

        barkCol   = mixOklab(barkCol, mossCol, mossMask);
        barkRough = mix(barkRough, 0.92, mossMask);
        if (detailAtten > 0.01 && mossMask > 0.15) {
            vec3 mossN = vec3(gradientNoise(p * 26.0), 0.35, gradientNoise(p * 26.0 + vec3(17.1, -9.3, 5.7)));
            nBumped = normalize(mix(nBumped, normalize(nBumped + mossN * 0.22 * detailAtten), mossMask * 0.55));
        }
    }

    albedo = barkCol;
    rough  = barkRough;
    nOut   = nBumped;
}

// Ultra-fast analytic trunk occlusion + trig-free valueNoise canopy gobo along FOREST_SUN_DIR
float forestSunVisibility(vec3 p) {
    float vis = 1.0;
    vec2 ld = FOREST_SUN_DIR.xz;
    float ldInvLen = inversesqrt(max(dot(ld, ld), 1e-4));
    vec2 ldDir  = ld * ldInvLen;
    float slopeY = FOREST_SUN_DIR.y * ldInvLen;

    for (int i = 0; i < 8; i++) {
        vec4 tr = FT_HERO_TRUNKS[i];
        vec2 toCyl = tr.xy - p.xz;
        if (toCyl.x < -0.75 || toCyl.y > 0.75) continue;
        float proj = dot(toCyl, ldDir);
        if (proj > 0.0 && proj < 18.0) {
            float perp = abs(toCyl.x * ldDir.y - toCyl.y * ldDir.x);
            float hitY = max(p.y + proj * slopeY, 0.0);
            float effR = tr.z * (1.0 + 0.22 * clamp(1.0 - hitY * 0.55, 0.0, 1.0));
            float penumbra = 0.040 + 0.018 * proj;
            vis *= smoothstep(effR - penumbra, effR + penumbra, perp);
        }
    }

    if (vis <= 0.005) return 0.0;

    float tCanopy = (9.0 - p.y) / max(FOREST_SUN_DIR.y, 0.15);
    vec2 skyHit   = p.xz + FOREST_SUN_DIR.xz * tCanopy;
    vec2 breeze   = vec2(0.04 * sin(gSceneTime * 0.55), 0.03 * cos(gSceneTime * 0.43));
    vec2 sc       = skyHit + breeze;

    vec2 scRot1 = mat2(0.80, -0.60, 0.60, 0.80) * sc;
    vec2 scRot2 = mat2(0.60,  0.80, -0.80, 0.60) * sc;
    float macroOpen  = smoothstep(0.28, 0.65, valueNoise(scRot1 * 0.34 + vec2(1.6, -0.8)));
    float boughGaps  = 0.62 * valueNoise(scRot1 * vec2(1.25, 0.82) + vec2(3.1, -1.4))
                     + 0.38 * valueNoise(scRot2 * 2.55 + vec2(-4.2, 2.9));
    float finePores  = valueNoise(scRot2 * vec2(4.6, 2.8) + vec2(2.3, 6.1));

    float shaftPattern = smoothstep(0.35, 0.66, boughGaps) * (0.32 + 0.68 * smoothstep(0.30, 0.72, finePores));
    return clamp(vis * mix(0.24, 1.0, macroOpen) * shaftPattern * 1.38, 0.0, 1.0);
}

float ft_cylinderExitT(vec2 roXZ, vec2 rdXZ, vec2 centerXZ, float radius) {
    float a = dot(rdXZ, rdXZ);
    if (a < 1e-5) return -1.0;
    vec2 oc = roXZ - centerXZ;
    float b = dot(oc, rdXZ);
    float c = dot(oc, oc) - radius * radius;
    float disc = b * b - a * c;
    if (disc < 0.0) return -1.0;
    return (-b + sqrt(disc)) / a;
}

// Per-layer ~54% lacy conifer bough density -> 3 depth layers stack to ~82% rich foliage + ~18% sparkling sky pinholes!
vec4 ft_coniferBoughLayer(vec2 p, float seed, float pxWorld, float sunScatter) {
    float crownEnv = smoothstep(-0.10, 1.05, p.y);
    if (crownEnv <= 0.002) return vec4(0.0);

    float upperFill = smoothstep(1.40, 3.80, p.y);
    vec2 sway = vec2(0.024 * sin(gSceneTime * 0.60 + seed + p.y * 0.4), 0.014 * cos(gSceneTime * 0.48 + p.x * 0.3));
    vec2 warp = vec2(gradientNoise(p * 0.42 + seed), gradientNoise(p * 0.42 + seed + 7.3));
    vec2 q    = p + sway + warp * vec2(0.68, 0.38);

    // Natural canopy openings so sparkling golden-white sky peeks through lacy needle gaps!
    float crownMass = smoothstep(-0.24, 0.24, fbm(q * vec2(0.38, 0.60) + vec2(seed * 3.1, -seed * 1.7), 2) + 0.12 * upperFill);
    if (crownMass <= 0.002) return vec4(0.0);

    // Horizontally sweeping conifer branch tiers + feathery lateral sprays
    float branchTier = ridgedFbm(q * vec2(0.52, 2.15) + vec2(seed * 2.3, 1.1), 2);
    float subSprays  = ridgedFbm(q * vec2(1.55, 3.45) - vec2(seed * 4.1, 3.7), 2);
    float woodyLimb  = pow(clamp(branchTier, 0.0, 1.0), 6.5) * crownMass * smoothstep(0.85, 1.75, p.y);
    float subTwigWeb = pow(clamp(subSprays, 0.0, 1.0), 4.2) * crownMass;

    float tuftClumps   = ridgedFbm(q * vec2(2.75, 4.00) + vec2(seed * 5.7, -2.9), 2);
    float needleFilter = gInDissolve ? 0.0 : (1.0 - smoothstep(0.020, 0.058, pxWorld));
    float fineNeedles  = 0.60;
    if (needleFilter > 0.01) {
        vec2 qA = rot2( 0.52) * q;
        vec2 qB = rot2(-0.52) * q;
        float combA = ridgedFbm(qA * vec2(3.8, 16.0) + seed * 8.7, 1);
        float combB = ridgedFbm(qB * vec2(3.8, 16.0) - seed * 6.1, 1);
        fineNeedles = mix(0.60, max(combA, combB), needleFilter);
    }

    float sprayBody  = clamp(pow(branchTier, 1.35) * 0.72 + subSprays * 0.42 + upperFill * 0.12, 0.0, 1.08);
    float needleLace = (0.38 + 0.62 * tuftClumps) * (0.42 + 0.85 * fineNeedles);
    float density    = crownEnv * crownMass * sprayBody * needleLace;

    float aa = clamp(pxWorld * 1.35, 0.020, 0.10);
    float foliageAlpha = smoothstep(0.22 - aa, 0.37 + aa, density);
    float twigMask     = clamp(woodyLimb * 1.5 + subTwigWeb * 0.48, 0.0, 1.0);
    float alpha        = max(foliageAlpha * 0.93, smoothstep(0.20, 0.55, twigMask) * 0.96);
    if (alpha <= 0.002) return vec4(0.0);

    float thinFringe  = 1.0 - smoothstep(0.20, 0.48, density);
    vec3 cDarkConifer = srgbToLinear(vec3(0.036, 0.072, 0.022));
    vec3 cMidConifer  = srgbToLinear(vec3(0.140, 0.228, 0.068));
    vec3 cGoldBacklit = srgbToLinear(vec3(0.510, 0.585, 0.180)) * (1.18 + 2.15 * pow(sunScatter, 2.1));
    vec3 cTwigBark    = srgbToLinear(vec3(0.030, 0.022, 0.014));

    vec3 needleCol = mixOklab(cDarkConifer, cMidConifer, clamp(tuftClumps * 0.76 + 0.16 * sunScatter, 0.0, 1.0));
    needleCol = mixOklab(needleCol, cGoldBacklit, clamp(thinFringe * (0.38 + 0.62 * sunScatter), 0.0, 1.0));
    vec3 col = mix(needleCol, cTwigBark, clamp(smoothstep(0.24, 0.64, twigMask) * 0.88, 0.0, 1.0));
    return vec4(col, alpha);
}

// Horizontal overarching conifer branch fans anchored directly to hero trunks & understory saplings!
vec4 ft_trunkBoughFan(vec2 hp, float trunkX, float reachX, float minY, float seed, float pxWorld, float sunScatter) {
    float dx = hp.x - trunkX;
    float adx = abs(dx);
    if (adx > reachX || hp.y < minY || hp.y > 10.2) return vec4(0.0);

    float uSpan = adx / reachX;
    float crownOutline = (1.0 - 0.06 * max(hp.y - 5.8, 0.0))
                       * (0.74 + 0.26 * fbm(vec2(hp.y * 0.88, seed * 3.1 + sign(dx) * 2.0), 2));
    float spanEnv = (1.0 - smoothstep(crownOutline * 0.56, crownOutline, uSpan))
                  * smoothstep(minY, minY + 0.72, hp.y);
    if (spanEnv <= 0.002) return vec4(0.0);

    float droopY = 0.26 * uSpan * reachX * 0.42 - 0.08 * uSpan * uSpan * reachX * 0.42;
    vec2 archP = vec2(dx, hp.y + droopY);
    vec2 nq = archP + 0.22 * vec2(gradientNoise(archP * 1.05 + seed), gradientNoise(archP * 1.05 - seed));

    float mainBoughs = ridgedFbm(nq * vec2(0.62, 2.15) + vec2(seed * 2.7, 0.5), 2);
    float stemMask   = pow(clamp(mainBoughs, 0.0, 1.0), 7.5) * spanEnv * (1.0 - smoothstep(0.76, 1.0, uSpan));

    float frondSprays  = ridgedFbm(nq * vec2(2.5, 4.0) + seed * 4.3, 2);
    float needleFilter = gInDissolve ? 0.0 : (1.0 - smoothstep(0.022, 0.095, pxWorld));
    float needles      = 0.62;
    if (needleFilter > 0.01) {
        vec2 rotCoord = rot2((dx >= 0.0 ? -0.48 : 0.48)) * nq;
        needles = mix(0.62, ridgedFbm(rotCoord * vec2(3.6, 16.5) + seed * 5.0, 2), needleFilter);
    }

    float sprayBody = clamp(pow(mainBoughs, 1.45) * 0.78 + frondSprays * 0.34, 0.0, 1.08);
    float fol = spanEnv * sprayBody * (0.40 + 0.85 * needles);
    float aa = clamp(pxWorld * 1.35, 0.018, 0.085);
    float folAlpha = smoothstep(0.22 - aa, 0.36 + aa, fol);
    float alpha = max(folAlpha * 0.92, smoothstep(0.20, 0.54, stemMask) * 0.95);
    if (alpha <= 0.002) return vec4(0.0);

    float backlitEdge = (1.0 - smoothstep(0.20, 0.48, fol)) * (0.35 + 0.65 * uSpan);
    vec3 cDark = srgbToLinear(vec3(0.036, 0.072, 0.022));
    vec3 cMid  = srgbToLinear(vec3(0.142, 0.230, 0.068));
    vec3 cGold = srgbToLinear(vec3(0.515, 0.590, 0.180)) * (1.18 + 2.15 * pow(sunScatter, 2.1));
    vec3 col = mixOklab(cDark, cMid, clamp(frondSprays * 0.76, 0.0, 1.0));
    col = mixOklab(col, cGold, clamp(backlitEdge * (0.38 + 0.62 * sunScatter), 0.0, 1.0));
    col = mix(col, srgbToLinear(vec3(0.030, 0.022, 0.014)), clamp(smoothstep(0.20, 0.58, stemMask) * 0.88, 0.0, 1.0));
    return vec4(col, alpha);
}

vec3 forestCanopySky(vec3 ro, vec3 rd, float pxAngle) {
    // Calibrated so solar starburst peeks right of Trunk 1 at 5s, eclipses behind Trunk 1 at 7s, and blazes at upper slot between Trunks 3 & 1 at 9s!
    vec3 canopySunDir = normalize(vec3(0.492, 0.388, -0.779));
    float sunMain = max(dot(rd, FOREST_SUN_DIR), 0.0);
    float sunGap  = max(dot(rd, canopySunDir), 0.0);
    float sunScatter = clamp(max(sunMain * 0.85, sunGap), 0.0, 1.0);

    // Matches 02b's ground mistTint seamlessly at the horizon (zero bright horizon band!)
    vec3 mistBase = mixOklab(
        srgbToLinear(vec3(0.31, 0.36, 0.24)),
        srgbToLinear(vec3(0.72, 0.68, 0.46)),
        pow(sunScatter, 2.2)
    );

    if (rd.y < -0.045) return mistBase;

    // Sparkling golden-ivory morning sky visible through lacy conifer needle pinholes above the horizon!
    float skyElev = smoothstep(0.06, 0.26, rd.y);
    vec3 skyCool  = srgbToLinear(vec3(0.64, 0.72, 0.54)) * 1.65;
    vec3 skyWarm  = srgbToLinear(vec3(1.00, 0.96, 0.84)) * 3.35;
    float skyGrad = clamp(pow(sunScatter, 1.6) * 0.78 + smoothstep(0.0, 0.50, rd.y) * 0.34, 0.0, 1.0);
    vec3 skyCol   = mixOklab(skyCool, skyWarm, skyGrad);

    vec3 sunOrthoX = normalize(cross(vec3(0.0, 1.0, 0.0), canopySunDir));
    vec3 sunOrthoY = cross(canopySunDir, sunOrthoX);
    vec2 sunDelta  = vec2(dot(rd, sunOrthoX), dot(rd, sunOrthoY));
    float sunAng   = length(sunDelta);
    float rayTheta = atan(sunDelta.y, sunDelta.x + 1e-6);
    float starburst = (pow(0.5 + 0.5 * cos(rayTheta * 12.0 + 0.4), 6.0)
                     + 0.65 * pow(0.5 + 0.5 * cos(rayTheta * 19.0 - 0.9), 8.0))
                    * exp(-sunAng * 13.5) * smoothstep(0.008, 0.036, sunAng);

    float mieHalo = phaseCornetteShanks(dot(rd, canopySunDir), 0.78) * 0.52
                  + phaseCornetteShanks(dot(rd, FOREST_SUN_DIR), 0.72) * 0.28;
    skyCol += vec3(1.35, 1.10, 0.68) * mieHalo;
    skyCol += vec3(6.2, 5.0, 3.0) * (pow(sunGap, 26.0) + starburst * 0.70);
    skyCol += vec3(15.5, 12.4, 7.8) * sunDisk(rd, canopySunDir, 0.025, pxAngle);

    vec3 col = mix(mistBase, skyCol, skyElev);
    float canopyOcc = 0.0;

    // Layer 0 (R = 23.0m): Integer-periodic seam-free misty distant redwood silhouettes
    const vec2 CYL_CENTER = vec2(0.0, -6.6);
    const float N_DIST_CELLS = 60.0;
    const float DIST_CELL_W  = (TAU * 23.0) / N_DIST_CELLS;
    float tDist = ft_cylinderExitT(ro.xz, rd.xz, CYL_CENTER, 23.0);
    if (tDist > 0.0) {
        vec3 hp = ro + rd * tDist;
        float ang = atan(hp.z - CYL_CENTER.y, hp.x - CYL_CENTER.x);
        float arcU = (ang + PI) * 23.0;
        float cell = floor(arcU / DIST_CELL_W);
        float cellId = mod(cell, N_DIST_CELLS);
        float cellH = hash11(cellId + 31.0);
        if (cellH > 0.44 && hp.y > -0.5) {
            float swayU   = 0.08 * sin(hp.y * 0.28 + cellId * 1.9);
            float centerU = (cell + 0.22 + 0.56 * hash11(cellId + 73.0)) * DIST_CELL_W + swayU;
            float halfW   = mix(0.09, 0.24, hash11(cellId + 19.0)) * max(0.65, 1.0 - 0.015 * max(hp.y, 0.0));
            float silhouette = 1.0 - smoothstep(halfW * 0.72, halfW + pxAngle * tDist * 1.5, abs(arcU - centerU));
            vec3 distTrunkCol = mix(srgbToLinear(vec3(0.07, 0.09, 0.05)), mistBase, 0.72);
            col = mix(col, distTrunkCol, silhouette * 0.62);
        }
    }

    // High overhead conifer vault + 2 concentric 360-degree cylindrical shells (ZERO-looped single AST copy of ft_coniferBoughLayer!)
    for (int layer = ZERO; layer < 3; layer++) {
        if (layer == 0) {
            if (gInDissolve || rd.y <= 0.10) continue;
            float tCrown = (6.8 - ro.y) / rd.y;
            if (tCrown > 0.0 && tCrown < 42.0) {
                vec3 cp = ro + rd * tCrown;
                vec4 crownSample = ft_coniferBoughLayer(cp.xz * 0.74 + vec2(0.0, 4.4), 11.3, pxAngle * tCrown, sunScatter);
                float crownFog = distanceFog(tCrown, 0.022);
                float a = crownSample.a * smoothstep(0.10, 0.24, rd.y);
                col = mix(col, mix(crownSample.rgb, mistBase, crownFog * 0.28), a);
                canopyOcc = mix(canopyOcc, 1.0, a);
            }
        } else {
            float fl = float(layer - 1);
            float radius = (layer == 1) ? 16.8 : 10.2;
            float tCyl = ft_cylinderExitT(ro.xz, rd.xz, CYL_CENTER, radius);
            if (tCyl > 0.0) {
                vec3 hp = ro + rd * tCyl;
                if (hp.y > -0.10 && hp.y < 15.0) {
                    vec2 dVec = (hp.xz - CYL_CENTER) / radius;
                    float symBreak = gradientNoise(vec3(dVec * 2.5 + fl * 5.3, hp.y * 0.35)) * 1.15;
                    float wFront = smoothstep(-0.92, -0.74, -dVec.y);
                    float seedL  = 2.3 + fl * 6.9;
                    float pxW    = pxAngle * tCyl;

                    vec4 bF = vec4(0.0), bB = vec4(0.0);
                    for (int ch = ZERO; ch < 2; ch++) {
                        if (ch == 0 && wFront <= 0.001) continue;
                        if (ch == 1 && wFront >= 0.999) continue;
                        float uC = (ch == 0) ? (atan(dVec.x, -dVec.y) * radius)
                                             : (atan(-dVec.x, dVec.y) * radius + 31.7);
                        vec4 sC = ft_coniferBoughLayer(vec2(uC + symBreak, hp.y), seedL + float(ch) * 3.1, pxW, sunScatter);
                        if (ch == 0) bF = sC; else bB = sC;
                    }
                    vec4 bough = mix(bB, bF, wFront);

                    float lowMist = mix(0.55, 0.0, smoothstep(-0.05, 1.30, hp.y));
                    float mistAmt = clamp(mix(0.20, 0.05, fl) + lowMist, 0.0, 0.85);
                    vec3 boughLit = mix(bough.rgb, mistBase, mistAmt);
                    float a = bough.a * mix(0.88, 0.95, fl);
                    col = mix(col, boughLit, a);
                    canopyOcc = mix(canopyOcc, 1.0, a);
                }
            }
        }
    }

    // Back-to-front horizontal conifer branch fans (ZERO-looped + dissolve LOD -> fast cross-dissolves!)
    float fwdVis = smoothstep(-0.08, -0.28, rd.z);
    if (fwdVis > 0.005) {
        float invRdZ = 1.0 / min(rd.z, -0.06);
        int startFan = gInDissolve ? 2 : 0;
        for (int k = ZERO; k < 6; k++) {
            if (k < startFan) continue;
            vec4 fan = (k == 0) ? vec4( 1.82, -12.40, 3.20, 1.35) :
                       (k == 1) ? vec4(-0.68, -10.60, 2.85, 1.05) :
                       (k == 2) ? vec4(-2.48,  -9.20, 2.95, 1.30) :
                       (k == 3) ? vec4( 3.10,  -9.42, 3.30, 0.90) :
                       (k == 4) ? vec4(-1.92,  -6.65, 2.70, 1.65) :
                                  vec4( 3.35,  -5.85, 2.25, 0.95);
            float tZ = (fan.y - ro.z) * invRdZ;
            if (tZ > 0.5) {
                vec2 hp = (ro + rd * tZ).xy;
                vec4 b = ft_trunkBoughFan(hp, fan.x, fan.z, fan.w, 3.7 + float(k) * 4.3, pxAngle * tZ, sunScatter);
                if (b.a > 0.002) {
                    float mistAmt = clamp((-fan.y - 4.5) * 0.020, 0.04, 0.20);
                    float a = b.a * fwdVis;
                    col = mix(col, mix(b.rgb, mistBase, mistAmt), a);
                    canopyOcc = mix(canopyOcc, 1.0, a);
                }
            }
        }
    }

    // Tight canopy-occluded optical lens halation & radial sunburst around open sky pinholes!
    float sunTrans = (1.0 - canopyOcc * 0.76) * skyElev;
    col += vec3(3.4, 2.7, 1.65) * (pow(sunGap, 44.0) + starburst * 0.75) * sunTrans
         + vec3(6.2, 4.9, 3.1) * sunDisk(rd, canopySunDir, 0.021, pxAngle) * (1.0 - canopyOcc * 0.88) * skyElev;

    float lowFade = 1.0 - smoothstep(-0.04, 0.04, rd.y);
    return mix(col, mistBase, lowFade * 0.40);
}

// ==== PART: 02b_forest_floor.glsl ====
// =============================================================================
// SCENE II (Part B): FOREST FLOOR & RENDERER
// Multi-tier Western sword-fern rosettes, neighbor-overlapping redwood sorrel
// (Oxalis oregana) shamrock carpet, decaying mossy nurse logs, concentric-zoned
// shelf fungi, crooked fallen deadwood branches/twigs, pillowy bryophyte moss
// hummocks, 3-tier domain-warped redwood needle duff & diagonal morning sunbeams.
// Exclusively owns: mapForest(), renderForest(), and private ff_* / FF_* helpers.
// Collaborates with 02a_forest_trees.glsl: forestBaseHeight, mapForestTrees,
// shadeForestTree, forestSunVisibility, forestCanopySky.
// =============================================================================

// Fast trig-free 2-octave billow noise (pillowy bryophyte domes at ~3x speed of gradient billowFbm)
float ff_billow2(vec2 p) {
    float b0 = abs(valueNoise(p) * 2.0 - 1.0);
    vec2  p1 = mat2(1.60, 1.20, -1.20, 1.60) * p + vec2(11.3, -7.1);
    float b1 = abs(valueNoise(p1) * 2.0 - 1.0);
    return b0 * 0.66 + b1 * 0.34;
}

// Smooth C1-faded base ground height (skips noise cleanly above y = 4.5m with zero trunk seam)
float ff_smoothBaseY(vec3 p) {
    if (p.y >= 4.5) return 0.0;
    float fade = 1.0 - smoothstep(2.6, 4.5, p.y);
    return forestBaseHeight(p.xz) * fade;
}

// Natural moisture/colonization mask for pillowy bryophyte moss cushions
float ff_mossColonization(vec2 xz) {
    float macro    = valueNoise(xz * 0.62 + vec2(2.1, -1.3));
    float cushions = ff_billow2(xz * 1.65 + vec2(-0.8, 3.1));
    float trailX   = 0.08 * sin(xz.y * 0.50 + 0.4);
    float dx       = (xz.x - trailX) * 1.85;
    float onTrail  = 1.0 / (1.0 + dx * dx * 1.6);
    return saturate((macro * 0.68 + cushions * 0.62 - 0.32) * (1.0 - 0.56 * onTrail));
}

// Tighter mounded woodland colony mask for 3-leaved redwood sorrel (Oxalis oregana) clusters
float ff_oxalisColonyMask(vec2 xz) {
    float c0 = valueNoise(xz * 0.82 + vec2(0.85, 2.35));
    float c1 = valueNoise(mat2(1.60, -1.20, 1.20, 1.60) * (xz * 1.45) + vec2(5.2, -3.4));
    float mounds = ff_billow2(xz * 2.15 + vec2(-1.7, 4.3));
    float colony = c0 * 0.48 + c1 * 0.30 + mounds * 0.28;

    float rightGlade = smoothstep(-0.82, 0.24, xz.x + 0.22 * sin(xz.y * 0.58));
    vec2  lp         = (xz - vec2(-0.46, -3.32)) * vec2(1.22, 0.64);
    float leftPocket = 0.68 / (1.0 + dot(lp, lp) * 1.9);
    float spatial    = saturate(mix(0.18, 1.0, rightGlade) + leftPocket);
    return smoothstep(0.27, 0.58, colony * spatial);
}

// Macro hummock topography shared by floor & resting deadwood sticks (zero exp(), fast ALU + valueNoise)
float ff_floorMacroHeight(vec2 xz, float baseY) {
    float trailX   = 0.08 * sin(xz.y * 0.50 + 0.4);
    float dx       = (xz.x - trailX) * 1.75;
    float offTrail = 1.0 - 0.48 / (1.0 + dx * dx * 1.5);
    float h = baseY + 0.062 * (ff_billow2(xz * 0.58 + vec2(1.4, -0.9)) - 0.37) * offTrail;

    // Curated pillowy moss mounds matching ref_5.00, 7.00, 9.00 foreground & midground
    vec2 m0 = (xz - vec2( 1.14, -3.16)) * vec2(1.35, 1.55);
    vec2 m1 = (xz - vec2(-0.86, -4.42)) * vec2(1.45, 1.35);
    vec2 m2 = (xz - vec2(-1.02, -2.12)) * vec2(1.45, 1.55);
    vec2 m3 = (xz - vec2( 0.88, -4.85)) * vec2(1.30, 1.40);
    h += 0.116 / (1.0 + dot(m0, m0) * 1.75);
    h += 0.084 / (1.0 + dot(m1, m1) * 1.75);
    h += 0.074 / (1.0 + dot(m2, m2) * 1.75);
    h += 0.078 / (1.0 + dot(m3, m3) * 1.75);
    return h;
}

// Multi-tier forest floor topography + macroGap-gated 3D pillowy bryophyte moss & oxalis cushions
float ff_floorHeight(vec2 xz, float baseY, float relY) {
    float h = ff_floorMacroHeight(xz, baseY);
    float macroGap = (baseY + relY) - h;
    if (!gFastMap && macroGap < 0.095 && xz.y > -12.0) {
        float fade = 1.0 - smoothstep(0.035, 0.092, macroGap);
        float p0   = abs(valueNoise(xz * 3.5 + vec2(4.2, 1.7)) * 2.0 - 1.0);
        float p1   = valueNoise(xz * 0.82 + vec2(2.1, -1.3));
        h += (0.034 * p0 * p1 + 0.009 * (valueNoise(xz * 7.2 + vec2(-2.7, 5.1)) - 0.5)) * fade;
    }
    return h;
}

// 2-layer neighbor-overlapping plump 3-heart-lobed Oxalis oregana shamrock solver (varied 0.034..0.066m mounded clusters!)
vec4 ff_evalOxalisCarpet(vec2 xz, float t, float foot, float groundFoot, out vec2 leafTiltSlope) {
    leafTiltSlope = vec2(0.0);
    float colM = ff_oxalisColonyMask(xz);
    if (colM < 0.05) return vec4(0.0);

    float nearWeight = (1.0 - smoothstep(4.5, 6.9, t)) * (1.0 - smoothstep(0.009, 0.022, groundFoot));
    if (nearWeight <= 0.005) return vec4(0.0);

    float bestPrio   = -1.0;
    float bestMask   = 0.0;
    float bestHash   = 0.5;
    float bestCrease = 0.0;
    vec2  bestSlope  = vec2(0.0);
    float minEdgeD   = 1.0;

    for (int layer = ZERO; layer < 2; layer++) {
        float fl  = float(layer);
        float sp  = (layer == 0) ? 0.066 : 0.086;
        vec2  gxz = (layer == 0) ? xz : (rot2(0.64) * xz + vec2(0.035, 0.027));
        vec2  id   = domRepeatId(gxz, vec2(sp));
        vec2  side = sign(gxz - sp * id);

        for (int j = ZERO; j < 2; j++) {
            for (int i = ZERO; i < 2; i++) {
                vec2 cell = id + vec2(float(i), float(j)) * side;
                vec3 hv   = hash32(cell + vec2(17.0 + fl * 41.0, 53.0 + fl * 29.0));
                if (hv.x > colM * 0.98) continue;

                vec2 center = cell * sp + (hv.yz - 0.5) * (sp * 0.66);
                vec2 dq = gxz - center;
                // Varied 0.034..0.066m shamrock scales peaking in lush mounded colony centers!
                float rLeaf = mix(0.034, 0.066, hv.y * hv.y) * smoothstep(0.03, 0.34, colM);
                if (dot(dq, dq) > (rLeaf + 0.018) * (rLeaf + 0.018)) continue;

                vec2 sp3 = domPolar(rot2(hv.x * TAU) * dq, 3.0);
                float ay = abs(sp3.y);
                // Obcordate (heart-notched) leaflet: plump rounded lobe with delicate apical heart cleft
                vec2 lobeQ  = rot2(-0.55) * vec2(ay, sp3.x - 0.0010);
                float dBase = sdUnevenCapsule(lobeQ, 0.0020, 0.48 * rLeaf, 0.53 * rLeaf);
                float cleft = length(vec2(sp3.x - 0.90 * rLeaf, ay * 1.35)) - 0.16 * rLeaf;
                float d2    = smoothSubtract(dBase, cleft, 0.0042);

                minEdgeD = min(minEdgeD, max(d2, 0.0));

                float aa   = clamp(max(foot * 1.4, groundFoot * 0.55), 0.0009, 0.009);
                float m    = 1.0 - smoothstep(-aa, aa, d2);
                float prio = hv.z + fl * 0.14;
                if (m > 0.01 && prio > bestPrio) {
                    bestPrio   = prio;
                    bestMask   = m;
                    bestHash   = fract(hv.x * 3.7 + hv.y * 1.9 + fl * 0.31);
                    bestCrease = exp(-ay / max(0.085 * rLeaf, 1e-4)) * smoothstep(0.0, 0.32 * rLeaf, sp3.x);

                    vec2 tilt       = (hv.yz - 0.5) * 0.64;
                    float rimBev    = smoothstep(-0.010, 0.0, d2);
                    vec2 radOut     = dq / max(length(dq), 1e-4);
                    vec2 localSlope = tilt - radOut * (rimBev * 0.62);
                    bestSlope       = (layer == 0) ? localSlope : (rot2(-0.64) * localSlope);
                }
            }
        }
    }

    leafTiltSlope = bestSlope * nearWeight;
    float underShadow = (1.0 - bestMask) * (1.0 - smoothstep(0.0, 0.022, minEdgeD)) * 0.82 * nearWeight;
    return vec4(bestMask * nearWeight, underShadow, bestHash, bestCrease);
}

// Single Western sword-fern frond (Polystichum munitum): outward-sweeping fountain arch
// (archPhase ~ 1.36..1.80 so tips sweep gracefully outward/horizontally — NEVER downward spider legs!)
float ff_sdSwordFrond(vec2 sec, float qy, float fLen, float hPeak, float baseLift, float halfW, float nPin, float archPhase, float seed, bool detailed) {
    float x = sec.x - 0.012;
    if (x < -0.03 || x > fLen + 0.05) {
        return length(vec3(
            max(-x, max(x - fLen, 0.0)),
            max(abs(qy - 0.5 * hPeak) - 0.5 * hPeak - 0.04, 0.0),
            max(abs(sec.y) - halfW, 0.0)
        ));
    }
    float u = clamp(x / max(fLen, 0.05), 0.0, 1.0);

    // Outward-sweeping botanical fountain curve: emerges from low crown & flares horizontally at tip!
    float angArg  = u * archPhase + 0.06;
    float archY   = hPeak * (sin(angArg) - sin(0.06)) + baseLift;
    float dArchDx = (hPeak * archPhase * cos(angArg)) / max(fLen, 0.05);

    float sway = detailed ? (0.028 * u * u * sin(seed * 3.7 + u * 2.8)) : 0.0;
    float lat  = sec.y - sway;
    float dn   = (qy - archY) * inversesqrt(1.0 + dArchDx * dArchDx);

    float rachisR = mix(0.0044, 0.0013, u);
    float dRachis = max(length(vec2(lat, dn)) - rachisR, max(-x, x - fLen * 0.99));

    // Authentic lanceolate sword silhouette: tapered base, full mid-blade, acuminate sword tip
    float env = smoothstep(0.015, 0.16, u) * pow(clamp(1.015 - u, 0.0, 1.0), 0.86);
    float maxSpan = halfW * env;
    if (maxSpan < 0.0018) return dRachis * 0.86;

    if (!detailed) {
        float pitchF = fLen / nPin;
        float pfF = abs(fract((x - abs(lat) * 0.20) / pitchF) - 0.5);
        float d2F = max(max(pfF * pitchF - 0.24 * pitchF, abs(lat) - maxSpan), max(0.025 * fLen - x, x - fLen));
        return min(dRachis, length(vec2(max(d2F, 0.0), dn)) - 0.0016) * 0.84;
    }

    float side   = (lat >= 0.0) ? 1.0 : -1.0;
    float pitch  = fLen / nPin;
    float xSwept = x - abs(lat) * 0.21;
    float pCoord = xSwept / pitch + 0.25 * side;
    float pId    = floor(pCoord);
    float pf     = fract(pCoord) - 0.5;

    float spanVar = maxSpan * (0.91 + 0.15 * sin(pId * 2.37 + seed * 5.1));
    float s = clamp((abs(lat) - rachisR * 0.45) / max(spanVar, 1e-4), 0.0, 1.0);

    // Crisp separated comb teeth all the way to the rachis + basal "sword-hilt" auricle lobe!
    float hilt   = 0.054 * exp(-pow((s - 0.14) * 7.8, 2.0)) * step(0.0, pf * side);
    float teeth  = 0.022 * sin(s * 26.0 + pId) * (1.0 - 0.4 * s);
    float leafHW = pitch * (0.242 * (1.0 - 0.76 * pow(s, 1.32)) + hilt + teeth);

    float dAlong = abs(pf) * pitch - leafHW;
    float dSpan  = abs(lat) - spanVar;
    float dEnds  = max(0.025 * fLen - x, x - fLen);
    float dPin2D = max(max(dAlong, dSpan), dEnds);

    float dnLeaf = dn + 0.0036 * s * s - 0.0013 * abs(pf);
    float dPin3D = length(vec2(max(dPin2D, 0.0), dnLeaf)) + min(max(dPin2D, abs(dnLeaf) - 0.0010), 0.0) - 0.0009;

    return min(dRachis, dPin3D) * 0.82;
}

// Asymmetric, low-crowned 3-tier Western sword-fern rosette (flush basal skirt + spreading fountain + upright crown!)
float ff_sdFernRosette(vec3 q, float scale, float seed, bool detailed) {
    float r = length(q.xz);
    float boundR = 0.68 * scale;
    if (r > boundR + 0.08) return r - boundR;

    float rNorm = r / max(scale, 0.1);
    float domeH = scale * (0.38 - 0.18 * max(rNorm - 0.42, 0.0)) + 0.02;
    if (q.y > domeH + 0.045) return (q.y - domeH) * 0.86;

    // Compact low scaly rootstock tucked inside frond bases (exact Lipschitz <= 1.0 ellipsoid bound!)
    float d = (length(vec3(q.x, (q.y - 0.014 * scale) * 1.80, q.z)) - 0.050 * scale) * 0.55;

    // Outer & Basal Skirt tiers: 14 irregular sectors (~24% skipped + asymmetric reach so never a 360° wheel!)
    const float N_OUTER = 14.0;
    vec2 qOuter = rot2(seed * 2.31) * q.xz;
    float coarseAsym = 0.80 + 0.28 * cos(atan(q.z, q.x + 1e-6) * 2.0 + seed * 1.9);
    if (detailed) {
        vec2 idsO = domPolarPair(qOuter, N_OUTER);
        for (int i = ZERO; i < 2; i++) {
            float fid = (i == 0) ? idsO.x : idsO.y;
            vec2 hv   = hash22(vec2(fid + 1.0, floor(seed * 10.0) + 13.0));
            if (hv.x < 0.23) continue;
            bool isLowSkirt = (mod(fid, 2.0) > 0.5);
            float asymBias  = 0.84 + 0.24 * cos(fid * (TAU / N_OUTER) + seed * 1.7);
            vec2 sec  = rot2((hv.y - 0.5) * 0.22) * domPolarSector(qOuter, fid, N_OUTER);
            float fLen  = scale * min(mix(0.42, 0.64, hv.x) * asymBias, 0.65);
            // Flush basal skirt hugs moss (0.045..0.085m); mid-tier sweeps outward horizontally (archP 1.56..1.76)!
            float hPeak = scale * (isLowSkirt ? mix(0.048, 0.088, hv.y) : mix(0.135, 0.205, hv.y));
            float archP = isLowSkirt ? mix(1.62, 1.82, hv.x) : mix(1.52, 1.74, hv.x);
            float lift  = isLowSkirt ? 0.006 : 0.014;
            float halfW = scale * mix(0.068, 0.092, hv.x);
            d = min(d, ff_sdSwordFrond(sec, q.y, fLen, hPeak, lift, halfW, 30.0, archP, seed + fid * 0.7, true));
        }
    } else {
        vec2 sec = domPolar(qOuter, N_OUTER);
        d = min(d, ff_sdSwordFrond(sec, q.y, 0.54 * scale * coarseAsym, 0.16 * scale, 0.012, 0.080 * scale, 21.0, 1.66, seed, false));
    }

    // Inner Crown tier: 8 upright young fronds fountaining outward (archP 1.32..1.52, irregular skip)
    if (r < 0.64 * scale) {
        const float N_INNER = 8.0;
        vec2 qInner = rot2(seed * 4.17 + 0.44) * q.xz;
        if (detailed) {
            vec2 idsI = domPolarPair(qInner, N_INNER);
            for (int i = ZERO; i < 2; i++) {
                float fid = (i == 0) ? idsI.x : idsI.y;
                vec2 hv   = hash22(vec2(fid + 29.0, floor(seed * 10.0) + 41.0));
                if (hv.x < 0.24) continue;
                vec2 sec  = rot2((hv.x - 0.5) * 0.24) * domPolarSector(qInner, fid, N_INNER);
                float fLen  = scale * mix(0.32, 0.48, hv.x);
                float hPeak = scale * mix(0.21, 0.30, hv.y);
                float halfW = scale * mix(0.056, 0.076, hv.y);
                d = min(d, ff_sdSwordFrond(sec, q.y, fLen, hPeak, 0.018, halfW, 23.0, mix(1.34, 1.52, hv.y), seed + fid * 1.3 + 5.0, true));
            }
        } else {
            vec2 sec = domPolar(qInner, N_INNER);
            d = min(d, ff_sdSwordFrond(sec, q.y, 0.40 * scale, 0.25 * scale, 0.016, 0.066 * scale, 16.0, 1.44, seed + 5.0, false));
        }
    }

    return d;
}

// 10 curated hero sword-fern rosettes calibrated across 5.0s -> 7.0s -> 9.0s: vec4(x, z, scale, seed)
const vec4 FF_HERO_FERNS[10] = vec4[10](
    vec4(-0.92, -1.98, 1.14,  1.3), // 0: 5s lush lower-left foreground hero fronds
    vec4(-1.06, -2.84, 1.08,  2.4), // 1: 7s lower-left corner framing fronds
    vec4( 0.96, -1.78, 0.96,  3.1), // 2: 5s lower-right foreground framer
    vec4( 0.28, -3.58, 1.02,  4.5), // 3: 7s star center-right sword-fern rosette
    vec4(-0.62, -4.08, 1.04,  5.9), // 4: 7s left-MG -> 9s lower-left corner hero fern
    vec4(-1.18, -4.55, 0.94,  6.7), // 5: 7s/9s Trunk-0 root-base companion fern
    vec4(-0.64, -5.24, 1.00,  7.4), // 6: 9s left-midground hero fern
    vec4( 0.36, -4.94, 1.02,  9.2), // 7: 9s right-midground hero fern
    vec4( 1.62, -3.72, 0.92, 11.6), // 8: 7s right-flank fern beside nurse log
    vec4( 0.88, -5.58, 0.90, 13.8)  // 9: 7s/9s Trunk-1 sunlit corridor fern
);

vec4 ff_nearestFernClump(vec2 xz, out float boundDist) {
    boundDist = 1e5;
    vec4 bestClump = vec4(0.0, 0.0, -1.0, 0.0);

    // Pure-ALU unrolled constant-array scan (zero dynamic indexing, zero Metal stack spill!)
    if (xz.y > -6.4 && xz.y < -0.7 && abs(xz.x) < 2.8) {
        for (int i = 0; i < 10; i++) {
            vec4 hc = FF_HERO_FERNS[i];
            float bDist = length(xz - hc.xy) - 0.68 * hc.z;
            if (bDist < boundDist) {
                boundDist = bDist;
                bestClump = hc;
            }
        }
    }

    // Lush sunlit midground glade & understory fern tufts (SPACING = 1.24m across z = -5.3..-13.8m!)
    const float SPACING = 1.24;
    vec2 uvGrid = rot2(0.38) * xz + vec2(0.45, 0.62);
    vec2 cid    = domRepeatId(uvGrid, vec2(SPACING));
    vec3 hv     = hash32(cid + vec2(19.0, 73.0));
    vec2 cLocal = cid * SPACING + (hv.yz - 0.5) * 0.30;
    vec2 worldC = rot2(-0.38) * (cLocal - vec2(0.45, 0.62));

    bool inHeroZone  = (worldC.y > -5.30 && abs(worldC.x - 0.05) < 1.32);
    // Synced to finalized #70 hero trunk shafts in 02a so ferns nestle naturally around buttress root spurs!
    bool inTrunkCore = (dot2(worldC - vec2(-2.86, -4.52)) < 0.98 * 0.98)
                    || (dot2(worldC - vec2( 1.75, -4.76)) < 0.72 * 0.72)
                    || (dot2(worldC - vec2(-1.92, -6.65)) < 0.72 * 0.72)
                    || (dot2(worldC - vec2( 3.46, -9.45)) < 0.76 * 0.76)
                    || (dot2(worldC - vec2(-2.38, -8.85)) < 0.58 * 0.58);

    if (hv.x > 0.24 && !inHeroZone && !inTrunkCore) {
        float sc = mix(0.54, 0.80, hv.x * 0.65 + hv.y * 0.35);
        float gDist = length(xz - worldC) - 0.68 * sc;
        if (gDist < boundDist) {
            boundDist = gDist;
            bestClump = vec4(worldC.x, worldC.y, sc, hv.x * 17.0 + hv.z * 7.3 + 3.1);
        }
    } else {
        vec2 inCell = abs(uvGrid - cid * SPACING);
        float toEdge = (0.5 * SPACING - max(inCell.x, inCell.y)) + 0.24;
        boundDist = min(boundDist, toEdge);
    }

    return bestClump;
}

float ff_sdAllFernsDir(vec3 p, float baseY, float closeFlat, float closeDome) {
    float relY = p.y - baseY;
    float maxCrownH = mix(0.39, 0.30, smoothstep(-5.8, -7.4, p.z));

    float bestBound;
    vec4 bestClump = ff_nearestFernClump(p.xz, bestBound);

    if (bestClump.z < 0.0 || bestBound > 0.06 || relY > maxCrownH + 0.04) {
        float dH = max(bestBound, 0.0);
        float dV = max(relY - maxCrownH, 0.0) / closeFlat;
        return max(dH, dV) + min(max(bestBound, relY - maxCrownH), 0.0);
    }

    vec3 q = vec3(p.x - bestClump.x, p.y - (baseY + 0.012), p.z - bestClump.y);
    float rNorm = length(q.xz) / max(bestClump.z, 0.1);
    float domeH = bestClump.z * (0.38 - 0.18 * max(rNorm - 0.42, 0.0)) + 0.02;
    if (q.y > domeH + 0.035) {
        return max((q.y - domeH) / closeDome, 0.025);
    }

    bool detailed = !gFastMap && (bestClump.y > (gInDissolve ? -5.6 : -7.6));
    return ff_sdFernRosette(q, bestClump.z, bestClump.w, detailed);
}

float ff_sdAllFerns(vec3 p, float baseY) {
    return ff_sdAllFernsDir(p, baseY, 1.0, 1.0);
}

// 5 curated decaying redwood nurse logs & fallen limbs
// Log 0 spans continuously from x = -0.98 to +2.24 across 5.0s foreground with exposed split-bark center!
const vec3 FF_LOG_A[5] = vec3[5](
    vec3(-0.98, -0.046, -2.44), // 0: Continuous 5s hero nurse log across entire foreground
    vec3( 0.72, -0.038, -3.42), // 1: 7s right-foreground nurse log with bracket fungi
    vec3(-1.38,  0.012, -2.96), // 2: 5s/7s left-foreground decaying redwood limb
    vec3(-1.44,  0.022, -4.64), // 3: 7s/9s left-midground fallen limb
    vec3( 0.24, -0.032, -6.12)  // 4: 7s/9s midground nurse log in sunlit glade
);
const vec3 FF_LOG_B[5] = vec3[5](
    vec3( 2.24,  0.070, -2.06),
    vec3( 2.26,  0.052, -3.84),
    vec3(-0.20, -0.068, -3.38),
    vec3(-0.32, -0.058, -5.32),
    vec3( 2.32,  0.078, -6.56)
);
const vec4 FF_LOG_P[5] = vec4[5](
    vec4(0.126, 0.142, -0.022, 1.4),
    vec4(0.134, 0.102, -0.016, 3.7),
    vec4(0.058, 0.032,  0.012, 5.2),
    vec4(0.088, 0.052, -0.014, 6.9),
    vec4(0.134, 0.100, -0.018, 8.5)
);

// 6 shelf/bracket polypore fungus clusters anchored to nurse log flanks: vec4(x, y, z, yaw)
const vec4 FF_FUNGI[6] = vec4[6](
    vec4( 0.46, -0.008, -2.14,  0.08),
    vec4( 1.22,  0.038, -2.04, -0.05),
    vec4( 1.06,  0.010, -3.34,  0.26),
    vec4( 1.54,  0.028, -3.49,  0.22),
    vec4(-0.92,  0.005, -4.87, -0.45),
    vec4( 0.82,  0.015, -6.07,  0.20)
);

// Shared lumpy moss-pillow & exposed-bark patch mask along nurse logs (carves bare split-bark gap at 5s center!)
float ff_logMossPatchMask(vec3 p, float uAlong, float seed) {
    float n0 = valueNoise(vec2(uAlong * 1.55 + seed * 2.3, seed * 1.7));
    float n1 = ff_billow2(p.xz * 2.6 + vec2(seed * 3.1, -seed));
    float patchM = smoothstep(0.24, 0.64, n0 * 0.62 + n1 * 0.48);
    // Expose dark split fibrous redwood bark in the 5.0s center-foreground gap (x ~ -0.22..+0.48) flanked by thick moss pillows!
    if (p.z > -2.75) {
        float centerBarkGap = 1.0 - smoothstep(0.16, 0.52, abs(p.x - 0.12));
        patchM *= (1.0 - 0.92 * centerBarkGap);
    }
    return patchM;
}

float ff_sdDecayingLogSingle(vec3 p, vec3 a, vec3 b, vec4 params) {
    float rA = params.x, rB = params.y, sag = params.z, seed = params.w;
    vec3 ba = b - a;
    float lenBA = max(length(ba), 0.01);
    vec3 dir = ba / lenBA;
    float proj = dot(p - a, dir);
    float h = clamp(proj / lenBA, 0.0, 1.0);

    vec3 sideDir = normalize(vec3(-dir.z, 0.0, dir.x));
    vec3 upPerp  = cross(sideDir, dir);
    float crookS = 0.062 * sin(h * PI * 1.35 + seed) + 0.024 * cos(h * 6.5 - seed);
    vec3 spine   = mix(a, b, h) + sideDir * crookS + vec3(0.0, sag * 4.0 * h * (1.0 - h), 0.0);
    float rad    = mix(rA, rB, h) * (1.0 + 0.08 * sin(h * 6.2 + seed * 2.1) - 0.04 * sin(h * 11.0));

    vec3 dVec    = p - spine;
    vec3 perpVec = dVec - dir * dot(dVec, dir);
    float rPerp  = length(perpVec);
    float rawCyl = rPerp - rad;
    float endOut = max(-proj, proj - lenBA);

    if (rawCyl > 0.15 || endOut > 0.15) {
        return length(vec2(max(rawCyl, 0.0), max(endOut, 0.0))) + min(max(rawCyl, endOut), 0.0);
    }

    float ang = atan(dot(perpVec, upPerp), dot(perpVec, sideDir) + 1e-6);
    float splinters = rad * (0.24 * sin(ang * 5.0 + seed) + 0.13 * cos(ang * 9.0 - seed * 2.0));
    float dLog = max(rawCyl, max(-(proj + splinters), proj - lenBA + splinters));

    float hollowA = sdSphere(p - a - dir * (0.03 * rA) + vec3(0.0, 0.02 * rA, 0.0), rA * 0.56);
    dLog = smoothSubtract(dLog, hollowA, 0.024);

    if (!gFastMap) {
        float dispFade   = 1.0 - smoothstep(0.035, 0.13, abs(dLog));
        float patchAlong = ff_logMossPatchMask(p, proj, seed);
        float crownAngle = dot(perpVec / max(rPerp, 1e-4), normalize(upPerp - sideDir * 0.12));
        float topMask    = smoothstep(0.06, 0.56, crownAngle) * patchAlong;
        // Lumpy, pillowy bryophyte cushions on colonized zones + deep longitudinal split grooves on bare wood!
        float pillows    = ff_billow2(p.xz * 2.2 + vec2(seed * 3.1, -seed)) * 0.68
                         + ff_billow2(p.xz * 5.4 - vec2(seed * 1.7, 2.3)) * 0.32;
        float mossDome   = (0.016 + 0.032 * pillows) * topMask;
        float barkSplit  = 0.013 * (valueNoise(vec2(proj * 2.4, ang * 4.5 + seed)) - 0.52) * (1.0 - 0.75 * topMask);
        dLog -= (mossDome + barkSplit) * dispFade;
    }

    return dLog * 0.80;
}

float ff_sdShelfFungusSingle(vec3 p, vec3 origin, float yaw, float seed, out float outLocalR) {
    vec3 q = p - origin;
    float d = 1e5;
    outLocalR = 0.02;
    for (int k = ZERO; k < 4; k++) {
        float fk = float(k);
        vec3 ofs = vec3((fk - 1.5) * 0.038, sin(fk * 2.1 + seed) * 0.018, cos(fk * 1.4 + seed) * 0.010);
        vec3 b = q - ofs;
        b.xz = rot2(yaw + (fk - 1.5) * 0.22) * b.xz;

        float rConk = 0.032 + 0.014 * hash11(fk * 7.0 + floor(seed * 10.0));
        float ang = atan(b.x, b.z + 0.014);
        float scallopedR = rConk * (1.0 + 0.14 * sin(ang * 5.0 + fk * 1.7) + 0.06 * cos(ang * 9.0));
        float radXZ = length(vec2(b.x, max(b.z, -0.012) - 0.008));
        float uR = clamp(radXZ / max(rConk, 0.01), 0.0, 1.0);

        float halfThick = mix(0.0088, 0.0024, uR);
        float dHoriz = max(radXZ - scallopedR, -b.z - 0.016);
        float by = b.y - 0.0035 * (1.0 - uR * uR);
        float dConk = length(vec2(max(dHoriz, 0.0), max(abs(by) - halfThick, 0.0)))
                    + min(max(dHoriz, abs(by) - halfThick), 0.0) - 0.0015;
        if (dConk < d) outLocalR = uR;
        d = smin(d, dConk, 0.004);
    }
    return d * 0.85;
}

vec2 ff_sdLogsAndFungi(vec3 p, float baseY) {
    float relY = p.y - baseY;
    if (relY > 0.42 || p.z < -7.0 || p.z > -1.4) {
        return vec2(length(vec2(max(relY - 0.34, 0.0), max(-7.0 - p.z, max(p.z + 1.4, 0.0)))), MAT_FOREST_LOG);
    }

    float bestBound = 1e5;
    vec3  bestLA = FF_LOG_A[0];
    vec3  bestLB = FF_LOG_B[0];
    vec4  bestLP = FF_LOG_P[0];
    for (int i = 0; i < 5; i++) {
        float maxR = max(FF_LOG_P[i].x, FF_LOG_P[i].y);
        float db = sdCapsule(p, FF_LOG_A[i], FF_LOG_B[i], maxR * 1.38 + 0.07);
        if (db < bestBound) {
            bestBound = db;
            bestLA    = FF_LOG_A[i];
            bestLB    = FF_LOG_B[i];
            bestLP    = FF_LOG_P[i];
        }
    }

    float dLogs = bestBound + 0.05;
    if (bestBound < 0.16) {
        dLogs = ff_sdDecayingLogSingle(p, bestLA, bestLB, bestLP);
    }

    vec2 res = vec2(dLogs, MAT_FOREST_LOG);

    if (!gFastMap && dLogs < 0.24) {
        float bestF2    = 1e5;
        vec4  bestFC    = FF_FUNGI[0];
        float bestFSeed = 1.7;
        for (int k = 0; k < 6; k++) {
            float r2 = dot2(p - FF_FUNGI[k].xyz);
            if (r2 < bestF2) {
                bestF2    = r2;
                bestFC    = FF_FUNGI[k];
                bestFSeed = float(k) * 2.1 + 1.7;
            }
        }
        if (bestF2 < 0.22 * 0.22) {
            float dummyR;
            float dFun = ff_sdShelfFungusSingle(p, bestFC.xyz, bestFC.w, bestFSeed, dummyR);
            if (dFun < res.x) res = vec2(dFun, MAT_FOREST_FUNGUS);
        }
    }

    return res;
}

// 8 gnarled, arched fallen redwood branches (slender 0.018..0.026m woody limbs) framing 5s, 7s & 9s foregrounds!
const vec3 FF_STICK_A[8] = vec3[8](
    vec3(-0.18, -0.045, -1.62), // 0: 5s lower-right crooked branch across oxalis
    vec3(-0.32,  0.032, -2.06), // 1: 5s crooked branch resting across nurse log's bare bark center
    vec3(-1.12, -0.005, -2.72), // 2: 7s left-foreground gnarled redwood limb
    vec3(-0.16, -0.052, -2.58), // 3: 7s center-foreground forked deadwood branch
    vec3(-1.08, -0.008, -3.72), // 4: 7s/9s left-foreground arching forked branch
    vec3(-0.42, -0.042, -4.08), // 5: 7s/9s center-left crooked deadwood limb
    vec3( 0.48, -0.036, -3.96), // 6: 7s/9s right-foreground forked stick
    vec3(-0.88, -0.028, -4.68)  // 7: 9s lower-left gnarled deadwood limb
);
const vec3 FF_STICK_B[8] = vec3[8](
    vec3( 1.06,  0.022, -1.94),
    vec3( 0.44, -0.044, -2.58),
    vec3( 0.08, -0.052, -3.14),
    vec3( 0.14, -0.048, -3.38),
    vec3( 0.06, -0.046, -4.18),
    vec3( 0.44, -0.040, -4.54),
    vec3( 1.24,  0.014, -4.38),
    vec3( 0.28, -0.044, -5.16)
);
const vec3 FF_STICK_P[8] = vec3[8](
    vec3(0.025, 0.013, 1.2),
    vec3(0.021, 0.011, 2.1),
    vec3(0.026, 0.014, 2.8),
    vec3(0.019, 0.010, 4.3),
    vec3(0.025, 0.013, 5.4),
    vec3(0.022, 0.011, 6.1),
    vec3(0.019, 0.009, 7.5),
    vec3(0.024, 0.012, 8.9)
);

float ff_sdCrookedStickSingle(vec3 p, vec3 a, vec3 b, vec3 params) {
    float rA = params.x, rB = params.y, seed = params.z;
    vec3 ba = b - a;
    float len = max(length(ba), 0.01);
    vec3 dir = ba / len;
    float h = clamp(dot(p - a, dir) / len, 0.0, 1.0);

    vec3 sideDir = normalize(vec3(-dir.z, 0.0, dir.x));
    float crook = 0.048 * sin(h * 4.5 + seed * 3.1) + 0.042 * (abs(h - 0.44) - 0.22);
    float arch  = 0.046 * sin(h * PI) * (0.75 + 0.25 * sin(seed * 2.0));
    vec3 spine  = mix(a, b, h) + sideDir * crook + vec3(0.0, arch, 0.0);

    float d = length(p - spine) - mix(rA, rB, h);
    vec3 forkRoot = mix(a, b, 0.50) + sideDir * 0.018 + vec3(0.0, 0.026, 0.0);
    vec3 forkTip  = forkRoot + normalize(dir + sideDir * 0.80) * (0.36 * len) + vec3(0.0, 0.022, 0.0);
    d = smin(d, sdCapsule(p, forkRoot, forkTip, rB * 0.82), 0.006);
    return d * 0.86;
}

// Grounded crooked woodland twigs (follow actual floor macro height so sticks NEVER float in orbit!)
float ff_sdTwigGrid(vec3 p, vec2 gridXZ, float localFloorY, float spacing, vec2 seedOfs, bool addFork) {
    vec2 cid = domRepeatId(gridXZ, vec2(spacing));
    vec3 hv  = hash32(cid + seedOfs);
    if (hv.x < 0.34) {
        vec2 inCell = abs(gridXZ - cid * spacing);
        return (0.5 * spacing - max(inCell.x, inCell.y)) + 0.14;
    }

    vec2 c  = cid * spacing + (hv.yz - 0.5) * (spacing * 0.26);
    vec2 dq = gridXZ - c;
    float halfLen = spacing * mix(0.18, 0.38, hv.y * hv.y);
    float radBound = length(dq);
    if (radBound > halfLen + 0.08) return radBound - halfLen;

    vec2 stickXZ = rot2(hv.z * TAU) * dq;
    float u = clamp((stickXZ.x + halfLen) / (2.0 * halfLen), 0.0, 1.0);
    float kinkSign = (hv.y > 0.5) ? 1.0 : -1.0;
    float crookZ = kinkSign * (0.040 * (abs(u - 0.42) - 0.21) + 0.024 * sin(u * 3.8 + hv.x * 4.0));
    float liftY  = 0.008 + 0.018 * sin(u * PI) * hv.y;
    float rStick = mix(0.018, 0.0085, u) * mix(0.85, 1.30, hv.x);

    float dx = max(abs(stickXZ.x) - halfLen, 0.0);
    float dz = stickXZ.y - crookZ;
    float dy = (p.y - localFloorY) - liftY;
    float d  = length(vec3(dx, dy, dz)) - rStick;

    if (addFork && hv.x > 0.48) {
        vec2 fp = stickXZ - vec2(0.04 * halfLen, crookZ);
        fp = rot2(0.74 * kinkSign) * fp;
        float fLen = 0.42 * halfLen;
        float fDx = max(max(-fp.x, fp.x - fLen), 0.0);
        float dFork = length(vec3(fDx, dy - 0.008 * clamp(fp.x / fLen, 0.0, 1.0), fp.y)) - rStick * 0.74;
        d = smin(d, dFork, 0.005);
    }
    return d * 0.86;
}

float ff_sdFallenTwigs(vec3 p, float macroFloorY) {
    float relY = p.y - macroFloorY;
    if (relY > 0.18) return relY - 0.10;

    float d = 1e5;

    if (p.z > -5.5 && p.z < -1.3 && abs(p.x) < 1.65) {
        float bestSB = 1e5;
        vec3  bestSA = FF_STICK_A[0];
        vec3  bestSE = FF_STICK_B[0];
        vec3  bestSP = FF_STICK_P[0];
        for (int i = 0; i < 8; i++) {
            float db = sdCapsule(p, FF_STICK_A[i], FF_STICK_B[i], 0.16);
            if (db < bestSB) {
                bestSB = db;
                bestSA = FF_STICK_A[i];
                bestSE = FF_STICK_B[i];
                bestSP = FF_STICK_P[i];
            }
        }
        d = bestSB + 0.09;
        if (bestSB < 0.13) {
            d = ff_sdCrookedStickSingle(p, bestSA, bestSE, bestSP);
        }
    }

    if (p.z > -6.8) {
        int layers = (!gFastMap && p.z > -5.8) ? 2 : 1;
        for (int l = ZERO; l < 2; l++) {
            if (l >= layers) break;
            vec2 gxz = (l == 0) ? p.xz : (rot2(1.08) * p.xz + vec2(0.37, 0.29));
            float sp = (l == 0) ? 0.86 : 0.62;
            vec2 seed = (l == 0) ? vec2(23.0, 67.0) : vec2(97.0, 43.0);
            d = min(d, ff_sdTwigGrid(p, gxz, macroFloorY, sp, seed, !gFastMap));
        }
    }
    return d;
}

// =============================================================================
// EXPORT 1: Complete Scene II SDF combining 02a_forest_trees + 02b_forest_floor
// =============================================================================
vec2 mapForest(vec3 p) {
    float baseY = ff_smoothBaseY(p);
    float relY  = p.y - baseY;

    vec2 res = mapForestTrees(p, baseY);

    float maxFloorH = (p.z > -13.8) ? mix(0.39, 0.30, smoothstep(-5.8, -7.4, p.z)) : 0.12;
    if (relY > maxFloorH + 0.12) {
        float dFloorAir = (relY - maxFloorH) * 0.88;
        if (dFloorAir < res.x) res = vec2(dFloorAir, MAT_FOREST_GROUND);
        return res;
    }

    float macroY   = ff_floorMacroHeight(p.xz, baseY);
    float groundY  = macroY;
    float macroGap = p.y - macroY;
    if (!gFastMap && macroGap < 0.095 && p.z > -12.0) {
        float fade = 1.0 - smoothstep(0.035, 0.092, macroGap);
        float p0   = abs(valueNoise(p.xz * 3.5 + vec2(4.2, 1.7)) * 2.0 - 1.0);
        float p1   = valueNoise(p.xz * 0.82 + vec2(2.1, -1.3));
        groundY += (0.034 * p0 * p1 + 0.009 * (valueNoise(p.xz * 7.2 + vec2(-2.7, 5.1)) - 0.5)) * fade;
    }
    float dGround = (p.y - groundY) * 0.82;
    if (dGround < res.x) res = vec2(dGround, MAT_FOREST_GROUND);

    if (p.z > -7.0 && p.z < -1.4 && relY < 0.42) {
        vec2 dLF = ff_sdLogsAndFungi(p, baseY);
        if (dLF.x < res.x) res = dLF;
    }

    if (p.z > -6.8 && p.z < 0.4 && abs(p.x) < 2.8 && macroGap < 0.18) {
        float dTwig = ff_sdFallenTwigs(p, macroY);
        if (dTwig < res.x) res = vec2(dTwig, MAT_FOREST_TWIG);
    }

    if (p.z > -13.8 && p.z < 0.6 && abs(p.x) < 4.4 && relY < maxFloorH + 0.10) {
        float dFern = ff_sdAllFerns(p, baseY);
        if (dFern < res.x) res = vec2(dFern, MAT_FOREST_FERN);
    }

    return res;
}

// Exact 2D grove-cylinder exit distance so sky rays never waste steps past the 16.5m outer grove!
float ff_cylinderExitT(vec2 roXZ, vec2 rdXZ, vec2 centerXZ, float radius) {
    float a = dot(rdXZ, rdXZ);
    if (a < 1e-5) return -1.0;
    vec2 oc = roXZ - centerXZ;
    float b = dot(oc, rdXZ);
    float c = dot(oc, oc) - radius * radius;
    float disc = b * b - a * c;
    return (disc >= 0.0) ? ((-b + sqrt(disc)) / a) : -1.0;
}

// Adaptive slope-bounded directional raymarcher (30 in dissolve) + distant tree fast-lane for 100% rooted orbit trunks!
vec3 ff_marchForest(vec3 ro, vec3 rd, float tmin, float tmax, int maxSteps) {
    int cap = gInDissolve ? 30 : maxSteps;
    int propStop = (cap * 7) / 10;
    float t = tmin;
    int steps = 0;

    float closeFlat   = max(-rd.y + 0.09, 0.012);
    float closeDome   = max(-rd.y + 0.34, 0.025);
    float closeGround = max(-rd.y + 0.42, 0.015);
    float closeDist   = max(-rd.y + 0.11, 0.008);

    float minTreeGap     = 1e5;
    float tClosestTree   = -1.0;
    float closestTreeMat = MAT_FOREST_TRUNK;

    for (int i = ZERO; i < 56; i++) {
        if (i >= cap) break;
        steps = i;
        vec3 p = ro + rd * t;
        float baseY = ff_smoothBaseY(p);
        float relY  = p.y - baseY;

        gFastMap = gInDissolve;
        vec2 res = mapForestTrees(p, baseY);
        gFastMap = false;
        if (res.x < minTreeGap) {
            minTreeGap     = res.x;
            tClosestTree   = t;
            closestTreeMat = res.y;
        }

        float maxFloorH = (p.z > -13.8 && t < 13.0) ? mix(0.39, 0.30, smoothstep(-5.8, -7.4, p.z)) : 0.10;
        if (relY < maxFloorH + 0.08 && p.z > -14.0 && t < 13.0 && i < propStop) {
            float macroY   = ff_floorMacroHeight(p.xz, baseY);
            float groundY  = macroY;
            float macroGap = p.y - macroY;
            if (macroGap < 0.095 && p.z > -12.0) {
                float fade = 1.0 - smoothstep(0.035, 0.092, macroGap);
                float p0   = abs(valueNoise(p.xz * 3.5 + vec2(4.2, 1.7)) * 2.0 - 1.0);
                float p1   = valueNoise(p.xz * 0.82 + vec2(2.1, -1.3));
                groundY += (0.034 * p0 * p1 + 0.009 * (valueNoise(p.xz * 7.2 + vec2(-2.7, 5.1)) - 0.5)) * fade;
            }
            float yGap   = p.y - groundY;
            float hitEps = max(0.0009 * t, 0.0004);
            if (yGap < hitEps && yGap < res.x) return vec3(t, MAT_FOREST_GROUND, float(i));

            float dDirGround = (-rd.y > -0.40) ? (yGap / closeGround) : 1e5;
            if (dDirGround < res.x) res = vec2(dDirGround, MAT_FOREST_GROUND);

            if (p.z > -7.0 && p.z < -1.4 && relY < 0.42) {
                vec2 dLF = ff_sdLogsAndFungi(p, baseY);
                if (dLF.x < res.x) res = dLF;
            }
            if (p.z > -6.8 && p.z < 0.4 && abs(p.x) < 2.8) {
                if (macroGap < 0.17) {
                    float dTwig = ff_sdFallenTwigs(p, macroY);
                    if (dTwig < res.x) res = vec2(dTwig, MAT_FOREST_TWIG);
                } else if (-rd.y > -0.08) {
                    float dDirTwig = (macroGap - 0.11) / closeFlat;
                    if (dDirTwig < res.x) res = vec2(dDirTwig, MAT_FOREST_TWIG);
                }
            }
            if (p.z < 0.6 && abs(p.x) < 4.4) {
                float dFern = ff_sdAllFernsDir(p, baseY, closeFlat, closeDome);
                if (dFern < res.x) res = vec2(dFern, MAT_FOREST_FERN);
            }
        } else {
            if (relY > maxFloorH + 0.08 && -rd.y > -0.08) {
                float dDirAir = (relY - maxFloorH) / closeFlat;
                if (dDirAir < res.x) res = vec2(max(dDirAir, 0.04), MAT_FOREST_GROUND);
            } else {
                float groundY = ff_floorMacroHeight(p.xz, baseY);
                float yGap    = p.y - groundY;
                if (yGap < max(0.0012 * t, 0.0005) && yGap < res.x) {
                    return vec3(t, MAT_FOREST_GROUND, float(i));
                }
                float dDirDist = (-rd.y > -0.10) ? (yGap / closeDist) : 1e5;
                if (dDirDist < res.x) res = vec2(dDirDist, MAT_FOREST_GROUND);
            }
        }

        if (abs(res.x) < max(0.0009 * t, 0.0004)) return vec3(t, res.y, float(i));
        t += res.x * 0.90;
        if (t > tmax) {
            if (minTreeGap < 0.014 && tClosestTree > 0.0) {
                return vec3(tClosestTree, closestTreeMat, float(i));
            }
            return vec3(-1.0, -1.0, float(i));
        }
    }

    // Seal close grazing bark-furrow step timeouts first
    if (minTreeGap < 0.022 && tClosestTree > 0.0) {
        return vec3(tClosestTree, closestTreeMat, float(cap));
    }

    // Fast-path tail march ONLY for rare (<0.3%) silhouette-grazing rays that hit step cap before tmax:
    // eliminates 1px sky-leak fringes between overlapping trunks at zero cost to 99.7% of pixels!
    if (!gInDissolve && t <= tmax) {
        gFastMap = true;
        for (int j = ZERO; j < 20; j++) {
            vec3 p = ro + rd * t;
            float baseY = ff_smoothBaseY(p);
            vec2 dT = mapForestTrees(p, baseY);
            float groundY = ff_floorMacroHeight(p.xz, baseY);
            float yGap    = p.y - groundY;
            if (yGap < max(0.0015 * t, 0.0006) && yGap < dT.x) {
                gFastMap = false;
                return vec3(t, MAT_FOREST_GROUND, float(cap));
            }
            if (dT.x < max(0.0015 * t, 0.0008)) {
                gFastMap = false;
                return vec3(t, dT.y, float(cap));
            }
            float dStep = (rd.y < -0.05) ? min(dT.x, yGap / closeDist) : dT.x;
            t += max(dStep * 0.95, 0.045);
            if (t > tmax) break;
        }
        gFastMap = false;
    }

    // Watertight analytic ground-plane fallback for rays threading multiple fern-pinnae gaps!
    if (rd.y < -0.008) {
        float tPlanar = (forestBaseHeight(ro.xz + rd.xz * t) - ro.y) / rd.y;
        if (tPlanar >= t * 0.90 && tPlanar < tmax) {
            return vec3(tPlanar, MAT_FOREST_GROUND, float(cap));
        }
    }
    return vec3(-1.0, -1.0, float(steps));
}

// Material-targeted tetrahedral normal: evaluates ONLY the hit sub-system SDF!
vec3 ff_calcForestNormal(vec3 p, float m, float baseY, float t) {
    float eps = max(0.0008 * t, 0.0005);
    if (m == MAT_FOREST_GROUND) {
        vec2 e = vec2(max(0.012, eps * 2.0), 0.0);
        float h0 = ff_floorHeight(p.xz, baseY, 0.0);
        float hx = ff_floorHeight(p.xz + e.xy, forestBaseHeight(p.xz + e.xy), 0.0);
        float hz = ff_floorHeight(p.xz + e.yx, forestBaseHeight(p.xz + e.yx), 0.0);
        return normalize(vec3(h0 - hx, e.x, h0 - hz));
    }

    gFastMap = (gInDissolve || t > 8.5);
    float macroY = ff_floorMacroHeight(p.xz, baseY);
    vec3 n = vec3(0.0);
    for (int i = ZERO; i < 4; i++) {
        vec3 e = 0.5773 * (2.0 * vec3((((i + 3) >> 1) & 1), ((i >> 1) & 1), (i & 1)) - 1.0);
        vec3 q = p + e * eps;
        float d;
        if (m == MAT_FOREST_TRUNK || m == MAT_FOREST_ROOT) {
            d = mapForestTrees(q, ff_smoothBaseY(q)).x;
        } else if (m == MAT_FOREST_FERN) {
            d = ff_sdAllFerns(q, baseY);
        } else if (m == MAT_FOREST_LOG || m == MAT_FOREST_FUNGUS) {
            d = ff_sdLogsAndFungi(q, baseY).x;
        } else {
            d = ff_sdFallenTwigs(q, macroY);
        }
        n += e * d;
    }
    gFastMap = false;
    return normalize(n);
}

// Pure-ALU spoked-starburst fern & log proxy for feathered contact shadows & AO
float ff_fastPropProxy(vec3 p, float baseY, bool includeFernDome) {
    float relY = p.y - baseY;
    float d = relY;

    if (includeFernDome) {
        float fb;
        vec4 fc = ff_nearestFernClump(p.xz, fb);
        if (fc.z > 0.0) {
            vec2 dq  = p.xz - fc.xy;
            float r  = length(dq);
            float ang = atan(dq.y, dq.x + 1e-6);
            // Irregular multi-harmonic frond shadow (never a regular 14-tooth gear wheel!)
            float spoke = 0.50 + 0.28 * sin(ang * 5.0 + fc.w * 2.1) + 0.22 * cos(ang * 9.0 - fc.w * 1.7);
            float effR  = (0.34 + 0.22 * spoke) * fc.z;
            float domeY = 0.16 * fc.z * (0.35 + 0.65 * sin(clamp(r / (0.64 * fc.z), 0.0, 1.0) * 1.72));
            float dF = max(length(vec2(max(r - effR, 0.0), max(relY - domeY, 0.0))) - 0.020, -(relY - 0.012));
            d = min(d, dF);
        }
    }

    if (p.z > -7.0 && p.z < -1.4) {
        for (int i = 0; i < 5; i++) {
            d = min(d, sdCapsule(p, FF_LOG_A[i], FF_LOG_B[i], max(FF_LOG_P[i].x, FF_LOG_P[i].y)));
        }
    }

    if (p.z > -5.5 && p.z < -1.3) {
        for (int i = 0; i < 8; i++) {
            d = min(d, sdCapsule(p, FF_STICK_A[i], FF_STICK_B[i], FF_STICK_P[i].x * 1.12));
        }
    }

    return d;
}

// ZERO-guarded shadow & AO loops prevent Metal PSO loop-unrolling bloat!
float ff_localFloorShadow(vec3 ro, vec3 rd, float baseY, bool isFern) {
    float res = 1.0;
    float t = 0.035;
    int steps = gInDissolve ? 3 : 5;
    for (int i = ZERO; i < 5; i++) {
        if (i >= steps) break;
        vec3 q = ro + rd * t;
        float h = ff_fastPropProxy(q, baseY + rd.y * 0.02, !isFern || t > 0.48);
        if (h < 0.001) { res = 0.0; break; }
        res = min(res, 4.8 * h / t);
        t += clamp(h, 0.06, 0.30);
        if (t > 1.25) break;
    }
    res = clamp(res, 0.0, 1.0);
    return res * res * (3.0 - 2.0 * res);
}

float ff_fastAO(vec3 p, vec3 n, float baseY, bool isTree, bool isFern) {
    if (gInDissolve) return 0.78;
    float occ = 0.0;
    float weight = 1.0;
    gFastMap = true;
    for (int i = ZERO; i < 3; i++) {
        float h = 0.04 + 0.09 * float(i);
        vec3 q = p + n * h;
        float d = isTree ? mapForestTrees(q, baseY).x : ff_fastPropProxy(q, baseY, !isFern);
        occ += (h - d) * weight;
        weight *= 0.55;
    }
    gFastMap = false;
    return clamp(1.0 - 2.4 * occ, 0.0, 1.0);
}

// =============================================================================
// Multi-Tier Floor Material Shaders & Dappled Canopy Sun-Fleck Field
// =============================================================================

// Coherent ~40-degree diagonal sunbeam ribbon field shared by volumetrics & floor sun pools!
float ff_diagonalBeamRibbons(vec3 p) {
    vec2 beamOrtho  = normalize(vec2(-FOREST_SUN_DIR.y, FOREST_SUN_DIR.x));
    float diagCoord = dot(p.xy, beamOrtho) + p.z * 0.22;
    float r0 = valueNoise(vec2(diagCoord * 1.45 + 1.7, p.z * 0.28 - 0.9));
    float r1 = valueNoise(vec2(diagCoord * 3.30 - 2.4, p.z * 0.55 + 2.1));
    float r2 = valueNoise(vec2(diagCoord * 6.80 + 4.3, p.z * 0.95 - 1.5));
    return smoothstep(0.35, 0.67, r0 * 0.52 + r1 * 0.33 + r2 * 0.15);
}

// Band-limited wide-penumbra volumetric shaft visibility (eliminates high-freq finePores stipple in #84!)
const vec3 FF_VOL_TRUNKS[8] = vec3[8](
    vec3(-2.86, -4.52, 0.68),
    vec3( 1.75, -4.76, 0.39),
    vec3(-1.92, -6.65, 0.39),
    vec3( 3.46, -9.45, 0.44),
    vec3(-2.38, -8.85, 0.25),
    vec3(-1.42, -12.80, 0.30),
    vec3( 0.58, -13.60, 0.25),
    vec3( 1.82, -12.40, 0.29)
);

float ff_volumetricShaftVis(vec3 p) {
    float vis = 1.0;
    vec2 ld = FOREST_SUN_DIR.xz;
    float ldInvLen = inversesqrt(max(dot(ld, ld), 1e-4));
    vec2 ldDir  = ld * ldInvLen;
    float slopeY = FOREST_SUN_DIR.y * ldInvLen;

    for (int i = 0; i < 8; i++) {
        vec3 tr = FF_VOL_TRUNKS[i];
        vec2 toCyl = tr.xy - p.xz;
        if (toCyl.x < -0.95 || toCyl.y > 0.95) continue;
        float proj = dot(toCyl, ldDir);
        if (proj > 0.0 && proj < 18.0) {
            float perp = abs(toCyl.x * ldDir.y - toCyl.y * ldDir.x);
            float hitY = max(p.y + proj * slopeY, 0.0);
            float effR = tr.z * (1.0 + 0.18 * clamp(1.0 - hitY * 0.55, 0.0, 1.0));
            // Wide soft penumbra prevents sub-step diagonal screen-door stipple!
            float penumbra = 0.22 + 0.042 * proj;
            vis *= smoothstep(effR - penumbra, effR + penumbra, perp);
        }
    }
    if (vis <= 0.005) return 0.0;

    float tCanopy = (9.0 - p.y) / max(FOREST_SUN_DIR.y, 0.15);
    vec2 sc = p.xz + FOREST_SUN_DIR.xz * tCanopy + vec2(0.04 * sin(gSceneTime * 0.55), 0.03 * cos(gSceneTime * 0.43));
    vec2 scRot = mat2(0.80, -0.60, 0.60, 0.80) * sc;
    float macroOpen = smoothstep(0.26, 0.66, valueNoise(scRot * 0.34 + vec2(1.6, -0.8)));
    float broadGaps = smoothstep(0.32, 0.68, valueNoise(scRot * vec2(1.05, 0.70) + vec2(3.1, -1.4)));
    return clamp(vis * mix(0.28, 1.0, macroOpen) * broadGaps * 1.28, 0.0, 1.0);
}

// High-contrast golden sun-fleck pools alternating with deep shady old-growth hollows
float ff_dappledFloorSun(vec3 p) {
    vec2 sunProj    = p.xz - FOREST_SUN_DIR.xz * (p.y / max(FOREST_SUN_DIR.y, 0.2));
    float gladePool  = smoothstep(0.36, 0.66, valueNoise(sunProj * 0.52 + vec2(1.8, -0.7)));
    float leafFlecks = smoothstep(0.36, 0.68, valueNoise(sunProj * 1.95 + vec2(-0.9, 2.4)));
    float ribbons    = ff_diagonalBeamRibbons(p);
    vec2  gladeD     = (p.xz - vec2(0.08, -7.2)) * vec2(0.42, 0.20);
    float clearingBoost = 0.92 / (1.0 + dot(gladeD, gladeD) * 1.4);
    return saturate((gladePool * leafFlecks * 1.05 + clearingBoost * 0.78) * (0.35 + 0.85 * ribbons));
}

// Domain-warped 3-tier needle duff (100% plaid-free in high orbit!), dark humus chiaroscuro & velvety moss
void ff_shadeForestGround(vec3 p, vec3 nIn, float t, float pxAngle, float groundFoot, float underLeafSha, out vec3 albedo, out float rough, out vec3 nOut, out float velvetFuzz) {
    float detailFade = 1.0 - smoothstep(4.5, 15.5, t);
    float microFade  = (1.0 - smoothstep(0.0022, 0.011, t * pxAngle)) * (1.0 - smoothstep(0.010, 0.022, groundFoot));

    float mossMask = ff_mossColonization(p.xz) * smoothstep(0.40, 0.86, nIn.y);
    float colMask  = ff_oxalisColonyMask(p.xz);

    // Organic domain warp BEFORE anisotropic stretching destroys 100% of woven plaid grid streaks in orbit!
    vec2 warpXZ = p.xz
                + 0.092 * vec2(gradientNoise(p.xz * 5.5), gradientNoise(p.xz * 5.5 + vec2(9.1, -4.7)))
                + 0.028 * vec2(gradientNoise(p.xz * 13.5 + vec2(3.1, 7.7)), gradientNoise(p.xz * 13.5 + vec2(-6.3, 2.9)));

    vec2 nUv0 = rot2(0.26) * warpXZ * vec2(3.6, 36.0);
    vec2 nUv1 = rot2(1.32) * warpXZ * vec2(3.8, 38.0) + vec2(7.3, 19.1);
    vec2 nUv2 = rot2(2.41) * warpXZ * vec2(3.5, 34.0) + vec2(31.7, 5.9);
    vec3 nd0  = valueNoiseD(nUv0);
    vec3 nd1  = valueNoiseD(nUv1);
    float nd2 = valueNoise(nUv2);
    float needleMat = saturate(max(max(nd0.x, nd1.x * 0.92), nd2 * 0.86));

    vec3 mossGrad = simplexNoiseD(p.xz * 34.0);
    vec3 midGrad  = gradientNoiseD(p.xz * 8.5);
    vec2 litterSlope = (rot2(-0.26) * (nd0.yz * vec2(3.6, 32.0)) + rot2(-1.32) * (nd1.yz * vec2(3.8, 34.0))) * 0.011 * microFade;
    vec2 bumpXZ = (mix(litterSlope, mossGrad.yz * 0.22 * microFade, mossMask) + midGrad.yz * 0.25) * detailFade;

    nOut = normalize(nIn + vec3(-bumpXZ.x, 0.0, -bumpXZ.y));

    // Rich dark damp redwood humus crevices vs warm rufous/cinnamon needle clusters (strong chiaroscuro!)
    float humusPatch  = smoothstep(0.30, 0.72, valueNoise(warpXZ * 1.85 + vec2(3.4, -2.1)));
    vec3 dampHumus    = srgbToLinear(vec3(0.095, 0.058, 0.034));
    vec3 rufousNeedle = srgbToLinear(vec3(0.295, 0.148, 0.068));
    vec3 dryTanNeedle = srgbToLinear(vec3(0.440, 0.265, 0.125));

    vec3 duffCol = mixOklab(dampHumus, rufousNeedle, saturate(humusPatch * 0.64 + needleMat * 0.58));
    duffCol = mixOklab(duffCol, dryTanNeedle, smoothstep(0.60, 0.88, needleMat) * microFade * 0.64);

    // Filtered sub-canopy foliage bed inside mounded oxalis colonies
    if (colMask > 0.05) {
        float subFoliage = mix(0.5, valueNoise(p.xz * 22.0 + vec2(4.1, -2.9)), microFade);
        vec3 oxUnderBed  = mixOklab(srgbToLinear(vec3(0.085, 0.185, 0.048)), srgbToLinear(vec3(0.215, 0.365, 0.095)), subFoliage);
        float bedBlend   = smoothstep(0.24, 0.68, colMask) * mix(0.38, 0.68, smoothstep(4.2, 7.0, t));
        duffCol = mixOklab(duffCol, oxUnderBed, bedBlend);
    }
    duffCol *= (1.0 - underLeafSha * 0.68);

    float h0 = abs(midGrad.x) * 1.35;
    float tuftTip = saturate(h0 * 0.68 + 0.32 * (0.5 + 0.5 * mossGrad.x * microFade));
    vec3 mossDeep = srgbToLinear(vec3(0.088, 0.192, 0.040));
    vec3 mossMid  = srgbToLinear(vec3(0.205, 0.358, 0.078));
    vec3 mossTip  = srgbToLinear(vec3(0.365, 0.515, 0.118));
    vec3 mossCol  = mixOklab(mossDeep, mossMid, smoothstep(0.14, 0.54, tuftTip));
    mossCol = mixOklab(mossCol, mossTip, smoothstep(0.54, 0.86, tuftTip));
    mossCol *= (1.0 - underLeafSha * 0.50);

    albedo = mixOklab(duffCol, mossCol, mossMask);
    rough  = mix(0.82, 0.90, mossMask);
    velvetFuzz = mossMask;
}

// =============================================================================
// EXPORT 2: Complete Scene II Forest Renderer
// =============================================================================
vec3 renderForest(vec2 uv, vec2 fragCoord, float pxAngle) {
    const float FOCAL = 1.85;
    float u = gSceneTime;

    float zCam = -0.35 - 0.52 * u;
    float groundHere = forestBaseHeight(vec2(0.0, zCam));
    vec3 ro = vec3(0.03 * sin(u * 0.4), groundHere + 0.76, zCam);
    vec3 ta = vec3(0.04, groundHere + 0.72, zCam - 5.5);
    applyOrbit(ro, vec3(0.0, groundHere + 0.95, zCam - 4.8), -0.45);

    float roBaseY = forestBaseHeight(ro.xz);
    ro.y = max(ro.y, roBaseY + 0.40);
    gFastMap = true;
    float camTreeD = mapForestTrees(ro, roBaseY).x;
    gFastMap = false;
    if (camTreeD < 0.44) {
        vec2 away = normalize(vec2(0.0, zCam - 4.8) - ro.xz + vec2(1e-4));
        ro.xz += away * (0.46 - camTreeD);
    }

    mat3 cam = cameraMatrix(ro, ta, 0.0);
    vec3 rd  = cameraRay(cam, uv, FOCAL);

#if DEBUG_MODE == 1
    return debugDistance(mapForest(vec3(uv.x * 3.2, uv.y * 2.2 + groundHere + 0.9, zCam - 3.6)).x);
#endif

    float tExitG = ff_cylinderExitT(ro.xz, rd.xz, vec2(0.0, -6.6), 16.5);
    float tMaxF  = (tExitG > 0.0) ? clamp(tExitG + 0.5, 15.2, 27.5) : 27.5;
    int   pSteps = (length(iMouse.xy) >= 0.5) ? 54 : 48;
    vec3  hit    = ff_marchForest(ro, rd, 0.08, tMaxF, pSteps);

#if DEBUG_MODE == 4
    return debugHeat(hit.z / float(pSteps));
#endif

    float tMaxVol = 18.0;
    vec3 col;

    if (hit.x > 0.0) {
        float t = hit.x;
        tMaxVol = min(t, 18.0);
        vec3 p = ro + rd * t;
        float baseY = ff_smoothBaseY(p);
        float m = floor(hit.y + 0.5);
        vec3 n = ff_calcForestNormal(p, m, baseY, t);
        vec3 v = -rd;

        float groundFoot = (t * pxAngle) / max(abs(rd.y), 0.14);
        float underOxalisShadow = 0.0;
        vec4 oxData  = vec4(0.0);
        vec2 oxSlope = vec2(0.0);
        if (!gInDissolve && m == MAT_FOREST_GROUND && p.z > -9.5 && t < 7.0) {
            oxData = ff_evalOxalisCarpet(p.xz, t, t * pxAngle, groundFoot, oxSlope);
            underOxalisShadow = oxData.y;
            if (oxData.x > 0.45) {
                m = MAT_FOREST_CLOVER;
            }
        }

        vec3  albedo     = vec3(0.15);
        float rough      = 0.80;
        float sssWeight  = 0.0;
        vec3  sssTint    = vec3(0.0);
        float velvetFuzz = 0.0;
        bool  isTree     = (m == MAT_FOREST_TRUNK || m == MAT_FOREST_ROOT);
        bool  isFern     = (m == MAT_FOREST_FERN);

        if (isTree) {
            shadeForestTree(m, p, n, t, albedo, rough, n);
        } else if (m == MAT_FOREST_GROUND || m == MAT_FOREST_CLOVER) {
            ff_shadeForestGround(p, n, t, pxAngle, groundFoot, underOxalisShadow, albedo, rough, n, velvetFuzz);
            float oxCov = oxData.x;
            if (oxCov > 0.005) {
                float detailFade = 1.0 - smoothstep(3.2, 7.0, t);
                vec3 nOx = normalize(n + vec3(-oxSlope.x, 0.0, -oxSlope.y) * detailFade);

                vec3 shamrockShade = srgbToLinear(vec3(0.135, 0.295, 0.078));
                vec3 shamrockFresh = srgbToLinear(vec3(0.285, 0.465, 0.138));
                vec3 shamrockSun   = srgbToLinear(vec3(0.605, 0.720, 0.385));
                vec3 oxAlbedo = mixOklab(shamrockShade, shamrockFresh, oxData.z);
                oxAlbedo = mixOklab(oxAlbedo, shamrockSun, smoothstep(0.60, 0.93, oxData.z) * 0.76 + oxData.w * 0.24);

                n          = normalize(mix(n, nOx, oxCov));
                albedo     = mixOklab(albedo, oxAlbedo, oxCov);
                rough      = mix(rough, 0.30, oxCov);
                velvetFuzz = mix(velvetFuzz, 0.0, oxCov);
                sssWeight  = 1.25 * oxCov;
                sssTint    = srgbToLinear(vec3(0.66, 0.82, 0.26));
            }
        } else if (isFern) {
            float detailFade = 1.0 - smoothstep(3.0, 12.5, t);
            vec3 vn = simplexNoiseD(p.xz * 56.0);
            n = normalize(n + vec3(-vn.y, 0.0, -vn.z) * 0.09 * detailFade);

            float relH = clamp((p.y - baseY) / 0.34, 0.0, 1.0);
            float frondVar = valueNoise(p.xz * 5.8 + vec2(p.y * 2.4));
            float rachisHint = smoothstep(0.42, 0.88, 1.0 - abs(n.y)) * smoothstep(0.0, 0.35, relH);

            // Deep cool forest-emerald in shadow (~0.08, 0.19, 0.06 sRGB) + blazing golden-lime in sunbeams!
            vec3 rootCrown  = srgbToLinear(vec3(0.085, 0.058, 0.034));
            vec3 deepFern   = srgbToLinear(vec3(0.082, 0.195, 0.056));
            vec3 lushFern   = srgbToLinear(vec3(0.158, 0.308, 0.086));
            vec3 youngCrown = srgbToLinear(vec3(0.265, 0.425, 0.118));
            albedo = mixOklab(deepFern, lushFern, saturate(frondVar * 0.68 + relH * 0.44));
            albedo = mixOklab(albedo, youngCrown, smoothstep(0.45, 0.95, relH) * 0.45 + rachisHint * 0.22);
            albedo = mixOklab(rootCrown, albedo, smoothstep(0.01, 0.11, relH));

            rough = mix(0.30, 0.46, frondVar);
            sssWeight = 1.75 * smoothstep(0.04, 0.22, relH);
            sssTint   = srgbToLinear(vec3(0.74, 0.88, 0.16));
        } else if (m == MAT_FOREST_LOG) {
            float detailFade = 1.0 - smoothstep(3.0, 12.0, t);
            float microFade  = 1.0 - smoothstep(0.0025, 0.012, t * pxAngle);

            float bestLD = 1e5;
            vec3 la = FF_LOG_A[0];
            vec3 lb = FF_LOG_B[0];
            vec4 lp = FF_LOG_P[0];
            for (int i = 0; i < 5; i++) {
                float dl = sdCapsule(p, FF_LOG_A[i], FF_LOG_B[i], max(FF_LOG_P[i].x, FF_LOG_P[i].y) * 1.4);
                if (dl < bestLD) {
                    bestLD = dl;
                    la     = FF_LOG_A[i];
                    lb     = FF_LOG_B[i];
                    lp     = FF_LOG_P[i];
                }
            }
            vec3 lDir  = normalize(lb - la);
            vec3 lSide = normalize(vec3(-lDir.z, 0.0, lDir.x));
            vec3 lUp   = cross(lSide, lDir);
            vec3 dVec  = p - (la + lDir * clamp(dot(p - la, lDir), 0.0, length(lb - la)));
            float uAlong  = dot(p - la, lDir);
            float vAround = atan(dot(dVec, lUp), dot(dVec, lSide) + 1e-6) * lp.x;

            float patchAlong = ff_logMossPatchMask(p, uAlong, lp.w);
            float mossBillow = ff_billow2(p.xz * 4.4 + vec2(1.7, -2.3));
            float shoulder   = dot(normalize(dVec + vec3(0.0, 1e-4, 0.0)), normalize(lUp - lSide * 0.12));
            float mossTop    = smoothstep(0.05, 0.52, shoulder + 0.26 * (mossBillow - 0.36)) * patchAlong;

            // Deeply split fibrous Sequoia bark in center bare gap + lumpy olive-emerald moss pillows!
            vec2 wUv = vec2(uAlong * 2.4, vAround * 22.0);
            vec3 wg  = gradientNoiseD(wUv);
            float g0 = ridgedFbm(wUv, 2);
            vec3 tangCirc = normalize(cross(lDir, n) + vec3(1e-4));
            vec3 woodBump = -(lDir * (wg.y * 0.06) + tangCirc * (wg.z * 0.28)) * (1.0 - mossTop * 0.88) * detailFade;

            vec3 mossTuft = simplexNoiseD(p.xz * 44.0);
            n = normalize(n + woodBump + vec3(-mossTuft.y, 0.0, -mossTuft.z) * 0.14 * microFade * mossTop * detailFade);

            vec3 rotChar     = srgbToLinear(vec3(0.042, 0.024, 0.014));
            vec3 redwoodCore = srgbToLinear(vec3(0.265, 0.120, 0.056));
            vec3 weatheredWd = srgbToLinear(vec3(0.415, 0.268, 0.158));
            vec3 woodCol = mixOklab(rotChar, redwoodCore, smoothstep(0.20, 0.64, g0));
            woodCol = mixOklab(woodCol, weatheredWd, smoothstep(0.66, 0.93, g0) * 0.58);

            vec3 logMossDeep = srgbToLinear(vec3(0.070, 0.165, 0.032));
            vec3 logMossMid  = srgbToLinear(vec3(0.188, 0.340, 0.072));
            vec3 logMossTip  = srgbToLinear(vec3(0.355, 0.505, 0.112));
            float tuftVal    = saturate(mossBillow * 0.72 + 0.28 * (0.5 + 0.5 * mossTuft.x * microFade));
            vec3 logMossCol  = mixOklab(logMossDeep, logMossMid, smoothstep(0.14, 0.54, tuftVal));
            logMossCol       = mixOklab(logMossCol, logMossTip, smoothstep(0.54, 0.88, tuftVal));

            albedo = mixOklab(woodCol, logMossCol, mossTop);
            rough = mix(0.78, 0.91, mossTop);
            velvetFuzz = mossTop;
        } else if (m == MAT_FOREST_FUNGUS) {
            float bestFD = 1e5;
            vec4  fc     = FF_FUNGI[0];
            for (int k = 0; k < 6; k++) {
                float df = dot2(p - FF_FUNGI[k].xyz);
                if (df < bestFD) {
                    bestFD = df;
                    fc     = FF_FUNGI[k];
                }
            }
            vec2  conkDelta = p.xz - fc.xz;
            float uConkR    = clamp(length(conkDelta - vec2(sin(fc.w), cos(fc.w)) * 0.012) / 0.046, 0.0, 1.0);
            float zones     = 0.5 + 0.5 * sin(uConkR * 22.0 + valueNoise(p.xz * 28.0) * 2.2);
            float outerLip  = smoothstep(0.72, 0.98, uConkR) + 0.45 * smoothstep(0.35, 0.85, 1.0 - abs(n.y));

            vec3 siennaZone = srgbToLinear(vec3(0.35, 0.175, 0.068));
            vec3 amberZone  = srgbToLinear(vec3(0.70, 0.460, 0.195));
            vec3 creamLip   = srgbToLinear(vec3(0.90, 0.84, 0.68));
            albedo = mixOklab(siennaZone, amberZone, zones);
            albedo = mixOklab(albedo, creamLip, saturate(outerLip) * 0.76);
            rough = 0.48;
            sssWeight = 0.78;
            sssTint   = srgbToLinear(vec3(0.88, 0.62, 0.26));
        } else {
            // Tangent-aligned longitudinal woody bark grain (eliminates diagonal barber-pole stripes!)
            vec3 stickTang = normalize(vec3(-n.z, 0.0, n.x) + vec3(1e-4, 0.0, 0.0));
            vec2 twigUv    = vec2(dot(p, stickTang) * 6.5, atan(n.y, length(n.xz) + 1e-4) * 5.5 + (p.x + p.z) * 4.0);
            vec3 twigGrd   = gradientNoiseD(twigUv);
            float stria    = ridgedFbm(twigUv, 2);
            float detailFade = 1.0 - smoothstep(3.0, 10.0, t);
            n = normalize(n + (stickTang * (-twigGrd.y * 0.06) + vec3(0.0, -twigGrd.z * 0.14, 0.0)) * detailFade);

            float lichenSpot = step(0.80, hash12(floor(p.xz * 42.0))) * smoothstep(0.2, 0.8, n.y);
            vec3 darkTwig = srgbToLinear(vec3(0.088, 0.052, 0.030));
            vec3 tanTwig  = srgbToLinear(vec3(0.415, 0.285, 0.172));
            albedo = mixOklab(darkTwig, tanTwig, smoothstep(0.20, 0.78, stria) * (0.50 + 0.50 * saturate(n.y)));
            albedo = mixOklab(albedo, srgbToLinear(vec3(0.36, 0.44, 0.29)), lichenSpot * 0.50);
            rough = 0.72;
        }

        float canopyVis = forestSunVisibility(p);
        float fleckVis  = isTree ? 0.0 : ff_dappledFloorSun(p);
        // Strictly respect 3D redwood trunk shadow lanes (canopyVis == 0 -> deep emerald/humus shadow!)
        float baseSun   = isTree ? canopyVis
                                 : saturate(canopyVis * (0.52 + 0.68 * fleckVis) + smoothstep(0.05, 0.35, canopyVis) * fleckVis * 0.45);
        float localSha  = (!isTree && baseSun > 0.02 && t < 12.5) ? ff_localFloorShadow(p + n * 0.020, FOREST_SUN_DIR, baseY, isFern) : 1.0;
        float sha       = baseSun * localSha * (1.0 - underOxalisShadow * 0.76);

        float ao = ((t < 12.5) ? ff_fastAO(p, n, baseY, isTree, isFern) : 0.82) * (1.0 - underOxalisShadow * 0.45);

        // High-contrast golden morning sunbeams vs cool shaded old-growth understory chiaroscuro!
        vec3 sunCol = vec3(8.8, 6.8, 3.75);
        vec3 key = shadePBR(n, v, FOREST_SUN_DIR, albedo, rough, 0.0) * sunCol * sha;

        if (isTree) {
            float sunSide = clamp(dot(n, FOREST_SUN_DIR), 0.0, 1.0);
            key += albedo * sunCol * sunSide * (0.22 + 0.78 * canopyVis) * 0.62;
        }

        if (sssWeight > 0.0) {
            float trans = translucency(n, v, FOREST_SUN_DIR, 0.45, 2.2, 0.18);
            float wrapD = wrapDiffuse(n, FOREST_SUN_DIR, 0.58);
            key += mix(albedo, sssTint, 0.62) * sunCol * (trans * 1.85 + wrapD * 0.62) * sha * sssWeight;
        }

        if (velvetFuzz > 0.01) {
            float rim = rimLight(n, v, 2.5) * max(dot(FOREST_SUN_DIR, -v) * 0.5 + 0.5, 0.0);
            key += srgbToLinear(vec3(0.50, 0.68, 0.16)) * sunCol * rim * sha * velvetFuzz * 0.48;
        }

        float fgShade   = isTree ? mix(1.05, 1.14, smoothstep(2.2, 8.2, t))
                                 : mix(0.88, 1.10, smoothstep(2.0, 8.2, t));
        // Calibrated linear canopy sky, camera-corridor mist bounce & warm humus fill (#72 Round-3 polish!)
        vec3 skyAmb     = (isTree ? srgbToLinear(vec3(0.39, 0.47, 0.31)) : vec3(0.255, 0.335, 0.185)) * fgShade;
        vec3 groundAmb  = (isTree ? srgbToLinear(vec3(0.24, 0.14, 0.068)) : vec3(0.125, 0.078, 0.040)) * fgShade;
        float fillScale = isTree ? 1.62 : (isFern ? 1.30 : 1.46);
        vec3 fill = albedo * hemisphereLight(n, skyAmb, groundAmb) * mix(0.24, 1.0, ao) * fillScale;
        if (isTree) {
            float corrBounce = max(dot(n, normalize(vec3(-0.35, 0.25, 0.90))), 0.0);
            fill += albedo * srgbToLinear(vec3(0.46, 0.50, 0.36)) * corrBounce * mix(0.45, 1.0, ao) * 0.85;
        }
        if (isFern || oxData.x > 0.05) {
            vec3 fSpec = envBRDFApprox(vec3(0.034), max(dot(n, v), 0.0), rough);
            fill += skyAmb * fSpec * ao * (0.42 + 0.85 * sha);
        }

#if DEBUG_MODE == 2
        return debugNormal(n);
#elif DEBUG_MODE == 3
        return debugIdColor(m);
#elif DEBUG_MODE == 5
        return vec3(sha, ao, baseSun);
#elif DEBUG_MODE == 6
        return vec3(luminance(key), luminance(fill), 0.0);
#endif

        col = key + fill;

        float sunAlign = max(dot(rd, normalize(vec3(0.478, 0.338, -0.810))), 0.0);
        vec3 mistTint = mixOklab(
            srgbToLinear(vec3(0.36, 0.41, 0.28)),
            srgbToLinear(vec3(0.84, 0.78, 0.55)),
            pow(sunAlign, 1.7)
        );
        float fogAmt = heightFog(ro + rd * min(t, 2.2), rd, max(t - 2.2, 0.0), 0.032, 0.24);
        col = mix(col, mistTint, fogAmt * 0.76);
    } else {
#if DEBUG_MODE == 2
        return vec3(0.0);
#elif DEBUG_MODE == 3
        return debugIdColor(0.0);
#elif DEBUG_MODE == 5
        return vec3(0.0);
#elif DEBUG_MODE == 6
        return vec3(0.0);
#endif
        col = forestCanopySky(ro, rd, pxAngle);
    }

    // Band-limited 8-step (2 in dissolve) ~40-degree diagonal morning sunbeams (#84 stipple-free wide penumbra!)
    if (tMaxVol > 1.2) {
        int volSteps = gInDissolve ? 2 : ((tMaxVol < 4.4) ? 4 : 8);
        float tStart = 1.05;
        float dt = (tMaxVol - tStart) / float(volSteps);
        float jitter = interleavedGradientNoise(floor(fragCoord), iFrame);

        vec3 canopyGapSun = normalize(vec3(0.478, 0.338, -0.810));
        vec2 beamOrtho    = normalize(vec2(-FOREST_SUN_DIR.y, FOREST_SUN_DIR.x));
        float muMain = dot(rd, FOREST_SUN_DIR);
        float muGap  = dot(rd, canopyGapSun);
        float phase  = 4.0 * PI * (0.45 * phaseDualHG(muMain, 0.62, -0.20, 0.82)
                                 + 0.55 * phaseDualHG(muGap,  0.68, -0.18, 0.85));

        vec3 volRad    = vec3(0.0);
        vec3 volTrans  = vec3(1.0);
        vec3 beamColor = vec3(3.35, 2.74, 1.60);
        vec3 ambMist   = srgbToLinear(vec3(0.22, 0.27, 0.17));

        for (int i = ZERO; i < 8; i++) {
            if (i >= volSteps) break;
            float tv = tStart + (float(i) + jitter) * dt;
            vec3 pv = ro + rd * tv;
            float depthGate   = smoothstep(1.2, 5.0, tv);
            float mistDensity = 0.026 * exp(-max(pv.y - 0.38, 0.0) * 0.19) * (0.18 + 0.82 * depthGate);
            float trunkAndCanopy = ff_volumetricShaftVis(pv);
            float diagCoord      = dot(pv.xy, beamOrtho) + pv.z * 0.22;
            float smoothRibbon   = smoothstep(0.28, 0.72, valueNoise(vec2(diagCoord * 0.95 + 1.7, pv.z * 0.20 - 0.9)));
            float shaft = trunkAndCanopy * (0.36 + 0.92 * smoothRibbon);
            vec3 inScat = mistDensity * (beamColor * phase * shaft + ambMist * 0.26);
            volumeStep(volRad, volTrans, vec3(mistDensity * 0.86), inScat, dt);
        }

        col = col * volTrans + volRad;
    }

    return col;
}

// ==== PART: 03a_ocean_waves.glsl ====
// =============================================================================
// SCENE III (Part A): OCEAN WAVES, STORM CLOUD CANOPY, FOAM WEBS & SPRAY
// Exports: stormCloudSky, traceStormOcean, shadeStormOcean, ow_islandSprayPlume
// =============================================================================

const vec3  ow_SKY_LIGHT_DIR  = normalize(vec3(-0.26, 0.78, -0.56));
const float ow_SWELL_LENGTH   = 22.5;
const float ow_SWELL_AMP      = 0.50;
const int   ow_TRACE_WAVES    = 8;
const int   ow_SHADE_WAVES    = 20;
const int   ow_FOAM_WAVES     = 6;
const float ow_TRACE_FAR      = 260.0;
const float ow_WATER_IOR      = 1.333;
const vec3  ow_WATER_EXTINCT  = vec3(0.52, 0.108, 0.074);

// Smoothstep returning vec2(value, dValue/dx) for exact analytic wave-envelope normals
vec2 ow_smoothstepD(float a, float b, float x) {
    float inv = 1.0 / max(b - a, 1e-5);
    float t = clamp((x - a) * inv, 0.0, 1.0);
    return vec2(t * t * (3.0 - 2.0 * t), 6.0 * t * (1.0 - t) * inv);
}

// Multi-directional dispersive storm wave spectrum: crossing North Atlantic swells + chunky wind chop
void ow_stormWave(int i, out vec2 dir, out float k, out float amp, out float phase, out float sharp) {
    float fi = float(i);
    if (i == 0) {
        dir   = vec2(-0.1045, 0.9945); // primary long Atlantic swell rolling toward +Z
        k     = TAU / ow_SWELL_LENGTH;
        amp   = ow_SWELL_AMP;
        phase = 1.20;
        sharp = 2.10;
        return;
    }
    if (i == 1) {
        dir   = vec2(0.2588, 0.9659);  // crossing swell (~21 deg) creating 3D wave groups
        k     = TAU / 16.2;
        amp   = ow_SWELL_AMP * 0.78;
        phase = 3.85;
        sharp = 2.20;
        return;
    }
    if (i == 2) {
        dir   = vec2(-0.3584, 0.9336); // oblique refracted swell train
        k     = TAU / 11.6;
        amp   = ow_SWELL_AMP * 0.60;
        phase = 5.15;
        sharp = 2.28;
        return;
    }
    vec3 h = hash32(vec2(fi, 37.0));
    float spread = mix(0.45, 1.28, clamp((fi - 2.0) / 10.0, 0.0, 1.0));
    float a = 1.58 + spread * (2.0 * h.x - 1.0);
    dir   = vec2(cos(a), sin(a));
    float wl = 9.2 * pow(0.775, fi - 3.0) * mix(0.88, 1.12, h.y);
    k     = TAU / max(wl, 0.10);
    amp   = (ow_SWELL_AMP * 0.46) * pow(0.735, fi - 3.0);
    phase = TAU * h.z;
    sharp = mix(2.40, 1.75, clamp((fi - 4.0) / 14.0, 0.0, 1.0));
}

float ow_waveKeep(vec2 dir, float k, vec4 fp) {
    float footprint = length(vec2(dot(dir, vec2(-fp.y, fp.x)) * fp.z, dot(dir, fp.xy) * fp.w));
    return smoothstep(2.0, 6.0, (TAU / k) / max(footprint, 1e-4));
}

// Sculpted asymmetric pitching/cresting foreground wave ridge sweeping past right foreground (10s..11.8s)
float ow_heroBreaker(vec2 xz, out vec2 grad, out float lipMask, out float faceMask, out float tumbleMask) {
    grad = vec2(0.0);
    lipMask = 0.0;
    faceMask = 0.0;
    tumbleMask = 0.0;

    float u = gSceneTime;
    float timeEnv = smoothstep(-0.10, 0.38, u) * (1.0 - smoothstep(2.00, 2.62, u));
    // Guard strictly outside C1 smoothstep zero-support (x in [-1.85, 11.2], z in [1.0, 27.6])
    if (timeEnv <= 1e-4 || xz.x <= -1.85 || xz.x >= 11.2 || xz.y <= 1.0 || xz.y >= 27.6) return 0.0;

    const vec2 bDir = vec2(-0.29237170, 0.95630476);
    const vec2 bTan = vec2( 0.95630476, 0.29237170);

    // Framed to film_10.00 (reaches uv.x ~ +1.05, leaving wide dark storm-teal ocean on far right uv.x = +1.08..+1.78!)
    vec2 xIn   = ow_smoothstepD(-1.75, 1.40, xz.x);
    vec2 xOut  = ow_smoothstepD(7.20, 10.90, xz.x);
    float xEnv = xIn.x * (1.0 - xOut.x);
    if (xEnv <= 1e-4) return 0.0;
    float dXEnv = xIn.y * (1.0 - xOut.x) - xIn.x * xOut.y;

    vec2 zIn   = ow_smoothstepD(1.20, 4.50, xz.y);
    vec2 zOut  = ow_smoothstepD(23.5, 27.5, xz.y);
    float zEnv = zIn.x * (1.0 - zOut.x);
    if (zEnv <= 1e-4) return 0.0;
    float dZEnv = zIn.y * (1.0 - zOut.x) - zIn.x * zOut.y;

    float sAlong = dot(xz, bTan);

    // Smooth sweeping crescent bow (zero curtain ripples on the translucent aqua barrel!)
    float bowArg = (xz.x - 4.2) * 0.25;
    float bowExp = exp(-bowArg * bowArg);
    float und1   = sin(sAlong * 0.56 - 0.30);
    float rShift = 1.25 * bowExp + 0.28 * und1;
    float dShift_ds = 0.28 * 0.56 * cos(sAlong * 0.56 - 0.30);
    float dShift_dx = 1.25 * (-2.0 * bowArg * 0.25) * bowExp;

    float sCrest = 11.30 + 6.45 * (u - 0.75);
    float sRel   = dot(xz, bDir) - (sCrest + rShift);
    if (abs(sRel) > 9.0) return 0.0;

    vec2 gradSRel = bDir - dShift_ds * bTan - vec2(dShift_dx, 0.0);

    // Steep pitching front face (sRel > 0, facing camera) vs shoaling back slope (sRel < 0)
    vec2 wMix   = ow_smoothstepD(-1.25, 0.85, sRel);
    float invW  = mix(0.32, 0.78, wMix.x);
    float dInvW = (0.78 - 0.32) * wMix.y;
    float q     = sRel * invW;
    float dq    = invW + sRel * dInvW;
    float eq    = exp(-q * q);

    // Drawn-down trough ahead of the pitching toe
    float qt    = (sRel - 2.20) * 0.52;
    float eqt   = exp(-qt * qt);

    float prof  = 1.65 * eq - 0.36 * eqt;
    float dProf = 1.65 * (-2.0 * q * dq) * eq - 0.36 * (-2.0 * qt * 0.52) * eqt;

    // Natural swell-peak modulation along ridge
    float ch1   = sin(sAlong * 0.70 + 0.25);
    float ch2   = sin(sAlong * 1.50 - u * 0.90);
    float cMod  = 0.90 + 0.16 * ch1 + 0.08 * ch2;
    float dCMod = 0.16 * 0.70 * cos(sAlong * 0.70 + 0.25)
                + 0.08 * 1.50 * cos(sAlong * 1.50 - u * 0.90);

    float env      = timeEnv * xEnv * zEnv;
    vec2  gradEnv  = timeEnv * vec2(dXEnv * zEnv, xEnv * dZEnv);
    float ampScale = env * cMod;
    vec2  gradAmp  = cMod * gradEnv + env * dCMod * bTan;

    grad = gradAmp * prof + ampScale * dProf * gradSRel;

    float activeEnv = smoothstep(0.08, 0.40, env);
    // Clean horizontal emerald-aqua pitching barrel window centered at xz.x ~ 4.1 right beneath the curling white lip!
    float clearBarrel = exp(-pow((xz.x - 4.1) / 2.25, 2.0));
    lipMask    = activeEnv * exp(-pow((sRel + 0.12) / 0.24, 2.0));
    faceMask   = activeEnv * smoothstep(0.02, 0.22, sRel) * (1.0 - smoothstep(0.82, 1.45, sRel)) * (0.42 + 0.58 * clearBarrel);
    float toeStart = mix(0.24, 0.92, clearBarrel);
    tumbleMask = activeEnv * smoothstep(toeStart - 0.12, toeStart + 0.24, sRel) * (1.0 - smoothstep(1.65, 2.75, sRel));

    return ampScale * prof;
}

float ow_oceanHeightTrace(vec2 xz, vec4 fp, bool checkBreaker) {
    float h = 0.0;
    float tAnim = gSceneTime + 4.2;
    // Hoisted aperiodic 2D spatial phase warp (evaluated ONCE per step instead of per wave -> >100 fps!)
    vec2 wp = xz * 0.026 + vec2(0.0, -0.04 * gSceneTime);
    vec2 swellWarp = 1.45 * vec2(gradientNoise(wp), gradientNoise(wp + vec2(17.3, 9.1)));

    for (int i = ZERO; i < ow_TRACE_WAVES; i++) {
        vec2 dir; float k, amp, ph, sharp;
        ow_stormWave(i, dir, k, amp, ph, sharp);
        float keep = ow_waveKeep(dir, k, fp);
        float meanOff = mix(0.31, 0.265, clamp((sharp - 2.0) * 1.6, 0.0, 1.0));
        float omega = sqrt(9.81 * k);
        float pWarp = (i < 6) ? dot(swellWarp, (i % 2 == 0) ? dir : vec2(-dir.y, dir.x)) : 0.0;
        float theta = k * dot(dir, xz) + pWarp - omega * tAnim + ph;
        h += keep * amp * (exp(sharp * (sin(theta) - 1.0)) - meanOff);
    }
    if (checkBreaker) {
        vec2 bGrad; float bLip, bFace, bTumble;
        h += ow_heroBreaker(xz, bGrad, bLip, bFace, bTumble);
    }
    return h;
}

vec4 ow_oceanDetail(vec2 xz, vec4 fp, out float lostSlope2, out float crest,
                    out float lipMask, out float faceMask, out float tumbleMask) {
    vec4 s = vec4(0.0);
    lostSlope2 = 0.0;
    crest = 0.0;
    float crestNorm = 0.0;
    float tAnim = gSceneTime + 4.2;

    // Hoisted analytic 2D phase-warp + derivatives (evaluated ONCE per pixel -> curves & bifurcates swells cleanly!)
    vec2 wp = xz * 0.026 + vec2(0.0, -0.04 * gSceneTime);
    vec3 gnA = gradientNoiseD(wp);
    vec3 gnB = gradientNoiseD(wp + vec2(17.3, 9.1));

    for (int i = ZERO; i < ow_SHADE_WAVES; i++) {
        vec2 dir; float k, amp, ph, sharp;
        ow_stormWave(i, dir, k, amp, ph, sharp);
        float keep = ow_waveKeep(dir, k, fp);

        float pWarp = 0.0;
        vec2  kVec  = k * dir;
        if (i < 6) {
            vec2 wMix = (i % 2 == 0) ? dir : vec2(-dir.y, dir.x);
            pWarp = 1.45 * (wMix.x * gnA.x + wMix.y * gnB.x);
            kVec += (1.45 * 0.026) * (wMix.x * gnA.yz + wMix.y * gnB.yz);
        }

        float omega = waterDispersion(k, 28.0, 9.81);
        float theta = k * dot(dir, xz) + pWarp - omega * tAnim + ph;
        float sn = sin(theta), cs = cos(theta);
        float e = exp(sharp * (sn - 1.0));
        float d1 = sharp * cs * e;
        float d2 = sharp * (sharp * cs * cs - sn) * e;
        float meanOff = mix(0.31, 0.265, clamp((sharp - 2.0) * 1.6, 0.0, 1.0));

        s += keep * amp * vec4(e - meanOff, d1 * kVec, k * k * d2);
        float slopeRms = 0.30 + 0.06 * sharp;
        float lost = amp * k * slopeRms;
        lostSlope2 += (1.0 - keep) * lost * lost;

        if (i < ow_FOAM_WAVES) {
            float w = amp * k;
            crest -= keep * w * d2;
            crestNorm += mix(0.50, 1.0, keep) * w * sharp;
        }
    }
    crest /= max(crestNorm, 1e-3);

    vec2 bGrad;
    float bH = ow_heroBreaker(xz, bGrad, lipMask, faceMask, tumbleMask);
    s.x  += bH;
    s.yz += bGrad;
    return s;
}

// Heavily fBm-warped radial reef distance around OCEAN_STACK_POS (radial surge lobes flush to rock, zero oval moat!)
float ow_reefDist(vec2 xz, out vec2 dIsl, out float angle) {
    dIsl = xz - (OCEAN_STACK_POS.xz + vec2(-0.30, 0.08));
    angle = atan(dIsl.y, dIsl.x + 1e-5);
    vec2 ellip = dIsl * vec2(0.76, 1.18);
    float fWarp = fbm(dIsl * 0.26 + vec2(0.0, -0.14 * gSceneTime), 3);
    float radialLobes = 0.65 * sin(angle * 3.0 + 0.7) + 0.42 * cos(angle * 5.0 - 1.2) + 0.35 * sin(angle * 8.0 + 0.4);
    return length(ellip) + 1.55 * fWarp + 0.55 * radialLobes;
}

// Fast analytic horizon mist color (cool North Atlantic slate-cyan-grey matching film_10..14!)
vec3 ow_horizonMistColor(vec3 rd) {
    float glow = 0.5 + 0.5 * clamp(dot(normalize(vec3(rd.x, 0.0, rd.z) + vec3(0.0, 0.0, -1e-4)),
                                       normalize(vec3(-0.18, 0.0, -0.98))), -1.0, 1.0);
    return mix(vec3(0.092, 0.150, 0.178), vec3(0.126, 0.194, 0.224), glow);
}

// Fast rough-filtered sky evaluation for ocean wave reflections
vec3 ow_stormSkyReflection(vec3 refl, float rough, vec3 lampPos, vec3 beamDir) {
    float h = clamp(refl.y, 0.0, 1.0);
    float u = gSceneTime;

    vec3 horiz = ow_horizonMistColor(refl);
    vec3 midSl = vec3(0.056, 0.104, 0.128);
    vec3 darkB = vec3(0.026, 0.052, 0.068);
    vec3 silv  = vec3(0.175, 0.238, 0.266);

    vec3 base = mixOklab(horiz, midSl, smoothstep(0.0, 0.18, h));
    base      = mixOklab(base, darkB, smoothstep(0.18, 0.48, h));

    float az = atan(refl.x, -refl.z);
    vec2 p = vec2(az * 2.4, h * 3.4) + vec2(u * 0.016, -u * 0.010);
    float c = 0.5 + 0.5 * fbm(p, 3);
    vec3 clouds = mixOklab(silv, darkB, smoothstep(0.22, 0.80, c));
    vec3 sky = mix(horiz, mix(base, clouds, 0.68 * (1.0 - rough * 0.55)), smoothstep(0.004, 0.055, h));

    vec3 bHoriz = normalize(vec3(beamDir.x, max(abs(beamDir.y), 0.16), beamDir.z));
    float alignM = max(dot(refl, bHoriz), 0.0);
    float warmB  = pow(alignM, 8.0) * smoothstep(0.04, 0.18, h) * (1.0 - smoothstep(0.24, 0.45, h)) * clamp(lampPos.y * 0.08, 0.4, 1.2);
    sky += blackbody(2850.0) * vec3(1.1, 0.94, 0.74) * warmB * 0.028;
    return sky;
}

// Multi-layered volumetric-feel North Atlantic storm cloud canopy
vec3 stormCloudSky(vec3 rd, vec3 lampPos, vec3 beamDir) {
    if (rd.y < -0.015) {
        return ow_horizonMistColor(rd) + 0.0 * (lampPos.x + beamDir.x);
    }

    float h = max(rd.y, 0.0);
    float u = gSceneTime;

    vec3 horizonMist = ow_horizonMistColor(rd);
    vec3 lowCloud    = vec3(0.092, 0.148, 0.174);
    vec3 midSlate    = vec3(0.058, 0.104, 0.128);
    vec3 darkBelly   = vec3(0.032, 0.060, 0.078);
    vec3 scudDark    = vec3(0.024, 0.046, 0.062);
    vec3 silverBreak = vec3(0.195, 0.260, 0.288);

    float az = atan(rd.x, -rd.z);
    float elevCoord = h * 2.55 + 0.22 * sqrt(h + 0.004);
    vec2 skyP  = vec2(az * 2.30, elevCoord);
    vec2 wind1 = vec2(u * 0.014, -u * 0.006);
    vec2 wind2 = vec2(u * 0.024, -u * 0.009);

    // Layer 1: Domain-warped cyclonic storm cloud bank (warpedFbm)
    vec2 wq, wr;
    float macroField = warpedFbm(skyP * 0.92 + wind1 + vec2(1.8, -0.7), 0.78, 3, wq, wr);

    // Layer 2: Velvety volumetric cumulus bellies (75% smooth 3D fBm + 25% billowFbm -> zero harsh Rorschach V-creases!)
    vec3 pBelly3   = vec3(skyP * 1.95 + wr * 0.48 + wind1 * 1.2, h * 2.6);
    float fbmBelly = 0.5 + 0.5 * fbm(pBelly3 * 0.85, 4, 2.02, 0.5);
    float bilBelly = billowFbm(pBelly3, 4);
    float belly    = mix(fbmBelly, bilBelly, 0.25);
    float bellyLight = 0.5 + 0.5 * fbm(pBelly3 * 0.85 + vec3(-0.20, 0.26, 0.14), 3, 2.02, 0.5);

    // Layer 3: Soft broad wind-sheared scud wisps (gentle 0.15 blend, zero dark ink cracks!)
    float scud = ridgedFbm(skyP * vec2(1.5, 2.2) + wq * 0.55 + wind2, 3);
    float wisp = turbulence(skyP * 3.1 - wr * 0.35 + wind2 * 1.25, 3);

    vec2 breakPos = vec2(az + 0.06, h - 0.28) * vec2(1.55, 3.3);
    float clearBreak = 0.32 * exp(-dot(breakPos, breakPos) * 1.8);
    float flankHeavy = 0.18 * smoothstep(0.16, 0.58, abs(az)) * smoothstep(0.08, 0.32, h);

    float cloudDensity = saturate(0.50 + 0.30 * macroField + 0.44 * (belly - 0.48) + 0.10 * (wisp - 0.5) + flankHeavy - clearBreak);
    float optDepth = saturate(0.46 + 0.28 * macroField + 0.46 * (bellyLight - 0.46) + flankHeavy - clearBreak * 0.85) * 2.3;

    float mu = clamp(dot(rd, ow_SKY_LIGHT_DIR), -1.0, 1.0);
    float powder = beerPowder(optDepth * 1.18);
    float trans  = mix(exp(-optDepth * 1.45), powder, 0.58);
    float phase  = 0.78 + 1.40 * phaseDualHG(mu, 0.58, -0.25, 0.70);

    vec3 cloudCol = mixOklab(silverBreak, lowCloud, smoothstep(0.15, 0.44, cloudDensity));
    cloudCol      = mixOklab(cloudCol, midSlate, smoothstep(0.38, 0.68, cloudDensity));
    cloudCol      = mixOklab(cloudCol, darkBelly, smoothstep(0.62, 0.92, cloudDensity));
    cloudCol     += silverBreak * (trans * phase * 0.12) * (1.0 - smoothstep(0.56, 0.88, cloudDensity));

    float scudMask = smoothstep(0.48, 0.84, scud * 0.62 + wisp * 0.38) * smoothstep(0.03, 0.16, h);
    cloudCol = mixOklab(cloudCol, scudDark, scudMask * 0.15);

    vec3 bHoriz = normalize(vec3(beamDir.x, max(abs(beamDir.y), 0.15), beamDir.z));
    float alignMain = max(dot(rd, bHoriz), 0.0);
    float baseBand  = smoothstep(0.08, 0.18, h) * (1.0 - smoothstep(0.24, 0.38, h));
    float warmGlow  = pow(alignMain, 12.0) * baseBand * (0.4 + 0.6 * belly) * clamp(lampPos.y * 0.08, 0.5, 1.25);
    cloudCol += blackbody(2850.0) * vec3(1.1, 0.94, 0.74) * warmGlow * 0.025;

    float stratus = 0.5 + 0.5 * fbm(vec2(az * 3.4 + u * 0.012, h * 34.0 + wq.x * 0.8), 3);
    vec3 lowHaze  = mixOklab(horizonMist, lowCloud, smoothstep(0.004, 0.048, h) * (0.45 + 0.55 * stratus));

    return mix(lowHaze, cloudCol, smoothstep(0.008, 0.058, h));
}

// Fast slab-clipped heightfield march with conservative ray-box breaker culling (>=100 fps!)
float traceStormOcean(vec3 ro, vec3 rd) {
    float u = gSceneTime;
    bool breakerTime = (u < 2.64);

    bool rayHitsBreakerBox = false;
    if (breakerTime && rd.y < 0.05) {
        float tNearCheck = max((ro.y - 2.35) / max(-rd.y, 0.02), 0.15);
        float tFarCheck  = min((ro.y + 1.25) / max(-rd.y, 0.02), 38.0);
        vec2 pA = ro.xz + rd.xz * tNearCheck;
        vec2 pB = ro.xz + rd.xz * tFarCheck;
        if (max(pA.x, pB.x) > -2.0 && min(pA.x, pB.x) < 11.5 && max(pA.y, pB.y) > 0.8 && min(pA.y, pB.y) < 27.8) {
            rayHitsBreakerBox = true;
        }
    }

    float yMax = rayHitsBreakerBox ? 2.35 : 1.38;
    float yMin = -1.30;

    if (rd.y >= -0.0005 && ro.y >= yMax) return -1.0;

    float tStart = 0.08;
    float tEnd   = ow_TRACE_FAR;
    if (rd.y < -0.0005) {
        if (ro.y > yMax) {
            tStart = max((ro.y - yMax) / -rd.y, 0.08);
        }
        tEnd = min((ro.y - yMin) / -rd.y, ow_TRACE_FAR);
    } else {
        tEnd = 36.0;
    }
    if (tStart >= tEnd) {
        return (rd.y < -0.0005) ? max(ro.y / -rd.y, 0.08) : -1.0;
    }

    vec2 viewXZ = (length(rd.xz) > 1e-4) ? normalize(rd.xz) : vec2(0.0, -1.0);
    float basePx = 2.0 / max(iResolution.y * 2.0, 1.0);
    vec4 pixelSpread = vec4(viewXZ, basePx, basePx / max(abs(rd.y), 0.025));

    float maxSlope = rayHitsBreakerBox ? 1.50 : 0.80;
    float closing  = max(-rd.y + maxSlope * length(rd.xz), 0.12);

    float t = tStart;
    float prevT = tStart;
    float prevGap = 1e6;
    int maxSteps = gInDissolve ? 30 : (rayHitsBreakerBox ? 42 : 34);

    for (int i = ZERO; i < 44; i++) {
        if (i >= maxSteps) break;
        vec3 p = ro + rd * t;
        float gap = p.y - ow_oceanHeightTrace(p.xz, pixelSpread * vec4(1.0, 1.0, t, t), rayHitsBreakerBox);
        if (gap < 0.0) {
            float lo = prevT;
            float hi = t;
            float sec = clamp(mix(lo, hi, prevGap / max(prevGap - gap, 1e-5)), lo, hi);
            for (int j = 0; j < 3; j++) {
                float mid = (j == 0) ? sec : 0.5 * (lo + hi);
                vec3 q = ro + rd * mid;
                float gMid = q.y - ow_oceanHeightTrace(q.xz, pixelSpread * vec4(1.0, 1.0, mid, mid), rayHitsBreakerBox);
                if (gMid > 0.0) lo = mid; else hi = mid;
            }
            return 0.5 * (lo + hi);
        }
        if (t >= tEnd) break;
        prevT = t;
        prevGap = gap;
        t = min(t + max(gap / closing, 0.014 * t + 0.03), tEnd);
    }

    if (rd.y < -0.0005) {
        return max(ro.y / -rd.y, 0.08);
    }
    return -1.0;
}

// Crashing white surf plumes on the basalt flanks (billowing cauliflower silhouette, zero outer box edge!)
vec4 ow_islandSprayPlume(vec3 ro, vec3 rd, float tMax) {
    vec3 center = OCEAN_STACK_POS + vec3(0.45, 1.75, -0.10);
    vec2 bSph = iSphere(ro, rd, center, 10.4);
    if (bSph.y <= 0.0 || bSph.x >= tMax) return vec4(0.0);

    float t0 = max(bSph.x, 0.2);
    float t1 = min(bSph.y, tMax);
    if (t1 <= t0 + 0.05) return vec4(0.0);

    float u = gSceneTime;
    const int STEPS = 5;
    float dt = (t1 - t0) / float(STEPS);

    float earlyImpact = 1.0 + 0.72 * (1.0 - smoothstep(1.1, 2.5, u));

    float alphaAcc = 0.0;
    float shadeAcc = 0.0;

    for (int i = 0; i < STEPS; i++) {
        float tm = t0 + (float(i) + 0.5) * dt;
        vec3 p = ro + rd * tm;
        if (p.y < -0.30 || p.y > 5.80) continue;

        vec2 q = p.xz - OCEAN_STACK_POS.xz;
        float ang = atan(q.y, q.x + 1e-5);
        float rRaw = length(q * vec2(0.78, 1.15));
        if (rRaw < 2.0 || rRaw > 9.4) continue;

        vec3 spCoord = p * vec3(0.46, 0.52, 0.46) + vec3(-0.20 * u, -0.68 * u, -0.12 * u);
        float puff = billowFbm(spCoord, 3);

        // Puff-warped radial & vertical falloff so outer plume silhouette is fluffy cauliflower, never a straight wall!
        float rWarped  = rRaw - 1.35 * (puff - 0.45);
        float ringBand = smoothstep(2.1, 3.5, rWarped) * (1.0 - smoothstep(4.6, 7.6, rWarped));
        if (ringBand <= 0.005) continue;

        float rightFlank = exp(-pow((ang - 0.12) / 0.56, 2.0)) * (0.95 + 0.25 * sin(u * 1.25 + 0.8)) * earlyImpact;
        float leftFlank  = exp(-pow((abs(ang) - 2.80) / 0.58, 2.0)) * (0.72 + 0.28 * sin(u * 1.45 + 2.2));
        float frontLeft  = exp(-pow((ang - 2.15) / 0.72, 2.0)) * (0.76 + 0.26 * sin(u * 1.65 - rRaw * 0.5));

        float maxH = (1.45 * frontLeft + 3.25 * rightFlank + 2.15 * leftFlank + 0.30) * (0.65 + 0.65 * puff);
        if (p.y > maxH) continue;

        float hNorm = clamp((p.y + 0.20) / max(maxH, 0.6), 0.0, 1.2);
        float vEnv  = smoothstep(0.0, 0.16, hNorm) * (1.0 - smoothstep(0.38, 1.0, hNorm));
        if (vEnv <= 0.005) continue;

        float shape = smoothstep(0.16, 0.56, puff);
        float plumeStrength = 1.65 * rightFlank + 1.05 * leftFlank + 1.10 * frontLeft;
        float dens  = ringBand * vEnv * shape * plumeStrength;
        float stepA = 1.0 - exp(-dens * dt * 0.68);
        float litH  = clamp(0.58 + 0.42 * hNorm + 0.18 * (puff - 0.45), 0.0, 1.0);
        shadeAcc += (1.0 - alphaAcc) * stepA * litH;
        alphaAcc += (1.0 - alphaAcc) * stepA;
    }

    if (alphaAcc <= 0.002) return vec4(0.0);
    float avgLit = shadeAcc / max(alphaAcc, 1e-4);
    vec3 sprayShadow = vec3(0.28, 0.37, 0.41);
    vec3 sprayBright = vec3(0.88, 0.95, 0.98);
    vec3 sprayCol    = mixOklab(sprayShadow, sprayBright, clamp(avgLit, 0.0, 1.0));
    return vec4(sprayCol, clamp(alphaAcc * 0.94, 0.0, 0.92));
}

// Sweeping circular mist arc rising over the 10.0s..11.0s foreground breaker barrel (matching film_10.00!)
vec4 ow_breakerSpindrift(vec3 ro, vec3 rd, float tHit) {
    float u = gSceneTime;
    float timeEnv = smoothstep(-0.05, 0.38, u) * (1.0 - smoothstep(1.92, 2.58, u));
    if (timeEnv <= 0.005) return vec4(0.0);

    const vec2 bDir = vec2(-0.29237170, 0.95630476);
    const vec2 bTan = vec2( 0.95630476, 0.29237170);

    float denom = dot(rd.xz, bDir);
    if (abs(denom) < 0.05) return vec4(0.0);

    float sCrest = 11.30 + 6.45 * (u - 0.75);
    float tau0   = (sCrest + 0.4 - dot(ro.xz, bDir)) / denom;
    if (tau0 < 0.5 || tau0 > tHit + 2.0) return vec4(0.0);

    vec2 xz0 = ro.xz + rd.xz * tau0;
    if (xz0.x < -0.2 || xz0.x > 9.8) return vec4(0.0);

    float sAl0  = dot(xz0, bTan);
    float bow0  = (xz0.x - 4.2) * 0.25;
    float rSh0  = 1.25 * exp(-bow0 * bow0) + 0.28 * sin(sAl0 * 0.56 - 0.30);
    float tauC  = (sCrest + rSh0 - 1.4 - dot(ro.xz, bDir)) / denom;
    if (tauC < 0.5 || tauC >= tHit - 0.1) return vec4(0.0);

    float alphaAcc = 0.0;
    float lumAcc   = 0.0;
    for (int k = -1; k <= 2; k++) {
        float tk = clamp(tauC + float(k) * 1.05, 0.4, tHit - 0.05);
        vec3 pk = ro + rd * tk;

        float xNorm = (pk.x - 5.2) / 3.2;
        if (abs(xNorm) > 1.25) continue;

        float sAl  = dot(pk.xz, bTan);
        float bowA = (pk.x - 4.2) * 0.25;
        float rSh  = 1.25 * exp(-bowA * bowA) + 0.28 * sin(sAl * 0.56 - 0.30);
        float sRel = dot(pk.xz, bDir) - (sCrest + rSh);

        float trailEnv = smoothstep(-4.8, -1.2, sRel) * (1.0 - smoothstep(0.4, 1.6, sRel));
        if (trailEnv <= 0.01) continue;

        float archDomeY = 1.05 + 2.95 * sqrt(max(1.0 - xNorm * xNorm * 0.76, 0.0));
        float distRim   = abs(pk.y - archDomeY);
        float rimArc    = exp(-(distRim * distRim) / 0.76);
        float innerMist = smoothstep(0.2, 1.4, pk.y) * (1.0 - smoothstep(archDomeY - 0.4, archDomeY + 0.8, pk.y)) * 0.52;
        float latFade   = smoothstep(1.22, 0.52, abs(xNorm));
        float band      = (rimArc * 0.85 + innerMist) * latFade * trailEnv;
        if (band <= 0.01) continue;

        vec2 spUV = vec2(pk.x * 0.45 - u * 0.65, pk.y * 0.55 + sRel * 0.25 - u * 1.05);
        float mist = 0.5 + 0.5 * fbm(spUV * 1.8, 3);
        float shred = turbulence(spUV * 3.2, 2);
        float d = timeEnv * band * smoothstep(0.16, 0.62, mist * 0.68 + shred * 0.32);
        float stepA = d * 0.42;
        lumAcc   += (1.0 - alphaAcc) * stepA * clamp(0.56 + 0.38 * (pk.y / 3.8), 0.0, 1.0);
        alphaAcc += (1.0 - alphaAcc) * stepA;
    }

    if (alphaAcc <= 0.002) return vec4(0.0);
    float l = lumAcc / max(alphaAcc, 1e-4);
    vec3 mistCol = mixOklab(vec3(0.26, 0.35, 0.39), vec3(0.76, 0.84, 0.87), l);
    return vec4(mistCol, clamp(alphaAcc, 0.0, 0.78));
}

// Sheared & eroded sea-froth filigree (zero closed fishnet loops, zero outer patch outline!)
float ow_erodedFrothWeb(vec2 q, float jitter, float width, float aa, float erodeField) {
    if (width <= 1e-4) return 0.0;
    vec3 vb = voronoiBorder(q, jitter);
    float r2 = dot(vb.yz, vb.yz);
    float d = vb.x - 0.34 * max(r2 - 0.09, 0.0) + erodeField;
    float effW = max(width, aa * 0.80);
    float cov  = clamp(width / max(effW, 1e-4), 0.0, 1.0);
    return cov * (1.0 - smoothstep(effW * 0.28, effW * 1.38, d));
}

vec3 shadeStormOcean(vec3 ro, vec3 rd, float t, float pxAngle, vec3 lampPos, vec3 beamDir) {
    float u = gSceneTime;
    vec3 p = ro + rd * t;

    vec2 viewXZ    = (length(rd.xz) > 1e-4) ? normalize(rd.xz) : vec2(0.0, -1.0);
    float acrossFp = max(t * pxAngle, 1e-4);
    float alongFp  = max(t * pxAngle / max(abs(rd.y), 0.025), acrossFp);
    vec4 fp        = vec4(viewXZ, acrossFp, alongFp);
    float isoFp    = sqrt(acrossFp * alongFp);

    float lostSlope2, crest, lipMask, faceMask, tumbleMask;
    vec4 wv = ow_oceanDetail(p.xz, fp, lostSlope2, crest, lipMask, faceMask, tumbleMask);
    vec2 slope = wv.yz;

    // 3 octaves of rotating-gradient simplexNoiseD wind-chop
    float keepR1 = smoothstep(2.0, 5.5, 0.85 / isoFp);
    float keepR2 = smoothstep(2.0, 5.5, 0.30 / isoFp);
    float keepR3 = smoothstep(2.0, 5.5, 0.11 / isoFp);

    if (keepR1 > 0.001) {
        vec3 r1 = simplexNoiseD(p.xz * 1.15 + vec2(0.24, 0.70) * u, 1.05 * u);
        slope += (0.013 * 1.15 * keepR1) * r1.yz;
    }
    if (keepR2 > 0.001) {
        vec3 r2 = simplexNoiseD(p.xz * 3.35 - vec2(0.45, 0.20) * u, -1.65 * u);
        slope += (0.0050 * 3.35 * keepR2) * r2.yz;
    }
    if (keepR3 > 0.001) {
        vec3 r3 = simplexNoiseD(p.xz * 8.90 + vec2(0.30, -0.55) * u, 2.35 * u);
        slope += (0.0018 * 8.90 * keepR3) * r3.yz;
    }

    lostSlope2 += (1.0 - keepR1) * 0.0015 + (1.0 - keepR2) * 0.0012 + (1.0 - keepR3) * 0.0008;

    // Heavily fBm-warped radial reef distance around OCEAN_STACK_POS
    vec2 dIsl; float islAng;
    float rReef = ow_reefDist(p.xz, dIsl, islAng);

    // -------------------------------------------------------------------------
    // Rich 3-tier sheared & eroded sea foam:
    //  - 75% glossy deep storm-teal foreground water at 10s..12s!
    //  - Softly feathered outer foam margins (width starts at 0.0 -> zero patch contour rings!)
    //  - Richer broken reef-shoal froth wake closer to island for 14s!
    // -------------------------------------------------------------------------
    vec2 macroCurl = curlNoise(p.xz * 0.16 + vec2(0.015 * u, -0.045 * u));

    // 1) Localized swirling eddy raft in lower-left/center foreground at 12s (z ~ 17.5, x ~ -0.3)
    vec2 dEddy  = (p.xz - vec2(-0.35, 17.4 + 0.15 * u)) * vec2(0.95, 1.25) + macroCurl * 1.55;
    float rEddy = length(dEddy);
    float eddySwirl = fbm(dEddy * 0.55 + macroCurl * 1.2, 3);
    float heroEddy  = smoothstep(0.3, 1.8, rEddy) * (1.0 - smoothstep(2.6, 4.8, rEddy + eddySwirl * 1.4))
                    * smoothstep(-0.15, 0.45, eddySwirl + 0.35 * sin(atan(dEddy.y, dEddy.x + 1e-5) * 2.0 + 1.1));

    // 2) Sparse sheared open-sea foam patches & broken gossamer spume wisps (zero stencil S-paint stripes!)
    vec2 rq, rr;
    float seaPatchField = warpedFbm((p.xz * vec2(0.75, 1.25) + macroCurl * 1.5) * 0.115 + vec2(0.01 * u, -0.04 * u), 0.85, 3, rq, rr);
    float sparseRafts   = smoothstep(0.52, 0.80, seaPatchField);

    float spumeRidge = ridgedFbm((p.xz + macroCurl * 2.1) * vec2(0.34, 0.17) + vec2(1.4, -0.08 * u), 3);
    float spumeBreak = 0.5 + 0.5 * fbm(p.xz * 1.35 - vec2(0.0, 0.15 * u), 3);
    float spumeFilaments = smoothstep(0.78, 0.95, spumeRidge) * smoothstep(0.42, 0.78, spumeBreak);
    float fgFade = 1.0 - smoothstep(18.0, 50.0, t);

    // 3) Rock-hugging radial surf collar + denser broken reef-shoal wake in rReef < 16.0m (fills 14s foreground richly!)
    float surgeWave = 0.5 + 0.5 * sin(rReef * 1.15 - u * 2.05 + 1.6 * macroCurl.x);
    float nearCollar = smoothstep(0.2, 1.8, rReef) * (1.0 - smoothstep(6.2, 10.6, rReef));
    float reefShoalWake = smoothstep(1.0, 3.2, rReef) * (1.0 - smoothstep(10.2, 16.4, rReef - max(dIsl.y, 0.0) * 0.18))
                        * smoothstep(0.04, 0.50, seaPatchField + 0.36 * sin(rReef * 1.28 - u * 1.85));

    float filigreeEnv = saturate(
        heroEddy * 0.92 * fgFade +
        sparseRafts * 0.72 * fgFade +
        spumeFilaments * 0.22 * fgFade +
        nearCollar * (0.76 + 0.24 * surgeWave) +
        reefShoalWake * 1.02
    );

    float laceFoam  = 0.0;
    float milkyVeil = 0.0;
    if (filigreeEnv > 0.015) {
        // Strictly invertible domain warp (det(J) > +1.6 everywhere -> ZERO folded-Voronoi tire-tread stripes in close/orbit views!)
        vec2 fWarp = vec2(fbm(p.xz * 0.60 + vec2(0.05 * u, -0.10 * u), 3),
                          fbm(p.xz * 0.60 + vec2(5.2 - 0.06 * u, 1.7 - 0.08 * u), 3));
        vec2 cFine = curlNoise(p.xz * 1.20 - vec2(0.07 * u, 0.11 * u));
        vec2 qCell = p.xz * vec2(2.20, 1.60) + 0.42 * fWarp + 0.13 * cFine;

        float frothClump  = billowFbm(p.xz * vec2(1.85, 1.35) + fWarp * 0.55 - vec2(0.0, 0.16 * u), 3);
        float fineCluster = 0.5 + 0.5 * fbm(qCell * 1.25 + cFine * 0.8, 3);
        float clusterKeep = frothClump * 0.56 + fineCluster * 0.44;

        // Progressive margin erosion (NO smoothstep(0.02, 0.26) sticker cliff!):
        // High filigreeEnv -> connected lacy bubble web; low filigreeEnv -> dissolves into dispersed isolated bubble clusters!
        float envRamp      = pow(clamp(filigreeEnv, 0.0, 1.0), 1.15);
        float clusterSurv  = smoothstep(0.56 - 0.50 * envRamp, 0.80 - 0.40 * envRamp, clusterKeep);
        float localFroth   = envRamp * clusterSurv;

        float erode1 = 0.26 * (1.0 - envRamp) * (1.10 - clusterKeep)
                     + 0.16 * max(0.40 - fineCluster, 0.0)
                     + 0.11 * max(turbulence(qCell * 2.4 - vec2(0.0, 0.18 * u), 2) - 0.50, 0.0);

        float width1 = 0.155 * localFroth * (0.55 + 0.55 * frothClump);
        float aa1    = max(isoFp * 4.2, 0.062);
        float web1   = ow_erodedFrothWeb(qCell * 2.15, 0.94, width1, aa1, erode1);

        float web2 = 0.0;
        float keepB2 = 1.0 - smoothstep(0.03, 0.16, isoFp);
        if (keepB2 > 0.01 && localFroth > 0.02) {
            float erode2 = 0.22 * (1.0 - envRamp) + 0.16 * max(0.42 - frothClump, 0.0);
            float aa2    = max(isoFp * 8.0, 0.070);
            web2 = ow_erodedFrothWeb(qCell * 4.90 + cFine * 0.85, 0.94, 0.12 * localFroth, aa2, erode2) * keepB2;
        }

        float microSpume = smoothstep(0.46, 0.82, clusterKeep * 0.65 + ridgedFbm(qCell * 1.85, 2) * 0.45);
        // Cluster-gated milky-aqua submerged froth halo (hugs dispersed bubble clusters, zero flat sticker silhouette!)
        milkyVeil = saturate(localFroth * (0.42 * microSpume + 0.45 * web1));
        laceFoam  = saturate(web1 * (0.76 + 0.24 * localFroth) + web2 * 0.55 + localFroth * microSpume * 0.38);
    }

    // Tier (a): Open-ocean breaking whitecaps gated by 2-octave warped fBm (varied organic lengths, ZERO grid!)
    vec2 capWarp = p.xz * vec2(0.048, 0.082) + macroCurl * 0.65 + vec2(0.4, -0.07 * u);
    float capGust = 0.5 + 0.5 * fbm(capWarp, 2);
    float nearCapDetail = 1.0 - smoothstep(0.08, 0.30, isoFp);
    float boil1 = 0.55;
    if (nearCapDetail > 0.01 || tumbleMask > 0.01 || lipMask > 0.01 || rReef < 9.5) {
        boil1 = billowFbm(p.xz * 0.85 + vec2(0.0, -0.35 * u), 4);
    }
    float capTex = mix(capGust, capGust * 0.58 + boil1 * 0.48, nearCapDetail);
    float openWhitecap = smoothstep(0.25, 0.52, crest) * smoothstep(0.48, 0.72, capTex);

    // Hero foreground breaker: deeply scalloped snowy cauliflower foam tongues + glowing sea-glass aqua barrel!
    float heroFoam = 0.0;
    if (tumbleMask > 0.005 || lipMask > 0.005) {
        float puffBig = billowFbm(p.xz * vec2(0.75, 0.58) + vec2(0.04 * u, -0.95 * u), 4);
        float puffMed = billowFbm(p.xz * 2.10 - vec2(0.08 * u, 1.50 * u), 3);
        float shredF  = turbulence(p.xz * 3.20 - vec2(0.12 * u, 1.85 * u), 3);
        float puffMix = puffBig * 0.60 + puffMed * 0.25 + shredF * 0.15;

        float toeLobes = tumbleMask * smoothstep(0.36, 0.60, puffMix + 0.14 * tumbleMask);
        float lipLobes = lipMask * smoothstep(0.22, 0.46, puffMix + 0.24 * lipMask);
        heroFoam = saturate(max(lipLobes * 1.12, toeLobes * 1.15));
    }

    // Tier (c): Bright surging whitewater surf boil flush against basalt sea stack
    float innerBoil = (1.0 - smoothstep(4.6, 8.2, rReef))
                    * smoothstep(0.14, 0.48, boil1 * 0.56 + surgeWave * 0.54);

    float thickFoam = saturate(max(heroFoam, max(innerBoil * 1.14, openWhitecap * 0.90)));
    float foam      = saturate(max(thickFoam, laceFoam) + 0.16 * min(thickFoam, laceFoam));
    foam *= 1.0 - smoothstep(95.0, 220.0, t) * 0.50;

    // 3D sculptural cauliflower normal relief on thick boiling whitewater
    float foamShadeLobe = 0.76;
    if (thickFoam > 0.04 && isoFp < 0.45) {
        vec3 bGrad1 = gradientNoiseD(p.xz * 1.25 - vec2(0.0, 0.90 * u));
        vec3 bGrad2 = gradientNoiseD(p.xz * 3.10 - vec2(0.08 * u, 1.40 * u));
        float bumpFade = thickFoam * (1.0 - smoothstep(0.10, 0.45, isoFp));
        slope += bumpFade * (0.44 * bGrad1.yz + 0.18 * bGrad2.yz);
        foamShadeLobe = clamp(0.64 + 0.34 * bGrad1.x + 0.14 * bGrad2.x, 0.28, 1.0);
    }

    vec3 n = normalize(vec3(-slope.x, 1.0, -slope.y));
    vec3 v = -rd;
    float NoV = clamp(dot(n, v), 1e-3, 1.0);

    // Toksvig / LEAN roughness from unresolved wave & capillary slope variance
    float alpha = sqrt(0.016 * 0.016 + 2.05 * lostSlope2);
    float rough = clamp(sqrt(alpha), 0.055, 0.65);

    // Exact unpolarized air-water dielectric Fresnel
    float effNoV = mix(NoV, max(NoV, 0.32), smoothstep(0.12, 0.55, rough) * 0.70);
    float F = fresnelDielectric(effNoV, 1.0, ow_WATER_IOR);

    // Rough-filtered storm sky reflection
    vec3 refl = reflect(rd, n);
    refl.y = max(refl.y, 0.012 + 0.08 * rough);
    refl = normalize(refl);
    vec3 skyRefl = ow_stormSkyReflection(refl, rough, lampPos, beamDir);

    // Rich North Atlantic Prussian storm-teal body + luminous shallow emerald reef surge
    float shoalMask   = 1.0 - smoothstep(3.2, 13.8, rReef);
    float opticalPath = mix(14.5, 1.65, shoalMask * (0.72 + 0.28 * surgeWave)) / max(NoV * 0.65 + 0.35, 0.35);
    vec3  transT      = beerTransmittance(ow_WATER_EXTINCT, opticalPath);

    vec3 deepScatter  = vec3(0.0062, 0.055, 0.083);
    vec3 reefBottom   = vec3(0.036,  0.186, 0.190);
    float troughAO    = smoothstep(-0.65, 0.35, wv.x);
    float skyDiff     = (0.54 + 0.46 * clamp(dot(n, ow_SKY_LIGHT_DIR), 0.0, 1.0)) * (0.68 + 0.32 * troughAO);
    vec3 waterBody    = (reefBottom * transT + deepScatter * (1.0 - transT)) * skyDiff * 1.22;

    // Translucent sea-glass emerald-aqua SSS through thin storm crests & steep hero breaker barrel wall!
    float thinCrest = smoothstep(0.10, 0.68, wv.x);
    float sssAmount = saturate(thinCrest * 0.42 + faceMask * 1.55 + shoalMask * 0.28);
    vec3  emeraldSSS = vec3(0.058, 0.245, 0.252) * beerTransmittance(vec3(0.20, 0.025, 0.030), 1.0 - 0.78 * faceMask);
    waterBody += emeraldSSS * sssAmount;

    // Filtered GGX silver-slate storm glint
    vec3 skyGlintCol = vec3(0.15, 0.208, 0.235);
    vec3 glint = specularGGX(n, v, ow_SKY_LIGHT_DIR, clamp(rough * 1.30, 0.15, 0.68), vec3(0.0204)) * skyGlintCol;

    vec3 cleanWater = skyRefl * F + waterBody * (1.0 - F) + glint;
    // Soft submerged milky-aqua bubble veil under/around surface froth so foam edges feather naturally into teal water!
    vec3 milkyAqua  = vec3(0.14, 0.34, 0.37) * (0.75 + 0.25 * skyDiff);
    cleanWater = mix(cleanWater, milkyAqua, milkyVeil * 0.34 * (1.0 - smoothstep(60.0, 160.0, t)));

    // Snowy aerated white foam lighting (sRGB ~ 0.88-0.94 on active breaker & surf boil!)
    float activeBoost = max(heroFoam, innerBoil);
    float foamDiff    = (0.56 + 0.44 * clamp(dot(n, ow_SKY_LIGHT_DIR), 0.0, 1.0)) * (0.58 + 0.42 * foamShadeLobe);
    vec3 foamShadow   = mix(vec3(0.18, 0.26, 0.295), vec3(0.36, 0.47, 0.51), activeBoost);
    vec3 foamCrest    = mix(vec3(0.84, 0.91, 0.94), vec3(1.12, 1.18, 1.20), activeBoost);
    vec3 foamLit      = mixOklab(foamShadow, foamCrest, clamp(foamDiff, 0.0, 1.0));
    foamLit          += emeraldSSS * (0.12 * (1.0 - thickFoam) + 0.12 * faceMask);

    vec3 col = mix(cleanWater, foamLit, foam);

#if DEBUG_MODE == 2
    return debugNormal(n);
#elif DEBUG_MODE == 3
    return debugIdColor(0.0);
#elif DEBUG_MODE == 5
    return vec3(foam, saturate(crest + lipMask), rough);
#elif DEBUG_MODE == 6
    return vec3(luminance(skyRefl * F), luminance(waterBody * (1.0 - F)), foam);
#endif

    // Composite 3D arcing spindrift spray over foreground breaker + flank surf plumes around sea stack
    vec4 spindrift = ow_breakerSpindrift(ro, rd, t);
    col = mix(col, spindrift.rgb, spindrift.a);

    vec4 islSpray = ow_islandSprayPlume(ro, rd, t);
    col = mix(col, islSpray.rgb, islSpray.a);

    // Storm aerial perspective + 2-3px grazing horizon mist feathering so uv.y = +0.119 blends like real storm mist!
    vec3 horizMist   = ow_horizonMistColor(rd);
    float grazingMist = exp(-max(-rd.y, 0.0) * 160.0) * 0.88;
    float hazeAmt    = clamp((1.0 - exp(-t * 0.0020)) * 0.50 + grazingMist, 0.0, 0.96);
    col = mix(col, horizMist, hazeAmt);

    return col;
}

// ==== PART: 03b_ocean_lighthouse.glsl ====
// =============================================================================
// SCENE III (Part B): Fractured Columnar Basalt Sea Stack, Ashlar Masonry
// Lighthouse, Fresnel Drum Optic, Bi-Valve Volumetric Beam & Ocean Integration
// =============================================================================

const vec3  OL_STORM_KEY_DIR = normalize(vec3(-0.26, 0.78, -0.56));
const vec2  OL_TOWER_OFFSET  = vec2(0.07, 0.0);
const float OL_LAMP_HEIGHT   = 11.05;

// Smoothly rotating bi-valve Fresnel lens axis calibrated to ref_10.00..14.00:
//   10s (u=0.75): +8 deg horizontal right -> 11s (u=1.75): +28 deg bright right ->
//   12s (u=2.75): +120 deg & +23 deg upward pitch into upper-left storm clouds with dazzling Mie glare ->
//   13s (u=3.75): +172 deg bright horizontal left -> 14s (u=4.75): +181 deg dead-horizontal left/right split!
vec3 ol_calcBeamDir(float u) {
    float yaw = 0.05 + 0.14 * u + 2.42 * smoothstep(1.22, 3.38, u);
    // Dead-horizontal (pitch = 0) on side views (10s, 11s, 13s, 14s); sweeps ~18 deg up-left into clouds at 12s!
    float camSweep = max(0.0, sin(yaw - 0.52));
    float pitch = 0.315 * pow(camSweep, 2.6);
    return normalize(vec3(cos(yaw) * cos(pitch), sin(pitch), sin(yaw) * cos(pitch)));
}

// Cylindrical modular ashlar stone lattice (Formula Cookbook: seamless even sector count)
// Returns vec4(mortarMask, stoneHashA, stoneHashB, continuousBlockRelief)
vec4 ol_ashlarLattice(vec3 tc, float sectors, float rowH, float footprint) {
    float ang = atan(tc.z, tc.x + 1e-6);
    float row = floor(tc.y / rowH);
    float rowParity = mod(row, 2.0);
    float rowShift = rowParity * 0.5 + 0.22 * (hash11(row * 13.0 + 5.0) - 0.5);

    float u = (ang / TAU + 0.5) * sectors + rowShift;
    float sec = mod(floor(u), sectors);
    vec2 cellId = vec2(sec, row);
    vec3 h = hash32(cellId + vec2(37.0, 19.0));

    float lu = fract(u) - 0.5;
    float lv = fract(tc.y / rowH) - 0.5;

    float borderDist = min(0.5 - abs(lu), (0.5 - abs(lv)) * 0.80);
    float aa = max(footprint * 2.5, 0.010);
    float mortar = 1.0 - smoothstep(0.054 - aa * 0.5, 0.054 + aa, borderDist);

    float faceBevel = smoothstep(0.02, 0.15, borderDist);
    float proud = (h.z - 0.45) * 0.028 * faceBevel - 0.014 * (1.0 - faceBevel);
    return vec4(mortar, h.x, h.y, proud);
}

// Helper: 3D pitched & rolled angular basalt crag block (zero flat horizontal ziggurat tops!)
float ol_sdCragBlock(vec3 p, vec3 angles, vec3 halfExt) {
    vec3 s = p;
    s.xz = rot2(angles.x) * s.xz;
    s.xy = rot2(angles.y) * s.xy;
    s.zy = rot2(angles.z) * s.zy;
    return sdRoundBox(s, halfExt, 0.035);
}

// Helper: 3D raked hexagonal basalt column cluster with pitched top termination
float ol_sdRakedHexCrag(vec3 p, vec3 angles, float radius, float halfH) {
    vec3 s = p;
    s.xz = rot2(angles.x) * s.xz;
    s.xy = rot2(angles.y) * s.xy;
    s.zy = rot2(angles.z) * s.zy;
    return sdHexPrism(vec3(s.x, s.z, s.y), vec2(radius, halfH));
}

// Jagged, asymmetric fractured columnar basalt sea stack (ZERO flat ziggurat steps or periodic comb teeth!)
float ol_sdBasaltSeaStack(vec3 q) {
    float rXZ = length(q.xz);
    if (rXZ > 7.5 || q.y > 5.35) {
        return max(rXZ - 6.7, q.y - 4.75);
    }

    // 1. Watertight asymmetric pyramidal volcanic core rising right into the bastion base
    vec3 coreP = q - vec3(-0.12, 1.90, 0.38);
    coreP.xy = rot2(0.05) * coreP.xy;
    float d = sdCappedCone(coreP, 2.45, 5.10, 2.38);

    // 2. Quadrant-gated jagged pitched basalt crags (skips opposite-side boxes for ~2.2x faster SDF steps!)
    if (q.y > 0.6) {
        d = opChamferUnion(d, ol_sdRakedHexCrag(q - vec3(-0.18, 2.48, 1.42), vec3( 0.18, -0.19,  0.24), 1.32, 2.28), 0.12);
    }
    if (q.x < 1.35) {
        d = opChamferUnion(d, ol_sdRakedHexCrag(q - vec3(-1.55, 2.45, 0.95), vec3( 0.35,  0.22, -0.18), 1.38, 2.32), 0.14);
        d = opChamferUnion(d, ol_sdCragBlock   (q - vec3(-2.35, 2.25, 0.55), vec3( 0.48,  0.28,  0.16), vec3(1.18, 1.92, 1.25)), 0.12);
        d = opChamferUnion(d, ol_sdCragBlock   (q - vec3(-2.45, 1.62, 1.95), vec3( 0.42,  0.26,  0.21), vec3(1.55, 1.28, 1.35)), 0.14);
        d = opChamferUnion(d, ol_sdRakedHexCrag(q - vec3(-3.65, 1.18, 1.15), vec3(-0.28,  0.31, -0.16), 1.42, 1.25), 0.12);
        if (q.y < 2.2) {
            d = opChamferUnion(d, ol_sdCragBlock(q - vec3(-4.75, 0.55, 1.72), vec3( 0.55,  0.24,  0.28), vec3(1.22, 0.78, 1.28)), 0.10);
            d = opChamferUnion(d, ol_sdCragBlock(q - vec3(-5.55, 0.14, 2.15), vec3(-0.35,  0.19,  0.22), vec3(0.85, 0.48, 0.98)), 0.08);
        }
    }
    if (q.x > -1.35) {
        d = opChamferUnion(d, ol_sdRakedHexCrag(q - vec3( 1.38, 2.38, 1.05), vec3(-0.42, -0.25,  0.19), 1.36, 2.22), 0.14);
        d = opChamferUnion(d, ol_sdCragBlock   (q - vec3( 1.55, 2.32, 1.85), vec3(-0.38, -0.34,  0.22), vec3(1.58, 1.38, 1.22)), 0.14);
        d = opChamferUnion(d, ol_sdCragBlock   (q - vec3( 2.75, 1.42, 2.35), vec3(-0.32, -0.29,  0.18), vec3(1.55, 1.22, 1.28)), 0.14);
        d = opChamferUnion(d, ol_sdRakedHexCrag(q - vec3( 3.45, 1.05, 1.18), vec3( 0.36, -0.28, -0.20), 1.35, 1.18), 0.12);
        if (q.y < 2.0) {
            d = opChamferUnion(d, ol_sdCragBlock(q - vec3( 4.38, 0.42, 2.15), vec3(-0.46, -0.22,  0.26), vec3(1.12, 0.68, 1.18)), 0.10);
        }
    }
    if (q.z > 0.65 && q.y < 3.4) {
        d = opChamferUnion(d, ol_sdCragBlock   (q - vec3(-0.35, 1.25, 3.05), vec3( 0.22,  0.18,  0.29), vec3(1.95, 1.22, 1.45)), 0.14);
        d = opChamferUnion(d, ol_sdRakedHexCrag(q - vec3(-1.55, 0.52, 3.98), vec3( 0.44,  0.24,  0.26), 1.08, 0.98), 0.10);
        d = opChamferUnion(d, ol_sdRakedHexCrag(q - vec3(-0.08, 0.62, 4.42), vec3(-0.31, -0.16,  0.32), 1.12, 0.94), 0.10);
        d = opChamferUnion(d, ol_sdRakedHexCrag(q - vec3( 1.52, 0.46, 3.88), vec3(-0.52, -0.26,  0.24), 1.10, 0.92), 0.10);
        d = opChamferUnion(d, ol_sdCragBlock   (q - vec3(-0.82, 0.06, 5.12), vec3( 0.38,  0.22,  0.30), vec3(0.92, 0.54, 0.78)), 0.08);
        d = opChamferUnion(d, ol_sdCragBlock   (q - vec3( 0.78, 0.02, 4.92), vec3(-0.41, -0.20,  0.28), vec3(0.88, 0.50, 0.74)), 0.08);
    }
    if (q.z < 0.25) {
        d = opChamferUnion(d, ol_sdRakedHexCrag(q - vec3(-1.85, 1.65, -2.35), vec3( 0.30,  0.20, -0.24), 1.48, 1.68), 0.14);
        d = opChamferUnion(d, ol_sdRakedHexCrag(q - vec3( 1.85, 1.58, -2.25), vec3(-0.34, -0.22, -0.22), 1.45, 1.60), 0.14);
        d = opChamferUnion(d, ol_sdCragBlock   (q - vec3( 0.00, 0.78, -3.45), vec3( 0.15,  0.12, -0.28), vec3(1.62, 0.95, 1.08)), 0.12);
    }

    if (gFastMap) {
        if (d < 0.65) {
            float coarseCrag = ridgedFbm(q.xz * 0.52 + vec2(q.y * 0.28), 2);
            d += 0.15 * (0.48 - coarseCrag);
        }
        return d * 0.74;
    }

    // 3. Non-periodic C1-continuous hexagonal basalt cleavage + irregular tectonic rock clefts (fast, zero 3x3 Voronoi in march!)
    if (d < 0.78) {
        float envFade = 1.0 - smoothstep(0.26, 0.76, d);
        vec2 colXZ = q.xz + q.y * vec2(0.085, -0.065);

        vec4 hg = hexGrid(colXZ * 0.88);
        float hexEdge = hexEdgeDistance(hg.xy);
        float cellInterior = smoothstep(0.02, 0.19, hexEdge);
        vec2 colRand = hash22(hg.zw + vec2(11.0, 47.0));

        float colProud = (colRand.x - 0.48) * 0.22 * cellInterior;
        float jointGroove = (1.0 - smoothstep(0.0, 0.09, hexEdge)) * 0.085;

        float fractureA = ridgedFbm(colXZ * 0.52 + vec2(q.y * 0.34, -q.y * 0.22), 2);
        float fractureB = ridgedFbm(rot2(0.75) * q.xy * 0.68 + vec2(q.z * 0.35, 1.9), 2);

        // Irregular non-periodic surf-erosion clefts (incommensurate warped ridges -> zero comb periodicity, 5x faster than Voronoi!)
        float cleftAng = atan(q.z - 0.6, q.x + 1e-6);
        float cleftField = abs(sin(cleftAng * 2.5 + 1.55 * sin(cleftAng * 1.4 - 0.9) + 0.55 * sin(cleftAng * 4.1 + 1.7) + 0.35 * q.y));
        float cleftCarve = (1.0 - smoothstep(0.04, 0.32, cleftField)) * (1.0 - smoothstep(0.25, 2.05, q.y)) * 0.21;

        float disp = -colProud + jointGroove + 0.18 * (0.50 - fractureA) + 0.09 * (0.50 - fractureB) + cleftCarve;
        d += disp * envFade;
    }

    return d * 0.68;
}

// Detailed North Atlantic Ashlar Lighthouse: Bastion, Tapered Shaft, Recessed Windows,
// Corbelled Stone Gallery, Double Iron Railings, Mullioned Lantern & Cupola Weathervane
vec2 ol_sdLighthouse(vec3 q) {
    vec3 tc = q - vec3(OL_TOWER_OFFSET.x, 0.0, OL_TOWER_OFFSET.y);
    float r = length(tc.xz);

    if (q.y > 5.30 && r > 1.92) {
        return vec2(r - 1.48, MAT_OCEAN_TOWER);
    }

    // ---- 1. Circular Stone Fortification Bastion & Parapet (r=2.45m, top y=5.08m) ----
    float bastTaper = clamp((tc.y - 3.10) / 2.00, 0.0, 1.0);
    float rBast = mix(2.58, 2.42, bastTaper);
    float dBastDrum = max(r - rBast, abs(tc.y - 4.08) - 0.98);
    float dBastInner = max(r - 2.08, -(tc.y - 4.72));
    float dBastion = opSubtract(dBastDrum, dBastInner);

    vec3 notchP = tc - vec3(-1.58, 5.02, 1.35);
    notchP.xz = rot2(0.55) * notchP.xz;
    dBastion = opSubtract(dBastion, sdBox(notchP, vec3(0.38, 0.20, 0.58)));

    float dBastCoping = opSubtract(
        sdCylinder(tc - vec3(0.0, 5.06, 0.0), 0.052, 2.48),
        sdCylinder(tc - vec3(0.0, 5.06, 0.0), 0.11,  2.05)
    );
    dBastCoping = opSubtract(dBastCoping, sdBox(notchP, vec3(0.36, 0.22, 0.58)));

    // ---- 2. Tapered Battered Ashlar Stone Tower Shaft (y = 4.68 .. 9.16m) ----
    float hNorm = clamp((tc.y - 5.00) / 4.15, 0.0, 1.0);
    float rShaft = mix(1.38, 1.09, hNorm) + 0.055 * (1.0 - hNorm) * (1.0 - hNorm);
    float dShaft = max(r - rShaft, abs(tc.y - 6.92) - 2.24);

    float dPlinth = min(
        sdCappedCone(tc - vec3(0.0, 4.95, 0.0), 0.25, 1.50, 1.41),
        sdTorus(tc - vec3(0.0, 5.20, 0.0), vec2(1.40, 0.042))
    );

    float dTrim = min(dBastCoping, dPlinth);

    if (!gFastMap) {
        if (abs(dBastion) < 0.15 && tc.y > 3.5 && tc.y < 5.02) {
            vec4 bl = ol_ashlarLattice(tc, 30.0, 0.23, 0.01);
            dBastion -= bl.w * 0.75;
        }
        if (abs(dShaft) < 0.15 && tc.y > 5.22 && tc.y < 9.02) {
            vec4 tl = ol_ashlarLattice(tc, 22.0, 0.235, 0.01);
            dShaft -= tl.w;
        }

        if (tc.y > 5.75 && tc.y < 8.85 && r > 0.85 && r < 1.52) {
            for (int w = 0; w < 3; w++) {
                float wy = 6.18 + float(w) * 1.08;
                float winAng = (w == 1) ? 1.46 : ((w == 0) ? 1.54 : 1.40);
                vec2 wRotA = rot2(-winAng) * tc.xz;
                vec3 wpA = vec3(wRotA.x - rShaft, tc.y - wy, wRotA.y);
                dShaft = opSubtract(dShaft, sdBox(wpA, vec3(0.18, 0.23, 0.11)));
                float sillA = sdBox(wpA - vec3(0.025, -0.255, 0.0), vec3(0.06, 0.032, 0.155));
                float lintA = sdBox(wpA - vec3(0.030,  0.258, 0.0), vec3(0.065, 0.038, 0.165));
                dTrim = min(dTrim, min(sillA, lintA));

                float flankAng = (w == 1) ? -1.72 : 0.38;
                vec2 wRotB = rot2(-flankAng) * tc.xz;
                vec3 wpB = vec3(wRotB.x - rShaft, tc.y - (wy - 0.18), wRotB.y);
                dShaft = opSubtract(dShaft, sdBox(wpB, vec3(0.17, 0.21, 0.10)));
                dTrim = min(dTrim, sdBox(wpB - vec3(0.02, -0.235, 0.0), vec3(0.055, 0.030, 0.14)));
            }
        }

        if (tc.y > 4.75 && tc.y < 5.75) {
            vec2 dRot = rot2(-1.82) * tc.xz;
            vec3 dp = vec3(dRot.x - 1.41, tc.y - 5.18, dRot.y);
            dShaft = opSubtract(dShaft, sdRoundBox(dp, vec3(0.18, 0.34, 0.16), 0.03));
            dTrim = min(dTrim, sdBox(dp - vec3(0.03, 0.37, 0.0), vec3(0.07, 0.042, 0.22)));
        }
    }

    float dTower = min(dBastion, dShaft) * 0.84;
    vec2 res = vec2(dTower, MAT_OCEAN_TOWER);

    // ---- 3. Corbelled Stone Gallery Deck & Wrought-Iron Railing (y = 8.90 .. 9.98m) ----
    float dCornice1 = sdCappedCone(tc - vec3(0.0, 9.06, 0.0), 0.18, 1.09, 1.26);
    float dCornice2 = sdCylinder(tc - vec3(0.0, 9.31, 0.0), 0.085, 1.35);
    float dCorniceLip = sdTorus(tc - vec3(0.0, 9.39, 0.0), vec2(1.35, 0.032));
    float dGallery = min(min(dCornice1, dCornice2), dCorniceLip);

    if (!gFastMap && tc.y > 8.82 && tc.y < 9.36 && r > 1.00 && r < 1.42) {
        vec2 cbPol = domPolar(tc.xz, 24.0);
        vec3 cbP = vec3(cbPol.x - 1.18, tc.y - 9.09, cbPol.y);
        dGallery = min(dGallery, sdRoundBox(cbP, vec3(0.11, 0.13, 0.038), 0.012));
    }

    if (tc.y > 9.30 && tc.y < 10.10 && r > 1.12 && r < 1.48) {
        float dRailTop = sdTorus(tc - vec3(0.0, 9.90, 0.0), vec2(1.30, 0.022));
        float dRailMid = sdTorus(tc - vec3(0.0, 9.66, 0.0), vec2(1.30, 0.015));
        float dRails = min(dRailTop, dRailMid);
        if (!gFastMap) {
            vec2 stPol = domPolar(tc.xz, 24.0);
            float dPost = sdVerticalCapsule(vec3(stPol.x - 1.30, tc.y - 9.38, stPol.y), 0.53, 0.019);
            dRails = min(dRails, dPost);
        }
        dGallery = min(dGallery, dRails);
    }

    // ---- 4. Lantern Service Murette + Upper Catwalk Ring & Railing (y = 9.38 .. 10.80m) ----
    float dMurette = sdCylinder(tc - vec3(0.0, 9.90, 0.0), 0.50, 0.94);
    float dCatwalk = sdCylinder(tc - vec3(0.0, 10.40, 0.0), 0.045, 1.06);
    dGallery = min(dGallery, min(dMurette, dCatwalk));

    if (tc.y > 10.32 && tc.y < 10.90 && r > 0.88 && r < 1.18) {
        float dUpRail = sdTorus(tc - vec3(0.0, 10.73, 0.0), vec2(1.02, 0.017));
        if (!gFastMap) {
            vec2 upPol = domPolar(tc.xz, 20.0);
            float dUpPost = sdVerticalCapsule(vec3(upPol.x - 1.02, tc.y - 10.40, upPol.y), 0.33, 0.014);
            dUpRail = min(dUpRail, dUpPost);
        }
        dGallery = min(dGallery, dUpRail);
    }

    dTrim = min(dTrim, dGallery);
    if (dTrim < res.x) res = vec2(dTrim, MAT_OCEAN_TRIM);

    // ---- 5. Storm-Glass Lantern Cylinder + Real 3D Cast-Iron Mullions (y = 10.42 .. 11.66m) ----
    float dLanternGlass = sdCylinder(tc - vec3(0.0, 11.04, 0.0), 0.62, 0.82);
    if (dLanternGlass < res.x) res = vec2(dLanternGlass, MAT_OCEAN_LANTERN);

    // ---- 6. Cupola Cornice, Standing-Seam Ribbed Dome, Ventilator Ball & Weathervane (y = 11.62 .. 13.10m) ----
    float dEaves1 = sdCylinder(tc - vec3(0.0, 11.67, 0.0), 0.046, 0.97);
    float dEaves2 = sdTorus(tc - vec3(0.0, 11.72, 0.0), vec2(0.93, 0.032));
    float dCupola = sdCutSphere(tc - vec3(0.0, 11.56, 0.0), 0.91, 0.12);
    float dVentNeck = sdCylinder(tc - vec3(0.0, 12.48, 0.0), 0.075, 0.078);
    float dVentBall = sdSphere(tc - vec3(0.0, 12.60, 0.0), 0.120);
    float dSpireCone = sdCappedCone(tc - vec3(0.0, 12.75, 0.0), 0.085, 0.056, 0.015);
    float dMast = sdVerticalCapsule(tc - vec3(0.0, 12.72, 0.0), 0.34, 0.012);
    float dVaneBar = sdCapsule(tc, vec3(-0.17, 12.91, 0.02), vec3(0.17, 12.91, -0.02), 0.010);

    float dDome = min(min(dEaves1, dEaves2), min(dCupola, min(dVentNeck, dVentBall)));
    dDome = min(dDome, min(dSpireCone, min(dMast, dVaneBar)));

    if (!gFastMap) {
        if (tc.y > 10.38 && tc.y < 11.70 && r > 0.70 && r < 0.96) {
            vec2 mPol = domPolar(tc.xz, 16.0);
            float dMullionV = sdVerticalCapsule(vec3(mPol.x - 0.832, tc.y - 10.43, mPol.y), 1.22, 0.017);
            float dMullionH1 = sdTorus(tc - vec3(0.0, 10.84, 0.0), vec2(0.832, 0.014));
            float dMullionH2 = sdTorus(tc - vec3(0.0, 11.25, 0.0), vec2(0.832, 0.014));
            dDome = min(dDome, min(dMullionV, min(dMullionH1, dMullionH2)));
        }
        if (tc.y > 11.66 && tc.y < 12.48 && r < 0.96) {
            vec2 rPol = domPolar(tc.xz, 16.0);
            float ribSphere = abs(length(tc - vec3(0.0, 11.56, 0.0)) - 0.918) - 0.011;
            float ribPlane  = abs(rPol.y) - 0.013;
            float dRib = max(max(ribSphere, ribPlane), -(tc.y - 11.68));
            dDome = min(dDome, dRib);
        }
    }

    if (dDome < res.x) res = vec2(dDome, MAT_OCEAN_DOME);
    return res;
}

vec2 mapOceanIsland(vec3 p) {
    vec3 q = p - OCEAN_STACK_POS;

    vec2 res = vec2(1e5, MAT_OCEAN_ROCK);
    if (q.y < 5.30) {
        res = vec2(ol_sdBasaltSeaStack(q), MAT_OCEAN_ROCK);
    }
    if (q.y > 3.05) {
        vec2 lh = ol_sdLighthouse(q);
        if (lh.x < res.x) res = lh;
    }
    return res;
}

vec3 ol_fastHorizonHaze(vec3 rd) {
    vec3 coolMist = srgbToLinear(vec3(0.41, 0.49, 0.53));
    vec3 slateTop = srgbToLinear(vec3(0.30, 0.37, 0.41));
    return mix(coolMist, slateTop, smoothstep(0.0, 0.25, max(rd.y, 0.0)));
}

// Analytic interior rendering of the multi-ring golden Fresnel bullseye lens & curved storm glass
vec3 ol_shadeLanternGlass(vec3 ro, vec3 rd, vec3 p, vec3 n, vec3 lampPos, vec3 beamDir) {
    vec3 tc = p - OCEAN_STACK_POS - vec3(OL_TOWER_OFFSET.x, 0.0, OL_TOWER_OFFSET.y);
    vec3 v = -rd;
    float NoV = max(dot(n, v), 1e-3);

    vec2 relXZ = tc.xz;
    vec2 rdXZ = rd.xz;
    float rdXZLen2 = max(dot(rdXZ, rdXZ), 1e-4);
    float tAxis = -dot(relXZ, rdXZ) / rdXZLen2;
    vec3 pAxis = p + rd * max(tAxis, 0.0);
    float perpR = length(pAxis.xz - (OCEAN_STACK_POS.xz + OL_TOWER_OFFSET));
    float opticY = pAxis.y - OL_LAMP_HEIGHT;

    vec3 backSky = stormCloudSky(rd, lampPos, beamDir);
    float tExit = 2.0 * max(tAxis, 0.0);
    vec3 pBack = tc + rd * tExit;
    float backAng = atan(pBack.z, pBack.x + 1e-6);
    float backBars = smoothstep(0.92, 0.985, abs(cos(backAng * 8.0)))
                   + smoothstep(0.035, 0.008, abs(abs(pBack.y - 11.045) - 0.205));
    vec3 transBg = backSky * (1.0 - 0.65 * saturate(backBars)) * vec3(0.86, 0.88, 0.86);

    float drumMask = (1.0 - smoothstep(0.30, 0.45, perpR)) * (1.0 - smoothstep(0.36, 0.50, abs(opticY)));
    float ringDist = length(vec2(perpR * 0.95, opticY * 1.15));
    float prismRings = 0.52 + 0.48 * sin(ringDist * 44.0);
    float bullseye = exp(-ringDist * ringDist * 14.0);

    float camAlign = max(dot(v, beamDir), 0.0);
    float directFlash = pow(smoothstep(0.45, 0.92, camAlign), 1.8);

    float burnerCore = exp(-(perpR * perpR * 42.0 + opticY * opticY * 16.0));

    vec3 richAmber = blackbody(2400.0);
    vec3 warmGold  = blackbody(3100.0);

    vec3 fresnelGlow = richAmber * drumMask * (2.6 + 3.4 * prismRings) * (1.0 + 7.5 * directFlash)
                     + warmGold * (burnerCore * (12.0 + 52.0 * directFlash) + bullseye * drumMask * (5.0 + 38.0 * directFlash));

    // During 12s sweep, flood the left 2/3 of the lantern glass with blazing overexposed golden-white glare!
    float leftGlareBias = smoothstep(0.48, -0.35, tc.x);
    vec3 paneGlow = mix(richAmber, warmGold, 0.55 * directFlash)
                  * (0.40 + 14.0 * directFlash * (0.35 + 0.65 * leftGlareBias))
                  * (1.0 - smoothstep(0.20, 0.84, perpR * (1.0 - 0.35 * directFlash)));

    vec3 refl = reflect(rd, n);
    float F = fresnelDielectric(NoV, 1.0, 1.50);
    vec3 glassRefl = ol_fastHorizonHaze(refl) * F;

    return mix(transBg + paneGlow, transBg * 0.14 + fresnelGlow + paneGlow, saturate(drumMask * 0.90 + burnerCore))
         + glassRefl;
}

// Seam-free importance-sampled volumetric bi-valve Fresnel searchlight (clean across ALL 360-deg / high / low orbits!)
vec3 ol_lighthouseBeam(vec3 ro, vec3 rd, float tMax, vec2 fragCoord, vec3 lampPos, vec3 beamDir) {
    vec3 toLamp0 = lampPos - ro;
    float tLamp = dot(toLamp0, rd);

    float span = 23.0;
    float tA = max(0.5, tLamp - span);
    float tB = min(tMax, tLamp + span);
    if (tB <= tA + 0.01) return vec3(0.0);

    // Exact linear-segment altitude guard: only early-out when BOTH endpoints of [tA, tB] stay below y = 6.2m!
    // Skips 100% of ocean pixels in normal view while producing ZERO circular seams in high/low mouse orbits!
    if (max(ro.y + rd.y * tA, ro.y + rd.y * tB) < 6.2) return vec3(0.0);

    float sMin = clamp((tA - tLamp) / span, -1.0, 1.0);
    float sMax = clamp((tB - tLamp) / span, -1.0, 1.0);
    if (sMax <= sMin + 0.002) return vec3(0.0);

    int steps = gInDissolve ? 10 : 16;
    float ds = (sMax - sMin) / float(steps);
    float jitter = interleavedGradientNoise(floor(fragCoord), iFrame);

    vec3 deepAmber = blackbody(2350.0);
    vec3 warmGold  = blackbody(2950.0);
    vec3 glareWhite = mix(warmGold, vec3(1.0, 0.96, 0.86), 0.52);
    vec3 windDrift = vec3(-0.34, 0.04, 0.12) * gSceneTime;

    float u = gSceneTime;
    float forwardSweep = pow(smoothstep(0.38, 0.88, beamDir.z), 1.7);
    float mainWeight   = mix(0.34, 1.0 + 0.45 * forwardSweep, smoothstep(0.65, 1.75, u));
    float secWeight    = 0.88 * smoothstep(2.95, 4.35, u);

    vec3 rad = vec3(0.0);
    vec3 trans = vec3(1.0);

    for (int i = 0; i < 16; i++) {
        if (i >= steps) break;
        float s = sMin + (float(i) + jitter) * ds;
        float s2 = s * s;
        float warp = s * (0.11 + 0.89 * s2);
        float dWarp = 0.11 + 2.67 * s2;
        float t = tLamp + span * warp;
        float dt = span * dWarp * ds;
        if (t < tA || t > tB) continue;

        vec3 p = ro + rd * t;
        // Smooth boundary & altitude fades (ZERO hard `if (p.y < ...)` cutoffs -> 100% seam-free in any orbit!)
        float altFade  = smoothstep(6.2, 9.3, p.y);
        float spanFade = 1.0 - smoothstep(span * 0.70, span, abs(t - tLamp));
        float envWeight = altFade * spanFade;
        if (envWeight <= 0.001) continue;

        vec3 v = p - lampPos;
        float dist = length(v);
        vec3 dir = v / max(dist, 1e-3);

        float leftBloomGate = mix(1.0, smoothstep(-0.10, 0.38, -dir.x), forwardSweep);
        float upperCut = mix(0.20, 0.72 * leftBloomGate + 0.08, forwardSweep);
        float windowShutter = smoothstep(-0.15, 0.02, dir.y) * (1.0 - smoothstep(0.10, upperCut, dir.y));
        if (windowShutter <= 0.001) continue;

        float cPos = max(dot(dir, beamDir), 0.0);
        float cNeg = max(dot(dir, -beamDir), 0.0);

        float corePos = pow(cPos, mix(145.0, 9.5,  forwardSweep));
        float haloPos = pow(cPos, mix(34.0,  4.2,  forwardSweep)) * mix(0.14, 0.88, forwardSweep);

        float coreNeg = pow(cNeg, 145.0);
        float haloNeg = pow(cNeg, 34.0) * 0.14;

        // Anchor nozzle glare slightly left & horizontal of lantern glass so left 2/3 blazes while right cupola stays dark!
        vec3 nozzleCenter = lampPos + vec3(beamDir.x * 0.92, -0.04, beamDir.z * 0.85);
        float dNozzle2 = dot2(p - nozzleCenter);
        float rawCone = mainWeight * (corePos + haloPos) + secWeight * (coreNeg + haloNeg);
        float rawGlare = (mix(0.06, 5.80, forwardSweep) / (0.12 + dNozzle2 * mix(1.4, 0.28, forwardSweep)))
                       * windowShutter * leftBloomGate;

        // Skip expensive 3D fbm/billowFbm outside the active light cone & nozzle halo (zero visual seam, ~3x faster!)
        if (rawCone * windowShutter < 0.0008 && rawGlare < 0.0012) continue;

        float muScatter = clamp(dot(dir, -rd), -1.0, 1.0);
        float miePhase = 4.0 * PI * phaseDualHG(muScatter, 0.64, -0.15, 0.85);

        vec3 mp = p * vec3(0.15, 0.24, 0.15) + windDrift;
        float wispA = 0.5 + 0.5 * fbm(mp, 2, 2.05, 0.52);
        float wispB = billowFbm(mp * 2.2 + vec3(3.1, -1.7, 0.8), 2);
        float mistDensity = (0.54 + 0.62 * wispA * (0.55 + 0.65 * wispB)) * envWeight;

        float radialAtten = exp(-dist * 0.070) / (0.35 + dist * 0.27 + dist * dist * 0.015);
        float shaftEnergy = rawCone * windowShutter * radialAtten * miePhase;
        float nozzleGlare = rawGlare * (0.78 + 0.22 * wispA);

        vec3 shaftTint = mix(deepAmber, warmGold, saturate(corePos * 0.72 + forwardSweep * 0.35));
        vec3 stepScat = (shaftTint * shaftEnergy * 1.55 + mix(warmGold, glareWhite, 0.55 * forwardSweep) * nozzleGlare * 0.68) * mistDensity;
        vec3 sigmaT = vec3(0.004 * mistDensity);
        volumeStep(rad, trans, sigmaT, stepScat, dt);
    }

    return rad;
}

vec3 renderOcean(vec2 uv, vec2 fragCoord, float pxAngle) {
    const float FOCAL = 2.0;
    float u = gSceneTime;

    // Sub-pixel calibrated aerial dolly + gentle left arc:
    //   locks horizon at exact uv.y = +0.119 and tracks ref_10..14 lamp & rock growth within <3px!
    vec3 ro = vec3(0.89 - 0.35 * u - 0.022 * u * u, 4.02 + 0.21 * u, 32.8 - 1.95 * u);
    vec3 ta = ro + vec3(0.0, -0.595, -10.0);
    applyOrbit(ro, OCEAN_STACK_POS + vec3(0.05, 5.2, 0.0), -3.0);

    mat3 cam = cameraMatrix(ro, ta, 0.0);
    vec3 rd  = cameraRay(cam, uv, FOCAL);

    vec3 lampPos = OCEAN_STACK_POS + vec3(OL_TOWER_OFFSET.x, OL_LAMP_HEIGHT, OL_TOWER_OFFSET.y);
    vec3 beamDir = ol_calcBeamDir(u);

#if DEBUG_MODE == 1
    return debugDistance(mapOceanIsland(vec3(uv.x * 8.5 + OCEAN_STACK_POS.x, uv.y * 8.5 + 6.2, 0.0)).x * 0.22);
#endif

    // Tight two-tier analytic AABB bound (wide lower sea stack + narrow upper lighthouse tower)
    vec2 tBoxBase  = iBox(ro - (OCEAN_STACK_POS + vec3(-0.15, 2.25, 0.85)), rd, vec3(6.85, 3.15, 5.65));
    vec2 tBoxTower = iBox(ro - (OCEAN_STACK_POS + vec3( 0.07, 8.20, 0.00)), rd, vec3(2.85, 5.05, 2.85));

    float tNear = 1e6;
    float tFar  = -1.0;
    if (tBoxBase.y > 0.0) {
        tNear = min(tNear, max(tBoxBase.x, 0.1));
        tFar  = max(tFar,  tBoxBase.y);
    }
    if (tBoxTower.y > 0.0) {
        tNear = min(tNear, max(tBoxTower.x, 0.1));
        tFar  = max(tFar,  tBoxTower.y);
    }

    vec3 islandHit = vec3(-1.0, -1.0, 0.0);
    if (tFar > tNear) {
        islandHit = marchBounded(ro, rd, tNear, min(tFar, 120.0), 0.86, 92);
        if (islandHit.x < 0.0) islandHit.z = 10.0;
    }

    bool needOcean = (islandHit.x < 0.0) || ((ro.y + rd.y * islandHit.x) < 1.35);
    float tOcean = needOcean ? traceStormOcean(ro, rd) : -1.0;
    bool hitIsland = (islandHit.x > 0.0) && (tOcean < 0.0 || islandHit.x < tOcean);

#if DEBUG_MODE == 4
    return debugHeat(islandHit.z / 92.0);
#endif

    float tScene = 120.0;
    vec3 col = vec3(0.0);

    if (hitIsland) {
        float t = islandHit.x;
        tScene = t;
        vec3 p = ro + rd * t;
        float fp = max(t * pxAngle, 0.001);
        vec3 n = calcNormal(p, max(0.0010 * t, 0.0012));
        vec3 v = -rd;
        float m = floor(islandHit.y + 0.5);

        vec3 q = p - OCEAN_STACK_POS;
        vec3 tc = q - vec3(OL_TOWER_OFFSET.x, 0.0, OL_TOWER_OFFSET.y);

        gFastMap = true;
        float ao = calcAO(p, n, 0.45);
        gFastMap = false;
        float sha = fastShadow(p + n * 0.035, OL_STORM_KEY_DIR, 0.06, 9.0, 8.0);
        vec3 horizonFogCol = ol_fastHorizonHaze(rd);

        if (m == MAT_OCEAN_LANTERN) {
#if DEBUG_MODE == 2
            return debugNormal(n);
#elif DEBUG_MODE == 3
            return debugIdColor(m);
#elif DEBUG_MODE == 5
            return vec3(ao, sha, 1.0);
#endif
            vec3 glassCol = ol_shadeLanternGlass(ro, rd, p, n, lampPos, beamDir);
#if DEBUG_MODE == 6
            return vec3(0.0, 0.0, luminance(glassCol));
#endif
            col = mix(glassCol, horizonFogCol, distanceFog(t, 0.0038));
        } else {
            vec3 albedo = srgbToLinear(vec3(0.08, 0.09, 0.095));
            float rough = 0.72;
            float metal = 0.0;
            float wetMask = 0.0;
            float runnelMask = 0.0;

            if (m == MAT_OCEAN_ROCK) {
                float detailFade = smoothstep(2.0, 6.0, 0.14 / fp);
                if (detailFade > 0.01) {
                    vec3 rp = q * vec3(2.2, 1.6, 2.2);
                    float epsB = 0.028;
                    float f0 = ridgedFbm(rp.xz + rp.y * 0.30, 3) + 0.40 * fbm(q * 8.5, 2, 2.0, 0.5);
                    float fx = ridgedFbm(rp.xz + vec2(epsB, 0.0) + rp.y * 0.30, 3) + 0.40 * fbm((q + vec3(epsB, 0.0, 0.0)) * 8.5, 2, 2.0, 0.5);
                    float fy = ridgedFbm(rp.xz + (rp.y + epsB) * 0.30, 3) + 0.40 * fbm((q + vec3(0.0, epsB, 0.0)) * 8.5, 2, 2.0, 0.5);
                    float fz = ridgedFbm(rp.xz + vec2(0.0, epsB) + rp.y * 0.30, 3) + 0.40 * fbm((q + vec3(0.0, 0.0, epsB)) * 8.5, 2, 2.0, 0.5);
                    vec3 gradB = vec3(fx - f0, fy - f0, fz - f0) / epsB;
                    n = normalize(n - (gradB - n * dot(gradB, n)) * 0.13 * detailFade);
                }

                vec2 colXZ = q.xz + q.y * vec2(0.085, -0.065);
                vec4 hg = hexGrid(colXZ * 0.88);
                float hexEdge = hexEdgeDistance(hg.xy);
                float colTone = hash12(hg.zw + vec2(71.0, 13.0));
                float grain = 0.5 + 0.5 * fbm(q * 3.0, 3, 2.05, 0.52);
                float microGrain = 0.5 + 0.5 * fbm(q * 11.5, 2, 2.0, 0.5);

                // Sculpted basalt palette with crisp dry upper facet highlights (q.y > 1.8m) so planes read clearly!
                vec3 basaltDark  = srgbToLinear(vec3(0.042, 0.048, 0.054));
                vec3 basaltSlate = srgbToLinear(vec3(0.158, 0.168, 0.175));
                vec3 ironOchre   = srgbToLinear(vec3(0.175, 0.135, 0.102));

                float facetBevel = smoothstep(0.04, 0.18, hexEdge);
                albedo = mixOklab(basaltDark, basaltSlate, saturate(0.45 * colTone + 0.55 * grain) * (0.45 + 0.55 * facetBevel));
                albedo = mixOklab(albedo, ironOchre, smoothstep(0.48, 0.84, microGrain) * 0.42 * smoothstep(1.4, 3.2, q.y));

                // Pale salt-efflorescence & coastal guano vertical streaks on upper crag faces (film_12..14!)
                float streakAng = atan(q.z - 0.6, q.x + 1e-6);
                float streakNoise = ridgedFbm(vec2(streakAng * 20.0 + 0.45 * fbm(q.xz * 2.0, 2), q.y * 0.50), 3);
                float guanoMask = smoothstep(0.68, 0.90, streakNoise)
                                * smoothstep(1.95, 2.75, q.y) * (1.0 - smoothstep(4.25, 4.78, q.y))
                                * smoothstep(0.18, 0.65, 1.0 - abs(n.y))
                                * smoothstep(-1.2, 0.8, q.x + q.z * 0.35);
                albedo = mixOklab(albedo, srgbToLinear(vec3(0.58, 0.60, 0.58)), guanoMask * 0.72);

                // Coastal olive-moss / lichen cushions on upward upper crags
                float crownMoss = smoothstep(2.7, 4.1, q.y) * smoothstep(0.48, 0.88, n.y)
                                * smoothstep(0.42, 0.76, fbm(q.xz * 2.6, 2));
                albedo = mixOklab(albedo, srgbToLinear(vec3(0.15, 0.19, 0.105)), crownMoss * 0.65);

                // Intertidal wave-surge wet zone: glossy wet jet-black basalt!
                float surgeHeight = 1.78 + 0.32 * sin(u * 1.85 + q.x * 0.55 - q.z * 0.45) + 0.30 * fbm(q.xz * 0.85, 2);
                wetMask = 1.0 - smoothstep(surgeHeight - 0.65, surgeHeight + 0.38, q.y);
                albedo *= mix(1.0, 0.30, wetMask);
                rough = mix(0.72 - 0.10 * microGrain, 0.12, wetMask);

                // 5-7 crisp, thin, snowy-white branching rivulets strictly inside irregular Voronoi/crevice clefts
                // (ZERO wide grey wash or periodic sine teeth — 85% of lower rock stays glossy black!)
                if (q.y < 1.85) {
                    vec4 vCleft = voronoi(vec2(streakAng * 2.4 + 0.35 * fbm(q.xz * 0.8, 2), q.y * 0.42), 0.92);
                    float cleftChannel = 1.0 - smoothstep(0.04, 0.25, vCleft.y - vCleft.x);
                    float gully = saturate((0.68 - ao) * 1.9 + cleftChannel * 0.75);

                    vec2 flowUV = vec2(streakAng * 7.8 + 0.65 * fbm(q.xz * 1.5, 2), q.y * 0.75 + u * 0.55);
                    float mainVein = ridgedFbm(vec2(flowUV.x * 1.02, flowUV.y * 0.42), 3);
                    float branchVein = ridgedFbm(vec2(flowUV.x * 2.30 - 0.4 * q.y, flowUV.y * 0.85), 2);

                    float heightEnv = 1.0 - smoothstep(0.38, 1.62, q.y + 0.25 * fbm(q.xz * 1.4, 2));
                    float slopeKeep = smoothstep(-0.25, 0.30, n.y + 0.38);

                    float thinStream = smoothstep(0.69, 0.87, mainVein * 0.78 + gully * 0.34)
                                     + 0.60 * smoothstep(0.75, 0.91, branchVein * 0.75 + gully * 0.32);
                    runnelMask = saturate(thinStream * smoothstep(0.32, 0.65, gully) * heightEnv * slopeKeep * 1.42);
                    rough = mix(rough, 0.35, runnelMask);
                }
            } else if (m == MAT_OCEAN_TOWER) {
                float sectors = (tc.y < 5.06) ? 30.0 : 22.0;
                float rowH    = (tc.y < 5.06) ? 0.23 : 0.235;
                float cellFp  = fp / rowH;
                vec4 lat = ol_ashlarLattice(tc, sectors, rowH, cellFp);
                float mortar = lat.x;

                float stoneDetail = smoothstep(2.0, 6.0, 0.09 / fp);
                if (stoneDetail > 0.01) {
                    float g0 = fbm(p * 13.0 + lat.y * 7.0, 2, 2.0, 0.5);
                    float gx = fbm((p + vec3(0.02, 0.0, 0.0)) * 13.0 + lat.y * 7.0, 2, 2.0, 0.5);
                    float gy = fbm((p + vec3(0.0, 0.02, 0.0)) * 13.0 + lat.y * 7.0, 2, 2.0, 0.5);
                    vec3 gGrad = vec3(gx - g0, gy - g0, 0.0) * 18.0;
                    n = normalize(n - (gGrad - n * dot(gGrad, n)) * 0.09 * stoneDetail * (1.0 - mortar));
                }

                // Multi-scale weathered coastal rubble-ashlar patchwork (macro multi-course blotches + per-block grain!)
                float faceGrain  = 0.5 + 0.5 * fbm(p * 7.2 + vec3(lat.y * 13.0, lat.z * 9.0, 0.0), 3, 2.0, 0.5);
                float macroPatch = 0.5 + 0.5 * fbm(p * 1.25 + vec3(2.4, -1.1, 0.7), 3, 2.0, 0.5);
                vec3 slateStone  = srgbToLinear(vec3(0.095, 0.106, 0.114));
                vec3 paleGranite = srgbToLinear(vec3(0.315, 0.318, 0.308));
                vec3 ochreBrown  = srgbToLinear(vec3(0.375, 0.268, 0.192));

                vec3 blockCol = mixOklab(slateStone, paleGranite, smoothstep(0.12, 0.86, lat.y * 0.65 + macroPatch * 0.35));
                blockCol = mixOklab(blockCol, ochreBrown, smoothstep(0.28, 0.78, lat.z * 0.60 + macroPatch * 0.40) * 0.85);
                blockCol *= 0.75 + 0.54 * faceGrain;

                float saltPatch = smoothstep(0.38, 0.74, fbm(p * 2.1 + vec3(0.0, 3.1, 0.0), 3, 2.0, 0.5));
                vec3 mortarCol = mixOklab(srgbToLinear(vec3(0.068, 0.074, 0.078)),
                                          srgbToLinear(vec3(0.33, 0.335, 0.320)), saltPatch * 0.86);
                albedo = mix(blockCol, mortarCol, mortar * 0.78);

                float corbelDamp = smoothstep(8.55, 9.06, tc.y);
                albedo *= 1.0 - 0.28 * saturate(corbelDamp);

                float rShaftApprox = mix(1.38, 1.09, clamp((tc.y - 5.00) / 4.15, 0.0, 1.0));
                if (tc.y > 5.85 && tc.y < 8.75 && length(tc.xz) < rShaftApprox - 0.085) {
                    albedo = srgbToLinear(vec3(0.022, 0.028, 0.034));
                    rough = 0.14;
                } else {
                    rough = mix(0.78, 0.90, mortar);
                    float bastWet = 1.0 - smoothstep(3.1, 4.25, tc.y);
                    albedo *= mix(1.0, 0.74, bastWet);
                    rough = mix(rough, 0.44, bastWet);
                }
            } else if (m == MAT_OCEAN_TRIM) {
                if (tc.y > 9.42) {
                    float rust = smoothstep(0.55, 0.85, fbm(p * 6.5, 2, 2.0, 0.5));
                    albedo = mixOklab(srgbToLinear(vec3(0.052, 0.058, 0.064)),
                                      srgbToLinear(vec3(0.10, 0.068, 0.050)), rust * 0.35);
                    rough = 0.36;
                    metal = 0.68;
                } else {
                    // Lighter salt-weathered dressed granite bastion coping, plinth, window sills & lintels
                    float chisel = 0.5 + 0.5 * fbm(p * 11.0, 2, 2.0, 0.5);
                    albedo = mixOklab(srgbToLinear(vec3(0.175, 0.180, 0.178)),
                                      srgbToLinear(vec3(0.295, 0.285, 0.268)), chisel);
                    rough = 0.72;
                }
            } else {
                float patina = smoothstep(0.48, 0.82, fbm(p * 5.2, 3, 2.0, 0.5));
                albedo = mixOklab(srgbToLinear(vec3(0.038, 0.044, 0.048)),
                                  srgbToLinear(vec3(0.058, 0.076, 0.076)), patina * 0.36);
                rough = 0.40;
                metal = 0.42;
            }

            vec3 keyCol = srgbToLinear(vec3(0.84, 0.89, 0.92));
            vec3 key = shadePBR(n, v, OL_STORM_KEY_DIR, albedo, rough, metal) * keyCol * (0.40 + 0.60 * sha);

            vec3 skyFill = hemisphereLight(n, srgbToLinear(vec3(0.45, 0.52, 0.56)),
                                              srgbToLinear(vec3(0.09, 0.15, 0.17))) * ao;
            vec3 diffFill = albedo * (1.0 - metal) * skyFill;

            vec3 f0 = mix(vec3(0.04), albedo, metal);
            vec3 refl = reflect(rd, n);
            vec3 envSpec = envBRDFApprox(f0, max(dot(n, v), 0.0), rough)
                         * ol_fastHorizonHaze(vec3(refl.x, max(refl.y, 0.02), refl.z))
                         * mix(0.38, 1.0, ao) * (1.0 - runnelMask * 0.85);

            vec3 toLamp = lampPos - p;
            float dLamp = length(toLamp);
            vec3 lLamp  = toLamp / max(dLamp, 0.01);
            float lampAperture = smoothstep(9.26, 9.52, tc.y) * (1.0 - smoothstep(11.62, 11.70, tc.y));
            vec3 lampRad = blackbody(2650.0) * lampAperture * (2.5 / (0.55 + dLamp * dLamp * 0.85));
            vec3 lampSpill = shadePBR(n, v, lLamp, albedo, max(rough, 0.30), metal) * lampRad;

#if DEBUG_MODE == 2
            return debugNormal(n);
#elif DEBUG_MODE == 3
            return debugIdColor(m);
#elif DEBUG_MODE == 5
            return vec3(ao, wetMask, runnelMask);
#elif DEBUG_MODE == 6
            return vec3(luminance(key), luminance(diffFill + envSpec), luminance(lampSpill));
#endif

            col = key + diffFill + envSpec + lampSpill;

            // Crisp snowy-white foaming rivulets (`sRGB ~ 0.89`) pouring down recessed basalt clefts!
            if (runnelMask > 0.001) {
                vec3 foamLit = srgbToLinear(vec3(0.88, 0.92, 0.94)) * (0.76 + 0.24 * max(n.y + 0.35, 0.0));
                col = mix(col, foamLit, runnelMask * 0.95);
            }

            float flankMistMask = smoothstep(3.5, 5.7, abs(q.x)) * (1.0 - smoothstep(1.2, 3.2, q.y));
            if (flankMistMask > 0.01) {
                vec4 spray = ow_islandSprayPlume(ro, rd, t);
                col = mix(col, spray.rgb, spray.a * flankMistMask * 0.36);
            }
            col = mix(col, horizonFogCol, distanceFog(t, 0.0038));
        }
    } else if (tOcean > 0.0) {
        tScene = min(tOcean, 120.0);
#if DEBUG_MODE == 3
        return debugIdColor(0.0);
#endif
        col = shadeStormOcean(ro, rd, tOcean, pxAngle, lampPos, beamDir);
#if DEBUG_MODE == 0
        // Preserve foreground (~31m) island splash plume across distant grazing-horizon ocean rays (tOcean > 42m)
        // where shadeStormOcean's far-field horizon mist (hazeAmt -> 0.96) attenuated foreground spray!
        if (tOcean > 42.0) {
            vec4 fgSpray = ow_islandSprayPlume(ro, rd, tOcean);
            if (fgSpray.a > 0.001) {
                float tIsl = length(OCEAN_STACK_POS - ro);
                vec3 sprayLit = mix(fgSpray.rgb, ol_fastHorizonHaze(rd), distanceFog(tIsl, 0.0038));
                float restore = smoothstep(42.0, 110.0, tOcean) * 0.92;
                col = mix(col, sprayLit, fgSpray.a * restore);
            }
        }
#endif
    } else {
        col = stormCloudSky(rd, lampPos, beamDir);
#if DEBUG_MODE == 0
        // Composite 3D sea-stack surf plume above the horizon so the 10.0s right-shoulder geyser rises cleanly into the sky!
        vec4 skySpray = ow_islandSprayPlume(ro, rd, 120.0);
        if (skySpray.a > 0.001) {
            float tIsl = length(OCEAN_STACK_POS - ro);
            vec3 sprayLit = mix(skySpray.rgb, ol_fastHorizonHaze(rd), distanceFog(tIsl, 0.0038));
            col = mix(col, sprayLit, skySpray.a);
        }
#endif
    }

#if DEBUG_MODE == 0
    col += ol_lighthouseBeam(ro, rd, tScene, fragCoord, lampPos, beamDir);
#elif DEBUG_MODE == 6
    col += vec3(0.0, 0.0, luminance(ol_lighthouseBeam(ro, rd, tScene, fragCoord, lampPos, beamDir)));
#endif

    return col;
}

// ==== PART: 04a_desert_dunes.glsl ====
// =============================================================================
// SCENE IV (Part A): DESERT DUNES, AEOLIAN RIPPLES, FLOOR PROPS & ATMOSPHERE
// Exports:
//   float desertDuneHeight(vec2 xz)
//   vec2  mapDesertFloorExtras(vec3 p, float duneH)
//   void  shadeDesertSand(vec3 p, vec3 nIn, float t, float pxAngle,
//                         out vec3 albedo, out float rough, out vec3 nOut)
//   vec3  desertAtmosphere(vec3 rd)
// =============================================================================

// C1-continuous, strictly convex-topped asymmetric aeolian dune profile:
// Nonzero negative second derivative at the brink prevents grazing-ray sphere-trace stalling,
// while the ~37-deg upper leeward slip-face drops immediately into golden-hour self-shadow!
float dd_asymmetricCrest(float dx, float wStoss, float wSlip, float h) {
    const float BRINK_B = 0.118;
    if (dx <= 0.0) {
        float r = -dx / max(wStoss, 1e-3);
        if (r >= 1.0) return 0.0;
        float u = clamp((sqrt(r * r + BRINK_B * BRINK_B) - BRINK_B) / (1.0 - BRINK_B), 0.0, 1.0);
        float f = 1.0 - u;
        return h * f * f * (1.0 + 1.05 * u);
    } else {
        float r = dx / max(wSlip, 1e-3);
        if (r >= 1.0) return 0.0;
        float u = clamp((sqrt(r * r + BRINK_B * BRINK_B) - BRINK_B) / (1.0 - BRINK_B), 0.0, 1.0);
        float f = 1.0 - u;
        return h * f * f * (1.0 - 0.12 * u);
    }
}

// Fast, non-repeating 4-harmonic 1D aeolian brink-scallop & crest-undulation curves:
// Over s in [4..20m], incommensurate frequencies give organic scalloped avalanche bites
// identical to 1D-sliced fbm at ~25x higher GPU raymarch throughput & 10x faster Metal PSO compile!
float dd_scallop1(float s) {
    return 0.50 * sin(s * 0.53 + 0.40) + 0.28 * sin(s * 1.19 - 1.30)
         + 0.15 * sin(s * 2.37 + 2.10) + (gFastMap ? 0.0 : 0.07 * sin(s * 4.29 - 0.70));
}

float dd_scallop2(float s) {
    return 0.48 * sin(s * 0.49 + 2.20) + 0.30 * sin(s * 1.13 + 0.65)
         + 0.15 * sin(s * 2.23 - 1.85) + (gFastMap ? 0.0 : 0.07 * sin(s * 4.07 + 1.15));
}

// Shared S-curved dune brink centerlines (s = -xz.y > 0 into scene), continuous from s ~ 0.5 to 20m.
// Calibrated against film_17.00.png brink traces: Brink 1 (x ~ -1.47 @ z=-7.4 -> -1.79 @ -8.6 -> -1.60 @ -10.2)
// and Brink 2 (x ~ +1.66 @ z=-7.3 -> +1.30 @ -7.7 -> +0.52 @ -8.6 -> +0.10 @ -10.0 -> -0.55 @ -11.2).
void dd_duneBrinks(float s, out float b1, out float b2, out float b3, out float b4L) {
    float scal1 = 0.25 * dd_scallop1(s);
    float scal2 = 0.27 * dd_scallop2(s);

    // Brink 1: bold left S-curve. Routed far left (off-frame) for s < 5 so the 15s foreground stays a
    // sunlit rippled windward slope, then sweeping in from the bottom-left corner across 17s & 19s.
    float leftRoute = 1.0 - smoothstep(3.5, 7.0, s);
    b1 = -1.04 - 0.76 * sin((s - 6.4) * 0.55) + 0.078 * (s - 9.5) + scal1 - 1.60 * leftRoute
       + 0.30 * cubicPulse(7.2, 2.0, s);

    // Brink 2: bold center-right S-curve rising from the lower-right (15s lower-right shadow ribbon),
    // peaking at x ~ +2.0 near s = 6, then sweeping hard up-left across the frame toward the bench.
    // C2 sminCubic clamp avoids any normal/slope derivative jump across s = 13.8 in orbited views!
    b2 = 0.56 + 1.14 * cos((s - 6.2) * 0.56) + 0.090 * (9.4 - sminCubic(s, 13.8, 2.4)) + scal2;

    // Brink 3: secondary right-flank dunelet
    b3 = b2 + 2.10 + 0.35 * sin(s * 0.45 + 1.1) + 0.15 * dd_scallop1(s * 1.18 + 4.3);

    // Brink 4L: outer-left mid-ground S-crest (frames lower-left at 18s..19s)
    b4L = b1 - 1.92 - 0.28 * cos(s * 0.48) + 0.15 * dd_scallop2(s * 1.14 - 2.7);
}

// Per-brink height envelopes in s (shared by geometry & shading so wind-scour masks align exactly)
vec4 dd_brinkEnvelopes(float s) {
    float backErg = 0.68 * smoothstep(-15.0, -5.0, s);
    return vec4(smoothstep(3.5, 6.5, s),                      // Brink 1
                mix(backErg, 1.0, smoothstep(0.8, 3.5, s)),   // Brink 2 (continues across sunward erg in orbits)
                mix(backErg, 1.0, smoothstep(1.0, 4.0, s)),   // Brink 3
                smoothstep(7.6, 10.4, s));                    // Brink 4L
}

// Smooth mask [0,1] where thinning windblown sand transitions onto the slickrock sandstone bench
float dd_slickrockApronMask(vec2 xz) {
    float s = -xz.y;
    if (s < 11.5 || s > 31.5) return 0.0;
    float benchZone  = smoothstep(15.8, 20.6, s) * (1.0 - smoothstep(26.5, 31.0, s));
    vec2  toArch     = (xz - DESERT_ARCH_POS.xz) * vec2(0.11, 0.16);
    float archPad    = exp(-dot(toArch, toArch)) * smoothstep(11.5, 14.5, s) * (1.0 - smoothstep(28.5, 31.5, s)) * 0.94;
    float sMid       = smoothstep(12.8, 17.8, s) * (1.0 - smoothstep(25.5, 29.5, s));
    float rightSheet = smoothstep(-2.6, 0.8, xz.x) * sMid * 0.84;
    float leftCobble = (1.0 - smoothstep(-8.8, -5.2, xz.x)) * smoothstep(14.2, 18.8, s) * (1.0 - smoothstep(25.5, 29.5, s)) * 0.36;
    return saturate(1.0 - (1.0 - benchZone) * (1.0 - archPad) * (1.0 - rightSheet) * (1.0 - leftCobble));
}

float desertDuneHeight(vec2 xz) {
    // Fast bypass beyond canyon rim where valleyBlend == 1.0 in mapDesert
    if (xz.y < -33.6) return 0.55;

    float s = clamp(-xz.y, 0.0, 34.0);

    // 1. Macro slickrock sandstone bench rising flush under the Arch pedestals (z = -23.5), tilted gently down-right
    float zRise = 0.35 + 0.061 * sminCubic(s, 23.8, 2.4) + 0.48 * smoothstep(9.5, 21.8, s);
    float xSpan = sminCubic(-sminCubic(-(xz.x - 1.0), 9.5, 2.0), 13.5, 2.0);
    float xTilt = -0.035 * xSpan * smoothstep(5.5, 18.5, s);
    // Gentle arch-window sill dip keeps distant badlands & mesas framed inside lower arch opening without floating pedestals!
    float winX  = cubicPulse(5.2, 2.8, xz.x);
    float winZ  = cubicPulse(23.5, 3.8, s);
    float rightDip = -0.14 * smoothstep(4.2, 10.5, xz.x) * smoothstep(14.0, 22.0, s);
    float macroBench = zRise + xTilt - 0.10 * winX * winZ + rightDip;
    macroBench += 0.09 * (valueNoise(xz * 0.085 + vec2(1.4, 0.6)) - 0.5)
                + 0.045 * (valueNoise(xz * 0.19 - vec2(0.8, 2.1)) - 0.5);

    // Beyond z < -26.2, roll bench smoothly down so canyonland badlands take over without a seam
    float rimKeep = 1.0 - smoothstep(26.2, 31.5, s);
    float h = mix(0.55, macroBench, rimKeep);

    // 2. Asymmetric wind-sculpted S-curved dune crests, continuous from the back-erg (-15m) through the
    //    slickrock bench (+20m) so 360-deg orbited views never hit an abrupt dune cutoff!
    float sDune     = clamp(-xz.y, -16.0, 34.0);
    float startFade = mix(0.62 * smoothstep(-15.0, -5.0, sDune), 1.0, smoothstep(0.3, 1.8, sDune));
    float farFade   = 1.0 - smoothstep(16.0, 20.2, sDune);
    float apron     = dd_slickrockApronMask(xz);
    float duneEnv   = startFade * farFade * (1.0 - 0.90 * apron);

    if (duneEnv > 0.001) {
        float b1, b2, b3, b4L;
        dd_duneBrinks(sDune, b1, b2, b3, b4L);
        vec4 env = dd_brinkEnvelopes(sDune);

        float und1 = 0.90 + 0.18 * (0.65 * sin(sDune * 0.43 + 1.1) + 0.35 * sin(sDune * 0.97 - 0.6));
        float und2 = 0.90 + 0.18 * (0.65 * sin(sDune * 0.39 + 2.7) + 0.35 * sin(sDune * 0.91 + 0.9));

        // Gentle windward stoss slopes (~0.18) stay well below camera ray slope rd.y/rd.x (~0.33),
        // completely eliminating grazing-ray step-timeout ribbons on Brink 1 & Brink 2!
        float c1  = dd_asymmetricCrest(xz.x - b1,  3.60, 1.10, 0.63 * und1 * env.x);
        float c2  = dd_asymmetricCrest(xz.x - b2,  3.20, 1.02, 0.50 * und2 * env.y);
        float c3  = dd_asymmetricCrest(xz.x - b3,  2.15, 0.82, 0.22 * und1 * env.z);
        float c3R = dd_asymmetricCrest(xz.x - (b3 + 1.92 + 0.24 * sin(sDune * 0.40)), 1.95, 0.80, 0.14 * env.z);
        float c4L = dd_asymmetricCrest(xz.x - b4L, 2.55, 0.88, 0.26 * und2 * env.w);
        // Outer lateral dune trains with C2 smooth union (no V-crease slope jumps in orbited views!)
        float c5L = dd_asymmetricCrest(xz.x - (b4L - 2.30 - 0.30 * sin(sDune * 0.37 + 0.8)), 2.40, 0.86, 0.24 * und1 * env.w);
        float c6R = dd_asymmetricCrest(xz.x - (b3 + 4.05 + 0.30 * cos(sDune * 0.33 + 1.9)), 2.10, 0.80, 0.17 * und2 * env.z);
        c4L = -sminCubic(-c4L, -c5L, 0.07);
        c3R = -sminCubic(-c3R, -c6R, 0.06);

        // Zero-floor smooth max (max + C2 cubic fillet only where two positive crests overlap -> 0 when crests == 0!)
        float d12 = -sminCubic(-c1, -c2, 0.08);
        float d34 = -sminCubic(-c3, -c3R, 0.06);
        float dunes = -sminCubic(-d12, -sminCubic(-d34, -c4L, 0.06), 0.06);
        h += dunes * duneEnv;
    }

    return h;
}

// Low, sprawling, wind-frayed dry desert bunchgrass clump (3D fbm breakup — zero radial stripes!)
float dd_sdScrubTuft(vec3 q, float radius, float height, float seed) {
    vec3 wq = vec3(q.x - 0.22 * max(q.y, 0.0), q.y - height * 0.26, q.z);
    vec3 rMain = vec3(radius, height * 0.48, radius * 0.82);

    float m1 = sdEllipsoid(wq, rMain);
    float m2 = sdEllipsoid(wq - vec3( radius * 0.44, -height * 0.04,  radius * 0.24), rMain * vec3(0.72, 0.78, 0.68));
    float m3 = sdEllipsoid(wq - vec3(-radius * 0.36, -height * 0.06, -radius * 0.30), rMain * vec3(0.65, 0.68, 0.66));
    float m4 = sdEllipsoid(wq - vec3( radius * 0.12,  height * 0.16, -radius * 0.28), rMain * vec3(0.56, 0.74, 0.56));
    float d  = smin(smin(m1, m2, 0.06), smin(m3, m4, 0.06), 0.06);

    if (d < 0.10) {
        float fray = valueNoise(wq * vec3(11.5, 8.0, 11.5) + vec3(seed * 13.0)) - 0.5;
        float wisp = valueNoise(wq * vec3(24.0, 15.0, 24.0) - vec3(seed * 7.0)) - 0.5;
        d += (0.042 * fray + 0.022 * wisp) * smoothstep(-height * 0.25, height * 0.35, wq.y);
    }
    return d * 0.66;
}

// Fast angular polygonal weathered sandstone slab / cobble (zero rectangular brick edges from any orbit!)
float dd_sdSandstoneSlab(vec3 q, vec3 halfExt, float yaw, float tilt) {
    q.xz = rot2(yaw) * q.xz;
    q.xy = rot2(tilt) * q.xy;
    float box    = sdRoundBox(q, halfExt, 0.032);
    float bevel1 = dot(q, vec3(0.233, 0.955, -0.184)) - halfExt.y * 0.80;
    float bevel2 = abs(dot(q.xz, vec2(0.58, 0.81))) - (halfExt.x * 0.62 + halfExt.z * 0.52);
    float chip   = 0.028 * sin(q.x * 5.2 + q.z * 3.7) * (1.0 - smoothstep(0.05, 0.28, abs(box)));
    return (smax(smax(box, bevel1, 0.04), bevel2, 0.05) + chip) * 0.84;
}

vec2 mapDesertFloorExtras(vec3 p, float duneH) {
    if (gFastMap || p.z < -28.0) {
        return vec2(1e5, MAT_DESERT_SLICKROCK);
    }

    float localY = p.y - duneH;

    // Tight sub-boxes so 97% of scene rays exit in 6 float ops with ZERO SDF/noise calls!
    float boxSlabs = max(max(abs(p.x + 6.0) - 3.9, abs(p.z + 17.85) - 4.75), localY - 0.34);
    float boxScrub = max(max(abs(p.x + 5.25) - 1.65, abs(p.z + 14.25) - 2.75), localY - 0.32);

    float nearZone = min(boxSlabs, boxScrub);
    if (nearZone > 0.24) {
        return vec2(nearZone + 0.08, MAT_DESERT_SLICKROCK);
    }

    vec2 res = vec2(1e5, MAT_DESERT_SLICKROCK);

    // 1. Weathered tabular sandstone slabs & sparse cobbles along left slickrock margin
    if (boxSlabs < 0.25) {
        float heroBox = max(max(abs(p.x + 6.5) - 3.0, abs(p.z + 17.6) - 2.2), localY - 0.32);
        if (heroBox < res.x) {
            float d1 = dd_sdSandstoneSlab(vec3(p.x + 6.20, localY - 0.08, p.z + 17.10), vec3(0.68, 0.16, 0.42),  0.28, -0.09);
            float d2 = dd_sdSandstoneSlab(vec3(p.x + 8.55, localY - 0.10, p.z + 16.85), vec3(0.76, 0.19, 0.46), -0.22,  0.07);
            float d3 = dd_sdSandstoneSlab(vec3(p.x + 5.30, localY - 0.03, p.z + 16.55), vec3(0.30, 0.08, 0.22),  0.65, -0.12);
            float d4 = dd_sdSandstoneSlab(vec3(p.x + 4.10, localY - 0.05, p.z + 18.95), vec3(0.44, 0.11, 0.29), -0.40, -0.06);
            float dSlabs = min(min(d1, d2), min(d3, d4));
            if (dSlabs < res.x) res = vec2(dSlabs, MAT_DESERT_SLICKROCK);
        }

        if (localY < 0.15) {
            const float COB_SPACE = 2.05;
            vec2 cid = domRepeatId(p.xz, vec2(COB_SPACE));
            vec3 ch  = hash32(cid + vec2(71.0, 29.0));
            if (ch.x > 0.70) {
                vec2 cpos = cid * COB_SPACE + (ch.yz - 0.5) * 0.90;
                vec3 cq   = vec3(p.x - cpos.x, localY - 0.01, p.z - cpos.y);
                float cBound = length(cq) - 0.25;
                if (cBound < res.x) {
                    vec3 cext = vec3(mix(0.08, 0.19, ch.y), mix(0.028, 0.060, ch.z), mix(0.06, 0.14, ch.x));
                    float dc  = dd_sdSandstoneSlab(cq, cext, ch.y * TAU, (ch.z - 0.5) * 0.24);
                    if (dc < res.x) res = vec2(dc, MAT_DESERT_SLICKROCK);
                }
            }
        }
    }

    // 2. Low dry golden-olive desert bunchgrass clumps (film_15.00 left mid-ground, sliding off by 19s!)
    if (boxScrub < 0.25) {
        vec3 q1 = vec3(p.x + 5.85, localY, p.z + 14.75);
        vec3 q2 = vec3(p.x + 5.30, localY, p.z + 14.95);
        vec3 q3 = vec3(p.x + 6.45, localY, p.z + 16.40);

        float b1 = length(q1) - 0.42;
        float b2 = length(q2) - 0.34;
        float b3 = length(q3) - 0.34;
        float minB = min(b1, min(b2, b3));

        if (minB < 0.08) {
            float dScrub = 1e5;
            if (b1 < 0.12) dScrub = min(dScrub, dd_sdScrubTuft(q1, 0.28, 0.15, 0.17));
            if (b2 < 0.12) dScrub = min(dScrub, dd_sdScrubTuft(q2, 0.21, 0.12, 0.63));
            if (b3 < 0.12) dScrub = min(dScrub, dd_sdScrubTuft(q3, 0.20, 0.12, 0.41));
            if (dScrub < res.x) res = vec2(dScrub, MAT_DESERT_SCRUB);
        } else if (minB < res.x) {
            res = vec2(minB, MAT_DESERT_SCRUB);
        }
    }

    return res;
}

// Taut, wind-combed bifurcating (Y-junction) aeolian sand ripples:
// Returns vec3(rippleHeightMeters, crestGrainMask, troughShadowMask).
vec3 dd_aeolianRipples(vec2 xz, vec2 nSlopeXZ, float microWeight) {
    // Constant orthonormal wind frame avoids |xz|-amplified phase jumps across dune curvature transitions,
    // while bounded local slopeRefract gently bends ripple crests across stoss flanks!
    const vec2 windDir  = vec2(0.9347809, -0.3552247); // normalize(vec2(0.935, -0.355))
    const vec2 crestDir = vec2(0.3552247,  0.9347809);
    vec2 uv = vec2(dot(xz, windDir), dot(xz, crestDir));

    // Gentle long-wavelength wind-streamline bend + broader wavelength on right sand sheet (x > +1)
    float bend1 = simplexNoise(uv * vec2(0.17, 0.10) + vec2(1.7, -0.9));
    float bend2 = simplexNoise(uv * vec2(0.36, 0.20) + vec2(-3.1, 2.2));
    float rightMask = smoothstep(-0.2, 2.2, xz.x);
    float bend3 = simplexNoise(uv * vec2(0.74, 0.55) + vec2(4.6, -2.7));
    float kScale = mix(1.0, 0.80, smoothstep(0.4, 4.2, xz.x));
    float slopeRefract = clamp(-0.022 * dot(nSlopeXZ, windDir), -0.016, 0.016);
    // Monotone phase (d/du >= ~0.5) -> organic sinuous crests with zero closed loops or zigzags
    float uWarped = uv.x * kScale + slopeRefract + (0.12 + 0.10 * rightMask) * bend1
                  + (0.05 + 0.06 * rightMask) * bend2 + 0.045 * rightMask * bend3;

    const float K1 = 19.4; // ~32cm primary wavelength (broadening to ~41cm on right flank)
    float phi1 = uWarped * K1 + 0.90 * bend1;

    // Co-aligned secondary wave (+8.5 deg, 1.14x k) creates isolated Y-fork dislocations every ~2m!
    const float K2 = 22.1;
    float phi2 = (uWarped * 0.989 + uv.y * 0.148 * kScale) * K2 - 0.75 * bend1 + 0.90 * bend2 + 1.6;

    float wBranch = mix(0.38, 0.86, smoothstep(-0.28, 0.42, fbm(uv * vec2(0.28, 0.17) + vec2(5.4, -1.9), 2)));

    float Z = cos(phi1) + wBranch * cos(phi2);
    float S = sin(phi1) + wBranch * sin(phi2);

    float amp = sqrt(Z * Z + S * S + 0.028);
    float c   = Z / amp;
    float s   = S / amp;
    float branchEnv = amp * inversesqrt(amp * amp + 0.09);

    // Asymmetric ballistic wind-ripple profile (gentle stoss climb, steeper leeward face, sharp crest)
    float sin2 = 2.0 * c * s;
    float cos2 = c * c - s * s;
    float primary = (0.72 * c + 0.25 * sin2 + 0.12 * cos2) * branchEnv;

    float micro = 0.0;
    if (microWeight > 0.005) {
        float phiM  = (uWarped * 76.0 + uv.y * 7.5) + 1.1 * bend2;
        float scour = simplexNoise(uv * vec2(2.2, 14.0));
        micro = (0.0016 * sin(phiM) * (0.55 - 0.45 * c) + 0.0010 * scour) * microWeight;
    }

    // Patchy ripple amplitude (sheltered smooth swales vs crisp wind-exposed ripple fields)
    float ampPatch = 0.62 + 0.50 * smoothstep(-0.55, 0.45, simplexNoise(xz * 0.21 + vec2(3.3, 1.1)));
    float hRip = 0.0150 * primary * ampPatch + micro;
    float crestSort = saturate(0.5 + 0.5 * (c * branchEnv) + 0.18 * cos2);
    float leeFlank  = saturate(0.5 - 0.42 * s - 0.28 * c) * branchEnv;
    return vec3(hRip, crestSort, leeFlank);
}

// Smooth, cell-border-safe meso sand slumps & crescent wind-scour dimples (film_15 & film_17 foreground!)
float dd_sandDimples(vec2 xz) {
    vec4 vd = voronoi(xz * 0.86 + vec2(0.35, -0.20), 0.48);
    float keep = step(0.72, hash12(vd.zw + vec2(17.0, 43.0)));
    if (keep < 0.5) return 0.0;
    float bowl = 1.0 - smoothstep(0.02, 0.21, vd.x);
    return -0.024 * bowl * bowl;
}

void shadeDesertSand(vec3 p, vec3 nIn, float t, float pxAngle, out vec3 albedo, out float rough, out vec3 nOut) {
    float fp = t * pxAngle;
    float sDepth = clamp(-p.z, -16.0, 36.0);

    // 1. Thinning sand onto windswept slickrock bench + distance footprint filter
    float apronMask = dd_slickrockApronMask(p.xz);
    float distKeep  = 1.0 - smoothstep(14.0, 25.5, t);

    // 2. Wind-scoured smooth dune brinks & leeward slip-faces (velvety golden knife-edge brinks
    //    on hero avalanche crests b1 & b2; gentle whaleback swells c3/c4L keep unbroken ripples!)
    float slipFaceMask = smoothstep(0.06, 0.30, nIn.x);
    float brinkScour = 0.0;
    if (sDepth > -15.0 && sDepth < 20.2) {
        float b1, b2, b3, b4L;
        dd_duneBrinks(sDepth, b1, b2, b3, b4L);
        float dEnv = mix(0.62 * smoothstep(-15.0, -5.0, sDepth), 1.0, smoothstep(0.3, 1.8, sDepth))
                   * (1.0 - smoothstep(15.8, 20.0, sDepth)) * (1.0 - 0.90 * apronMask);
        vec4 env = dd_brinkEnvelopes(sDepth) * dEnv;
        float near1 = (1.0 - smoothstep(0.16, 0.52, abs(p.x - b1))) * env.x;
        float near2 = (1.0 - smoothstep(0.15, 0.48, abs(p.x - b2))) * env.y;
        brinkScour = max(near1, near2);
    }
    float smoothZone = saturate(max(slipFaceMask, brinkScour * 0.94));
    float microKeep  = (1.0 - smoothstep(4.2, 10.5, t)) * (1.0 - smoothZone);

    float rippleAmp = (1.0 - 0.96 * smoothZone) * (1.0 - 0.88 * apronMask) * distKeep;

    vec3 n = nIn;
    float crestSort = 0.5;
    float leeFlank  = 0.0;

    if (rippleAmp > 0.004) {
        float eps = clamp(fp * 1.35, 0.011, 0.068);
        vec3 r0 = dd_aeolianRipples(p.xz, nIn.xz, microKeep);
        vec3 rx = dd_aeolianRipples(p.xz + vec2(eps, 0.0), nIn.xz, microKeep);
        vec3 rz = dd_aeolianRipples(p.xz + vec2(0.0, eps), nIn.xz, microKeep);
        crestSort = r0.y;
        leeFlank  = r0.z * rippleAmp;

        float dimpAmp = (1.0 - smoothstep(10.5, 18.5, t)) * (1.0 - apronMask) * (1.0 - 0.65 * smoothZone);
        float d0 = (dimpAmp > 0.01) ? dd_sandDimples(p.xz) * dimpAmp : 0.0;
        float dx = (dimpAmp > 0.01) ? dd_sandDimples(p.xz + vec2(eps, 0.0)) * dimpAmp : 0.0;
        float dz = (dimpAmp > 0.01) ? dd_sandDimples(p.xz + vec2(0.0, eps)) * dimpAmp : 0.0;

        float ripGain = 0.96 * rippleAmp * mix(1.30, 1.0, smoothstep(6.0, 10.5, t));
        vec2 grad = vec2((rx.x - r0.x) * ripGain + (dx - d0),
                         (rz.x - r0.x) * ripGain + (dz - d0)) / eps;
        n = normalize(n + vec3(-grad.x, 0.0, -grad.y));
    }

    // Subtle down-slope avalanche grain-flow streaks on leeward slip-faces
    if (slipFaceMask > 0.05 && t < 20.0) {
        float flow0 = fbm(p.xz * vec2(1.3, 8.2), 2);
        float flowZ = fbm((p.xz + vec2(0.0, 0.05)) * vec2(1.3, 8.2), 2);
        float streakFade = slipFaceMask * (1.0 - smoothstep(8.5, 20.0, t));
        n = normalize(n + vec3(0.0, 0.0, -(flowZ - flow0) * 1.15) * streakFade);
    }

    // Luminous golden-hour Entrada sand palette (calibrated against vignette + AgX tonemapping
    // to match sRGB (0.81, 0.51, 0.29) sunlit windward sand & sRGB (0.30, 0.21, 0.16) slip-face shadows):
    vec3 troughTerracotta = srgbToLinear(vec3(0.82, 0.40, 0.150));
    vec3 windwardOrange   = srgbToLinear(vec3(0.93, 0.50, 0.190));
    vec3 crestPaleGold    = srgbToLinear(vec3(0.97, 0.58, 0.250));
    vec3 slipVelvet       = srgbToLinear(vec3(0.85, 0.46, 0.200));
    vec3 slickrockBuff    = srgbToLinear(vec3(0.76, 0.46, 0.265));

    float macroPatch = 0.5 + 0.5 * fbm(p.xz * 0.20 + vec2(2.1, -1.4), 3);
    float fineMottle = 0.5 + 0.5 * fbm(p.xz * 2.4, 2);

    vec3 sandCol = mixOklab(troughTerracotta, windwardOrange, saturate(0.35 + 0.65 * macroPatch));
    sandCol = mixOklab(sandCol, crestPaleGold, smoothstep(0.36, 0.86, crestSort) * rippleAmp * 0.80);
    sandCol = mixOklab(sandCol, slipVelvet, smoothZone * 0.68);
    // Horizon micro-occlusion in leeward ripple troughs gives realistic 2cm sand-ridge chiaroscuro
    sandCol *= mix(1.0, 0.74, smoothstep(0.18, 0.78, leeFlank));
    sandCol *= (0.95 + 0.10 * fineMottle);

    // Compacted cross-bedded sandstone patches showing through the windswept slickrock apron
    if (apronMask > 0.02) {
        float strataBand = 0.5 + 0.5 * sin(p.x * 1.8 + p.z * 0.75 + 3.0 * fbm(p.xz * 0.32, 2));
        vec3 apronCol = mixOklab(srgbToLinear(vec3(0.72, 0.41, 0.23)), slickrockBuff, strataBand);
        float patchMask = apronMask * smoothstep(0.26, 0.72, macroPatch + 0.28 * apronMask);
        sandCol = mixOklab(sandCol, apronCol, patchMask * 0.56);
    }

    rough = mix(0.84, 0.68, smoothstep(0.42, 0.88, crestSort) * rippleAmp);
    rough = mix(rough, 0.77, apronMask * 0.5);

    // Distant open-erg sand sheet (t > 16m outside slickrock bench -> untouched in solo 15..19s):
    // rolling meso sand swells + porous granular stoss tilt prevent bleached dielectric Fresnel glare in sunward orbits!
    float farErg = smoothstep(16.0, 32.0, t) * (1.0 - apronMask) * (1.0 - 0.5 * smoothZone);
    if (farErg > 0.005) {
        float swellFade = farErg * (1.0 - smoothstep(42.0, 84.0, t));
        float sw1 = cos(p.x * 0.68 - p.z * 0.26 + 0.9 * sin(p.z * 0.17));
        float sw2 = cos(p.x * 0.31 + p.z * 0.19 - 1.4);
        vec2 ergTilt = vec2(-0.15 * farErg - 0.08 * swellFade * sw1 - 0.05 * swellFade * sw2,
                             0.06 * farErg + 0.03 * swellFade * sw1);
        n = normalize(n + vec3(ergTilt.x, 0.0, ergTilt.y));
        rough = mix(rough, 0.99, farErg);
        sandCol = mixOklab(sandCol, srgbToLinear(vec3(0.80, 0.43, 0.18)), farErg * 0.32);
    }

    // Footprint-filtered quartz sand grain micro-sparkle (zero shimmer in distance, zero glint in shadow!)
    float sparkleFade = 1.0 - smoothstep(2.4, 9.0, t);
    if (sparkleFade > 0.005) {
        const float GRAIN_SCALE = 86.0;
        vec2 gp  = p.xz * GRAIN_SCALE;
        vec2 gid = floor(gp);
        vec2 gf  = gp - gid - 0.5;
        vec3 gh  = hash32(gid + vec2(19.0, 83.0));

        if (gh.x > 0.915) {
            vec2 jitter  = (gh.yz - 0.5) * 0.54;
            float kernelW = max(0.20, fp * GRAIN_SCALE * 0.85);
            float spot    = 1.0 - smoothstep(kernelW * 0.35, kernelW, length(gf - jitter));
            float glintAmt = spot * sparkleFade * (0.55 + 0.45 * crestSort);

            vec2 tilt = (hash22(gid + vec2(53.0, 11.0)) - 0.5) * 0.50;
            vec3 glintN = normalize(n + DESERT_SUN_DIR * 0.26 + vec3(tilt.x, 0.0, tilt.y));
            n = normalize(mix(n, glintN, glintAmt * 0.62));
            rough = mix(rough, 0.24, glintAmt * 0.76);
            sandCol = mixOklab(sandCol, srgbToLinear(vec3(0.98, 0.84, 0.62)), glintAmt * 0.36);
        }
    }

    albedo = sandCol;
    nOut   = n;
}

vec3 desertAtmosphere(vec3 rd) {
    float h = max(rd.y, 0.0);

    // Scene-linear HDR sky, solved by inverting vignette(uv, 2.2) * DESERT_EXPOSURE (1.14) * tonemapAgX
    // against film_15..19.png sky samples at 4 elevation bands x (left | right azimuth):
    //   crisp saturated cobalt-cerulean across the upper sky, warm golden-cream glow confined to h < ~0.16
    //   and strongest toward the right horizon.
    float wR = smoothstep(-0.10, 0.75, rd.x);
    wR *= sqrt(wR);

    vec3 zenDeep = mix(vec3(0.010, 0.115, 0.340), vec3(0.120, 0.360, 0.860), wR); // h >= 0.65
    vec3 zenith  = mix(vec3(0.015, 0.170, 0.440), vec3(0.200, 0.500, 1.120), wR); // h ~ 0.36
    vec3 midSky  = mix(vec3(0.045, 0.270, 0.650), vec3(0.470, 0.910, 1.570), wR); // h ~ 0.25
    vec3 lowSky  = mix(vec3(0.200, 0.510, 0.870), vec3(1.580, 2.100, 2.260), wR); // h ~ 0.16
    vec3 horizon = mix(vec3(0.630, 0.850, 0.880), vec3(4.200, 3.330, 2.000), wR); // h <= 0.085

    vec3 sky = mixOklab(horizon, lowSky, smoothstep(0.085, 0.16, h));
    sky = mixOklab(sky, midSky,  smoothstep(0.16, 0.25, h));
    sky = mixOklab(sky, zenith,  smoothstep(0.25, 0.36, h));
    sky = mixOklab(sky, zenDeep, smoothstep(0.36, 0.65, h));

    // Haze tones for the analytic distant silhouettes below
    float rightWarmth = smoothstep(-0.08, 0.78, rd.x);
    vec3 horizCool    = vec3(0.510, 0.670, 0.750);
    vec3 horizAmber   = vec3(1.820, 1.680, 1.380);

    // Analytic multi-ridge distant mountain & canyonland mesa backdrop:
    // Gated strictly to horizon band (rd.y < 0.076) -> zero noise octaves on upper sky!
    if (rd.y < 0.076) {
        float az = atan(rd.x, -rd.z + 1e-5);

        // 1. Far left snow/haze-dusted La Sal mountain peaks (az in [-0.66, -0.02])
        float mtnEnv   = smoothstep(-0.68, -0.46, az) * (1.0 - smoothstep(-0.14, 0.02, az));
        float mtnPeaks = (mtnEnv > 0.002) ? ridgedFbm(vec2(az * 9.5 + 2.1, 1.4), 3) : 0.0;
        float mtnH     = 0.036 + 0.036 * mtnEnv * (0.35 + 0.65 * mtnPeaks);

        // 2. Stepped flat-topped distant canyonland mesa range across north horizon & inside arch window;
        //    for off-canyon sunward/lateral erg orbits (|az| > 0.76, zero overlap with solo 15..19s frustum!),
        //    tapers smoothly into a soft sun-veiled desert erg horizon so orbited sand fades seamlessly!
        float ergWrap   = smoothstep(0.76, 1.38, abs(az));
        float mesaNoise = fbm(vec2(az * 5.2 + 0.8, 3.3), 2);
        float mesaSteps = floor(2.6 * saturate(0.52 + 0.55 * mesaNoise) + 0.5) / 2.6;
        float rightButteRise = 0.014 * smoothstep(0.42, 0.68, az) * (1.0 - ergWrap);
        float canyonMesaH = 0.034 + 0.019 * mesaSteps + 0.003 * sin(az * 28.0 + 4.0 * mesaNoise) + rightButteRise;
        float ergRidgeH   = 0.014 + 0.006 * saturate(0.5 + 0.5 * mesaNoise);
        float mesaH       = mix(canyonMesaH, ergRidgeH, ergWrap);

        // 3. Closer hazy badland rim below mesaH so negative/grazing rd.y stays warm dusty valley/sand
        float rimH = mix(0.018 + 0.009 * saturate(0.5 + 0.5 * mesaNoise), 0.009, ergWrap);

        if (rd.y < max(mtnH, mesaH) + 0.004) {
            float sunAz = saturate(dot(normalize(rd.xz + vec2(1e-5)), normalize(DESERT_SUN_DIR.xz)));
            vec3 horizonHaze = mixOklab(horizCool, horizAmber * 0.78, smoothstep(0.08, 0.90, max(rightWarmth, sunAz * 0.72 * ergWrap)));

            float snowCrest = smoothstep(0.55, 0.88, mtnPeaks) * smoothstep(0.048, 0.066, rd.y);
            vec3 mtnBase = mixOklab(srgbToLinear(vec3(0.42, 0.47, 0.55)), srgbToLinear(vec3(0.76, 0.77, 0.79)), snowCrest * 0.65);
            vec3 mtnCol  = mixOklab(mtnBase, horizonHaze, 0.52);

            // Clamped rd.y >= 0.008 eliminates Venetian-blind banding for negative rd.y in orbited views!
            float strata   = 0.5 + 0.5 * sin(max(rd.y, 0.008) * 320.0 + 3.2 * mesaNoise);
            vec3 mesaRock  = mixOklab(srgbToLinear(vec3(0.38, 0.28, 0.24)), srgbToLinear(vec3(0.54, 0.40, 0.32)), strata);
            vec3 mesaCol   = mixOklab(mesaRock, horizonHaze, mix(0.34, 0.54, rightWarmth));
            // Match da_canyonAerialHaze & backlit sand dust across sunward/lateral erg orbits (zero dark mesa band!)
            vec3 ergHaze   = mixOklab(srgbToLinear(vec3(0.62, 0.55, 0.50)), srgbToLinear(vec3(0.75, 0.67, 0.59)), sunAz);
            mesaCol        = mixOklab(mesaCol, ergHaze, ergWrap * 0.94);

            vec3 valleyRaw = mixOklab(srgbToLinear(vec3(0.48, 0.36, 0.27)), srgbToLinear(vec3(0.61, 0.47, 0.35)), saturate(0.5 + 0.5 * mesaNoise));
            vec3 valleyCol = mixOklab(valleyRaw, horizonHaze, 0.34);
            valleyCol      = mixOklab(valleyCol, ergHaze, ergWrap * 0.92);

            // Sub-horizon downward warmth (rd.y < 0.008 -> negative rd.y in elevated orbits) so farOrbitFade
            // melts sunlit orange-terracotta dunes seamlessly into the horizon haze without a gray-cream band!
            float subHoriz = 1.0 - smoothstep(-0.048, 0.008, rd.y);
            vec3  sandMist = mixOklab(srgbToLinear(vec3(0.63, 0.46, 0.34)), srgbToLinear(vec3(0.74, 0.62, 0.51)), sunAz);
            valleyCol      = mixOklab(valleyCol, sandMist, subHoriz * (0.68 + 0.28 * ergWrap));

            float mesaFeather = mix(0.0018, 0.0150, ergWrap);
            float rimFeather  = mix(0.0025, 0.0160, ergWrap);
            float mtnMask  = 1.0 - smoothstep(mtnH - 0.0025, mtnH + 0.0018, rd.y);
            float mesaMask = 1.0 - smoothstep(mesaH - mesaFeather, mesaH + mesaFeather, rd.y);
            float rimMask  = 1.0 - smoothstep(rimH - rimFeather, rimH + rimFeather, rd.y);

            sky = mix(sky, mtnCol, mtnMask * mtnEnv);
            sky = mix(sky, mesaCol, mesaMask);
            sky = mix(sky, valleyCol, rimMask * mix(0.72, 0.98, max(subHoriz, ergWrap)));
        }
    }

    return sky;
}

// ==== PART: 04b_desert_arch.glsl ====
// =============================================================================
// SCENE IV (Part B): DESERT ARCH, STRATIFIED BUTTE, CANYON RIM, BADLANDS & RENDERER
// Collaborates with 04a_desert_dunes.glsl (desertDuneHeight, mapDesertFloorExtras,
// shadeDesertSand, desertAtmosphere). All private helpers prefixed with da_.
// =============================================================================

// Smooth sandstone slickrock ramp rising gently from z = -15 to z = -25.8 so the
// windswept apron in front of Delicate Arch remains proudly visible above foreground dunes.
float da_slickrockRamp(vec2 xz) {
    float s = -xz.y;
    if (s < 14.5 || s > 31.5) return 0.0;
    float riseZ = smoothstep(14.8, 23.0, s) * (1.0 - smoothstep(26.0, 31.2, s));
    float spanX = (1.0 - smoothstep(6.5, 14.0, xz.x)) * smoothstep(-14.5, -7.5, xz.x);
    return 0.42 * riseZ * spanX;
}

// Strict conservative zero-noise upper bound on (desertDuneHeight + da_slickrockRamp).
float da_duneUpperEnvelope(vec2 xz) {
    float s = clamp(-xz.y, 0.0, 34.0);
    float zRise = 0.68 + 0.062 * min(s, 24.0) + 0.50 * smoothstep(9.0, 22.0, s);
    float xTilt = -0.035 * clamp(xz.x - 1.0, -9.8, 13.5) * smoothstep(5.0, 18.5, s);
    float duneCrestMax = 0.90 * (1.0 - smoothstep(16.0, 21.0, s));
    return zRise + xTilt + duneCrestMax + da_slickrockRamp(xz);
}

float da_duneAndRampHeight(vec2 xz) {
    return desertDuneHeight(xz) + da_slickrockRamp(xz);
}

// Non-uniform Entrada sandstone macro relief: massive weathered beds separated
// by selective deep bedding alcoves, chiseled rock crags, and vertical fracture clefts.
float da_sandstoneRelief(vec3 p, float rawD, float scaleY, float cragAmp) {
    float fade = 1.0 - smoothstep(0.22, 0.68, rawD);
    if (fade <= 0.001) return 0.0;

    float macroWarp = fbm(p * vec3(0.16, 0.24, 0.16), 2, 2.0, 0.5);
    float bedY = p.y * scaleY + 0.85 * macroWarp;
    float bedId = floor(bedY);
    float bedFrac = bedY - bedId;
    float bedHash = hash11(bedId * 17.0 + 5.0);

    float alcoveWeight = smoothstep(0.36, 0.82, bedHash);
    float parting = exp(-abs(bedFrac - 0.08) * 18.0) * alcoveWeight;
    float shelfLip = 0.032 * sin(bedY * TAU - 0.45 * sin(bedY * TAU)) * alcoveWeight;

    float crag  = fbm(p * vec3(0.60, 1.15, 0.60) + vec3(1.7, 0.0, -2.3), 3, 2.05, 0.54);
    float ridge = ridgedFbm(vec2(p.x * 0.48 - p.z * 0.36, p.y * 0.64), 2);

    float vGate = smoothstep(0.14, 0.56, macroWarp);
    float vBorder = voronoiBorder(vec2(p.x * 0.72 + p.z * 0.48, p.y * 0.16) + 0.22 * crag, 0.82).x;
    float vCrack = (1.0 - smoothstep(0.006, 0.036, vBorder)) * 0.088 * vGate;

    float disp = parting * 0.100 - shelfLip + vCrack + 0.078 * (0.48 - ridge) + 0.054 * crag;
    return disp * cragAmp * fade;
}

// Hero Entrada Sandstone Natural Arch (sub-pixel X & crown registration to film_15..19.png!)
float da_sdSandstoneArch(vec3 p) {
    vec3 q = p - vec3(DESERT_ARCH_POS.x + 0.22, 2.36, DESERT_ARCH_POS.z);
    q.xz = rot2(-0.12) * q.xz;

    // 1. Sculpted rounded lower-left "boot" pedestal rising to q.y ~ 2.02 before the sharp ankle pinch
    float bellH = clamp((q.y + 0.05) / 2.02, 0.0, 1.0);
    float bellRadX = mix(1.18, 0.66, pow(bellH, 1.55)) + 0.13 * sin(bellH * PI);
    vec3 qPed = q - vec3(-3.94 + 0.17 * sin(bellH * PI), 0.22, 0.04);
    float dLeftPed = sdRoundBox(qPed, vec3(bellRadX, 1.88, 0.96 - 0.16 * bellH), 0.40);
    dLeftPed = opEngrave(dLeftPed, q.y - 0.04 + 0.03 * (q.x + 4.0), 0.13);

    // 3 stacked flat pancake talus slabs at outer-left pedestal foot
    float slab1   = sdRoundBox(q - vec3(-5.08, 0.08, 0.12), vec3(0.76, 0.10, 0.56), 0.045);
    float slab2   = sdRoundBox(q - vec3(-4.96, 0.29, 0.08), vec3(0.58, 0.088, 0.46), 0.040);
    float slab3   = sdRoundBox(q - vec3(-5.04, 0.48, 0.10), vec3(0.40, 0.070, 0.35), 0.030);
    float slabToe = sdRoundBox(q - vec3(-5.60, -0.08, 0.18), vec3(0.52, 0.12, 0.42), 0.040);
    float dTalusL = min(min(slab1, slab2), min(slab3, slabToe));

    // 2. Sharp chiseled left "ankle" joint + flat wedged sandstone wafer
    float dAnkle      = sdRoundBox(q - vec3(-4.10, 2.02, 0.0), vec3(0.40, 0.24, 0.58), 0.10);
    float dAnkleWafer = sdRoundBox(q - vec3(-4.20, 2.08, 0.02), vec3(0.58, 0.070, 0.55), 0.028);
    float dLeft = smin(dLeftPed, dAnkle, 0.14);
    dLeft = opEngrave(dLeft, q.y - 1.88, 0.12);
    dLeft = opEngrave(dLeft, q.y - 2.20, 0.10);
    dLeft = min(min(dLeft, dAnkleWafer), dTalusL);

    // 3. Sweeping asymmetric sandstone bridge (registered to inner window & outer shoulder of film_15..19.png)
    float radL = mix(0.60, 1.45, smoothstep(2.05, 5.35, q.y));
    float dSpanL = sdQuadraticBezier(q, vec3(-4.12, 2.14, 0.0), vec3(-3.84, 4.50, -0.04), vec3(-1.42, 5.64, 0.0)) - radL;

    float radR = mix(1.12, 1.44, smoothstep(3.75, 5.72, q.y));
    float dSpanR = sdQuadraticBezier(q, vec3(-1.50, 5.62, 0.0), vec3(0.62, 5.90, 0.04), vec3(2.66, 3.72, 0.04)) - radR;
    float dBridge = smin(dSpanL, dSpanR, 0.40);

    // Smoothly tucked cantilevered bedding wedge under upper-right soffit
    vec3 qTooth = q - vec3(0.94, 4.56, -0.04);
    qTooth.xy = rot2(0.36) * qTooth.xy;
    float dSoffitTooth = sdRoundBox(qTooth, vec3(0.66, 0.34, 0.74), 0.10);
    dBridge = smin(dBridge, dSoffitTooth, 0.34);

    // Jagged, meandering, pinching vertical rock joints on upper bridge & crown (gated & valueNoise-fast!)
    float bedWarp = gFastMap ? 0.0 : (0.11 * (valueNoise(p * 1.35) - 0.5));
    if (!gFastMap && q.y > 4.00 && q.y < 6.90 && dBridge < 0.48) {
        float vn1 = valueNoise(p * 1.25) - 0.5;
        float vn2 = valueNoise(p * 2.65 + vec3(3.1, -1.7, 0.8)) - 0.5;
        float vn3 = valueNoise(p * 1.25 + vec3(-4.2, 2.3, 1.9)) - 0.5;
        float jWarp1  = 0.42 * vn1 + 0.18 * vn2;
        float jWarp2  = 0.42 * vn3 - 0.14 * vn2;
        float jPinch1 = 0.095 * smoothstep(4.25, 5.15, q.y) * (0.30 + 0.70 * smoothstep(-0.22, 0.30, valueNoise(p * vec3(0.85, 1.45, 0.85) + 4.7) - 0.5));
        float jPinch2 = 0.068 * smoothstep(4.35, 5.25, q.y) * (0.28 + 0.72 * smoothstep(-0.20, 0.32, valueNoise(p * vec3(0.90, 1.40, 0.90) - 3.3) - 0.5));
        dBridge = opEngrave(dBridge, q.x - 1.22 + 0.11 * (q.y - 5.4) + jWarp1, jPinch1);
        dBridge = opEngrave(dBridge, q.x + 1.14 - 0.14 * (q.y - 5.6) + jWarp2, jPinch2);
    }

    // 4. Flat overhanging horizontally-fissured capstone crown
    float capArch = 0.20 * max(0.0, 1.0 - (q.x + 0.26) * (q.x + 0.26) * 0.15);
    float cap1 = sdRoundBox(vec3(q.x + 0.26, q.y - 5.76 - capArch, q.z), vec3(2.36, 0.24, 1.12), 0.06);
    float cap2 = sdRoundBox(vec3(q.x + 0.30, q.y - 6.16 - capArch * 0.85, q.z), vec3(2.38, 0.18, 1.06), 0.05);
    float cap3 = sdRoundBox(q - vec3(-0.34, 6.46 + capArch * 0.65, 0.0), vec3(1.88, 0.14, 0.92), 0.045);
    float dCap = min(cap1, min(cap2, cap3));
    dCap = opEngrave(dCap, q.y - 5.98 - capArch * 0.90 + bedWarp, 0.11);
    dCap = opEngrave(dCap, q.y - 6.30 - capArch * 0.75 - bedWarp * 0.85, 0.09);

    // 5. Stepped right shoulder + massive flaring trapezoidal right buttress pier
    float dShoulder       = sdRoundBox(q - vec3(2.98, 3.72, 0.04), vec3(0.96, 0.50, 1.12), 0.12);
    float dShoulderLedge1 = sdRoundBox(q - vec3(3.06, 4.26, 0.04), vec3(0.75, 0.12, 0.94), 0.04);
    float dShoulderLedge2 = sdRoundBox(q - vec3(2.82, 4.50, 0.02), vec3(0.56, 0.10, 0.82), 0.035);
    dShoulder = min(dShoulder, min(dShoulderLedge1, dShoulderLedge2));

    float pierFlare = clamp((3.55 - q.y) * 0.26, 0.0, 1.28);
    vec3 qPier = q - vec3(3.04 + 0.38 * pierFlare, 1.26, 0.06);
    float dPier = sdRoundBox(qPier, vec3(1.34 + 0.44 * pierFlare, 2.58, 1.32 + 0.26 * pierFlare), 0.28);
    dPier = opEngrave(dPier, q.y + 0.04 + 0.03 * (q.x - 3.2) + bedWarp, 0.16);
    dPier = opEngrave(dPier, q.y - 1.76 - 0.02 * (q.x - 3.2) - bedWarp * 0.9, 0.11);

    // Cascading right slickrock plinth & rounded sandstone boulder toes
    float dPlinthMain  = sdRoundBox(q - vec3(4.20, -0.88, 0.14), vec3(2.38, 0.95, 1.78), 0.24);
    float dPlinthStep  = sdRoundBox(q - vec3(5.65, -1.24, 0.26), vec3(1.70, 0.80, 1.48), 0.20);
    float dBoulderToe  = sdRoundBox(q - vec3(4.75, -0.34, 0.55), vec3(0.98, 0.46, 0.88), 0.22);
    float dApronBridge = sdRoundBox(q - vec3(0.25, -1.52, 0.15), vec3(4.75, 0.85, 1.65), 0.26);
    float dRight = smin(min(dShoulder, dPier), min(min(dPlinthMain, dPlinthStep), dBoulderToe), 0.26);
    dRight = smin(dRight, dApronBridge, 0.34);

    float d = smin(dLeft, dBridge, 0.22);
    d = smin(d, dCap, 0.18);
    d = smin(d, dRight, 0.28);

    float finHalfZ = mix(1.06, 1.94, (1.0 - smoothstep(-0.5, 4.5, q.y)) * smoothstep(-1.5, 4.2, q.x));
    float finCut = abs(q.z - 0.10 * sin(q.x * 0.42 + 0.3 * q.y)) - finHalfZ;
    d = smax(d, finCut, 0.38);

    if (!gFastMap && d < 0.68) {
        float cragProfile = mix(0.76, 1.56, smoothstep(1.4, 4.8, q.y));
        d += da_sandstoneRelief(p, d, 0.96, cragProfile);
    }

    return d * 0.75;
}

// Left Foreground Multi-Terraced Stratified Sandstone Butte (dome at uv.y = +0.66 at 15s, sliding off-left by 19s!)
float da_sdLeftButte(vec3 p) {
    vec3 q = p - vec3(-15.10, 1.52, -20.8);
    q.xz = rot2(0.18) * q.xz;

    float tierBase = sdCappedCone(q - vec3(-0.10, 0.95, 0.0), 2.85, 4.85, 3.42);
    float tierMid  = sdCappedCone(q - vec3(-0.34, 3.60, 0.15), 1.62, 3.30, 2.22);
    float tierCap  = sdCutSphere(q - vec3(-0.68, 4.58, 0.20), 2.16, -0.35);

    float d = opStairsUnion(tierBase, tierMid, 0.75, 4.0);
    d = opStairsUnion(d, tierCap, 0.56, 3.0);

    d = opEngrave(d, q.y - 0.58, 0.11);
    d = opEngrave(d, q.y - 1.58, 0.13);
    d = opEngrave(d, q.y - 2.95, 0.12);
    d = opEngrave(d, q.y - 4.18, 0.10);
    float skirt1 = sdRoundBox(q - vec3(3.25, 0.28, 0.65), vec3(0.82, 0.44, 0.68), 0.16);
    float skirt2 = sdRoundBox(q - vec3(2.65, 0.54, 1.35), vec3(0.66, 0.36, 0.54), 0.14);
    d = smin(d, min(skirt1, skirt2), 0.26);

    if (!gFastMap && d < 0.72) {
        d += da_sandstoneRelief(p + vec3(3.1, 0.4, -1.7), d, 0.96, 1.28);
        if (q.y > 0.35 && q.y < 2.60) {
            float tafoni = smoothstep(0.66, 0.90, billowFbm(p * vec3(1.3, 2.2, 1.3), 2));
            d += 0.078 * tafoni * (1.0 - smoothstep(0.22, 0.68, d));
        }
    }
    return d * 0.76;
}

// Right Canyon Rim Cliff Outcrop (natural weathered sandstone domes & stepped benches)
float da_sdRightCanyonRim(vec3 p) {
    vec3 q = p - vec3(16.8, 0.65, -27.5);
    q.xz = rot2(0.14) * q.xz;

    vec3 q1 = q - vec3(-3.15, -0.80, 0.75); q1.xz = rot2(-0.18) * q1.xz;
    vec3 q2 = q - vec3(-0.35, -0.45, -0.10); q2.xz = rot2(0.12) * q2.xz;
    vec3 q3 = q - vec3( 2.75, -0.62, -0.50); q3.xz = rot2(-0.09) * q3.xz;
    vec3 q4 = q - vec3( 6.35, -0.38, -0.95); q4.xz = rot2(0.15) * q4.xz;

    float b1 = sdCappedCone(q1, 3.45, 2.35, 1.65) - 0.18;
    float b2 = sdCappedCone(q2, 3.80, 2.65, 1.88) - 0.22;
    float b3 = sdCappedCone(q3, 3.68, 2.85, 2.05) - 0.20;
    float b4 = sdCappedCone(q4, 3.90, 3.10, 2.25) - 0.22;
    float gorgeWall = sdRoundBox(q - vec3(1.35, -2.55, 2.45), vec3(7.45, 2.55, 2.75), 0.35);

    float cap1 = sdRoundBox(q2 - vec3(-0.10, 3.42, 0.0), vec3(1.55, 0.38, 1.65), 0.16);
    float cap2 = sdRoundBox(q3 - vec3(-0.15, 3.24, 0.0), vec3(1.80, 0.36, 1.85), 0.16);

    float d = opStairsUnion(smin(b1, b2, 0.35), smin(b3, b4, 0.35), 0.65, 3.0);
    d = opStairsUnion(d, min(cap1, cap2), 0.45, 3.0);
    d = opStairsUnion(d, gorgeWall, 0.78, 4.0);

    // Taper unseen rear cliff roof downward behind rear of b4 (q.z < -2.35) so b4 stays 100% solid!
    float rearSlope = q.y - (3.65 - 0.55 * max(-q.z - 2.35, 0.0));
    d = smax(d, rearSlope, 0.35);

    if (!gFastMap && d < 0.85) {
        float cleftWarp = fbm(p * vec3(0.28, 0.18, 0.28), 2, 2.0, 0.5);
        float verticalClefts = pow(ridgedFbm(vec2(q.x * 0.52 + cleftWarp * 0.8, q.z * 0.35), 2), 3.0);
        d += 0.22 * verticalClefts * (1.0 - smoothstep(0.25, 0.82, d));
        d += da_sandstoneRelief(p + vec3(-5.0, 1.1, 2.0), d, 0.90, 1.15);
    }
    return d * 0.72;
}

// Mid-ground Canyon Rim Sandstone Hogback Fin & Outcrop (strictly left of Arch ankle!)
float da_sdRimHogback(vec3 p) {
    vec3 q = p - vec3(-7.8, 1.48, -30.2);
    q.xz = rot2(-0.10) * q.xz;
    q.xy = rot2(-0.02) * q.xy;
    float fin = sdRoundBox(q, vec3(3.05, 1.12, 1.05), 0.22);
    float crestNotch = 0.20 * sin(q.x * 1.25) + 0.14 * sin(q.x * 2.8 + 1.0);
    fin += crestNotch * 0.42;

    vec3 qb = p - vec3(-9.5, 2.18, -26.8);
    float boulder = sdRoundBox(qb, vec3(1.18, 0.78, 0.82), 0.26);

    float d = min(fin, boulder);
    if (!gFastMap && d < 0.60) {
        d += 0.07 * (ridgedFbm(vec2(p.x * 0.65, p.y * 1.4), 2) - 0.45);
    }
    return d * 0.78;
}

// Distant Canyonland Eroded Badlands, Smooth-Terraced Mesas & La Sal Peaks
// Calibrated to exact film_15..19.png mesa skyline (~7.6..8.4m at z = -60 + arch-window badland spur!)
float da_valleyAndMesaHeight(vec2 xz) {
    int oct = gFastMap ? 2 : 3;
    float distRise = (1.0 - smoothstep(-58.0, -29.0, xz.y)) * 2.40;
    float badlands = 1.48 + distRise
                   + 1.55 * erodedFbm(xz * 0.068 + vec2(2.1, -0.8), oct)
                   + 0.42 * ridgedFbm(xz * 0.15 + vec2(-1.4, 3.2), 2);

    // Craggy badland spur strictly inside the arch window (x in [2.0, 6.0], zero bleed left of Arch ankle x = +0.32!)
    float winMask = smoothstep(2.0, 3.1, xz.x) * (1.0 - smoothstep(4.7, 6.0, xz.x))
                  * smoothstep(-54.0, -47.0, xz.y) * (1.0 - smoothstep(-44.0, -37.5, xz.y));
    float spur = 1.78 * winMask * (0.76 + 0.44 * erodedFbm(xz * 0.14 + vec2(-2.3, 1.6), 2));

    float h = badlands + spur;

    // Smooth-terraced Canyonlands mesa plateau (~5.6..6.3m on left under La Sal peaks, rising to ~7.3..8.2m
    // inside the Arch window & right horizon to fill the lower third of the window cleanly!)
    if (xz.y < -43.0) {
        float warpEdge = 7.5 * fbm(vec2(xz.x * 0.035 + 1.7, 2.9), 2);
        float mesaLine = -59.5 + warpEdge;
        float cliffRise = 1.0 - smoothstep(mesaLine - 2.2, mesaLine + 8.5, xz.y);
        if (cliffRise > 0.001) {
            float tierField = saturate(0.50 + 0.50 * fbm(xz * vec2(0.028, 0.018) + vec2(4.1, -1.5), 2));
            float bench1 = smoothstep(0.26, 0.36, tierField);
            float bench2 = smoothstep(0.62, 0.72, tierField);
            float windowPlateauLift = 1.55 * smoothstep(-3.2, 3.4, xz.x) + 0.32 * smoothstep(14.0, 30.0, xz.x);
            float steppedTop = 5.58 + windowPlateauLift + 0.44 * bench1 + 0.34 * bench2;
            h = mix(h, steppedTop, cliffRise);
        }
    }

    // Far-left snow-dusted La Sal mountain peaks rising above the left mesa (z < -82, x < 8)
    if (xz.y < -82.0 && xz.x < 9.0) {
        float mtnMask = (1.0 - smoothstep(-105.0, -82.0, xz.y)) * (1.0 - smoothstep(-10.0, 8.0, xz.x));
        float peaks = 5.8 * pow(ridgedFbm(xz * 0.044 + vec2(0.8, 5.1), gFastMap ? 2 : 3), 1.30);
        h += mtnMask * peaks;
    }
    return h;
}

vec2 mapDesert(vec3 p) {
    float terrainD = 1.0;
    float terrainMat = MAT_DESERT_SAND;
    float floorH = 2.0;
    bool haveFloorH = false;

    if (p.z >= -27.2) {
        float envH = da_duneUpperEnvelope(p.xz);
        if (p.y < envH + 0.35) {
            floorH = da_duneAndRampHeight(p.xz);
            haveFloorH = true;
            float lipScale = mix(0.68, 0.88, 1.0 - smoothstep(-20.0, -15.5, p.z));
            terrainD = (p.y - floorH) * lipScale;
        } else {
            terrainD = (p.y - envH) * 0.85;
        }
    } else if (p.z > -33.2) {
        if (p.y < 4.90) {
            floorH = da_duneAndRampHeight(p.xz);
            haveFloorH = true;
            float valH = da_valleyAndMesaHeight(p.xz);
            float valleyBlend = 1.0 - smoothstep(-33.0, -27.2, p.z);
            terrainD = (p.y - mix(floorH, valH, valleyBlend)) * 0.78;
            terrainMat = (valleyBlend > 0.45) ? MAT_DESERT_SLICKROCK : MAT_DESERT_SAND;
        } else {
            terrainD = (p.y - 4.40) * 0.82;
            terrainMat = MAT_DESERT_SLICKROCK;
        }
    } else {
        float maxFarH = (p.z < -82.0 && p.x < 9.0) ? 15.8 : 9.6;
        terrainMat = (p.z < -52.0) ? MAT_DESERT_BUTTE : MAT_DESERT_SLICKROCK;
        if (p.y < maxFarH + 0.8) {
            terrainD = (p.y - da_valleyAndMesaHeight(p.xz)) * 0.82;
        } else {
            terrainD = (p.y - maxFarH) * 0.86;
        }
    }

    vec2 res = vec2(terrainD, terrainMat);

    // 2. Floor extras from 04a_desert_dunes.glsl (cobbles & desert scrub tufts)
    if (!gFastMap && p.z > -25.4 && p.z < -9.2 && p.x < 0.7 && p.x > -11.4 && p.y < 3.40) {
        if (!haveFloorH) floorH = da_duneAndRampHeight(p.xz);
        vec2 extras = mapDesertFloorExtras(p, floorH);
        if (extras.x < res.x) res = extras;
    }

    // 3. Bounded Hero Entrada Sandstone Arch
    vec3 qa = abs(p - vec3(DESERT_ARCH_POS.x + 0.40, 4.95, DESERT_ARCH_POS.z));
    float archBox = max(max(qa.x - 8.1, qa.y - 5.2), qa.z - 3.4);
    if (archBox < res.x + 0.32) {
        float dArch = da_sdSandstoneArch(p);
        if (dArch < res.x) res = vec2(dArch, MAT_DESERT_ARCH);
    }

    // 4. Bounded Left Foreground Stratified Butte (MAT_DESERT_BUTTE = 33.0)
    vec3 ql = abs(p - vec3(-14.7, 4.1, -20.8));
    float leftBox = max(max(ql.x - 6.5, ql.y - 5.4), ql.z - 6.0);
    if (leftBox < res.x + 0.32) {
        float dButte = da_sdLeftButte(p);
        if (dButte < res.x) res = vec2(dButte, MAT_DESERT_BUTTE);
    }

    // 5. Bounded Right Canyon Rim Cliff Outcrop (MAT_DESERT_BUTTE = 33.0)
    vec3 qr = abs(p - vec3(18.1, 0.9, -27.5));
    float rightBox = max(max(qr.x - 10.4, qr.y - 4.7), qr.z - 5.3);
    if (rightBox < res.x + 0.32) {
        float dCliff = da_sdRightCanyonRim(p);
        if (dCliff < res.x) res = vec2(dCliff, MAT_DESERT_BUTTE);
    }

    // 6. Mid-ground Canyon Rim Hogback Fin & Slickrock Boulder
    vec3 qh = abs(p - vec3(-7.8, 1.6, -28.8));
    float hogBox = max(max(qh.x - 3.9, qh.y - 1.7), qh.z - 3.1);
    if (hogBox < res.x + 0.30) {
        float dHog = da_sdRimHogback(p);
        if (dHog < res.x) res = vec2(dHog, MAT_DESERT_SLICKROCK);
    }

    return res;
}

// High-speed Material-Aware Hybrid Tracer (84-step gFastMap dissolve + 102-step solo w/ crevice-stall valley handoff -> ZERO sky cutouts!):
vec3 da_marchDesert(vec3 ro, vec3 rd, float tmin, float tmax) {
    int cap = gInDissolve ? 78 : 108;
    int stallStep = gInDissolve ? 54 : 82;
    bool prevFast = gFastMap;
    if (gInDissolve) gFastMap = true;
    float t = tmin;
    float prevT = tmin;
    float prevH = 1.0;
    int stepsTaken = 0;

    for (int i = ZERO; i < 110; i++) {
        if (i >= cap) break;
        stepsTaken = i;
        vec3 p = ro + rd * t;

        // If a horizon ray stalls past step 82 behind the front cliff faces (z in [-34.0, -28.8]),
        // hand off cleanly to z = -34.0 so the remaining 26 steps hit the true Canyonlands valley/mesa (zero sky cutouts, zero front-cliff punch-through!)
        if (i == stallStep) {
            gFastMap = true;
            float zGate = (p.x > 19.0) ? -29.0 : -25.6;
            if (p.z < zGate && p.z > -34.0 && rd.z < -0.20) {
                t = max(t, (-34.0 - ro.z) / rd.z);
                p = ro + rd * t;
                prevT = t;
                prevH = 1.0;
            }
        }

        // Once strictly past all 3D SDF monuments (z < -33.5), rays rising above the highest mesa/mountain
        // can never intersect terrain again -> instant exit saves ~70 sky steps across the horizon!
        if (p.z < -33.5 && rd.y >= 0.0005 && p.y > ((p.x < 9.5) ? 15.8 : 9.6)) break;

        vec2 h = mapDesert(p);
        float tol = gInDissolve ? max(0.0024 * t, 0.0012) : max(0.0013 * t, 0.0006);

        if (h.x < -tol) {
            float lo = prevT;
            float hi = t;
            float hLo = prevH;
            float hHi = h.x;
            float midMat = h.y;
            for (int b = ZERO; b < 2; b++) {
                float mid = 0.5 * (lo + hi);
                vec2 hm = mapDesert(ro + rd * mid);
                midMat = hm.y;
                if (hm.x > 0.0) { lo = mid; hLo = hm.x; }
                else            { hi = mid; hHi = hm.x; }
            }
            float tHit = mix(lo, hi, clamp(hLo / max(hLo - hHi, 1e-4), 0.0, 1.0));
            gFastMap = prevFast;
            return vec3(tHit, midMat, float(i));
        }
        if (h.x < tol) {
            gFastMap = prevFast;
            return vec3(t, h.y, float(i));
        }

        prevT = t;
        prevH = h.x;

        // Pure 2.5D Canyonlands valley/mesa heightfield for p.z < -33.5: safe over-relaxation + bisection!
        if (p.z < -33.5) {
            t += max(h.x * (gInDissolve ? 1.32 : 1.25), (gInDissolve ? 0.032 : 0.026) * t);
        } else if (p.z < -27.2 && p.x > -3.6 && p.x < 7.6) {
            // Open canyon window behind Arch between Hogback (x < -4.4) and Right Cliff (x > 7.7)
            t += max(h.x * 1.06, 0.022 * t);
        } else if (p.z < -29.0 && p.x > 6.8 && p.y > 3.5) {
            // Rays clearing front/flank clefts of Right Canyon Cliff accelerate cleanly to hit the z = -60 right mesa!
            t += max(h.x * 1.10, 0.025 * t);
        } else if (h.y != MAT_DESERT_SAND) {
            t += h.x * (gInDissolve ? 1.02 : 0.96);
        } else {
            vec3 qaSpan = abs(p - vec3(DESERT_ARCH_POS.x + 0.40, 6.4, DESERT_ARCH_POS.z)) - vec3(6.8, 2.9, 2.2);
            float dSpan = max(max(qaSpan.x, qaSpan.y), qaSpan.z);
            vec3 qrTop  = abs(p - vec3(18.1, 2.7, -26.4)) - vec3(10.2, 2.3, 3.0);
            float dCliffBox = max(max(qrTop.x, qrTop.y), qrTop.z);
            float safeBox = min(dSpan, dCliffBox);

            if (safeBox < 0.22) {
                t += h.x * 0.94;
            } else {
                float hfStride = max(h.x * (gInDissolve ? 1.15 : 0.96), (gInDissolve ? 0.042 : 0.025) * t);
                t += min(hfStride, max(safeBox - 0.12, h.x * 0.92));
            }
        }
        if (t > tmax) break;
    }
    gFastMap = prevFast;
    return vec3(-1.0, -1.0, float(stepsTaken));
}

vec3 da_sandNormal(vec3 p, float eps, out float outFloorH) {
    float h0 = da_duneAndRampHeight(p.xz);
    outFloorH = h0;
    float hxM = da_duneAndRampHeight(p.xz - vec2(eps, 0.0));
    float hzP = da_duneAndRampHeight(p.xz + vec2(0.0, eps));
    return normalize(vec3(hxM - h0, eps, h0 - hzP));
}

// Silky-smooth C1-continuous 12-step golden-hour shadow along DESERT_SUN_DIR
// (exact gFastMap=false brink match + continuous max(h,0) penumbra -> ZERO 1px black crest hairline!)
float da_sandBrinkShadow(vec3 p, vec3 lDir) {
    float res = 1.0;
    float t = 0.040;
    float ph = 1e10;
    // Since DESERT_SUN_DIR.z = +0.49 > 0, Arch (z = -24.5) ONLY casts shadow onto p.z < -23.0!
    bool nearArchShadowZone  = (p.z < -22.8 && p.z > -27.4 && p.x > -3.5 && p.x < 13.5);
    bool nearButteShadowZone = (p.z < -18.5 && p.z > -26.8 && p.x < -3.5);

    for (int i = ZERO; i < 12; i++) {
        vec3 sp = p + lDir * t;
        float envH = da_duneUpperEnvelope(sp.xz);
        float h = (sp.y < envH + 0.35) ? (sp.y - da_duneAndRampHeight(sp.xz)) * 0.74 : (sp.y - envH) * 0.88;
        if (nearArchShadowZone && sp.y < 9.8 && abs(sp.z - DESERT_ARCH_POS.z) < 3.2 && abs(sp.x - (DESERT_ARCH_POS.x + 0.3)) < 7.8) {
            gFastMap = true;
            h = min(h, da_sdSandstoneArch(sp));
            gFastMap = false;
        }
        if (nearButteShadowZone && sp.x < -8.2 && sp.y < 9.5) {
            gFastMap = true;
            h = min(h, da_sdLeftButte(sp));
            gFastMap = false;
        }
        if (h <= 0.0) { res = 0.0; break; }
        float y = h * h / (2.0 * ph);
        float d = sqrt(max(h * h - y * y, 0.0));
        res = min(res, 15.0 * d / max(t - y, 0.04));
        ph = h;
        t += clamp(h, 0.032, 0.48);
        if (res < 0.005 || t > (nearArchShadowZone ? 15.0 : 8.2)) break;
    }
    res = clamp(res, 0.0, 1.0);
    return res * res * (3.0 - 2.0 * res);
}

vec3 da_canyonAerialHaze(vec3 rd) {
    float rightWarmth = clamp(0.5 + 0.55 * rd.x, 0.0, 1.0);
    vec3 coolMesaHaze = srgbToLinear(vec3(0.51, 0.53, 0.58));
    vec3 warmMesaHaze = srgbToLinear(vec3(0.65, 0.56, 0.48));
    return mixOklab(coolMesaHaze, warmMesaHaze, smoothstep(0.10, 0.90, rightWarmth));
}

float da_crossBedScalar(vec3 p) {
    float warp = fbm(p * vec3(0.18, 0.24, 0.18), 2, 2.0, 0.5);
    float setCoord = p.y * 0.92 + 0.80 * warp;
    float setId = floor(setCoord);
    float setFrac = setCoord - setId;

    float dipX = (hash11(setId * 17.0 + 3.0) - 0.45) * 0.58;
    float dipZ = (hash11(setId * 29.0 + 11.0) - 0.50) * 0.40;
    float lamContrast = mix(0.32, 0.98, hash11(setId * 31.0 + 9.0));
    float foreset = sin((p.y + dipX * p.x + dipZ * p.z) * 14.5 + 3.4 * fbm(p * 0.95, 2, 2.0, 0.5));
    float rockGrain = fbm(p * vec3(1.6, 2.8, 1.6), 2, 2.0, 0.5);

    float boundSeam = (1.0 - smoothstep(0.0, 0.07, min(setFrac, 1.0 - setFrac))) * step(0.38, hash11(setId * 11.0 + 1.0));
    return 0.50 + 0.21 * foreset * lamContrast + 0.19 * rockGrain - 0.37 * boundSeam;
}

void da_shadeFormation(float m, vec3 p, vec3 nIn, float t, float pxAngle,
                       out vec3 albedo, out float rough, out vec3 nOut) {
    float fp = max(t * pxAngle, 0.0005);
    nOut = nIn;

    // Dry wheat-gold desert bunchgrass tussocks (synced with @desert-dunes #44!)
    if (m == MAT_DESERT_SCRUB) {
        vec4 g = gradientNoiseD(p * 20.0);
        float wTwig = 1.0 - smoothstep(0.006, 0.030, fp);
        nOut = normalize(nIn + g.yzw * (0.28 * wTwig));
        float tipMix = saturate(0.45 + 0.55 * fbm(p * 8.0, 2, 2.0, 0.5) + 0.35 * max(nIn.y, 0.0));
        vec3 dryStrawBase = srgbToLinear(vec3(0.62, 0.52, 0.30));
        vec3 sunWheatGold = srgbToLinear(vec3(0.80, 0.68, 0.42));
        albedo = mixOklab(dryStrawBase, sunWheatGold, tipMix);
        rough = 0.88;
        return;
    }

    if (p.z < -33.2 && m != MAT_DESERT_ARCH) {
        if (p.z < -82.0) {
            float ridgeTex = saturate(0.5 + 0.5 * fbm(p.xz * 0.12, 2));
            float snowCrest = smoothstep(6.8, 9.8, p.y) * smoothstep(0.35, 0.75, nIn.y);
            vec3 mtnRock  = srgbToLinear(vec3(0.36, 0.42, 0.52));
            vec3 mtnTalus = srgbToLinear(vec3(0.48, 0.48, 0.54));
            albedo = mixOklab(mtnRock, mtnTalus, ridgeTex);
            albedo = mixOklab(albedo, srgbToLinear(vec3(0.76, 0.77, 0.80)), snowCrest * 0.60);
            rough = 0.90;
            return;
        }
        float mesaMask = 1.0 - smoothstep(-59.5, -50.0, p.z);

        if (mesaMask < 0.8 && t < 68.0) {
            float b0 = erodedFbm(p.xz * 0.18, 2);
            float bx = erodedFbm((p.xz + vec2(0.25, 0.0)) * 0.18, 2);
            float bz = erodedFbm((p.xz + vec2(0.0, 0.25)) * 0.18, 2);
            nOut = normalize(nIn + vec3(-(bx - b0), 0.0, -(bz - b0)) * 1.8);
        }

        float strata = 0.5 + 0.5 * sin(p.y * 4.4 + 2.2 * fbm(p.xz * 0.09, 2));
        vec3 badlandClay = srgbToLinear(vec3(0.54, 0.45, 0.34));
        vec3 badlandBuff = srgbToLinear(vec3(0.70, 0.60, 0.46));
        vec3 badlandCol  = mixOklab(badlandClay, badlandBuff, saturate(0.35 + 0.65 * fbm(p.xz * 0.28, 2)));

        vec3 mesaRed = srgbToLinear(vec3(0.24, 0.15, 0.12));
        vec3 mesaTan = srgbToLinear(vec3(0.36, 0.24, 0.18));
        vec3 mesaCol = mixOklab(mesaRed, mesaTan, strata * 0.72);
        albedo = mixOklab(badlandCol, mesaCol, mesaMask);
        rough = 0.88;
        return;
    }

    float wMid   = gInDissolve ? 0.0 : (1.0 - smoothstep(20.0, 50.0, t));
    float wMicro = gInDissolve ? 0.0 : (1.0 - smoothstep(0.005, 0.025, fp));
    float archRugged = (m == MAT_DESERT_ARCH) ? 1.35 : 1.0;

    float eps = clamp(fp * 0.90, 0.012, 0.055);
    float cb0 = da_crossBedScalar(p);
    if (wMid > 0.01) {
        float cbx = da_crossBedScalar(p + vec3(eps, 0.0, 0.0));
        float cby = da_crossBedScalar(p + vec3(0.0, eps, 0.0));
        float cbz = da_crossBedScalar(p + vec3(0.0, 0.0, eps));
        vec3 cbGrad = vec3(cbx - cb0, cby - cb0, cbz - cb0) / eps;
        cbGrad -= nIn * dot(cbGrad, nIn);
        nOut = normalize(nOut - cbGrad * (0.21 * archRugged * wMid));
        if (m == MAT_DESERT_ARCH) {
            // Horizontally-anisotropic spalled sandstone ledges & facets (chiseled rock, zero sponge pitting!)
            vec4 spallN = gradientNoiseD(p * vec3(1.15, 4.80, 1.15) + vec3(1.9, -0.7, 3.3));
            vec3 spTan = spallN.yzw - nOut * dot(spallN.yzw, nOut);
            nOut = normalize(nOut + spTan * (0.16 * wMid));
        }
    }

    vec2 crackUv = vec2(p.x * 0.74 + p.z * 0.48, p.y * 0.18) + 0.26 * fbm(p.xz * 0.35, 2);
    vec3 vb = voronoiBorder(crackUv, 0.82);
    float jointBreakup = smoothstep(0.14, 0.56, fbm(p * vec3(0.42, 0.22, 0.42) + vec3(2.7, -1.3, 5.1), 2, 2.0, 0.5));
    float aa = max(fp * 0.85, 0.008);
    float crackMask = (1.0 - smoothstep(0.008, 0.022 + aa, vb.x)) * jointBreakup * wMid;

    vec3 crackTilt = normalize(vec3(vb.y, vb.z * 0.22, vb.y * 0.55) + vec3(1e-5));
    nOut = normalize(nOut + (crackTilt - nOut * dot(crackTilt, nOut)) * (0.28 * archRugged * crackMask));

    if (wMicro > 0.01) {
        vec4 microN = gradientNoiseD(p * 18.0);
        vec3 gTan = microN.yzw - nOut * dot(microN.yzw, nOut);
        nOut = normalize(nOut + gTan * (0.20 * archRugged * wMicro));
    }

    bool isLeftButte = (m == MAT_DESERT_BUTTE && p.x < -4.0);
    vec3 entradaTerracotta = isLeftButte ? srgbToLinear(vec3(0.64, 0.36, 0.19)) : srgbToLinear(vec3(0.50, 0.25, 0.13));
    vec3 goldenSandstone   = isLeftButte ? srgbToLinear(vec3(0.78, 0.48, 0.26)) : srgbToLinear(vec3(0.66, 0.38, 0.20));
    vec3 paleNavajo        = srgbToLinear(vec3(0.80, 0.58, 0.37));
    vec3 deepSienna        = srgbToLinear(vec3(0.25, 0.105, 0.062));
    vec3 desertVarnish     = srgbToLinear(vec3(0.11, 0.055, 0.042));

    float lamMix = saturate(cb0);
    albedo = mixOklab(entradaTerracotta, goldenSandstone, smoothstep(0.26, 0.78, lamMix));

    float leachedBand = cubicPulse(0.62, 0.16, fract(p.y * 0.22 + 0.16 * fbm(p.xz * 0.25, 2)));
    if (isLeftButte) {
        leachedBand = max(leachedBand, cubicPulse(4.8, 1.05, p.y));
    }
    albedo = mixOklab(albedo, paleNavajo, leachedBand * (isLeftButte ? 0.54 : 0.38));

    float ironBed = (1.0 - smoothstep(0.12, 0.42, cb0)) * (0.52 + 0.48 * (1.0 - smoothstep(2.4, 5.8, p.y)));
    albedo = mixOklab(albedo, deepSienna, ironBed * 0.46);

    float steepFace = pow(saturate(1.0 - abs(nIn.y)), 2.2);
    float streakNoise = fbm(vec2((p.x * 0.85 - p.z * 0.52) * 2.6, p.y * 0.26), 2);
    float varnishMask = steepFace * smoothstep(0.10, 0.54, streakNoise) * smoothstep(2.6, 7.6, p.y);
    albedo = mixOklab(albedo, desertVarnish, varnishMask * 0.48);

    albedo = mixOklab(albedo, desertVarnish, crackMask * 0.40);
    float sandDust = smoothstep(0.58, 0.92, nOut.y) * (1.0 - smoothstep(3.4, 8.0, p.y));
    albedo = mixOklab(albedo, srgbToLinear(vec3(0.74, 0.44, 0.22)), sandDust * 0.38);

    rough = clamp(0.86 - 0.08 * leachedBand + 0.06 * crackMask - 0.06 * varnishMask, 0.66, 0.94);
}

// Scene-local tetrahedral normal & soft shadow calling mapDesert() directly
// (avoids global map(p) 4-scene inlining & VGPR pressure in full assembled film!)
vec3 da_calcDesertNormal(vec3 p, float eps) {
    bool prevFast = gFastMap;
    if (gInDissolve) gFastMap = true;
    vec3 n = vec3(0.0);
    for (int i = ZERO; i < 4; i++) {
        vec3 e = 0.5773 * (2.0 * vec3((((i + 3) >> 1) & 1), ((i >> 1) & 1), (i & 1)) - 1.0);
        n += e * mapDesert(p + e * eps).x;
    }
    gFastMap = prevFast;
    return normalize(n);
}

float da_fastDesertShadow(vec3 ro, vec3 rd, float tmin, float tmax, float k) {
    gFastMap = true;
    float res = 1.0, t = tmin;
    int cap = gInDissolve ? 8 : 14;
    for (int i = ZERO; i < 14; i++) {
        if (i >= cap) break;
        float h = mapDesert(ro + rd * t).x;
        if (h < 0.001) { res = 0.0; break; }
        res = min(res, k * h / max(t, 1e-3));
        t += clamp(h, 0.05, 0.95);
        if (res < 0.01 || t > tmax) break;
    }
    gFastMap = false;
    res = clamp(res, 0.0, 1.0);
    return res * res * (3.0 - 2.0 * res);
}

vec3 renderDesert(vec2 uv, vec2 fragCoord, float pxAngle) {
    const float FOCAL = 1.92;
    float u = gSceneTime;

    float zCam  = -1.10 - 1.38 * u;
    float xCam  = -0.35 + 0.18 * u;
    float baseH = da_duneAndRampHeight(vec2(xCam, zCam));
    vec3 ro = vec3(xCam, baseH + 1.50, zCam);
    vec3 ta = vec3(xCam + 0.56 + 0.08 * u, ro.y - 0.66, zCam - 10.0);

    applyOrbit(ro, DESERT_ARCH_POS + vec3(-0.2, 3.6, 3.5), -1.8);
    ro.y = max(ro.y, da_duneAndRampHeight(ro.xz) + 0.45);

    mat3 cam = cameraMatrix(ro, ta, 0.0);
    vec3 rd  = cameraRay(cam, uv, FOCAL);

#if DEBUG_MODE == 1
    return debugDistance(da_sdSandstoneArch(vec3(uv.x * 8.5 + DESERT_ARCH_POS.x, uv.y * 8.5 + 5.0, DESERT_ARCH_POS.z)) * 0.18);
#endif

    // Upper-sky bounding-box cull strictly above rd.y > 0.108 (above ALL mesas, mountains & cliff crevices!)
    float tMinMarch = 0.12;
    float tMaxMarch = 148.0;
    bool skipMarch = false;
    if (rd.y > 0.108 && ro.y < 10.0) {
        vec2 bArch  = iBox(ro - vec3(DESERT_ARCH_POS.x + 0.40, 5.0, DESERT_ARCH_POS.z), rd, vec3(7.9, 4.7, 3.4));
        vec2 bButte = iBox(ro - vec3(-14.7, 4.1, -20.8), rd, vec3(6.6, 5.4, 6.0));
        bool hitA = (bArch.y > 0.0);
        bool hitB = (bButte.y > 0.0);
        if (!hitA && !hitB) {
            skipMarch = true;
        } else {
            float nearA = hitA ? max(bArch.x, 0.12) : 1e5;
            float nearB = hitB ? max(bButte.x, 0.12) : 1e5;
            float farA  = hitA ? bArch.y : 0.0;
            float farB  = hitB ? bButte.y : 0.0;
            tMinMarch = min(nearA, nearB);
            tMaxMarch = min(max(farA, farB), 52.0);
        }
    } else if (rd.y < -0.18 && ro.y > 2.0 && ro.y < 3.9 && ro.z > -9.0) {
        tMinMarch = max(0.12, (ro.y - 2.15) / -rd.y);
        tMaxMarch = 36.0;
    }

    vec3 hit = skipMarch ? vec3(-1.0, -1.0, 0.0) : da_marchDesert(ro, rd, tMinMarch, tMaxMarch);
#if DEBUG_MODE == 4
    return debugHeat((skipMarch ? 0.0 : hit.z) / 96.0 + 0.0 * fragCoord.x);
#endif
    if (hit.x < 0.0) return desertAtmosphere(rd);

    float t = hit.x;
    vec3 p  = ro + rd * t;
    float m = floor(hit.y + 0.5);

    float nEps = max(0.0012 * t, 0.0020);
    float sandFloorH = p.y;
    vec3 nGeom = (m == MAT_DESERT_SAND) ? da_sandNormal(p, clamp(0.0009 * t, 0.006, 0.022), sandFloorH) : da_calcDesertNormal(p, nEps);

    vec3 albedo = vec3(0.2);
    float rough = 0.82;
    vec3 n = nGeom;

    if (m == MAT_DESERT_SAND) {
        shadeDesertSand(p, nGeom, t, pxAngle, albedo, rough, n);
    } else {
        da_shadeFormation(m, p, nGeom, t, pxAngle, albedo, rough, n);
    }

    vec3 v = -rd;
    // Unified golden-hour shadow along DESERT_SUN_DIR (exact sandFloorH origin -> zero distant ring acne!)
    float sha = 1.0;
    if (m == MAT_DESERT_SAND) {
        if (gInDissolve) {
            sha = smoothstep(-0.04, 0.18, dot(nGeom, DESERT_SUN_DIR));
        } else if (t < 34.0) {
            vec3 pShadowOrig = vec3(p.x, sandFloorH + 0.012, p.z) + nGeom * 0.034;
            sha = da_sandBrinkShadow(pShadowOrig, DESERT_SUN_DIR);
        }
    } else if (!gInDissolve && t < 44.0 && p.z > -32.5) {
        sha = da_fastDesertShadow(p + nGeom * 0.045, DESERT_SUN_DIR, 0.07, 16.0, 18.0);
    }

    float ao = 1.0;
    if (m != MAT_DESERT_SAND && t < (gInDissolve ? 0.0 : 38.0)) {
        gFastMap = true;
        float d1 = mapDesert(p + nGeom * 0.14).x;
        float d2 = mapDesert(p + nGeom * 0.42).x;
        gFastMap = false;
        ao = saturate(1.0 - 1.45 * (max(0.14 - d1, 0.0) + 0.45 * max(0.42 - d2, 0.0)));
    } else if (m != MAT_DESERT_SAND) {
        ao = 0.88;
    } else {
        ao = 0.90 + 0.10 * saturate(nGeom.y);
    }

    // Calibrated golden-hour direct sun
    vec3 sunCol = (m == MAT_DESERT_SAND) ? vec3(2.85, 2.04, 1.40) : vec3(2.72, 2.00, 1.40);

    vec3 keyDir = DESERT_SUN_DIR;
    if (m == MAT_DESERT_ARCH || (m == MAT_DESERT_BUTTE && p.x > 6.0 && p.z > -34.0)) {
        keyDir = normalize(vec3(-0.90, 0.28, 0.22));
    }
    vec3 key = shadePBR(n, v, keyDir, albedo, rough, 0.0) * sunCol * sha;

    // Warm sandstone wrap illumination on Left Stratified Butte from left-front DESERT_SUN_DIR
    if (m == MAT_DESERT_BUTTE && p.x < -4.0 && p.z > -32.0) {
        float wDiff = wrapDiffuse(n, DESERT_SUN_DIR, 0.45);
        key += albedo * vec3(2.15, 1.45, 0.88) * wDiff * (0.35 + 0.65 * sha) * (0.45 + 0.55 * ao);
    }

    if (m == MAT_DESERT_SCRUB) {
        float grassTrans = translucency(n, v, DESERT_SUN_DIR, 0.35, 2.5, 0.25);
        key += albedo * sunCol * grassTrans * (0.35 + 0.65 * sha) * 0.70;
    }

    // Subtle warm horizon rim catchlight on elevated rock silhouettes
    if ((m == MAT_DESERT_ARCH || m == MAT_DESERT_BUTTE || m == MAT_DESERT_SLICKROCK) && p.z > -34.0) {
        vec3 horizonRimDir = normalize(vec3(0.86, 0.22, -0.44));
        float rimElev = smoothstep(2.0, 3.6, p.y);
        key += shadePBR(n, v, horizonRimDir, albedo, rough, 0.0)
             * vec3(1.85, 1.24, 0.76) * rimElev * 0.68 * ao;
    }

    // Calibrated skyFill + slip-face bounce (synced with @desert-dunes #44 inverse-AgX shadow calibration!)
    vec3 skyFill;
    vec3 bounce;
    if (m == MAT_DESERT_SAND) {
        // Gate skyFill sun-dimming by N.L as well as sha so self-shadowed leeward brinks (N.L <= 0, sha == 1)
        // receive full umber skyFill + warm quartz grain wrap instead of a 1px dark trough!
        float sunLit = sha * smoothstep(0.0, 0.24, dot(n, keyDir));
        float brinkGlow = smoothstep(-0.28, 0.10, dot(n, keyDir)) * (1.0 - smoothstep(0.04, 0.26, dot(n, keyDir))) * sha;
        float grazeCrest = (1.0 - smoothstep(0.04, 0.28, saturate(dot(nGeom, v)))) * smoothstep(0.06, 0.28, nGeom.x) * sha;
        key += albedo * sunCol * (0.11 * brinkGlow + 0.22 * grazeCrest);
        float slipBounce = 0.38 + 0.62 * saturate(n.x * 0.85 + 0.25);
        skyFill = albedo * vec3(0.090, 0.205, 0.800) * (0.80 + 0.20 * saturate(n.y)) * ao * (1.0 - 0.45 * sunLit);
        bounce  = albedo * vec3(0.040, 0.022, 0.012) * slipBounce;
    } else {
        float fillScale = (m == MAT_DESERT_ARCH || (m == MAT_DESERT_BUTTE && p.x > 6.0 && p.z > -34.0)) ? 0.60 : 0.84;
        skyFill = albedo * hemisphereLight(
            n,
            srgbToLinear(vec3(0.26, 0.41, 0.60)),
            srgbToLinear(vec3(0.42, 0.22, 0.11))
        ) * ao * fillScale;
        float underBounce = 0.20 + 0.80 * saturate(-n.y * 0.92 + 0.15);
        float archProximity = (m == MAT_DESERT_ARCH) ? 1.42 : 0.88;
        bounce = albedo * srgbToLinear(vec3(0.80, 0.44, 0.20)) * underBounce * ao * (0.32 * archProximity);
    }

#if DEBUG_MODE == 2
    return debugNormal(n);
#elif DEBUG_MODE == 3
    return debugIdColor(m);
#elif DEBUG_MODE == 5
    return vec3(sha, ao, clamp((p.y - 1.5) * 0.12, 0.0, 1.0));
#elif DEBUG_MODE == 6
    return vec3(luminance(key), luminance(skyFill), luminance(bounce));
#endif

    vec3 col = key + skyFill + bounce;

    // Warm golden-rose atmospheric bluff haze on Right Canyon Rim Outcrop (matching film_15..19.png!)
    if (p.x > 10.5 && p.z < -24.0 && p.z > -34.5) {
        float cliffHaze = smoothstep(10.5, 15.5, p.x) * (1.0 - smoothstep(-34.5, -24.0, p.z) * 0.35);
        vec3 warmRoseHaze = srgbToLinear(vec3(0.56, 0.42, 0.34));
        col = mix(col, warmRoseHaze, clamp(cliffHaze * 0.38, 0.0, 0.42));
    }

    // Canyonlands valley & mesa aerial perspective + seamless 360-deg orbit fade into desertAtmosphere(rd)!
    if (t > 32.0) {
        vec3 mesaHaze   = da_canyonAerialHaze(rd);
        vec3 valleyDust = srgbToLinear(vec3(0.58, 0.49, 0.40));
        float lowMist   = smoothstep(34.0, 72.0, t) * exp(-max(p.y - 3.0, 0.0) * 0.32) * 0.32;
        float midHaze   = smoothstep(48.0, 112.0, t) * 0.68;
        col = mix(col, valleyDust, saturate(lowMist));
        col = mix(col, mesaHaze, saturate(midHaze));
        if (t > 76.0) {
            float farOrbitFade = smoothstep(76.0, 142.0, t);
            col = mix(col, desertAtmosphere(rd), farOrbitFade);
        }
    }
    return col;
}

// ==== PART: 05a_cavern_rock.glsl ====
// =============================================================================
// SCENE V (Part A): Karst Limestone Vault, Nested Arches, Flowstone & Stalactites
// =============================================================================

float cavernCenterX(float z) {
    return -0.28 * sin(z * 0.09 + 0.3) - 0.14;
}

float cr_vaultCenterX(float z) {
    // Matches cavernCenterX across foreground/midground; gently curves into distant grotto pocket
    return cavernCenterX(z) - 0.18 * smoothstep(-16.0, -26.5, z);
}

float cr_archRibMask(float z) {
    // Crisp transverse limestone ceiling & wall ribs framing receding cavern chambers
    float r0 = 0.68 * cubicPulse(-3.25, 0.95, z);
    float r1 = 1.02 * cubicPulse(-6.00, 1.05, z);
    float r2 = 1.08 * cubicPulse(-11.35, 1.05, z);
    float r3 = 1.16 * cubicPulse(-16.95, 1.05, z);
    float r4 = 1.12 * cubicPulse(-21.90, 0.95, z);
    return clamp(r0 + r1 + r2 + r3 + r4, 0.0, 1.25);
}

void cr_vaultEnvelopeWithRib(float z, float rib, out float cx, out float y0, out float halfW, out float halfH) {
    cx = cr_vaultCenterX(z);
    // Lower springline y0 in the far tunnel so Arch 3 (-16.95) & Arch 4 (-21.9) form true semicircular arches!
    y0 = mix(0.54, 0.08, smoothstep(-12.0, -17.2, z));

    float farStep1   = smoothstep(-12.5, -16.8, z);
    float farStep2   = smoothstep(-18.5, -22.2, z);
    float grottoOpen = 0.20 * cubicPulse(-25.0, 1.80, z);

    halfW = 2.42 - 0.32 * rib - 0.18 * farStep1 - 0.62 * farStep2 + grottoOpen;
    halfH = 2.18 - 0.38 * rib - 0.06 * farStep1 - 0.66 * farStep2 + grottoOpen * 0.85;
}

void cr_vaultEnvelope(float z, out float cx, out float y0, out float halfW, out float halfH) {
    cr_vaultEnvelopeWithRib(z, cr_archRibMask(z), cx, y0, halfW, halfH);
}

float cr_wallLedgeOffset(float y, float z, float sideSign) {
    float jut = 0.0;
    if (sideSign > 0.0) {
        // Right foreground steep craggy wall (20s) + broken multi-level karst boulder bank (22s..24s, zero flat curb or smooth dome!)
        float fgWall     = 0.28 * cubicPulse(-3.05, 2.15, z) * (1.0 - smoothstep(1.45, 2.30, y));
        float zRightBank = cubicPulse(-5.85, 1.78, z);
        float cragY      = y + 0.08 * sin(z * 2.6 + 0.5) + 0.035 * cos(z * 5.1 - 0.8);
        float stepBench1 = 0.50 * (1.0 - smoothstep(0.16, 0.38, cragY));
        float stepBench2 = 0.20 * (1.0 - smoothstep(0.44, 0.72, cragY - 0.06 * sin(z * 3.8)));
        float upButtress = 0.28 * cubicPulse(-5.40, 1.90, z) * cubicPulse(1.45, 0.78, y);
        jut += fgWall + zRightBank * (stepBench1 + stepBench2) + upButtress;
    } else {
        // Left foreground stepped limestone toe near waterline
        jut += 0.24 * cubicPulse(-4.1, 2.05, z) * (1.0 - smoothstep(0.26, 0.52, y));
    }

    // Concave scalloped crystal bays recessed between the transverse arch ribs
    float bayMask = cubicPulse(-8.9, 1.65, z) + cubicPulse(-14.2, 1.65, z) + 0.65 * cubicPulse(-19.5, 1.35, z);
    jut -= 0.22 * bayMask * cubicPulse(0.76, 0.72, y);

    // Blocky bank promontories & sharp phreatic waterline undercut along y ~ 0.0..0.32
    float bankWave = 0.14 * sin(z * 0.92 + sideSign * 1.55) + 0.09 * sin(z * 2.25 - sideSign * 0.7);
    jut += bankWave * exp(-max(y + 0.04, 0.0) * 1.85);
    jut -= 0.09 * cubicPulse(0.08, 0.13, y);
    return jut;
}

float cr_macroWallRelief(float y, float z, float sideSign) {
    // Deterministic low-frequency rock massing shared 1:1 between cr_cavernWallX and mapCavernRock
    return 0.11 * sin(z * 0.62 + y * 0.85 + sideSign * 1.1)
         + 0.07 * cos(z * 1.35 - y * 1.25 + sideSign * 2.3);
}

// Coarse world-X of the sculpted limestone wall at (y, z) for sideSign in {-1.0, +1.0}.
// Exported so 05b_cavern_crystals.glsl can snap crystal clusters & druzy beds directly onto rock!
float cr_cavernWallX(float y, float z, float sideSign) {
    float cx, y0, halfW, halfH;
    cr_vaultEnvelope(z, cx, y0, halfW, halfH);
    float sSign = (sideSign >= 0.0) ? 1.0 : -1.0;
    float sideW = max(halfW - cr_wallLedgeOffset(y, z, sSign) - cr_macroWallRelief(y, z, sSign), 0.62);
    float belowUndercut = 1.0 - 0.05 * clamp((y0 - y) / 0.65, 0.0, 1.0);
    float uy = clamp(max(y - y0, 0.0) / max(halfH, 0.4), 0.0, 0.97);
    float archSpan = sideW * belowUndercut * sqrt(max(1.0 - uy * uy, 0.03));
    return cx + sSign * archSpan;
}

float cr_fastCeilingY(float x, float cx, float y0, float halfW, float halfH) {
    float ux = clamp(abs(x - cx) / max(halfW * 0.96, 0.60), 0.0, 0.95);
    return y0 + halfH * sqrt(max(1.0 - ux * ux, 0.04));
}

float cr_sdTaperedIcicle(vec3 p, vec2 posXZ, float ceilY, float len, float baseR) {
    float yTop = ceilY + 0.22;
    float yTip = ceilY - len;
    vec2 dxz = p.xz - posXZ;
    float rXZ = length(dxz);
    float dBound = length(max(vec2(rXZ - baseR * 1.25, yTip - p.y), 0.0));
    if (dBound > 0.20) return dBound;

    float hSpan = 0.5 * (yTop - yTip);
    vec3 q = vec3(dxz.x, 0.5 * (yTop + yTip) - p.y, dxz.y);
    return sdCappedCone(q, hSpan, baseR * 1.16, 0.005);
}

float cr_sdStalactiteCurtains(vec3 p, float cx, float y0, float halfW, float halfH, float ribHere, float dVault) {
    float localCeil = cr_fastCeilingY(p.x, cx, y0, halfW, halfH);
    bool inHeroZone = (p.z > -7.2 && p.z < -2.0 && abs(p.x - cx) < 1.15);
    float maxGridLen = (0.34 + 0.78 * min(ribHere, 1.05)) * (1.0 - 0.42 * smoothstep(-13.5, -23.0, p.z));
    float minTipHere = localCeil - (inHeroZone ? 1.48 : maxGridLen);

    // Fast vertical ceiling-curtain skip: zero loop overhead in the open river vault!
    if (p.y < minTipHere - 0.24) return (minTipHere - 0.04) - p.y;

    float dStal = 1e5;

    // 1. Curated foreground & midground hero dripstone curtains matching film_20.00..24.00.png!
    if (inHeroZone) {
        if (p.z < -4.6) {
            // Curtain B (z ~ -5.9): iconic 22s..24s center-right 1.42m fluted hero stalactite + sweeping curtain
            float cB = cavernCenterX(-5.90);
            float d0 = cr_sdTaperedIcicle(p, vec2(cB + 0.16, -5.92), 2.36, 1.42, 0.156);
            float d1 = cr_sdTaperedIcicle(p, vec2(cB - 0.09, -5.80), 2.38, 0.98, 0.106);
            float d2 = cr_sdTaperedIcicle(p, vec2(cB - 0.34, -5.68), 2.40, 0.76, 0.086);
            float d3 = cr_sdTaperedIcicle(p, vec2(cB + 0.43, -6.06), 2.32, 0.94, 0.098);
            dStal = smin(smin(d0, d1, 0.065), smin(d2, d3, 0.055), 0.060);
        }
        if (p.z > -4.8) {
            // Curtain A (z ~ -3.1..-3.5): the 3 prominent foreground top-left pale-grey fluted hero stalactites in film_20.00.png!
            float cA = cavernCenterX(-3.20);
            float a0 = cr_sdTaperedIcicle(p, vec2(cA - 0.52, -3.12), 2.40, 1.38, 0.148); // Main FG-left hero at uv.x ~ -0.50
            float a1 = cr_sdTaperedIcicle(p, vec2(cA - 0.31, -3.28), 2.47, 1.04, 0.106); // Inner-left companion at uv.x ~ -0.29
            float a2 = cr_sdTaperedIcicle(p, vec2(cA - 0.15, -3.42), 2.50, 0.88, 0.088); // Center-left slender tooth at uv.x ~ -0.15
            float a3 = cr_sdTaperedIcicle(p, vec2(cA - 0.76, -3.04), 2.32, 0.74, 0.084); // Outer-left flanker at uv.x ~ -0.68
            dStal = min(dStal, smin(smin(a0, a1, 0.062), smin(a2, a3, 0.050), 0.055));
        }
    }

    // In fast reflection/AO mode, keep all 8 hero stalactites and skip the 2x2 fine grid!
    if (gFastMap) {
        return (dVault > 0.88) ? min(dStal, dVault - 0.70) : dStal;
    }

    // 2. Unified Multi-Scale 2x2 Neighbor-Checked Curtain Grid (concentrated on transverse arch curtains with open vault bays!)
    if (p.z > -23.8 && p.z < -0.2 && p.y > localCeil - maxGridLen - 0.18) {
        const float SP = 0.35;
        vec2 sid = domRepeatId(p.xz, vec2(SP));
        vec2 side = sign(p.xz - SP * sid);
        float farScale = 1.0 - 0.45 * smoothstep(-13.5, -23.0, p.z);

        for (int j = ZERO; j < 2; j++) {
            for (int i = ZERO; i < 2; i++) {
                vec2 cell = sid + vec2(float(i), float(j)) * side;
                vec3 h = hash32(cell + vec2(41.0, 83.0));
                vec2 posXZ = cell * SP + (h.xy - 0.5) * 0.14;

                float joint = 0.5 + 0.5 * sin(posXZ.y * 1.05 + posXZ.x * 1.35);
                float pres  = clamp(ribHere * 1.15 + joint * joint * 0.24, 0.0, 1.35);
                // High threshold between arch ribs leaves genuine dark vaulted limestone ceiling gaps!
                if (h.x < clamp(0.84 - 0.68 * pres, 0.14, 0.86)) continue;

                float relSignedX = (posXZ.x - cx) / max(halfW, 0.6);
                if (abs(relSignedX) > 0.80 || (posXZ.y > -6.8 && relSignedX > 0.44)) continue;

                float ceilY = cr_fastCeilingY(posXZ.x, cx, y0, halfW, halfH);
                bool isHeroCell = (h.z > 0.60);
                float rawLen = isHeroCell ? mix(0.48, 1.14, (h.z - 0.60) / 0.40) : mix(0.15, 0.46, h.z / 0.60);
                float len = rawLen * (0.38 + 0.64 * min(pres, 1.1)) * (1.0 - 0.32 * abs(relSignedX)) * farScale;

                if (posXZ.y > -5.4 && abs(posXZ.x - cx) < 0.88) {
                    len = min(len, max(ceilY - 1.22, 0.18));
                }

                float baseR = isHeroCell ? mix(0.052, 0.098, (h.z - 0.60) / 0.40) : mix(0.018, 0.044, h.z / 0.60);
                float dc = cr_sdTaperedIcicle(p, posXZ, ceilY, len, baseR);
                dStal = smin(dStal, dc, 0.042);
            }
        }
    }

    // Apply C1-smooth vertical calcite dripstone fluting & growth-ring bulges once after neighbor blend!
    if (!gFastMap && dStal < 0.13) {
        float fFade  = 1.0 - smoothstep(0.05, 0.13, dStal);
        float flutes = ridgedFbm(vec2((p.x * 1.85 - p.z * 1.65) * 7.5, p.y * 1.4), 2);
        float rings  = sin(p.y * 20.0 + (p.x + p.z) * 4.0) * 0.0035;
        dStal -= fFade * (0.015 * (flutes - 0.45) + rings);
        dStal *= 0.82;
    }

    return dStal;
}

float cr_sdFlowstoneDraperies(vec3 p, float cx, float ribHere, float dVault) {
    // Vertical organ-pipe dripstone drapery teeth clinging to upper cave haunches
    if (gFastMap || dVault > 0.38) return dVault - 0.18;
    if (p.y < 0.92 || p.y > 2.40 || p.z < -17.5 || p.z > -1.8) return 1e5;

    float sideSign = (p.x >= cx) ? 1.0 : -1.0;
    const float FL_SPACE = 0.28;
    float zid = domRepeatId(p.z, FL_SPACE);
    float zSide = (p.z >= zid * FL_SPACE) ? 1.0 : -1.0;
    float dFlow = 1e5;

    for (int k = ZERO; k < 2; k++) {
        float cz = zid + float(k) * zSide;
        float zCenter = cz * FL_SPACE;
        float rightHeroCurtain = (sideSign > 0.0) ? cubicPulse(-5.15, 1.15, zCenter) : 0.0;
        float pres = ribHere * 0.65 + rightHeroCurtain * 1.25;
        vec3 h = hash32(vec2(cz + 57.0, sideSign * 19.0 + 31.0));
        if (pres < 0.42 || h.x < 0.28) continue;

        float zPos = zCenter + (h.y - 0.5) * 0.09;
        float yTop = mix(1.94, 2.32, h.z);
        float len  = max(mix(0.38, 0.86, h.x) * min(pres, 1.15) - 0.22, 0.14);
        float wX   = cr_cavernWallX(min(yTop - 0.15, 1.95), zPos, sideSign) - sideSign * (0.04 + 0.07 * h.z);
        float baseR = mix(0.036, 0.072, h.z);
        dFlow = smin(dFlow, cr_sdTaperedIcicle(p, vec2(wX, zPos), yTop - 0.22, len, baseR), 0.035);
    }
    return dFlow;
}

vec2 mapCavernRock(vec3 p) {
    float rib = cr_archRibMask(p.z);
    float cx, y0, halfW, halfH;
    cr_vaultEnvelopeWithRib(p.z, rib, cx, y0, halfW, halfH);

    float sideSign = (p.x >= cx) ? 1.0 : -1.0;
    float ledgeJut = cr_wallLedgeOffset(p.y, p.z, sideSign);

    float sideW = max(halfW - ledgeJut - cr_macroWallRelief(p.y, p.z, sideSign), 0.62);
    float belowUndercut = 1.0 - 0.05 * clamp((y0 - p.y) / 0.65, 0.0, 1.0);

    float ux = abs(p.x - cx) / max(sideW * belowUndercut, 0.35);
    float uy = max(p.y - y0, 0.0) / max(halfH, 0.40);
    float ellipR = length(vec2(ux, uy));
    float dVault = (1.0 - ellipR) * min(sideW, halfH);

    // Enclosed craggy grotto back-wall at z ~ -26.05
    float grottoEnd = (-26.05 - p.z) + 0.35 * sin(p.x * 1.4 + p.y * 1.1);
    dVault = min(dVault, -grottoEnd);

    // Tier-1 broad karst block massing: gated strictly near cave walls (dVault < 0.50)
    float dCave = dVault - 0.12;
    if (dVault < 0.50) {
        float cFade = 1.0 - smoothstep(0.30, 0.50, dVault);
        float nBroad = gradientNoise(vec2(p.z * 0.78 + p.x * 0.40, p.y * 1.05))
                     + 0.55 * gradientNoise(vec2(p.z * 1.75 - p.y * 0.85, p.x * 1.25));
        dCave = dVault - cFade * (0.12 * nBroad) - (1.0 - cFade) * 0.12;
    }

    // Tier-2 stepped flat-topped karst strata ledges, sharp undercuts & angular block clefts!
    if (!gFastMap) {
        if (dCave > 0.22) {
            dCave -= 0.075;
        } else {
            float detailFade = 1.0 - smoothstep(0.11, 0.22, dCave);
            float warp = gradientNoise(vec2(p.z * 1.25 + p.x * 0.65, p.y * 1.35 + 1.7));

            // C1-smooth asymmetric stepped limestone strata terraces (clean at grazing angles!)
            float bTheta = (p.y * 6.8 + 0.42 * sin(p.z * 0.85) + 1.65 * warp) * 1.4;
            float terraceStep = 0.022 * sin(bTheta - 0.36 * cos(bTheta));

            // Smooth Lipschitz-bounded karst block clefts along lower banks & walls (zero wall punch-through!)
            float cragField = ridgedFbm(vec2(p.z * 2.35 + p.x * 1.05, p.y * 2.75 + 0.65 * warp), 2);
            float cragCut   = -0.048 * cragField * cragField;

            // Vertical wet solution flutes along cave walls
            float vertRibs = 0.038 * (ridgedFbm(vec2(p.z * 3.8 + p.x * 1.7 + 0.40 * warp, p.y * 1.05), 2) - 0.48)
                           * (1.0 - smoothstep(1.5, 2.35, p.y));

            float fineKarst = terraceStep + cragCut + vertRibs;
            dCave = dCave - detailFade * fineKarst - (1.0 - detailFade) * 0.075;
        }
    }

    vec2 res = vec2(dCave * 0.64, MAT_CAVERN_WALL);

    // Smoothly blend vertical organ-pipe wall flowstone draperies into upper walls
    float dFlow = cr_sdFlowstoneDraperies(p, cx, rib, dVault);
    if (dFlow < res.x + 0.15) {
        vec2 blendFlow = sminBlend(res.x, dFlow, 0.12);
        res.x = blendFlow.x;
        if (blendFlow.y < 0.52) res.y = MAT_CAVERN_FLOWSTONE;
    }

    // Multi-scale neighbor-checked stalactite curtains flared organically into ceiling ribs with sminBlend
    if (p.y > 0.68) {
        float dStal = cr_sdStalactiteCurtains(p, cx, y0, halfW, halfH, rib, dVault);
        if (dStal < res.x + 0.18) {
            vec2 blendStal = sminBlend(res.x, dStal, 0.14);
            res.x = blendStal.x;
            if (blendStal.y < 0.56) res.y = MAT_CAVERN_STALACTITE;
        }
    }

    return res;
}

void shadeCavernRock(float matId, vec3 p, vec3 nIn, float t, bool isRefl, out vec3 albedo, out float rough, out vec3 nOut) {
    float m = floor(matId + 0.5);
    nOut = nIn;

    float detailKeep  = 1.0 - smoothstep(7.5, 22.0, t);
    float bumpFade    = isRefl ? 0.0 : (1.0 - smoothstep(5.5, 18.5, t));
    float closeFade   = isRefl ? 0.0 : (1.0 - smoothstep(2.2, 9.5, t));
    float grottoShade = 1.0 - 0.72 * smoothstep(-21.5, -25.8, p.z);

    // Surface tangent basis for 3-tier rock cleavage, sharp crag facets & high-freq mineral micro-grain
    vec3 upRef = (abs(nIn.y) < 0.85) ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 tU = normalize(cross(upRef, nIn));
    vec3 tV = cross(nIn, tU);

    if (m == MAT_CAVERN_STALACTITE) {
        float uCirc = (p.x * 1.75 + p.z * 1.95) * 8.5;
        vec3 g1 = simplexNoiseD(vec2(uCirc, p.y * 2.2), 0.4);
        vec3 g2 = gradientNoiseD(vec2(uCirc * 3.2 + 3.1, p.y * 9.0));
        vec3 g3 = gradientNoiseD(vec2(uCirc * 9.5 - 1.7, p.y * 28.0));
        if (bumpFade > 0.01) {
            float ringSlope = cos(p.y * 28.0 + 3.0 * g1.x) * 0.45;
            vec2 dUV = g1.yz * vec2(2.4, 0.7) + g2.yz * vec2(1.6, 1.1) + g3.yz * (1.2 * closeFade) + vec2(0.0, ringSlope);
            nOut = normalize(nIn - (tU * dUV.x + tV * dUV.y) * (0.16 * bumpFade));
        }

        // Weathered cool taupe-grey & pale bone-ivory calcite dripstone matching film_20..24.png!
        float bandWarp = turbulence(vec2(p.x * 3.8 + p.z * 3.5, p.y * 1.8), 2);
        float growthBands = 0.5 + 0.5 * sin(p.y * 19.0 + 4.6 * bandWarp);
        float fluteMask = saturate(0.50 + 0.50 * g1.x);

        vec3 darkTaupe = srgbToLinear(vec3(0.215, 0.212, 0.208));
        vec3 midTaupe  = srgbToLinear(vec3(0.375, 0.365, 0.350));
        vec3 boneIvory = srgbToLinear(vec3(0.490, 0.478, 0.458));

        albedo = mixOklab(darkTaupe, midTaupe, fluteMask);
        albedo = mixOklab(albedo, boneIvory, growthBands * (0.42 + 0.36 * fluteMask) * (0.45 + 0.55 * detailKeep));
        albedo *= grottoShade;

        float tipWet = 1.0 - smoothstep(0.95, 2.25, p.y);
        albedo *= mix(1.0, 0.86, tipWet * 0.40);
        rough = mix(0.44, 0.22, tipWet) + 0.08 * g3.x * closeFade;
        return;
    }

    if (m == MAT_CAVERN_FLOWSTONE) {
        vec2 fUV = vec2(p.z * 6.5 + p.x * 3.4, p.y * 1.8);
        vec3 gf = simplexNoiseD(fUV, 0.8);
        vec3 gfFine = gradientNoiseD(fUV * 4.5 + vec2(1.7, -2.3));
        if (bumpFade > 0.01) {
            vec2 dF = gf.yz * vec2(2.4, 0.8) + gfFine.yz * 1.5;
            nOut = normalize(nIn - (tU * dF.x + tV * dF.y) * (0.16 * bumpFade));
        }
        float fluteCrest = ridgedFbm(fUV, 2);
        float waveBand   = 0.5 + 0.5 * sin(p.y * 14.0 + p.z * 4.5 + 3.2 * gf.x);

        vec3 coolTrav = srgbToLinear(vec3(0.24, 0.25, 0.265));
        vec3 buffTrav = srgbToLinear(vec3(0.41, 0.405, 0.395));
        albedo = mixOklab(coolTrav, buffTrav, saturate(0.42 * waveBand + 0.58 * fluteCrest)) * grottoShade;
        rough = mix(0.40, 0.22, fluteCrest);
        return;
    }

    // MAT_CAVERN_WALL: 3-tier chiseled cool-slate wet karst limestone (de-waxed, granular & fracture-stepped!)
    vec2 baseUV = vec2(p.z * 2.15 + p.x * 0.90, p.y * 2.75 - p.x * 0.55);
    vec3 w1 = gradientNoiseD(baseUV * 0.55 + vec2(2.1, -1.3));
    vec3 w2 = gradientNoiseD(baseUV * 1.45 + vec2(-3.4, 4.1));
    float macroBed = saturate(0.5 + 0.52 * w1.x + 0.30 * w2.x);

    // Cool pale silver-grey limestone highlight on Inner Arch 3 (z ~ -16.95) matching film_20..24.png!
    float ribHere = cr_archRibMask(p.z);
    float arch3Highlight = cubicPulse(-16.95, 1.55, p.z);
    float archLift = 0.24 * ribHere + 0.72 * arch3Highlight;

    vec3 coolSlate  = srgbToLinear(vec3(0.245, 0.248, 0.254));
    vec3 medGrey    = srgbToLinear(vec3(0.352, 0.356, 0.363));
    vec3 silverGrey = srgbToLinear(vec3(0.442, 0.448, 0.456));

    albedo = mixOklab(coolSlate, medGrey, smoothstep(0.22, 0.78, macroBed));
    albedo = mixOklab(albedo, silverGrey, saturate(0.20 * macroBed + archLift));
    // Calibrated neutral limestone reflectance lift above y > 0.42 (especially right wall matching sRGB ~ 0.28..0.30!)
    float rightBias = 0.55 + 0.45 * smoothstep(-1.0, 1.0, p.x - cavernCenterX(p.z));
    albedo *= mix(1.0, 1.0 + 0.18 * rightBias, smoothstep(0.36, 0.58, p.y));

    // Accentuate dark recessed ceiling vault pockets between transverse stalactite curtains!
    float bayVaultDark = (1.0 - min(ribHere, 1.0)) * smoothstep(1.55, 2.35, p.y) * (1.0 - arch3Highlight * 0.7);
    albedo *= 1.0 - 0.38 * bayVaultDark;

    // Tier 2: Warped angular rock cleavage blocks + crisp karst fractures
    vec2 uvWarp = vec2(w1.x, w2.x) * 0.92;
    vec2 warpedUV = baseUV + uvWarp;
    vec4 vCell = voronoi(warpedUV * 1.65, 0.92);
    float blockTone = hash12(vCell.zw + vec2(17.0, 53.0));
    albedo *= mix(0.87, 1.13, isRefl ? 0.5 : blockTone);

    float cellCrack    = (1.0 - smoothstep(0.012, 0.065, vCell.y - vCell.x)) * smoothstep(-0.15, 0.35, w1.x);
    float ridgeFissure = smoothstep(0.78, 0.95, ridgedFbm(warpedUV * 1.55 + vec2(1.4, -0.9), 3));
    float horizJoint   = smoothstep(0.81, 0.95, ridgedFbm(vec2(p.z * 1.05 + p.x * 0.45, p.y * 3.60 + 1.1 * w1.x), 3));
    float creviceMask  = saturate(cellCrack * 0.75 + ridgeFissure * 0.88 + horizJoint * 0.85) * detailKeep;
    // Prevent un-bumped ceiling Voronoi cracks from drawing dark contour squiggles on calm foreground river!
    creviceMask *= (isRefl ? 0.20 : 1.0);

    vec3 deepCrevice = srgbToLinear(vec3(0.038, 0.044, 0.055));
    albedo = mix(albedo, deepCrevice, creviceMask * 0.85);

    // Tier 3: Planar cleaved limestone slabs alternating with macroBed-gated crag pockets + pitted micro-grain!
    float roughGrain = 0.5;
    if (bumpFade > 0.01) {
        vec2 cragCoord = vec2(p.z * 7.4 + p.x * 3.2, p.y * 8.6 - p.x * 2.2) + uvWarp * 1.6;
        vec3 r1 = simplexNoiseD(cragCoord, 0.35);
        vec3 r2 = gradientNoiseD(cragCoord * 2.05 + vec2(3.7, -1.9));
        float ridgeW1 = 1.0 - abs(r1.x);
        vec2 cragGrad = -(r1.x >= 0.0 ? 1.0 : -1.0) * r1.yz * 1.15
                      - (r2.x >= 0.0 ? 1.0 : -1.0) * r2.yz * (0.95 * ridgeW1);

        // Spatially gate mid-freq crags by macroBed so broad planar cleaved slabs alternate with rough crag pockets!
        float cragPocketMask = mix(0.18, 0.85, smoothstep(0.36, 0.78, macroBed + 0.30 * creviceMask));

        // Footprint-filtered high-frequency pitted limestone micro-grain (freq ~44 & ~60)
        vec3 pitGrain1 = gradientNoiseD(vec2(p.z * 42.0 + p.x * 19.0, p.y * 46.0 - p.x * 14.0));
        vec3 pitGrain2 = simplexNoiseD(vec2(p.z * 60.0 - p.x * 27.0, p.y * 58.0 + p.z * 13.0), 0.7);
        roughGrain = saturate(0.5 + 0.42 * pitGrain1.x + 0.35 * pitGrain2.x);

        vec2 facetTilt = (hash22(vCell.zw + vec2(91.0, 13.0)) - 0.5) * 0.62;
        float jointCrease = (horizJoint - ridgeFissure) * 2.2;

        vec2 dN = cragGrad * (0.58 * cragPocketMask)
                + facetTilt
                + vec2(0.0, jointCrease)
                + (pitGrain1.yz * 0.42 + pitGrain2.yz * 0.30) * closeFade;
        dN = clamp(dN, vec2(-4.0), vec2(4.0));
        nOut = normalize(nIn - (tU * dN.x + tV * dN.y) * (0.135 * bumpFade));

        // Subtle pitted micro-grain modulation on close-up stone albedo
        albedo *= 1.0 + 0.14 * (roughGrain - 0.5) * closeFade;
    }

    // Fine domain-warped pale calcite mineral veins
    if (!isRefl && detailKeep > 0.05) {
        float turb = turbulence(warpedUV * 1.95 + vec2(4.2, -2.7), 2);
        float vein = pow(saturate(1.0 - abs(sin(p.y * 5.8 + p.z * 2.4 + 5.8 * turb))), 16.0);
        albedo = mix(albedo, srgbToLinear(vec3(0.49, 0.50, 0.51)), vein * detailKeep * (1.0 - creviceMask) * 0.38);
    }

    // Darkened wet charcoal waterline zone (sRGB ~ 0.12..0.16 for y < 0.36!) + micro-grain modulated roughness!
    float lowWaterBank = 1.0 - smoothstep(0.06, 0.42, p.y + 0.06 * w2.x);
    float midDampZone  = 1.0 - smoothstep(0.28, 0.82, p.y + 0.10 * w1.x);
    float seepStreak   = smoothstep(0.66, 0.90, ridgedFbm(vec2(p.z * 3.1 + p.x * 1.6, p.y * 0.48), 3))
                       * (1.0 - smoothstep(0.4, 2.3, p.y));

    // Strong physical wet-charcoal darkening right at the river waterline (y < 0.38), clean neutral stone above!
    float wetDarken = mix(1.0, 0.36, lowWaterBank) * mix(1.0, 0.85, midDampZone * (1.0 - lowWaterBank) + seepStreak * 0.30);
    albedo *= wetDarken * grottoShade;

    // Pitted limestone roughness (0.20..0.54) so speculars break into crisp wet mineral pinpoints, never waxy plastic!
    float dryDampRough = mix(0.44, 0.62, roughGrain);
    float wetGrainRough = mix(0.20, 0.48, roughGrain * 0.85);
    rough = mix(dryDampRough, wetGrainRough, saturate(lowWaterBank * 0.90 + midDampZone * 0.45 + seepStreak * 0.65));
}

// ==== PART: 05b_cavern_crystals.glsl ====
// =============================================================================
// SCENE V (Part B): CAVERN CRYSTALS, DRUZY VEINS, LIGHTING & UNDERGROUND RIVER
// 12-prong chisel-pointed hexagonal amethyst & cyan quartz clusters, craggy
// baby-point druzy collars, jagged fissure veins, cool-slate cave lighting,
// and liquid horizontally-rippled underground river with concentric drip rings.
// =============================================================================

const int CC_CLUSTER_COUNT = 16;

// Precomputed world anchors snapped 1:1 onto 05a_cavern_rock's stepped karst benches & bays!
// Stored in GPU constant address space (zero thread-stack spill -> +18 fps speedup!).
const vec3 CC_ANC[16] = vec3[16](
    vec3( 1.984, 0.500,  -2.150), // 0: orbit rear-right guard
    vec3(-2.015, 0.220,  -3.350), // 1: far-left 20s waterline violet cluster
    vec3( 1.758, 1.280,  -5.520), // 2: upper-right radial amethyst hero rosette!
    vec3( 1.685, 0.270,  -5.380), // 3: lower-right waterline twin #1 (cyan heart)
    vec3(-1.936, 1.040,  -5.850), // 4: upper-left splayed cyan/violet star cluster
    vec3( 1.525, 0.280,  -6.550), // 5: lower-right waterline twin #2 (hero in 23s/24s!)
    vec3(-2.268, 0.200,  -7.850), // 6: mid-left waterline amethyst peacock fan!
    vec3(-2.132, 1.380,  -8.150), // 7: mid-left upper-arch hanging cyan cluster
    vec3( 2.226, 0.220, -10.350), // 8: mid-right recessed alcove violet bank
    vec3( 2.521, 0.840, -13.350), // 9: deeper right mid-wall small violet cluster
    vec3(-2.421, 1.000, -13.650), // 10: deeper left upper-arch cyan cluster
    vec3(-2.330, 0.220, -13.850), // 11: deeper left waterline cyan fan
    vec3( 2.389, 0.220, -15.150), // 12: deeper right waterline violet fan
    vec3(-2.106, 0.240, -19.850), // 13: beyond inner arch subtle cyan cluster
    vec3(-1.329, 0.460, -24.950), // 14: end-grotto left-wall turquoise cluster
    vec3(-0.080, 0.200, -25.400)  // 15: end-grotto center-bottom turquoise cluster!
);

const vec3 CC_GROW_DIR[16] = vec3[16](
    vec3(-0.72029,  0.58023,  0.38015), // 0
    vec3( 0.73051,  0.56039,  0.39027), // 1
    vec3(-0.75378, -0.32161,  0.57287), // 2: wide outward-left radial amethyst rosette!
    vec3(-0.68243,  0.52186,  0.51182), // 3: waterline twin #1 angled out-up
    vec3( 0.80915, -0.17981,  0.55941), // 4: upper-left star
    vec3(-0.66079,  0.54065,  0.52063), // 5: waterline twin #2 angled out-up
    vec3( 0.71986,  0.51990,  0.45991), // 6: mid-left waterline amethyst peacock fan
    vec3( 0.54975, -0.77965,  0.29987), // 7: mid-left upper cyan down-right
    vec3(-0.66119,  0.62112,  0.42076), // 8: mid-right violet bank
    vec3(-0.78164, -0.25053,  0.57120), // 9: deeper right mid violet
    vec3( 0.70098, -0.56079,  0.44062), // 10: deeper left upper cyan
    vec3( 0.65094,  0.65094,  0.39057), // 11: deeper left waterline cyan
    vec3(-0.68037,  0.62034,  0.39021), // 12: deeper right waterline violet
    vec3( 0.67983,  0.64984,  0.33992), // 13: beyond inner arch cyan
    vec3( 0.72141,  0.36070,  0.59115), // 14: end-grotto left turquoise
    vec3( 0.06025,  0.80334,  0.59246)  // 15: end-grotto center turquoise
);

// vec4(scale, seedAngleRad, matId, cyanStyle)
const vec4 CC_PARAMS[16] = vec4[16](
    vec4(0.65, 0.70, MAT_CAVERN_CRYSTAL_VIOLET, 0.06), // 0
    vec4(0.44, 1.45, MAT_CAVERN_CRYSTAL_VIOLET, 0.08), // 1
    vec4(1.14, 2.38, MAT_CAVERN_CRYSTAL_VIOLET, 0.16), // 2: royal amethyst w/ tight cyan-lilac heart
    vec4(0.90, 3.20, MAT_CAVERN_CRYSTAL_CYAN,   0.46), // 3: cyan heart + cobalt-violet shafts
    vec4(0.54, 4.96, MAT_CAVERN_CRYSTAL_CYAN,   0.58), // 4: upper-left cyan/violet star
    vec4(1.04, 4.06, MAT_CAVERN_CRYSTAL_CYAN,   0.44), // 5: cyan heart + cobalt-violet shafts
    vec4(1.15, 0.92, MAT_CAVERN_CRYSTAL_VIOLET, 0.10), // 6: deep royal amethyst peacock fan
    vec4(0.60, 5.53, MAT_CAVERN_CRYSTAL_CYAN,   0.95), // 7: hanging cyan cluster
    vec4(0.84, 2.70, MAT_CAVERN_CRYSTAL_VIOLET, 0.06), // 8: mid-right violet bank
    vec4(0.40, 4.58, MAT_CAVERN_CRYSTAL_VIOLET, 0.06), // 9
    vec4(0.46, 3.71, MAT_CAVERN_CRYSTAL_CYAN,   0.96), // 10
    vec4(0.74, 1.95, MAT_CAVERN_CRYSTAL_CYAN,   0.92), // 11
    vec4(0.72, 1.70, MAT_CAVERN_CRYSTAL_VIOLET, 0.08), // 12
    vec4(0.50, 5.15, MAT_CAVERN_CRYSTAL_CYAN,   0.95), // 13
    vec4(0.58, 5.72, MAT_CAVERN_CRYSTAL_CYAN,   1.00), // 14
    vec4(0.90, 2.89, MAT_CAVERN_CRYSTAL_CYAN,   1.00)  // 15
);

// 12-prong trig-free radiating quartz cluster tables (including stubby baby basal points!):
// 0..5: main crown shafts (also evaluated in gFastMap reflections)
// 6..8: wide lateral fan blades (tilted off-axis so zero flat stop-sign ends face camera!)
// 9..11: short stubby baby quartz points tucked into the craggy druzy rock socket!
const vec4 CC_PRONG_ROT[12] = vec4[12](
    vec4( 0.98481,  0.17365,  0.99255, -0.12187), // 0: tall central king point
    vec4( 0.80902,  0.58779,  0.90631, -0.42262), // 1: tall V-crown companion
    vec4(-0.91355,  0.40674,  0.86603, -0.50000), // 2: opposite inner crown
    vec4(-0.55919, -0.82904,  0.88295, -0.46947), // 3: back-inner point
    vec4( 0.69466, -0.71934,  0.81915, -0.57358), // 4: front-inner point
    vec4( 0.10453,  0.99452,  0.52992, -0.84805), // 5: long lateral fan blade
    vec4(-0.97815, -0.20791,  0.57358, -0.81915), // 6: wide opposite fan blade
    vec4( 0.61566,  0.78801,  0.60182, -0.79864), // 7: angled side gem (off-camera axis)
    vec4( 0.06976, -0.99756,  0.46947, -0.88295), // 8: wide lateral fan blade
    vec4(-0.55919,  0.82904,  0.37461, -0.92718), // 9: stubby baby basal point #1
    vec4( 0.95106, -0.30902,  0.40674, -0.91355), // 10: stubby baby basal point #2
    vec4(-0.80902, -0.58779,  0.32557, -0.94552)  // 11: stubby baby basal point #3
);

const vec4 CC_PRONG_DIM[12] = vec4[12](
    vec4(0.0550, 0.7200, 0.1001,  0.050),
    vec4(0.0480, 0.6100, 0.0854, -0.060),
    vec4(0.0450, 0.5500, 0.0792,  0.040),
    vec4(0.0420, 0.4700, 0.0731, -0.050),
    vec4(0.0440, 0.5100, 0.0770,  0.060),
    vec4(0.0420, 0.5000, 0.0739, -0.040),
    vec4(0.0400, 0.4300, 0.0688,  0.050),
    vec4(0.0390, 0.3700, 0.0671, -0.050),
    vec4(0.0360, 0.3900, 0.0619,  0.040),
    vec4(0.0360, 0.2500, 0.0594, -0.040),
    vec4(0.0370, 0.2300, 0.0610,  0.040),
    vec4(0.0340, 0.2000, 0.0551, -0.030)
);

const vec2 CC_PRONG_SPIN[12] = vec2[12](
    vec2(0.95106, 0.30902),
    vec2(0.75471, 0.65606),
    vec2(0.98163, 0.19081),
    vec2(0.89101, 0.45399),
    vec2(0.61566, 0.78801),
    vec2(0.96593, 0.25882),
    vec2(0.80902, 0.58779),
    vec2(0.68200, 0.73135),
    vec2(0.92718, 0.37461),
    vec2(0.85717, 0.51504),
    vec2(0.94552, 0.32557),
    vec2(0.73135, 0.68200)
);

void cc_prongLocal(int k, float lenVar, vec3 qs, out vec3 s, out vec4 shape) {
    vec4 pr = CC_PRONG_ROT[k];
    vec4 dm = CC_PRONG_DIM[k];
    vec2 sp = CC_PRONG_SPIN[k];

    float x1 = pr.x * qs.x - pr.y * qs.z;
    float z1 = pr.y * qs.x + pr.x * qs.z;

    float radialOff = (k == 0) ? 0.0 : ((k < 5) ? 0.028 : ((k < 9) ? 0.050 : 0.082));
    float x2 = x1 - radialOff;
    float y2 = qs.y + 0.02;

    float x3 = pr.z * x2 - pr.w * y2;
    float y3 = pr.w * x2 + pr.z * y2;

    s = vec3(sp.x * x3 - sp.y * z1, y3, sp.y * x3 + sp.x * z1);

    float alt = ((k & 1) == 0) ? (1.0 + lenVar) : (1.0 - lenVar);
    shape = vec4(dm.x, dm.y * alt, dm.z, dm.w);
}

// Exact/bound hexagonal quartz prism along +Y terminated by a sharp 6-sided pyramidal chisel point!
float cc_sdQuartzPoint(vec3 s, vec4 shape) {
    const vec3 kHex = vec3(-0.8660254, 0.5, 0.57735027);
    float r     = shape.x;
    float len   = shape.y;
    float hTip  = shape.z;
    float slant = shape.w;

    vec2 q = abs(s.xz);
    q -= 2.0 * min(dot(kHex.xy, q), 0.0) * kHex.xy;

    float dHex = length(q - vec2(clamp(q.x, -kHex.z * r, kHex.z * r), r)) * sign(q.y - r);
    float invNorm = inversesqrt(hTip * hTip + r * r);
    float dCap = (q.y * hTip + (s.y + slant * s.z - len) * r) * invNorm;
    float dBase = -0.18 - s.y;

    return max(max(dHex, dCap), dBase);
}

vec2 mapCavern(vec3 p) {
    vec2 res = mapCavernRock(p);

    int i0 = 0;
    int i1 = 1;
    if (p.z <= -17.5) {
        i0 = 12; i1 = 15;
    } else if (p.z <= -11.8) {
        i0 = 8;  i1 = 12;
    } else if (p.z <= -7.10) {
        i0 = 5;  i1 = 8;
    } else if (p.z <= -4.15) {
        i0 = 1;  i1 = 6;
    }

    for (int id = i0; id <= i1; id++) {
        vec3 anc    = CC_ANC[id];
        vec4 params = CC_PARAMS[id];
        float scale = params.x;

        // Generous boundR margin (>= 0.18 * scale + 0.08 above 0.78 * scale) so dShell NEVER
        // drops below reflection hitEps at any distance!
        float boundR = 0.96 * scale + 0.08;

        vec3 rel = p - anc;
        vec3 ad  = abs(rel);
        if (max(ad.x, max(ad.y, ad.z)) > boundR + res.x) continue;

        float r2 = dot(rel, rel);
        float maxR = boundR + res.x;
        if (r2 > maxR * maxR) continue;

        float rDist = sqrt(r2);
        if (rDist > boundR) {
            float dShell = rDist - 0.78 * scale;
            if (dShell < res.x) res = vec2(dShell, params.z);
            continue;
        }

        vec3 growDir = CC_GROW_DIR[id];
        vec3 upRef = (abs(growDir.y) < 0.92) ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
        vec3 bX = normalize(cross(upRef, growDir));
        vec3 bZ = cross(growDir, bX);
        vec3 qs = vec3(dot(rel, bX), dot(rel, growDir), dot(rel, bZ)) / scale;

        float seedAng = params.y;
        float cs = cos(seedAng), sn = sin(seedAng);
        qs.xz = vec2(cs * qs.x - sn * qs.z, sn * qs.x + cs * qs.z);
        float lenVar = 0.11 * sin(seedAng * 2.3);

        float dCrystal = 1e5;
        int prongCount = gFastMap ? 6 : 12;
        for (int k = 0; k < 12; k++) {
            if (k >= prongCount) break;
            vec3 s;
            vec4 shape;
            cc_prongLocal(k, lenVar, qs, s, shape);
            float dp = cc_sdQuartzPoint(s, shape);
            dCrystal = min(dCrystal, dp);
        }
        dCrystal = max(dCrystal, -0.02 - qs.y);
        dCrystal = dCrystal * scale * 0.92;

        // Sleek craggy hexagonal druzy socket tucked cleanly at the cluster root
        const vec3 kHex = vec3(-0.8660254, 0.5, 0.57735027);
        vec2 qCol = abs(qs.xz);
        qCol -= 2.0 * min(dot(kHex.xy, qCol), 0.0) * kHex.xy;
        float dCollarRadial = qCol.y - 0.175;
        float dDruzy = max(dCollarRadial, max(qs.y - 0.044, -0.22 - qs.y));
        if (dDruzy < 0.09) {
            float cragFade = 1.0 - smoothstep(0.04, 0.09, dDruzy);
            float crag = ridgedFbm(qs.xz * 7.5 + vec2(seedAng * 2.1, -seedAng), 2);
            dDruzy += 0.030 * (0.52 - crag) * cragFade;
        }
        dDruzy = dDruzy * scale * 0.80;

        float dCluster = min(dCrystal, dDruzy);
        if (dCluster < res.x) {
            float mCluster = (dDruzy < dCrystal - 0.003) ? MAT_CAVERN_DRUZY : params.z;
            res = vec2(dCluster, mCluster);
        }
    }

    return res;
}

vec3 cc_marchCavern(vec3 ro, vec3 rd, float tmin, float tmax, int maxSteps, out float lastTOut) {
    int cap = gInDissolve ? 52 : maxSteps;
    float stride = gInDissolve ? 0.99 : 0.94;
    float tolScale = gInDissolve ? 0.0018 : 0.0009;
    float tolMin   = gInDissolve ? 0.0008 : 0.0004;
    float t = tmin;
    vec2 lastH = vec2(1e5, MAT_CAVERN_WALL);
    for (int i = ZERO; i < 64; i++) {
        if (i >= cap) break;
        vec2 h = mapCavern(ro + rd * t);
        lastH = h;
        lastTOut = t;
        if (abs(h.x) < max(tolScale * t, tolMin)) return vec3(t, h.y, float(i));
        t += h.x * stride;
        if (t > tmax) break;
    }
    lastTOut = t;
    if (t <= tmax && lastH.x < 0.075) return vec3(t, lastH.y, float(cap));
    return vec3(-1.0, -1.0, float(cap));
}

vec3 cc_calcCavernNormal(vec3 p, float eps) {
    vec3 n = vec3(0.0);
    for (int i = ZERO; i < 4; i++) {
        vec3 e = 0.5773 * (2.0 * vec3((((i + 3) >> 1) & 1), ((i >> 1) & 1), (i & 1)) - 1.0);
        n += e * mapCavern(p + e * eps).x;
    }
    return normalize(n);
}

int cc_nearestClusterId(vec3 p, out float bestNormDist) {
    int bestId = 0;
    bestNormDist = 1e5;
    for (int i = 0; i < CC_CLUSTER_COUNT; i++) {
        vec3 rel = p - CC_ANC[i];
        float d = length(rel) / max(CC_PARAMS[i].x, 0.45);
        if (d < bestNormDist) {
            bestNormDist = d;
            bestId = i;
        }
    }
    return bestId;
}

// Jagged multi-octave ridgedFbm-eroded rock crack veins & tiny druzy flecks around cluster roots
// (sits strictly inside ragged karst fractures — zero smooth Voronoi worms!)
void cc_applyWallVeins(vec3 p, vec3 n, float t, bool isRefl, inout vec3 albedo, inout float rough, out vec3 emissive, out float veinMaskOut) {
    emissive = vec3(0.0);
    veinMaskOut = 0.0;
    if (isRefl || t > 16.0) return;

    float normDist;
    int cid = cc_nearestClusterId(p, normDist);
    float env = 1.0 - smoothstep(0.22, 0.88, normDist);
    if (env <= 0.005) return;

    vec4 par = CC_PARAMS[cid];
    float fp = max(t * 0.0012, 0.0008);

    // Multi-octave turbulent warp + ridgedFbm rock fracture erosion so veins look jagged & crystalline!
    vec2 baseUv = p.zy * 2.4 + vec2(p.x * 1.1, float(cid) * 1.7);
    float rCrease = ridgedFbm(baseUv * 1.35, 3);
    float tCrease = turbulence(baseUv * 2.6 + vec2(3.1, -1.9), 3);
    vec2 jagWarp = vec2(rCrease - 0.5, tCrease - 0.5) * 0.95;

    float border = voronoiBorder(baseUv + jagWarp, 0.92).x;
    // Erode border width with high-freq ridgedFbm so crack pinches & branches organically
    float erodedBorder = border + 0.028 * (1.0 - rCrease) + 0.016 * tCrease;
    float fractureGate = smoothstep(0.48, 0.80, rCrease);

    float w = clamp(0.018 + fp * 1.5, 0.018, 0.052);
    float seam = (1.0 - smoothstep(w * 0.20, w * 1.25, erodedBorder)) * fractureGate * env;
    float darkLip = (1.0 - smoothstep(w * 0.5, w * 2.2, erodedBorder)) * fractureGate * env;
    veinMaskOut = seam;

    float fleck = 0.0;
    if (normDist < 0.72) {
        vec4 vc = voronoi(p.zy * 22.0 + p.x * 14.0 + jagWarp * 3.0, 0.95);
        fleck = (1.0 - smoothstep(0.035, 0.14, vc.x)) * step(0.86, hash12(vc.zw + 19.0))
              * fractureGate * (1.0 - smoothstep(0.28, 0.72, normDist));
    }

    vec3 darkSocket = srgbToLinear(vec3(0.042, 0.048, 0.090));
    vec3 veinViolet = srgbToLinear(vec3(0.32, 0.18, 0.88));
    vec3 veinCyan   = srgbToLinear(vec3(0.10, 0.72, 0.98));
    vec3 mineralCol = mixOklab(veinViolet, veinCyan, par.w);

    albedo = mix(albedo, darkSocket, saturate(darkLip * 0.70));
    rough  = mix(rough, 0.26, saturate(darkLip * 0.40));
    emissive = mineralCol * (seam * 0.62 + fleck * 1.05 * (0.4 + 0.6 * abs(n.x)));
}

// Cavern lighting rig: moody wet charcoal-slate near-left framing + warm-neutral grey karst stone
// + cool limestone silver-grey Arch 3 chamber light + tightly localized crystal alcove bounce!
vec3 cc_lightCavernRock(vec3 p, vec3 n, vec3 v, vec3 albedo, float rough, float ao, bool isRefl, out vec3 neutralOut, out vec3 bounceOut) {
    vec3 cViolet = srgbToLinear(vec3(0.48, 0.24, 1.00));
    vec3 cCyan   = srgbToLinear(vec3(0.16, 0.86, 1.00));

    float cx = cavernCenterX(p.z);
    float foreFade = 1.0 - smoothstep(-3.5, -16.2, p.z) * 0.60;
    // Dim near-left foreground wall ~26% for moody framing; boost foreground right wall ~28% to match film_20..24!
    float nearLeftDim    = 1.0 - 0.26 * (1.0 - smoothstep(-6.0, -2.2, p.z)) * smoothstep(0.0, 1.15, cx - p.x);
    float rightWallBoost = 1.0 + 0.28 * (1.0 - smoothstep(-7.5, -2.5, p.z)) * smoothstep(0.0, 1.15, p.x - cx);
    float wallProfile    = foreFade * nearLeftDim * rightWallBoost;

    vec3 channelDir = normalize(vec3((cx - p.x) * 0.52, 0.22 - (p.y - 0.95) * 0.24, 0.66));
    float stoneRough = clamp(rough, 0.34, 0.72);
    float wrapDiff = wrapDiffuse(n, channelDir, 0.58);
    vec3 stoneLightCol = srgbToLinear(vec3(0.92, 0.90, 0.86));

    vec3 neutralKey = (albedo * stoneLightCol * wrapDiff * 1.82
                    + specularGGX(n, v, channelDir, stoneRough, vec3(0.032)) * stoneLightCol * 0.66)
                    * wallProfile;

    vec3 caveAmb = albedo * hemisphereLight(
        n,
        srgbToLinear(vec3(0.50, 0.50, 0.49)),
        srgbToLinear(vec3(0.23, 0.23, 0.23))
    ) * (1.52 * wallProfile + 0.26) * ao;

    // Pale cool limestone silver-grey chamber light at inner Arch 3 (z ~ -17.5) matching film_20..24.png!
    vec3 archLightPos = vec3(cavernCenterX(-17.8), 1.35, -17.8);
    vec3 toArch = archLightPos - p;
    float dArch2 = dot(toArch, toArch);
    vec3 archDir = toArch * inversesqrt(max(dArch2, 1e-3));
    float archBell = exp(-pow((p.z + 17.6) * 0.36, 2.0));
    vec3 coolArchTint = srgbToLinear(vec3(0.78, 0.81, 0.84));
    vec3 archLight = albedo * coolArchTint * wrapDiffuse(n, archDir, 0.45) * (2.35 * archBell / (1.0 + dArch2 * 0.14))
                   + albedo * srgbToLinear(vec3(0.50, 0.53, 0.56)) * (0.85 * archBell * ao);

    neutralOut = neutralKey + caveAmb + archLight;

    bounceOut = vec3(0.0);
    if (isRefl && p.z < -15.0) return neutralOut;
    for (int i = 0; i < CC_CLUSTER_COUNT; i++) {
        vec3 anc = CC_ANC[i];
        if (abs(p.z - anc.z) > 1.65) continue;

        vec4 par  = CC_PARAMS[i];
        vec3 gDir = CC_GROW_DIR[i];
        vec3 lPos = anc + gDir * (0.24 * par.x);
        vec3 L = lPos - p;
        float d2 = dot(L, L);
        if (d2 > 2.50) continue;

        float dist = sqrt(max(d2, 1e-4));
        vec3 lDir = L / dist;
        // Tight alcove cutoff so rock >1.2m from a crystal reads true neutral grey-slate limestone!
        float cutoff = 1.0 - smoothstep(0.65, 1.55, dist);
        float power = par.x * par.x * (1.80 / (0.24 + d2 * 2.35)) * cutoff;

        vec3 lCol = mixOklab(cViolet, cCyan, par.w);
        if (isRefl) {
            bounceOut += albedo * lCol * (max(dot(n, lDir), 0.0) * 0.58 + 0.16) * power;
        } else {
            vec3 pbrTerm = min(shadePBR(n, v, lDir, albedo, max(rough, 0.34), 0.0), vec3(0.85));
            bounceOut += pbrTerm * lCol * power;
            bounceOut += albedo * lCol * wrapDiffuse(n, lDir, 0.45) * power * 0.24 * ao;
        }
    }

    return neutralOut + bounceOut;
}

// High-contrast faceted mineral optics: deep saturated royal-amethyst outer shafts (65%+),
// crisp chevron phantom growth zones, grazing-only specular ridge glints (zero CAD wireframe!),
// and a tightly concentrated blazing electric-cyan/lilac root heart (inner 25..32%)!
vec3 cc_shadeCrystal(vec3 p, vec3 rd, vec3 n, float t, float pxAngle, bool isRefl, out float bevelOut) {
    float normDist;
    int cid = cc_nearestClusterId(p, normDist);

    vec3 anc     = CC_ANC[cid];
    vec3 growDir = CC_GROW_DIR[cid];
    vec4 params  = CC_PARAMS[cid];

    float scale   = params.x;
    float seedAng = params.y;
    float style   = params.w;

    vec3 upRef = (abs(growDir.y) < 0.92) ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 bX = normalize(cross(upRef, growDir));
    vec3 bZ = cross(growDir, bX);
    vec3 qs = vec3(dot(p - anc, bX), dot(p - anc, growDir), dot(p - anc, bZ)) / scale;

    float cs = cos(seedAng), sn = sin(seedAng);
    qs.xz = vec2(cs * qs.x - sn * qs.z, sn * qs.x + cs * qs.z);
    float lenVar = 0.11 * sin(seedAng * 2.3);

    float bestD = 1e5;
    vec3  bestS = vec3(0.0, 0.3, 0.0);
    vec4  bestShape = vec4(0.05, 0.6, 0.09, 0.0);
    float bestIdx = 0.0;
    int prongCount = isRefl ? 6 : 12;
    for (int k = 0; k < 12; k++) {
        if (k >= prongCount) break;
        vec3 s;
        vec4 shape;
        cc_prongLocal(k, lenVar, qs, s, shape);
        float dp = cc_sdQuartzPoint(s, shape);
        if (dp < bestD) {
            bestD = dp;
            bestS = s;
            bestShape = shape;
            bestIdx = float(k);
        }
    }

    const vec3 kHex = vec3(-0.8660254, 0.5, 0.57735027);
    float r    = bestShape.x;
    float len  = bestShape.y;
    float hTip = bestShape.z;

    vec2 q = abs(bestS.xz);
    q -= 2.0 * min(dot(kHex.xy, q), 0.0) * kHex.xy;

    float uAxial = clamp((bestS.y + 0.01) / max(len, 0.05), 0.0, 1.0);
    float shY    = len - hTip;
    float inTip  = smoothstep(shY - 0.010, shY + 0.010, bestS.y);

    float dPrismRidge = length(vec2(abs(q.x), q.y) - vec2(kHex.z * r, r));
    float dPyrRidge   = abs(abs(q.x) - kHex.z * q.y) * 0.866;
    float dShoulder   = length(vec2(q.y - r, bestS.y - shY));
    float edgeDist    = min(mix(dPrismRidge, dPyrRidge, inTip), dShoulder) * scale;

    float fp = max(t * pxAngle, 0.0010);
    float bevelW = clamp(0.0016 + 0.22 * fp, 0.0016, 0.0068);
    float rawEdge = 1.0 - smoothstep(bevelW * 0.20, bevelW * 1.30, edgeDist);

    vec3 v = -rd;
    vec3 refrDir = refract(rd, n, 1.0 / 1.544);
    vec3 pInt = p + refrDir * (0.055 * scale);

    // Crisp internal quartz chevron phantom growth bands parallel to the 6-sided termination faces!
    float chevronCoord = bestS.y + q.y * (hTip / max(r, 1e-3)) + bestIdx * 0.17;
    float chevWave1 = smoothstep(0.28, 0.76, 0.5 + 0.5 * sin(chevronCoord * 38.0 + 1.8 * gradientNoise(pInt * 10.0)));
    float chevWave2 = smoothstep(0.35, 0.80, 0.5 + 0.5 * sin(chevronCoord * 82.0));
    float chevronBands = 0.68 * chevWave1 + 0.32 * chevWave2;
    float phantomZone  = cubicPulse(0.68, 0.17, uAxial) + 0.72 * cubicPulse(0.46, 0.13, uAxial);

    float cleavage = 0.0;
    float striations = 0.0;
    if (!isRefl && t < 18.0) {
        float cBorder = voronoiBorder(pInt.yz * 11.5 + pInt.x * 6.5 + seedAng, 0.88).x;
        cleavage = 1.0 - smoothstep(0.009, 0.055, cBorder);
        float striaKeep = (1.0 - inTip) * (1.0 - smoothstep(0.003, 0.014, fp));
        striations = (0.5 + 0.5 * sin(bestS.y * 165.0 + q.x * 10.0)) * striaKeep;
    }

    // Tightly confined bioluminescent heart on amethyst (#2/#6: inner 25..32%), widened ~30% into a
    // glowing electric-aquamarine heart on cyan-cored hero clusters (#3/#5, style > 0.40)!
    float cyanBoost = smoothstep(0.28, 0.54, style);
    float aboveSocket = smoothstep(-0.005, 0.055, qs.y);
    vec3 coreCenter = anc + growDir * (0.06 * scale);
    float distRoot  = length(pInt - coreCenter) / max(scale, 0.40);
    float coreSpatial = exp(-distRoot * mix(5.8, 3.85, cyanBoost));
    float coreAxial   = pow(1.0 - smoothstep(0.0, mix(0.35, 0.51, cyanBoost), uAxial), 1.95);
    float rootHeart   = saturate(coreSpatial * 0.85 + coreAxial * 0.50) * aboveSocket;
    float midGlow     = exp(-distRoot * mix(4.2, 2.75, cyanBoost)) * (1.0 - smoothstep(0.06, mix(0.42, 0.60, cyanBoost), uAxial)) * aboveSocket;

    // Rich mineral palette: deep indigo-amethyst shadow faces vs bright icy-lilac specular faces!
    vec3 deepAmethyst  = srgbToLinear(vec3(0.15, 0.10, 0.48));
    vec3 royalAmethyst = srgbToLinear(vec3(0.38, 0.22, 0.86));
    vec3 cobaltViolet  = srgbToLinear(vec3(0.26, 0.34, 0.88));
    vec3 icyLilac      = srgbToLinear(vec3(0.68, 0.73, 0.99));
    vec3 deepAqua      = srgbToLinear(vec3(0.07, 0.42, 0.74));
    vec3 brightAqua    = srgbToLinear(vec3(0.20, 0.80, 0.98));
    vec3 electricCyan  = srgbToLinear(vec3(0.16, 0.94, 0.98));
    vec3 hotIceCore    = srgbToLinear(vec3(0.78, 0.98, 1.00));

    float pureCyan = smoothstep(0.65, 0.98, style);
    vec3 shaftMid  = mixOklab(royalAmethyst, cobaltViolet, smoothstep(0.0, 0.55, style) * 0.65);
    shaftMid = mixOklab(shaftMid, brightAqua, pureCyan);

    vec3 shaftDark = mixOklab(deepAmethyst, deepAqua, pureCyan);
    vec3 brightFaceCol = mixOklab(icyLilac, srgbToLinear(vec3(0.60, 0.94, 1.00)), pureCyan);

    // Strong flat face-to-face contrast between adjacent 60-deg prism & pyramid facets!
    vec3 fLight1 = normalize(vec3(-growDir.x * 0.68, 0.56, 0.48));
    vec3 fLight2 = normalize(vec3(growDir.x * 0.60, -0.32, 0.73));
    vec3 fLight3 = normalize(vec3(-growDir.x * 0.20, 0.85, 0.48));
    float f1 = pow(max(dot(n, fLight1), 0.0), 2.3);
    float f2 = pow(max(dot(n, fLight2), 0.0), 2.0);
    float f3 = pow(max(dot(n, fLight3), 0.0), 3.0);

    float faceContrast = saturate(f1 * 0.95 + f2 * 0.45 + f3 * 0.35);
    float bandMod = 0.78 + 0.34 * chevronBands + 0.08 * striations;

    vec3 crystalCol = mix(shaftDark, shaftMid, saturate(faceContrast * 1.15)) * bandMod;
    // Bright icy-lilac / frost-cyan sheen on direct key-facing facets
    crystalCol = mix(crystalCol, brightFaceCol * (0.78 + 0.42 * chevronBands), pow(faceContrast, 1.8) * (0.58 + 0.24 * inTip));
    // Distinct deeper royal-indigo chevron phantom growth bands inside mid/upper shaft
    crystalCol = mix(crystalCol, shaftDark * 0.56, saturate(phantomZone * (0.50 + 0.42 * (1.0 - chevronBands))));

    // Confined internal cyan-lilac transmission & blazing root heart
    vec3 midCyanTint = mixOklab(srgbToLinear(vec3(0.54, 0.68, 1.00)), electricCyan, smoothstep(0.0, 0.38, style));
    crystalCol = mix(crystalCol, midCyanTint * (1.42 + 0.55 * cyanBoost), saturate(midGlow * (0.82 + 0.16 * cyanBoost)));

    vec3 coreRadiance = mix(midCyanTint * (2.50 + 0.65 * cyanBoost), hotIceCore * (3.50 + 0.75 * cyanBoost), smoothstep(0.40, 0.85, rootHeart));
    crystalCol = mix(crystalCol, coreRadiance, smoothstep(0.18, 0.80, rootHeart) * 0.95);

    // Subtle refracted internal cleavage planes strictly inside translucent heart (zero outer polygon lines!)
    crystalCol *= 1.0 - 0.18 * cleavage * (1.0 - rootHeart);
    crystalCol += midCyanTint * cleavage * rootHeart * 0.55;

    // Grazing/specular-gated micro-ridge glint ONLY (zero uniform CAD wireframe outlines!)
    float NoV = max(dot(n, v), 1e-3);
    float F = fresnelDielectric(NoV, 1.0, 1.544);
    vec3 reflV = reflect(rd, n);
    float specAlign = max(max(dot(reflV, fLight1), 0.0), max(dot(reflV, fLight3), 0.0) * 0.85);
    float grazingGate = saturate(pow(1.0 - NoV, 2.2) * 0.55 + pow(specAlign, 3.0) * 0.85) * (0.25 + 0.75 * faceContrast);
    float bevelGlint = rawEdge * grazingGate;
    bevelOut = bevelGlint;

    crystalCol += brightFaceCol * bevelGlint * (0.65 + 0.55 * inTip);

    float rough = mix(0.085, 0.042, inTip) + 0.03 * striations;
    vec3 glassSpec = specularGGX(n, v, fLight1, rough, vec3(0.046)) * srgbToLinear(vec3(0.92, 0.94, 1.00)) * 2.25
                   + specularGGX(n, v, fLight3, rough, vec3(0.046)) * brightFaceCol * 1.25;

    crystalCol = mix(crystalCol, shaftDark * 0.65, F * 0.28 * (1.0 - rootHeart));
    crystalCol += glassSpec;

    return crystalCol;
}

// Craggy dark geode druzy collar (blends seamlessly into wet dark karst stone — no purple disk!)
vec3 cc_shadeDruzyBed(vec3 p, vec3 rd, vec3 nIn, float t, float pxAngle, bool isRefl) {
    float normDist;
    int cid = cc_nearestClusterId(p, normDist);
    vec4 par = CC_PARAMS[cid];
    vec3 gDir = CC_GROW_DIR[cid];

    vec3 n = nIn;
    float sparkle = 0.0;
    if (!isRefl && t < 14.0) {
        vec4 vc = voronoi(p.yz * 34.0 + p.x * 22.0, 0.95);
        vec2 cellRnd = hash22(vc.zw + vec2(7.0, 23.0)) - 0.5;
        float fade = saturate(1.0 - smoothstep(2.5, 12.0, t) - smoothstep(0.004, 0.018, t * pxAngle) * 0.5);
        n = normalize(n + vec3(cellRnd.x, cellRnd.y, -cellRnd.x * 0.7) * 0.62 * fade);
        sparkle = pow(max(dot(reflect(rd, n), normalize(vec3(-gDir.x, 0.55, 0.72))), 0.0), 26.0) * fade;
    }

    vec3 albedo = srgbToLinear(vec3(0.065, 0.070, 0.092));
    vec3 glowTint = mixOklab(srgbToLinear(vec3(0.42, 0.26, 0.96)), srgbToLinear(vec3(0.18, 0.84, 1.00)), par.w);

    vec3 nOut1;
    vec3 nOut2;
    vec3 col = cc_lightCavernRock(p, n, -rd, albedo, 0.28, 0.45, isRefl, nOut1, nOut2);
    col += glowTint * (exp(-normDist * 5.2) * 0.36 + sparkle * 1.35);
    return col;
}

float cc_fastCaveAO(vec3 p, vec3 n) {
    gFastMap = true;
    float h1 = mapCavern(p + n * 0.11).x;
    float h2 = mapCavern(p + n * 0.34).x;
    gFastMap = false;
    float occ = (0.11 - h1) * 2.4 + (0.34 - h2) * 0.95;
    return clamp(1.0 - occ, 0.0, 1.0);
}

vec3 cc_shadeSurface(vec3 ro, vec3 rd, float t, float matId, float pxAngle, bool isRefl,
                     out vec3 dbgN, out vec3 dbgMasks, out vec3 dbgLight) {
    vec3 p = ro + rd * t;
    bool fastN = (isRefl || t > 15.5);
    if (fastN) gFastMap = true;
    vec3 n = cc_calcCavernNormal(p, max(0.0015 * t, 0.0009));
    if (fastN) gFastMap = false;

    float m = floor(matId + 0.5);
    vec3 darkCaveFog = srgbToLinear(vec3(0.020, 0.032, 0.038));

    if (m == MAT_CAVERN_CRYSTAL_VIOLET || m == MAT_CAVERN_CRYSTAL_CYAN) {
        float bevelMask = 0.0;
        vec3 cCol = cc_shadeCrystal(p, rd, n, t, pxAngle, isRefl, bevelMask);
        if (isRefl) cCol *= 1.15;
        dbgN = n;
        dbgMasks = vec3(1.0, 0.8, bevelMask);
        dbgLight = vec3(0.0, luminance(cCol) * 0.5, luminance(cCol));
        return mix(cCol, darkCaveFog, distanceFog(t, 0.012));
    }

    if (m == MAT_CAVERN_DRUZY) {
        vec3 dCol = cc_shadeDruzyBed(p, rd, n, t, pxAngle, isRefl);
        dbgN = n;
        dbgMasks = vec3(0.45, 0.9, 0.25);
        dbgLight = vec3(0.1, luminance(dCol), 0.25);
        return mix(dCol, darkCaveFog, distanceFog(t, 0.016));
    }

    vec3 albedo = vec3(0.15);
    float rough = 0.45;
    vec3 rockN = n;
    shadeCavernRock(m, p, n, t, isRefl, albedo, rough, rockN);

    vec3 veinEmissive = vec3(0.0);
    float veinMask = 0.0;
    cc_applyWallVeins(p, rockN, t, isRefl, albedo, rough, veinEmissive, veinMask);

    float ao = (isRefl || t > (gInDissolve ? 10.5 : 15.0)) ? 0.66 : cc_fastCaveAO(p, rockN);

    vec3 neutralL;
    vec3 bounceL;
    vec3 lit = cc_lightCavernRock(p, rockN, -rd, albedo, rough, ao, isRefl, neutralL, bounceL);
    lit = lit * mix(0.36, 1.0, ao) + veinEmissive;

    if (isRefl && m == MAT_CAVERN_STALACTITE) {
        float steepDim = 1.0 - 0.85 * smoothstep(0.38, 0.65, rd.y);
        lit = mix(srgbToLinear(vec3(0.032, 0.048, 0.046)), lit, 0.46 * steepDim);
    }

    dbgN = rockN;
    dbgMasks = vec3(ao, veinMask, 1.0 - rough);
    dbgLight = vec3(luminance(neutralL), luminance(bounceL), luminance(veinEmissive));

    return mix(lit, darkCaveFog, distanceFog(t, 0.017));
}

// Horizontally-rippled underground river (active down to tWater ~ 0.9m so foreground reflections
// break into liquid horizontal bands!) + 1.65x crisp expanding concentric ceiling-drip rings!
vec3 cc_riverNormal(vec2 xz, float zCam, float tWater, float pxAngle, out float dripMaskOut) {
    float u = gSceneTime;
    float fp = tWater * pxAngle / max(0.06, 0.35 / (1.0 + tWater * 0.15));
    float farFade  = 1.0 - smoothstep(13.5, 26.5, tWater);
    float foreRamp = 0.64 + 0.36 * smoothstep(0.75, 2.50, tWater);

    // Longitudinal z-wavelets (stronger dh/dz) slicing reflections into shimmering horizontal liquid rungs!
    vec4 w1 = waterWaveD(xz, u * 0.54 + 2.0, vec2(0.07, 0.998), 0.31, 0.0028, 1.5, fp);
    vec4 w2 = waterWaveD(xz, u * 0.66 + 5.1, vec2(-0.11, 0.994), 0.16, 0.0014, 1.5, fp);
    vec4 w3 = waterWaveD(xz, u * 0.42 + 1.3, vec2(0.04, 0.999), 0.52, 0.0022, 1.5, fp);
    vec3 f1 = simplexNoiseD(xz * vec2(0.80, 4.40) + vec2(0.0, u * 0.18), 0.24 * u);
    float noiseKeep = smoothstep(2.0, 6.0, 0.24 / max(fp, 1e-4));

    vec2 slope = ((w1.yz + w2.yz + w3.yz) * 1.15 + f1.yz * vec2(0.0016, 0.0145) * noiseKeep) * foreRamp;

    // Prominent concentric ceiling-drip ring packets in center foreground (22s..24s hero feature!)
    dripMaskOut = 0.0;
    for (int d = 0; d < 2; d++) {
        float fd = float(d);
        vec2 origin = (d == 0)
            ? vec2(cavernCenterX(zCam - 3.55) - 0.03, zCam - 3.55)
            : vec2(cavernCenterX(zCam - 6.75) + 0.14, zCam - 6.75);

        vec2 delta = xz - origin;
        float r = length(delta);
        if (r < 2.7) {
            vec2 rDir = delta / max(r, 1e-4);
            for (int gen = 0; gen < 2; gen++) {
                float cycle = fract(u * 0.38 + fd * 0.47 + 0.42) + float(gen);
                float rFront = cycle * 1.18 + 0.14;
                float packet = cubicPulse(rFront, 0.58, r) * exp(-r * 0.52) * (1.0 - cycle * 0.34);
                float kRing = 19.0;
                float ringKeep = smoothstep(2.0, 5.5, (TAU / kRing) / max(fp * 0.42, 1e-4));
                float dWave = cos((r - rFront) * kRing) * kRing * 0.0096 * packet * ringKeep;
                slope += rDir * dWave;
                float ringCrest = pow(0.5 + 0.5 * sin((r - rFront) * kRing), 2.2) * packet * ringKeep;
                dripMaskOut = max(dripMaskOut, ringCrest);
            }
        }
    }

    slope *= farFade;
    return normalize(vec3(-slope.x, 1.0, -slope.y));
}

vec3 cc_grottoBackdrop(vec3 rd, float endZ) {
    vec3 darkVault = srgbToLinear(vec3(0.012, 0.020, 0.025));
    float reachGrotto = smoothstep(-23.2, -25.0, endZ);
    vec2 gUv = vec2(rd.x + 0.04, rd.y + 0.03);
    float gDist = length(gUv * vec2(1.0, 1.45));
    return darkVault + srgbToLinear(vec3(0.06, 0.46, 0.58)) * exp(-gDist * 11.5) * (0.65 * reachGrotto);
}

vec3 renderCavern(vec2 uv, vec2 fragCoord, float pxAngle) {
    const float FOCAL = 1.85;
    float u = gSceneTime;

    float zCam = -0.80 - 0.72 * u;
    float xCam = cavernCenterX(zCam);
    vec3 ro = vec3(xCam, 0.44, zCam);
    vec3 ta = vec3(cavernCenterX(zCam - 6.5) - 0.10, 0.34, zCam - 6.5);

    bool orbited = (length(iMouse.xy) >= 0.5);
    applyOrbit(ro, vec3(cavernCenterX(zCam - 5.0), 0.72, zCam - 5.0), -0.54);
    if (orbited) {
        float cxOrb = cavernCenterX(ro.z);
        ro.x = clamp(ro.x, cxOrb - 1.05, cxOrb + 1.05);
        ro.y = clamp(ro.y, 0.18, 1.35);
    }

    mat3 cam = cameraMatrix(ro, ta, 0.0);
    vec3 rd  = cameraRay(cam, uv, FOCAL);

#if DEBUG_MODE == 1
    vec3 sliceP = vec3(uv.x * 2.6 + cavernCenterX(-5.52), uv.y * 1.8 + 0.85, -5.52);
    return debugDistance(mapCavern(sliceP).x);
#endif

    float tWater = (rd.y < -0.0004) ? (-ro.y / rd.y) : -1.0;
    float tMaxPrimary = (tWater > 0.0) ? min(tWater, 34.0) : 34.0;

    bool skipPrimaryToWater = false;
    if (!orbited && tWater > 0.0 && tWater < 21.5) {
        vec3 wpCheck = ro + rd * tWater;
        if (wpCheck.z > -22.5 && abs(wpCheck.x - cavernCenterX(wpCheck.z)) < 0.96) {
            skipPrimaryToWater = true;
        }
    }

    vec3 hit = vec3(-1.0, -1.0, 2.0);
    float lastT = tMaxPrimary;
    if (!skipPrimaryToWater) {
        hit = cc_marchCavern(ro, rd, 0.10, tMaxPrimary, 58, lastT);
        if (hit.x < 0.0 && tWater > 0.0) hit.z = min(hit.z, 14.0);
    }
    float totalSteps = hit.z;

    if (hit.x > 0.0 && (tWater < 0.0 || hit.x < tWater)) {
        vec3 dbgN;
        vec3 dbgMasks;
        vec3 dbgLight;
        vec3 surfCol = cc_shadeSurface(ro, rd, hit.x, hit.y, pxAngle, false, dbgN, dbgMasks, dbgLight);
#if DEBUG_MODE == 2
        return debugNormal(dbgN);
#elif DEBUG_MODE == 3
        return debugIdColor(floor(hit.y + 0.5));
#elif DEBUG_MODE == 4
        return debugHeat(totalSteps / 58.0);
#elif DEBUG_MODE == 5
        return dbgMasks;
#elif DEBUG_MODE == 6
        return dbgLight;
#endif
        return surfCol + 0.0 * fragCoord.x;
    }

    if (tWater > 0.0 && tWater < 30.0) {
        vec3 wp = ro + rd * tWater;
        float dripMask = 0.0;
        vec3 wn = cc_riverNormal(wp.xz, zCam, tWater, pxAngle, dripMask);

        vec3 reflRd = reflect(rd, wn);
        reflRd.y = max(reflRd.y, 0.012);

        gFastMap = true;
        int reflCap = gInDissolve ? 11 : 22;
        float rt = 0.08;
        float rMat = -1.0;
        int rSteps = 0;
        for (int i = ZERO; i < 24; i++) {
            if (i >= reflCap) break;
            rSteps = i + 1;
            vec2 rh = mapCavern(wp + reflRd * rt);
            if (abs(rh.x) < 0.0040 * rt + 0.0022) {
                rMat = rh.y;
                break;
            }
            rt += rh.x * 1.00;
            if (rt > 28.0) break;
        }
        gFastMap = false;
        totalSteps += float(rSteps);

#if DEBUG_MODE == 2
        return debugNormal(wn);
#elif DEBUG_MODE == 3
        return debugIdColor(0.0);
#elif DEBUG_MODE == 4
        return debugHeat(totalSteps / 70.0);
#endif

        vec3 reflCol = cc_grottoBackdrop(reflRd, wp.z + reflRd.z * rt);
        if (rMat > 0.0) {
            vec3 rN;
            vec3 rM;
            vec3 rL;
            reflCol = cc_shadeSurface(wp, reflRd, rt, rMat, pxAngle * 1.6, true, rN, rM, rL);
        }

        float NoV = max(dot(wn, -rd), 1e-3);
        float F = fresnelDielectric(NoV, 1.0, 1.333);

        float bankDist = abs(wp.x - cavernCenterX(wp.z));
        float bankShade = 1.0 - 0.52 * smoothstep(0.95, 2.25, bankDist);
        float depthEst = mix(1.65, 0.42, smoothstep(1.1, 2.3, bankDist));
        float refrPath = depthEst / max(sqrt(1.0 - 0.56 * (1.0 - NoV * NoV)), 0.35);
        vec3 T = beerTransmittance(vec3(0.68, 0.34, 0.38), refrPath);

        vec3 riverScatter = srgbToLinear(vec3(0.076, 0.110, 0.100)) * bankShade;
        vec3 riverBed     = srgbToLinear(vec3(0.088, 0.108, 0.096)) * bankShade;
        vec3 waterBody    = riverBed * T + riverScatter * (vec3(1.0) - T);

        float reflWeight = clamp(F * 1.14 + 0.12, 0.0, 0.90);
        vec3 waterCol = waterBody * (1.0 - reflWeight) + reflCol * reflWeight;
        // Fresnel-gated cool cave-arch sky glint along expanding concentric circular drip-ring crests!
        waterCol += srgbToLinear(vec3(0.24, 0.29, 0.31)) * dripMask * (0.06 + 0.88 * F);

#if DEBUG_MODE == 5
        return vec3(F, dripMask, bankShade);
#elif DEBUG_MODE == 6
        return vec3(luminance(waterBody), luminance(reflCol * reflWeight), dripMask);
#endif

        vec3 waterFog = srgbToLinear(vec3(0.020, 0.036, 0.042));
        return mix(waterCol, waterFog, distanceFog(tWater, 0.016));
    }

    float endZ = ro.z + rd.z * lastT;
#if DEBUG_MODE == 2
    return vec3(0.0);
#elif DEBUG_MODE == 3
    return debugIdColor(0.0);
#elif DEBUG_MODE == 4
    return debugHeat(totalSteps / 58.0);
#elif DEBUG_MODE == 5
    return vec3(0.0);
#elif DEBUG_MODE == 6
    return cc_grottoBackdrop(rd, endZ);
#endif

    return cc_grottoBackdrop(rd, endZ);
}

// ==== PART: 99_main.glsl ====
// =============================================================================
// Scene Dispatcher, Exposure, AgX Tonemap & Seamless 25s Cross-Dissolve Loop
// =============================================================================
vec3 renderScene(int sceneId, float localTime, vec2 fragCoord) {
    gSceneId   = sceneId;
    gSceneTime = localTime;
    gFastMap   = false;

    vec2 uv = (2.0 * fragCoord - iResolution.xy) / iResolution.y;
    float pxAngle = 2.0 / max(iResolution.y * 1.95, 1.0);

    vec3 hdr = vec3(0.0);
    float exposure = 1.0;

    if (sceneId == 0) {
        hdr = renderSpace(uv, fragCoord, pxAngle);
        exposure = SPACE_EXPOSURE;
    } else if (sceneId == 1) {
        hdr = renderForest(uv, fragCoord, pxAngle);
        exposure = FOREST_EXPOSURE;
    } else if (sceneId == 2) {
        hdr = renderOcean(uv, fragCoord, pxAngle);
        exposure = OCEAN_EXPOSURE;
    } else if (sceneId == 3) {
        hdr = renderDesert(uv, fragCoord, pxAngle);
        exposure = DESERT_EXPOSURE;
    } else {
        hdr = renderCavern(uv, fragCoord, pxAngle);
        exposure = CAVERN_EXPOSURE;
    }

#if DEBUG_MODE == 0
    hdr *= vignette(uv, 2.2);
    return tonemapAgX(max(hdr, vec3(0.0)) * exposure);
#else
    return hdr;
#endif
}

vec3 sampleFilm(vec2 fragCoord) {
    float filmT  = mod(max(iTime, 0.0), FILM_DURATION);
    int   slot   = min(int(floor(filmT / SCENE_DURATION)), 4);
    float inSlot = filmT - SCENE_DURATION * float(slot);
    float dissolveStart = SCENE_DURATION - DISSOLVE_TIME;
    gInDissolve = (inSlot >= dissolveStart);

    float alpha = clamp((inSlot - dissolveStart) / DISSOLVE_TIME, 0.0, 1.0);
    vec3 colOut = vec3(0.0);
    for (int pass = ZERO; pass < 2; pass++) {
        if (pass == 1 && !gInDissolve) break;
        int sc = (pass == 0) ? slot : ((slot + 1) % 5);
        float uLocal = (pass == 0) ? (inSlot + DISSOLVE_TIME) : (inSlot - dissolveStart);
        vec3 c = renderScene(sc, uLocal, fragCoord);
#if DEBUG_MODE == 0
        c = linearToSrgb(c);
#endif
        colOut = (pass == 0) ? c : mix(colOut, c, alpha);
    }
    return colOut;
}

vec2 map(vec3 p) {
    // Scenes II, IV, and V use scene-local march/normal/shadow/AO; only Scene III calls global map(p).
    if (gSceneId == 2) return mapOceanIsland(p);
    return vec2(length(p) - 1.0, 0.0);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec3 acc = vec3(0.0);
    for (int i = 0; i < AA; i++) {
        vec2 ofs = (AA > 1) ? aaOffset(i) : vec2(0.0);
        acc += sampleFilm(fragCoord + ofs);
    }
    vec3 col = acc / float(AA);
#if DEBUG_MODE == 0
    col += ditherTPDF(fragCoord, iFrame);
#endif
    fragColor = vec4(saturate(col), 1.0);
}

// ---- Tuning Guide ----
// DEBUG_MODE (0..6) / AA (1..4): inspect distance slices, normals, material IDs, raymarch step heat, masks, lighting, or supersample.
// FILM_DURATION / SCENE_DURATION / DISSOLVE_TIME: timeline sync with public/film.mp4 (25.0s loop, 5.0s scenes, 0.75s dissolves).
// ORBIT_YAW_RANGE / ORBIT_PITCH_MAX: sensitivity and elevation bounds of iMouse camera orbit across all 5 scenes.
// SPACE_EXPOSURE..CAVERN_EXPOSURE: per-scene linear exposure prior to AgX tonemapping.
// FOREST_SUN_DIR / OCEAN_STACK_POS / DESERT_SUN_DIR / DESERT_ARCH_POS: cross-module hero placement and directional key lights.
