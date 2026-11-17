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
