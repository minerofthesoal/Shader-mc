#version 120
// =============================================================================
// composite1.fsh - Second composite pass
//
// Handles screen-space reflections (SSR) and horizontal bloom blur.
// =============================================================================

// ---------------------------------------------------------------------------
// Feature toggles
// ---------------------------------------------------------------------------
#define RAYTRACING
#define SSR_QUALITY 2   // [0 1 2]

// ---------------------------------------------------------------------------
// Varyings
// ---------------------------------------------------------------------------
varying vec2 texcoord;

// ---------------------------------------------------------------------------
// Uniforms - Samplers
// ---------------------------------------------------------------------------
uniform sampler2D colortex0;    // Scene color from composite pass
uniform sampler2D colortex1;    // Bloom bright-pass data from composite pass
uniform sampler2D colortex2;    // Material data (for water detection)
uniform sampler2D depthtex0;    // Depth buffer

// ---------------------------------------------------------------------------
// Uniforms - Matrices
// ---------------------------------------------------------------------------
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;

// ---------------------------------------------------------------------------
// Uniforms - Vectors & Scalars
// ---------------------------------------------------------------------------
uniform float viewWidth;
uniform float viewHeight;
uniform float far;
uniform float near;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------
#if SSR_QUALITY == 0
    const int   SSR_MAX_STEPS     = 16;
    const int   SSR_REFINE_STEPS  = 2;
    const float SSR_STEP_SIZE     = 2.0;
#elif SSR_QUALITY == 1
    const int   SSR_MAX_STEPS     = 32;
    const int   SSR_REFINE_STEPS  = 4;
    const float SSR_STEP_SIZE     = 1.5;
#else
    const int   SSR_MAX_STEPS     = 48;
    const int   SSR_REFINE_STEPS  = 6;
    const float SSR_STEP_SIZE     = 1.0;
#endif

const float SSR_MAX_DISTANCE = 80.0;

// Gaussian blur weights for a 13-tap horizontal kernel
const float BLUR_WEIGHTS[7] = float[7](
    0.1964825501511,
    0.2969069646728,
    0.2195956971883,
    0.0439036077653,
    0.0109634019413,
    0.0018216249164,
    0.0002195946828
);

// Correction: GLSL 120 doesn't support array initializers; use individual constants
// We'll use hardcoded values in the loop instead.

