#version 120

/*
 * gbuffers_water.fsh
 * Fragment shader for translucent geometry (water, stained glass, ice).
 * Water gets a tinted semi-transparent colour; other translucents pass through
 * normally. Writes to gbuffer MRT in the same layout as terrain.
 */

// ---------------------------------------------------------------------------
// Uniforms
// ---------------------------------------------------------------------------
uniform sampler2D texture;
uniform sampler2D lightmap;

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
// Water colour settings
// ---------------------------------------------------------------------------
const vec3 WATER_TINT  = vec3(0.05, 0.15, 0.35); // deep-blue tint
const float WATER_ALPHA = 0.55;                   // translucency

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
        // Replace the flat water texture with a tinted translucent colour
        // Keep vertex colour influence (biome water colour)
        albedo.rgb = mix(WATER_TINT, glcolor.rgb, 0.3);
        albedo.a   = WATER_ALPHA;
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
    // For water: specular = 0.8 (reflective), roughness = 0.05 (smooth)
    float encodedId = blockId / 256.0;
    float specular  = (isWater > 0.5) ? 0.8 : 0.0;
    float roughness = (isWater > 0.5) ? 0.05 : 1.0;

    gl_FragData[2] = vec4(encodedId, specular, roughness, lmcoord.x);
}
