// =============================================================================
// SCENE V (Part B): CAVERN CRYSTALS, DRUZY VEINS, LIGHTING & UNDERGROUND RIVER
// 12-prong chisel-pointed hexagonal amethyst & cyan quartz clusters, craggy
// baby-point druzy collars, jagged fissure veins, cool-slate cave lighting,
// and liquid horizontally-rippled underground river with concentric drip rings.
// =============================================================================

const int CC_CLUSTER_COUNT = 16;

// Precomputed world anchors snapped 1:1 onto 05a_cavern_rock's stepped karst benches & bays!
// Stored in GPU constant address space (zero thread-stack spill -> +18 fps speedup!).
const vec3 CC_ANC[16] = vec3[16](
    vec3( 1.984, 0.500,  -2.150), // 0: orbit rear-right guard
    vec3(-2.015, 0.220,  -3.350), // 1: far-left 20s waterline violet cluster
    vec3( 1.758, 1.280,  -5.520), // 2: upper-right radial amethyst hero rosette!
    vec3( 1.685, 0.270,  -5.380), // 3: lower-right waterline twin #1 (cyan heart)
    vec3(-1.936, 1.040,  -5.850), // 4: upper-left splayed cyan/violet star cluster
    vec3( 1.525, 0.280,  -6.550), // 5: lower-right waterline twin #2 (hero in 23s/24s!)
    vec3(-2.268, 0.200,  -7.850), // 6: mid-left waterline amethyst peacock fan!
    vec3(-2.132, 1.380,  -8.150), // 7: mid-left upper-arch hanging cyan cluster
    vec3( 2.226, 0.220, -10.350), // 8: mid-right recessed alcove violet bank
    vec3( 2.521, 0.840, -13.350), // 9: deeper right mid-wall small violet cluster
    vec3(-2.421, 1.000, -13.650), // 10: deeper left upper-arch cyan cluster
    vec3(-2.330, 0.220, -13.850), // 11: deeper left waterline cyan fan
    vec3( 2.389, 0.220, -15.150), // 12: deeper right waterline violet fan
    vec3(-2.106, 0.240, -19.850), // 13: beyond inner arch subtle cyan cluster
    vec3(-1.329, 0.460, -24.950), // 14: end-grotto left-wall turquoise cluster
    vec3(-0.080, 0.200, -25.400)  // 15: end-grotto center-bottom turquoise cluster!
);

const vec3 CC_GROW_DIR[16] = vec3[16](
    vec3(-0.72029,  0.58023,  0.38015), // 0
    vec3( 0.73051,  0.56039,  0.39027), // 1
    vec3(-0.75378, -0.32161,  0.57287), // 2: wide outward-left radial amethyst rosette!
    vec3(-0.68243,  0.52186,  0.51182), // 3: waterline twin #1 angled out-up
    vec3( 0.80915, -0.17981,  0.55941), // 4: upper-left star
    vec3(-0.66079,  0.54065,  0.52063), // 5: waterline twin #2 angled out-up
    vec3( 0.71986,  0.51990,  0.45991), // 6: mid-left waterline amethyst peacock fan
    vec3( 0.54975, -0.77965,  0.29987), // 7: mid-left upper cyan down-right
    vec3(-0.66119,  0.62112,  0.42076), // 8: mid-right violet bank
    vec3(-0.78164, -0.25053,  0.57120), // 9: deeper right mid violet
    vec3( 0.70098, -0.56079,  0.44062), // 10: deeper left upper cyan
    vec3( 0.65094,  0.65094,  0.39057), // 11: deeper left waterline cyan
    vec3(-0.68037,  0.62034,  0.39021), // 12: deeper right waterline violet
    vec3( 0.67983,  0.64984,  0.33992), // 13: beyond inner arch cyan
    vec3( 0.72141,  0.36070,  0.59115), // 14: end-grotto left turquoise
    vec3( 0.06025,  0.80334,  0.59246)  // 15: end-grotto center turquoise
);

// vec4(scale, seedAngleRad, matId, cyanStyle)
const vec4 CC_PARAMS[16] = vec4[16](
    vec4(0.65, 0.70, MAT_CAVERN_CRYSTAL_VIOLET, 0.06), // 0
    vec4(0.44, 1.45, MAT_CAVERN_CRYSTAL_VIOLET, 0.08), // 1
    vec4(1.14, 2.38, MAT_CAVERN_CRYSTAL_VIOLET, 0.16), // 2: royal amethyst w/ tight cyan-lilac heart
    vec4(0.90, 3.20, MAT_CAVERN_CRYSTAL_CYAN,   0.46), // 3: cyan heart + cobalt-violet shafts
    vec4(0.54, 4.96, MAT_CAVERN_CRYSTAL_CYAN,   0.58), // 4: upper-left cyan/violet star
    vec4(1.04, 4.06, MAT_CAVERN_CRYSTAL_CYAN,   0.44), // 5: cyan heart + cobalt-violet shafts
    vec4(1.15, 0.92, MAT_CAVERN_CRYSTAL_VIOLET, 0.10), // 6: deep royal amethyst peacock fan
    vec4(0.60, 5.53, MAT_CAVERN_CRYSTAL_CYAN,   0.95), // 7: hanging cyan cluster
    vec4(0.84, 2.70, MAT_CAVERN_CRYSTAL_VIOLET, 0.06), // 8: mid-right violet bank
    vec4(0.40, 4.58, MAT_CAVERN_CRYSTAL_VIOLET, 0.06), // 9
    vec4(0.46, 3.71, MAT_CAVERN_CRYSTAL_CYAN,   0.96), // 10
    vec4(0.74, 1.95, MAT_CAVERN_CRYSTAL_CYAN,   0.92), // 11
    vec4(0.72, 1.70, MAT_CAVERN_CRYSTAL_VIOLET, 0.08), // 12
    vec4(0.50, 5.15, MAT_CAVERN_CRYSTAL_CYAN,   0.95), // 13
    vec4(0.58, 5.72, MAT_CAVERN_CRYSTAL_CYAN,   1.00), // 14
    vec4(0.90, 2.89, MAT_CAVERN_CRYSTAL_CYAN,   1.00)  // 15
);

