#version 460
#extension GL_EXT_ray_tracing : require
#extension GL_GOOGLE_include_directive : enable

// ============================================================================
// miss.rmiss — Miss shader for rays that don't hit any geometry
// Returns sky color based on ray direction.
// ============================================================================

#include "../include/common.glsl"

layout(location = 0) rayPayloadInEXT struct RayPayload {
    vec3  hitPosition;
    vec3  hitNormal;
    vec3  albedo;
    uint  materialCategory;
    float hitDistance;
    bool  isMiss;
} payload;

void main() {
    vec3 dir = normalize(gl_WorldRayDirectionEXT);

    // Procedural sky color
    float sunDot = max(dot(dir, frame.sunDirection.xyz), 0.0);
    float moonDot = max(dot(dir, frame.moonDirection.xyz), 0.0);

    // Rayleigh-inspired sky gradient
    float altitude = dir.y * 0.5 + 0.5;
    vec3 zenith = vec3(0.25, 0.45, 1.0);
    vec3 horizon = vec3(0.6, 0.75, 1.0);
    vec3 sky = mix(horizon, zenith, pow(altitude, 0.5));

    // Sun glow
    sky += vec3(1.0, 0.9, 0.7) * pow(sunDot, 256.0) * 10.0; // sun disk
    sky += vec3(1.0, 0.8, 0.5) * pow(sunDot, 8.0) * 0.5;    // halo

    // Moon glow
    sky += vec3(0.7, 0.8, 1.0) * pow(moonDot, 256.0) * 2.0;

    // Scale by time of day
    sky *= frame.skyLightLevel / 15.0;

    payload.hitPosition = gl_WorldRayOriginEXT + dir * 10000.0;
    payload.hitNormal = -dir;
    payload.albedo = sky;
    payload.materialCategory = MAT_SKY;
    payload.hitDistance = gl_RayTmaxEXT;
    payload.isMiss = true;
}
