// Gemini Video 2 GLSL (v2) — Five-scene procedural Shadertoy recreation of a 25-second Gemini Omni 1.2 Flash film.
// Built with shader-art-coding from gokayfem/shader-skills (MIT): https://github.com/gokayfem/shader-skills
// Scenes (5s each, 0.75s cross-dissolves including seamless 25s -> 0s loop):
//   I.   Space  (00s-05s) - Ringed banded gas giant, storm vortex & wakes, icy ring debris, cosmic web & sun
//   II.  Forest (05s-10s) - Flared redwood trunks, braided bark, sword ferns, oxalis, mossy logs & sunbeams
//   III. Ocean  (10s-15s) - Stormy deep-teal swells, breaking whitecaps, basalt sea stack, ashlar lighthouse & beam
//   IV.  Desert (15s-20s) - S-curved golden-hour dunes, Y-branching ripples, Entrada sandstone arch, butte & mesas
//   V.   Cavern (20s-25s) - Karst limestone river vault, fluted stalactites, chisel-pointed amethyst/cyan crystals

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

// ---- Material IDs across raymarched scenes ----
// Scene II: Forest
const float MAT_FOREST_GROUND = 10.0;
const float MAT_FOREST_TRUNK  = 11.0;
const float MAT_FOREST_ROOT   = 12.0;
const float MAT_FOREST_FERN   = 13.0;
const float MAT_FOREST_CLOVER = 14.0;
const float MAT_FOREST_LOG    = 15.0;
const float MAT_FOREST_FUNGUS = 16.0;
const float MAT_FOREST_TWIG   = 17.0;

// Scene III: Ocean
const float MAT_OCEAN_ROCK    = 20.0;
const float MAT_OCEAN_TOWER   = 21.0;
const float MAT_OCEAN_TRIM    = 22.0;
const float MAT_OCEAN_LANTERN = 23.0;
const float MAT_OCEAN_DOME    = 24.0;

// Scene IV: Desert
const float MAT_DESERT_SAND      = 30.0;
const float MAT_DESERT_SLICKROCK = 31.0;
const float MAT_DESERT_ARCH      = 32.0;
const float MAT_DESERT_BUTTE     = 33.0;
const float MAT_DESERT_SCRUB     = 34.0;

// Scene V: Cavern
const float MAT_CAVERN_WALL           = 40.0;
const float MAT_CAVERN_STALACTITE     = 41.0;
const float MAT_CAVERN_FLOWSTONE      = 42.0;
const float MAT_CAVERN_CRYSTAL_VIOLET = 43.0;
const float MAT_CAVERN_CRYSTAL_CYAN   = 44.0;
const float MAT_CAVERN_DRUZY          = 45.0;

// ---- Shared cross-part anchor constants ----
const vec3 FOREST_SUN_DIR  = normalize(vec3(0.76, 0.57, -0.31));
const vec3 OCEAN_STACK_POS = vec3(1.55, 0.0, 0.0);
const vec3 DESERT_SUN_DIR  = normalize(vec3(-0.82, 0.29, 0.49));
const vec3 DESERT_ARCH_POS = vec3(5.2, 0.95, -23.5);

// ---- Mutable scene dispatch state for map()/calcNormal()/calcAO() ----
int   gSceneId    = 0;
float gSceneTime  = 0.0;
bool  gFastMap    = false;
bool  gInDissolve = false;

vec2 map(vec3 p);

// Bounded sphere tracer with configurable maxSteps for real-time budget
vec3 marchBounded(vec3 ro, vec3 rd, float tmin, float tmax, float stepScale, int maxSteps) {
    int cap = gInDissolve ? (maxSteps * 2) / 3 : maxSteps;
    float t = tmin;
    for (int i = ZERO; i < 160; i++) {
        if (i >= cap) break;
        vec2 h = map(ro + rd * t);
        if (abs(h.x) < max(0.0009 * t, 0.0004)) return vec3(t, h.y, float(i));
        t += h.x * stepScale;
        if (t > tmax) break;
    }
    return vec3(-1.0, -1.0, float(cap));
}

// Fast soft shadow using coarse LOD map evaluation (gFastMap = true)
float fastShadow(vec3 ro, vec3 rd, float tmin, float tmax, float k) {
    gFastMap = true;
    float res = 1.0;
    float t = tmin;
    for (int i = ZERO; i < 20; i++) {
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

// Interactive mouse camera orbit shared by all five scenes
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
