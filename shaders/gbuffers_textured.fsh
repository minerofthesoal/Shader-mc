#version 120

/*
 * gbuffers_textured.fsh
 * Fragment shader for simple textured geometry (particles, etc.).
 * Writes to gbuffer MRT. No lightmap sampling -- uses full brightness.
 */

// ---------------------------------------------------------------------------
// Uniforms
// ---------------------------------------------------------------------------
uniform sampler2D texture;

// ---------------------------------------------------------------------------
// Varyings
// ---------------------------------------------------------------------------
varying vec2 texcoord;
varying vec4 glcolor;
varying vec3 viewPos;
varying vec3 normal;

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
void main() {
    vec4 albedo = texture2D(texture, texcoord);
    albedo *= glcolor;

    if (albedo.a < 0.1) discard;

    // MRT 0: colour (no lightmap, pass through as-is)
    gl_FragData[0] = albedo;

    // MRT 1: encoded normal, sky light = 1.0 (full sky exposure for particles)
    vec3 encodedNormal = normal * 0.5 + 0.5;
    gl_FragData[1] = vec4(encodedNormal, 1.0);

    // MRT 2: material flags (default)
    gl_FragData[2] = vec4(0.0, 0.0, 1.0, 1.0);
}
