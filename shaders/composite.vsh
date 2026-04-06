#version 120
// =============================================================================
// composite.vsh - Fullscreen quad vertex shader for main composite pass
// =============================================================================

varying vec2 texcoord;

void main() {
    gl_Position = ftransform();
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).st;
}
