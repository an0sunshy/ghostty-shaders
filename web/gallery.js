// ghostty-weather gallery — WebGL2 player for the scene shaders.
//
// Scenes are fetched VERBATIM from scenes/*.glsl (the same files Ghostty
// compiles) and assembled exactly like the terminal pipeline does:
//
//   preamble (glsl/preamble.glsl)   <- the host's uniform declarations
//   baked #defines                  <- what ghostty-weather-swap injects
//   #line 1 + scene + epilogue      <- Shadertoy body driven by main()
//
// Control changes re-bake the defines and recompile, which is faithfully
// how a real swap works (Ghostty has no iDate uniform, so phase/time are
// compile-time constants there too).
'use strict';

// Derived from the picker buttons in index.html — the single web-side scene
// registry (a unit test pins those buttons to shaders/scenes/*.glsl).
const SCENE_NAMES = [...document.querySelectorAll('.scene-picker button')]
  .map((b) => b.dataset.scene);

// Per-scene flavor for the fake terminal screenful (WMO code + description,
// mirroring what ghostty-weather-poll logs for that condition).
const SCENE_WMO = {
  'clear-day':    [0,  'clear sky'],
  'clear-night':  [0,  'clear sky'],
  'cloudy':       [3,  'overcast'],
  'rain':         [61, 'rain, slight'],
  'snow':         [71, 'snow, slight'],
  'thunderstorm': [95, 'thunderstorm'],
};

const MOON_NAMES = [
  'new', 'wax cresc', 'first qtr', 'wax gibb',
  'full', 'wan gibb', 'last qtr', 'wan cresc',
];

const state = {
  scene: 'clear-night',
  moonPhase: 0.5,
  timeOfDay: 43200, // seconds since midnight
  isDay: true,
  bg: [0x16 / 255, 0x18 / 255, 0x1f / 255],
  paused: false,
  fixedTime: null,  // #t=<secs>: freeze iTime for deterministic captures
};

const $ = (id) => document.getElementById(id);
const canvas = $('gl');
const errBox = $('err');
const statusBox = $('status');
const fpsBox = $('fps');

let gl = null;
let program = null;
let uniforms = null;
let termTex = null;
let sources = null;            // { preamble, epilogue, scenes: {name: src} }
let needsCompile = false;
let needsTexture = false;
let needsDraw = false;         // render one frame even while paused
let pausedNote = '';           // e.g. ' (reduced motion)'
let rafId = 0;
const t0 = performance.now();  // iTime epoch: "seconds since first frame"
let frames = 0;
let fpsStamp = performance.now();

// --- shader assembly ---------------------------------------------------------

function bakeDefines() {
  // Always bake all three; every scene #ifndef-guards the ones it uses and
  // silently ignores the rest — same contract as ghostty-weather-swap.
  return [
    `#define MOON_PHASE ${state.moonPhase.toFixed(4)}`,
    `#define IS_DAY ${state.isDay ? '1.0' : '0.0'}`,
    `#define TIME_OF_DAY_BASE ${state.timeOfDay.toFixed(1)}`,
  ].join('\n');
}

function fragmentSource() {
  return `${sources.preamble}\n${bakeDefines()}\n#line 1\n${sources.scenes[state.scene]}\n${sources.epilogue}`;
}

const VERT_SRC = `#version 300 es
// Fullscreen "big triangle" from gl_VertexID — no buffers needed.
void main() {
  vec2 p = vec2(float((gl_VertexID << 1) & 2), float(gl_VertexID & 2));
  gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
}`;

function compileShader(type, src) {
  const sh = gl.createShader(type);
  gl.shaderSource(sh, src);
  gl.compileShader(sh);
  if (!gl.getShaderParameter(sh, gl.COMPILE_STATUS)) {
    const log = gl.getShaderInfoLog(sh);
    gl.deleteShader(sh);
    throw new Error(log);
  }
  return sh;
}

function rebuildProgram() {
  const started = performance.now();
  let vs, fs, prog;
  try {
    vs = compileShader(gl.VERTEX_SHADER, VERT_SRC);
    fs = compileShader(gl.FRAGMENT_SHADER, fragmentSource());
    prog = gl.createProgram();
    gl.attachShader(prog, vs);
    gl.attachShader(prog, fs);
    gl.linkProgram(prog);
    if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) {
      throw new Error(gl.getProgramInfoLog(prog));
    }
  } catch (e) {
    // Keep the previous program running; surface the log (scene-relative
    // line numbers, courtesy of the #line 1 in the assembly).
    showError(`shader compile failed for ${state.scene} ` +
              `(line numbers are scene-relative):\n\n${e.message}`);
    return;
  } finally {
    if (vs) gl.deleteShader(vs);
    if (fs) gl.deleteShader(fs);
  }
  if (program) gl.deleteProgram(program);
  program = prog;
  uniforms = {
    iResolution:      gl.getUniformLocation(prog, 'iResolution'),
    iTime:            gl.getUniformLocation(prog, 'iTime'),
    iChannel0:        gl.getUniformLocation(prog, 'iChannel0'),
    iBackgroundColor: gl.getUniformLocation(prog, 'iBackgroundColor'),
  };
  hideError();
  statusBox.textContent =
    `${state.scene} · compiled in ${(performance.now() - started).toFixed(0)} ms` +
    (state.paused ? ` · paused${pausedNote}` : '');
}

