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
