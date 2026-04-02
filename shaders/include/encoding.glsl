#ifndef ENCODING_GLSL
#define ENCODING_GLSL

// ============================================================================
// encoding.glsl — Normal encoding/decoding, color packing utilities
// ============================================================================

// Octahedral normal encoding (unit vec3 -> RG16F)
// Based on "Survey of Efficient Representations for Independent Unit Vectors"
vec2 octEncode(vec3 n) {
    n /= (abs(n.x) + abs(n.y) + abs(n.z));
    if (n.z < 0.0) {
        n.xy = (1.0 - abs(n.yx)) * vec2(n.x >= 0.0 ? 1.0 : -1.0,
                                          n.y >= 0.0 ? 1.0 : -1.0);
    }
    return n.xy * 0.5 + 0.5;
}

vec3 octDecode(vec2 e) {
    e = e * 2.0 - 1.0;
    vec3 n = vec3(e.xy, 1.0 - abs(e.x) - abs(e.y));
    if (n.z < 0.0) {
        n.xy = (1.0 - abs(n.yx)) * vec2(n.x >= 0.0 ? 1.0 : -1.0,
                                          n.y >= 0.0 ? 1.0 : -1.0);
    }
    return normalize(n);
}

// Note: packHalf2x16/unpackHalf2x16 are GLSL builtins — no wrapper needed

// Pack RGB into R11G11B10 (unsigned float)
uint packR11G11B10(vec3 rgb) {
    // Clamp to representable range
    rgb = clamp(rgb, vec3(0.0), vec3(65024.0));
    uint r = uint(rgb.r * 2047.0 / 65024.0) & 0x7FFu;
    uint g = uint(rgb.g * 2047.0 / 65024.0) & 0x7FFu;
    uint b = uint(rgb.b * 1023.0 / 65024.0) & 0x3FFu;
    return (r) | (g << 11u) | (b << 22u);
}

vec3 unpackR11G11B10(uint packed) {
    float r = float(packed & 0x7FFu) * 65024.0 / 2047.0;
    float g = float((packed >> 11u) & 0x7FFu) * 65024.0 / 2047.0;
    float b = float((packed >> 22u) & 0x3FFu) * 65024.0 / 1023.0;
    return vec3(r, g, b);
}

// Spherical coordinate encoding for directions
vec2 dirToSpherical(vec3 d) {
    return vec2(atan(d.z, d.x), acos(clamp(d.y, -1.0, 1.0)));
}

vec3 sphericalToDir(vec2 s) {
    float sinTheta = sin(s.y);
    return vec3(cos(s.x) * sinTheta, cos(s.y), sin(s.x) * sinTheta);
}

// Tangent-space basis from a normal (Frisvad's method, revised)
void buildTangentBasis(vec3 n, out vec3 t, out vec3 b) {
    if (n.z < -0.9999999) {
        t = vec3(0.0, -1.0, 0.0);
        b = vec3(-1.0, 0.0, 0.0);
        return;
    }
    float a = 1.0 / (1.0 + n.z);
    float d = -n.x * n.y * a;
    t = vec3(1.0 - n.x * n.x * a, d, -n.x);
    b = vec3(d, 1.0 - n.y * n.y * a, -n.y);
}

#endif // ENCODING_GLSL