// --- fake terminal texture (iChannel0) ----------------------------------------
// Ghostty hands scenes the rendered terminal as a premultiplied text-only
// texture; scenes composite their sky BEHIND it. We simulate a screenful.

function terminalLines() {
  const [wmo, desc] = SCENE_WMO[state.scene] ?? [0, 'clear sky'];
  const day = state.scene === 'clear-night' ? 'night'
    : state.scene === 'clear-day' ? 'day'
    : (state.isDay ? 'day' : 'night');
  return [
    ['$ ', 'ghostty-weather-poll'],
    ['', `poll: 47.61,-122.33 -> WMO ${wmo} (${desc}) · ${day}`],
    ['', `swap: scene=${state.scene} -> weather-20260610.glsl`],
    ['', 'swap: SIGUSR2 -> reloaded 3 surfaces in place'],
    ['', ''],
    ['$ ', 'ghostty-weather-toggle --status'],
    ['', `scene: ${state.scene} · paused: no · poller: every 15 min`],
    ['', ''],
    ['# ', 'text stays legible: scenes render behind the glyphs'],
    ['$ ', '█'],
  ];
}

// One reused backing store — a fresh full-framebuffer canvas per rebuild
// would be ~14 MB of garbage per resize step at dpr 2.
const termCanvas = document.createElement('canvas');
const termCtx = termCanvas.getContext('2d');

function rebuildTerminalTexture() {
  const w = canvas.width, h = canvas.height;
  if (w === 0 || h === 0) return;
  const cv = termCanvas;
  cv.width = w;            // size assignment also clears the canvas
  cv.height = h;
  const ctx = termCtx;
  const px = Math.max(12, Math.round(h / 34));
  ctx.font = `${px}px ui-monospace, SFMono-Regular, Menlo, Consolas, monospace`;
  ctx.textBaseline = 'top';
  const lineH = Math.round(px * 1.45);
  const left = Math.round(px * 1.2);
  let y = Math.round(px * 1.2);
  for (const [prefix, text] of terminalLines()) {
    let x = left;
    if (prefix) {
      ctx.fillStyle = prefix.startsWith('#') ? '#565f89' : '#9ece6a';
      ctx.fillText(prefix, x, y);
      x += ctx.measureText(prefix).width;
    }
    ctx.fillStyle = prefix === '$ ' ? '#c0caf5' : prefix === '# ' ? '#565f89' : '#787c99';
    ctx.fillText(text, x, y);
    y += lineH;
  }

  if (!termTex) termTex = gl.createTexture();
  gl.bindTexture(gl.TEXTURE_2D, termTex);
  // Scenes assume premultiplied alpha ("over" blend: bg*(1-a)+rgb).
  gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, true);
  gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, cv);
  gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
}

// --- render loop ---------------------------------------------------------------

function drawFrame() {
  gl.viewport(0, 0, canvas.width, canvas.height);
  gl.useProgram(program);
  gl.uniform3f(uniforms.iResolution, canvas.width, canvas.height, 1.0);
  gl.uniform1f(uniforms.iTime,
    state.fixedTime ?? (performance.now() - t0) / 1000);
  gl.uniform3f(uniforms.iBackgroundColor, state.bg[0], state.bg[1], state.bg[2]);
  gl.activeTexture(gl.TEXTURE0);
  gl.bindTexture(gl.TEXTURE_2D, termTex);
  gl.uniform1i(uniforms.iChannel0, 0);
  gl.drawArrays(gl.TRIANGLES, 0, 3);
}

let ticking = false;

// Arm the rAF loop if it isn't running. The loop parks itself when paused
// with nothing pending (a paused tab costs zero CPU — the same
// don't-burn-the-battery ethos as the terminal version), so every state
// mutation funnels through here to wake it.
function ensureTicking() {
  if (!ticking) {
    ticking = true;
    rafId = requestAnimationFrame(tick);
  }
}

