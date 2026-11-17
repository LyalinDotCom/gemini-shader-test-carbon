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
