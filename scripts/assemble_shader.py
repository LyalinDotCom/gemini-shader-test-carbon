#!/usr/bin/env python3
"""Assemble modular shader parts from shaders/parts/*.glsl into shaders/film.glsl
or into a standalone single-scene shader (/tmp/shader_swarm/test_<scene>.glsl) with stubs.

Usage examples:
  # Assemble full shaders/film.glsl from shaders/parts/*.glsl:
  python3 scripts/assemble_shader.py

  # Strict mode (fail if any of the 11 expected part files is missing):
  python3 scripts/assemble_shader.py --strict

  # Assemble standalone scene shader (safe even while other scenes are mid-edit),
  # plus optionally bundle & glslangValidator check in one shot:
  python3 scripts/assemble_shader.py --scene space --bundle /tmp/shader_swarm/test_space.bundled.glsl --check
  python3 scripts/assemble_shader.py --scene forest --bundle /tmp/shader_swarm/test_forest.bundled.glsl --check
  python3 scripts/assemble_shader.py --scene ocean --bundle /tmp/shader_swarm/test_ocean.bundled.glsl --check
  python3 scripts/assemble_shader.py --scene desert --bundle /tmp/shader_swarm/test_desert.bundled.glsl --check
  python3 scripts/assemble_shader.py --scene cavern --bundle /tmp/shader_swarm/test_cavern.bundled.glsl --check
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PARTS_DIR = ROOT / "shaders" / "parts"
DEFAULT_OUT = ROOT / "shaders" / "film.glsl"
GLSL_TOOLS = ROOT / "shader-skills" / "skills" / "shader-art-coding" / "scripts" / "glsl_tools.py"

SCENE_ALIASES = {
    "space": "space", "01": "space", "1": "space",
    "forest": "forest", "02": "forest", "2": "forest",
    "ocean": "ocean", "03": "ocean", "3": "ocean",
    "desert": "desert", "04": "desert", "4": "desert",
    "cavern": "cavern", "05": "cavern", "5": "cavern",
}

EXPECTED_PARTS = [
    ("00_common.glsl", "common"),
    ("01_space.glsl", "space"),
    ("02a_forest_trees.glsl", "forest"),
    ("02b_forest_floor.glsl", "forest"),
    ("03a_ocean_waves.glsl", "ocean"),
    ("03b_ocean_lighthouse.glsl", "ocean"),
    ("04a_desert_dunes.glsl", "desert"),
    ("04b_desert_arch.glsl", "desert"),
    ("05a_cavern_rock.glsl", "cavern"),
    ("05b_cavern_crystals.glsl", "cavern"),
    ("99_main.glsl", "main"),
]

# Minimal stubs when an entire non-target scene is omitted or not yet written
SCENE_STUBS = {
    "space": """// ---- stub: Scene I (Space) ----
vec3 renderSpace(vec2 uv, vec2 fragCoord, float pxAngle) {
    return vec3(0.01) + 0.0 * vec3(uv.x, fragCoord.x, pxAngle);
}
""",
    "forest": """// ---- stub: Scene II (Forest) ----
vec2 mapForest(vec3 p) {
    return vec2(p.y + 2.0, MAT_FOREST_GROUND);
}
vec3 renderForest(vec2 uv, vec2 fragCoord, float pxAngle) {
    return vec3(0.02) + 0.0 * vec3(uv.x, fragCoord.x, pxAngle);
}
""",
    "ocean": """// ---- stub: Scene III (Ocean) ----
vec2 mapOceanIsland(vec3 p) {
    return vec2(length(p - OCEAN_STACK_POS) - 1.0, MAT_OCEAN_ROCK);
}
vec3 renderOcean(vec2 uv, vec2 fragCoord, float pxAngle) {
    return vec3(0.02) + 0.0 * vec3(uv.x, fragCoord.x, pxAngle);
}
""",
    "desert": """// ---- stub: Scene IV (Desert) ----