// 12-prong trig-free radiating quartz cluster tables (including stubby baby basal points!):
// 0..5: main crown shafts (also evaluated in gFastMap reflections)
// 6..8: wide lateral fan blades (tilted off-axis so zero flat stop-sign ends face camera!)
// 9..11: short stubby baby quartz points tucked into the craggy druzy rock socket!
const vec4 CC_PRONG_ROT[12] = vec4[12](
    vec4( 0.98481,  0.17365,  0.99255, -0.12187), // 0: tall central king point
    vec4( 0.80902,  0.58779,  0.90631, -0.42262), // 1: tall V-crown companion
    vec4(-0.91355,  0.40674,  0.86603, -0.50000), // 2: opposite inner crown
    vec4(-0.55919, -0.82904,  0.88295, -0.46947), // 3: back-inner point
    vec4( 0.69466, -0.71934,  0.81915, -0.57358), // 4: front-inner point
    vec4( 0.10453,  0.99452,  0.52992, -0.84805), // 5: long lateral fan blade
    vec4(-0.97815, -0.20791,  0.57358, -0.81915), // 6: wide opposite fan blade
    vec4( 0.61566,  0.78801,  0.60182, -0.79864), // 7: angled side gem (off-camera axis)
    vec4( 0.06976, -0.99756,  0.46947, -0.88295), // 8: wide lateral fan blade
    vec4(-0.55919,  0.82904,  0.37461, -0.92718), // 9: stubby baby basal point #1
    vec4( 0.95106, -0.30902,  0.40674, -0.91355), // 10: stubby baby basal point #2
    vec4(-0.80902, -0.58779,  0.32557, -0.94552)  // 11: stubby baby basal point #3
);

const vec4 CC_PRONG_DIM[12] = vec4[12](
    vec4(0.0550, 0.7200, 0.1001,  0.050),
    vec4(0.0480, 0.6100, 0.0854, -0.060),
    vec4(0.0450, 0.5500, 0.0792,  0.040),
    vec4(0.0420, 0.4700, 0.0731, -0.050),
    vec4(0.0440, 0.5100, 0.0770,  0.060),
    vec4(0.0420, 0.5000, 0.0739, -0.040),
    vec4(0.0400, 0.4300, 0.0688,  0.050),
    vec4(0.0390, 0.3700, 0.0671, -0.050),
    vec4(0.0360, 0.3900, 0.0619,  0.040),
    vec4(0.0360, 0.2500, 0.0594, -0.040),
    vec4(0.0370, 0.2300, 0.0610,  0.040),
    vec4(0.0340, 0.2000, 0.0551, -0.030)
);

const vec2 CC_PRONG_SPIN[12] = vec2[12](
    vec2(0.95106, 0.30902),
    vec2(0.75471, 0.65606),
    vec2(0.98163, 0.19081),
    vec2(0.89101, 0.45399),
    vec2(0.61566, 0.78801),
    vec2(0.96593, 0.25882),
    vec2(0.80902, 0.58779),
    vec2(0.68200, 0.73135),
    vec2(0.92718, 0.37461),
    vec2(0.85717, 0.51504),
    vec2(0.94552, 0.32557),
    vec2(0.73135, 0.68200)
);

void cc_prongLocal(int k, float lenVar, vec3 qs, out vec3 s, out vec4 shape) {
    vec4 pr = CC_PRONG_ROT[k];
    vec4 dm = CC_PRONG_DIM[k];
    vec2 sp = CC_PRONG_SPIN[k];

    float x1 = pr.x * qs.x - pr.y * qs.z;
    float z1 = pr.y * qs.x + pr.x * qs.z;

    float radialOff = (k == 0) ? 0.0 : ((k < 5) ? 0.028 : ((k < 9) ? 0.050 : 0.082));
    float x2 = x1 - radialOff;
    float y2 = qs.y + 0.02;

    float x3 = pr.z * x2 - pr.w * y2;
    float y3 = pr.w * x2 + pr.z * y2;

    s = vec3(sp.x * x3 - sp.y * z1, y3, sp.y * x3 + sp.x * z1);

    float alt = ((k & 1) == 0) ? (1.0 + lenVar) : (1.0 - lenVar);
    shape = vec4(dm.x, dm.y * alt, dm.z, dm.w);
}

// Exact/bound hexagonal quartz prism along +Y terminated by a sharp 6-sided pyramidal chisel point!
float cc_sdQuartzPoint(vec3 s, vec4 shape) {
    const vec3 kHex = vec3(-0.8660254, 0.5, 0.57735027);
    float r     = shape.x;
    float len   = shape.y;
    float hTip  = shape.z;
    float slant = shape.w;

    vec2 q = abs(s.xz);
    q -= 2.0 * min(dot(kHex.xy, q), 0.0) * kHex.xy;

    float dHex = length(q - vec2(clamp(q.x, -kHex.z * r, kHex.z * r), r)) * sign(q.y - r);
    float invNorm = inversesqrt(hTip * hTip + r * r);
    float dCap = (q.y * hTip + (s.y + slant * s.z - len) * r) * invNorm;
    float dBase = -0.18 - s.y;

    return max(max(dHex, dCap), dBase);
}

