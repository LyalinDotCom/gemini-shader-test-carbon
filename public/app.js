const FILM_DURATION = 25.0;
const CANVAS_W = 1280;
const CANVAS_H = 720;

const SHADERTOY_PRELUDE = `#version 300 es
precision highp float;
precision highp int;
precision mediump sampler3D;
uniform vec3 iResolution;
uniform float iTime;
uniform float iTimeDelta;
uniform float iFrameRate;
uniform int iFrame;
uniform vec4 iMouse;
uniform vec4 iDate;
uniform float iChannelTime[4];
uniform vec3 iChannelResolution[4];
uniform sampler2D iChannel0;
uniform sampler2D iChannel1;
uniform sampler2D iChannel2;
uniform sampler2D iChannel3;
out vec4 st_FragColor;
`;

const SHADERTOY_EPILOGUE = `
void main() {
    mainImage(st_FragColor, gl_FragCoord.xy);
    st_FragColor.a = 1.0;
}
`;

const VERTEX_SRC = `#version 300 es
void main() {
    vec2 p = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
    gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
}
`;

const filmVideo = document.getElementById('film-video');
const shaderCanvas = document.getElementById('shader-canvas');
const shaderLoading = document.getElementById('shader-loading');
const shaderLoadingStage = document.getElementById('shader-loading-stage');
const shaderLoadingBar = document.getElementById('shader-loading-bar');
const shaderLoadingTime = document.getElementById('shader-loading-time');
const stageViewport = document.getElementById('stage-viewport');
const modeSbsBtn = document.getElementById('mode-sbs-btn');
const modeWipeBtn = document.getElementById('mode-wipe-btn');
const resetOrbitBtn = document.getElementById('reset-orbit-btn');
const wipeDivider = document.getElementById('wipe-divider');
const playPauseBtn = document.getElementById('play-pause-btn');
const playPauseLabel = document.getElementById('play-pause-label');
const iconPlay = document.getElementById('icon-play');
const iconPause = document.getElementById('icon-pause');
const scrubber = document.getElementById('scrubber');
const timecode = document.getElementById('timecode');
const sceneBtns = Array.from(document.querySelectorAll('.scene-btn'));
const clipCards = Array.from(document.querySelectorAll('.clip-card'));

let viewMode = 'sbs'; // 'sbs' | 'wipe'
let wipePercent = 50;
let isScrubbing = false;

// Orbit state mapped cleanly onto standard Shadertoy iMouse
let hasOrbited = false;
let orbitOffsetX = 0; // pixels around center (CANVAS_W * 0.5)
let orbitOffsetY = 0; // pixels around center (CANVAS_H * 0.5)
let isDraggingOrbit = false;
let dragStartClientX = 0;
let dragStartClientY = 0;
let dragBaseOffsetX = 0;
let dragBaseOffsetY = 0;

// WebGL2 & async compilation state
let gl = null;
let program = null;
let vao = null;
let uniforms = {};
let shaderReady = false;
let isCompiling = true;
let compileStageFloor = 0.08;
const compileStartPerf = performance.now();
let frameIndex = 0;
let lastWallTime = performance.now();
let smoothedFps = 60.0;

function formatTime(sec) {
  const clamped = Math.max(0, Math.min(FILM_DURATION, sec));
  const mins = Math.floor(clamped / 60);
  const rem = clamped - mins * 60;
  const whole = Math.floor(rem);
  const tenths = Math.floor((rem - whole + 1e-6) * 10);
  return `${String(mins).padStart(2, '0')}:${String(whole).padStart(2, '0')}.${Math.min(tenths, 9)}`;
}

function updateTransportUI(currentSec) {
  const t = ((currentSec % FILM_DURATION) + FILM_DURATION) % FILM_DURATION;
  if (!isScrubbing) {
    scrubber.value = t.toFixed(3);
  }
  const pct = (t / FILM_DURATION) * 100;
  scrubber.style.setProperty('--progress-pct', `${pct.toFixed(3)}%`);
  timecode.textContent = `${formatTime(t)} / 00:25.0`;

  const activeScene = Math.min(4, Math.floor(t / 5.0));
  for (const btn of sceneBtns) {
    btn.classList.toggle('is-active', Number(btn.dataset.scene) === activeScene);
  }
  for (const card of clipCards) {
    card.classList.toggle('is-active', Number(card.dataset.scene) === activeScene);
  }
}

