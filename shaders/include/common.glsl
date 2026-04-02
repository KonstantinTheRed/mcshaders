#ifndef COMMON_GLSL
#define COMMON_GLSL

// ============================================================================
// common.glsl — Shared constants, uniforms, and utility functions
// Next-Gen Minecraft Ray Tracing Shader
// ============================================================================

#define PI        3.14159265358979323846
#define TWO_PI    6.28318530717958647692
#define HALF_PI   1.57079632679489661923
#define INV_PI    0.31830988618379067154
#define INV_TWO_PI 0.15915494309189533577
#define EPSILON   1e-6
#define FLT_MAX   3.402823466e+38

// Block material categories (3 bits = 8 categories for SER coherence hint)
#define MAT_OPAQUE    0u
#define MAT_WATER     1u
#define MAT_GLASS     2u
#define MAT_EMISSIVE  3u
#define MAT_LEAVES    4u
#define MAT_METAL     5u
#define MAT_SUBSURFACE 6u
#define MAT_SKY       7u

// G-Buffer binding indices
#define GBUF_DEPTH_BINDING     0
#define GBUF_NORMAL_BINDING    1
#define GBUF_ALBEDO_BINDING    2
#define GBUF_MATERIAL_BINDING  3
#define GBUF_MOTION_BINDING    4

// Per-frame uniform data pushed to all shaders
layout(set = 0, binding = 0) uniform FrameUniforms {
    mat4  viewMatrix;
    mat4  projMatrix;
    mat4  invViewMatrix;
    mat4  invProjMatrix;
    mat4  prevViewMatrix;
    mat4  prevProjMatrix;
    vec4  cameraPos;          // xyz = position, w = time
    vec4  sunDirection;       // xyz = direction, w = sunIntensity
    vec4  moonDirection;      // xyz = direction, w = moonIntensity
    ivec4 screenSize;         // xy = resolution, zw = frame index (low, high)
    vec4  jitter;             // xy = TAA jitter, zw = reserved
    float nearPlane;
    float farPlane;
    float deltaTime;
    float totalTime;
    int   frameCount;
    int   cascadeUpdateIndex; // which RC cascade to update this frame
    float skyLightLevel;      // 0-15 Minecraft sky light
    float blockLightScale;    // user-configurable emissive intensity
} frame;

// Reconstruct world position from depth + screen UV
vec3 worldPosFromDepth(float depth, vec2 uv) {
    vec4 clipPos = vec4(uv * 2.0 - 1.0, depth, 1.0);
    vec4 viewPos = frame.invProjMatrix * clipPos;
    viewPos /= viewPos.w;
    return (frame.invViewMatrix * viewPos).xyz;
}

// Screen UV from world position (for reprojection)
vec2 uvFromWorldPos(vec3 worldPos, mat4 viewProj) {
    vec4 clip = viewProj * vec4(worldPos, 1.0);
    return clip.xy / clip.w * 0.5 + 0.5;
}

// Linear depth from hyperbolic depth buffer value
float linearizeDepth(float d) {
    return frame.nearPlane * frame.farPlane /
           (frame.farPlane - d * (frame.farPlane - frame.nearPlane));
}

// Luminance of an RGB color (Rec. 709)
float luminance(vec3 c) {
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

// Safe normalize that avoids NaN for zero-length vectors
vec3 safeNormalize(vec3 v) {
    float len = dot(v, v);
    return len > 0.0 ? v * inversesqrt(len) : vec3(0.0);
}

// Clamp to positive (used after lighting calculations)
vec3 clampPositive(vec3 v) {
    return max(v, vec3(0.0));
}

// Convert block coordinates to world-space center
vec3 blockCenter(ivec3 blockPos) {
    return vec3(blockPos) + 0.5;
}

#endif // COMMON_GLSL
