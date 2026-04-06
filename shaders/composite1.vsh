#version 120
// =============================================================================
// composite1.vsh - Fullscreen quad vertex shader for second composite pass
// =============================================================================

varying vec2 texcoord;

void main() {
    gl_Position = ftransform();
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).st;
}
