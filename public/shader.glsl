// Gemini Video 2 GLSL — Five-scene procedural Shadertoy recreation of a 25-second Gemini Omni 1.2 Flash film.
// Built with shader-art-coding from gokayfem/shader-skills (MIT): https://github.com/gokayfem/shader-skills
// Scenes (5s each, 0.75s cross-dissolves including seamless 25s -> 0s loop):
//   I.   Space  (00s-05s) - Ringed banded gas giant, storm vortex, ring shadow, violet nebula, starfield & sun
//   II.  Forest (05s-10s) - Ancient redwood corridor, sword ferns, mossy floor, diagonal morning sunbeams
//   III. Ocean  (10s-15s) - Stormy deep-teal swells, whitecaps, dark basalt sea stack, stone lighthouse & beam
//   IV.  Desert (15s-20s) - Rippled golden-hour orange dunes, freestanding sandstone arch, layered hazy mesas
//   V.   Cavern (20s-25s) - Underground limestone river, hanging stalactites, glowing cyan/violet crystals

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
// 0 at x = 0 and x = 1, peak 1 at x = 0.5; k sharpens.
float parabola(float x, float k) {
    return pow(4.0 * x * (1.0 - x), k);
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
// Box-filtered grid lines (unit cells, line width = 1/n of a cell). Returns 1 on lines, 0 inside cells.
float filteredGrid(vec2 p, vec2 w, float n) {
    w = max(w, 1e-4);
    vec2 a = p + 0.5 * w;
    vec2 b = p - 0.5 * w;
    vec2 i = (floor(a) + min(fract(a) * n, 1.0) - floor(b) - min(fract(b) * n, 1.0)) / (n * w);
    return 1.0 - (1.0 - i.x) * (1.0 - i.y);
}

// ---- shader-skills library: sdf3d ----
// Box with rounded edges. The outer size stays b; r is the edge radius (r <= min(b)).
float sdRoundBox(vec3 p, vec3 b, float r) {
    vec3 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0) - r;
}
// Partial torus (arc) in the XY plane, symmetric about +Y. sc = vec2(sin, cos) of the half-aperture angle, ra = major radius, rb = tube radius.
float sdCappedTorus(vec3 p, vec2 sc, float ra, float rb) {
    p.x = abs(p.x);
    float k = (sc.y * p.x > sc.x * p.y) ? dot(p.xy, sc) : length(p.xy);
    return sqrt(max(dot(p, p) + ra * ra - 2.0 * ra * k, 0.0)) - rb;
}
// Capsule: segment a-b swept by radius r.
float sdCapsule(vec3 p, vec3 a, vec3 b, float r) {
    vec3 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
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
// Round cone: sphere r1 at y = 0 smoothly hulled with sphere r2 at y = h.
float sdRoundCone(vec3 p, float r1, float r2, float h) {
    float b = (r1 - r2) / h;
    float a = sqrt(1.0 - b * b);
    vec2 q = vec2(length(p.xz), p.y);
    float k = dot(q, vec2(-b, a));
    if (k < 0.0) return length(q) - r1;
    if (k > a * h) return length(q - vec2(0.0, h)) - r2;
    return dot(q, vec2(a, b)) - r1;
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

// ---- shader-skills library: operators ----
// Smooth union (polynomial, C1). Blends where |a - b| < k, with a max bulge of k/4.
float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}
// Smooth intersection, the mirror of smin.
float smax(float a, float b, float k) { return -smin(-a, -b, k); }
// Union with n stair steps of total size r at the seam.
float opStairsUnion(float a, float b, float r, float n) {
    float s = r / n;
    float u = b - r;
    return min(min(a, b), 0.5 * (u + a + abs(mod(u - a + s, 2.0 * s) - s)));
}
// Hollow shell of thickness 2t around the surface. Apply repeatedly for concentric layers.
float opOnion(float d, float t) { return abs(d) - t; }

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

// ---- shader-skills library: water ----
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

// Material IDs shared across raymarched scenes
const float MAT_TERRAIN     = 1.0;
const float MAT_TRUNK       = 2.0;
const float MAT_FERN        = 3.0;
const float MAT_LOG         = 4.0;
const float MAT_ROCK        = 5.0;
const float MAT_TOWER       = 6.0;
const float MAT_LANTERN     = 7.0;
const float MAT_DOME        = 8.0;
const float MAT_SAND        = 9.0;
const float MAT_SANDSTONE   = 10.0;
const float MAT_CAVE_WALL   = 11.0;
const float MAT_STALACTITE  = 12.0;
const float MAT_CRYSTAL_A   = 13.0;
const float MAT_CRYSTAL_B   = 14.0;

// Mutable scene dispatch state for map()/calcNormal()/calcAO()
int   gSceneId    = 0;
float gSceneTime  = 0.0;
bool  gFastMap    = false;
bool  gInDissolve = false;

vec2 map(vec3 p);

// Bounded sphere tracer with configurable maxSteps for real-time 60fps budget
vec3 marchBounded(vec3 ro, vec3 rd, float tmin, float tmax, float stepScale, int maxSteps) {
    int cap = gInDissolve ? (maxSteps * 2) / 3 : maxSteps;
    float t = tmin;
    for (int i = ZERO; i < 128; i++) {
        if (i >= cap) break;
        vec2 h = map(ro + rd * t);
        if (abs(h.x) < max(0.0009 * t, 0.0004)) return vec3(t, h.y, float(i));
        t += h.x * stepScale;
        if (t > tmax) break;
    }
    return vec3(-1.0, -1.0, float(cap));
}

// Fast 18-step soft shadow using coarse LOD map evaluation
float fastShadow(vec3 ro, vec3 rd, float tmin, float tmax, float k) {
    gFastMap = true;
    float res = 1.0;
    float t = tmin;
    for (int i = ZERO; i < 18; i++) {
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

// -----------------------------------------------------------------------------
// Camera & Mouse Orbit
// -----------------------------------------------------------------------------
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

// =============================================================================
// SCENE I: SPACE (Analytic Sphere + Tilted Ring Plane + Nebula + Starfield)
// =============================================================================
vec3 spaceStarsAndNebula(vec3 rd, vec3 sunSkyDir, vec3 camRight, vec3 camUp, float pxAngle) {
    vec2 skyUv = vec2(atan(rd.x, -rd.z), asin(clamp(rd.y, -1.0, 1.0)));
    vec3 col = vec3(0.0009, 0.0008, 0.0015);

    for (int layer = 0; layer < 3; layer++) {
        float fl = float(layer);
        float scale = 95.0 * pow(2.1, fl);
        vec2 st = skyUv * scale + vec2(fl * 37.3, fl * 23.1);
        vec2 cell = floor(st);
        vec2 f = st - cell - 0.5;
        vec3 h = hash32(cell + vec2(107.0 * fl, 59.0));
        float thresh = mix(0.94, 0.91, fl * 0.5);
        if (h.x > thresh) {
            vec2 jitter = (hash22(cell + vec2(17.0, 73.0 + fl * 11.0)) - 0.5) * 0.65;
            float d = length(f - jitter) / scale;
            float sigma = max(pxAngle * mix(0.76, 0.52, fl * 0.5), 0.00036);
            float core = exp(-(d * d) / (sigma * sigma));
            float mag = pow((h.x - thresh) / (1.0 - thresh), 2.2);
            vec3 starTint = mix(vec3(0.90, 0.92, 1.0), blackbody(mix(3800.0, 11000.0, h.y)), 0.55);
            float twinkle = 0.92 + 0.08 * sin(h.z * TAU + gSceneTime * 1.5);
            col += starTint * core * (0.16 + 1.75 * mag) * mix(1.15, 0.42, fl * 0.5) * twinkle;
        }
    }

    // Gossamer violet/magenta filamentous nebula in the gap between planet and sun
    vec2 nebCenter = vec2(0.04, 0.05);
    vec2 np = (skyUv - nebCenter) * vec2(2.6, 2.2);
    float env = exp(-dot(np, np) * 1.55);
    if (env > 0.002) {
        vec2 wq, wr;
        float wf = warpedFbm(skyUv * 3.8 + vec2(1.7, -0.9), 0.9, 4, wq, wr);
        float web1 = ridgedFbm(skyUv * 6.4 + wr * 1.35 + vec2(3.4, 0.8), 5);
        float web2 = ridgedFbm(skyUv * 12.0 - wq * 1.05 + vec2(-1.8, 2.9), 4);
        float threads = pow(saturate(web1), 5.8) * (0.45 + 1.15 * pow(saturate(web2), 3.5));
        float softVeil = saturate(0.45 + 0.55 * wf) * env;

        vec3 deepViolet  = srgbToLinear(vec3(0.25, 0.13, 0.41));
        vec3 brightLilac = srgbToLinear(vec3(0.86, 0.56, 0.98));
        vec3 warmKnot    = srgbToLinear(vec3(0.55, 0.34, 0.25));

        col += deepViolet * softVeil * 0.15;
        col += mix(deepViolet, brightLilac, saturate(web2)) * threads * env * 1.35;
        col += warmKnot * saturate(wr.x * 0.8) * env * 0.06;
    }

    // Bright golden-white sun + subtle starburst + screen-horizontal anamorphic flare
    float cosSun = clamp(dot(rd, sunSkyDir), -1.0, 1.0);
    float ang = acos(cosSun);
    vec3 sunTint = mix(vec3(1.0, 0.96, 0.90), blackbody(5400.0), 0.65);

    float solarCore  = exp(-(ang * ang) / (0.0125 * 0.0125)) * 28.0;
    float innerBloom = 0.0022 / (ang * ang + 0.00035);
    float outerGlow  = 0.0095 / (ang + 0.045) * (1.0 - smoothstep(0.05, 0.50, ang));

    vec2 sunDelta = vec2(dot(rd, camRight) - dot(sunSkyDir, camRight), dot(rd, camUp) - dot(sunSkyDir, camUp));
    float rayAng  = atan(sunDelta.y, sunDelta.x + 1e-6);
    float fineRays = pow(0.5 + 0.5 * cos(rayAng * 22.0 + 0.3), 7.0)
                   + 0.7 * pow(0.5 + 0.5 * cos(rayAng * 13.0 - 1.1), 9.0);
    float rayEnv = exp(-ang * 12.0) * smoothstep(0.008, 0.028, ang);
    float horizStreak = exp(-abs(sunDelta.y) * 260.0) * exp(-abs(sunDelta.x) * 8.0) * 0.95;

    col += sunTint * (solarCore + innerBloom * 0.56 + outerGlow * 0.40 + fineRays * rayEnv * 0.16)
         + vec3(1.0, 0.90, 0.76) * horizStreak;
    return max(col, vec3(0.0));
}

vec3 shadeGasGiant(vec3 hitPos, vec3 planetCenter, vec3 rd, vec3 lightDir, vec3 ringNormal) {
    vec3 n = normalize(hitPos - planetCenter);
    vec3 upAxis = ringNormal;
    vec3 eqX = normalize(cross(upAxis, vec3(0.0, 0.0, 1.0)));
    vec3 eqZ = cross(eqX, upAxis);
    vec3 local = vec3(dot(n, eqX), dot(n, upAxis), dot(n, eqZ));

    float spin = 0.036 * gSceneTime + 0.42;
    local.xz = rot2(spin) * local.xz;
    float lat = asin(clamp(local.y, -1.0, 1.0));

    // Seam-free 3D cloud-belt coordinates with rich curly festoons & turbulent eddies!
    vec3 cylP = vec3(local.x * 2.6, lat * 6.8, local.z * 2.6);
    float warpA = fbm(cylP * vec3(1.6, 2.5, 1.6) + vec3(0.03 * gSceneTime, 0.0, 0.0), 4, 2.05, 0.52);
    float warpB = fbm(cylP * vec3(4.2, 7.2, 4.2) + vec3(warpA * 0.85, -warpA * 0.65, 0.04 * gSceneTime), 5, 2.05, 0.54);
    float festoons = ridgedFbm(vec2(lat * 24.0 + warpB * 2.2, (local.x * 1.3 - local.z * 1.1) * 6.5 + warpA * 2.4), 5);
    float microSwirl = turbulence(vec2(lat * 34.0 + warpB * 1.8, (local.x + local.z) * 9.5 - warpA * 2.0), 4);

    float wLat = lat + 0.055 * warpA + 0.034 * warpB + 0.018 * (festoons - 0.5);

    vec3 cCream = srgbToLinear(vec3(0.84, 0.78, 0.69));
    vec3 cSand  = srgbToLinear(vec3(0.65, 0.49, 0.33));
    vec3 cRust  = srgbToLinear(vec3(0.49, 0.23, 0.10));
    vec3 cSlate = srgbToLinear(vec3(0.44, 0.48, 0.52));
    vec3 cPolar = srgbToLinear(vec3(0.38, 0.33, 0.26));

    float zones = 0.5 + 0.5 * sin(wLat * 18.0 + 0.35 + microSwirl * 1.15);
    float eqBeltN = cubicPulse(0.07, 0.20, wLat);
    float eqBeltS = cubicPulse(-0.27, 0.16, wLat);
    float thinBelt = cubicPulse(0.31, 0.075, wLat) + cubicPulse(-0.49, 0.08, wLat);
    float slateZone = cubicPulse(-0.11, 0.085, wLat) + 0.75 * cubicPulse(0.21, 0.06, wLat);

    vec3 albedo = mixOklab(cCream, cSand, smoothstep(0.18, 0.82, zones));
    float rustMask = saturate((eqBeltN + eqBeltS + 0.65 * thinBelt) * (0.28 + 0.85 * pow(festoons, 1.5) + 0.35 * microSwirl));
    albedo = mixOklab(albedo, cRust, rustMask);
    albedo = mixOklab(albedo, cSlate, saturate(slateZone * (0.55 + 0.55 * microSwirl)));
    albedo = mixOklab(albedo, cPolar, smoothstep(0.58, 1.15, abs(lat)));

    // Great Southern Oval Storm + companion white eddies (matching film_2.00.png!)
    vec3 stormDir = normalize(vec3(0.22, -0.44, 0.87));
    vec3 localUnspun = vec3(dot(n, eqX), dot(n, upAxis), dot(n, eqZ));
    localUnspun.xz = rot2(0.015 * (gSceneTime - 2.5)) * localUnspun.xz;
    vec3 dStorm3 = localUnspun - stormDir;
    vec3 stormTanX = normalize(cross(upAxis, stormDir));
    vec3 stormTanY = cross(stormDir, stormTanX);
    vec2 sd = vec2(dot(dStorm3, stormTanX) * 0.82, dot(dStorm3, stormTanY) * 1.55);
    float sr = length(sd);
    if (sr < 0.26) {
        float swirlAng = (1.0 - smoothstep(0.0, 0.26, sr)) * 4.5;
        vec2 sw = rot2(swirlAng) * sd;
        float eye = 0.5 + 0.5 * sin(sr * 58.0 + fbm(sw * 24.0, 3) * 2.4);
        vec3 vortexCol = mixOklab(cRust * 1.25, cCream, eye * 0.58);
        float mStorm = 1.0 - smoothstep(0.13, 0.25, sr);
        albedo = mixOklab(albedo, vortexCol, mStorm * 0.95);
    }

    float NoL = dot(n, lightDir);
    float diff = smoothstep(-0.08, 0.28, NoL) * (0.36 + 0.64 * clamp(NoL, 0.0, 1.0));
    float NoV = max(dot(n, -rd), 0.0);
    float limbDark = pow(NoV, 0.34);
    float rimAtmo = pow(1.0 - NoV, 4.2) * smoothstep(-0.12, 0.55, NoL);

    vec3 sunCol = vec3(2.05, 1.92, 1.76);
    vec3 nightFill = srgbToLinear(vec3(0.10, 0.082, 0.064)) * 0.28;
    vec3 col = albedo * (sunCol * diff * limbDark + nightFill);
    col += srgbToLinear(vec3(0.68, 0.74, 0.84)) * rimAtmo * 0.24;
    return col;
}

vec4 shadeRings(vec3 p, vec3 planetCenter, float planetRadius, vec3 rd, vec3 lightDir, vec3 shadowAxis, vec3 ringX, vec3 ringZ) {
    vec3 rel = p - planetCenter;
    vec2 disk = vec2(dot(rel, ringX), dot(rel, ringZ));
    float r = length(disk);
    const float R_INNER = 1.98;
    const float R_OUTER = 4.62;
    if (r < R_INNER || r > R_OUTER) return vec4(0.0);

    float u = (r - R_INNER) / (R_OUTER - R_INNER);
    float edgeFade = smoothstep(0.0, 0.04, u) * (1.0 - smoothstep(0.96, 1.0, u));

    float ringlets   = 0.55 + 0.45 * fbm(vec2(r * 14.5, 1.7), 5);
    float microBands = 0.5 + 0.5 * sin(r * 74.0 + 2.2 * fbm(vec2(r * 8.0, 4.1), 3));
    float cassiniGap = 1.0 - 0.92 * cubicPulse(0.70, 0.036, u);
    float innerC     = mix(0.48, 1.0, smoothstep(0.02, 0.20, u));
    float density    = saturate((0.38 + 0.48 * ringlets + 0.22 * microBands) * cassiniGap * innerC) * edgeFade;

    float ang = atan(disk.y, disk.x + 1e-6) - gSceneTime * (0.045 / max(pow(r * 0.4, 1.5), 0.3));
    vec2 ringCoords = vec2(cos(ang), sin(ang)) * r;

    vec3 iceWarm = srgbToLinear(vec3(0.71, 0.69, 0.66));
    vec3 iceCool = srgbToLinear(vec3(0.47, 0.47, 0.50));
    vec3 albedo  = mixOklab(iceCool, iceWarm, saturate(ringlets * 0.78 + microBands * 0.3));

    // Full-width planet shadow cast cleanly across the right side of the rings!
    float projAlong = dot(rel, shadowAxis);
    float perpDist  = length(rel - shadowAxis * projAlong);
    float inShadow  = 1.0;
    if (projAlong > 0.0) {
        inShadow = smoothstep(planetRadius * 0.78, planetRadius * 0.86, perpDist);
    }

    vec4 v1 = voronoi(ringCoords * 9.5, 0.95);
    vec4 v2 = voronoi(ringCoords * 21.0 + vec2(7.3, -3.1), 0.95);
    float rock1 = (1.0 - smoothstep(0.035, 0.095, v1.x)) * step(0.86, hash12(v1.zw));
    float rock2 = (1.0 - smoothstep(0.035, 0.085, v2.x)) * step(0.83, hash12(v2.zw + 19.0));
    float pebble = saturate(rock1 + rock2 * 0.75) * cassiniGap * edgeFade;

    float phase = 0.76 + 0.24 * clamp(dot(-rd, lightDir), -1.0, 1.0);
    vec3 litRing   = albedo * vec3(1.52, 1.46, 1.38) * phase * mix(0.02, 1.0, inShadow);
    vec3 pebbleCol = srgbToLinear(vec3(0.10, 0.10, 0.11)) * mix(0.02, 0.55, inShadow);

    vec3 finalCol = mix(litRing, pebbleCol, pebble * 0.90);
    float alpha = saturate(density * 0.90 + pebble * 0.6);
    return vec4(finalCol, alpha);
}

vec3 renderSpace(vec2 uv, float pxAngle) {
    const float FOCAL = 2.0;
    float u = gSceneTime;

    vec3 planetCenter = vec3(-1.76, 0.08, 0.0);
    float orbitAng = -0.04 + 0.028 * u;
    vec3 ro = vec3(sin(orbitAng) * 5.05 - 0.12, 0.24 + 0.012 * u, cos(orbitAng) * 5.05);
    vec3 ta = vec3(-0.06 + 0.015 * u, 0.01, 0.0);
    applyOrbit(ro, planetCenter, -3.5);

    mat3 cam = cameraMatrix(ro, ta, 0.0);
    vec3 rd  = cameraRay(cam, uv, FOCAL);

    vec3 sunSkyDir = normalize(cam * vec3(1.285, 0.675, FOCAL));
    vec3 keyLight  = normalize(vec3(0.93, 0.12, 0.34));

    vec3 ringNormal = normalize(vec3(0.095, 0.982, 0.162));
    vec3 ringX = normalize(cross(ringNormal, vec3(0.0, 0.0, 1.0)));
    vec3 ringZ = normalize(cross(ringX, ringNormal));

    float shAng = 0.24 - 0.030 * u;
    vec3 shadowAxis = normalize(ringX * cos(shAng) + ringZ * sin(shAng));

    float planetRadius = 1.66;
    vec2 tSph  = iSphere(ro, rd, planetCenter, planetRadius);
    float tRing = iPlane(ro - planetCenter, rd, ringNormal, 0.0);

#if DEBUG_MODE == 1
    return debugDistance(length(vec3(uv * 2.5, 0.0) - vec3(-0.8, 0.05, 0.0)) - 0.8);
#endif

    vec3 bg = spaceStarsAndNebula(rd, sunSkyDir, cam[0], cam[1], pxAngle);
    bool hitPlanet = (tSph.x > 0.0);
    bool hitRing   = (tRing > 0.0);

    vec4 ringSample = vec4(0.0);
    if (hitRing) {
        ringSample = shadeRings(ro + rd * tRing, planetCenter, planetRadius, rd, keyLight, shadowAxis, ringX, ringZ);
    }

#if DEBUG_MODE == 2
    if (hitPlanet && (!hitRing || tSph.x < tRing || ringSample.a < 0.1)) {
        return debugNormal(normalize(ro + rd * tSph.x - planetCenter));
    }
    if (hitRing && ringSample.a > 0.05) return debugNormal(ringNormal);
    return vec3(0.0);
#elif DEBUG_MODE == 3
    if (hitPlanet && (!hitRing || tSph.x < tRing || ringSample.a < 0.2)) return debugIdColor(1.0);
    if (hitRing && ringSample.a > 0.05) return debugIdColor(2.0);
    return debugIdColor(0.0);
#elif DEBUG_MODE == 4
    return debugHeat(hitPlanet ? 0.15 : (hitRing ? 0.1 : 0.02));
#endif

    vec3 col = bg;
    if (hitPlanet) {
        vec3 planetCol = shadeGasGiant(ro + rd * tSph.x, planetCenter, rd, keyLight, ringNormal);
        if (hitRing && tRing < tSph.x) {
            col = mix(planetCol, ringSample.rgb, ringSample.a);
        } else {
            col = planetCol;
        }
    } else if (hitRing) {
        col = mix(bg, ringSample.rgb, ringSample.a);
    }
    return col;
}

// =============================================================================
// SCENE II: FOREST (Redwood Trunks, Feathered Sword Ferns, Diagonal Sunbeams)
// =============================================================================
const vec3 FOREST_SUN_DIR = normalize(vec3(0.76, 0.57, -0.31));

float forestGroundHeight(vec2 xz) {
    float h = 0.14 * fbm(xz * 0.32, 2);
    if (!gFastMap) h += 0.045 * fbm(xz * 1.5, 2);
    h -= 0.08 * exp(-xz.x * xz.x * 0.4);
    return h;
}

vec3 forestHeroTrunk(int idx) {
    if (idx == 0) return vec3(-1.68, -3.1, 0.56);
    if (idx == 1) return vec3( 1.38, -4.1, 0.52);
    if (idx == 2) return vec3(-1.32, -7.6, 0.45);
    if (idx == 3) return vec3( 2.18, -8.4, 0.42);
    if (idx == 4) return vec3(-2.45, -6.0, 0.38);
    if (idx == 5) return vec3(-0.52, -13.2, 0.39);
    if (idx == 6) return vec3( 0.68, -14.6, 0.38);
    return vec3( 1.75, -11.8, 0.34);
}

float sdRedwoodTrunk(vec3 p, vec2 centerXZ, float baseR, float seed) {
    vec2 q = p.xz - centerXZ;
    float rDist = length(q);
    float flare = 1.0 + 0.34 * exp(-max(p.y + 0.15, 0.0) * 1.5);
    float taper = max(0.74, 1.0 - 0.012 * max(p.y, 0.0));
    float rad = baseR * flare * taper;
    float rawD = rDist - rad;

    if (gFastMap || rawD > 0.32) return rawD;

    float dispFade = 1.0 - smoothstep(0.06, 0.30, rawD);
    float ang = atan(q.y, q.x + 1e-6);
    float furrow1 = ridgedFbm(vec2(ang * 4.2 + seed, p.y * 0.32), 2);
    float furrow2 = sin(ang * 26.0 + seed * 5.0 + 1.4 * fbm(vec2(ang * 3.2, p.y * 0.5), 2));
    float barkDisp = baseR * (0.052 * (furrow1 - 0.45) + 0.018 * furrow2) * dispFade;
    return (rawD - barkDisp) * 0.72;
}

// Single-cell bounded feathered sword-fern rosette (4x faster than 2x2 neighbor check, crisp serrated pinnae!)
float sdFernClumps(vec3 p, float groundY) {
    float localY = p.y - groundY;
    if (localY > 0.56) return localY - 0.46;

    const float SPACING = 1.18;
    vec2 id = domRepeatId(p.xz, vec2(SPACING));
    float keep = hash12(id + vec2(7.0, 91.0));
    if (keep < 0.14) return 0.42;

    vec2 j2 = (hash22(id + vec2(31.0, 17.0)) - 0.5) * 0.24;
    vec2 c  = id * SPACING + j2;
    vec3 q  = vec3(p.x - c.x, localY, p.z - c.y);
    float r = length(q.xz);
    float frondLen = mix(0.38, 0.50, keep);
    if (r > frondLen + 0.12) return r - frondLen - 0.04;

    vec2 sec = domPolar(rot2(keep * TAU) * q.xz, 13.0);
    float u = clamp(sec.x / frondLen, 0.0, 1.0);
    float archY = (0.31 * sin(u * 2.55) + 0.04) * (frondLen / 0.46);
    // Deeply notched serrated pinnae leaflets so fronds look feathery, not solid banana leaves!
    float pinnae = 0.22 + 0.78 * smoothstep(-0.2, 0.55, sin(u * 52.0));
    float width = 0.058 * parabola(u, 0.75) * pinnae;
    vec2 bladeD = vec2(max(abs(sec.y) - width, 0.0), q.y - archY);
    float d = max(length(bladeD) - 0.008, sec.x - frondLen);
    return d * 0.72;
}

vec2 mapForest(vec3 p) {
    float gh = forestGroundHeight(p.xz);
    vec2 res = vec2((p.y - gh) * 0.70, MAT_TERRAIN);

    float dLog1 = sdCapsule(p, vec3(-0.25, gh + 0.08, -2.55), vec3(2.35, gh + 0.11, -3.05), 0.13);
    float dLog2 = sdCapsule(p, vec3(-1.95, gh + 0.05, -4.4), vec3(-0.35, gh + 0.04, -5.2), 0.07);
    float dLogs = min(dLog1, dLog2);
    if (dLogs < res.x) res = vec2(dLogs, MAT_LOG);

    for (int i = ZERO; i < 8; i++) {
        vec3 tr = forestHeroTrunk(i);
        float dt = sdRedwoodTrunk(p, tr.xy, tr.z, float(i) * 1.7 + 0.5);
        if (dt < res.x) res = vec2(dt, MAT_TRUNK);
    }

    if (!gFastMap && (p.z < -9.5 || abs(p.x) > 2.8)) {
        const float CELL = 4.2;
        vec2 cid = domRepeatId(p.xz, vec2(CELL));
        if (abs(cid.x) >= 0.55 || cid.y <= -3.4) {
            vec3 h = hash32(cid + vec2(53.0, 19.0));
            vec2 pos = cid * CELL + (h.xy - 0.5) * 1.4;
            float rad = mix(0.22, 0.44, h.z);
            float dt = length(p.xz - pos) - rad * (1.0 + 0.22 * exp(-max(p.y, 0.0) * 1.5));
            if (dt < res.x) res = vec2(dt, MAT_TRUNK);
        }
    }

    if (p.z > -14.5 && p.z < 1.2 && (p.y - gh) < 0.58) {
        float df = sdFernClumps(p, gh);
        if (df < res.x) res = vec2(df, MAT_FERN);
    }

    return res;
}

float forestVolumetricSun(vec3 p) {
    float vis = 1.0;
    vec2 ld = FOREST_SUN_DIR.xz;
    float ldLen2 = max(dot(ld, ld), 1e-4);

    for (int i = 0; i < 6; i++) {
        vec3 tr = forestHeroTrunk(i);
        vec2 toCyl = tr.xy - p.xz;
        float proj = dot(toCyl, ld) / ldLen2;
        if (proj > 0.0) {
            vec2 closest = toCyl - ld * proj;
            float perp = length(closest);
            vis *= smoothstep(tr.z * 0.85, tr.z * 1.15, perp);
        }
    }

    vec3 sunOrtho1 = normalize(cross(FOREST_SUN_DIR, vec3(0.0, 0.0, 1.0)));
    vec3 sunOrtho2 = cross(FOREST_SUN_DIR, sunOrtho1);
    vec2 beamCoord = vec2(dot(p, sunOrtho1), dot(p, sunOrtho2));
    float shaftNoise = fbm(beamCoord * vec2(1.45, 0.55) + vec2(2.3, -1.1), 2);
    float ribbons = pow(0.5 + 0.5 * sin(beamCoord.x * 3.9 + shaftNoise * 3.0), 2.2);
    float broadOpen = smoothstep(-0.35, 0.25, shaftNoise);
    return vis * broadOpen * (0.25 + 0.75 * ribbons);
}

vec3 forestCanopyBackground(vec3 ro, vec3 rd, float pxAngle) {
    float sunAmt = max(dot(rd, FOREST_SUN_DIR), 0.0);
    vec3 brightSky = mixOklab(
        srgbToLinear(vec3(0.45, 0.56, 0.36)),
        srgbToLinear(vec3(1.0, 0.94, 0.76)) * 2.2,
        pow(sunAmt, 2.2) + smoothstep(0.05, 0.55, rd.y) * 0.35
    );
    brightSky += vec3(5.5, 4.4, 2.6) * sunDisk(rd, FOREST_SUN_DIR, 0.04, pxAngle);

    vec3 col = brightSky;
    for (int layer = 0; layer < 3; layer++) {
        float fl = float(layer);
        float zPlane = -18.0 + fl * 5.2;
        float tP = (zPlane - ro.z) / min(rd.z, -0.15);
        if (tP > 0.0) {
            vec3 hp = ro + rd * tP;
            if (hp.y > 1.2) {
                vec2 boughUV = hp.xy * vec2(0.55, 0.85) + vec2(fl * 7.3, fl * 3.1);
                float bough = fbm(boughUV * 1.8, 3);
                float needles = fbm(boughUV * 7.5, 2);
                float heightMask = smoothstep(1.4, 3.6, hp.y);
                float density = saturate((bough * 0.65 + needles * 0.35 + 0.22) * heightMask);
                float alpha = smoothstep(0.18, 0.56, density) * mix(0.68, 0.88, fl * 0.5);
                vec3 leafDark = srgbToLinear(vec3(0.10, 0.16, 0.06));
                vec3 leafGold = srgbToLinear(vec3(0.48, 0.56, 0.20)) * (1.2 + 2.0 * pow(sunAmt, 2.5));
                vec3 leafCol  = mixOklab(leafDark, leafGold, smoothstep(0.35, 0.75, needles + 0.35 * sunAmt));
                col = mix(col, leafCol, alpha);
            }
        }
    }

    vec3 lowMist = mixOklab(srgbToLinear(vec3(0.46, 0.48, 0.35)), srgbToLinear(vec3(0.84, 0.78, 0.58)), pow(sunAmt, 1.8));
    float lowFade = 1.0 - smoothstep(-0.02, 0.28, rd.y);
    return mix(col, lowMist, lowFade * 0.76);
}

vec3 renderForest(vec2 uv, vec2 fragCoord, float pxAngle) {
    const float FOCAL = 1.85;
    float u = gSceneTime;

    float zCam = -0.35 - 0.52 * u;
    float groundHere = forestGroundHeight(vec2(0.0, zCam));
    vec3 ro = vec3(0.03 * sin(u * 0.4), groundHere + 0.78, zCam);
    vec3 ta = vec3(0.05, groundHere + 0.74, zCam - 5.5);
    applyOrbit(ro, vec3(0.0, 1.0, zCam - 4.8), -0.55);

    mat3 cam = cameraMatrix(ro, ta, 0.0);
    vec3 rd  = cameraRay(cam, uv, FOCAL);

#if DEBUG_MODE == 1
    return debugDistance(mapForest(vec3(uv.x * 3.5, uv.y * 2.5 + 1.2, zCam - 4.0)).x);
#endif

    vec3 bg = forestCanopyBackground(ro, rd, pxAngle);
    vec3 hit = marchBounded(ro, rd, 0.08, 24.0, 0.88, 74);
#if DEBUG_MODE == 4
    return debugHeat(hit.z / 74.0);
#endif

    float tMaxVol = 19.0;
    vec3 col = bg;

    if (hit.x > 0.0) {
        float t = hit.x;
        tMaxVol = min(t, 19.0);
        vec3 p = ro + rd * t;
        vec3 n = calcNormal(p, 0.0012 * t);
        vec3 v = -rd;
        float m = floor(hit.y + 0.5);

        vec3 albedo = vec3(0.1);
        float rough = 0.85;
        if (m == MAT_TERRAIN) {
            // Post-hit micro-relief normal bump for forest floor litter, twigs & moss cushions (zero raymarch cost!)
            vec2 gEps = vec2(0.02, 0.0);
            float f0 = fbm(p.xz * 7.5, 3);
            float fx = fbm((p.xz + gEps.xy) * 7.5, 3);
            float fz = fbm((p.xz + gEps.yx) * 7.5, 3);
            n = normalize(n + vec3(-(fx - f0), 0.0, -(fz - f0)) * 4.5 * (1.0 - smoothstep(4.0, 14.0, t)));

            float mossPatch = smoothstep(-0.08, 0.24, fbm(p.xz * 2.2, 3));
            float clover = (1.0 - smoothstep(0.06, 0.17, voronoi(p.xz * 9.0, 0.9).x)) * smoothstep(-0.05, 0.30, fbm(p.xz * 1.6 + 5.0, 2));
            float twigs  = smoothstep(0.70, 0.90, ridgedFbm(p.xz * 6.0, 2));
            vec3 duffCol = srgbToLinear(vec3(0.26, 0.15, 0.08)) * (0.7 + 0.6 * (0.5 + 0.5 * fbm(p.xz * 13.0, 2)));
            vec3 mossCol = srgbToLinear(vec3(0.24, 0.37, 0.09));
            vec3 clovCol = srgbToLinear(vec3(0.32, 0.48, 0.14));
            albedo = mixOklab(duffCol, mossCol, mossPatch * smoothstep(0.5, 0.88, n.y));
            albedo = mixOklab(albedo, clovCol, clover * 0.78);
            albedo = mixOklab(albedo, srgbToLinear(vec3(0.14, 0.09, 0.05)), twigs * 0.6);
            rough = 0.86;
        } else if (m == MAT_LOG) {
            float mossTop = smoothstep(0.20, 0.68, n.y + 0.28 * fbm(p.xz * 5.5, 2));
            albedo = mixOklab(srgbToLinear(vec3(0.20, 0.12, 0.07)), srgbToLinear(vec3(0.24, 0.38, 0.10)), mossTop);
            rough = 0.82;
        } else if (m == MAT_TRUNK) {
            // Post-hit deep craggy fibrous bark plate normal bump (zero raymarch cost, crisp sunlit bark relief!)
            vec3 tang = normalize(vec3(-n.z, 0.0, n.x));
            float uBark = dot(p, tang) * 9.0;
            float b0 = ridgedFbm(vec2(uBark, p.y * 1.15), 3);
            float b1 = ridgedFbm(vec2(uBark + 0.08, p.y * 1.15), 3);
            float b2 = ridgedFbm(vec2(uBark, p.y * 1.15 + 0.08), 3);
            n = normalize(n + (tang * (b1 - b0) * 5.5 + vec3(0.0, (b2 - b0) * 2.5, 0.0)) * (1.0 - smoothstep(5.0, 16.0, t)));

            float barkGrain = 0.5 + 0.5 * fbm(vec3(p.x * 7.5, p.y * 0.85, p.z * 7.5), 3, 2.0, 0.5);
            float lichen = smoothstep(0.45, 0.78, fbm(p * 3.4, 2, 2.0, 0.5)) * (1.0 - smoothstep(0.4, 2.2, p.y));
            vec3 darkBark = srgbToLinear(vec3(0.11, 0.075, 0.045));
            vec3 warmBark = srgbToLinear(vec3(0.35, 0.23, 0.13));
            albedo = mixOklab(darkBark, warmBark, barkGrain * (0.45 + 0.75 * b0));
            albedo = mixOklab(albedo, srgbToLinear(vec3(0.26, 0.35, 0.20)), lichen * 0.65);
            rough = 0.86;
        } else {
            float frondVar = 0.5 + 0.5 * fbm(p.xz * 12.0, 2);
            albedo = mixOklab(srgbToLinear(vec3(0.16, 0.31, 0.08)), srgbToLinear(vec3(0.42, 0.56, 0.16)), frondVar);
            rough = 0.50;
        }

        // Bright golden dappled sunlight patches along the forest floor clearing!
        float clearingSun = smoothstep(-0.35, 0.25, fbm(p.xz * 0.95 + vec2(1.4, -0.6), 2));
        float sha = (0.18 + 0.82 * clearingSun) * fastShadow(p + n * 0.03, FOREST_SUN_DIR, 0.06, 7.5, 10.0);
        gFastMap = true;
        float ao = calcAO(p, n, 0.28);
        gFastMap = false;

        vec3 sunCol = vec3(5.6, 4.3, 2.5);
        vec3 key = shadePBR(n, v, FOREST_SUN_DIR, albedo, rough, 0.0) * sunCol * sha;
        if (m == MAT_TRUNK) {
            // Strong golden morning sun catching sun-facing redwood bark ridges!
            float sunSide = clamp(dot(n, FOREST_SUN_DIR), 0.0, 1.0);
            key += albedo * sunCol * sunSide * (0.45 + 0.55 * sha) * 0.75;
        }
        if (m == MAT_FERN) {
            float trans = translucency(n, v, FOREST_SUN_DIR, 0.4, 2.5, 0.20);
            key += albedo * sunCol * (trans * 1.8 + wrapDiffuse(n, FOREST_SUN_DIR, 0.55) * 0.65) * (0.35 + 0.65 * sha);
        }
        vec3 fill = albedo * hemisphereLight(n, srgbToLinear(vec3(0.38, 0.46, 0.29)), srgbToLinear(vec3(0.18, 0.14, 0.07))) * ao * 1.65;

#if DEBUG_MODE == 2
        return debugNormal(n);
#elif DEBUG_MODE == 3
        return debugIdColor(m);
#elif DEBUG_MODE == 5
        return vec3(sha, ao, forestVolumetricSun(p));
#elif DEBUG_MODE == 6
        return vec3(luminance(key), luminance(fill), 0.0);
#endif

        col = key + fill;
        vec3 mistTint = mixOklab(srgbToLinear(vec3(0.42, 0.45, 0.32)), srgbToLinear(vec3(0.78, 0.72, 0.52)), max(dot(rd, FOREST_SUN_DIR), 0.0));
        float fogAmt = heightFog(ro, rd, t, 0.045, 0.24);
        col = mix(col, mistTint, fogAmt * 0.78);
    }

    // Fast jittered diagonal volumetric sunbeams
    int volSteps = gInDissolve ? 8 : 12;
    float dt = tMaxVol / float(volSteps);
    float jitter = interleavedGradientNoise(floor(fragCoord), iFrame);
    float mu = dot(rd, FOREST_SUN_DIR);
    float phase = 4.0 * PI * phaseDualHG(mu, 0.68, -0.22, 0.82);

    vec3 volRad = vec3(0.0);
    vec3 volTrans = vec3(1.0);
    vec3 beamColor = vec3(2.45, 1.95, 1.16);
    vec3 ambMist   = srgbToLinear(vec3(0.24, 0.28, 0.18));

    for (int i = 0; i < 12; i++) {
        if (i >= volSteps) break;
        float tv = (float(i) + jitter) * dt;
        vec3 pv = ro + rd * tv;
        float depthGate = smoothstep(2.2, 6.2, tv);
        float mistDensity = 0.028 * exp(-max(pv.y - 0.3, 0.0) * 0.20) * (0.22 + 0.78 * depthGate);
        float shaft = forestVolumetricSun(pv);
        vec3 inScat = mistDensity * (beamColor * phase * shaft * 0.78 + ambMist * 0.34);
        volumeStep(volRad, volTrans, vec3(mistDensity), inScat, dt);
    }

    return col * volTrans + volRad;
}

// =============================================================================
// SCENE III: OCEAN (Storm Clouds, Deep-Teal Swells, Sea Stack & Lighthouse)
// =============================================================================
const vec3  OCEAN_ISLAND_POS = vec3(1.55, 0.0, 0.0);
const float OCEAN_SWELL_LEN  = 22.0;
const float OCEAN_SWELL_AMP  = 0.52;

void stormWave(int i, out vec2 dir, out float k, out float amp, out float phase) {
    float fi = float(i);
    vec3 h = hash32(vec2(fi, 29.0));
    float a = 1.72 + mix(0.32, 1.25, min(fi / 10.0, 1.0)) * (2.0 * h.x - 1.0);
    dir = vec2(cos(a), sin(a));
    k = TAU / (OCEAN_SWELL_LEN * pow(0.79, fi) * mix(0.88, 1.12, h.y));
    amp = OCEAN_SWELL_AMP * pow(0.71, fi);
    phase = TAU * h.z;
}

float stormOceanHeight(vec2 xz, int count) {
    float h = 0.0;
    for (int i = ZERO; i < 14; i++) {
        if (i >= count) break;
        vec2 dir; float k, amp, ph;
        stormWave(i, dir, k, amp, ph);
        float theta = k * dot(dir, xz) - sqrt(9.81 * k) * (gSceneTime + 4.0) + ph;
        h += amp * (exp(2.1 * (sin(theta) - 1.0)) - 0.32);
    }
    return h;
}

vec4 stormOceanDetail(vec2 xz, float footprint, out float crest) {
    vec4 s = vec4(0.0);
    crest = 0.0;
    float crestMax = 1e-4;
    for (int i = ZERO; i < 18; i++) {
        vec2 dir; float k, amp, ph;
        stormWave(i, dir, k, amp, ph);
        float keep = smoothstep(2.0, 6.0, (TAU / k) / max(footprint, 1e-4));
        float theta = k * dot(dir, xz) - sqrt(9.81 * k) * (gSceneTime + 4.0) + ph;
        float sn = sin(theta), cs = cos(theta);
        float e = exp(2.1 * (sn - 1.0));
        float d1 = 2.1 * cs * e;
        float d2 = 2.1 * (2.1 * cs * cs - sn) * e;
        s += keep * amp * vec4(e - 0.32, k * d1 * dir, k * k * d2);
        if (i < 6) {
            crest -= keep * amp * k * k * d2;
            crestMax += amp * k * k * 2.1;
        }
    }
    crest /= crestMax;
    return s;
}

vec2 mapOceanIsland(vec3 p) {
    vec3 q = p - OCEAN_ISLAND_POS;

    float dRock = sdCappedCone(q - vec3(0.0, 2.2, 0.0), 2.8, 5.4, 2.9);
    vec3 b1 = q - vec3(-3.5, 1.0, 1.4); b1.xz = rot2(0.45) * b1.xz;
    vec3 b2 = q - vec3( 3.3, 0.85, 1.2); b2.xz = rot2(-0.35) * b2.xz;
    vec3 b3 = q - vec3(-1.9, 2.6, 2.2); b3.xy = rot2(0.28) * b3.xy;
    vec3 b4 = q - vec3( 2.0, 2.4, 2.0); b4.xy = rot2(-0.24) * b4.xy;
    vec3 b5 = q - vec3( 0.2, 3.8, 1.1); b5.xz = rot2(0.6) * b5.xz;
    vec3 b6 = q - vec3(-4.7, 0.35, 0.3); b6.xz = rot2(0.25) * b6.xz;

    dRock = smin(dRock, sdRoundBox(b1, vec3(1.85, 1.35, 1.5), 0.16), 0.38);
    dRock = smin(dRock, sdRoundBox(b2, vec3(1.75, 1.15, 1.4), 0.16), 0.38);
    dRock = smin(dRock, sdRoundBox(b3, vec3(1.45, 1.45, 1.2), 0.14), 0.32);
    dRock = smin(dRock, sdRoundBox(b4, vec3(1.5, 1.35, 1.2), 0.14), 0.32);
    dRock = smin(dRock, sdRoundBox(b5, vec3(2.4, 1.1, 1.8), 0.15), 0.30);
    dRock = smin(dRock, sdRoundBox(b6, vec3(1.35, 0.75, 1.2), 0.14), 0.35);

    if (dRock < 1.8) {
        float crag = ridgedFbm(q.xz * 0.65 + vec2(q.y * 0.4), 4);
        float rockFbm = fbm(q * vec3(0.55, 0.75, 0.55), 3, 2.05, 0.52);
        dRock += -0.48 * rockFbm + 0.38 * (0.5 - crag);
    }
    dRock *= 0.62;

    vec2 res = vec2(dRock, MAT_ROCK);

    vec3 lt = q - vec3(0.15, 3.65, 0.0);
    float bastion = sdRoundBox(lt - vec3(0.0, 0.35, 0.0), vec3(2.35, 0.55, 2.15), 0.12);
    float shaft   = sdCappedCone(lt - vec3(0.0, 3.55, 0.0), 2.85, 1.35, 1.06);
    float gallery = sdCylinder(lt - vec3(0.0, 6.45, 0.0), 0.24, 1.38);
    float rail    = opOnion(sdCylinder(lt - vec3(0.0, 6.85, 0.0), 0.18, 1.34), 0.04);
    float dTower  = min(min(bastion, shaft), min(gallery, rail));
    if (dTower < res.x) res = vec2(dTower, MAT_TOWER);

    float dLantern = sdCylinder(lt - vec3(0.0, 7.30, 0.0), 0.65, 0.94);
    if (dLantern < res.x) res = vec2(dLantern, MAT_LANTERN);

    float roofRim = sdCylinder(lt - vec3(0.0, 7.96, 0.0), 0.10, 1.08);
    float dome    = sdCutSphere(lt - vec3(0.0, 7.96, 0.0), 0.98, 0.0);
    float spire   = sdCappedCone(lt - vec3(0.0, 9.20, 0.0), 0.45, 0.07, 0.01);
    float dDome   = min(min(roofRim, dome), spire);
    if (dDome < res.x) res = vec2(dDome, MAT_DOME);

    return res;
}

vec3 stormCloudSky(vec3 rd) {
    float h = max(rd.y, 0.0);
    vec3 horizonCol = srgbToLinear(vec3(0.45, 0.54, 0.58));
    vec3 midStorm   = srgbToLinear(vec3(0.32, 0.38, 0.41));
    vec3 zenithDark = srgbToLinear(vec3(0.24, 0.29, 0.32));

    vec3 baseSky = mixOklab(horizonCol, midStorm, smoothstep(0.0, 0.22, h));
    baseSky = mixOklab(baseSky, zenithDark, smoothstep(0.18, 0.65, h));

    vec2 domeUV = rd.xz / (h + 0.42) * 1.6 + vec2(gSceneTime * 0.025, -gSceneTime * 0.018);
    float c1 = 0.5 + 0.5 * fbm(domeUV, 4);
    float c2 = billowFbm(domeUV * 2.1 + vec2(2.4, -1.3), 4);
    float cloudMod = smoothstep(0.25, 0.78, c1 * 0.62 + c2 * 0.38);

    vec3 cloudLight = srgbToLinear(vec3(0.46, 0.52, 0.55));
    vec3 cloudBelly = srgbToLinear(vec3(0.25, 0.30, 0.33));
    vec3 clouds = mixOklab(cloudLight, cloudBelly, cloudMod);

    return mix(horizonCol, mix(baseSky, clouds, 0.68), smoothstep(0.01, 0.14, h));
}

vec3 lighthouseBeamScatter(vec3 ro, vec3 rd, float tMax, vec3 lampPos, vec3 beamDir) {
    float tClosest = clamp(dot(lampPos - ro, rd), 0.0, tMax);
    float t0 = max(0.0, tClosest - 18.0);
    float t1 = min(tMax, tClosest + 18.0);
    if (t1 <= t0) return vec3(0.0);

    const int STEPS = 14;
    float dt = (t1 - t0) / float(STEPS);
    vec3 acc = vec3(0.0);
    vec3 warmLamp = blackbody(2850.0) * vec3(1.15, 0.96, 0.75);

    for (int i = 0; i < STEPS; i++) {
        float t = t0 + (float(i) + 0.5) * dt;
        vec3 p = ro + rd * t;
        if (p.y < 6.5) continue;
        vec3 v = p - lampPos;
        float dist = length(v);
        vec3 dir = v / max(dist, 1e-3);

        float align = max(dot(dir, beamDir), -dot(dir, beamDir) * 0.75);
        float cone = pow(smoothstep(0.88, 0.996, align), 2.4);
        float bloom = 0.85 / (0.35 + dist * dist * 0.55);
        float atten = exp(-dist * 0.11) / (1.0 + dist * 0.22);
        float cloudWisp = 0.75 + 0.35 * fbm(p.xy * 0.22 + vec2(gSceneTime * 0.05, 0.0), 3);
        acc += warmLamp * (cone * atten * 0.95 * cloudWisp + bloom * 0.22) * dt;
    }
    return acc;
}

vec3 renderOcean(vec2 uv, float pxAngle) {
    const float FOCAL = 2.0;
    float u = gSceneTime;

    float zCam = 34.5 - 2.35 * u;
    float yCam = 4.65 - 0.08 * u;
    vec3 ro = vec3(-0.15, yCam, zCam);
    // Downward camera pitch (-0.595 over 10m) places ocean horizon at exact uv.y = +0.119 matching film!
    vec3 ta = vec3(-0.10, yCam - 0.595, zCam - 10.0);
    applyOrbit(ro, OCEAN_ISLAND_POS + vec3(0.0, 5.2, 0.0), -3.5);

    mat3 cam = cameraMatrix(ro, ta, 0.0);
    vec3 rd  = cameraRay(cam, uv, FOCAL);

    vec3 lampPos = OCEAN_ISLAND_POS + vec3(0.15, 10.95, 0.0);
    float beamAngle = 0.08 + 0.88 * (u - 0.75);
    vec3 beamDir = normalize(vec3(cos(beamAngle), 0.22 * sin(beamAngle), sin(beamAngle)));

#if DEBUG_MODE == 1
    return debugDistance(mapOceanIsland(vec3(uv.x * 9.0 + OCEAN_ISLAND_POS.x, uv.y * 9.0 + 6.0, 0.0)).x * 0.2);
#endif

    vec3 stormLightDir = normalize(vec3(-0.35, 0.78, 0.52));
    vec3 horizonFogCol = srgbToLinear(vec3(0.43, 0.52, 0.56));

    vec2 tBound = iSphere(ro, rd, OCEAN_ISLAND_POS + vec3(0.0, 5.8, 0.0), 11.2);
    vec3 islandHit = vec3(-1.0, -1.0, 0.0);
    if (tBound.y > 0.0) {
        islandHit = marchBounded(ro, rd, max(tBound.x, 0.1), min(tBound.y, 120.0), 0.80, 96);
    }

    float tOcean = -1.0;
    if (rd.y < -0.001) {
        float tLow  = max((ro.y - 1.25) / -rd.y, 0.1);
        float tHigh = min((ro.y + 1.05) / -rd.y, 260.0);
        float tCur  = tLow;
        float prevT = tLow, prevGap = 1e5;
        for (int i = ZERO; i < 44; i++) {
            vec3 p = ro + rd * tCur;
            float gap = p.y - stormOceanHeight(p.xz, 10);
            if (gap < 0.0) {
                tOcean = mix(prevT, tCur, prevGap / max(prevGap - gap, 1e-4));
                break;
            }
            if (tCur >= tHigh) break;
            prevT = tCur;
            prevGap = gap;
            tCur += max(gap * 0.52, 0.016 * tCur);
        }
        if (tOcean < 0.0) tOcean = ro.y / -rd.y;
    }

    bool hitIsland = (islandHit.x > 0.0) && (tOcean < 0.0 || islandHit.x < tOcean);
    float tScene = 120.0;
    vec3 col = stormCloudSky(rd);

#if DEBUG_MODE == 4
    return debugHeat(islandHit.z / 96.0);
#endif

    if (hitIsland) {
        float t = islandHit.x;
        tScene = t;
        vec3 p = ro + rd * t;
        vec3 n = calcNormal(p, 0.0012 * t);
        vec3 v = -rd;
        float m = floor(islandHit.y + 0.5);

        vec3 albedo = srgbToLinear(vec3(0.08, 0.09, 0.09));
        float rough = 0.65;
        float metal = 0.0;
        vec3 emissive = vec3(0.0);

        if (m == MAT_ROCK) {
            float wetZone = 1.0 - smoothstep(0.5, 2.8, p.y);
            float rockVar = 0.5 + 0.5 * fbm(p * 1.6, 3, 2.0, 0.5);
            albedo = srgbToLinear(mix(vec3(0.045, 0.055, 0.06), vec3(0.11, 0.12, 0.125), rockVar));
            albedo *= mix(1.0, 0.55, wetZone);
            rough = mix(0.76, 0.20, wetZone);

            float runnel = pow(saturate(0.5 + 0.5 * sin((p.x - OCEAN_ISLAND_POS.x) * 4.5 + fbm(p * 2.4, 2, 2.0, 0.5) * 3.8)), 5.0);
            float runnelMask = runnel * (1.0 - smoothstep(0.15, 1.95, p.y)) * smoothstep(0.0, 0.65, n.y + 0.35);
            albedo = mix(albedo, srgbToLinear(vec3(0.80, 0.85, 0.87)), runnelMask * 0.88);
        } else if (m == MAT_TOWER) {
            float ang = atan(p.z - OCEAN_ISLAND_POS.z, p.x - OCEAN_ISLAND_POS.x - 0.15 + 1e-5);
            vec2 masonryUV = vec2(ang * 4.2 + 0.5 * floor(p.y * 3.0), p.y * 3.0);
            float mortar = filteredGrid(masonryUV, vec2(0.07), 12.0);
            float stoneId = hash12(floor(masonryUV));
            vec3 stoneA = srgbToLinear(vec3(0.09, 0.09, 0.085));
            vec3 stoneB = srgbToLinear(vec3(0.18, 0.16, 0.14));
            albedo = mix(mix(stoneA, stoneB, stoneId), srgbToLinear(vec3(0.06, 0.06, 0.06)), mortar * 0.6);
            rough = 0.84;
        } else if (m == MAT_LANTERN) {
            float ang = atan(p.z - OCEAN_ISLAND_POS.z, p.x - OCEAN_ISLAND_POS.x - 0.15 + 1e-5);
            float mullions = smoothstep(0.88, 0.96, abs(sin(ang * 7.0)));
            float paneMask = 1.0 - mullions * 0.65;
            albedo = srgbToLinear(vec3(0.12, 0.10, 0.08));
            rough = 0.2;
            emissive = blackbody(3000.0) * paneMask * 22.0;
        } else {
            albedo = srgbToLinear(vec3(0.07, 0.08, 0.085));
            rough = 0.42;
            metal = 0.35;
        }

        float ao = calcAO(p, n, 0.45);
        vec3 skyFill = hemisphereLight(n, srgbToLinear(vec3(0.36, 0.43, 0.47)), srgbToLinear(vec3(0.06, 0.12, 0.14))) * ao;
        vec3 key = shadePBR(n, v, stormLightDir, albedo, rough, metal) * srgbToLinear(vec3(0.62, 0.68, 0.72));
        vec3 toLamp = lampPos - p;
        float dLamp = length(toLamp);
        vec3 lampSpill = albedo * blackbody(2800.0) * max(dot(n, toLamp / max(dLamp, 0.01)), 0.0) * (2.2 / (1.0 + dLamp * dLamp * 0.65));

#if DEBUG_MODE == 2
        return debugNormal(n);
#elif DEBUG_MODE == 3
        return debugIdColor(m);
#elif DEBUG_MODE == 5
        return vec3(ao, 0.0, 0.0);
#elif DEBUG_MODE == 6
        return vec3(luminance(key), luminance(skyFill), luminance(emissive));
#endif

        col = key + albedo * (1.0 - metal) * skyFill + lampSpill + emissive;
        col = mix(col, horizonFogCol, distanceFog(t, 0.0042));
    } else if (tOcean > 0.0) {
        float t = tOcean;
        tScene = min(t, 120.0);
        vec3 p = ro + rd * t;
        float fp = t * pxAngle / max(-rd.y, 0.04);

        float crest;
        vec4 wv = stormOceanDetail(p.xz, fp, crest);
        vec2 slope = wv.yz;

        float keepRip = smoothstep(2.0, 6.0, 0.9 / max(fp, 1e-4));
        vec3 r1 = simplexNoiseD(p.xz * 1.2 + vec2(0.25, 0.8) * u, 1.1 * u);
        vec3 r2 = simplexNoiseD(p.xz * 3.2 - vec2(0.5, 0.2) * u, -1.7 * u);
        slope += 0.024 * keepRip * (r1.yz + 0.6 * r2.yz);
        vec3 n = normalize(vec3(-slope.x, 1.0, -slope.y));

        vec3 v = -rd;
        float NoV = max(dot(n, v), 1e-3);
        float F = fresnelDielectric(NoV, 1.0, 1.333) * 0.65;

        vec3 refl = reflect(rd, n);
        refl.y = abs(refl.y);
        vec3 skyRefl = stormCloudSky(refl);

        vec3 deepTeal  = srgbToLinear(vec3(0.075, 0.235, 0.285));
        vec3 surfAqua  = srgbToLinear(vec3(0.14, 0.43, 0.44));
        vec2 dIsl = p.xz - OCEAN_ISLAND_POS.xz;
        float rWarp = length(dIsl) + 2.4 * fbm(dIsl * 0.22 + vec2(0.0, u * 0.15), 3) + 1.1 * fbm(dIsl * 0.65, 2);
        float shallowMask = 1.0 - smoothstep(5.5, 16.5, rWarp);
        float crestHeightMask = smoothstep(-0.25, 0.55, wv.x);
        vec3 body = (1.0 - F) * mix(deepTeal, surfAqua, saturate(crestHeightMask * 0.45 + shallowMask * 0.65));

        // Organic frothy swirling sea-foam lace (heavily domain-warped fbm + fine bubbles — ZERO polygon lines!)
        vec2 foamWarp = vec2(fbm(p.xz * 0.38 + vec2(0.12 * u, 0.0), 3), fbm(p.xz * 0.38 + vec2(5.2, -0.15 * u), 3));
        float frothA  = ridgedFbm(p.xz * 0.72 + foamWarp * 2.1, 4);
        float frothB  = billowFbm(p.xz * 1.65 - foamWarp * 1.4, 4);
        float fineBub = 1.0 - smoothstep(0.02, 0.20, voronoiBorder(p.xz * 3.8 + foamWarp * 2.5, 1.0).x);

        float patchEnv = smoothstep(0.42, 0.76, billowFbm(p.xz * 0.16 + vec2(0.0, 0.08 * u), 3));
        float foreLace = pow(saturate(frothA), 2.4) * (0.45 + 0.55 * fineBub) * patchEnv * (1.0 - smoothstep(10.0, 42.0, t));

        float openWhitecaps = smoothstep(0.10, 0.32, crest) * smoothstep(0.42, 0.76, frothB);
        float surfBreak = (1.0 - smoothstep(5.0, 11.8, rWarp)) * smoothstep(2.8, 5.8, rWarp) * (0.45 + 0.55 * frothB);
        float wakeSwirl = (1.0 - smoothstep(5.5, 22.0, rWarp)) * pow(saturate(frothA), 2.0)
                        * smoothstep(0.35, 0.78, 0.5 + 0.5 * sin(rWarp * 1.15 - u * 2.2));

        float foam = saturate(foreLace * 0.95 + openWhitecaps * 0.88 + surfBreak * 1.05 + wakeSwirl * 0.75);
        foam *= 1.0 - smoothstep(45.0, 130.0, t) * 0.65;

        vec3 foamLit = srgbToLinear(vec3(0.80, 0.86, 0.88)) * (0.76 + 0.24 * max(n.y, 0.0));

#if DEBUG_MODE == 2
        return debugNormal(n);
#elif DEBUG_MODE == 3
        return debugIdColor(0.0);
#elif DEBUG_MODE == 5
        return vec3(foam, saturate(crest), F);
#elif DEBUG_MODE == 6
        return vec3(luminance(F * skyRefl), luminance(body), foam);
#endif

        col = mix(F * skyRefl + body, foamLit, foam);
        float spray = (1.0 - smoothstep(4.5, 10.8, rWarp)) * smoothstep(0.30, 0.74, fbm(p.xz * 0.45 - vec2(0.0, u * 0.7), 3));
        col = mix(col, srgbToLinear(vec3(0.74, 0.80, 0.82)), spray * 0.58);
        col = mix(col, horizonFogCol, distanceFog(t, 0.0052));
    }

    col += lighthouseBeamScatter(ro, rd, tScene, lampPos, beamDir);
    return col;
}

// =============================================================================
// SCENE IV: DESERT (Rippled Orange Dunes, Sandstone Natural Arch, Hazy Mesas)
// =============================================================================
const vec3 DESERT_SUN_DIR  = normalize(vec3(-0.82, 0.29, 0.49));
const vec3 DESERT_ARCH_POS = vec3(5.2, 0.95, -23.5);

float desertDuneBase(vec2 xz) {
    // Smooth asymmetric sweeping dune crests with safe Lipschitz bound (zero crest or horizon overshoot!)
    float curve = xz.x + 1.85 * sin(xz.y * 0.14 + 0.6) + 0.10 * xz.y;
    float ph1 = curve * 0.54 + 0.55;
    float s1  = sin(ph1 + 0.38 * sin(ph1));
    float crestField = 0.56 * s1 + 0.16 * sin(ph1 * 2.0 - 0.8);

    float bench = 0.022 * (-xz.y) + 0.26 * fbm(xz * 0.045 + vec2(1.4, 0.5), 2);
    vec2 da = (xz - DESERT_ARCH_POS.xz) * vec2(0.085, 0.10);
    float pedestal = 0.95 * exp(-dot(da, da));
    float duneFade = smoothstep(4.2, 11.0, length(xz - DESERT_ARCH_POS.xz)) * (1.0 - smoothstep(30.0, 58.0, -xz.y));
    return bench + crestField * duneFade + pedestal;
}

float desertSandRipples(vec2 xz, float footprint) {
    float keep = smoothstep(2.0, 6.0, 0.34 / max(footprint, 1e-4));
    if (keep <= 0.001) return 0.0;
    float warp = fbm(xz * 0.65, 2);
    float phase = (xz.x * 0.58 - xz.y * 0.81) * 17.5 + warp * 3.8;
    float s = sin(phase - 0.32 * cos(phase));
    return 0.015 * s * keep;
}

float sdSandstoneArch(vec3 p) {
    vec3 q = p - DESERT_ARCH_POS;
    q.xz = rot2(-0.14) * q.xz;

    vec3 arcP = q - vec3(0.0, 4.35, 0.0);
    float dArc = sdCappedTorus(arcP, vec2(sin(1.70), cos(1.70)), 4.65, 1.38);

    float leftPed  = sdRoundCone(q - vec3(-4.55, -0.5, 0.0), 1.55, 0.95, 2.25);
    float leftNeck = sdRoundCone(q - vec3(-4.50, 1.85, 0.0), 0.72, 1.22, 2.35);
    float dLeft    = smin(leftPed, leftNeck, 0.38);

    float rightBase = sdRoundCone(q - vec3(4.65, -0.6, 0.0), 2.55, 1.88, 3.2);
    float rightMid  = sdRoundCone(q - vec3(4.40, 2.5, 0.0), 1.78, 1.42, 2.5);
    float dRight    = smin(rightBase, rightMid, 0.48);

    float cap = sdRoundBox(q - vec3(-0.10, 9.55, 0.0), vec3(2.85, 0.78, 1.25), 0.22);

    float d = smin(dArc, min(dLeft, dRight), 0.58);
    d = smin(d, cap, 0.52);
    float slab = abs(q.z) - 1.38;
    d = smax(d, slab - 0.30, 0.38);

    if (!gFastMap && d < 0.95) {
        // Natural weathered Navajo/Entrada sandstone strata + blocky rock fractures
        float blockNoise = fbm(p * vec3(0.38, 0.95, 0.38), 3, 2.0, 0.5);
        float strata = 0.024 * sin(p.y * 6.5 + 3.2 * blockNoise) + 0.014 * sin(p.y * 15.0 + 1.8 * blockNoise);
        float fractures = 0.11 * (ridgedFbm(vec2(p.x * 0.5 + p.z * 0.35, p.y * 0.75), 3) - 0.5);
        d += strata + fractures;
    }
    return d * 0.70;
}

vec2 mapDesert(vec3 p) {
    // Seamless valley & multi-tier mesa horizon (zero gap!)
    float h = desertDuneBase(p.xz);
    if (p.z < -42.0) {
        float mesaStart = -64.0 + 8.5 * fbm(vec2(p.x * 0.045, 3.1), 2);
        float mesaRise  = smoothstep(mesaStart + 8.0, mesaStart - 5.0, p.z);
        float tiers     = 2.8 + 1.1 * floor(0.5 + 2.0 * saturate(0.5 + 0.5 * fbm(vec2(p.x * 0.05, p.z * 0.02), 2)));
        h += mesaRise * tiers;
    }

    vec2 res = vec2((p.y - h) * 0.55, (p.z < -46.0) ? MAT_SANDSTONE : MAT_SAND);

    vec3 qa = abs(p - (DESERT_ARCH_POS + vec3(0.0, 4.6, 0.0)));
    float archBox = max(max(qa.x - 8.8, qa.y - 7.0), qa.z - 4.0);
    if (archBox < res.x + 0.5) {
        float dArch = sdSandstoneArch(p);
        if (dArch < res.x) res = vec2(dArch, MAT_SANDSTONE);
    }

    // Left margin layered sandstone butte (framed cleanly on far left edge just like film_15..19s!)
    vec3 lb = p - vec3(-12.2, 0.9, -15.8);
    if (length(lb.xz) < 6.5) {
        float b1 = sdCappedCone(lb - vec3(0.0, 1.8, 0.0), 2.2, 4.3, 2.8);
        float b2 = sdCappedCone(lb - vec3(-0.5, 4.0, 0.2), 1.6, 2.7, 1.8);
        float dButte = opStairsUnion(b1, b2, 0.65, 5.0);
        if (!gFastMap && dButte < 1.1) dButte += 0.035 * sin(p.y * 7.0) + 0.08 * fbm(p * vec3(0.45, 1.1, 0.45), 2, 2.0, 0.5);
        dButte *= 0.70;
        if (dButte < res.x) res = vec2(dButte, MAT_SANDSTONE);
    }

    // Right lower canyon bluff outcrop
    vec3 rb = p - vec3(15.2, 0.4, -27.5);
    if (length(rb.xz) < 8.5) {
        float dBluff = sdRoundBox(rb - vec3(0.0, 1.6, 0.0), vec3(4.8, 2.0, 3.0), 0.45);
        if (!gFastMap && dBluff < 1.3) dBluff += 0.14 * fbm(p * vec3(0.35, 1.1, 0.35), 2, 2.0, 0.5);
        dBluff *= 0.72;
        if (dBluff < res.x) res = vec2(dBluff, MAT_SANDSTONE);
    }

    return res;
}

vec3 desertSky(vec3 rd) {
    float h = max(rd.y, 0.0);
    vec3 zenith  = srgbToLinear(vec3(0.14, 0.39, 0.62));
    vec3 midBlue = srgbToLinear(vec3(0.35, 0.56, 0.71));
    vec3 horizon = srgbToLinear(vec3(0.80, 0.80, 0.76));

    vec3 sky = mixOklab(horizon, midBlue, smoothstep(0.0, 0.20, h));
    sky = mixOklab(sky, zenith, smoothstep(0.16, 0.62, h));
    sky += srgbToLinear(vec3(0.88, 0.68, 0.42)) * 0.22 * (1.0 - smoothstep(0.0, 0.28, h));
    return sky;
}

vec3 renderDesert(vec2 uv, float pxAngle) {
    const float FOCAL = 1.95;
    float u = gSceneTime;

    float zCam = -1.2 - 1.45 * u;
    float xCam = -0.35 + 0.16 * u;
    float baseH = desertDuneBase(vec2(xCam, zCam));
    vec3 ro = vec3(xCam, baseH + 1.44, zCam);
    vec3 ta = vec3(xCam + 0.72, baseH + 1.44 + 1.25, zCam - 10.0);
    applyOrbit(ro, DESERT_ARCH_POS + vec3(-1.0, 3.4, 4.0), -2.2);

    mat3 cam = cameraMatrix(ro, ta, 0.0);
    vec3 rd  = cameraRay(cam, uv, FOCAL);

#if DEBUG_MODE == 1
    return debugDistance(sdSandstoneArch(vec3(uv.x * 9.0 + DESERT_ARCH_POS.x, uv.y * 9.0 + 4.8, DESERT_ARCH_POS.z)) * 0.2);
#endif

    vec3 sky = desertSky(rd);
    // Analytic distant hazy mesa range right along the horizon so grazing valley rays never show sky gaps!
    float mesaAngle = atan(rd.x, -rd.z);
    float mesaRidge1 = 0.032 + 0.014 * floor(0.5 + 2.2 * saturate(0.5 + 0.5 * fbm(vec2(mesaAngle * 4.5, 1.7), 3)));
    float mesaRidge2 = 0.048 + 0.016 * saturate(0.5 + 0.5 * fbm(vec2(mesaAngle * 7.2 + 3.1, 4.2), 3));
    if (rd.y < mesaRidge2) {
        vec3 farRangeCol = mixOklab(srgbToLinear(vec3(0.46, 0.42, 0.41)), sky, 0.55);
        vec3 midMesaCol  = mixOklab(srgbToLinear(vec3(0.42, 0.31, 0.25)), sky, 0.34);
        sky = mix(sky, farRangeCol, 1.0 - smoothstep(mesaRidge2 - 0.004, mesaRidge2 + 0.002, rd.y));
        sky = mix(sky, midMesaCol,  1.0 - smoothstep(mesaRidge1 - 0.004, mesaRidge1 + 0.002, rd.y));
    }

    vec3 hit = marchBounded(ro, rd, 0.12, 165.0, 0.78, 108);
#if DEBUG_MODE == 4
    return debugHeat(hit.z / 108.0);
#endif
    if (hit.x < 0.0) return sky;

    float t = hit.x;
    vec3 p = ro + rd * t;
    float fp = t * pxAngle;
    vec3 n = calcNormal(p, max(0.0014 * t, 0.002));
    float m = floor(hit.y + 0.5);

    vec3 albedo = vec3(0.2);
    float rough = 0.82;

    if (m == MAT_SAND) {
        float eps = max(0.014, fp * 0.5);
        float r0 = desertSandRipples(p.xz, fp);
        float rx = desertSandRipples(p.xz + vec2(eps, 0.0), fp);
        float rz = desertSandRipples(p.xz + vec2(0.0, eps), fp);
        float duneMask = smoothstep(4.2, 10.5, length(p.xz - DESERT_ARCH_POS.xz)) * (1.0 - smoothstep(26.0, 48.0, t));
        vec3 ripN = normalize(vec3(-(rx - r0) / eps, 1.0, -(rz - r0) / eps));
        n = normalize(mix(n, normalize(vec3(n.x + ripN.x * 0.58, n.y, n.z + ripN.z * 0.58)), duneMask));

        float grain = 0.5 + 0.5 * fbm(p.xz * 2.8, 2);
        vec3 orangeSand = srgbToLinear(vec3(0.77, 0.44, 0.21));
        vec3 warmGold   = srgbToLinear(vec3(0.85, 0.53, 0.28));
        albedo = mixOklab(orangeSand, warmGold, grain);
        rough = 0.78;
    } else {
        float band = 0.5 + 0.5 * sin(p.y * 5.8 + 2.4 * fbm(p.xz * 0.45, 2));
        float seam = smoothstep(0.66, 0.92, ridgedFbm(vec2(p.x * 0.55 + p.z * 0.35, p.y * 1.1), 3));
        vec3 redRock  = srgbToLinear(vec3(0.58, 0.31, 0.17));
        vec3 tanLayer = srgbToLinear(vec3(0.73, 0.46, 0.28));
        vec3 darkSeam = srgbToLinear(vec3(0.26, 0.13, 0.08));
        albedo = mixOklab(redRock, tanLayer, band * 0.65);
        albedo = mixOklab(albedo, darkSeam, seam * 0.42);
        rough = 0.86;
    }

    vec3 v = -rd;
    float sha = (t < 48.0) ? fastShadow(p + n * 0.04, DESERT_SUN_DIR, 0.08, 28.0, 18.0) : 1.0;
    gFastMap = true;
    float ao  = (t < 44.0) ? calcAO(p, n, 0.45) : 1.0;
    gFastMap = false;

    vec3 sunCol = vec3(2.60, 1.98, 1.44);
    vec3 key    = shadePBR(n, v, DESERT_SUN_DIR, albedo, rough, 0.0) * sunCol * sha;
    vec3 skyFill = albedo * hemisphereLight(n, srgbToLinear(vec3(0.32, 0.46, 0.64)), srgbToLinear(vec3(0.42, 0.23, 0.12))) * ao * 0.95;
    vec3 bounce  = albedo * srgbToLinear(vec3(0.68, 0.38, 0.18)) * (0.35 + 0.65 * max(-n.y, 0.0)) * ao * 0.28;

#if DEBUG_MODE == 2
    return debugNormal(n);
#elif DEBUG_MODE == 3
    return debugIdColor(m);
#elif DEBUG_MODE == 5
    return vec3(sha, ao, 0.0);
#elif DEBUG_MODE == 6
    return vec3(luminance(key), luminance(skyFill), luminance(bounce));
#endif

    vec3 col = key + skyFill + bounce;
    vec3 mesaHaze = desertSky(normalize(vec3(rd.x, max(rd.y, 0.03), rd.z))) * 0.82;
    float distHaze = smoothstep(38.0, 125.0, t) * 0.78 + distanceFog(t, 0.0035) * 0.18;
    return mix(col, mesaHaze, saturate(distHaze));
}

// =============================================================================
// SCENE V: CAVERN (Dark Wet Limestone, Stalactites, Saturated Cyan/Violet Gems)
// =============================================================================
float cavernCenterX(float z) {
    return -0.28 * sin(z * 0.09 + 0.3) - 0.14;
}

vec4 cavernCrystalAnchor(float sliceIdx, float sideSign) {
    float z = -3.1 * sliceIdx - 2.4 + 0.5 * (hash11(sliceIdx * 7.0 + sideSign * 3.0) - 0.5);
    float cx = cavernCenterX(z);
    // Anchor right on the rocky limestone wall alcoves so clusters sprout directly from the rock!
    float wallX = cx + sideSign * mix(2.22, 2.52, hash11(sliceIdx * 13.0 + sideSign + 5.0));
    float wallY = mix(0.32, 1.38, hash11(sliceIdx * 19.0 - sideSign * 2.0));
    float hueId = hash11(sliceIdx * 29.0 + sideSign * 11.0);
    return vec4(wallX, wallY, z, hueId);
}

float sdCrystalCluster(vec3 p, vec3 anchor, float sideSign, float seed) {
    vec3 q = p - anchor;
    float r = length(q);
    if (r > 0.92) return r - 0.68;

    q.xy = rot2(sideSign * 0.78) * q.xy;
    q.xz = rot2((seed - 0.5) * 0.75) * q.xz;

    // 5 crisp pointed hexagonal quartz/amethyst prisms radiating inward from wall rock
    float d = 1e5;
    for (int i = 0; i < 5; i++) {
        float fi = float(i) - 2.0;
        vec3 s = q;
        s.xy = rot2(fi * 0.34) * s.xy;
        s.yz = rot2(sin(fi * 2.1 + seed * 6.0) * 0.36) * s.yz;
        float h = mix(0.32, 0.62, 1.0 - abs(fi) * 0.25);
        float w = mix(0.055, 0.095, 1.0 - abs(fi) * 0.20);
        vec3 hp = vec3(s.x, s.z, s.y - h * 0.52);
        float tipTaper = 1.0 - 0.85 * smoothstep(h * 0.15, h * 0.98, s.y);
        float prism = sdHexPrism(hp, vec2(w * max(tipTaper, 0.08), h * 0.52));
        d = min(d, prism);
    }
    return d * 0.75;
}

vec2 mapCavern(vec3 p) {
    float cx = cavernCenterX(p.z);
    vec2 local = vec2(p.x - cx, p.y - 0.68);

    float rib = 0.10 * sin(p.z * 1.15);
    vec2 archScale = vec2(local.x / (2.68 + rib), local.y / (2.15 + rib * 0.8));
    float tunnelR = length(archScale);
    float wallDisp = gFastMap
        ? (0.14 * fbm(p * vec3(0.95, 1.35, 0.75), 2, 2.05, 0.52))
        : (0.15 * fbm(p * vec3(0.95, 1.35, 0.75), 3, 2.05, 0.52)
         + 0.06 * ridgedFbm(vec2(p.z * 1.2, atan(local.y, local.x + 1e-5) * 3.5), 2));
    float dCave = (1.0 - tunnelR) * 2.10 - wallDisp;
    vec2 res = vec2(dCave * 0.60, MAT_CAVE_WALL);

    // Hanging limestone stalactites along ceiling arch
    if (p.y > 0.40 && abs(local.x) < 2.15) {
        const float ST_SPACE = 0.40;
        vec2 sid = domRepeatId(p.xz, vec2(ST_SPACE));
        vec2 side = sign(p.xz - ST_SPACE * sid);
        float dStal = 1e5;
        for (int j = 0; j < 2; j++) {
            for (int i = 0; i < 2; i++) {
                vec2 cell = sid + vec2(float(i), float(j)) * side;
                float cellCx = cavernCenterX(cell.y * ST_SPACE);
                float relX = (cell.x * ST_SPACE - cellCx) / 2.55;
                if (abs(relX) > 0.74) continue;
                vec3 h = hash32(cell + vec2(41.0, 83.0));
                if (h.x < 0.24) continue;
                float ceilY = 0.68 + 2.12 * sqrt(max(1.0 - relX * relX, 0.0));
                float len   = mix(0.24, 1.22, pow(h.y, 1.8)) * (1.0 - 0.38 * abs(relX));
                float baseR = mix(0.038, 0.090, h.z);
                vec2 posXZ  = cell * ST_SPACE + (h.xy - 0.5) * 0.14;
                vec3 sp = vec3(p.x - posXZ.x, (ceilY - len * 0.5) - p.y, p.z - posXZ.y);
                float dc = sdCappedCone(sp, len * 0.54, baseR, 0.006);
                dStal = min(dStal, dc);
            }
        }
        if (dStal < res.x) res = vec2(dStal, MAT_STALACTITE);
    }

    // Only evaluate crystals on the side of the tunnel p is on, for the 2 nearest z-slices -> 3x faster!
    if (abs(local.x) > 0.95) {
        float sideSign = (local.x > 0.0) ? 1.0 : -1.0;
        float sliceF = (-p.z - 2.4) / 3.1;
        float s0 = floor(sliceF);
        for (int ds = 0; ds < 2; ds++) {
            float sIdx = max(0.0, s0 + float(ds));
            if (sIdx > 9.0) continue;
            vec4 anc = cavernCrystalAnchor(sIdx, sideSign);
            float dc = sdCrystalCluster(p, anc.xyz, sideSign, anc.w);
            float matC = (anc.w > 0.48) ? MAT_CRYSTAL_A : MAT_CRYSTAL_B;
            if (dc < res.x) res = vec2(dc, matC);
        }
    }

    return res;
}

vec3 cavernCrystalLighting(vec3 p, vec3 n, vec3 v, vec3 albedo, float rough) {
    vec3 cCyan   = srgbToLinear(vec3(0.18, 0.82, 1.00));
    vec3 cViolet = srgbToLinear(vec3(0.56, 0.28, 1.00));

    float slice = floor((-p.z - 2.4) / 3.1 + 0.5);
    vec3 total = vec3(0.0);

    for (int ds = -1; ds < 2; ds++) {
        float sIdx = max(0.0, slice + float(ds));
        if (sIdx > 9.0) continue;
        for (int sideIdx = 0; sideIdx < 2; sideIdx++) {
            float sideSign = (sideIdx == 0) ? -1.0 : 1.0;
            vec4 anc = cavernCrystalAnchor(sIdx, sideSign);
            vec3 lightPos = anc.xyz - vec3(sideSign * 0.35, 0.0, 0.0);
            vec3 L = lightPos - p;
            float d2 = dot(L, L);
            vec3 lDir = L * inversesqrt(max(d2, 1e-4));
            // Tight alcove falloff so rock walls stay cool neutral limestone except right beside crystals!
            vec3 lCol = mix(cViolet, cCyan, step(0.48, anc.w)) * (1.25 / (0.55 + d2 * 1.45));
            total += shadePBR(n, v, lDir, albedo, rough, 0.0) * lCol;
        }
    }

    // Cool neutral-slate limestone ambient matching the foreground grey rock & tan stalactites in film_22.00.png!
    vec3 camLight = normalize(vec3(0.0, 0.15, 1.0));
    total += shadePBR(n, v, camLight, albedo, rough, 0.0) * srgbToLinear(vec3(0.62, 0.64, 0.68)) * 1.15;
    total += albedo * hemisphereLight(n, srgbToLinear(vec3(0.42, 0.44, 0.48)), srgbToLinear(vec3(0.12, 0.15, 0.17))) * 1.45;
    return total;
}

vec3 shadeCavernSurface(vec3 ro, vec3 rd, float t, float matId, bool isRefl) {
    vec3 p = ro + rd * t;
    vec3 n = calcNormal(p, 0.0016 * t);
    vec3 v = -rd;
    float m = floor(matId + 0.5);

    vec3 darkHaze = srgbToLinear(vec3(0.02, 0.045, 0.055));

    if (m == MAT_CRYSTAL_A || m == MAT_CRYSTAL_B) {
        // Rich saturated amethyst-violet outer prisms with glowing electric-cyan inner heart!
        float sideSign = (p.x > cavernCenterX(p.z)) ? 1.0 : -1.0;
        float s0 = max(floor((-p.z - 2.4) / 3.1), 0.0);
        vec4 anc0 = cavernCrystalAnchor(s0, sideSign);
        vec4 anc1 = cavernCrystalAnchor(min(s0 + 1.0, 9.0), sideSign);
        float distFromRoot = min(length(p - anc0.xyz), length(p - anc1.xyz));
        float coreHeart = exp(-distFromRoot * 5.8);

        float cleavage = 1.0 - smoothstep(0.01, 0.09, voronoiBorder(p.yz * 7.5 + p.x * 3.5, 0.85).x);
        float NoV = max(dot(n, v), 0.0);
        float facetShade = 0.25 + 0.75 * abs(dot(n, normalize(vec3(-sideSign * 0.6, 0.55, 0.58))));
        vec3 deepAmethyst = srgbToLinear(vec3(0.36, 0.14, 0.90));
        vec3 electricCyan = srgbToLinear(vec3(0.10, 0.85, 1.00));

        vec3 outerTone = (m == MAT_CRYSTAL_A) ? deepAmethyst : mixOklab(deepAmethyst, electricCyan, 0.42);
        vec3 heartTone = electricCyan * 2.4;

        vec3 col = mix(outerTone * (0.50 + 0.95 * facetShade), heartTone, coreHeart * 0.90);
        col *= 1.0 - 0.38 * cleavage;
        col += electricCyan * cleavage * coreHeart * 0.85;
        float edgeRim = pow(1.0 - NoV, 2.5);
        col = mix(col, deepAmethyst * 0.45, edgeRim * 0.60);
        col += vec3(0.65, 0.82, 1.0) * pow(max(dot(reflect(rd, n), normalize(vec3(-sideSign, 0.45, 0.65))), 0.0), 16.0) * 0.9;
        return mix(col, darkHaze, distanceFog(t, 0.020));
    }

    // Post-hit limestone crag normal relief (zero raymarch cost!)
    if (!isRefl && t < 16.0) {
        float c0 = ridgedFbm(vec2(p.z * 3.5, p.y * 4.2 + p.x * 2.0), 3);
        float cz = ridgedFbm(vec2(p.z * 3.5 + 0.06, p.y * 4.2 + p.x * 2.0), 3);
        float cy = ridgedFbm(vec2(p.z * 3.5, p.y * 4.2 + 0.06 + p.x * 2.0), 3);
        n = normalize(n + vec3(0.0, -(cy - c0), -(cz - c0)) * 3.2 * (1.0 - smoothstep(6.0, 16.0, t)));
    }

    float rockTex = 0.5 + 0.5 * fbm(p * 2.8, 2, 2.0, 0.5);
    float crevice = smoothstep(0.45, 0.85, ridgedFbm(vec2(p.z * 2.2, p.y * 2.8 + p.x), 2));
    vec3 albedo = (m == MAT_STALACTITE)
        ? mix(srgbToLinear(vec3(0.18, 0.16, 0.14)), srgbToLinear(vec3(0.34, 0.30, 0.25)), rockTex)
        : mix(srgbToLinear(vec3(0.10, 0.11, 0.125)), srgbToLinear(vec3(0.24, 0.25, 0.27)), rockTex);
    albedo *= 1.0 - 0.45 * crevice;
    float wet = 1.0 - smoothstep(0.05, 1.15, p.y);
    float rough = mix(0.56, 0.22, wet);

    gFastMap = true;
    float ao = isRefl ? 0.68 : calcAO(p, n, 0.34);
    gFastMap = false;
    vec3 col = cavernCrystalLighting(p, n, v, albedo, rough) * mix(0.24, 1.0, ao);
    return mix(col, darkHaze, distanceFog(t, 0.026));
}

vec3 renderCavern(vec2 uv) {
    const float FOCAL = 1.85;
    float u = gSceneTime;

    float zCam = -0.8 - 0.72 * u;
    float xCam = cavernCenterX(zCam);
    vec3 ro = vec3(xCam, 0.44, zCam);
    vec3 ta = vec3(cavernCenterX(zCam - 6.5) - 0.10, 0.34, zCam - 6.5);
    applyOrbit(ro, vec3(cavernCenterX(zCam - 5.0), 0.72, zCam - 5.0), -0.60);

    mat3 cam = cameraMatrix(ro, ta, 0.0);
    vec3 rd  = cameraRay(cam, uv, FOCAL);

#if DEBUG_MODE == 1
    return debugDistance(mapCavern(vec3(uv.x * 3.0 + xCam, uv.y * 2.5 + 1.1, zCam - 4.0)).x);
#endif

    float tWater = (rd.y < -0.0005) ? (-ro.y / rd.y) : -1.0;
    float tMaxPrimary = (tWater > 0.0) ? min(tWater, 28.0) : 28.0;

    vec3 hit = marchBounded(ro, rd, 0.08, tMaxPrimary, 0.82, 72);
#if DEBUG_MODE == 4
    return debugHeat(hit.z / 72.0);
#endif

    float endDist = length((uv - vec2(-0.14, -0.04)) * vec2(1.0, 1.35));
    vec3 endGlow = srgbToLinear(vec3(0.06, 0.36, 0.44)) * exp(-endDist * 5.5) * 1.4
                 + srgbToLinear(vec3(0.015, 0.04, 0.05));

    if (hit.x > 0.0 && (tWater < 0.0 || hit.x < tWater)) {
#if DEBUG_MODE == 2
        return debugNormal(calcNormal(ro + rd * hit.x, 0.0016 * hit.x));
#elif DEBUG_MODE == 3
        return debugIdColor(floor(hit.y + 0.5));
#elif DEBUG_MODE == 5
        vec3 pDbg = ro + rd * hit.x;
        return vec3(calcAO(pDbg, calcNormal(pDbg, 0.002 * hit.x), 0.34), 0.0, 0.0);
#elif DEBUG_MODE == 6
        return shadeCavernSurface(ro, rd, hit.x, hit.y, false);
#endif
        return shadeCavernSurface(ro, rd, hit.x, hit.y, false);
    }

    if (tWater > 0.0 && tWater < 28.0) {
        vec3 wp = ro + rd * tWater;
        vec2 ringOrigin = vec2(cavernCenterX(zCam - 5.2), zCam - 5.2);
        float rDrip = length(wp.xz - ringOrigin);
        float dripWave = sin(rDrip * 18.0 - u * 4.2) * exp(-rDrip * 0.75) * 0.0032;
        vec3 flow = simplexNoiseD(wp.xz * vec2(0.9, 2.8) + vec2(0.0, u * 0.25), 0.35 * u);
        vec2 slope = flow.yz * vec2(0.0032, 0.013) + normalize(wp.xz - ringOrigin + vec2(1e-4)) * dripWave * 4.5;
        slope *= 1.0 - smoothstep(10.0, 25.0, tWater);
        vec3 wn = normalize(vec3(-slope.x, 1.0, -slope.y));

#if DEBUG_MODE == 2
        return debugNormal(wn);
#elif DEBUG_MODE == 3
        return debugIdColor(0.0);
#endif

        vec3 reflRd = reflect(rd, wn);
        reflRd.y = max(reflRd.y, 0.015);

        gFastMap = true;
        float rt = 0.08;
        float rMat = -1.0;
        for (int i = ZERO; i < 32; i++) {
            vec2 rh = mapCavern(wp + reflRd * rt);
            if (abs(rh.x) < 0.004 * rt + 0.002) {
                rMat = rh.y;
                break;
            }
            rt += rh.x * 0.90;
            if (rt > 24.0) break;
        }
        gFastMap = false;

        vec3 reflCol = endGlow;
        if (rMat > 0.0) {
            reflCol = shadeCavernSurface(wp, reflRd, rt, rMat, true);
        }

        float F = fresnelDielectric(max(dot(wn, -rd), 1e-3), 1.0, 1.333);
        vec3 riverDeep = srgbToLinear(vec3(0.012, 0.032, 0.036)) * beerTransmittance(vec3(0.30, 0.09, 0.07), 1.6);
        float reflWeight = clamp(F * 1.25 + 0.14, 0.0, 0.92);
        vec3 waterCol = riverDeep + reflCol * reflWeight * 0.90;
        return mix(waterCol, endGlow * 0.35, distanceFog(tWater, 0.024));
    }

    return endGlow;
}

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
        hdr = renderSpace(uv, pxAngle);
        exposure = SPACE_EXPOSURE;
    } else if (sceneId == 1) {
        hdr = renderForest(uv, fragCoord, pxAngle);
        exposure = FOREST_EXPOSURE;
    } else if (sceneId == 2) {
        hdr = renderOcean(uv, pxAngle);
        exposure = OCEAN_EXPOSURE;
    } else if (sceneId == 3) {
        hdr = renderDesert(uv, pxAngle);
        exposure = DESERT_EXPOSURE;
    } else {
        hdr = renderCavern(uv);
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

    float uA = inSlot + DISSOLVE_TIME;
    vec3 colA = renderScene(slot, uA, fragCoord);

#if DEBUG_MODE == 0
    colA = linearToSrgb(colA);
#endif

    if (gInDissolve) {
        int nextSlot = (slot + 1) % 5;
        float uB = inSlot - dissolveStart;
        float alpha = clamp((inSlot - dissolveStart) / DISSOLVE_TIME, 0.0, 1.0);
        vec3 colB = renderScene(nextSlot, uB, fragCoord);
#if DEBUG_MODE == 0
        colB = linearToSrgb(colB);
#endif
        return mix(colA, colB, alpha);
    }
    return colA;
}

vec2 map(vec3 p) {
    if (gSceneId == 1) return mapForest(p);
    if (gSceneId == 2) return mapOceanIsland(p);
    if (gSceneId == 3) return mapDesert(p);
    return mapCavern(p);
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
// FILM_DURATION / SCENE_DURATION / DISSOLVE_TIME: timeline sync with public/film.mp4 (25s loop, 0.75s dissolves).
// ORBIT_YAW_RANGE / ORBIT_PITCH_MAX: sensitivity and elevation bounds of iMouse camera orbit across all 5 scenes.
// SPACE_EXPOSURE..CAVERN_EXPOSURE: per-scene scene-linear exposure prior to AgX tonemapping.
// OCEAN_SWELL_LEN / OCEAN_SWELL_AMP: primary storm wavelength and swell height in Scene III.
// DESERT_ARCH_POS / DESERT_SUN_DIR: sandstone arch placement and golden-hour shadow angle in Scene IV.
