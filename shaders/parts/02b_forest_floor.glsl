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
