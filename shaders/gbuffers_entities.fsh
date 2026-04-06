#version 120

/*
 * gbuffers_entities.fsh
 * Fragment shader for entities.
 * Writes to gbuffer MRT in the same layout as terrain.
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
varying vec3 normal;

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
void main() {
    // Sample entity texture
    vec4 albedo = texture2D(texture, texcoord);
    albedo *= glcolor;

    // Alpha test
    if (albedo.a < 0.1) discard;

    // Lightmap
    vec3 lmColor = texture2D(lightmap, lmcoord).rgb;
    vec3 litAlbedo = albedo.rgb * mix(vec3(1.0), lmColor, 0.35);

    // MRT 0: colour
    gl_FragData[0] = vec4(litAlbedo, albedo.a);

    // MRT 1: encoded normal + sky light
    vec3 encodedNormal = normal * 0.5 + 0.5;
    gl_FragData[1] = vec4(encodedNormal, lmcoord.y);

    // MRT 2: material flags (no block ID for entities, default material)
    gl_FragData[2] = vec4(0.0, 0.0, 1.0, lmcoord.x);
}