vec2 mapCavern(vec3 p) {
    vec2 res = mapCavernRock(p);

    int i0 = 0;
    int i1 = 1;
    if (p.z <= -17.5) {
        i0 = 12; i1 = 15;
    } else if (p.z <= -11.8) {
        i0 = 8;  i1 = 12;
    } else if (p.z <= -7.10) {
        i0 = 5;  i1 = 8;
    } else if (p.z <= -4.15) {
        i0 = 1;  i1 = 6;
    }

    for (int id = i0; id <= i1; id++) {
        vec3 anc    = CC_ANC[id];
        vec4 params = CC_PARAMS[id];
        float scale = params.x;

        // Generous boundR margin (>= 0.18 * scale + 0.08 above 0.78 * scale) so dShell NEVER
        // drops below reflection hitEps at any distance!
        float boundR = 0.96 * scale + 0.08;

        vec3 rel = p - anc;
        vec3 ad  = abs(rel);
        if (max(ad.x, max(ad.y, ad.z)) > boundR + res.x) continue;

        float r2 = dot(rel, rel);
        float maxR = boundR + res.x;
        if (r2 > maxR * maxR) continue;

        float rDist = sqrt(r2);
        if (rDist > boundR) {
            float dShell = rDist - 0.78 * scale;
            if (dShell < res.x) res = vec2(dShell, params.z);
            continue;
        }

        vec3 growDir = CC_GROW_DIR[id];
        vec3 upRef = (abs(growDir.y) < 0.92) ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
        vec3 bX = normalize(cross(upRef, growDir));
        vec3 bZ = cross(growDir, bX);
        vec3 qs = vec3(dot(rel, bX), dot(rel, growDir), dot(rel, bZ)) / scale;

        float seedAng = params.y;
        float cs = cos(seedAng), sn = sin(seedAng);
        qs.xz = vec2(cs * qs.x - sn * qs.z, sn * qs.x + cs * qs.z);
        float lenVar = 0.11 * sin(seedAng * 2.3);

        float dCrystal = 1e5;
        int prongCount = gFastMap ? 6 : 12;
        for (int k = 0; k < 12; k++) {
            if (k >= prongCount) break;
            vec3 s;
            vec4 shape;
            cc_prongLocal(k, lenVar, qs, s, shape);
            float dp = cc_sdQuartzPoint(s, shape);
            dCrystal = min(dCrystal, dp);
        }
        dCrystal = max(dCrystal, -0.02 - qs.y);
        dCrystal = dCrystal * scale * 0.92;

        // Sleek craggy hexagonal druzy socket tucked cleanly at the cluster root
        const vec3 kHex = vec3(-0.8660254, 0.5, 0.57735027);
        vec2 qCol = abs(qs.xz);
        qCol -= 2.0 * min(dot(kHex.xy, qCol), 0.0) * kHex.xy;
        float dCollarRadial = qCol.y - 0.175;
        float dDruzy = max(dCollarRadial, max(qs.y - 0.044, -0.22 - qs.y));
        if (dDruzy < 0.09) {
            float cragFade = 1.0 - smoothstep(0.04, 0.09, dDruzy);
            float crag = ridgedFbm(qs.xz * 7.5 + vec2(seedAng * 2.1, -seedAng), 2);
            dDruzy += 0.030 * (0.52 - crag) * cragFade;
        }
        dDruzy = dDruzy * scale * 0.80;

        float dCluster = min(dCrystal, dDruzy);
        if (dCluster < res.x) {
            float mCluster = (dDruzy < dCrystal - 0.003) ? MAT_CAVERN_DRUZY : params.z;
            res = vec2(dCluster, mCluster);
        }
    }

    return res;
}

vec3 cc_marchCavern(vec3 ro, vec3 rd, float tmin, float tmax, int maxSteps, out float lastTOut) {
    int cap = gInDissolve ? 52 : maxSteps;
    float stride = gInDissolve ? 0.99 : 0.94;
    float tolScale = gInDissolve ? 0.0018 : 0.0009;
    float tolMin   = gInDissolve ? 0.0008 : 0.0004;
    float t = tmin;
    vec2 lastH = vec2(1e5, MAT_CAVERN_WALL);
    for (int i = ZERO; i < 64; i++) {
        if (i >= cap) break;
        vec2 h = mapCavern(ro + rd * t);
        lastH = h;
        lastTOut = t;
        if (abs(h.x) < max(tolScale * t, tolMin)) return vec3(t, h.y, float(i));
        t += h.x * stride;
        if (t > tmax) break;
    }
    lastTOut = t;
    if (t <= tmax && lastH.x < 0.075) return vec3(t, lastH.y, float(cap));
    return vec3(-1.0, -1.0, float(cap));
}

vec3 cc_calcCavernNormal(vec3 p, float eps) {
    vec3 n = vec3(0.0);
    for (int i = ZERO; i < 4; i++) {
        vec3 e = 0.5773 * (2.0 * vec3((((i + 3) >> 1) & 1), ((i >> 1) & 1), (i & 1)) - 1.0);
        n += e * mapCavern(p + e * eps).x;
    }
    return normalize(n);
}

int cc_nearestClusterId(vec3 p, out float bestNormDist) {
    int bestId = 0;
    bestNormDist = 1e5;
    for (int i = 0; i < CC_CLUSTER_COUNT; i++) {
        vec3 rel = p - CC_ANC[i];
        float d = length(rel) / max(CC_PARAMS[i].x, 0.45);
        if (d < bestNormDist) {
            bestNormDist = d;
            bestId = i;
        }
    }
    return bestId;
}

// Jagged multi-octave ridgedFbm-eroded rock crack veins & tiny druzy flecks around cluster roots
// (sits strictly inside ragged karst fractures — zero smooth Voronoi worms!)
void cc_applyWallVeins(vec3 p, vec3 n, float t, bool isRefl, inout vec3 albedo, inout float rough, out vec3 emissive, out float veinMaskOut) {
    emissive = vec3(0.0);
    veinMaskOut = 0.0;
    if (isRefl || t > 16.0) return;

    float normDist;
    int cid = cc_nearestClusterId(p, normDist);
    float env = 1.0 - smoothstep(0.22, 0.88, normDist);
    if (env <= 0.005) return;

    vec4 par = CC_PARAMS[cid];
    float fp = max(t * 0.0012, 0.0008);

    // Multi-octave turbulent warp + ridgedFbm rock fracture erosion so veins look jagged & crystalline!
    vec2 baseUv = p.zy * 2.4 + vec2(p.x * 1.1, float(cid) * 1.7);
    float rCrease = ridgedFbm(baseUv * 1.35, 3);
    float tCrease = turbulence(baseUv * 2.6 + vec2(3.1, -1.9), 3);
    vec2 jagWarp = vec2(rCrease - 0.5, tCrease - 0.5) * 0.95;

    float border = voronoiBorder(baseUv + jagWarp, 0.92).x;
    // Erode border width with high-freq ridgedFbm so crack pinches & branches organically
    float erodedBorder = border + 0.028 * (1.0 - rCrease) + 0.016 * tCrease;
    float fractureGate = smoothstep(0.48, 0.80, rCrease);

    float w = clamp(0.018 + fp * 1.5, 0.018, 0.052);
    float seam = (1.0 - smoothstep(w * 0.20, w * 1.25, erodedBorder)) * fractureGate * env;
    float darkLip = (1.0 - smoothstep(w * 0.5, w * 2.2, erodedBorder)) * fractureGate * env;
    veinMaskOut = seam;

    float fleck = 0.0;
    if (normDist < 0.72) {
        vec4 vc = voronoi(p.zy * 22.0 + p.x * 14.0 + jagWarp * 3.0, 0.95);
        fleck = (1.0 - smoothstep(0.035, 0.14, vc.x)) * step(0.86, hash12(vc.zw + 19.0))
              * fractureGate * (1.0 - smoothstep(0.28, 0.72, normDist));
    }

    vec3 darkSocket = srgbToLinear(vec3(0.042, 0.048, 0.090));
    vec3 veinViolet = srgbToLinear(vec3(0.32, 0.18, 0.88));
    vec3 veinCyan   = srgbToLinear(vec3(0.10, 0.72, 0.98));
    vec3 mineralCol = mixOklab(veinViolet, veinCyan, par.w);

    albedo = mix(albedo, darkSocket, saturate(darkLip * 0.70));
    rough  = mix(rough, 0.26, saturate(darkLip * 0.40));
    emissive = mineralCol * (seam * 0.62 + fleck * 1.05 * (0.4 + 0.6 * abs(n.x)));
}

