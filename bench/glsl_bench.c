// glsl_bench — headless GPU timing for ghostty-weather scene shaders.
//
// Creates an off-screen OpenGL 4.1 core context via CGL (no window, no GLFW —
// only macOS system frameworks), wraps a Shadertoy-style scene with the four
// uniforms Ghostty supplies (iResolution, iTime, iChannel0, iBackgroundColor),
// renders a full-screen triangle into an FBO at the requested resolution, and
// measures steady-state GPU cost as milliseconds per frame.
//
// METHOD: warm up, then submit FRAMES draws back-to-back advancing iTime each
// frame, then one glFinish() and divide wall-clock by FRAMES. Batching the
// draws (rather than glFinish per frame) lets the GPU pipeline frames the way
// a continuously-animating shader actually runs, so the number reflects per-
// frame throughput, not per-call sync latency. TRIALS repetitions are run; we
// print the min (cleanest, GPU at peak clock) and median (typical).
//
// CAVEAT: macOS OpenGL is itself layered over Metal, so absolute ms is a proxy
// for Ghostty's native-Metal pipeline. Relative ranking between scenes and the
// order-of-magnitude frame-budget % are sound — which is what the 5% gate needs.
//
// Build:  clang -O2 -DGL_SILENCE_DEPRECATION glsl_bench.c -framework OpenGL -o glsl_bench
// Usage:  glsl_bench <scene.glsl> [width height frames trials]
// Output (stdout, one line, parseable):  min_ms=<f> median_ms=<f>
// Diagnostics + GLSL compile logs go to stderr.

#include <OpenGL/OpenGL.h>   // CGL
#include <OpenGL/gl3.h>      // GL 3.2+ core entry points
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

// --- Ghostty-equivalent preamble. Only the uniforms the scenes actually use.
// The scenes carry their own #ifndef guards for TIME_OF_DAY_BASE / MOON_PHASE /
// IS_DAY, so stand-alone defaults match the swap script's fallbacks exactly.
static const char *PREAMBLE =
    "#version 410 core\n"
    "uniform vec3  iResolution;\n"
    "uniform float iTime;\n"
    "uniform sampler2D iChannel0;\n"
    "uniform vec3  iBackgroundColor;\n"
    "out vec4 _ghostty_fragColor;\n"
    "#line 1\n";

// Appended after the scene: a main() that drives Shadertoy's mainImage().
// gl_FragCoord is bottom-origin here vs Ghostty's top-origin, but orientation
// does not change per-pixel op count, so it is irrelevant to timing.
static const char *EPILOGUE =
    "\nvoid main() {\n"
    "    vec4 c;\n"
    "    mainImage(c, gl_FragCoord.xy);\n"
    "    _ghostty_fragColor = c;\n"
    "}\n";

// Trivial passthrough used as the baseline cost of running ANY full-screen
// custom-shader pass (rasterize + one texture fetch + FBO write bandwidth).
static const char *BASELINE_SCENE =
    "void mainImage(out vec4 fragColor, in vec2 fragCoord) {\n"
    "    vec4 term = texture(iChannel0, fragCoord / iResolution.xy);\n"
    "    vec3 outRgb = iBackgroundColor * (1.0 - term.a) + term.rgb;\n"
    "    fragColor = vec4(outRgb, 1.0);\n"
    "}\n";

static const char *VERT_SRC =
    "#version 410 core\n"
    "void main() {\n"
    "    vec2 p = vec2((gl_VertexID == 2) ? 3.0 : -1.0,\n"
    "                  (gl_VertexID == 1) ? 3.0 : -1.0);\n"
    "    gl_Position = vec4(p, 0.0, 1.0);\n"
    "}\n";

static char *read_file(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) { fprintf(stderr, "cannot open %s\n", path); return NULL; }
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *buf = malloc(n + 1);
    if (!buf) { fclose(f); return NULL; }
    if (fread(buf, 1, n, f) != (size_t)n) { fclose(f); free(buf); return NULL; }
    buf[n] = '\0';
    fclose(f);
    return buf;
}

static GLuint compile(GLenum type, const char *src, const char *label) {
    GLuint sh = glCreateShader(type);
    glShaderSource(sh, 1, &src, NULL);
    glCompileShader(sh);
    GLint ok = 0;
    glGetShaderiv(sh, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[8192];
        glGetShaderInfoLog(sh, sizeof log, NULL, log);
        fprintf(stderr, "[%s] GLSL compile failed:\n%s\n", label, log);
        glDeleteShader(sh);
        return 0;
    }
    return sh;
}

// Assemble PREAMBLE + scene + EPILOGUE, compile + link with the vertex shader.
static GLuint build_program(const char *scene_src) {
    size_t len = strlen(PREAMBLE) + strlen(scene_src) + strlen(EPILOGUE) + 1;
    char *frag = malloc(len);
    snprintf(frag, len, "%s%s%s", PREAMBLE, scene_src, EPILOGUE);

    GLuint vs = compile(GL_VERTEX_SHADER, VERT_SRC, "vertex");
    GLuint fs = compile(GL_FRAGMENT_SHADER, frag, "fragment");
    free(frag);
    if (!vs || !fs) return 0;

    GLuint prog = glCreateProgram();
    glAttachShader(prog, vs);
    glAttachShader(prog, fs);
    glLinkProgram(prog);
    glDeleteShader(vs);
    glDeleteShader(fs);
    GLint ok = 0;
    glGetProgramiv(prog, GL_LINK_STATUS, &ok);
    if (!ok) {
        char log[8192];
        glGetProgramInfoLog(prog, sizeof log, NULL, log);
        fprintf(stderr, "link failed:\n%s\n", log);
        return 0;
    }
    return prog;
}

