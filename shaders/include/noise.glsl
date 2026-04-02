#ifndef NOISE_GLSL
#define NOISE_GLSL

// ============================================================================
// noise.glsl — Hash functions, blue noise, and random number generation
// ============================================================================

// PCG hash — fast, high-quality integer hash
uint pcgHash(uint v) {
    uint state = v * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}

// Hash a 2D coordinate + frame for per-pixel temporal variation
uint hashPixel(uvec2 pixel, uint frame) {
    uint h = pcgHash(pixel.x);
    h = pcgHash(h ^ pixel.y);
    h = pcgHash(h ^ frame);
    return h;
}

// Convert uint hash to float in [0, 1)
float hashToFloat(uint h) {
    return float(h) * (1.0 / 4294967296.0);
}

// Generate a 2D random sample from a pixel hash state
// Uses nested PCG to produce decorrelated dimensions
struct RNG {
    uint state;
};

RNG rngInit(uvec2 pixel, uint frame) {
    RNG rng;
    rng.state = hashPixel(pixel, frame);
    return rng;
}

float rngNext(inout RNG rng) {
    rng.state = pcgHash(rng.state);
    return hashToFloat(rng.state);
}

vec2 rngNext2D(inout RNG rng) {
    return vec2(rngNext(rng), rngNext(rng));
}

vec3 rngNext3D(inout RNG rng) {
    return vec3(rngNext(rng), rngNext(rng), rngNext(rng));
}

// Cosine-weighted hemisphere sampling (returns direction in tangent space)
vec3 sampleCosineHemisphere(vec2 u) {
    float r = sqrt(u.x);
    float phi = TWO_PI * u.y;
    float x = r * cos(phi);
    float y = r * sin(phi);
    float z = sqrt(max(0.0, 1.0 - u.x));
    return vec3(x, y, z);
}

// PDF for cosine-weighted hemisphere: cos(theta) / PI
float pdfCosineHemisphere(float cosTheta) {
    return max(cosTheta, 0.0) * INV_PI;
}

// Uniform sphere sampling
vec3 sampleUniformSphere(vec2 u) {
    float z = 1.0 - 2.0 * u.x;
    float r = sqrt(max(0.0, 1.0 - z * z));
    float phi = TWO_PI * u.y;
    return vec3(r * cos(phi), r * sin(phi), z);
}

// Uniform hemisphere sampling
vec3 sampleUniformHemisphere(vec2 u) {
    float z = u.x;
    float r = sqrt(max(0.0, 1.0 - z * z));
    float phi = TWO_PI * u.y;
    return vec3(r * cos(phi), r * sin(phi), z);
}

// Roberts R2 quasi-random sequence (low-discrepancy 2D)
vec2 r2Sequence(uint index) {
    const float g = 1.32471795724474602596;
    const float a1 = 1.0 / g;
    const float a2 = 1.0 / (g * g);
    return fract(vec2(0.5 + float(index) * a1,
                      0.5 + float(index) * a2));
}

// Spatial hash for 3D positions (used by SHaRC and voxel lookups)
uint spatialHash(ivec3 pos) {
    uint h = uint(pos.x) * 73856093u;
    h ^= uint(pos.y) * 19349663u;
    h ^= uint(pos.z) * 83492791u;
    return h;
}

#endif // NOISE_GLSL