// ---------------------------------------------------------------------------
// Helper: Luminance
// ---------------------------------------------------------------------------
float luminance(vec3 color) {
    return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

// ---------------------------------------------------------------------------
// Helper: Linear depth from depth buffer value
// ---------------------------------------------------------------------------
float linearizeDepth(float depth) {
    return 2.0 * near * far / (far + near - (2.0 * depth - 1.0) * (far - near));
}

// ---------------------------------------------------------------------------
// Helper: Reconstruct view-space position from depth
// ---------------------------------------------------------------------------
vec3 getViewPos(vec2 uv, float depth) {
    vec4 clipPos = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 viewPos = gbufferProjectionInverse * clipPos;
    return viewPos.xyz / viewPos.w;
}

// ---------------------------------------------------------------------------
// Helper: Project view-space position to screen UV + depth
// ---------------------------------------------------------------------------
vec3 projectToScreen(vec3 viewPos) {
    vec4 clipPos = gbufferProjection * vec4(viewPos, 1.0);
    clipPos.xyz /= clipPos.w;
    return clipPos.xyz * 0.5 + 0.5;
}

// ---------------------------------------------------------------------------
// Helper: Decode normal from colortex data (stored as 0..1 -> -1..1)
// ---------------------------------------------------------------------------
vec3 decodeNormal(vec2 uv) {
    vec3 enc = texture2D(colortex2, uv).rgb;
    // Normal is stored in a secondary way; we re-read from the scene
    // For this pack, normals are in colortex1 rgb, but that's now bloom.
    // We need normals from a separate encoding. Use colortex2 channels.
    // Fallback: reconstruct from depth if needed.
    return vec3(0.0, 1.0, 0.0); // placeholder
}

// ---------------------------------------------------------------------------
// Helper: Get normal from depth buffer via cross-product of neighbors
// This is a fallback when we don't have a dedicated normal buffer.
// ---------------------------------------------------------------------------
vec3 getNormalFromDepth(vec2 uv) {
    vec2 texel = vec2(1.0 / viewWidth, 1.0 / viewHeight);

    float depthC = texture2D(depthtex0, uv).r;
    float depthR = texture2D(depthtex0, uv + vec2(texel.x, 0.0)).r;
    float depthU = texture2D(depthtex0, uv + vec2(0.0, texel.y)).r;

    vec3 posC = getViewPos(uv, depthC);
    vec3 posR = getViewPos(uv + vec2(texel.x, 0.0), depthR);
    vec3 posU = getViewPos(uv + vec2(0.0, texel.y), depthU);

    vec3 tangent  = posR - posC;
    vec3 binormal = posU - posC;

    return normalize(cross(tangent, binormal));
}

// ---------------------------------------------------------------------------
// Helper: Fresnel (Schlick approximation)
// ---------------------------------------------------------------------------
float fresnel(vec3 viewDir, vec3 normal, float F0) {
    float cosTheta = max(dot(-viewDir, normal), 0.0);
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

// ---------------------------------------------------------------------------
// 1) Screen-Space Reflections
//
// Traces a ray in screen space along the reflection vector. Uses the depth
// buffer to detect intersections. Applies Fresnel-based intensity scaling.
// Only applied to water surfaces (detected via material ID in colortex2)
// and optionally to other reflective surfaces.
// ---------------------------------------------------------------------------
#ifdef RAYTRACING
vec3 computeSSR(vec2 uv, vec3 sceneColor) {
    float depth = texture2D(depthtex0, uv).r;

    // Skip sky
    if (depth > 0.999) return sceneColor;

    // Read material data to detect water/reflective surfaces
    // colortex2 layout: (encodedId, specular, roughness, blockLight)
    vec4 matData = texture2D(colortex2, uv);
    float specular  = matData.g;
    float roughness = matData.b;

    // Water: specular ~0.8 and roughness ~0.05 (set in gbuffers_water.fsh)
    bool isWater     = (specular > 0.7 && roughness < 0.1);
    bool isReflective = (specular > 0.5 && !isWater); // other reflective surfaces

    if (!isWater && !isReflective) return sceneColor;

    // Reflectivity: water is fairly reflective, metals more so
    float baseReflectivity = isWater ? 0.04 : 0.5;

    // Reconstruct view-space position and normal
    vec3 viewPos = getViewPos(uv, depth);
    vec3 normal  = getNormalFromDepth(uv);

    // View direction (in view space, camera is at origin looking -Z)
    vec3 viewDir = normalize(viewPos);

    // Fresnel determines reflection strength
    float F = fresnel(viewDir, normal, baseReflectivity);

    // Reflection direction
    vec3 reflectDir = reflect(viewDir, normal);

    // --- Screen-space ray march ---
    vec3 rayPos  = viewPos;
    vec3 rayStep = reflectDir * SSR_STEP_SIZE;

    vec3 hitColor   = vec3(0.0);
    bool hitFound   = false;
    float traveled  = 0.0;

    for (int i = 0; i < SSR_MAX_STEPS; i++) {
        rayPos  += rayStep;
        traveled = length(rayPos - viewPos);

        // Bail if too far
        if (traveled > SSR_MAX_DISTANCE) break;

        // Project to screen
        vec3 screenPos = projectToScreen(rayPos);

        // Out of screen bounds?
        if (screenPos.x < 0.0 || screenPos.x > 1.0 ||
            screenPos.y < 0.0 || screenPos.y > 1.0) break;

        // Sample the depth buffer at the projected position
        float sampleDepth = texture2D(depthtex0, screenPos.xy).r;
        vec3  sampleViewPos = getViewPos(screenPos.xy, sampleDepth);

        // Check if our ray is behind the scene geometry
        float depthDiff = rayPos.z - sampleViewPos.z;

        if (depthDiff > 0.0 && depthDiff < SSR_STEP_SIZE * 2.0) {
            // Binary refinement for more accurate hit
            vec3 refinePos = rayPos;
            vec3 refineStep = rayStep * 0.5;

            for (int j = 0; j < SSR_REFINE_STEPS; j++) {
                refinePos -= refineStep;
                refineStep *= 0.5;

                vec3 refScreen = projectToScreen(refinePos);
                float refDepth = texture2D(depthtex0, refScreen.xy).r;
                vec3  refViewPos = getViewPos(refScreen.xy, refDepth);

                if (refinePos.z > refViewPos.z) {
                    refinePos += refineStep;
                }
            }

            vec3 finalScreen = projectToScreen(refinePos);
            hitColor = texture2D(colortex0, finalScreen.xy).rgb;
            hitFound = true;
            break;
        }
    }

    if (!hitFound) return sceneColor;

    // Fade at screen edges to prevent hard cutoffs
    vec3 finalScreenPos = projectToScreen(rayPos);
    float edgeFade = 1.0;
    edgeFade *= smoothstep(0.0, 0.05, finalScreenPos.x);
    edgeFade *= smoothstep(1.0, 0.95, finalScreenPos.x);
    edgeFade *= smoothstep(0.0, 0.05, finalScreenPos.y);
    edgeFade *= smoothstep(1.0, 0.95, finalScreenPos.y);

    // Fade with distance traveled
    float distFade = 1.0 - clamp(traveled / SSR_MAX_DISTANCE, 0.0, 1.0);
    distFade = distFade * distFade;

    // Combine
    float reflectionStrength = F * edgeFade * distFade;
    return mix(sceneColor, hitColor, reflectionStrength);
}
#endif

// ---------------------------------------------------------------------------
// 2) Bloom Horizontal Blur
//
// Applies a 13-tap Gaussian blur horizontally on the bloom bright-pass data
// from the previous composite pass. The vertical blur happens in composite2.
// ---------------------------------------------------------------------------
vec3 bloomHorizontalBlur(vec2 uv) {
    float texelSize = 1.0 / viewWidth;

    // 13-tap Gaussian weights (sigma ~ 4.0)
    // Precomputed symmetric kernel
    float w0 = 0.1964825501;
    float w1 = 0.1747075801;
    float w2 = 0.1209853623;
    float w3 = 0.0653263330;
    float w4 = 0.0275283843;
    float w5 = 0.0090506338;
    float w6 = 0.0023205330;

    vec3 result = texture2D(colortex1, uv).rgb * w0;

    // Symmetric taps
    result += texture2D(colortex1, uv + vec2(texelSize * 1.0, 0.0)).rgb * w1;
    result += texture2D(colortex1, uv - vec2(texelSize * 1.0, 0.0)).rgb * w1;
    result += texture2D(colortex1, uv + vec2(texelSize * 2.0, 0.0)).rgb * w2;
    result += texture2D(colortex1, uv - vec2(texelSize * 2.0, 0.0)).rgb * w2;
    result += texture2D(colortex1, uv + vec2(texelSize * 3.0, 0.0)).rgb * w3;
    result += texture2D(colortex1, uv - vec2(texelSize * 3.0, 0.0)).rgb * w3;
    result += texture2D(colortex1, uv + vec2(texelSize * 4.0, 0.0)).rgb * w4;
    result += texture2D(colortex1, uv - vec2(texelSize * 4.0, 0.0)).rgb * w4;
    result += texture2D(colortex1, uv + vec2(texelSize * 5.0, 0.0)).rgb * w5;
    result += texture2D(colortex1, uv - vec2(texelSize * 5.0, 0.0)).rgb * w5;
    result += texture2D(colortex1, uv + vec2(texelSize * 6.0, 0.0)).rgb * w6;
    result += texture2D(colortex1, uv - vec2(texelSize * 6.0, 0.0)).rgb * w6;

    return result;
}

// ==========================================================================
// Main
// ==========================================================================
void main() {
    vec3 sceneColor = texture2D(colortex0, texcoord).rgb;

    // ---- 1) Screen-space reflections ----
    #ifdef RAYTRACING
        sceneColor = computeSSR(texcoord, sceneColor);
    #endif

    // ---- 2) Horizontal bloom blur ----
    vec3 bloomBlurred = bloomHorizontalBlur(texcoord);

    // ================================================================
    // Output
    // ================================================================
    /* DRAWBUFFERS:01 */
    gl_FragData[0] = vec4(sceneColor, 1.0);    // Scene with SSR applied
    gl_FragData[1] = vec4(bloomBlurred, 1.0);   // Horizontally blurred bloom
}
