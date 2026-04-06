#version 120

varying vec3 viewDir;
varying vec4 starData;

void main() {
    gl_Position = ftransform();

    // View direction for atmosphere calculations
    viewDir = normalize((gl_ModelViewMatrixInverse * gl_ModelViewMatrix * gl_Vertex).xyz);

    // Star data: pass vertex color for star rendering
    // Vanilla Minecraft sends star brightness in vertex color
    starData = gl_Color;
}