vec2 mapDesert(vec3 p) {
    return vec2(p.y + 2.0, MAT_DESERT_SAND);
}
vec3 renderDesert(vec2 uv, vec2 fragCoord, float pxAngle) {
    return vec3(0.02) + 0.0 * vec3(uv.x, fragCoord.x, pxAngle);
}
""",
    "cavern": """// ---- stub: Scene V (Cavern) ----
vec2 mapCavern(vec3 p) {
    return vec2(2.5 - length(p.xy), MAT_CAVERN_WALL);
}
vec3 renderCavern(vec2 uv, vec2 fragCoord, float pxAngle) {
    return vec3(0.02) + 0.0 * vec3(uv.x, fragCoord.x, pxAngle);
}
""",
}

# Partner stubs when one half of a two-part scene exists and the other half is not yet created
PARTNER_STUBS = {
    "02a_forest_trees.glsl": """// ---- partner stub: 02a_forest_trees.glsl ----
float forestBaseHeight(vec2 xz) {
    return 0.15 * fbm(xz * 0.30, 2) - 0.09 * exp(-xz.x * xz.x * 0.38);
}
vec2 mapForestTrees(vec3 p, float baseGroundY) {
    float d = length(p.xz - vec2(-1.68, -3.1)) - 0.52 + 0.0 * baseGroundY;
    return vec2(d, MAT_FOREST_TRUNK);
}
void shadeForestTree(float matId, vec3 p, vec3 nIn, float t, out vec3 albedo, out float rough, out vec3 nOut) {
    albedo = srgbToLinear(vec3(0.28, 0.17, 0.09)) + 0.0 * vec3(matId + p.x + t);
    rough = 0.85;
    nOut = nIn;
}
float forestSunVisibility(vec3 p) {
    return clamp(0.55 + 0.45 * sin(p.x * 1.8 + p.z * 0.4), 0.0, 1.0);
}
vec3 forestCanopySky(vec3 ro, vec3 rd, float pxAngle) {
    return srgbToLinear(vec3(0.45, 0.54, 0.34)) + 0.0 * vec3(ro.x + rd.y + pxAngle);
}
""",
    "02b_forest_floor.glsl": """// ---- partner preview stub: 02b_forest_floor.glsl ----
vec2 mapForest(vec3 p) {
    float gh = forestBaseHeight(p.xz);
    vec2 res = vec2((p.y - gh) * 0.75, MAT_FOREST_GROUND);
    vec2 tr = mapForestTrees(p, gh);
    if (tr.x < res.x) res = tr;
    return res;
}
vec3 renderForest(vec2 uv, vec2 fragCoord, float pxAngle) {
    float zCam = -0.35 - 0.52 * gSceneTime;
    float gh = forestBaseHeight(vec2(0.0, zCam));
    vec3 ro = vec3(0.0, gh + 0.78, zCam);
    vec3 ta = vec3(0.05, gh + 0.74, zCam - 5.5);
    applyOrbit(ro, vec3(0.0, 1.0, zCam - 4.8), -0.55);
    mat3 cam = cameraMatrix(ro, ta, 0.0);
    vec3 rd = cameraRay(cam, uv, 1.85);
    vec3 col = forestCanopySky(ro, rd, pxAngle);
    vec3 hit = marchBounded(ro, rd, 0.08, 24.0, 0.85, 80);
    if (hit.x > 0.0) {
        vec3 p = ro + rd * hit.x;
        vec3 n = calcNormal(p, 0.0012 * hit.x);
        vec3 albedo = srgbToLinear(vec3(0.22, 0.28, 0.10));
        float rough = 0.85;
        if (hit.y >= MAT_FOREST_TRUNK - 0.5 && hit.y <= MAT_FOREST_ROOT + 0.5) {
            shadeForestTree(hit.y, p, n, hit.x, albedo, rough, n);
        }
        float vis = forestSunVisibility(p) * fastShadow(p + n * 0.03, FOREST_SUN_DIR, 0.06, 7.5, 10.0);
        col = shadePBR(n, -rd, FOREST_SUN_DIR, albedo, rough, 0.0) * vec3(5.0, 3.9, 2.3) * vis
            + albedo * vec3(0.18, 0.22, 0.12);
    }
    return col + 0.0 * fragCoord.x;
}
""",
    "03a_ocean_waves.glsl": """// ---- partner stub: 03a_ocean_waves.glsl ----
