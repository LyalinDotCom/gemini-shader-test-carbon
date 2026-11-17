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
