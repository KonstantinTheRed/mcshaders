#ifndef SHARC_CACHE_GLSL
#define SHARC_CACHE_GLSL

// ============================================================================
// sharc_cache.glsl — SHaRC (Spatially Hashed Radiance Cache)
//
// Primary GI system for Minecraft. Persistent world-space radiance cache.
// Light propagates one bounce per frame via the "echo chamber" — after N
// frames, light has bounced N times with only 1 bounce of GPU cost per frame.
//
// Mitigations implemented:
//   - Normal-octant hashing: prevents light leaking through thin walls
//   - 4M entry table: matches C++ allocation, reduces collisions
//   - Age-priority eviction: evicts oldest entry when table is full
//   - Trilinear interpolation: smooth sub-block lighting gradients
//   - Reduced MAX_AGE=16: faster adaptation to lighting changes
// ============================================================================

#include "../include/common.glsl"
#include "../include/noise.glsl"

// Hash table configuration — matches C++ sharcCapacity = 1u << 22
#define SHARC_HASH_TABLE_SIZE 4194304u  // 4M entries
#define SHARC_MAX_AGE         16u       // frames before eviction (fast adaptation)
#define SHARC_STALE_FRAMES    4u        // frames before decay begins
#define SHARC_GRID_SCALE      1.0       // 1 cell = 1 Minecraft block
#define SHARC_MAX_SAMPLES     32.0      // EMA sample cap
#define SHARC_PROBE_STEPS     8u        // linear probe window

// Hash table SSBOs
layout(set = 7, binding = 0, std430) buffer SharcHashTable {
    uint  keys[];
} sharcKeys;

layout(set = 7, binding = 1, std430) buffer SharcRadiance {
    vec4  entries[];       // xyz = radiance (accumulated), w = sampleCount
} sharcRadiance;

layout(set = 7, binding = 2, std430) buffer SharcAge {
    uint  frameStamps[];
} sharcAge;

// ── Normal-octant hashing ────────────────────────────────────────────
// Encodes the dominant normal direction into the hash key so opposing
// faces of a 1-block wall get different cache entries.
// 6 octants: +X, -X, +Y, -Y, +Z, -Z
uint normalOctant(vec3 normal) {
    vec3 a = abs(normal);
    if (a.x > a.y && a.x > a.z) return normal.x > 0.0 ? 0u : 1u;
    if (a.y > a.z)               return normal.y > 0.0 ? 2u : 3u;
    return                               normal.z > 0.0 ? 4u : 5u;
}

// Hash world position + normal octant to a cache key
uint sharcHashPosition(vec3 worldPos, vec3 normal) {
    ivec3 gridPos = ivec3(floor(worldPos * SHARC_GRID_SCALE));
    uint h = spatialHash(gridPos);
    // Mix normal octant into hash — different faces get different entries
    h ^= normalOctant(normal) * 2654435761u;
    return h;
}

// Legacy overload (no normal — for backward compat with existing callers)
uint sharcHashPosition(vec3 worldPos) {
    ivec3 gridPos = ivec3(floor(worldPos * SHARC_GRID_SCALE));
    return spatialHash(gridPos);
}

// ── Slot management with age-priority eviction ───────────────────────
uint sharcFindSlot(uint hashKey) {
    uint baseSlot = hashKey % SHARC_HASH_TABLE_SIZE;
    uint oldestSlot = baseSlot;
    uint oldestAge = 0u;

    for (uint i = 0u; i < SHARC_PROBE_STEPS; i++) {
        uint slot = (baseSlot + i) % SHARC_HASH_TABLE_SIZE;
        uint existing = sharcKeys.keys[slot];

        if (existing == hashKey) return slot;

        if (existing == 0u) {
            uint prev = atomicCompSwap(sharcKeys.keys[slot], 0u, hashKey);
            if (prev == 0u || prev == hashKey) return slot;
        }

        // Track oldest for eviction
        uint age = uint(frame.frameCount) - sharcAge.frameStamps[slot];
        if (age > oldestAge) {
            oldestAge = age;
            oldestSlot = slot;
        }
    }

    // All slots occupied — evict oldest if it's old enough
    if (oldestAge > SHARC_STALE_FRAMES) {
        sharcKeys.keys[oldestSlot] = hashKey;
        sharcRadiance.entries[oldestSlot] = vec4(0.0, 0.0, 0.0, 0.0);
        sharcAge.frameStamps[oldestSlot] = uint(frame.frameCount);
        return oldestSlot;
    }

    return 0xFFFFFFFFu;
}

// ── Single-cell cache read ───────────────────────────────────────────
bool sharcGetCachedRadianceSingle(vec3 worldPos, vec3 normal, out vec3 radiance) {
    uint hashKey = sharcHashPosition(worldPos, normal);
    uint baseSlot = hashKey % SHARC_HASH_TABLE_SIZE;

    for (uint i = 0u; i < SHARC_PROBE_STEPS; i++) {
        uint slot = (baseSlot + i) % SHARC_HASH_TABLE_SIZE;
        if (sharcKeys.keys[slot] == hashKey) {
            vec4 entry = sharcRadiance.entries[slot];
            uint age = sharcAge.frameStamps[slot];

            if (entry.w > 0.0 &&
                (uint(frame.frameCount) - age) < SHARC_MAX_AGE) {
                radiance = entry.xyz / entry.w;
                sharcAge.frameStamps[slot] = uint(frame.frameCount);
                return true;
            }
            return false;
        }
        if (sharcKeys.keys[slot] == 0u) return false;
    }
    return false;
}

