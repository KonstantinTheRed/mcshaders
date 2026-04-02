#ifndef VOXEL_DDA_GLSL
#define VOXEL_DDA_GLSL

// ============================================================================
// voxel_dda.glsl — Digital Differential Analyzer for voxel grid traversal
// Exact integer-stepping through Minecraft's block grid.
// Zero approximation error, no BVH needed, excellent cache locality.
// ============================================================================

#include "common.glsl"
#include "block_data.glsl"

struct VoxelHit {
    bool  hit;          // did we hit a solid block?
    ivec3 blockPos;     // integer position of the hit block
    vec3  hitPoint;     // exact world-space intersection point
    vec3  normal;       // face normal at the hit point
    float distance;     // ray distance to hit
    uint  blockPacked;  // packed block data at hit position
};

// Core DDA traversal through the voxel grid
// origin: ray start in world space
// direction: normalized ray direction
// maxDist: maximum distance to trace
VoxelHit traceVoxelRay(vec3 origin, vec3 direction, float maxDist) {
    VoxelHit result;
    result.hit = false;
    result.distance = maxDist;

    // Current voxel position (integer)
    ivec3 mapPos = ivec3(floor(origin));

    // Step direction: +1 or -1 per axis
    ivec3 stepDir = ivec3(sign(direction));

    // Avoid division by zero — replace zero components with a large value
    vec3 invDir = vec3(
        abs(direction.x) > EPSILON ? 1.0 / direction.x : 1e30,
        abs(direction.y) > EPSILON ? 1.0 / direction.y : 1e30,
        abs(direction.z) > EPSILON ? 1.0 / direction.z : 1e30
    );

    // tDelta: how far along the ray (in t) to cross one full voxel per axis
    vec3 tDelta = abs(invDir);

    // tMax: t at which the ray crosses the next voxel boundary per axis
    vec3 tMax = vec3(
        (direction.x > 0.0 ? (float(mapPos.x + 1) - origin.x) : (origin.x - float(mapPos.x))) * abs(invDir.x),
        (direction.y > 0.0 ? (float(mapPos.y + 1) - origin.y) : (origin.y - float(mapPos.y))) * abs(invDir.y),
        (direction.z > 0.0 ? (float(mapPos.z + 1) - origin.z) : (origin.z - float(mapPos.z))) * abs(invDir.z)
    );

    // Track which axis we last stepped along (for face normal)
    int stepAxis = 0;
    float t = 0.0;

    // Maximum iterations to prevent infinite loops
    int maxSteps = int(maxDist * 1.8) + 4; // generous bound

    for (int i = 0; i < maxSteps && t < maxDist; i++) {
        // Check current block
        uint packed = getBlockPacked(mapPos);
        uint id = blockID(packed);

        if (id != 0u && !blockIsTransparent(packed)) {
            // Hit a solid block
            result.hit = true;
            result.blockPos = mapPos;
            result.hitPoint = origin + direction * t;
            result.distance = t;
            result.blockPacked = packed;

            // Face normal based on which axis we stepped
            result.normal = vec3(0.0);
            result.normal[stepAxis] = -float(stepDir[stepAxis]);

            return result;
        }

        // Advance to next voxel boundary (whichever axis is closest)
        if (tMax.x < tMax.y) {
            if (tMax.x < tMax.z) {
                t = tMax.x;
                mapPos.x += stepDir.x;
                tMax.x += tDelta.x;
                stepAxis = 0;
            } else {
                t = tMax.z;
                mapPos.z += stepDir.z;
                tMax.z += tDelta.z;
                stepAxis = 2;
            }
        } else {
            if (tMax.y < tMax.z) {
                t = tMax.y;
                mapPos.y += stepDir.y;
                tMax.y += tDelta.y;
                stepAxis = 1;
            } else {
                t = tMax.z;
                mapPos.z += stepDir.z;
                tMax.z += tDelta.z;
                stepAxis = 2;
            }
        }
    }

    return result;
}

// Simplified DDA for shadow rays — only needs to know hit/miss, not details
bool traceVoxelShadowRay(vec3 origin, vec3 direction, float maxDist) {
    ivec3 mapPos = ivec3(floor(origin));
    ivec3 stepDir = ivec3(sign(direction));

    vec3 invDir = vec3(
        abs(direction.x) > EPSILON ? 1.0 / direction.x : 1e30,
        abs(direction.y) > EPSILON ? 1.0 / direction.y : 1e30,
        abs(direction.z) > EPSILON ? 1.0 / direction.z : 1e30
    );

    vec3 tDelta = abs(invDir);
    vec3 tMax = vec3(
        (direction.x > 0.0 ? (float(mapPos.x + 1) - origin.x) : (origin.x - float(mapPos.x))) * abs(invDir.x),
        (direction.y > 0.0 ? (float(mapPos.y + 1) - origin.y) : (origin.y - float(mapPos.y))) * abs(invDir.y),
        (direction.z > 0.0 ? (float(mapPos.z + 1) - origin.z) : (origin.z - float(mapPos.z))) * abs(invDir.z)
    );

    float t = 0.0;
    int maxSteps = int(maxDist * 1.8) + 4;

    for (int i = 0; i < maxSteps && t < maxDist; i++) {
        uint packed = getBlockPacked(mapPos);
        if (blockID(packed) != 0u && !blockIsTransparent(packed)) {
            return true; // occluded
        }

        if (tMax.x < tMax.y) {
            if (tMax.x < tMax.z) {
                t = tMax.x; mapPos.x += stepDir.x; tMax.x += tDelta.x;
            } else {
                t = tMax.z; mapPos.z += stepDir.z; tMax.z += tDelta.z;
            }
        } else {
            if (tMax.y < tMax.z) {
                t = tMax.y; mapPos.y += stepDir.y; tMax.y += tDelta.y;
            } else {
                t = tMax.z; mapPos.z += stepDir.z; tMax.z += tDelta.z;
            }
        }
    }

    return false; // not occluded
}

// DDA with interval range — used by Radiance Cascades
// Only checks blocks between tMin and tMax along the ray
VoxelHit traceVoxelRayInterval(vec3 origin, vec3 direction, float tMin, float tMax_dist) {
    // Advance origin to the interval start
    vec3 intervalOrigin = origin + direction * tMin;
    VoxelHit result = traceVoxelRay(intervalOrigin, direction, tMax_dist - tMin);

    // Adjust distance to be relative to original origin
    if (result.hit) {
        result.distance += tMin;
        result.hitPoint = origin + direction * result.distance;
    } else {
        result.distance += tMin;
    }

    return result;
}

#endif // VOXEL_DDA_GLSL