function syncPlayButtonState() {
  const playing = !filmVideo.paused && !filmVideo.ended;
  playPauseBtn.classList.toggle('is-playing', playing);
  playPauseLabel.textContent = playing ? 'Pause' : 'Play';
  iconPlay.hidden = playing;
  iconPause.hidden = !playing;
}

async function togglePlay() {
  if (filmVideo.paused || filmVideo.ended) {
    try {
      await filmVideo.play();
    } catch {
      filmVideo.muted = true;
      await filmVideo.play();
    }
  } else {
    filmVideo.pause();
  }
  syncPlayButtonState();
}

function seekTo(sec) {
  const target = Math.max(0, Math.min(FILM_DURATION - 0.001, sec));
  filmVideo.currentTime = target;
  updateTransportUI(target);
  renderShaderFrame(target, 1 / 60);
}

// Mode switching
function setViewMode(mode) {
  viewMode = mode;
  const isWipe = mode === 'wipe';
  stageViewport.classList.toggle('is-sbs', !isWipe);
  stageViewport.classList.toggle('is-wipe', isWipe);
  modeSbsBtn.classList.toggle('is-active', !isWipe);
  modeWipeBtn.classList.toggle('is-active', isWipe);
  modeSbsBtn.setAttribute('aria-pressed', String(!isWipe));
  modeWipeBtn.setAttribute('aria-pressed', String(isWipe));
}

function setWipePercent(pct) {
  wipePercent = Math.max(0, Math.min(100, pct));
  stageViewport.style.setProperty('--wipe-pct', `${wipePercent.toFixed(2)}%`);
  wipeDivider.setAttribute('aria-valuenow', String(Math.round(wipePercent)));
}

modeSbsBtn.addEventListener('click', () => setViewMode('sbs'));
modeWipeBtn.addEventListener('click', () => setViewMode('wipe'));

// Wipe divider drag & keyboard
let isDraggingWipe = false;
wipeDivider.addEventListener('pointerdown', (e) => {
  e.stopPropagation();
  e.preventDefault();
  isDraggingWipe = true;
  wipeDivider.classList.add('is-dragging');
  wipeDivider.setPointerCapture(e.pointerId);
});

wipeDivider.addEventListener('pointermove', (e) => {
  if (!isDraggingWipe) return;
  const rect = stageViewport.getBoundingClientRect();
  if (rect.width <= 0) return;
  const pct = ((e.clientX - rect.left) / rect.width) * 100;
  setWipePercent(pct);
});

function endWipeDrag(e) {
  if (!isDraggingWipe) return;
  isDraggingWipe = false;
  wipeDivider.classList.remove('is-dragging');
  if (e && wipeDivider.hasPointerCapture?.(e.pointerId)) {
    wipeDivider.releasePointerCapture(e.pointerId);
  }
}
wipeDivider.addEventListener('pointerup', endWipeDrag);
wipeDivider.addEventListener('pointercancel', endWipeDrag);

wipeDivider.addEventListener('keydown', (e) => {
  if (e.key === 'ArrowLeft') {
    e.preventDefault();
    setWipePercent(wipePercent - 2);
  } else if (e.key === 'ArrowRight') {
    e.preventDefault();
    setWipePercent(wipePercent + 2);
  }
});

// Mouse Orbit (works on shader canvas in Side-by-Side AND anywhere off divider in Wipe)
function beginOrbitDrag(e, captureEl) {
  if (e.button !== undefined && e.button !== 0) return;
  if (isDraggingWipe || e.target.closest('#wipe-divider')) return;
  e.preventDefault();
  isDraggingOrbit = true;
  dragStartClientX = e.clientX;
  dragStartClientY = e.clientY;
  dragBaseOffsetX = orbitOffsetX;
  dragBaseOffsetY = orbitOffsetY;
  shaderCanvas.classList.add('is-dragging');
  stageViewport.classList.add('is-orbiting');
  captureEl.setPointerCapture(e.pointerId);
}

function moveOrbitDrag(e, referenceEl) {
  if (!isDraggingOrbit) return;
  const rect = referenceEl.getBoundingClientRect();
  if (rect.width <= 0 || rect.height <= 0) return;
  const dx = e.clientX - dragStartClientX;
  const dy = e.clientY - dragStartClientY;
  if (Math.hypot(dx, dy) > 1.5 && !hasOrbited) {
    hasOrbited = true;
    resetOrbitBtn.hidden = false;
  }
  const scaleX = CANVAS_W / rect.width;
  const scaleY = CANVAS_H / rect.height;
  orbitOffsetX = dragBaseOffsetX + dx * scaleX;
  orbitOffsetY = Math.max(-CANVAS_H * 0.48, Math.min(CANVAS_H * 0.48, dragBaseOffsetY - dy * scaleY));
  if (filmVideo.paused) {
    renderShaderFrame(filmVideo.currentTime || 0, 1 / 60);
  }
}

