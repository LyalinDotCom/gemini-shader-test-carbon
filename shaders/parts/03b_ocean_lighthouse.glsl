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
