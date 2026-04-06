#version 120
// =============================================================================
// composite.fsh - Main composite pass
//
// Handles shadow mapping, dynamic lighting, god rays, volumetric fog,
// subsurface scattering, true darkness, and bloom extraction.
// =============================================================================

// ---------------------------------------------------------------------------
// Feature toggles
// ---------------------------------------------------------------------------
#define SHADOWS
#define DYNAMIC_LIGHTS
#define GODRAYS
#define GODRAY_STRENGTH 0.4    // [0.1 0.2 0.3 0.4 0.5 0.6 0.8 1.0]
#define SHADOW_QUALITY 2       // [0 1 2]
#define TRUE_DARK
#define VOLUMETRIC_FOG
#define SUBSURFACE_SCATTERING
#define BLOOM
#define BLOOM_AMOUNT 0.15      // [0.1 0.15 0.2 0.25 0.3 0.4 0.5]

// ---------------------------------------------------------------------------
// Varyings
// ---------------------------------------------------------------------------
varying vec2 texcoord;

// ---------------------------------------------------------------------------
// Uniforms - Samplers
// ---------------------------------------------------------------------------
uniform sampler2D colortex0;    // Scene color from gbuffers
uniform sampler2D colortex1;    // Normals (rgb) + lightmap (a) encoded
uniform sampler2D colortex2;    // Material / specular data
uniform sampler2D depthtex0;    // Depth buffer
uniform sampler2D shadowtex0;   // Shadow depth - opaque only
uniform sampler2D shadowtex1;   // Shadow depth - all geometry
uniform sampler2D shadowcolor0; // Shadow color (for translucent colored shadows)
uniform sampler2D noisetex;     // Blue / white noise texture

// ---------------------------------------------------------------------------
// Uniforms - Matrices
// ---------------------------------------------------------------------------
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowProjection;
uniform mat4 shadowModelView;

// ---------------------------------------------------------------------------
// Uniforms - Vectors & Scalars
// ---------------------------------------------------------------------------
uniform vec3 sunPosition;
uniform vec3 shadowLightPosition;
uniform float viewWidth;
uniform float viewHeight;
uniform float frameTimeCounter;
uniform int worldTime;
uniform float rainStrength;
uniform vec3 cameraPosition;
uniform float far;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------
const float SHADOW_MAP_BIAS  = 0.0005;
const float SHADOW_DISTORT_K = 0.20;
const int   SHADOW_SAMPLES   = 2;          // radius in texels for PCF
const float SHADOW_SOFTNESS  = 1.0 / 2048.0; // 1 / shadow map resolution

const int   GODRAY_SAMPLES   = 16;
const float GODRAY_DECAY     = 0.96;
const float GODRAY_DENSITY   = 1.0;

const float BLOOM_THRESHOLD  = 0.75;

const float SSS_STRENGTH     = 0.45;