function endOrbitDrag(e, captureEl) {
  if (!isDraggingOrbit) return;
  isDraggingOrbit = false;
  shaderCanvas.classList.remove('is-dragging');
  stageViewport.classList.remove('is-orbiting');
  if (e && captureEl.hasPointerCapture?.(e.pointerId)) {
    captureEl.releasePointerCapture(e.pointerId);
  }
  if (filmVideo.paused) {
    renderShaderFrame(filmVideo.currentTime || 0, 1 / 60);
  }
}

shaderCanvas.addEventListener('pointerdown', (e) => {
  if (viewMode === 'sbs') beginOrbitDrag(e, shaderCanvas);
});
shaderCanvas.addEventListener('pointermove', (e) => {
  if (viewMode === 'sbs') moveOrbitDrag(e, shaderCanvas);
});
shaderCanvas.addEventListener('pointerup', (e) => {
  if (viewMode === 'sbs') endOrbitDrag(e, shaderCanvas);
});
shaderCanvas.addEventListener('pointercancel', (e) => {
  if (viewMode === 'sbs') endOrbitDrag(e, shaderCanvas);
});

stageViewport.addEventListener('pointerdown', (e) => {
  if (viewMode === 'wipe') beginOrbitDrag(e, stageViewport);
});
stageViewport.addEventListener('pointermove', (e) => {
  if (viewMode === 'wipe') moveOrbitDrag(e, stageViewport);
});
stageViewport.addEventListener('pointerup', (e) => {
  if (viewMode === 'wipe') endOrbitDrag(e, stageViewport);
});
stageViewport.addEventListener('pointercancel', (e) => {
  if (viewMode === 'wipe') endOrbitDrag(e, stageViewport);
});

resetOrbitBtn.addEventListener('click', () => {
  hasOrbited = false;
  orbitOffsetX = 0;
  orbitOffsetY = 0;
  resetOrbitBtn.hidden = true;
  renderShaderFrame(filmVideo.currentTime || 0, 1 / 60);
});

// Transport events
playPauseBtn.addEventListener('click', togglePlay);
filmVideo.addEventListener('play', syncPlayButtonState);
filmVideo.addEventListener('pause', syncPlayButtonState);

scrubber.addEventListener('pointerdown', () => {
  isScrubbing = true;
});
scrubber.addEventListener('input', () => {
  const val = Number(scrubber.value);
  filmVideo.currentTime = Math.min(FILM_DURATION - 0.001, val);
  const pct = (val / FILM_DURATION) * 100;
  scrubber.style.setProperty('--progress-pct', `${pct.toFixed(3)}%`);
  timecode.textContent = `${formatTime(val)} / 00:25.0`;
  renderShaderFrame(val, 1 / 60);
});
window.addEventListener('pointerup', () => {
  if (isScrubbing) {
    isScrubbing = false;
    updateTransportUI(filmVideo.currentTime || 0);
  }
});

for (const btn of sceneBtns) {
  btn.addEventListener('click', () => {
    seekTo(Number(btn.dataset.time));
  });
}

for (const card of clipCards) {
  const previewVid = card.querySelector('video');
  if (previewVid) {
    previewVid.addEventListener('loadedmetadata', () => {
      previewVid.currentTime = 1.2;
    }, { once: true });
    card.addEventListener('pointerenter', () => {
      previewVid.play().catch(() => {});
    });
    card.addEventListener('pointerleave', () => {
      previewVid.pause();
    });
  }
  card.addEventListener('click', () => {
    seekTo(Number(card.dataset.time));
  });
}

window.addEventListener('keydown', (e) => {
  if (e.target.matches('input, button, a, [role="slider"]')) {
    if (e.code !== 'Space') return;
  }
  if (e.code === 'Space' && document.activeElement !== playPauseBtn) {
    e.preventDefault();
    togglePlay();
  }
});

// Async non-blocking WebGL2 initialization & Shadertoy uniform feed
const nextFrame = () => new Promise((resolve) => requestAnimationFrame(resolve));
const yieldTwoFrames = () =>
  new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));

