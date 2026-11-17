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
