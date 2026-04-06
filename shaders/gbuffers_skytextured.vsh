#version 120

varying vec2 texcoord;
varying vec4 color;
varying vec3 viewDir;

void main() {
    gl_Position = ftransform();

    // Pass through texture coordinates and vertex color
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    color = gl_Color;

    // View direction for glow effects
    viewDir = normalize((gl_ModelViewMatrixInverse * gl_ModelViewMatrix * gl_Vertex).xyz);
}
