#!/usr/bin/env python3
"""
BC-250 offscreen graphics correctness verifier.

Renders deterministic integer and floating-point fragment workloads through EGL/GLES3,
reads the framebuffer back, and compares per-frame/per-tile hashes against a stock
24-CU reference. The reference is generated and self-checked while the board is in
its known-good boot routing.

This catches corruption that a compute-only verifier can miss. It cannot guarantee
catching corruption introduced strictly after rendering/readback (e.g. final scanout/PHY).
"""
from __future__ import annotations

import argparse
import ctypes as C
import ctypes.util
import hashlib
import json
import os
import shutil
import sys
import time
from pathlib import Path

# EGL constants/types (subset only)
EGL_NONE = 0x3038
EGL_SURFACE_TYPE = 0x3033
EGL_PBUFFER_BIT = 0x0001
EGL_RENDERABLE_TYPE = 0x3040
EGL_OPENGL_ES3_BIT = 0x0040
EGL_RED_SIZE = 0x3024
EGL_GREEN_SIZE = 0x3023
EGL_BLUE_SIZE = 0x3022
EGL_ALPHA_SIZE = 0x3021
EGL_WIDTH = 0x3057
EGL_HEIGHT = 0x3056
EGL_CONTEXT_CLIENT_VERSION = 0x3098
EGL_OPENGL_ES_API = 0x30A0
EGL_PLATFORM_SURFACELESS_MESA = 0x31DD
EGL_VENDOR = 0x3053
EGL_VERSION = 0x3054

# GLES constants (subset only)
GL_VENDOR = 0x1F00
GL_RENDERER = 0x1F01
GL_VERSION = 0x1F02
GL_SHADING_LANGUAGE_VERSION = 0x8B8C
GL_VERTEX_SHADER = 0x8B31
GL_FRAGMENT_SHADER = 0x8B30
GL_COMPILE_STATUS = 0x8B81
GL_LINK_STATUS = 0x8B82
GL_INFO_LOG_LENGTH = 0x8B84
GL_TEXTURE_2D = 0x0DE1
GL_TEXTURE_MIN_FILTER = 0x2801
GL_TEXTURE_MAG_FILTER = 0x2800
GL_TEXTURE_WRAP_S = 0x2802
GL_TEXTURE_WRAP_T = 0x2803
GL_NEAREST = 0x2600
GL_CLAMP_TO_EDGE = 0x812F
GL_RGBA8 = 0x8058
GL_RGBA8UI = 0x8D7C
GL_RGBA = 0x1908
GL_RGBA_INTEGER = 0x8D99
GL_UNSIGNED_BYTE = 0x1401
GL_FRAMEBUFFER = 0x8D40
GL_COLOR_ATTACHMENT0 = 0x8CE0
GL_FRAMEBUFFER_COMPLETE = 0x8CD5
GL_COLOR_BUFFER_BIT = 0x00004000
GL_TRIANGLES = 0x0004
GL_DITHER = 0x0BD0
GL_BLEND = 0x0BE2
GL_NO_ERROR = 0

VERTEX_SHADER = r"""#version 300 es
precision highp float;
const vec2 P[3] = vec2[3](
    vec2(-1.0, -1.0),
    vec2( 3.0, -1.0),
    vec2(-1.0,  3.0)
);
void main() {
    gl_Position = vec4(P[gl_VertexID], 0.0, 1.0);
}
"""

INT_FRAGMENT_SHADER = r"""#version 300 es
precision highp float;
precision highp int;
layout(location=0) out uvec4 outColor;
uniform highp uint uSeed;
uniform highp uint uRounds;
uint avalanche(uint h) {
    h ^= h >> 16u;
    h *= 0x7feb352du;
    h ^= h >> 15u;
    h *= 0x846ca68bu;
    h ^= h >> 16u;
    return h;
}
void main() {
    uint x = uint(gl_FragCoord.x);
    uint y = uint(gl_FragCoord.y);
    uint h = x * 0x9e3779b9u ^ y * 0x85ebca6bu ^ uSeed * 0xc2b2ae35u;
    for (uint i = 0u; i < uRounds; ++i) {
        h = avalanche(h + i * 0x27d4eb2du + x * 0x165667b1u + y * 0xd3a2646cu);
        h ^= (h << ((i & 7u) + 1u)) | (h >> (31u - (i & 7u)));
    }
    uint a = avalanche(h ^ 0xa5a5a5a5u);
    uint b = avalanche(h ^ 0x3c6ef372u);
    uint c = avalanche(h ^ 0xbb67ae85u);
    uint d = avalanche(h ^ 0x1f83d9abu);
    outColor = uvec4(a & 255u, b & 255u, c & 255u, d & 255u);
}
"""