vec3 stormCloudSky(vec3 rd, vec3 lampPos, vec3 beamDir) {
    return mix(srgbToLinear(vec3(0.44, 0.53, 0.57)), srgbToLinear(vec3(0.25, 0.30, 0.33)), clamp(rd.y * 2.0, 0.0, 1.0))
         + 0.0 * (lampPos.x + beamDir.x);
}
float traceStormOcean(vec3 ro, vec3 rd) {
    return (rd.y < -0.001) ? (-ro.y / rd.y) : -1.0;
}
vec3 shadeStormOcean(vec3 ro, vec3 rd, float t, float pxAngle, vec3 lampPos, vec3 beamDir) {
    return srgbToLinear(vec3(0.08, 0.24, 0.28)) + 0.0 * (ro.x + rd.x + t + pxAngle + lampPos.x + beamDir.x);
}
vec4 ow_islandSprayPlume(vec3 ro, vec3 rd, float tMax) {
    return vec4(0.0) + 0.0 * vec4(ro.x, rd.x, tMax, 0.0);
}
""",
    "03b_ocean_lighthouse.glsl": """// ---- partner preview stub: 03b_ocean_lighthouse.glsl ----
vec2 mapOceanIsland(vec3 p) {
    return vec2(length(p - (OCEAN_STACK_POS + vec3(0.0, 3.0, 0.0))) - 3.2, MAT_OCEAN_ROCK);
}
vec3 renderOcean(vec2 uv, vec2 fragCoord, float pxAngle) {
    float u = gSceneTime;
    float zCam = 34.5 - 2.35 * u;
    float yCam = 4.65 - 0.08 * u;
    vec3 ro = vec3(-0.15, yCam, zCam);
    vec3 ta = vec3(-0.10, yCam - 0.595, zCam - 10.0);
    applyOrbit(ro, OCEAN_STACK_POS + vec3(0.0, 5.2, 0.0), -3.5);
    mat3 cam = cameraMatrix(ro, ta, 0.0);
    vec3 rd = cameraRay(cam, uv, 2.0);
    vec3 lampPos = OCEAN_STACK_POS + vec3(0.15, 10.95, 0.0);
    float beamAngle = 0.08 + 0.88 * (u - 0.75);
    vec3 beamDir = normalize(vec3(cos(beamAngle), 0.22 * sin(beamAngle), sin(beamAngle)));
    vec3 col = stormCloudSky(rd, lampPos, beamDir);
    float tOcean = traceStormOcean(ro, rd);
    if (tOcean > 0.0) {
        col = shadeStormOcean(ro, rd, tOcean, pxAngle, lampPos, beamDir);
    }
    return col + 0.0 * fragCoord.x;
}
""",
    "04a_desert_dunes.glsl": """// ---- partner stub: 04a_desert_dunes.glsl ----
float desertDuneHeight(vec2 xz) {
    return 0.022 * (-xz.y) + 0.35 * sin(xz.x * 0.45 + sin(xz.y * 0.14));
}
vec2 mapDesertFloorExtras(vec3 p, float duneH) {
    return vec2(1e5 + 0.0 * (p.x + duneH), MAT_DESERT_SLICKROCK);
}
void shadeDesertSand(vec3 p, vec3 nIn, float t, float pxAngle, out vec3 albedo, out float rough, out vec3 nOut) {
    albedo = srgbToLinear(vec3(0.79, 0.47, 0.24)) + 0.0 * vec3(p.x + t + pxAngle);
    rough = 0.78;
    nOut = nIn;
}
vec3 desertAtmosphere(vec3 rd) {
    return mix(srgbToLinear(vec3(0.80, 0.78, 0.72)), srgbToLinear(vec3(0.16, 0.40, 0.63)), clamp(rd.y * 2.2, 0.0, 1.0));
}
""",
    "04b_desert_arch.glsl": """// ---- partner preview stub: 04b_desert_arch.glsl ----
