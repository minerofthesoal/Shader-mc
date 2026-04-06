#version 120

varying vec2 texcoord;
varying vec4 shadowColor;

// Shadow distortion for better near-camera resolution
vec2 distortShadowPos(vec2 pos) {
    float distortionFactor = length(pos.xy) + 0.2;
    return pos.xy / distortionFactor;
}

void main() {
    // Transform vertex into shadow clip space
    vec4 position = gl_ProjectionMatrix * gl_ModelViewMatrix * gl_Vertex;

    // Apply shadow distortion on the XY plane (normalized device coords)
    position.xy = distortShadowPos(position.xy);

    gl_Position = position;

    // Pass texcoord for alpha testing in fragment shader
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;

    // Pass vertex color for colored shadow support
    shadowColor = gl_Color;
}