FPQ_FRAGMENT_SHADER = r"""#version 300 es
precision highp float;
precision highp int;
layout(location=0) out uvec4 outColor;
uniform highp uint uSeed;
uniform highp uint uRounds;

// FP workload intentionally uses dyadic (binary-exact) constants and quantizes
// every round.  The old chaotic fract() recurrence amplified harmless FP rounding
// into whole-frame byte changes on stock hardware, which made exact references
// unusable.  This still drives FP/vector ALU, conversions and fragment execution,
// but keeps the expected framebuffer reproducible bit-for-bit.
void main() {
    uint x = uint(gl_FragCoord.x);
    uint y = uint(gl_FragCoord.y);
    vec4 v = vec4(
        float((x + (uSeed        & 255u)) & 255u),
        float((y + ((uSeed >>  8u) & 255u)) & 255u),
        float(((x ^ y) + ((uSeed >> 16u) & 255u)) & 255u),
        float(((x + y) + ((uSeed >> 24u) & 255u)) & 255u)
    );

    for (uint i = 0u; i < uRounds; ++i) {
        vec4 addv = vec4(
            float((i + (uSeed & 15u)) & 15u),
            float(((i * 3u) + ((uSeed >> 4u) & 15u)) & 15u),
            float(((i * 5u) + ((uSeed >> 8u) & 15u)) & 15u),
            float(((i * 7u) + ((uSeed >> 12u) & 15u)) & 15u)
        );

        // All coefficients are exactly representable in binary32.
        v = v * vec4(1.5, 1.25, 0.75, 1.125) + addv;
        v = v.yzwx + v.wxyz * vec4(0.5, 0.25, 0.5, 0.25);

        // Collapse tiny implementation-level FP differences instead of amplifying
        // them. floor(x/4)*4 keeps values on an exact integer lattice.
        v = floor(v * 0.25) * 4.0;
        // Exact modulo 1024 using 1/1024 (also binary-exact).
        v = v - floor(v * 0.0009765625) * 1024.0;
        v = abs(v);
    }

    uvec4 q = uvec4(v) & 255u;
    // Add a deterministic integer post-mix so each channel remains visually busy.
    q ^= uvec4(x, y, x ^ y, x + y) & 255u;
    outColor = q;
}
"""


def die(msg: str, code: int = 1) -> None:
    print(f"[bc250-gfx] ERROR: {msg}", file=sys.stderr)
    raise SystemExit(code)


def info(msg: str) -> None:
    print(f"[bc250-gfx] {msg}", flush=True)


def _lib(name: str, fallbacks: list[str]) -> C.CDLL:
    found = ctypes.util.find_library(name)
    for candidate in ([found] if found else []) + fallbacks:
        if not candidate:
            continue
        try:
            return C.CDLL(candidate)
        except OSError:
            pass
    die(f"could not load {name} ({', '.join(fallbacks)})")