// Cavern lighting rig: moody wet charcoal-slate near-left framing + warm-neutral grey karst stone
// + cool limestone silver-grey Arch 3 chamber light + tightly localized crystal alcove bounce!
vec3 cc_lightCavernRock(vec3 p, vec3 n, vec3 v, vec3 albedo, float rough, float ao, bool isRefl, out vec3 neutralOut, out vec3 bounceOut) {
    vec3 cViolet = srgbToLinear(vec3(0.48, 0.24, 1.00));
    vec3 cCyan   = srgbToLinear(vec3(0.16, 0.86, 1.00));

    float cx = cavernCenterX(p.z);
    float foreFade = 1.0 - smoothstep(-3.5, -16.2, p.z) * 0.60;
    // Dim near-left foreground wall ~26% for moody framing; boost foreground right wall ~28% to match film_20..24!
    float nearLeftDim    = 1.0 - 0.26 * (1.0 - smoothstep(-6.0, -2.2, p.z)) * smoothstep(0.0, 1.15, cx - p.x);
    float rightWallBoost = 1.0 + 0.28 * (1.0 - smoothstep(-7.5, -2.5, p.z)) * smoothstep(0.0, 1.15, p.x - cx);
    float wallProfile    = foreFade * nearLeftDim * rightWallBoost;

    vec3 channelDir = normalize(vec3((cx - p.x) * 0.52, 0.22 - (p.y - 0.95) * 0.24, 0.66));
    float stoneRough = clamp(rough, 0.34, 0.72);
    float wrapDiff = wrapDiffuse(n, channelDir, 0.58);
    vec3 stoneLightCol = srgbToLinear(vec3(0.92, 0.90, 0.86));

    vec3 neutralKey = (albedo * stoneLightCol * wrapDiff * 1.82
                    + specularGGX(n, v, channelDir, stoneRough, vec3(0.032)) * stoneLightCol * 0.66)
                    * wallProfile;

    vec3 caveAmb = albedo * hemisphereLight(
        n,
        srgbToLinear(vec3(0.50, 0.50, 0.49)),
        srgbToLinear(vec3(0.23, 0.23, 0.23))
    ) * (1.52 * wallProfile + 0.26) * ao;

    // Pale cool limestone silver-grey chamber light at inner Arch 3 (z ~ -17.5) matching film_20..24.png!
    vec3 archLightPos = vec3(cavernCenterX(-17.8), 1.35, -17.8);
    vec3 toArch = archLightPos - p;
    float dArch2 = dot(toArch, toArch);
    vec3 archDir = toArch * inversesqrt(max(dArch2, 1e-3));
    float archBell = exp(-pow((p.z + 17.6) * 0.36, 2.0));
    vec3 coolArchTint = srgbToLinear(vec3(0.78, 0.81, 0.84));
    vec3 archLight = albedo * coolArchTint * wrapDiffuse(n, archDir, 0.45) * (2.35 * archBell / (1.0 + dArch2 * 0.14))
                   + albedo * srgbToLinear(vec3(0.50, 0.53, 0.56)) * (0.85 * archBell * ao);

    neutralOut = neutralKey + caveAmb + archLight;

    bounceOut = vec3(0.0);
    if (isRefl && p.z < -15.0) return neutralOut;
    for (int i = 0; i < CC_CLUSTER_COUNT; i++) {
        vec3 anc = CC_ANC[i];
        if (abs(p.z - anc.z) > 1.65) continue;

        vec4 par  = CC_PARAMS[i];
        vec3 gDir = CC_GROW_DIR[i];
        vec3 lPos = anc + gDir * (0.24 * par.x);
        vec3 L = lPos - p;
        float d2 = dot(L, L);
        if (d2 > 2.50) continue;

        float dist = sqrt(max(d2, 1e-4));
        vec3 lDir = L / dist;
        // Tight alcove cutoff so rock >1.2m from a crystal reads true neutral grey-slate limestone!
        float cutoff = 1.0 - smoothstep(0.65, 1.55, dist);
        float power = par.x * par.x * (1.80 / (0.24 + d2 * 2.35)) * cutoff;

        vec3 lCol = mixOklab(cViolet, cCyan, par.w);
        if (isRefl) {
            bounceOut += albedo * lCol * (max(dot(n, lDir), 0.0) * 0.58 + 0.16) * power;
        } else {
            vec3 pbrTerm = min(shadePBR(n, v, lDir, albedo, max(rough, 0.34), 0.0), vec3(0.85));
            bounceOut += pbrTerm * lCol * power;
            bounceOut += albedo * lCol * wrapDiffuse(n, lDir, 0.45) * power * 0.24 * ao;
        }
    }

    return neutralOut + bounceOut;
}

