#version 120
// =============================================================================
// composite2.vsh - Fullscreen quad vertex shader for third composite pass
// =============================================================================

varying vec2 texcoord;

void main() {
    gl_Position = ftransform();
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).st;
}
