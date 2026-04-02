#ifndef RESERVOIR_GLSL
#define RESERVOIR_GLSL

// ============================================================================
// reservoir.glsl — ReSTIR DI reservoir data structures and operations
//
// Implements weighted reservoir sampling for direct illumination.
// Each pixel maintains a reservoir that stores a single light sample,
// refined through temporal and spatial reuse.
// Based on Bitterli et al. 2020 (SIGGRAPH).
// ============================================================================

#include "../include/common.glsl"
#include "../include/noise.glsl"

// A reservoir stores one selected sample and its running weight
struct Reservoir {
    uint  lightIndex;    // index into emissive block list
    float targetPdf;     // p-hat: the target PDF value for the selected sample
    float weightSum;     // running sum of weights (W_sum)
    float M;             // number of candidates seen so far
    float W;             // final sample weight = W_sum / (M * targetPdf)
};

Reservoir createReservoir() {
    Reservoir r;
    r.lightIndex = 0xFFFFFFFFu;
    r.targetPdf = 0.0;
    r.weightSum = 0.0;
    r.M = 0.0;
    r.W = 0.0;
    return r;
}

// Update reservoir with a new candidate sample
// Returns true if the new sample was accepted
bool reservoirUpdate(inout Reservoir r, uint lightIdx, float weight,
                     float targetPdf, inout RNG rng) {
    r.weightSum += weight;
    r.M += 1.0;

    // Accept with probability weight / weightSum
    if (rngNext(rng) * r.weightSum < weight) {
        r.lightIndex = lightIdx;
        r.targetPdf = targetPdf;
        return true;
    }
    return false;
}

// Combine two reservoirs (for spatial/temporal reuse)
// Merges reservoir 'other' into 'r'
bool reservoirMerge(inout Reservoir r, Reservoir other, float targetPdfAtR,
                    inout RNG rng) {
    // The weight for merging is: other.M * other.W * targetPdf_at_r
    float weight = other.M * other.W * targetPdfAtR;
    return reservoirUpdate(r, other.lightIndex, weight, targetPdfAtR, rng);
}

// Finalize the reservoir: compute the unbiased weight W
void reservoirFinalize(inout Reservoir r) {
    if (r.targetPdf > 0.0 && r.M > 0.0) {
        r.W = r.weightSum / (r.M * r.targetPdf);
    } else {
        r.W = 0.0;
    }
}

// Packed reservoir for storage in buffers (compact representation)
struct PackedReservoir {
    uint  data0; // lightIndex
    float data1; // targetPdf
    float data2; // weightSum
    float data3; // M
};

PackedReservoir packReservoir(Reservoir r) {
    PackedReservoir p;
    p.data0 = r.lightIndex;
    p.data1 = r.targetPdf;
    p.data2 = r.weightSum;
    p.data3 = r.M;
    return p;
}

Reservoir unpackReservoir(PackedReservoir p) {
    Reservoir r;
    r.lightIndex = p.data0;
    r.targetPdf = p.data1;
    r.weightSum = p.data2;
    r.M = p.data3;
    r.W = (r.targetPdf > 0.0 && r.M > 0.0)
        ? r.weightSum / (r.M * r.targetPdf) : 0.0;
    return r;
}

// Reservoir buffers for temporal reuse
layout(set = 4, binding = 0, std430) buffer ReservoirCurrent {
    PackedReservoir reservoirs[];
} reservoirCurrent;

layout(set = 4, binding = 1, std430) buffer ReservoirPrevious {
    PackedReservoir reservoirs[];
} reservoirPrevious;

// Helper: get linear pixel index
uint pixelIndex(ivec2 pixel, ivec2 screenSize) {
    return uint(pixel.y) * uint(screenSize.x) + uint(pixel.x);
}

#endif // RESERVOIR_GLSL