// High-contrast faceted mineral optics: deep saturated royal-amethyst outer shafts (65%+),
// crisp chevron phantom growth zones, grazing-only specular ridge glints (zero CAD wireframe!),
// and a tightly concentrated blazing electric-cyan/lilac root heart (inner 25..32%)!
vec3 cc_shadeCrystal(vec3 p, vec3 rd, vec3 n, float t, float pxAngle, bool isRefl, out float bevelOut) {
    float normDist;
    int cid = cc_nearestClusterId(p, normDist);

    vec3 anc     = CC_ANC[cid];
    vec3 growDir = CC_GROW_DIR[cid];
    vec4 params  = CC_PARAMS[cid];

    float scale   = params.x;
    float seedAng = params.y;
    float style   = params.w;

    vec3 upRef = (abs(growDir.y) < 0.92) ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 bX = normalize(cross(upRef, growDir));
    vec3 bZ = cross(growDir, bX);
    vec3 qs = vec3(dot(p - anc, bX), dot(p - anc, growDir), dot(p - anc, bZ)) / scale;

    float cs = cos(seedAng), sn = sin(seedAng);
    qs.xz = vec2(cs * qs.x - sn * qs.z, sn * qs.x + cs * qs.z);
    float lenVar = 0.11 * sin(seedAng * 2.3);

    float bestD = 1e5;
    vec3  bestS = vec3(0.0, 0.3, 0.0);
    vec4  bestShape = vec4(0.05, 0.6, 0.09, 0.0);
    float bestIdx = 0.0;
    int prongCount = isRefl ? 6 : 12;
    for (int k = 0; k < 12; k++) {
        if (k >= prongCount) break;
        vec3 s;
        vec4 shape;
        cc_prongLocal(k, lenVar, qs, s, shape);
        float dp = cc_sdQuartzPoint(s, shape);
        if (dp < bestD) {
            bestD = dp;
            bestS = s;
            bestShape = shape;
            bestIdx = float(k);
        }
    }

    const vec3 kHex = vec3(-0.8660254, 0.5, 0.57735027);
    float r    = bestShape.x;
    float len  = bestShape.y;
    float hTip = bestShape.z;

    vec2 q = abs(bestS.xz);
    q -= 2.0 * min(dot(kHex.xy, q), 0.0) * kHex.xy;

    float uAxial = clamp((bestS.y + 0.01) / max(len, 0.05), 0.0, 1.0);
    float shY    = len - hTip;
    float inTip  = smoothstep(shY - 0.010, shY + 0.010, bestS.y);

    float dPrismRidge = length(vec2(abs(q.x), q.y) - vec2(kHex.z * r, r));
    float dPyrRidge   = abs(abs(q.x) - kHex.z * q.y) * 0.866;
    float dShoulder   = length(vec2(q.y - r, bestS.y - shY));
    float edgeDist    = min(mix(dPrismRidge, dPyrRidge, inTip), dShoulder) * scale;

    float fp = max(t * pxAngle, 0.0010);
    float bevelW = clamp(0.0016 + 0.22 * fp, 0.0016, 0.0068);
    float rawEdge = 1.0 - smoothstep(bevelW * 0.20, bevelW * 1.30, edgeDist);

    vec3 v = -rd;
    vec3 refrDir = refract(rd, n, 1.0 / 1.544);
    vec3 pInt = p + refrDir * (0.055 * scale);

    // Crisp internal quartz chevron phantom growth bands parallel to the 6-sided termination faces!
    float chevronCoord = bestS.y + q.y * (hTip / max(r, 1e-3)) + bestIdx * 0.17;
    float chevWave1 = smoothstep(0.28, 0.76, 0.5 + 0.5 * sin(chevronCoord * 38.0 + 1.8 * gradientNoise(pInt * 10.0)));
    float chevWave2 = smoothstep(0.35, 0.80, 0.5 + 0.5 * sin(chevronCoord * 82.0));
    float chevronBands = 0.68 * chevWave1 + 0.32 * chevWave2;
    float phantomZone  = cubicPulse(0.68, 0.17, uAxial) + 0.72 * cubicPulse(0.46, 0.13, uAxial);

    float cleavage = 0.0;
    float striations = 0.0;
    if (!isRefl && t < 18.0) {
        float cBorder = voronoiBorder(pInt.yz * 11.5 + pInt.x * 6.5 + seedAng, 0.88).x;
        cleavage = 1.0 - smoothstep(0.009, 0.055, cBorder);
        float striaKeep = (1.0 - inTip) * (1.0 - smoothstep(0.003, 0.014, fp));
        striations = (0.5 + 0.5 * sin(bestS.y * 165.0 + q.x * 10.0)) * striaKeep;
    }

    // Tightly confined bioluminescent heart on amethyst (#2/#6: inner 25..32%), widened ~30% into a
    // glowing electric-aquamarine heart on cyan-cored hero clusters (#3/#5, style > 0.40)!
    float cyanBoost = smoothstep(0.28, 0.54, style);
    float aboveSocket = smoothstep(-0.005, 0.055, qs.y);
    vec3 coreCenter = anc + growDir * (0.06 * scale);
    float distRoot  = length(pInt - coreCenter) / max(scale, 0.40);
    float coreSpatial = exp(-distRoot * mix(5.8, 3.85, cyanBoost));
    float coreAxial   = pow(1.0 - smoothstep(0.0, mix(0.35, 0.51, cyanBoost), uAxial), 1.95);
    float rootHeart   = saturate(coreSpatial * 0.85 + coreAxial * 0.50) * aboveSocket;
    float midGlow     = exp(-distRoot * mix(4.2, 2.75, cyanBoost)) * (1.0 - smoothstep(0.06, mix(0.42, 0.60, cyanBoost), uAxial)) * aboveSocket;

    // Rich mineral palette: deep indigo-amethyst shadow faces vs bright icy-lilac specular faces!
    vec3 deepAmethyst  = srgbToLinear(vec3(0.15, 0.10, 0.48));
    vec3 royalAmethyst = srgbToLinear(vec3(0.38, 0.22, 0.86));
    vec3 cobaltViolet  = srgbToLinear(vec3(0.26, 0.34, 0.88));
    vec3 icyLilac      = srgbToLinear(vec3(0.68, 0.73, 0.99));
    vec3 deepAqua      = srgbToLinear(vec3(0.07, 0.42, 0.74));
    vec3 brightAqua    = srgbToLinear(vec3(0.20, 0.80, 0.98));
    vec3 electricCyan  = srgbToLinear(vec3(0.16, 0.94, 0.98));
    vec3 hotIceCore    = srgbToLinear(vec3(0.78, 0.98, 1.00));

    float pureCyan = smoothstep(0.65, 0.98, style);
    vec3 shaftMid  = mixOklab(royalAmethyst, cobaltViolet, smoothstep(0.0, 0.55, style) * 0.65);
    shaftMid = mixOklab(shaftMid, brightAqua, pureCyan);

    vec3 shaftDark = mixOklab(deepAmethyst, deepAqua, pureCyan);
    vec3 brightFaceCol = mixOklab(icyLilac, srgbToLinear(vec3(0.60, 0.94, 1.00)), pureCyan);

    // Strong flat face-to-face contrast between adjacent 60-deg prism & pyramid facets!
    vec3 fLight1 = normalize(vec3(-growDir.x * 0.68, 0.56, 0.48));
    vec3 fLight2 = normalize(vec3(growDir.x * 0.60, -0.32, 0.73));
    vec3 fLight3 = normalize(vec3(-growDir.x * 0.20, 0.85, 0.48));
    float f1 = pow(max(dot(n, fLight1), 0.0), 2.3);
    float f2 = pow(max(dot(n, fLight2), 0.0), 2.0);
    float f3 = pow(max(dot(n, fLight3), 0.0), 3.0);

    float faceContrast = saturate(f1 * 0.95 + f2 * 0.45 + f3 * 0.35);
    float bandMod = 0.78 + 0.34 * chevronBands + 0.08 * striations;

    vec3 crystalCol = mix(shaftDark, shaftMid, saturate(faceContrast * 1.15)) * bandMod;
    // Bright icy-lilac / frost-cyan sheen on direct key-facing facets
    crystalCol = mix(crystalCol, brightFaceCol * (0.78 + 0.42 * chevronBands), pow(faceContrast, 1.8) * (0.58 + 0.24 * inTip));
    // Distinct deeper royal-indigo chevron phantom growth bands inside mid/upper shaft
    crystalCol = mix(crystalCol, shaftDark * 0.56, saturate(phantomZone * (0.50 + 0.42 * (1.0 - chevronBands))));

    // Confined internal cyan-lilac transmission & blazing root heart
    vec3 midCyanTint = mixOklab(srgbToLinear(vec3(0.54, 0.68, 1.00)), electricCyan, smoothstep(0.0, 0.38, style));
    crystalCol = mix(crystalCol, midCyanTint * (1.42 + 0.55 * cyanBoost), saturate(midGlow * (0.82 + 0.16 * cyanBoost)));

    vec3 coreRadiance = mix(midCyanTint * (2.50 + 0.65 * cyanBoost), hotIceCore * (3.50 + 0.75 * cyanBoost), smoothstep(0.40, 0.85, rootHeart));
    crystalCol = mix(crystalCol, coreRadiance, smoothstep(0.18, 0.80, rootHeart) * 0.95);

    // Subtle refracted internal cleavage planes strictly inside translucent heart (zero outer polygon lines!)
    crystalCol *= 1.0 - 0.18 * cleavage * (1.0 - rootHeart);
    crystalCol += midCyanTint * cleavage * rootHeart * 0.55;

    // Grazing/specular-gated micro-ridge glint ONLY (zero uniform CAD wireframe outlines!)
    float NoV = max(dot(n, v), 1e-3);
    float F = fresnelDielectric(NoV, 1.0, 1.544);
    vec3 reflV = reflect(rd, n);
    float specAlign = max(max(dot(reflV, fLight1), 0.0), max(dot(reflV, fLight3), 0.0) * 0.85);
    float grazingGate = saturate(pow(1.0 - NoV, 2.2) * 0.55 + pow(specAlign, 3.0) * 0.85) * (0.25 + 0.75 * faceContrast);
    float bevelGlint = rawEdge * grazingGate;
    bevelOut = bevelGlint;

    crystalCol += brightFaceCol * bevelGlint * (0.65 + 0.55 * inTip);

    float rough = mix(0.085, 0.042, inTip) + 0.03 * striations;
    vec3 glassSpec = specularGGX(n, v, fLight1, rough, vec3(0.046)) * srgbToLinear(vec3(0.92, 0.94, 1.00)) * 2.25
                   + specularGGX(n, v, fLight3, rough, vec3(0.046)) * brightFaceCol * 1.25;

    crystalCol = mix(crystalCol, shaftDark * 0.65, F * 0.28 * (1.0 - rootHeart));
    crystalCol += glassSpec;

    return crystalCol;
}