// Slider drags request a recompile per input event; compiling per rAF frame
// would chain main-thread stalls on slow GLSL compilers (ANGLE/HLSL). The
// flag persists until consumed, so the final drag position always compiles.
const COMPILE_MIN_GAP_MS = 150;
let lastCompileAt = -Infinity;

function tick() {
  ticking = false;
  if (needsTexture) { rebuildTerminalTexture(); needsTexture = false; needsDraw = true; }
  if (needsCompile && performance.now() - lastCompileAt >= COMPILE_MIN_GAP_MS) {
    rebuildProgram();
    needsCompile = false;
    lastCompileAt = performance.now();
    needsDraw = true;
  }
  if (program) {
    // While paused, still render exactly one frame whenever something
    // changed (control tweak, resize, recompile, context restore) so the
    // view never goes stale or blank.
    if (!state.paused || needsDraw) {
      needsDraw = false;
      drawFrame();
      if (!state.paused) {
        frames++;
        const now = performance.now();
        if (now - fpsStamp >= 500) {
          fpsBox.textContent = `· ${Math.round((frames * 1000) / (now - fpsStamp))} fps`;
          frames = 0;
          fpsStamp = now;
        }
      }
    }
  } else {
    needsDraw = false; // nothing can consume it; don't spin while paused
  }
  // Keep running while animating or while work is pending (e.g. a throttled
  // recompile); park otherwise.
  if (!state.paused || needsCompile || needsTexture || needsDraw) ensureTicking();
}

// --- errors / status -----------------------------------------------------------

function showError(msg) {
  errBox.textContent = msg;
  errBox.hidden = false;
}
function hideError() {
  errBox.hidden = true;
}

// --- UI ------------------------------------------------------------------------

function fmtTime(secs) {
  const h = String(Math.floor(secs / 3600)).padStart(2, '0');
  const m = String(Math.floor((secs % 3600) / 60)).padStart(2, '0');
  return `${h}:${m}`;
}
function moonName(p) {
  return MOON_NAMES[Math.round(p * 8) % 8];
}

function syncPauseButton() {
  const btn = $('ctl-pause');
  btn.setAttribute('aria-pressed', String(state.paused));
  btn.textContent = state.paused ? '▶ resume' : '⏸ pause';
}

function syncControls() {
  for (const label of document.querySelectorAll('.controls label[data-for-scene]')) {
    label.hidden = !label.dataset.forScene.split(' ').includes(state.scene);
  }
  for (const btn of document.querySelectorAll('.scene-picker button')) {
    btn.setAttribute('aria-pressed', String(btn.dataset.scene === state.scene));
  }
  $('moon-out').value = moonName(state.moonPhase);
  $('time-out').value = fmtTime(state.timeOfDay);
}

// Debounced: slider drags fire per input event, and Safari rate-limits
// history.replaceState (throws SecurityError past ~100 calls / 30 s).
let hashTimer = 0;
function syncHash() {
  clearTimeout(hashTimer);
  hashTimer = setTimeout(writeHash, 250);
}
function writeHash() {
  const p = new URLSearchParams({
    scene: state.scene,
    moon: state.moonPhase.toFixed(2),
    time: String(state.timeOfDay),
    day: state.isDay ? '1' : '0',
  });
  // Keep capture/embed params so the URL stays a faithful reproduction of
  // what's on screen.
  if (state.fixedTime !== null) p.set('t', String(state.fixedTime));
  if (document.body.classList.contains('embed')) p.set('embed', '1');
  history.replaceState(null, '', `#${p}`);
}

function readHash() {
  const p = new URLSearchParams(location.hash.slice(1));
  if (SCENE_NAMES.includes(p.get('scene'))) state.scene = p.get('scene');
  const moon = parseFloat(p.get('moon'));
  if (moon >= 0 && moon < 1) state.moonPhase = moon;
  const time = parseInt(p.get('time'), 10);
  if (time >= 0 && time < 86400) state.timeOfDay = time;
  if (p.has('day')) state.isDay = p.get('day') !== '0';
  // Embed mode: bare terminal window, for iframes and README captures.
  if (p.get('embed') === '1') document.body.classList.add('embed');
  // Fixed time: render exactly one deterministic frame at iTime=t.
  const t = parseFloat(p.get('t'));
  if (Number.isFinite(t) && t >= 0) {
    state.fixedTime = t;
    state.paused = true;
  }
}

function onStateChange({ recompile = false, retexture = false } = {}) {
  needsCompile = needsCompile || recompile;
  needsTexture = needsTexture || retexture;
  needsDraw = true;
  syncControls();
  syncHash();
  ensureTicking();
}

