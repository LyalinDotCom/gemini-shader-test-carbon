# Video 2 GLSL

Generate a short five-scene film with the Gemini video model, then recreate the whole film as one procedural GLSL fragment shader, and build a small web page that plays the two side by side.

Work in an empty folder. This run is unattended: do not ask questions or wait for approval. Make the call yourself and note it in the README.

You need Node, Python 3, `ffmpeg`, `glslangValidator`, Chrome, and an authenticated `gemini-api` CLI.

## 1. Make the film

Generate one clip per scene with `gemini-api video` (see `gemini-api video --help`), 16:9 at 720p. Use the descriptions below as the prompts, and add to each: one continuous shot, slow steady camera, no cuts, no people, no text.

| Scene | Label | Description |
| :--- | :--- | :--- |
| I | Space | A slow orbital glide past a huge banded gas giant with wide icy rings. The planet's shadow falls across the rings. A small bright sun, a faint violet nebula and a dense starfield sit behind it. |
| II | Forest | A low, slow forward glide through an ancient redwood forest in golden morning light. Massive trunks, ferns and moss on the floor, pale mist, and strong diagonal sunbeams between the trunks. |
| III | Ocean | A low aerial pass over a rolling deep-teal open ocean under heavy storm clouds. Whitecaps break on the swells. A dark rock sea stack carries a stone lighthouse with a warm glowing lamp. |
| IV | Desert | A golden-hour glide over rippled orange dunes toward a huge red sandstone natural arch. Layered mesas fade into warm haze under a deep blue sky. |
| V | Cavern | A slow glide at water level down a dark, still underground river in a limestone cavern. Stalactites hang overhead. Glowing cyan and violet crystals on the walls are reflected in the water. |

The clips come back longer than you need. Cut them into one 25-second film: 5 seconds per scene, in order, with a short cross-dissolve between scenes and from the last scene back into the first, so the film loops. Keep the five source clips; the page shows them too.

## 2. Get the skill

Clone [gokayfem/shader-skills](https://github.com/gokayfem/shader-skills) (MIT) into `shader-skills/`. Read `shader-skills/skills/shader-art-coding/SKILL.md` and follow its workflow, conventions and hard rules for everything in step 3. Build from its library and bundle with its tools. Starting from its templates is fine.

## 3. Write the shader

Recreate the entire 25-second film as a single Shadertoy shader.

- **The video is the reference.** Take each scene's content, framing, camera move, colours, light and motion from the frames of your film, not from the descriptions above. Extract frames and compare them with your renders as you go.
- **One pass, Shadertoy form.** `mainImage`, standard Shadertoy uniforms only, so the bundled file pastes into Shadertoy with no channels.
- **Procedural only.** No textures, no video frames, no baked image data. Everything is computed.
- **Same timeline as the film.** 25 seconds, 5 per scene, the same dissolves, and no visible jump when it loops.
- **Mouse orbit.** Dragging on the shader orbits the camera around the scene, in every scene.
- **Clean.** The bundled shader passes the skill's `check` with `glslangValidator` installed, with no errors or warnings.
- **Real time.** Aim for at least 30 fps at 1280×720. Looks come before speed: reach 30, then spend the rest on detail and motion.

## 4. Build the page

A calm, minimal page whose only job is to compare the film with the live shader. Top to bottom:

1. **Header.** The title `Gemini Video 2 GLSL`, and the credit line from step 5.
2. **Stage.** The film and the live shader, both 16:9, with two modes: **Side-by-Side** (film left, shader right) and **Wipe** (both stacked, with a divider you drag across).
3. **Transport bar** under the stage: a scrubber, a Play/Pause button, a timecode, and a button for each of the five scenes with the current one highlighted.
4. **Original Videos.** The five source clips in a row with their labels. Clicking one jumps the stage to that scene.

The shader's time is locked to the film's time, so both panes always show the same moment through play, pause, scrubbing and scene jumps. Dragging the shader orbits its camera, and a reset control appears once it has been dragged.

The look is dark and quiet: a near-black background, warm off-white text, and one amber accent for whatever is active. Use Instrument Sans for text and JetBrains Mono for labels, buttons and the timecode. Leave everything else off the page: no FPS counters, code viewers, debug menus or marketing copy.

Serve it with a small Node server that has no dependencies, started by `npm start`. Video seeking must work, so the server has to support byte-range requests.

## 5. Credit the skill

Credit `gokayfem/shader-skills` in three places, and keep its `LICENSE` and `CREDITS.md` in the cloned folder:

- **Page header:** `Built with Gemini models and tools with the help of shader-art-coding (gokayfem/shader-skills)`, linked to the repository.
- **Shader:** the repository URL in the header comment of the source and the bundled file.
- **README:** a line saying what the skill provided, and which of its templates and library modules you used.

## 6. Check your work and report

Before you finish, look at the result the way a viewer would: load the page in Chrome, play the whole loop in both modes, try every control, and compare film and shader frame by frame in every scene. Fix what is wrong and look again.

Then write a short `README.md` with:

1. How to run it.
2. One still per scene showing a film frame next to the shader frame at the same time.
3. For each scene, what matches the film, what does not, and what you simplified.
4. The frame rate you measured, at what resolution, and on which GPU. Measure it on the same settings the stills were rendered with.
5. Whether `check` ran with `glslangValidator`, and its result.
6. Anything that does not work or that you could not check. Say so plainly rather than leaving it out.

## Layout

```text
README.md
package.json            npm start, plus scripts to bundle and check the shader
server.mjs
shaders/                the shader source you write
public/                 the page, the bundled shader, the 25-second film
raw_clips/              the five source clips
shader-skills/          the cloned skill
```
