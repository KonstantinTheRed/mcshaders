#version 460
#extension GL_EXT_ray_tracing : require
#extension GL_EXT_ray_tracing_position_fetch : enable
#extension GL_GOOGLE_include_directive : enable

// ============================================================================
// closesthit.rchit — Closest-hit shader for primary and reflection rays
//
// Extracts hit position, normal, albedo, and material from the block
// geometry. The instance custom index encodes the material category.
// Block texture sampling uses the block ID to index into the texture atlas.
// ============================================================================

#include "../include/common.glsl"

// Hit attributes from intersection (barycentric coordinates)
hitAttributeEXT vec2 baryCoord;

// Ray payload output
layout(location = 0) rayPayloadInEXT struct RayPayload {
    vec3  hitPosition;
    vec3  hitNormal;
    vec3  albedo;
    uint  materialCategory;
    float hitDistance;
    bool  isMiss;
} payload;

// Block texture atlas
layout(set = 6, binding = 0) uniform sampler2D blockTextureAtlas;

// Per-instance data: maps geometry instance to block type
struct BlockInstance {
    uint  blockID;
    uint  materialCategory;
    vec4  texCoordOffset; // xy = atlas offset, zw = atlas tile size
};

layout(set = 6, binding = 1, std430) readonly buffer InstanceData {
    BlockInstance instances[];
} instanceData;

void main() {
    // Compute hit position
    vec3 hitWorld = gl_WorldRayOriginEXT + gl_WorldRayDirectionEXT * gl_HitTEXT;

    // Barycentric interpolation for triangle attributes
    vec3 bary = vec3(1.0 - baryCoord.x - baryCoord.y, baryCoord.x, baryCoord.y);

    // Fetch vertex positions to compute geometric normal
    // (using GL_EXT_ray_tracing_position_fetch)
    vec3 v0 = gl_HitTriangleVertexPositionsEXT[0];
    vec3 v1 = gl_HitTriangleVertexPositionsEXT[1];
    vec3 v2 = gl_HitTriangleVertexPositionsEXT[2];

    vec3 edge1 = v1 - v0;
    vec3 edge2 = v2 - v0;
    vec3 geometricNormal = normalize(cross(edge1, edge2));

    // For Minecraft blocks, normals are axis-aligned — snap to nearest axis
    vec3 absN = abs(geometricNormal);
    if (absN.x > absN.y && absN.x > absN.z) {
        geometricNormal = vec3(sign(geometricNormal.x), 0.0, 0.0);
    } else if (absN.y > absN.z) {
        geometricNormal = vec3(0.0, sign(geometricNormal.y), 0.0);
    } else {
        geometricNormal = vec3(0.0, 0.0, sign(geometricNormal.z));
    }

    // Ensure normal faces the ray (for back-face handling)
    if (dot(geometricNormal, gl_WorldRayDirectionEXT) > 0.0) {
        geometricNormal = -geometricNormal;
    }

    // Instance data for block type
    uint instanceIdx = gl_InstanceCustomIndexEXT;
    BlockInstance blockInst = instanceData.instances[instanceIdx];

    // Compute texture coordinates from hit position
    // For axis-aligned blocks, UVs come from the two non-normal axes
    vec2 texUV;
    if (abs(geometricNormal.x) > 0.5) {
        texUV = fract(hitWorld.zy);
    } else if (abs(geometricNormal.y) > 0.5) {
        texUV = fract(hitWorld.xz);
    } else {
        texUV = fract(hitWorld.xy);
    }

    // Map to atlas position
    vec2 atlasUV = blockInst.texCoordOffset.xy + texUV * blockInst.texCoordOffset.zw;
    vec4 texColor = texture(blockTextureAtlas, atlasUV);

    // Fill payload
    payload.hitPosition = hitWorld;
    payload.hitNormal = geometricNormal;
    payload.albedo = texColor.rgb;
    payload.materialCategory = blockInst.materialCategory;
    payload.hitDistance = gl_HitTEXT;
    payload.isMiss = false;
}