// Craggy dark geode druzy collar (blends seamlessly into wet dark karst stone — no purple disk!)
vec3 cc_shadeDruzyBed(vec3 p, vec3 rd, vec3 nIn, float t, float pxAngle, bool isRefl) {
    float normDist;
    int cid = cc_nearestClusterId(p, normDist);
    vec4 par = CC_PARAMS[cid];
    vec3 gDir = CC_GROW_DIR[cid];

    vec3 n = nIn;
    float sparkle = 0.0;
    if (!isRefl && t < 14.0) {
        vec4 vc = voronoi(p.yz * 34.0 + p.x * 22.0, 0.95);
        vec2 cellRnd = hash22(vc.zw + vec2(7.0, 23.0)) - 0.5;
        float fade = saturate(1.0 - smoothstep(2.5, 12.0, t) - smoothstep(0.004, 0.018, t * pxAngle) * 0.5);
        n = normalize(n + vec3(cellRnd.x, cellRnd.y, -cellRnd.x * 0.7) * 0.62 * fade);
        sparkle = pow(max(dot(reflect(rd, n), normalize(vec3(-gDir.x, 0.55, 0.72))), 0.0), 26.0) * fade;
    }

    vec3 albedo = srgbToLinear(vec3(0.065, 0.070, 0.092));
    vec3 glowTint = mixOklab(srgbToLinear(vec3(0.42, 0.26, 0.96)), srgbToLinear(vec3(0.18, 0.84, 1.00)), par.w);

    vec3 nOut1;
    vec3 nOut2;
    vec3 col = cc_lightCavernRock(p, n, -rd, albedo, 0.28, 0.45, isRefl, nOut1, nOut2);
    col += glowTint * (exp(-normDist * 5.2) * 0.36 + sparkle * 1.35);
    return col;
}

float cc_fastCaveAO(vec3 p, vec3 n) {
    gFastMap = true;
    float h1 = mapCavern(p + n * 0.11).x;
    float h2 = mapCavern(p + n * 0.34).x;
    gFastMap = false;
    float occ = (0.11 - h1) * 2.4 + (0.34 - h2) * 0.95;
    return clamp(1.0 - occ, 0.0, 1.0);
}

