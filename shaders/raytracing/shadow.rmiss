#version 460
#extension GL_EXT_ray_tracing : require

// ============================================================================
// shadow.rmiss — Shadow ray miss shader
// If the shadow ray misses all geometry, the light is visible (not occluded).
// ============================================================================

layout(location = 1) rayPayloadInEXT bool isShadowed;

void main() {
    isShadowed = false;
}
