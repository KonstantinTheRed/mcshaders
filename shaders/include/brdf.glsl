#ifndef BRDF_GLSL
#define BRDF_GLSL

// ============================================================================
// brdf.glsl — PBR material evaluation (Cook-Torrance GGX)
// ============================================================================

#include "common.glsl"

// GGX/Trowbridge-Reitz normal distribution function
float D_GGX(float NdotH, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;
    float denom = NdotH * NdotH * (a2 - 1.0) + 1.0;
    return a2 / (PI * denom * denom);
}

// Smith's geometry function (GGX-correlated)
float G_SmithGGX(float NdotV, float NdotL, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;
    float ggxV = NdotL * sqrt(NdotV * NdotV * (1.0 - a2) + a2);
    float ggxL = NdotV * sqrt(NdotL * NdotL * (1.0 - a2) + a2);
    float denom = ggxV + ggxL;
    return denom > 0.0 ? 0.5 / denom : 0.0;
}

// Schlick's Fresnel approximation
vec3 F_Schlick(float cosTheta, vec3 F0) {
    float t = 1.0 - cosTheta;
    float t2 = t * t;
    return F0 + (1.0 - F0) * (t2 * t2 * t);
}

// Full Cook-Torrance specular BRDF evaluation
vec3 evalSpecularBRDF(vec3 N, vec3 V, vec3 L, float roughness, vec3 F0) {
    vec3 H = safeNormalize(V + L);
    float NdotH = max(dot(N, H), 0.0);
    float NdotV = max(dot(N, V), EPSILON);
    float NdotL = max(dot(N, L), 0.0);
    float VdotH = max(dot(V, H), 0.0);

    float D = D_GGX(NdotH, roughness);
    float G = G_SmithGGX(NdotV, NdotL, roughness);
    vec3  F = F_Schlick(VdotH, F0);

    return D * G * F;
}

// Lambertian diffuse BRDF
vec3 evalDiffuseBRDF(vec3 albedo) {
    return albedo * INV_PI;
}

// Combined PBR evaluation: diffuse + specular
vec3 evalPBR(vec3 N, vec3 V, vec3 L, vec3 albedo, float roughness, float metallic) {
    vec3 F0 = mix(vec3(0.04), albedo, metallic);
    float NdotL = max(dot(N, L), 0.0);

    vec3 specular = evalSpecularBRDF(N, V, L, roughness, F0);
    vec3 F = F_Schlick(max(dot(safeNormalize(V + L), V), 0.0), F0);

    // Energy conservation: diffuse is reduced by what specular reflects
    vec3 kD = (1.0 - F) * (1.0 - metallic);
    vec3 diffuse = evalDiffuseBRDF(albedo);

    return (kD * diffuse + specular) * NdotL;
}

// GGX importance sampling — sample a microfacet normal
vec3 sampleGGX(vec2 u, float roughness) {
    float a = roughness * roughness;
    float cosTheta = sqrt((1.0 - u.x) / (1.0 + (a * a - 1.0) * u.x));
    float sinTheta = sqrt(max(0.0, 1.0 - cosTheta * cosTheta));
    float phi = TWO_PI * u.y;
    return vec3(sinTheta * cos(phi), sinTheta * sin(phi), cosTheta);
}

// PDF for GGX importance sampling
float pdfGGX(float NdotH, float VdotH, float roughness) {
    return D_GGX(NdotH, roughness) * NdotH / (4.0 * VdotH);
}

// Minecraft-specific: F0 for common block materials
vec3 getBlockF0(uint materialCategory) {
    switch (materialCategory) {
        case MAT_WATER:  return vec3(0.02);
        case MAT_GLASS:  return vec3(0.04);
        case MAT_METAL:  return vec3(0.7, 0.7, 0.7); // iron-like default
        default:         return vec3(0.04);            // dielectric default
    }
}

// Minecraft-specific: roughness for common block materials
float getBlockRoughness(uint materialCategory) {
    switch (materialCategory) {
        case MAT_WATER:  return 0.05;
        case MAT_GLASS:  return 0.02;
        case MAT_METAL:  return 0.3;
        case MAT_LEAVES: return 0.9;
        default:         return 0.8; // rough stone/dirt/wood
    }
}

#endif // BRDF_GLSL