vec2 mapDesert(vec3 p) {
    float dh = desertDuneHeight(p.xz);
    vec2 res = vec2((p.y - dh) * 0.55, MAT_DESERT_SAND);
    vec2 ex = mapDesertFloorExtras(p, dh);
    if (ex.x < res.x) res = ex;
    return res;
}
vec3 renderDesert(vec2 uv, vec2 fragCoord, float pxAngle) {
    float u = gSceneTime;
    float zCam = -1.2 - 1.45 * u;
    float xCam = -0.35 + 0.16 * u;
    float baseH = desertDuneHeight(vec2(xCam, zCam));
    vec3 ro = vec3(xCam, baseH + 1.44, zCam);
    vec3 ta = vec3(xCam + 0.72, baseH + 2.69, zCam - 10.0);
    applyOrbit(ro, DESERT_ARCH_POS + vec3(-1.0, 3.4, 4.0), -2.2);
    mat3 cam = cameraMatrix(ro, ta, 0.0);
    vec3 rd = cameraRay(cam, uv, 1.95);
    vec3 sky = desertAtmosphere(rd);
    vec3 hit = marchBounded(ro, rd, 0.12, 140.0, 0.75, 108);
    if (hit.x < 0.0) return sky;
    vec3 p = ro + rd * hit.x;
    vec3 n = calcNormal(p, max(0.0014 * hit.x, 0.002));
    vec3 albedo = srgbToLinear(vec3(0.65, 0.36, 0.20));
    float rough = 0.82;
    if (abs(hit.y - MAT_DESERT_SAND) < 0.5) {
        shadeDesertSand(p, n, hit.x, pxAngle, albedo, rough, n);
    }
    float sha = (hit.x < 48.0) ? fastShadow(p + n * 0.04, DESERT_SUN_DIR, 0.08, 28.0, 18.0) : 1.0;
    return (shadePBR(n, -rd, DESERT_SUN_DIR, albedo, rough, 0.0) * vec3(2.6, 1.98, 1.44) * sha
          + albedo * srgbToLinear(vec3(0.35, 0.44, 0.58)) * 0.85) + 0.0 * fragCoord.x;
}
""",
    "05a_cavern_rock.glsl": """// ---- partner stub: 05a_cavern_rock.glsl ----
float cavernCenterX(float z) {
    return -0.28 * sin(z * 0.09 + 0.3) - 0.14;
}
float cr_cavernWallX(float y, float z, float sideSign) {
    return cavernCenterX(z) + sideSign * 2.25 + 0.0 * y;
}
vec2 mapCavernRock(vec3 p) {
    vec2 lc = vec2((p.x - cavernCenterX(p.z)) / 2.68, (p.y - 0.68) / 2.15);
    return vec2((1.0 - length(lc)) * 1.5, MAT_CAVERN_WALL);
}
void shadeCavernRock(float matId, vec3 p, vec3 nIn, float t, bool isRefl, out vec3 albedo, out float rough, out vec3 nOut) {
    albedo = srgbToLinear(vec3(0.16, 0.17, 0.19)) + 0.0 * vec3(matId + p.x + t + (isRefl ? 1.0 : 0.0));
    rough = 0.42;
    nOut = nIn;
}
""",
    "05b_cavern_crystals.glsl": """// ---- partner preview stub: 05b_cavern_crystals.glsl ----
