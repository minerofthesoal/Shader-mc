#version 120
// =============================================================================
// final.vsh - Fullscreen quad vertex shader for final output pass
// =============================================================================

varying vec2 texcoord;

void main() {
    gl_Position = ftransform();
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).st;
}