function setLoadingStage(label, floorPct) {
  if (shaderLoadingStage) {
    shaderLoadingStage.textContent = label;
  }
  if (typeof floorPct === 'number') {
    compileStageFloor = Math.max(compileStageFloor, floorPct);
  }
}

function tickLoadingOverlay(now) {
  if (!isCompiling) return;
  const elapsedSec = Math.max(0, (now - compileStartPerf) * 0.001);
  if (shaderLoadingTime) {
    shaderLoadingTime.textContent = `${elapsedSec.toFixed(1)}s`;
  }
  if (shaderLoadingBar) {
    const asym = 1 - Math.exp(-elapsedSec / 3.4);
    const pct = Math.max(compileStageFloor, Math.min(0.95, 0.08 + asym * 0.84));
    shaderLoadingBar.style.transform = `scaleX(${pct.toFixed(4)})`;
  }
  requestAnimationFrame(tickLoadingOverlay);
}

window.__shaderStudio = {
  ready: false,
  compiling: true,
  seekTo,
  setViewMode,
  setWipePercent,
};

requestAnimationFrame(tickLoadingOverlay);

async function initShader() {
  setLoadingStage('Fetching procedural GLSL…', 0.08);
  const shaderFetchPromise = fetch('/shader.glsl', { cache: 'no-cache' });

  // Guarantee the entire page shell, videos, badges, and loading overlay paint first (<50ms)
  await yieldTwoFrames();

  const res = await shaderFetchPromise;
  if (!res.ok) {
    throw new Error(`Failed to load /shader.glsl (${res.status})`);
  }
  const bundledSource = await res.text();

  setLoadingStage('Compiling 5-scene shader on GPU…', 0.16);
  await yieldTwoFrames();

  gl = shaderCanvas.getContext('webgl2', {
    alpha: false,
    antialias: false,
    depth: false,
    stencil: false,
    powerPreference: 'high-performance',
    preserveDrawingBuffer: false,
  });
  if (!gl) {
    throw new Error('WebGL2 is not available in this browser.');
  }

  const parallelExt = gl.getExtension('KHR_parallel_shader_compile');
  await nextFrame();

  const fragSource = SHADERTOY_PRELUDE + bundledSource + SHADERTOY_EPILOGUE;

  // Dispatch shader compilation & program linking WITHOUT querying COMPILE_STATUS or LINK_STATUS yet
  // so Chrome/ANGLE compiles asynchronously on background GPU threads without stalling the main thread.
  const vs = gl.createShader(gl.VERTEX_SHADER);
  gl.shaderSource(vs, VERTEX_SRC);
  gl.compileShader(vs);

  const fs = gl.createShader(gl.FRAGMENT_SHADER);
  gl.shaderSource(fs, fragSource);
  gl.compileShader(fs);

  const pendingProgram = gl.createProgram();
  gl.attachShader(pendingProgram, vs);
  gl.attachShader(pendingProgram, fs);
  gl.linkProgram(pendingProgram);
  gl.flush();

  if (parallelExt) {
    while (!gl.getProgramParameter(pendingProgram, parallelExt.COMPLETION_STATUS_KHR)) {
      await nextFrame();
    }
  } else {
    await yieldTwoFrames();
  }

  const linked = gl.getProgramParameter(pendingProgram, gl.LINK_STATUS);
  if (!linked) {
    const vsOk = gl.getShaderParameter(vs, gl.COMPILE_STATUS);
    const fsOk = gl.getShaderParameter(fs, gl.COMPILE_STATUS);
    const errInfo =
      (!vsOk && gl.getShaderInfoLog(vs)) ||
      (!fsOk && gl.getShaderInfoLog(fs)) ||
      gl.getProgramInfoLog(pendingProgram) ||
      'Program link failed';
    gl.deleteShader(vs);
    gl.deleteShader(fs);
    gl.deleteProgram(pendingProgram);
    throw new Error(errInfo);
  }

  gl.deleteShader(vs);
  gl.deleteShader(fs);

  setLoadingStage('Warming GPU pipeline…', 0.94);
  await yieldTwoFrames();

  program = pendingProgram;
  vao = gl.createVertexArray();
  uniforms = {
    iResolution: gl.getUniformLocation(program, 'iResolution'),
    iTime: gl.getUniformLocation(program, 'iTime'),
    iTimeDelta: gl.getUniformLocation(program, 'iTimeDelta'),
    iFrameRate: gl.getUniformLocation(program, 'iFrameRate'),
    iFrame: gl.getUniformLocation(program, 'iFrame'),
    iMouse: gl.getUniformLocation(program, 'iMouse'),
    iDate: gl.getUniformLocation(program, 'iDate'),
  };
  shaderReady = true;

  renderShaderFrame(filmVideo.currentTime || 0, 1 / 60);
  gl.flush();
  await nextFrame();

  isCompiling = false;
  const compileMs = Math.round(performance.now() - compileStartPerf);
  if (shaderLoadingBar) {
    shaderLoadingBar.style.transform = 'scaleX(1)';
  }
  if (shaderLoadingTime) {
    shaderLoadingTime.textContent = `${(compileMs * 0.001).toFixed(1)}s`;
  }
  if (shaderLoading) {
    shaderLoading.classList.add('is-loaded');
    shaderLoading.setAttribute('aria-hidden', 'true');
  }

  const dbg = gl.getExtension('WEBGL_debug_renderer_info');
  const gpuRenderer = dbg ? gl.getParameter(dbg.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER);

  // Non-visual inspection hooks for automated testing and frame verification
  window.__shaderStudio = {
    ready: true,
    compiling: false,
    compileMs,
    parallelCompile: Boolean(parallelExt),
    gpuRenderer,
    resolution: [CANVAS_W, CANVAS_H],
    getFps: () => smoothedFps,
    captureAt: (timeSec) => {
      renderShaderFrame(timeSec, 1 / 60);
      return shaderCanvas.toDataURL('image/png');
    },
    seekTo,
    setViewMode,
    setWipePercent,
  };
}

