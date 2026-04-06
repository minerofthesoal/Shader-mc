#version 120

/*
 * gbuffers_hand.vsh
 * Vertex shader for the first-person hand and held item.
 * Same as entities -- standard transform, lightmap, normal.
 */

// ---------------------------------------------------------------------------
// Uniforms
// ---------------------------------------------------------------------------
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;

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
    lmcoord  = clamp(gl_MultiTexCoord1.st / 256.0, 0.0, 1.0);
    glcolor  = gl_Color;
    normal   = normalize(gl_NormalMatrix * gl_Normal);

    vec4 viewPos4 = gl_ModelViewMatrix * gl_Vertex;
    viewPos = viewPos4.xyz;

    gl_Position = gl_ProjectionMatrix * viewPos4;
}
