#version 120

/*
 * gbuffers_entities.vsh
 * Vertex shader for entities (mobs, items on ground, etc.).
 * Standard transform with lightmap and normal passthrough.
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
    // Texture coordinates
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).st;

    // Lightmap (OptiFine convention: MultiTexCoord1 in 0-255 range)
    lmcoord = clamp(gl_MultiTexCoord1.st / 256.0, 0.0, 1.0);

    // Vertex colour (entity tint, hurt flash, etc.)
    glcolor = gl_Color;

    // View-space normal
    normal = normalize(gl_NormalMatrix * gl_Normal);

    // View-space position
    vec4 viewPos4 = gl_ModelViewMatrix * gl_Vertex;
    viewPos = viewPos4.xyz;

    // Clip-space position
    gl_Position = gl_ProjectionMatrix * viewPos4;
}
