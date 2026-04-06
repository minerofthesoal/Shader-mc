#version 120

/*
 * gbuffers_textured_lit.vsh
 * Vertex shader for lit textured geometry (lit particles, etc.).
 * Same as gbuffers_textured but includes lightmap coordinates.
 */

// ---------------------------------------------------------------------------
// Varyings -> fragment
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
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).st;
    lmcoord  = clamp((gl_TextureMatrix[1] * gl_MultiTexCoord1).st, 0.0, 1.0);
    glcolor  = gl_Color;
    normal   = normalize(gl_NormalMatrix * gl_Normal);

    vec4 viewPos4 = gl_ModelViewMatrix * gl_Vertex;
    viewPos = viewPos4.xyz;

    gl_Position = gl_ProjectionMatrix * viewPos4;
}
