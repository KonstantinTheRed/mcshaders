#ifndef BLOCK_DATA_GLSL
#define BLOCK_DATA_GLSL

// ============================================================================
// block_data.glsl — Minecraft block data lookups and material properties
// ============================================================================

#include "common.glsl"

// Block data layout in SSBO:
//   bits [0..15]  = blockID (up to 65536 block types)
//   bits [16..19] = sky light level (0-15)
//   bits [20..23] = block light level (0-15)
//   bits [24..26] = material category (MAT_OPAQUE..MAT_SKY)
//   bit  [27]     = is emissive
//   bit  [28]     = is transparent (alpha < 1)
//   bit  [29]     = is full cube (vs. partial geometry like slabs/stairs)
//   bits [30..31] = reserved

// Chunk dimensions
#define CHUNK_SIZE_X 16
#define CHUNK_SIZE_Y 384   // Minecraft 1.18+ world height (-64 to 319)
#define CHUNK_SIZE_Z 16
#define CHUNK_Y_OFFSET 64  // blocks below y=0

// Voxel world SSBO — contains block data for loaded chunks
// Indexed via spatial hash of chunk position + local block offset
layout(set = 1, binding = 0, std430) readonly buffer VoxelWorld {
    uint blockData[];  // packed block entries
} voxelWorld;

// Chunk hash table — maps chunk (cx, cz) to index in blockData
#define CHUNK_TABLE_SIZE 4096u

struct ChunkEntry {
    ivec2 pos;     // (cx, cz)
    uint  offset;  // byte offset into blockData
    uint  padding;
};

layout(set = 1, binding = 1, std430) readonly buffer ChunkTable {
    uint       chunkCount;
    uint       pad0, pad1, pad2;
    ChunkEntry entries[CHUNK_TABLE_SIZE];
} chunkTable;

// Emissive block list for ReSTIR DI (rebuilt each frame)
struct EmissiveBlock {
    vec4 posAndRadius;  // xyz = world position (block center), w = influence radius
    vec4 colorAndPower; // rgb = emission color, a = power (light level * scale)
};

layout(set = 1, binding = 2, std430) readonly buffer EmissiveList {
    uint          emissiveCount;
    EmissiveBlock emissives[];
} emissiveList;

// Hash a chunk coordinate to a table index
uint chunkHash(int cx, int cz) {
    uint h = uint(cx) * 73856093u ^ uint(cz) * 83492791u;
    return h % CHUNK_TABLE_SIZE;
}

// Look up a chunk's data offset (returns 0xFFFFFFFF if not loaded)
uint findChunkOffset(int cx, int cz) {
    uint idx = chunkHash(cx, cz);
    // Linear probe (max 8 steps)
    for (uint i = 0u; i < 8u; i++) {
        uint slot = (idx + i) % CHUNK_TABLE_SIZE;
        if (chunkTable.entries[slot].pos.x == cx &&
            chunkTable.entries[slot].pos.y == cz) {
            return chunkTable.entries[slot].offset;
        }
    }
    return 0xFFFFFFFFu; // not found
}

// Get packed block data at a world position
uint getBlockPacked(ivec3 worldPos) {
    int cx = worldPos.x >> 4; // divide by 16
    int cz = worldPos.z >> 4;
    uint offset = findChunkOffset(cx, cz);
    if (offset == 0xFFFFFFFFu) return 0u; // air (unloaded)

    int lx = worldPos.x & 15; // mod 16
    int ly = worldPos.y + CHUNK_Y_OFFSET;
    int lz = worldPos.z & 15;

    if (ly < 0 || ly >= CHUNK_SIZE_Y) return 0u; // out of world bounds

    uint localIdx = uint(ly) * 256u + uint(lz) * 16u + uint(lx);
    return voxelWorld.blockData[offset + localIdx];
}

// Extract fields from packed block data
uint  blockID(uint packed)       { return packed & 0xFFFFu; }
uint  blockSkyLight(uint packed) { return (packed >> 16u) & 0xFu; }
uint  blockLight(uint packed)    { return (packed >> 20u) & 0xFu; }
uint  blockMaterial(uint packed) { return (packed >> 24u) & 0x7u; }
bool  blockIsEmissive(uint packed) { return (packed & (1u << 27u)) != 0u; }
bool  blockIsTransparent(uint packed) { return (packed & (1u << 28u)) != 0u; }
bool  blockIsFullCube(uint packed) { return (packed & (1u << 29u)) != 0u; }

// Check if a block position is solid (opaque or non-air)
bool isBlockSolid(ivec3 pos) {
    uint packed = getBlockPacked(pos);
    uint id = blockID(packed);
    return id != 0u && !blockIsTransparent(packed);
}

// Check if a block position is opaque (blocks light completely)
bool isBlockOpaque(ivec3 pos) {
    uint packed = getBlockPacked(pos);
    return blockID(packed) != 0u && blockIsFullCube(packed) && !blockIsTransparent(packed);
}

// Get emission color for an emissive block (from block ID lookup table)
// This would typically be populated from Minecraft's block registry
vec3 getBlockEmission(uint blockId) {
    // Common emissive blocks — hardcoded fallbacks
    // In production, this would be a texture lookup or SSBO table
    switch (blockId) {
        case 50u:   return vec3(1.0, 0.8, 0.5) * 14.0;  // torch
        case 51u:   return vec3(1.0, 0.6, 0.2) * 15.0;  // fire
        case 89u:   return vec3(1.0, 0.9, 0.6) * 15.0;  // glowstone
        case 91u:   return vec3(1.0, 0.7, 0.3) * 15.0;  // jack o lantern
        case 124u:  return vec3(1.0, 0.85, 0.6) * 15.0; // redstone lamp (on)
        case 169u:  return vec3(0.8, 0.95, 1.0) * 15.0; // sea lantern
        case 198u:  return vec3(0.7, 0.3, 1.0) * 12.0;  // end rod
        default:    return vec3(1.0, 0.9, 0.7) * 10.0;  // generic emissive
    }
}

#endif // BLOCK_DATA_GLSL
