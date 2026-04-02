#ifndef RC_COMMON_GLSL
#define RC_COMMON_GLSL

// ============================================================================
// rc_common.glsl — Radiance Cascades 3D shared constants and helpers
//
// Implements Alexander Sannikov's Radiance Cascades in 3D for Minecraft.
// Key insight: higher cascades have fewer probes but more ray directions,
// lower cascades have more probes but fewer directions. Merging top-to-bottom
// propagates far-field radiance into near-field probes.
// ============================================================================

#include "../include/common.glsl"

// Cascade configuration
#define RC_NUM_CASCADES      6    // cascade levels 0..5
#define RC_CASCADE0_GRID     64   // probe grid size for cascade 0 per axis
#define RC_CASCADE0_DIRS     8    // ray directions for cascade 0 (per hemisphere axis)
#define RC_BRANCHING_FACTOR  2    // each cascade doubles dirs, halves probes

// Derived constants
// Cascade n:
//   probeGrid  = RC_CASCADE0_GRID >> n     (halves each level)
//   numDirs    = RC_CASCADE0_DIRS << n      (doubles each level)
//   interval   = [2^n - 1, 2^(n+1) - 1] blocks (geometric intervals)

// World coverage: cascade 0 covers RC_CASCADE0_GRID blocks per axis (64),
// centered on the player. Higher cascades cover the same volume but with
// fewer, more widely spaced probes.

// Total directions per cascade for spherical coverage:
// We use octahedral direction mapping. For cascade n:
//   dirs_per_axis = RC_CASCADE0_DIRS << n
//   total_dirs = dirs_per_axis * dirs_per_axis (octahedral map)

// Atlas texture layout:
// Each cascade stored as a 2D texture atlas.
// Dimensions: (probeGrid * dirsPerAxis) x (probeGrid * probeGrid * dirsPerAxis)
// This is a direction-first layout: directions are the fast-varying dimension
// for better cache coherence during merge.

// Cascade parameters
struct CascadeParams {
    int   probeGridSize;   // probes per axis
    int   numDirsPerAxis;  // direction samples per octahedral axis
    float intervalStart;   // min ray distance (blocks)
    float intervalEnd;     // max ray distance (blocks)
    float probeSpacing;    // world units between probes
};

CascadeParams getCascadeParams(int cascadeLevel) {
    CascadeParams p;
    p.probeGridSize  = RC_CASCADE0_GRID >> cascadeLevel;
    p.numDirsPerAxis = RC_CASCADE0_DIRS << cascadeLevel;

    // Geometric intervals: cascade n traces from 2^n - 1 to 2^(n+1) - 1
    // This ensures each cascade covers a distinct distance range
    float scale = float(1 << cascadeLevel);
    p.intervalStart = scale - 1.0;
    p.intervalEnd   = scale * 2.0 - 1.0;

    // Probe spacing = world coverage / probe count
    // Coverage is always RC_CASCADE0_GRID blocks centered on player
    p.probeSpacing = float(RC_CASCADE0_GRID) / float(p.probeGridSize);

    return p;
}

// World position of a probe in a given cascade
vec3 probeWorldPos(ivec3 probeIdx, int cascadeLevel, vec3 playerPos) {
    CascadeParams p = getCascadeParams(cascadeLevel);
    // Center the grid on the player, snapped to probe spacing
    vec3 gridOrigin = floor(playerPos / p.probeSpacing) * p.probeSpacing
                    - float(p.probeGridSize / 2) * p.probeSpacing;
    return gridOrigin + (vec3(probeIdx) + 0.5) * p.probeSpacing;
}

// Direction from octahedral index
vec3 dirFromOctIndex(ivec2 dirIdx, int dirsPerAxis) {
    // Map integer index to [-1, 1] octahedral coordinates
    vec2 oct = (vec2(dirIdx) + 0.5) / float(dirsPerAxis) * 2.0 - 1.0;

    // Octahedral decode to unit sphere direction
    vec3 d = vec3(oct.xy, 1.0 - abs(oct.x) - abs(oct.y));
    if (d.z < 0.0) {
        d.xy = (1.0 - abs(d.yx)) * vec2(d.x >= 0.0 ? 1.0 : -1.0,
                                          d.y >= 0.0 ? 1.0 : -1.0);
    }
    return normalize(d);
}

// Octahedral index from direction (for lookups)
ivec2 octIndexFromDir(vec3 dir, int dirsPerAxis) {
    // Encode direction to octahedral [-1, 1]
    dir /= (abs(dir.x) + abs(dir.y) + abs(dir.z));
    if (dir.z < 0.0) {
        dir.xy = (1.0 - abs(dir.yx)) * vec2(dir.x >= 0.0 ? 1.0 : -1.0,
                                              dir.y >= 0.0 ? 1.0 : -1.0);
    }
    vec2 oct = dir.xy * 0.5 + 0.5; // [0, 1]
    ivec2 idx = ivec2(oct * float(dirsPerAxis));
    return clamp(idx, ivec2(0), ivec2(dirsPerAxis - 1));
}

// Atlas coordinate for a given probe + direction in a cascade
// Returns the texel position in the 2D atlas texture
ivec2 atlasCoord(ivec3 probeIdx, ivec2 dirIdx, int cascadeLevel) {
    CascadeParams p = getCascadeParams(cascadeLevel);

    // Direction-first layout:
    // x = probeIdx.x * dirsPerAxis + dirIdx.x
    // y = (probeIdx.z * probeGridSize + probeIdx.y) * dirsPerAxis + dirIdx.y
    int ax = probeIdx.x * p.numDirsPerAxis + dirIdx.x;
    int ay = (probeIdx.z * p.probeGridSize + probeIdx.y) * p.numDirsPerAxis + dirIdx.y;

    return ivec2(ax, ay);
}

// Atlas texture dimensions for a given cascade
ivec2 atlasSize(int cascadeLevel) {
    CascadeParams p = getCascadeParams(cascadeLevel);
    return ivec2(
        p.probeGridSize * p.numDirsPerAxis,
        p.probeGridSize * p.probeGridSize * p.numDirsPerAxis
    );
}

// Cascade atlas textures — one per cascade level
layout(set = 2, binding = 0, rgba16f) uniform image2D rcCascadeAtlas[RC_NUM_CASCADES];

// Player position for centering cascades (updated each frame)
layout(set = 2, binding = 6) uniform RCUniforms {
    vec3  playerPosition;
    int   updateCascade;    // which cascade to update this frame
    float cascadeBlend;     // temporal blending factor for updated cascade
} rcParams;

#endif // RC_COMMON_GLSL