static double now_ms(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec * 1000.0 + t.tv_nsec / 1.0e6;
}

static int cmp_double(const void *a, const void *b) {
    double x = *(const double *)a, y = *(const double *)b;
    return (x > y) - (x < y);
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s <scene.glsl|--baseline> [w h frames trials]\n", argv[0]);
        return 2;
    }
    int W = argc > 2 ? atoi(argv[2]) : 3456;
    int H = argc > 3 ? atoi(argv[3]) : 2234;
    int FRAMES = argc > 4 ? atoi(argv[4]) : 600;
    int TRIALS = argc > 5 ? atoi(argv[5]) : 9;
    int WARMUP = 60;

    char *scene = NULL;
    if (strcmp(argv[1], "--baseline") == 0) {
        scene = strdup(BASELINE_SCENE);
    } else {
        scene = read_file(argv[1]);
        if (!scene) return 1;
    }

    // --- Headless CGL context (OpenGL 4.1 core on Apple Silicon).
    CGLPixelFormatAttribute attrs[] = {
        kCGLPFAAccelerated,
        kCGLPFAOpenGLProfile, (CGLPixelFormatAttribute)kCGLOGLPVersion_GL4_Core,
        (CGLPixelFormatAttribute)0
    };
    CGLPixelFormatObj pix = NULL;
    GLint npix = 0;
    if (CGLChoosePixelFormat(attrs, &pix, &npix) != kCGLNoError || !pix) {
        fprintf(stderr, "CGLChoosePixelFormat failed (no GUI session?)\n");
        return 1;
    }
    CGLContextObj ctx = NULL;
    if (CGLCreateContext(pix, NULL, &ctx) != kCGLNoError || !ctx) {
        fprintf(stderr, "CGLCreateContext failed\n");
        return 1;
    }
    CGLSetCurrentContext(ctx);

    fprintf(stderr, "GL_RENDERER: %s\n", glGetString(GL_RENDERER));
    fprintf(stderr, "GL_VERSION:  %s\n", glGetString(GL_VERSION));

    // --- Off-screen render target at the requested resolution.
    GLuint fbo, rbo;
    glGenFramebuffers(1, &fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    glGenRenderbuffers(1, &rbo);
    glBindRenderbuffer(GL_RENDERBUFFER, rbo);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8, W, H);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, rbo);
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
        fprintf(stderr, "framebuffer incomplete\n");
        return 1;
    }
    glViewport(0, 0, W, H);

    GLuint vao;
    glGenVertexArrays(1, &vao);
    glBindVertexArray(vao);

    // Defeat dead-frame elimination on this tile-based GPU. Each frame fully
    // overwrites the FBO, so without a cross-frame dependency the driver is
    // free to skip every draw but the last (only its output is observable),
    // collapsing the measured per-frame time to near zero. Additive blending
    // makes frame N read the buffer left by frame N-1 → a serial dependency
    // that forces all FRAMES draws to execute in order. A 1-pixel readback
    // after each trial then forces the tile store to actually resolve.
    glEnable(GL_BLEND);
    glBlendFunc(GL_ONE, GL_ONE);

    GLuint prog = build_program(scene);
    free(scene);
    if (!prog) return 1;
    glUseProgram(prog);

    // Static uniforms.
    glUniform3f(glGetUniformLocation(prog, "iResolution"), (float)W, (float)H, 1.0f);
    glUniform3f(glGetUniformLocation(prog, "iBackgroundColor"), 0.07f, 0.09f, 0.12f);
    GLint uTime = glGetUniformLocation(prog, "iTime");

    // Dummy text layer: 2x2 fully-transparent texture (term.a = 0 → background
    // shows, the dominant case). texture() costs one fetch regardless of size.
    GLuint tex;
    glGenTextures(1, &tex);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, tex);
    unsigned char px[2 * 2 * 4] = {0};
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 2, 2, 0, GL_RGBA, GL_UNSIGNED_BYTE, px);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glUniform1i(glGetUniformLocation(prog, "iChannel0"), 0);

    // Warm up: compile caches, GPU clock ramp.
    for (int i = 0; i < WARMUP; i++) {
        if (uTime >= 0) glUniform1f(uTime, (float)i * 0.016f);
        glDrawArrays(GL_TRIANGLES, 0, 3);
    }
    glFinish();

    volatile unsigned char sink = 0;  // consumes readback so it can't be elided
    double *results = malloc(sizeof(double) * TRIALS);
    for (int t = 0; t < TRIALS; t++) {
        glClear(GL_COLOR_BUFFER_BIT);  // reset accumulation each trial
        double start = now_ms();
        for (int i = 0; i < FRAMES; i++) {
            if (uTime >= 0) glUniform1f(uTime, 1000.0f + (float)i * 0.016f);
            glDrawArrays(GL_TRIANGLES, 0, 3);
        }
        unsigned char rgba[4];
        glReadPixels(W / 2, H / 2, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, rgba);
        glFinish();
        results[t] = (now_ms() - start) / FRAMES;
        sink ^= rgba[0];
    }
    (void)sink;

    qsort(results, TRIALS, sizeof(double), cmp_double);
    double min_ms = results[0];
    double median_ms = results[TRIALS / 2];

    printf("min_ms=%.5f median_ms=%.5f\n", min_ms, median_ms);

    free(results);
    glDeleteProgram(prog);
    CGLSetCurrentContext(NULL);
    CGLDestroyContext(ctx);
    CGLDestroyPixelFormat(pix);
    return 0;
}