vec2 mapCavern(vec3 p) {
    return mapCavernRock(p);
}
vec3 renderCavern(vec2 uv, vec2 fragCoord, float pxAngle) {
    float zCam = -0.8 - 0.72 * gSceneTime;
    float xCam = cavernCenterX(zCam);
    vec3 ro = vec3(xCam, 0.44, zCam);
    vec3 ta = vec3(cavernCenterX(zCam - 6.5) - 0.10, 0.34, zCam - 6.5);
    applyOrbit(ro, vec3(cavernCenterX(zCam - 5.0), 0.72, zCam - 5.0), -0.60);
    mat3 cam = cameraMatrix(ro, ta, 0.0);
    vec3 rd = cameraRay(cam, uv, 1.85);
    vec3 hit = marchBounded(ro, rd, 0.08, 28.0, 0.80, 80);
    if (hit.x < 0.0) return srgbToLinear(vec3(0.03, 0.16, 0.20));
    vec3 p = ro + rd * hit.x;
    vec3 n = calcNormal(p, 0.0016 * hit.x);
    vec3 albedo; float rough; vec3 nOut;
    shadeCavernRock(hit.y, p, n, hit.x, false, albedo, rough, nOut);
    return shadePBR(nOut, -rd, normalize(vec3(0.0, 0.2, 1.0)), albedo, rough, 0.0) * vec3(1.2)
         + albedo * vec3(0.22, 0.25, 0.28) + 0.0 * (fragCoord.x + pxAngle);
}
""",
}


def parse_overrides(items: list[str]) -> dict[str, Path]:
    out: dict[str, Path] = {}
    for raw in items:
        if "=" not in raw:
            raise SystemExit(f"--override expects PART_FILENAME=/path/to/file.glsl, got: {raw}")
        k, v = raw.split("=", 1)
        p = Path(v).expanduser().resolve()
        if not p.is_file():
            raise SystemExit(f"Override file does not exist: {p}")
        out[Path(k).name] = p
    return out


def read_part(filename: str, overrides: dict[str, Path]) -> str | None:
    if filename in overrides:
        return overrides[filename].read_text(encoding="utf-8")
    p = PARTS_DIR / filename
    if p.is_file():
        return p.read_text(encoding="utf-8")
    return None


def assemble(target_scene: str | None, strict: bool, overrides: dict[str, Path], only_part: str | None) -> tuple[str, list[str]]:
    common_src = read_part("00_common.glsl", overrides)
    main_src = read_part("99_main.glsl", overrides)
    if common_src is None or main_src is None:
        raise SystemExit("Missing shaders/parts/00_common.glsl or shaders/parts/99_main.glsl")

    chunks: list[str] = [common_src.rstrip()]
    notes: list[str] = []

    scenes_order = [
        ("space", ["01_space.glsl"]),
        ("forest", ["02a_forest_trees.glsl", "02b_forest_floor.glsl"]),
        ("ocean", ["03a_ocean_waves.glsl", "03b_ocean_lighthouse.glsl"]),
        ("desert", ["04a_desert_dunes.glsl", "04b_desert_arch.glsl"]),
        ("cavern", ["05a_cavern_rock.glsl", "05b_cavern_crystals.glsl"]),
    ]

    # Pick up any extra custom part files in shaders/parts/ if full assembly (sorted order)
    known_names = {name for name, _ in EXPECTED_PARTS}
    extra_parts = sorted(
        p for p in PARTS_DIR.glob("*.glsl")
        if p.name not in known_names
    ) if target_scene is None else []
    if extra_parts:
        notes.append(f"extra parts included: {[p.name for p in extra_parts]}")

    for scene_name, part_files in scenes_order:
        if target_scene is not None and scene_name != target_scene:
            chunks.append(SCENE_STUBS[scene_name].rstrip())
            continue

        present = {}
        for pf in part_files:
            if only_part and pf != only_part and not pf.startswith(only_part):
                present[pf] = None
            else:
                present[pf] = read_part(pf, overrides)

        if all(v is None for v in present.values()):
            if strict:
                raise SystemExit(f"ERROR (--strict): missing scene parts for '{scene_name}': {part_files}")
            notes.append(f"stubbed missing scene '{scene_name}'")
            chunks.append(SCENE_STUBS[scene_name].rstrip())
            continue

        for pf in part_files:
            src = present[pf]
            if src is not None:
                chunks.append(f"// ==== PART: {pf} ====\n" + src.rstrip())
            else:
                if strict:
                    raise SystemExit(f"ERROR (--strict): missing part file '{pf}'")
                notes.append(f"stubbed partner part '{pf}'")
                chunks.append(PARTNER_STUBS[pf].rstrip())

    for ep in extra_parts:
        chunks.append(f"// ==== PART: {ep.name} ====\n" + ep.read_text(encoding="utf-8").rstrip())

    chunks.append("// ==== PART: 99_main.glsl ====\n" + main_src.rstrip())
    return "\n\n".join(chunks) + "\n", notes


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-o", "--output", type=Path, default=None, help="Output unbundled GLSL path")
    ap.add_argument("--scene", type=str, default=None, help="Assemble standalone scene: space|forest|ocean|desert|cavern")
    ap.add_argument("--only-part", type=str, default=None, help="Within --scene, test only one sub-part (e.g. 02a) using partner stub")
    ap.add_argument("--override", action="append", default=[], help="Override a part file: PART.glsl=/path/to/draft.glsl")
    ap.add_argument("--strict", action="store_true", help="Fail if any expected part file in shaders/parts/ is missing")
    ap.add_argument("--bundle", nargs="?", const="AUTO", default=None, help="Also run glsl_tools.py bundle (optional output path)")
    ap.add_argument("--check", action="store_true", help="Also run glsl_tools.py check on assembled (and bundled) output")
    args = ap.parse_args()

    target_scene = None
    if args.scene is not None:
        key = args.scene.strip().lower()
        if key not in SCENE_ALIASES:
            raise SystemExit(f"Unknown --scene '{args.scene}'. Choose from: space, forest, ocean, desert, cavern")
        target_scene = SCENE_ALIASES[key]

    out_path = args.output
    if out_path is None:
        if target_scene is not None:
            out_path = Path(f"/tmp/shader_swarm/test_{target_scene}.glsl")
        else:
            out_path = DEFAULT_OUT

    overrides = parse_overrides(args.override)
    assembled, notes = assemble(target_scene, args.strict, overrides, args.only_part)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(assembled, encoding="utf-8")

    note_str = f" ({'; '.join(notes)})" if notes else ""
    print(f"[assemble_shader] wrote {out_path} ({assembled.count(chr(10))} lines){note_str}")

    bundled_path: Path | None = None
    if args.bundle is not None:
        if args.bundle == "AUTO":
            bundled_path = out_path.with_suffix(".bundled.glsl") if target_scene else (ROOT / "public" / "shader.glsl")
        else:
            bundled_path = Path(args.bundle)
        bundled_path.parent.mkdir(parents=True, exist_ok=True)
        cmd = [sys.executable, str(GLSL_TOOLS), "bundle", str(out_path), "-o", str(bundled_path)]
        res = subprocess.run(cmd, capture_output=True, text=True)
        if res.returncode != 0:
            sys.stderr.write(res.stdout + res.stderr)
            raise SystemExit(res.returncode)
        print(f"[assemble_shader] bundled -> {bundled_path}")

    if args.check:
        targets = [str(out_path)] + ([str(bundled_path)] if bundled_path else [])
        cmd = [sys.executable, str(GLSL_TOOLS), "check", *targets]
        res = subprocess.run(cmd, capture_output=True, text=True)
        sys.stdout.write(res.stdout)
        sys.stderr.write(res.stderr)
        if res.returncode != 0:
            raise SystemExit(res.returncode)


if __name__ == "__main__":
    main()
