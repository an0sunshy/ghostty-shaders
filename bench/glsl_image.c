// glsl_image — deterministic single-frame render of a ghostty-weather scene,
// for golden-image visual-regression testing.
//
// Shares glsl_bench.c's headless CGL/OpenGL 4.1 approach (off-screen FBO, no
// window, no dependencies beyond macOS system frameworks) and the IDENTICAL
// scene wrapping (PREAMBLE + scene + EPILOGUE), so the pixels here correspond
// to the same program the timing harness measures. But instead of timing, it
// renders ONE frame at a FIXED iTime and FIXED resolution and either writes it
// to a PNG or compares it against a reference PNG.
//
// Determinism levers:
//   * iTime is pinned (DEFAULT_TIME) so animated scenes resolve to one frame.
//   * iChannel0 is a 1x1 fully-transparent-black texture, so the glyph layer
//     contributes nothing — we test the scene effect, not text.
//   * resolution is fixed (default 480x310, override via argv or the ref PNG).
//   * no blending — a single opaque pass, unlike the timing harness which adds
//     frames to defeat dead-frame elimination.
// Residual nondeterminism is GPU floating-point: see bench/golden.sh for the
// cross-hardware caveat and how the comparison tolerance absorbs it.
//
// Build:
//   clang -O2 -DGL_SILENCE_DEPRECATION glsl_image.c -framework OpenGL -o glsl_image
// PNG I/O via stb single-header libs, expected at bench/vendor/ (golden.sh
// fetches them).
//
// CLI:
//   glsl_image <scene.glsl> --write   <out.png> [W H]
//   glsl_image <scene.glsl> --compare <ref.png> [--tolerance MEANABSDIFF] [W H]
//
// --compare loads the reference, re-renders at the reference's dimensions,
// computes the MEAN absolute per-channel difference over RGB (0-255 scale),
// prints the score, and exits 0 if score <= tolerance (default 2.0) else 1.
// A dimension mismatch is a hard failure.

#include <OpenGL/OpenGL.h>   // CGL
#include <OpenGL/gl3.h>      // GL 3.2+ core entry points
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define STB_IMAGE_IMPLEMENTATION
#include "vendor/stb_image.h"
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "vendor/stb_image_write.h"

#define DEFAULT_W    480
#define DEFAULT_H    310
#define DEFAULT_TIME 10.0f
#define DEFAULT_TOL  2.0

// --- Scene wrapping — MUST match glsl_bench.c exactly. -----------------------
static const char *PREAMBLE =
    "#version 410 core\n"
    "uniform vec3  iResolution;\n"
    "uniform float iTime;\n"
    "uniform sampler2D iChannel0;\n"
    "uniform vec3  iBackgroundColor;\n"
    "out vec4 _ghostty_fragColor;\n"
    "#line 1\n";

static const char *EPILOGUE =
    "\nvoid main() {\n"
    "    vec4 c;\n"
    "    mainImage(c, gl_FragCoord.xy);\n"
    "    _ghostty_fragColor = c;\n"
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

// Render one deterministic frame of `scene_src` at W x H into a freshly-malloc'd
// RGBA8 buffer (scene-upright rows, ready for PNG). Returns NULL on failure.
static unsigned char *render_frame(const char *scene_src, int W, int H) {
    CGLPixelFormatAttribute attrs[] = {
        kCGLPFAAccelerated,
        kCGLPFAOpenGLProfile, (CGLPixelFormatAttribute)kCGLOGLPVersion_GL4_Core,
        (CGLPixelFormatAttribute)0
    };
    CGLPixelFormatObj pix = NULL;
    GLint npix = 0;
    if (CGLChoosePixelFormat(attrs, &pix, &npix) != kCGLNoError || !pix) {
        fprintf(stderr, "CGLChoosePixelFormat failed (no GUI session?)\n");
        return NULL;
    }
    CGLContextObj ctx = NULL;
    if (CGLCreateContext(pix, NULL, &ctx) != kCGLNoError || !ctx) {
        fprintf(stderr, "CGLCreateContext failed\n");
        CGLDestroyPixelFormat(pix);
        return NULL;
    }
    CGLSetCurrentContext(ctx);

    GLuint fbo, rbo;
    glGenFramebuffers(1, &fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    glGenRenderbuffers(1, &rbo);
    glBindRenderbuffer(GL_RENDERBUFFER, rbo);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8, W, H);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, rbo);
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
        fprintf(stderr, "framebuffer incomplete\n");
        return NULL;
    }
    glViewport(0, 0, W, H);

    GLuint vao;
    glGenVertexArrays(1, &vao);
    glBindVertexArray(vao);

    GLuint prog = build_program(scene_src);
    if (!prog) return NULL;
    glUseProgram(prog);

    // Same static uniforms as the timing harness.
    glUniform3f(glGetUniformLocation(prog, "iResolution"), (float)W, (float)H, 1.0f);
    glUniform3f(glGetUniformLocation(prog, "iBackgroundColor"), 0.07f, 0.09f, 0.12f);
    GLint uTime = glGetUniformLocation(prog, "iTime");
    if (uTime >= 0) glUniform1f(uTime, DEFAULT_TIME);

    // 1x1 fully-transparent-black glyph layer → text contributes nothing.
    GLuint tex;
    glGenTextures(1, &tex);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, tex);
    unsigned char px[4] = {0, 0, 0, 0};
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 1, 1, 0, GL_RGBA, GL_UNSIGNED_BYTE, px);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glUniform1i(glGetUniformLocation(prog, "iChannel0"), 0);

    glDisable(GL_BLEND);
    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
    glDrawArrays(GL_TRIANGLES, 0, 3);
    glFinish();

    // Read back. glReadPixels returns rows bottom-first, but the scenes
    // interpret fragCoord as TOP-origin (Ghostty's Metal convention) and flip
    // uv.y internally, so the framebuffer is vertically mirrored: bottom-first
    // readback already yields scene-upright rows, oriented exactly as Ghostty
    // displays them. (Reversing rows here — the usual GL-to-PNG fix for
    // bottom-origin shaders — re-inverts these scenes; it's what rendered
    // every golden upside down.)
    unsigned char *out = malloc((size_t)W * H * 4);
    if (!out) return NULL;
    glReadPixels(0, 0, W, H, GL_RGBA, GL_UNSIGNED_BYTE, out);

    glDeleteProgram(prog);
    CGLSetCurrentContext(NULL);
    CGLDestroyContext(ctx);
    CGLDestroyPixelFormat(pix);
    return out;
}