function wireUI() {
  for (const btn of document.querySelectorAll('.scene-picker button')) {
    btn.addEventListener('click', () => {
      state.scene = btn.dataset.scene;
      onStateChange({ recompile: true, retexture: true });
    });
  }
  $('ctl-moon').addEventListener('input', (e) => {
    state.moonPhase = parseFloat(e.target.value);
    onStateChange({ recompile: true });
  });
  $('ctl-time').addEventListener('input', (e) => {
    state.timeOfDay = parseInt(e.target.value, 10);
    onStateChange({ recompile: true });
  });
  $('ctl-day').addEventListener('change', (e) => {
    state.isDay = e.target.checked;
    onStateChange({ recompile: true, retexture: true });
  });
  $('ctl-bg').addEventListener('input', (e) => {
    const v = e.target.value;
    state.bg = [1, 3, 5].map((i) => parseInt(v.slice(i, i + 2), 16) / 255);
    needsDraw = true; // uniform only — no recompile needed
    ensureTicking();
  });
  $('ctl-pause').addEventListener('click', () => {
    state.paused = !state.paused;
    if (!state.paused) {
      // Resuming exits fixed-time mode — otherwise the loop would run but
      // redraw the same frozen iTime forever. Reset the fps window too, or
      // the first readout would average over the whole paused interval.
      state.fixedTime = null;
      pausedNote = '';
      frames = 0;
      fpsStamp = performance.now();
      syncHash();
      ensureTicking();
    }
    syncPauseButton();
    fpsBox.textContent = '';
  });

  // Reflect hash-set control values back into the inputs.
  $('ctl-moon').value = String(state.moonPhase);
  $('ctl-time').value = String(state.timeOfDay);
  $('ctl-day').checked = state.isDay;
}

// --- boot ----------------------------------------------------------------------

async function fetchSources() {
  const get = async (url) => {
    const res = await fetch(url);
    if (!res.ok) throw new Error(`${url}: HTTP ${res.status}`);
    return res.text();
  };
  const [preamble, epilogue, ...sceneSrcs] = await Promise.all([
    get('glsl/preamble.glsl'),
    get('glsl/epilogue.glsl'),
    ...SCENE_NAMES.map((n) => get(`scenes/${n}.glsl`)),
  ]);
  return {
    preamble,
    epilogue,
    scenes: Object.fromEntries(SCENE_NAMES.map((n, i) => [n, sceneSrcs[i]])),
  };
}

function setupGL() {
  // preserveDrawingBuffer keeps right-click "Save image as…" working.
  gl = canvas.getContext('webgl2', {
    alpha: false,
    antialias: false,
    preserveDrawingBuffer: true,
  });
  return gl !== null;
}

function setupResize() {
  const apply = () => {
    // Read dpr per invocation — it changes when the window moves to a
    // different-density monitor (cap at 2: fbm per pixel beyond that is
    // invisible cost).
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    const w = Math.round(canvas.clientWidth * dpr);
    const h = Math.round(canvas.clientHeight * dpr);
    if (w === canvas.width && h === canvas.height) return;
    canvas.width = w;
    canvas.height = h;
    needsTexture = true; // tick redraws even while paused (needsDraw)
    ensureTicking();
  };
  // ResizeObserver doesn't fire on a monitor move (CSS size is unchanged),
  // so watch devicePixelRatio via the canonical once-per-value matchMedia
  // pattern.
  const watchDpr = () => {
    matchMedia(`(resolution: ${window.devicePixelRatio}dppx)`)
      .addEventListener('change', () => { apply(); watchDpr(); }, { once: true });
  };
  watchDpr();
  new ResizeObserver(apply).observe(canvas);
  apply();
}

async function main() {
  if (!setupGL()) {
    $('no-webgl2').hidden = false;
    statusBox.textContent = 'WebGL2 unavailable';
    return;
  }
  readHash();
  wireUI();
  syncControls();
  try {
    sources = await fetchSources();
  } catch (e) {
    showError(`failed to fetch shader sources: ${e.message}\n\n` +
              'If running locally, serve the assembled site with ' +
              'scripts/serve-site.sh (the gallery expects the Pages layout).');
    statusBox.textContent = 'load failed';
    return;
  }
  setupResize();
  needsCompile = true;
  needsTexture = true;

  if (window.matchMedia('(prefers-reduced-motion: reduce)').matches &&
      state.fixedTime === null) {
    state.paused = true;
    pausedNote = ' (reduced motion)';
  }
  syncPauseButton();

  canvas.addEventListener('webglcontextlost', (e) => {
    e.preventDefault();
    cancelAnimationFrame(rafId);
    ticking = false;
    statusBox.textContent = 'GPU context lost — waiting for restore…';
  });
  canvas.addEventListener('webglcontextrestored', () => {
    program = null;
    termTex = null;
    needsCompile = true;
    needsTexture = true;
    ensureTicking();
  });

  ensureTicking();
}

main();
