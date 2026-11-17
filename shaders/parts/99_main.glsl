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
        hdr = renderSpace(uv, fragCoord, pxAngle);
        exposure = SPACE_EXPOSURE;
    } else if (sceneId == 1) {
        hdr = renderForest(uv, fragCoord, pxAngle);
        exposure = FOREST_EXPOSURE;
    } else if (sceneId == 2) {
        hdr = renderOcean(uv, fragCoord, pxAngle);
        exposure = OCEAN_EXPOSURE;
    } else if (sceneId == 3) {
        hdr = renderDesert(uv, fragCoord, pxAngle);
        exposure = DESERT_EXPOSURE;
    } else {
        hdr = renderCavern(uv, fragCoord, pxAngle);
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

    float alpha = clamp((inSlot - dissolveStart) / DISSOLVE_TIME, 0.0, 1.0);
    vec3 colOut = vec3(0.0);
    for (int pass = ZERO; pass < 2; pass++) {
        if (pass == 1 && !gInDissolve) break;
        int sc = (pass == 0) ? slot : ((slot + 1) % 5);
        float uLocal = (pass == 0) ? (inSlot + DISSOLVE_TIME) : (inSlot - dissolveStart);
        vec3 c = renderScene(sc, uLocal, fragCoord);
#if DEBUG_MODE == 0
        c = linearToSrgb(c);
#endif
        colOut = (pass == 0) ? c : mix(colOut, c, alpha);
    }
    return colOut;
}

vec2 map(vec3 p) {
    // Scenes II, IV, and V use scene-local march/normal/shadow/AO; only Scene III calls global map(p).
    if (gSceneId == 2) return mapOceanIsland(p);
    return vec2(length(p) - 1.0, 0.0);
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
// DEBUG_MODE (0..6) / AA (1..4): inspect distance slices, normals, material IDs, raymarch step heat, masks, lighting, or supersample.
// FILM_DURATION / SCENE_DURATION / DISSOLVE_TIME: timeline sync with public/film.mp4 (25.0s loop, 5.0s scenes, 0.75s dissolves).
// ORBIT_YAW_RANGE / ORBIT_PITCH_MAX: sensitivity and elevation bounds of iMouse camera orbit across all 5 scenes.
// SPACE_EXPOSURE..CAVERN_EXPOSURE: per-scene linear exposure prior to AgX tonemapping.
// FOREST_SUN_DIR / OCEAN_STACK_POS / DESERT_SUN_DIR / DESERT_ARCH_POS: cross-module hero placement and directional key lights.