class EGLGLES:
    def __init__(self, width: int, height: int):
        self.width = width
        self.height = height
        self.egl = _lib("EGL", ["libEGL.so.1"])
        self.gl = _lib("GLESv2", ["libGLESv2.so.2"])
        self._bind_egl()
        self._init_egl()
        self._bind_gl()
        self.renderer = self._gl_string(GL_RENDERER)
        self.vendor = self._gl_string(GL_VENDOR)
        self.gl_version = self._gl_string(GL_VERSION)
        self.glsl_version = self._gl_string(GL_SHADING_LANGUAGE_VERSION)
        self.egl_vendor = self._egl_string(EGL_VENDOR)
        self.egl_version = self._egl_string(EGL_VERSION)
        self.programs = {
            "int": self._program(VERTEX_SHADER, INT_FRAGMENT_SHADER),
            "fpq": self._program(VERTEX_SHADER, FPQ_FRAGMENT_SHADER),
        }
        self.fbos = {
            "int": self._make_target(GL_RGBA8UI, GL_RGBA_INTEGER),
            "fpq": self._make_target(GL_RGBA8UI, GL_RGBA_INTEGER),
        }
        self.gl.glDisable(GL_DITHER)
        self.gl.glDisable(GL_BLEND)

    def _bind_egl(self) -> None:
        e = self.egl
        e.eglGetProcAddress.argtypes = [C.c_char_p]
        e.eglGetProcAddress.restype = C.c_void_p
        e.eglGetDisplay.argtypes = [C.c_void_p]
        e.eglGetDisplay.restype = C.c_void_p
        e.eglInitialize.argtypes = [C.c_void_p, C.POINTER(C.c_int), C.POINTER(C.c_int)]
        e.eglInitialize.restype = C.c_uint
        e.eglBindAPI.argtypes = [C.c_uint]
        e.eglBindAPI.restype = C.c_uint
        e.eglChooseConfig.argtypes = [C.c_void_p, C.POINTER(C.c_int), C.POINTER(C.c_void_p), C.c_int, C.POINTER(C.c_int)]
        e.eglChooseConfig.restype = C.c_uint
        e.eglCreatePbufferSurface.argtypes = [C.c_void_p, C.c_void_p, C.POINTER(C.c_int)]
        e.eglCreatePbufferSurface.restype = C.c_void_p
        e.eglCreateContext.argtypes = [C.c_void_p, C.c_void_p, C.c_void_p, C.POINTER(C.c_int)]
        e.eglCreateContext.restype = C.c_void_p
        e.eglMakeCurrent.argtypes = [C.c_void_p, C.c_void_p, C.c_void_p, C.c_void_p]
        e.eglMakeCurrent.restype = C.c_uint
        e.eglQueryString.argtypes = [C.c_void_p, C.c_int]
        e.eglQueryString.restype = C.c_char_p
        e.eglGetError.restype = C.c_uint

    def _init_egl(self) -> None:
        get_platform_addr = self.egl.eglGetProcAddress(b"eglGetPlatformDisplayEXT")
        dpy = None
        if get_platform_addr:
            fn = C.CFUNCTYPE(C.c_void_p, C.c_uint, C.c_void_p, C.POINTER(C.c_int))(get_platform_addr)
            dpy = fn(EGL_PLATFORM_SURFACELESS_MESA, None, None)
        if not dpy:
            dpy = self.egl.eglGetDisplay(None)
        if not dpy:
            die("eglGetDisplay/eglGetPlatformDisplayEXT failed")
        major, minor = C.c_int(), C.c_int()
        if not self.egl.eglInitialize(dpy, C.byref(major), C.byref(minor)):
            die(f"eglInitialize failed (0x{self.egl.eglGetError():04x})")
        if not self.egl.eglBindAPI(EGL_OPENGL_ES_API):
            die("eglBindAPI(OpenGL ES) failed")
        attrs = (C.c_int * 15)(
            EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
            EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
            EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8,
            EGL_NONE, 0, 0,
        )
        # Correct terminator location; final two values above are ignored after EGL_NONE.
        config = C.c_void_p()
        num = C.c_int()
        if not self.egl.eglChooseConfig(dpy, attrs, C.byref(config), 1, C.byref(num)) or num.value < 1:
            die(f"no EGL GLES3 pbuffer config (0x{self.egl.eglGetError():04x})")
        pbuf_attrs = (C.c_int * 5)(EGL_WIDTH, self.width, EGL_HEIGHT, self.height, EGL_NONE)
        surf = self.egl.eglCreatePbufferSurface(dpy, config, pbuf_attrs)
        if not surf:
            die(f"eglCreatePbufferSurface failed (0x{self.egl.eglGetError():04x})")
        ctx_attrs = (C.c_int * 3)(EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE)
        ctx = self.egl.eglCreateContext(dpy, config, None, ctx_attrs)
        if not ctx:
            die(f"eglCreateContext GLES3 failed (0x{self.egl.eglGetError():04x})")
        if not self.egl.eglMakeCurrent(dpy, surf, surf, ctx):
            die(f"eglMakeCurrent failed (0x{self.egl.eglGetError():04x})")
        self.display, self.surface, self.context = dpy, surf, ctx

    def _bind_gl(self) -> None:
        g = self.gl
        g.glGetString.argtypes = [C.c_uint]; g.glGetString.restype = C.c_char_p
        g.glGetError.restype = C.c_uint
        g.glCreateShader.argtypes = [C.c_uint]; g.glCreateShader.restype = C.c_uint
        g.glShaderSource.argtypes = [C.c_uint, C.c_int, C.POINTER(C.c_char_p), C.POINTER(C.c_int)]
        g.glCompileShader.argtypes = [C.c_uint]
        g.glGetShaderiv.argtypes = [C.c_uint, C.c_uint, C.POINTER(C.c_int)]
        g.glGetShaderInfoLog.argtypes = [C.c_uint, C.c_int, C.POINTER(C.c_int), C.c_char_p]
        g.glDeleteShader.argtypes = [C.c_uint]
        g.glCreateProgram.restype = C.c_uint
        g.glAttachShader.argtypes = [C.c_uint, C.c_uint]
        g.glLinkProgram.argtypes = [C.c_uint]
        g.glGetProgramiv.argtypes = [C.c_uint, C.c_uint, C.POINTER(C.c_int)]
        g.glGetProgramInfoLog.argtypes = [C.c_uint, C.c_int, C.POINTER(C.c_int), C.c_char_p]
        g.glUseProgram.argtypes = [C.c_uint]
        g.glGetUniformLocation.argtypes = [C.c_uint, C.c_char_p]; g.glGetUniformLocation.restype = C.c_int
        g.glUniform1ui.argtypes = [C.c_int, C.c_uint]
        g.glGenTextures.argtypes = [C.c_int, C.POINTER(C.c_uint)]
        g.glBindTexture.argtypes = [C.c_uint, C.c_uint]
        g.glTexParameteri.argtypes = [C.c_uint, C.c_uint, C.c_int]
        g.glTexImage2D.argtypes = [C.c_uint, C.c_int, C.c_int, C.c_int, C.c_int, C.c_int, C.c_uint, C.c_uint, C.c_void_p]
        g.glGenFramebuffers.argtypes = [C.c_int, C.POINTER(C.c_uint)]
        g.glBindFramebuffer.argtypes = [C.c_uint, C.c_uint]
        g.glFramebufferTexture2D.argtypes = [C.c_uint, C.c_uint, C.c_uint, C.c_uint, C.c_int]
        g.glCheckFramebufferStatus.argtypes = [C.c_uint]; g.glCheckFramebufferStatus.restype = C.c_uint
        g.glViewport.argtypes = [C.c_int, C.c_int, C.c_int, C.c_int]
        g.glClear.argtypes = [C.c_uint]
        g.glDrawArrays.argtypes = [C.c_uint, C.c_int, C.c_int]
        g.glFinish.argtypes = []
        g.glReadPixels.argtypes = [C.c_int, C.c_int, C.c_int, C.c_int, C.c_uint, C.c_uint, C.c_void_p]
        g.glDisable.argtypes = [C.c_uint]
        # ES3 VAO functions are exported by Mesa GLESv2.
        if hasattr(g, "glGenVertexArrays"):
            g.glGenVertexArrays.argtypes = [C.c_int, C.POINTER(C.c_uint)]
            g.glBindVertexArray.argtypes = [C.c_uint]
            vao = C.c_uint()
            g.glGenVertexArrays(1, C.byref(vao)); g.glBindVertexArray(vao.value)
            self.vao = vao.value

    def _egl_string(self, which: int) -> str:
        p = self.egl.eglQueryString(self.display, which)
        return p.decode("utf-8", "replace") if p else "unknown"

    def _gl_string(self, which: int) -> str:
        p = self.gl.glGetString(which)
        return p.decode("utf-8", "replace") if p else "unknown"

    def _compile(self, kind: int, source: str) -> int:
        s = self.gl.glCreateShader(kind)
        src = C.c_char_p(source.encode())
        self.gl.glShaderSource(s, 1, C.byref(src), None)
        self.gl.glCompileShader(s)
        ok = C.c_int()
        self.gl.glGetShaderiv(s, GL_COMPILE_STATUS, C.byref(ok))
        if not ok.value:
            n = C.c_int(); self.gl.glGetShaderiv(s, GL_INFO_LOG_LENGTH, C.byref(n))
            buf = C.create_string_buffer(max(1, n.value))
            self.gl.glGetShaderInfoLog(s, len(buf), None, buf)
            die(f"shader compile failed: {buf.value.decode(errors='replace')}")
        return s

    def _program(self, vs_src: str, fs_src: str) -> tuple[int, int, int]:
        vs = self._compile(GL_VERTEX_SHADER, vs_src)
        fs = self._compile(GL_FRAGMENT_SHADER, fs_src)
        p = self.gl.glCreateProgram()
        self.gl.glAttachShader(p, vs); self.gl.glAttachShader(p, fs); self.gl.glLinkProgram(p)
        ok = C.c_int(); self.gl.glGetProgramiv(p, GL_LINK_STATUS, C.byref(ok))
        self.gl.glDeleteShader(vs); self.gl.glDeleteShader(fs)
        if not ok.value:
            n = C.c_int(); self.gl.glGetProgramiv(p, GL_INFO_LOG_LENGTH, C.byref(n))
            buf = C.create_string_buffer(max(1, n.value))
            self.gl.glGetProgramInfoLog(p, len(buf), None, buf)
            die(f"program link failed: {buf.value.decode(errors='replace')}")
        seed_loc = self.gl.glGetUniformLocation(p, b"uSeed")
        rounds_loc = self.gl.glGetUniformLocation(p, b"uRounds")
        if seed_loc < 0 or rounds_loc < 0:
            die("shader uniforms were optimized away unexpectedly")
        return p, seed_loc, rounds_loc

    def _make_target(self, internal_fmt: int, read_fmt: int) -> tuple[int, int, int]:
        tex = C.c_uint(); fbo = C.c_uint()
        self.gl.glGenTextures(1, C.byref(tex)); self.gl.glBindTexture(GL_TEXTURE_2D, tex.value)
        for pname, val in ((GL_TEXTURE_MIN_FILTER, GL_NEAREST), (GL_TEXTURE_MAG_FILTER, GL_NEAREST),
                           (GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE), (GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)):
            self.gl.glTexParameteri(GL_TEXTURE_2D, pname, val)
        self.gl.glTexImage2D(GL_TEXTURE_2D, 0, internal_fmt, self.width, self.height, 0,
                             read_fmt, GL_UNSIGNED_BYTE, None)
        self.gl.glGenFramebuffers(1, C.byref(fbo)); self.gl.glBindFramebuffer(GL_FRAMEBUFFER, fbo.value)
        self.gl.glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tex.value, 0)
        status = self.gl.glCheckFramebufferStatus(GL_FRAMEBUFFER)
        if status != GL_FRAMEBUFFER_COMPLETE:
            die(f"framebuffer incomplete: 0x{status:04x}")
        return tex.value, fbo.value, read_fmt

    def render(self, workload: str, seed: int, rounds: int) -> bytes:
        program, seed_loc, rounds_loc = self.programs[workload]
        _tex, fbo, read_fmt = self.fbos[workload]
        self.gl.glBindFramebuffer(GL_FRAMEBUFFER, fbo)
        self.gl.glViewport(0, 0, self.width, self.height)
        self.gl.glUseProgram(program)
        self.gl.glUniform1ui(seed_loc, seed & 0xFFFFFFFF)
        self.gl.glUniform1ui(rounds_loc, rounds)
        self.gl.glClear(GL_COLOR_BUFFER_BIT)
        self.gl.glDrawArrays(GL_TRIANGLES, 0, 3)
        self.gl.glFinish()
        n = self.width * self.height * 4
        out = (C.c_ubyte * n)()
        self.gl.glReadPixels(0, 0, self.width, self.height, read_fmt, GL_UNSIGNED_BYTE, out)
        err = self.gl.glGetError()
        if err != GL_NO_ERROR:
            die(f"glReadPixels/render error: 0x{err:04x}")
        return bytes(out)