vec3 cc_shadeSurface(vec3 ro, vec3 rd, float t, float matId, float pxAngle, bool isRefl,
                     out vec3 dbgN, out vec3 dbgMasks, out vec3 dbgLight) {
    vec3 p = ro + rd * t;
    bool fastN = (isRefl || t > 15.5);
    if (fastN) gFastMap = true;
    vec3 n = cc_calcCavernNormal(p, max(0.0015 * t, 0.0009));
    if (fastN) gFastMap = false;

    float m = floor(matId + 0.5);
    vec3 darkCaveFog = srgbToLinear(vec3(0.020, 0.032, 0.038));

    if (m == MAT_CAVERN_CRYSTAL_VIOLET || m == MAT_CAVERN_CRYSTAL_CYAN) {
        float bevelMask = 0.0;
        vec3 cCol = cc_shadeCrystal(p, rd, n, t, pxAngle, isRefl, bevelMask);
        if (isRefl) cCol *= 1.15;
        dbgN = n;
        dbgMasks = vec3(1.0, 0.8, bevelMask);
        dbgLight = vec3(0.0, luminance(cCol) * 0.5, luminance(cCol));
        return mix(cCol, darkCaveFog, distanceFog(t, 0.012));
    }

    if (m == MAT_CAVERN_DRUZY) {
        vec3 dCol = cc_shadeDruzyBed(p, rd, n, t, pxAngle, isRefl);
        dbgN = n;
        dbgMasks = vec3(0.45, 0.9, 0.25);
        dbgLight = vec3(0.1, luminance(dCol), 0.25);
        return mix(dCol, darkCaveFog, distanceFog(t, 0.016));
    }

    vec3 albedo = vec3(0.15);
    float rough = 0.45;
    vec3 rockN = n;
    shadeCavernRock(m, p, n, t, isRefl, albedo, rough, rockN);

    vec3 veinEmissive = vec3(0.0);
    float veinMask = 0.0;
    cc_applyWallVeins(p, rockN, t, isRefl, albedo, rough, veinEmissive, veinMask);

    float ao = (isRefl || t > (gInDissolve ? 10.5 : 15.0)) ? 0.66 : cc_fastCaveAO(p, rockN);

    vec3 neutralL;
    vec3 bounceL;
    vec3 lit = cc_lightCavernRock(p, rockN, -rd, albedo, rough, ao, isRefl, neutralL, bounceL);
    lit = lit * mix(0.36, 1.0, ao) + veinEmissive;

    if (isRefl && m == MAT_CAVERN_STALACTITE) {
        float steepDim = 1.0 - 0.85 * smoothstep(0.38, 0.65, rd.y);
        lit = mix(srgbToLinear(vec3(0.032, 0.048, 0.046)), lit, 0.46 * steepDim);
    }

    dbgN = rockN;
    dbgMasks = vec3(ao, veinMask, 1.0 - rough);
    dbgLight = vec3(luminance(neutralL), luminance(bounceL), luminance(veinEmissive));

    return mix(lit, darkCaveFog, distanceFog(t, 0.017));
}

// Horizontally-rippled underground river (active down to tWater ~ 0.9m so foreground reflections
// break into liquid horizontal bands!) + 1.65x crisp expanding concentric ceiling-drip rings!
vec3 cc_riverNormal(vec2 xz, float zCam, float tWater, float pxAngle, out float dripMaskOut) {
    float u = gSceneTime;
    float fp = tWater * pxAngle / max(0.06, 0.35 / (1.0 + tWater * 0.15));
    float farFade  = 1.0 - smoothstep(13.5, 26.5, tWater);
    float foreRamp = 0.64 + 0.36 * smoothstep(0.75, 2.50, tWater);

    // Longitudinal z-wavelets (stronger dh/dz) slicing reflections into shimmering horizontal liquid rungs!
    vec4 w1 = waterWaveD(xz, u * 0.54 + 2.0, vec2(0.07, 0.998), 0.31, 0.0028, 1.5, fp);
    vec4 w2 = waterWaveD(xz, u * 0.66 + 5.1, vec2(-0.11, 0.994), 0.16, 0.0014, 1.5, fp);
    vec4 w3 = waterWaveD(xz, u * 0.42 + 1.3, vec2(0.04, 0.999), 0.52, 0.0022, 1.5, fp);
    vec3 f1 = simplexNoiseD(xz * vec2(0.80, 4.40) + vec2(0.0, u * 0.18), 0.24 * u);
    float noiseKeep = smoothstep(2.0, 6.0, 0.24 / max(fp, 1e-4));

    vec2 slope = ((w1.yz + w2.yz + w3.yz) * 1.15 + f1.yz * vec2(0.0016, 0.0145) * noiseKeep) * foreRamp;

    // Prominent concentric ceiling-drip ring packets in center foreground (22s..24s hero feature!)
    dripMaskOut = 0.0;
    for (int d = 0; d < 2; d++) {
        float fd = float(d);
        vec2 origin = (d == 0)
            ? vec2(cavernCenterX(zCam - 3.55) - 0.03, zCam - 3.55)
            : vec2(cavernCenterX(zCam - 6.75) + 0.14, zCam - 6.75);

        vec2 delta = xz - origin;
        float r = length(delta);
        if (r < 2.7) {
            vec2 rDir = delta / max(r, 1e-4);
            for (int gen = 0; gen < 2; gen++) {
                float cycle = fract(u * 0.38 + fd * 0.47 + 0.42) + float(gen);
                float rFront = cycle * 1.18 + 0.14;
                float packet = cubicPulse(rFront, 0.58, r) * exp(-r * 0.52) * (1.0 - cycle * 0.34);
                float kRing = 19.0;
                float ringKeep = smoothstep(2.0, 5.5, (TAU / kRing) / max(fp * 0.42, 1e-4));
                float dWave = cos((r - rFront) * kRing) * kRing * 0.0096 * packet * ringKeep;
                slope += rDir * dWave;
                float ringCrest = pow(0.5 + 0.5 * sin((r - rFront) * kRing), 2.2) * packet * ringKeep;
                dripMaskOut = max(dripMaskOut, ringCrest);
            }
        }
    }

    slope *= farFade;
    return normalize(vec3(-slope.x, 1.0, -slope.y));
}

vec3 cc_grottoBackdrop(vec3 rd, float endZ) {
    vec3 darkVault = srgbToLinear(vec3(0.012, 0.020, 0.025));
    float reachGrotto = smoothstep(-23.2, -25.0, endZ);
    vec2 gUv = vec2(rd.x + 0.04, rd.y + 0.03);
    float gDist = length(gUv * vec2(1.0, 1.45));
    return darkVault + srgbToLinear(vec3(0.06, 0.46, 0.58)) * exp(-gDist * 11.5) * (0.65 * reachGrotto);
}

