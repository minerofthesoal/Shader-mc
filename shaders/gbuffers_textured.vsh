#version 120

/*
 * gbuffers_textured.vsh
 * Vertex shader for simple textured geometry (particles, etc.).
 * No lightmap -- unlit textured quads.
 */

// ---------------------------------------------------------------------------
// Varyings -> fragment
// ---------------------------------------------------------------------------
varying vec2 texcoord;
varying vec4 glcolor;
varying vec3 viewPos;
varying vec3 normal;

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
void main() {
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).st;
    glcolor  = gl_Color;
    normal   = normalize(gl_NormalMatrix * gl_Normal);

    vec4 viewPos4 = gl_ModelViewMatrix * gl_Vertex;
    viewPos = viewPos4.xyz;

    gl_Position = gl_ProjectionMatrix * viewPos4;
}
