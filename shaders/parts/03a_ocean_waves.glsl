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
