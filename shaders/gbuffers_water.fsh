#version 120

/*
 * gbuffers_water.fsh
 * Fragment shader for translucent geometry (water, stained glass, ice).
 * Water gets tinted semi-transparent color with animated caustics and
 * biome-blended coloring. Other translucents pass through.
 * Writes to gbuffer MRT in same layout as terrain.
 */

// ---------------------------------------------------------------------------
// Uniforms
// ---------------------------------------------------------------------------
uniform sampler2D texture;
uniform sampler2D lightmap;
uniform float frameTimeCounter;

// ---------------------------------------------------------------------------
// Varyings
// ---------------------------------------------------------------------------
varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 glcolor;
varying vec3 viewPos;
varying vec3 worldPos;
varying vec3 normal;
varying float blockId;
varying float isWater;

// ---------------------------------------------------------------------------
// Water settings
// ---------------------------------------------------------------------------
const vec3 WATER_TINT    = vec3(0.08, 0.22, 0.38);   // blue tint
const float WATER_ALPHA  = 0.58;                      // translucency

// ---------------------------------------------------------------------------
// Simple animated caustic pattern
// ---------------------------------------------------------------------------
float causticPattern(vec2 pos, float time) {
    float c1 = sin(pos.x * 3.0 + time * 1.2) * sin(pos.y * 3.7 + time * 0.9);
    float c2 = sin(pos.x * 2.3 - time * 0.8 + 1.0) * sin(pos.y * 2.8 + time * 1.1 + 2.0);
    float c3 = sin((pos.x + pos.y) * 4.1 + time * 0.7);
    float caustic = (c1 + c2 + c3 * 0.5) * 0.5 + 0.5;
    caustic = pow(caustic, 2.0);
    return caustic * 0.12;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
void main() {
    // -- Sample texture -------------------------------------------------------
    vec4 albedo = texture2D(texture, texcoord);
    albedo *= glcolor;

    // -- Alpha test (for non-water translucents like glass panes) -------------
    if (albedo.a < 0.1) discard;

    // -- Water-specific colour override ---------------------------------------
    if (isWater > 0.5) {
        // Base water color blended with biome tint
        vec3 waterColor = mix(WATER_TINT, glcolor.rgb * 0.4, 0.25);

        // Add animated caustics on the water surface
        float time = frameTimeCounter;
        float caustic = causticPattern(worldPos.xz, time);
        waterColor += vec3(caustic * 0.6, caustic * 0.8, caustic);

        // Subtle view-angle darkening (deeper looking at steep angles)
        float viewDot = abs(dot(normalize(normal), normalize(-viewPos)));
        float fresnelDarken = mix(0.7, 1.0, viewDot);
        waterColor *= fresnelDarken;

        albedo.rgb = waterColor;
        // Fresnel-based alpha: more opaque at glancing angles
        albedo.a = mix(WATER_ALPHA + 0.15, WATER_ALPHA, viewDot);
    }

    // -- Lightmap -------------------------------------------------------------
    vec3 lmColor = texture2D(lightmap, lmcoord).rgb;
    vec3 litAlbedo = albedo.rgb * mix(vec3(1.0), lmColor, 0.35);

    // -- MRT 0: colour --------------------------------------------------------
    gl_FragData[0] = vec4(litAlbedo, albedo.a);

    // -- MRT 1: encoded normal + sky light ------------------------------------
    vec3 encodedNormal = normal * 0.5 + 0.5;
    gl_FragData[1] = vec4(encodedNormal, lmcoord.y);

    // -- MRT 2: material flags ------------------------------------------------
    float encodedId = blockId / 256.0;
    float specular  = (isWater > 0.5) ? 0.8 : 0.0;
    float roughness = (isWater > 0.5) ? 0.05 : 1.0;

    gl_FragData[2] = vec4(encodedId, specular, roughness, lmcoord.x);
}