static void usage(const char *prog) {
    fprintf(stderr,
        "usage: %s <scene.glsl> --write <out.png> [W H]\n"
        "       %s <scene.glsl> --compare <ref.png> [--tolerance MEANABSDIFF] [W H]\n",
        prog, prog);
}

int main(int argc, char **argv) {
    if (argc < 3) { usage(argv[0]); return 2; }

    const char *scene_path = argv[1];
    const char *mode = argv[2];   // --write | --compare
    if (argc < 4) { usage(argv[0]); return 2; }
    const char *png_path = argv[3];

    int W = DEFAULT_W, H = DEFAULT_H;
    double tolerance = DEFAULT_TOL;

    // Parse the trailing optional args: [--tolerance T] [W H], any order
    // (tolerance only meaningful for --compare).
    int pos = 0;            // count of positional W/H seen
    for (int i = 4; i < argc; i++) {
        if (strcmp(argv[i], "--tolerance") == 0) {
            if (i + 1 >= argc) { fprintf(stderr, "--tolerance needs a value\n"); return 2; }
            tolerance = atof(argv[++i]);
        } else if (pos == 0) {
            W = atoi(argv[i]); pos++;
        } else if (pos == 1) {
            H = atoi(argv[i]); pos++;
        } else {
            fprintf(stderr, "unexpected argument: %s\n", argv[i]);
            return 2;
        }
    }

    char *scene = read_file(scene_path);
    if (!scene) return 1;

    if (strcmp(mode, "--write") == 0) {
        unsigned char *img = render_frame(scene, W, H);
        free(scene);
        if (!img) return 1;
        if (!stbi_write_png(png_path, W, H, 4, img, W * 4)) {
            fprintf(stderr, "failed to write PNG %s\n", png_path);
            free(img);
            return 1;
        }
        free(img);
        printf("wrote %s (%dx%d)\n", png_path, W, H);
        return 0;
    }

    if (strcmp(mode, "--compare") == 0) {
        int rw = 0, rh = 0, rc = 0;
        unsigned char *ref = stbi_load(png_path, &rw, &rh, &rc, 4);
        if (!ref) {
            fprintf(stderr, "cannot load reference PNG %s: %s\n",
                    png_path, stbi_failure_reason());
            free(scene);
            return 1;
        }
        // Re-render at the reference's dimensions (any positional W/H is ignored
        // when comparing — the reference defines the canvas).
        unsigned char *img = render_frame(scene, rw, rh);
        free(scene);
        if (!img) { stbi_image_free(ref); return 1; }

        // MEAN absolute per-channel difference over RGB only (ignore alpha;
        // every frame is opaque).
        double sum = 0.0;
        size_t npx = (size_t)rw * rh;
        for (size_t p = 0; p < npx; p++) {
            for (int c = 0; c < 3; c++) {
                int d = (int)img[p * 4 + c] - (int)ref[p * 4 + c];
                if (d < 0) d = -d;
                sum += d;
            }
        }
        double score = sum / (double)(npx * 3);
        stbi_image_free(ref);
        free(img);

        printf("meanabsdiff=%.4f tolerance=%.4f (%dx%d)\n", score, tolerance, rw, rh);
        if (score <= tolerance) return 0;
        fprintf(stderr, "DRIFT: %s exceeds tolerance (%.4f > %.4f)\n",
                scene_path, score, tolerance);
        return 1;
    }

    free(scene);
    usage(argv[0]);
    return 2;
}