// ---------------------------------------------------------------------------
// Helper: Luminance
// ---------------------------------------------------------------------------
float luminance(vec3 color) {
    return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

// ---------------------------------------------------------------------------
// Helper: Decode normal from colortex1 (stored as 0..1 -> -1..1)
// ---------------------------------------------------------------------------
vec3 decodeNormal(vec3 enc) {
    return enc * 2.0 - 1.0;
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
// Helper: View-space position to world-space position
// ---------------------------------------------------------------------------
vec3 viewToWorld(vec3 viewPos) {
    vec4 worldPos = gbufferModelViewInverse * vec4(viewPos, 1.0);
    return worldPos.xyz;
}

// ---------------------------------------------------------------------------
// Shadow distortion - matches the shadow vertex shader distortion
// Keeps center of the shadow map high-resolution, stretches edges.
// ---------------------------------------------------------------------------
vec2 distortShadowCoord(vec2 coord) {
    float distortFactor = length(coord) + SHADOW_DISTORT_K;
    return coord / distortFactor;
}

// ---------------------------------------------------------------------------
// 1) Shadow Mapping
//
// Transforms the fragment into shadow clip space, applies distortion that
// matches the shadow pass vertex shader, then performs Percentage Closer
// Filtering (PCF) over a 3x3 or 5x5 kernel depending on SHADOW_QUALITY.
// Also reads shadowcolor0 for colored translucent shadows (stained glass).
// ---------------------------------------------------------------------------
#ifdef SHADOWS
vec3 computeShadow(vec3 viewPos, float NdotL) {
    // ---- Transform to shadow clip space ----
    vec3 worldPos = viewToWorld(viewPos);
    vec4 shadowViewPos  = shadowModelView * vec4(worldPos, 1.0);
    vec4 shadowClipPos  = shadowProjection * shadowViewPos;
    shadowClipPos.xyz  /= shadowClipPos.w;

    // Apply distortion
    shadowClipPos.xy = distortShadowCoord(shadowClipPos.xy);

    // Map from [-1,1] to [0,1] for texture lookup
    vec3 shadowCoord = shadowClipPos.xyz * 0.5 + 0.5;

    // Early out if outside shadow map bounds
    if (shadowCoord.x < 0.0 || shadowCoord.x > 1.0 ||
        shadowCoord.y < 0.0 || shadowCoord.y > 1.0 ||
        shadowCoord.z < 0.0 || shadowCoord.z > 1.0) {
        return vec3(1.0);
    }

    // ---- Adaptive bias based on surface angle to light ----
    float cosTheta = clamp(NdotL, 0.0, 1.0);
    float bias = SHADOW_MAP_BIAS * tan(acos(cosTheta));
    bias = clamp(bias, 0.0, 0.005);

    // ---- PCF kernel ----
    // SHADOW_QUALITY 0 = hard shadow (1 sample)
    // SHADOW_QUALITY 1 = 3x3 PCF
    // SHADOW_QUALITY 2 = 5x5 PCF
    #if SHADOW_QUALITY == 0
        int pcfRadius = 0;
    #elif SHADOW_QUALITY == 1
        int pcfRadius = 1;
    #else
        int pcfRadius = 2;
    #endif

    float shadowAccum  = 0.0;
    vec3  colorAccum   = vec3(0.0);
    float totalSamples = 0.0;

    for (int x = -pcfRadius; x <= pcfRadius; x++) {
        for (int y = -pcfRadius; y <= pcfRadius; y++) {
            vec2 offset = vec2(float(x), float(y)) * SHADOW_SOFTNESS;
            vec2 sampleCoord = shadowCoord.xy + offset;

            // Opaque shadow depth
            float shadowDepthOpaque = texture2D(shadowtex0, sampleCoord).r;
            // Full shadow depth (including translucent)
            float shadowDepthAll    = texture2D(shadowtex1, sampleCoord).r;

            // Check if the fragment is in shadow from opaque geometry
            float inShadowOpaque = step(shadowCoord.z - bias, shadowDepthOpaque);

            // Check colored / translucent shadow
            float inShadowAll = step(shadowCoord.z - bias, shadowDepthAll);

            // If opaque blocks light completely, shadow = 0
            // If translucent blocks light, tint with shadowcolor0
            if (inShadowOpaque < 0.5 && inShadowAll > 0.5) {
                // Translucent shadow - sample color
                vec4 sColor = texture2D(shadowcolor0, sampleCoord);
                colorAccum += sColor.rgb * sColor.a;
                shadowAccum += 1.0;
            } else {
                shadowAccum += inShadowOpaque;
                colorAccum  += vec3(inShadowOpaque);
            }

            totalSamples += 1.0;
        }
    }

    shadowAccum /= totalSamples;
    colorAccum  /= totalSamples;

    // Blend between white (fully lit) and the colored shadow result
    vec3 shadowColor = mix(vec3(shadowAccum), colorAccum, 1.0 - shadowAccum);
    return clamp(shadowColor, 0.0, 1.0);
}
#endif

// ---------------------------------------------------------------------------
// 2) Dynamic Lighting
//
// Uses the block light channel from the lightmap (stored in colortex1.a or
// similar encoding). Higher block light produces warmer torch-like color
// with a smooth inverse-square-ish falloff.
// ---------------------------------------------------------------------------
#ifdef DYNAMIC_LIGHTS
vec3 computeDynamicLight(float blockLight) {
    // Smooth the lightmap value for a nicer falloff
    float light = pow(blockLight, 2.5);

    // Warm torch color palette: orange-yellow at full brightness
    vec3 torchColor = vec3(1.0, 0.65, 0.30);

    // Mix toward a slightly cooler tone at lower intensities
    vec3 dimTorch = vec3(0.85, 0.50, 0.20);
    vec3 finalTorch = mix(dimTorch, torchColor, light);

    return finalTorch * light * 1.2;
}
#endif

// ---------------------------------------------------------------------------
// 3) God Rays (Volumetric Light Scattering)
//
// Projects the sun position to screen space, then marches from the current
// fragment toward the sun in UV space, accumulating scene brightness along
// the ray.  Decays exponentially so samples closer to the sun contribute
// more.  Only active during the day and when the sun is above the horizon.
// ---------------------------------------------------------------------------
#ifdef GODRAYS
vec3 computeGodRays(vec2 uv, vec3 sceneColor) {
    // Day time check: worldTime 0-12000 is day
    float dayFactor = 1.0;
    if (worldTime > 12000) {
        // Night - scale down to moonrays (much weaker)
        dayFactor = 0.15;
    }

    // Project sun to screen space (NDC)
    vec4 sunScreen = gl_ProjectionMatrix * vec4(normalize(sunPosition), 1.0);
    // Perspective divide, but sunPosition is already in view space direction
    // We use a simpler projection for the directional light
    vec2 sunUV = (sunPosition.xy / -sunPosition.z) * 0.5 + 0.5;

    // If sun is behind the camera, skip
    if (sunPosition.z > 0.0) {
        return vec3(0.0);
    }

    // Direction from fragment toward sun in screen space
    vec2 deltaUV = (sunUV - uv);
    float rayLength = length(deltaUV);
    deltaUV = deltaUV / float(GODRAY_SAMPLES) * GODRAY_DENSITY;

    // March along the ray
    vec2 sampleUV = uv;
    float illumination = 0.0;
    float decay = 1.0;

    for (int i = 0; i < GODRAY_SAMPLES; i++) {
        sampleUV += deltaUV;

        // Clamp to screen bounds
        vec2 clamped = clamp(sampleUV, 0.001, 0.999);

        // Sample scene brightness at this point
        vec3 sampleColor = texture2D(colortex0, clamped).rgb;
        float sampleLum  = luminance(sampleColor);

        // Check depth - sky pixels (depth ~1.0) contribute more
        float sampleDepth = texture2D(depthtex0, clamped).r;
        float isSky = step(0.999, sampleDepth);

        illumination += sampleLum * isSky * decay;
        decay *= GODRAY_DECAY;
    }

    illumination /= float(GODRAY_SAMPLES);

    // Sun color tint (warm golden during day)
    vec3 rayColor = mix(vec3(0.8, 0.85, 1.0), vec3(1.0, 0.9, 0.7), dayFactor);

    // Reduce in rain
    float rainFade = 1.0 - rainStrength * 0.7;

    return rayColor * illumination * GODRAY_STRENGTH * dayFactor * rainFade;
}
#endif

// ---------------------------------------------------------------------------
// 4) True Dark Mode
//
// When both sky light and block light are very low, crush the ambient to
// near-zero.  This makes unlit caves genuinely dark instead of the default
// Minecraft grey-ambient look.
// ---------------------------------------------------------------------------
#ifdef TRUE_DARK
vec3 applyTrueDark(vec3 color, float skyLight, float blockLight) {
    // Determine how "lit" this fragment is
    float totalLight = max(skyLight, blockLight);

    // Smoothly ramp darkness when light is below threshold
    float darkFactor = smoothstep(0.0, 0.15, totalLight);

    // Crush towards near-black in truly unlit areas
    vec3 darkColor = color * 0.015;

    return mix(darkColor, color, darkFactor);
}
#endif

// ---------------------------------------------------------------------------
// 5) Volumetric Fog
//
// Height-based distance fog that is denser below Y=64 and thins at higher
// altitudes.  Uses animated noise sampling for an organic, swirling look.
// Fog color shifts with time of day (warm at sunset, cool at night).
// ---------------------------------------------------------------------------
#ifdef VOLUMETRIC_FOG
vec3 computeVolumetricFog(vec3 color, vec3 worldPos, float depth) {
    // Skip sky pixels
    if (depth > 0.999) return color;

    // World-space Y coordinate (absolute)
    float worldY = worldPos.y + cameraPosition.y;

    // Distance from the camera
    float dist = length(worldPos);

    // Height-based density: thick below Y=64, thin above
    float heightFactor = 1.0 - smoothstep(40.0, 120.0, worldY);
    heightFactor = max(heightFactor, 0.05); // minimum fog everywhere

    // Distance-based density with exponential falloff
    float fogDensity = 1.0 - exp(-dist * 0.003 * heightFactor);
    fogDensity = clamp(fogDensity, 0.0, 0.85);

    // Animated noise for organic movement
    vec2 noiseUV = worldPos.xz * 0.002 + vec2(frameTimeCounter * 0.01);
    float noise = texture2D(noisetex, fract(noiseUV)).r;
    noise = noise * 0.3 + 0.7; // subtle variation
    fogDensity *= noise;

    // Increase fog in rain
    fogDensity = mix(fogDensity, min(fogDensity * 2.0, 0.9), rainStrength);

    // Fog color based on time of day
    vec3 dayFogColor   = vec3(0.70, 0.80, 0.95);
    vec3 nightFogColor = vec3(0.04, 0.05, 0.08);
    vec3 duskFogColor  = vec3(0.90, 0.60, 0.40);

    // Time interpolation
    float dayAmount  = 0.0;
    float duskAmount = 0.0;

    if (worldTime < 11000) {
        dayAmount = 1.0;
    } else if (worldTime < 13000) {
        // Sunset transition
        float t = float(worldTime - 11000) / 2000.0;
        dayAmount  = 1.0 - t;
        duskAmount = sin(t * 3.14159);
    } else if (worldTime < 23000) {
        dayAmount = 0.0;
    } else {
        // Sunrise transition
        float t = float(worldTime - 23000) / 1000.0;
        dayAmount  = t;
        duskAmount = sin(t * 3.14159);
    }

    vec3 fogColor = mix(nightFogColor, dayFogColor, dayAmount);
    fogColor = mix(fogColor, duskFogColor, duskAmount * 0.6);

    // Rain makes fog grey
    fogColor = mix(fogColor, vec3(0.5, 0.52, 0.55), rainStrength * 0.6);

    return mix(color, fogColor, fogDensity);
}
#endif

// ---------------------------------------------------------------------------
// 6) Subsurface Scattering
//
// Approximates light transmission through thin vegetation. When the sun is
// behind foliage, light bleeds through with a warm green/yellow tint.
// Material ID in colortex2 is used to identify plants / leaves.
// ---------------------------------------------------------------------------
#ifdef SUBSURFACE_SCATTERING
vec3 computeSSS(vec3 color, vec3 normal, vec3 viewPos, float materialID) {
    // Detect vegetation blocks by encoded ID (blockId / 256.0)
    // Leaves: 18(0.070), 161(0.629); Grass: 31(0.121), 175(0.684)
    // Flowers: 37(0.145), 38(0.148); Vines: 106(0.414); Crops: 59(0.230)
    float id256 = materialID * 256.0; // recover approximate block ID
    bool isVegetation = (id256 > 17.5 && id256 < 18.5)   // leaves
                     || (id256 > 160.5 && id256 < 161.5)  // leaves2
                     || (id256 > 30.5 && id256 < 31.5)    // tallgrass
                     || (id256 > 174.5 && id256 < 175.5)  // double_plant
                     || (id256 > 36.5 && id256 < 38.5)    // flowers
                     || (id256 > 105.5 && id256 < 106.5)  // vines
                     || (id256 > 58.5 && id256 < 59.5);   // wheat

    if (!isVegetation) return color;

    // View direction
    vec3 viewDir = normalize(-viewPos);

    // Light direction in view space
    vec3 lightDir = normalize(shadowLightPosition);

    // Wrap-around diffuse for translucency
    // Negative NdotL means light is behind the surface
    float NdotL = dot(normal, lightDir);
    float backlit = max(-NdotL, 0.0);

    // Forward scattering lobe
    float VdotL = max(dot(viewDir, -lightDir), 0.0);
    float scatter = pow(VdotL, 4.0) * backlit;

    // Subsurface color: warm green-yellow for leaves
    vec3 sssColor = vec3(0.5, 0.7, 0.2);

    // Modulate by day/night
    float dayStrength = 1.0;
    if (worldTime > 12500 && worldTime < 23000) {
        dayStrength = 0.1; // minimal at night
    }

    // Rain reduces scattering (overcast)
    dayStrength *= 1.0 - rainStrength * 0.8;

    return color + sssColor * scatter * SSS_STRENGTH * dayStrength;
}
#endif

// ---------------------------------------------------------------------------
// 7) Bloom Extraction
//
// Extracts the high-luminance portions of the scene that will be blurred
// and added back in subsequent passes.  Uses a soft knee so the transition
// from non-blooming to blooming is smooth.
// ---------------------------------------------------------------------------
#ifdef BLOOM
vec3 extractBloom(vec3 color) {
    float lum = luminance(color);

    // Soft knee: ramp from threshold to threshold + knee width
    float knee = 0.15;
    float softLum = lum - BLOOM_THRESHOLD + knee;
    softLum = clamp(softLum / (2.0 * knee), 0.0, 1.0);
    softLum = softLum * softLum;

    float contribution = max(lum - BLOOM_THRESHOLD, 0.0);
    contribution = max(contribution, softLum * knee);

    // Scale the original color by the bloom contribution
    vec3 bloom = color * (contribution / max(lum, 0.001));

    return bloom * BLOOM_AMOUNT;
}
#endif

// ==========================================================================
// Main
// ==========================================================================
void main() {
    // ---- Sample G-buffer data ----
    vec3  sceneColor = texture2D(colortex0, texcoord).rgb;
    vec4  normalData = texture2D(colortex1, texcoord);
    vec4  matData    = texture2D(colortex2, texcoord);
    float depth      = texture2D(depthtex0, texcoord).r;

    // Decode normal
    vec3 normal = decodeNormal(normalData.rgb);

    // Lightmap channels - must match gbuffers_terrain.fsh MRT layout:
    //   colortex1 = (encodedNormal.rgb, lmcoord.y)  -> skyLight in alpha
    //   colortex2 = (encodedId, specular, roughness, lmcoord.x) -> blockLight in alpha
    float blockLight = matData.a;       // lmcoord.x from colortex2.a
    float skyLight   = normalData.a;    // lmcoord.y from colortex1.a
    float materialID = matData.r;       // encodedId from colortex2.r

    // Reconstruct positions
    vec3 viewPos  = getViewPos(texcoord, depth);
    vec3 worldPos = viewToWorld(viewPos);

    // Light direction
    vec3 lightDir = normalize(shadowLightPosition);
    float NdotL   = dot(normalize(normal), lightDir);

    // ---- Is this a sky pixel? ----
    bool isSky = (depth > 0.999);

    // ================================================================
    // Apply effects to non-sky fragments
    // ================================================================
    vec3 finalColor = sceneColor;

    if (!isSky) {
        // ---- 1) Shadow mapping ----
        vec3 shadowFactor = vec3(1.0);
        #ifdef SHADOWS
            shadowFactor = computeShadow(viewPos, NdotL);

            // Apply shadow to scene color
            // Use skyLight to determine how much shadow matters
            // (underground areas without sky access don't receive sun shadows)
            float shadowInfluence = smoothstep(0.0, 0.3, skyLight);
            vec3 shadowed = finalColor * mix(vec3(1.0), shadowFactor, shadowInfluence);

            // Ambient fill so shadows aren't fully black
            vec3 ambientColor = finalColor * 0.08;
            finalColor = max(shadowed, ambientColor * shadowInfluence);
        #endif

        // ---- 2) Dynamic lighting (torch / block light) ----
        #ifdef DYNAMIC_LIGHTS
            vec3 dynamicLight = computeDynamicLight(blockLight);
            finalColor += sceneColor * dynamicLight;
        #endif

        // ---- 4) True darkness ----
        #ifdef TRUE_DARK
            finalColor = applyTrueDark(finalColor, skyLight, blockLight);
        #endif

        // ---- 6) Subsurface scattering ----
        #ifdef SUBSURFACE_SCATTERING
            finalColor = computeSSS(finalColor, normal, viewPos, materialID);
        #endif

        // ---- 5) Volumetric fog ----
        #ifdef VOLUMETRIC_FOG
            finalColor = computeVolumetricFog(finalColor, worldPos, depth);
        #endif
    }

    // ---- 3) God rays (applied to both sky and terrain) ----
    #ifdef GODRAYS
        vec3 rays = computeGodRays(texcoord, sceneColor);
        finalColor += rays;
    #endif

    // ================================================================
    // Bloom extraction
    // ================================================================
    vec3 bloomData = vec3(0.0);
    #ifdef BLOOM
        bloomData = extractBloom(finalColor);
    #endif

    // ================================================================
    // Output
    // ================================================================
    /* DRAWBUFFERS:01 */
    gl_FragData[0] = vec4(finalColor, 1.0);  // Lit, shadowed, post-processed scene
    gl_FragData[1] = vec4(bloomData, 1.0);   // Bloom bright-pass for next pass
}
