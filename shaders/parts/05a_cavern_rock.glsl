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