// ── Trilinear interpolated cache read ────────────────────────────────
// Reads 8 neighboring cells and blends based on sub-block position.
// Produces smooth lighting gradients across block boundaries.
bool sharcGetCachedRadiance(vec3 worldPos, vec3 normal, out vec3 radiance) {
    vec3 cellPos = worldPos * SHARC_GRID_SCALE;
    vec3 frac = fract(cellPos) - 0.5;
    vec3 base = floor(cellPos) / SHARC_GRID_SCALE;

    vec3 total = vec3(0.0);
    float totalWeight = 0.0;

    for (int dz = 0; dz <= 1; dz++)
    for (int dy = 0; dy <= 1; dy++)
    for (int dx = 0; dx <= 1; dx++) {
        vec3 cellWorld = base + vec3(dx, dy, dz) / SHARC_GRID_SCALE + 0.5 / SHARC_GRID_SCALE;
        vec3 cached;
        if (sharcGetCachedRadianceSingle(cellWorld, normal, cached)) {
            vec3 d = abs(frac - vec3(dx, dy, dz));
            float w = (1.0 - d.x) * (1.0 - d.y) * (1.0 - d.z);
            total += cached * w;
            totalWeight += w;
        }
    }

    if (totalWeight > 0.01) {
        radiance = total / totalWeight;
        return true;
    }
    return false;
}

// Legacy overload without normal (falls back to nearest, no octant)
bool sharcGetCachedRadiance(vec3 worldPos, out vec3 radiance) {
    uint hashKey = sharcHashPosition(worldPos);
    uint baseSlot = hashKey % SHARC_HASH_TABLE_SIZE;

    for (uint i = 0u; i < SHARC_PROBE_STEPS; i++) {
        uint slot = (baseSlot + i) % SHARC_HASH_TABLE_SIZE;
        if (sharcKeys.keys[slot] == hashKey) {
            vec4 entry = sharcRadiance.entries[slot];
            uint age = sharcAge.frameStamps[slot];

            if (entry.w > 0.0 &&
                (uint(frame.frameCount) - age) < SHARC_MAX_AGE) {
                radiance = entry.xyz / entry.w;
                sharcAge.frameStamps[slot] = uint(frame.frameCount);
                return true;
            }
            return false;
        }
        if (sharcKeys.keys[slot] == 0u) return false;
    }
    return false;
}

// ── Cache update (the echo) ──────────────────────────────────────────
// Writes radiance to the cache using exponential moving average.
// Energy conservation: caller must multiply indirect by albedo before calling.
void sharcUpdateEntry(vec3 worldPos, vec3 normal, vec3 radiance) {
    uint hashKey = sharcHashPosition(worldPos, normal);
    uint slot = sharcFindSlot(hashKey);

    if (slot == 0xFFFFFFFFu) return;

    // Clamp input to prevent fireflies propagating through cache
    float lum = dot(radiance, vec3(0.2126, 0.7152, 0.0722));
    if (lum > 20.0) radiance *= 20.0 / lum;

    vec4 existing = sharcRadiance.entries[slot];
    uint age = sharcAge.frameStamps[slot];

    if ((uint(frame.frameCount) - age) >= SHARC_MAX_AGE || existing.w <= 0.0) {
        // Fresh entry
        sharcRadiance.entries[slot] = vec4(radiance, 1.0);
    } else {
        // Exponential moving average
        float count = min(existing.w + 1.0, SHARC_MAX_SAMPLES);
        float alpha = 1.0 / count;
        vec3 blended = mix(existing.xyz / max(existing.w, 1.0), radiance, alpha);
        sharcRadiance.entries[slot] = vec4(blended * count, count);
    }

    sharcAge.frameStamps[slot] = uint(frame.frameCount);
}

// Legacy overload without normal
void sharcUpdateEntry(vec3 worldPos, vec3 radiance) {
    uint hashKey = sharcHashPosition(worldPos);
    uint slot = sharcFindSlot(hashKey);

    if (slot == 0xFFFFFFFFu) return;

    float lum = dot(radiance, vec3(0.2126, 0.7152, 0.0722));
    if (lum > 20.0) radiance *= 20.0 / lum;

    vec4 existing = sharcRadiance.entries[slot];
    uint age = sharcAge.frameStamps[slot];

    if ((uint(frame.frameCount) - age) >= SHARC_MAX_AGE || existing.w <= 0.0) {
        sharcRadiance.entries[slot] = vec4(radiance, 1.0);
    } else {
        float count = min(existing.w + 1.0, SHARC_MAX_SAMPLES);
        float alpha = 1.0 / count;
        vec3 blended = mix(existing.xyz / max(existing.w, 1.0), radiance, alpha);
        sharcRadiance.entries[slot] = vec4(blended * count, count);
    }

    sharcAge.frameStamps[slot] = uint(frame.frameCount);
}

#endif // SHARC_CACHE_GLSL