def tile_hashes(buf: bytes, width: int, height: int, tile: int) -> list[str]:
    stride = width * 4
    out: list[str] = []
    for ty in range(0, height, tile):
        th = min(tile, height - ty)
        for tx in range(0, width, tile):
            tw = min(tile, width - tx)
            h = hashlib.sha256()
            start_x = tx * 4
            end_x = start_x + tw * 4
            for y in range(ty, ty + th):
                row = y * stride
                h.update(buf[row + start_x: row + end_x])
            out.append(h.hexdigest())
    return out


def fingerprint(buf: bytes, width: int, height: int, tile: int) -> dict:
    return {
        "sha256": hashlib.sha256(buf).hexdigest(),
        "tiles": tile_hashes(buf, width, height, tile),
    }


def render_suite(ctx: EGLGLES, passes: int, rounds: int, tile: int) -> dict[str, list[dict]]:
    result: dict[str, list[dict]] = {"int": [], "fpq": []}
    for workload in ("int", "fpq"):
        for p in range(passes):
            seed = (0x243F6A88 + p * 0x9E3779B9 + (0xA5A5A5A5 if workload == "fpq" else 0)) & 0xFFFFFFFF
            t0 = time.monotonic()
            buf = ctx.render(workload, seed, rounds)
            fp = fingerprint(buf, ctx.width, ctx.height, tile)
            fp["seed"] = seed
            fp["seconds"] = round(time.monotonic() - t0, 4)
            result[workload].append(fp)
            info(f"{workload} pass {p+1}/{passes}: {fp['sha256'][:16]} ({fp['seconds']}s)")
    return result