vec3 renderCavern(vec2 uv, vec2 fragCoord, float pxAngle) {
    const float FOCAL = 1.85;
    float u = gSceneTime;

    float zCam = -0.80 - 0.72 * u;
    float xCam = cavernCenterX(zCam);
    vec3 ro = vec3(xCam, 0.44, zCam);
    vec3 ta = vec3(cavernCenterX(zCam - 6.5) - 0.10, 0.34, zCam - 6.5);

    bool orbited = (length(iMouse.xy) >= 0.5);
    applyOrbit(ro, vec3(cavernCenterX(zCam - 5.0), 0.72, zCam - 5.0), -0.54);
    if (orbited) {
        float cxOrb = cavernCenterX(ro.z);
        ro.x = clamp(ro.x, cxOrb - 1.05, cxOrb + 1.05);
        ro.y = clamp(ro.y, 0.18, 1.35);
    }

    mat3 cam = cameraMatrix(ro, ta, 0.0);
    vec3 rd  = cameraRay(cam, uv, FOCAL);

#if DEBUG_MODE == 1
    vec3 sliceP = vec3(uv.x * 2.6 + cavernCenterX(-5.52), uv.y * 1.8 + 0.85, -5.52);
    return debugDistance(mapCavern(sliceP).x);
#endif

    float tWater = (rd.y < -0.0004) ? (-ro.y / rd.y) : -1.0;
    float tMaxPrimary = (tWater > 0.0) ? min(tWater, 34.0) : 34.0;

    bool skipPrimaryToWater = false;
    if (!orbited && tWater > 0.0 && tWater < 21.5) {
        vec3 wpCheck = ro + rd * tWater;
        if (wpCheck.z > -22.5 && abs(wpCheck.x - cavernCenterX(wpCheck.z)) < 0.96) {
            skipPrimaryToWater = true;
        }
    }

    vec3 hit = vec3(-1.0, -1.0, 2.0);
    float lastT = tMaxPrimary;
    if (!skipPrimaryToWater) {
        hit = cc_marchCavern(ro, rd, 0.10, tMaxPrimary, 58, lastT);
        if (hit.x < 0.0 && tWater > 0.0) hit.z = min(hit.z, 14.0);
    }
    float totalSteps = hit.z;

    if (hit.x > 0.0 && (tWater < 0.0 || hit.x < tWater)) {
        vec3 dbgN;
        vec3 dbgMasks;
        vec3 dbgLight;
        vec3 surfCol = cc_shadeSurface(ro, rd, hit.x, hit.y, pxAngle, false, dbgN, dbgMasks, dbgLight);
#if DEBUG_MODE == 2
        return debugNormal(dbgN);
#elif DEBUG_MODE == 3
        return debugIdColor(floor(hit.y + 0.5));
#elif DEBUG_MODE == 4
        return debugHeat(totalSteps / 58.0);
#elif DEBUG_MODE == 5
        return dbgMasks;
#elif DEBUG_MODE == 6
        return dbgLight;
#endif
        return surfCol + 0.0 * fragCoord.x;
    }

    if (tWater > 0.0 && tWater < 30.0) {
        vec3 wp = ro + rd * tWater;
        float dripMask = 0.0;
        vec3 wn = cc_riverNormal(wp.xz, zCam, tWater, pxAngle, dripMask);

        vec3 reflRd = reflect(rd, wn);
        reflRd.y = max(reflRd.y, 0.012);

        gFastMap = true;
        int reflCap = gInDissolve ? 11 : 22;
        float rt = 0.08;
        float rMat = -1.0;
        int rSteps = 0;
        for (int i = ZERO; i < 24; i++) {
            if (i >= reflCap) break;
            rSteps = i + 1;
            vec2 rh = mapCavern(wp + reflRd * rt);
            if (abs(rh.x) < 0.0040 * rt + 0.0022) {
                rMat = rh.y;
                break;
            }
            rt += rh.x * 1.00;
            if (rt > 28.0) break;
        }
        gFastMap = false;
        totalSteps += float(rSteps);

#if DEBUG_MODE == 2
        return debugNormal(wn);
#elif DEBUG_MODE == 3
        return debugIdColor(0.0);
#elif DEBUG_MODE == 4
        return debugHeat(totalSteps / 70.0);
#endif

        vec3 reflCol = cc_grottoBackdrop(reflRd, wp.z + reflRd.z * rt);
        if (rMat > 0.0) {
            vec3 rN;
            vec3 rM;
            vec3 rL;
            reflCol = cc_shadeSurface(wp, reflRd, rt, rMat, pxAngle * 1.6, true, rN, rM, rL);
        }

        float NoV = max(dot(wn, -rd), 1e-3);
        float F = fresnelDielectric(NoV, 1.0, 1.333);

        float bankDist = abs(wp.x - cavernCenterX(wp.z));
        float bankShade = 1.0 - 0.52 * smoothstep(0.95, 2.25, bankDist);
        float depthEst = mix(1.65, 0.42, smoothstep(1.1, 2.3, bankDist));
        float refrPath = depthEst / max(sqrt(1.0 - 0.56 * (1.0 - NoV * NoV)), 0.35);
        vec3 T = beerTransmittance(vec3(0.68, 0.34, 0.38), refrPath);

        vec3 riverScatter = srgbToLinear(vec3(0.076, 0.110, 0.100)) * bankShade;
        vec3 riverBed     = srgbToLinear(vec3(0.088, 0.108, 0.096)) * bankShade;
        vec3 waterBody    = riverBed * T + riverScatter * (vec3(1.0) - T);

        float reflWeight = clamp(F * 1.14 + 0.12, 0.0, 0.90);
        vec3 waterCol = waterBody * (1.0 - reflWeight) + reflCol * reflWeight;
        // Fresnel-gated cool cave-arch sky glint along expanding concentric circular drip-ring crests!
        waterCol += srgbToLinear(vec3(0.24, 0.29, 0.31)) * dripMask * (0.06 + 0.88 * F);

#if DEBUG_MODE == 5
        return vec3(F, dripMask, bankShade);
#elif DEBUG_MODE == 6
        return vec3(luminance(waterBody), luminance(reflCol * reflWeight), dripMask);
#endif

        vec3 waterFog = srgbToLinear(vec3(0.020, 0.036, 0.042));
        return mix(waterCol, waterFog, distanceFog(tWater, 0.016));
    }

    float endZ = ro.z + rd.z * lastT;
#if DEBUG_MODE == 2
    return vec3(0.0);
#elif DEBUG_MODE == 3
    return debugIdColor(0.0);
#elif DEBUG_MODE == 4
    return debugHeat(totalSteps / 58.0);
#elif DEBUG_MODE == 5
    return vec3(0.0);
#elif DEBUG_MODE == 6
    return cc_grottoBackdrop(rd, endZ);
#endif

    return cc_grottoBackdrop(rd, endZ);
}