function getShaderMouseVec4() {
  if (!hasOrbited) {
    return [0, 0, 0, 0];
  }
  const mx = CANVAS_W * 0.5 + orbitOffsetX;
  const my = CANVAS_H * 0.5 + orbitOffsetY;
  const clickX = CANVAS_W * 0.5;
  const clickY = CANVAS_H * 0.5;
  const signZ = isDraggingOrbit ? 1 : -1;
  return [mx, my, signZ * clickX, signZ * clickY];
}

function renderShaderFrame(timeSec, dt) {
  if (!shaderReady || !gl || !program) return;
  gl.viewport(0, 0, CANVAS_W, CANVAS_H);
  gl.useProgram(program);
  gl.bindVertexArray(vao);

  const now = new Date();
  const secsOfDay =
    now.getHours() * 3600 + now.getMinutes() * 60 + now.getSeconds() + now.getMilliseconds() * 0.001;
  const [mx, my, mz, mw] = getShaderMouseVec4();

  gl.uniform3f(uniforms.iResolution, CANVAS_W, CANVAS_H, 1.0);
  gl.uniform1f(uniforms.iTime, timeSec);
  gl.uniform1f(uniforms.iTimeDelta, dt);
  gl.uniform1f(uniforms.iFrameRate, smoothedFps);
  gl.uniform1i(uniforms.iFrame, frameIndex);
  gl.uniform4f(uniforms.iMouse, mx, my, mz, mw);
  gl.uniform4f(uniforms.iDate, now.getFullYear(), now.getMonth(), now.getDate(), secsOfDay);

  gl.drawArrays(gl.TRIANGLES, 0, 3);
  frameIndex += 1;
}

function tick(now) {
  const dt = Math.max(0.0005, (now - lastWallTime) * 0.001);
  lastWallTime = now;
  const instFps = 1.0 / dt;
  smoothedFps = smoothedFps * 0.92 + instFps * 0.08;

  const t = filmVideo.currentTime || 0;
  updateTransportUI(t);
  if (!filmVideo.paused || isDraggingOrbit || frameIndex < 3) {
    renderShaderFrame(t, dt);
  }
  requestAnimationFrame(tick);
}

filmVideo.addEventListener('loadeddata', () => {
  updateTransportUI(filmVideo.currentTime || 0);
  renderShaderFrame(filmVideo.currentTime || 0, 1 / 60);
});

filmVideo.addEventListener('seeked', () => {
  updateTransportUI(filmVideo.currentTime || 0);
  renderShaderFrame(filmVideo.currentTime || 0, 1 / 60);
});

initShader()
  .then(() => {
    lastWallTime = performance.now();
    smoothedFps = 60.0;
    requestAnimationFrame(tick);
  })
  .catch((err) => {
    isCompiling = false;
    console.error(err);
    if (shaderLoading) {
      shaderLoading.classList.add('has-error');
    }
    setLoadingStage('Shader compilation failed', 0);
    window.__shaderStudio = { ready: false, compiling: false, error: String(err) };
  });