def compare_suite(ref: dict, got: dict, width: int, height: int, tile: int) -> tuple[int, list[str]]:
    mismatches = 0
    details: list[str] = []
    tiles_x = (width + tile - 1) // tile
    for workload in ("int", "fpq"):
        for i, (r, g) in enumerate(zip(ref[workload], got[workload])):
            if r["sha256"] == g["sha256"]:
                continue
            mismatches += 1
            bad_tiles = [j for j, (a, b) in enumerate(zip(r["tiles"], g["tiles"])) if a != b]
            coords = [f"({(j % tiles_x)*tile},{(j // tiles_x)*tile})" for j in bad_tiles[:12]]
            details.append(
                f"{workload} pass {i+1}: frame hash differs; bad_tiles={len(bad_tiles)} "
                f"first={','.join(coords) if coords else 'unknown'}"
            )
    return mismatches, details


def main() -> int:
    ap = argparse.ArgumentParser(description="BC-250 offscreen graphics corruption detector")
    ap.add_argument("mode", choices=["baseline", "verify", "info"])
    default_state = os.environ.get("BC250_STATE_DIR")
    if not default_state:
        default_state = ("/home/.steamos/offload/var/lib/bc250-wgp-lab"
                         if shutil.which("steamos-readonly") else "/var/lib/bc250-probe")
    ap.add_argument("--reference", default=os.path.join(default_state, "gfx-reference.json"))
    ap.add_argument("--width", type=int, default=int(os.getenv("BC250_GFX_WIDTH", "512")))
    ap.add_argument("--height", type=int, default=int(os.getenv("BC250_GFX_HEIGHT", "512")))
    ap.add_argument("--passes", type=int, default=int(os.getenv("BC250_GFX_PASSES", "6")))
    ap.add_argument("--rounds", type=int, default=int(os.getenv("BC250_GFX_ROUNDS", "64")))
    ap.add_argument("--tile", type=int, default=int(os.getenv("BC250_GFX_TILE", "64")))
    ap.add_argument("--repeats", type=int, default=int(os.getenv("BC250_GFX_REPEATS", "16")))
    ap.add_argument("--min-seconds", type=float, default=float(os.getenv("BC250_GFX_MIN_SECONDS", "4")))
    ap.add_argument("--allow-software", action="store_true")
    args = ap.parse_args()
    for n, v in (("width", args.width), ("height", args.height), ("passes", args.passes),
                 ("rounds", args.rounds), ("tile", args.tile), ("repeats", args.repeats),
                 ("min-seconds", args.min_seconds)):
        if v < 1:
            die(f"--{n} must be >= 1")

    ctx = EGLGLES(args.width, args.height)
    info(f"renderer: {ctx.renderer}")
    info(f"GL: {ctx.gl_version}; GLSL: {ctx.glsl_version}")
    info(f"EGL: {ctx.egl_vendor} {ctx.egl_version} (surfaceless pbuffer)")
    low = (ctx.renderer + " " + ctx.vendor).lower()
    if not args.allow_software and any(x in low for x in ("llvmpipe", "softpipe", "swrast")):
        die("software renderer detected; refusing because this would not test the BC-250 GPU")
    if args.mode == "info":
        return 0

    ref_path = Path(args.reference)
    config = {"width": args.width, "height": args.height, "passes": args.passes,
              "rounds": args.rounds, "tile": args.tile, "workloads": ["int", "fpq"]}

    if args.mode == "baseline":
        info("generating stock graphics reference")
        first = render_suite(ctx, args.passes, args.rounds, args.tile)
        info("self-checking stock reference with a second identical render")
        second = render_suite(ctx, args.passes, args.rounds, args.tile)
        bad, details = compare_suite(first, second, args.width, args.height, args.tile)
        if bad:
            for d in details: info("SELF-CHECK MISMATCH: " + d)
            die("stock rendering is not deterministic/clean; reference NOT written", 3)
        payload = {
            "version": 2,
            "created": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
            "renderer": ctx.renderer,
            "vendor": ctx.vendor,
            "gl_version": ctx.gl_version,
            "glsl_version": ctx.glsl_version,
            "config": config,
            "frames": first,
        }
        ref_path.parent.mkdir(parents=True, exist_ok=True)
        tmp = ref_path.with_suffix(ref_path.suffix + ".tmp")
        tmp.write_text(json.dumps(payload, indent=2) + "\n")
        os.replace(tmp, ref_path)
        info(f"BASELINE PASS: deterministic reference written to {ref_path}")
        return 0

    if not ref_path.is_file():
        die(f"reference missing: {ref_path}; run graphics baseline first")
    ref = json.loads(ref_path.read_text())
    if ref.get("version") != 2:
        die("unsupported reference version")
    if ref.get("config") != config:
        die(f"reference config {ref.get('config')} differs from requested {config}; regenerate baseline")
    if ref.get("renderer") != ctx.renderer:
        die(f"renderer changed since baseline: '{ref.get('renderer')}' -> '{ctx.renderer}'; regenerate baseline")

    total_bad = 0
    all_details: list[str] = []
    started = time.monotonic()
    r = 0
    while r < args.repeats or (time.monotonic() - started) < args.min_seconds:
        r += 1
        info(f"verification repeat {r} (minimum repeats={args.repeats}, minimum time={args.min_seconds:g}s)")
        got = render_suite(ctx, args.passes, args.rounds, args.tile)
        bad, details = compare_suite(ref["frames"], got, args.width, args.height, args.tile)
        total_bad += bad
        all_details.extend([f"repeat {r}: {d}" for d in details])
    if total_bad:
        for d in all_details[:40]: info("MISMATCH: " + d)
        info(f"FAIL: {total_bad} rendered frame(s) differed from the known-good stock reference")
        return 2
    info("PASS: all offscreen graphics frames match the known-good stock reference exactly")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
